'use strict';
// Plugin system. Plugins are JavaScript run inside a QuickJS WebAssembly
// sandbox: no filesystem, no processes, no network except through the host
// API, and every host capability must be declared in plugin.json and granted
// by the user. CPU time and memory are capped per call.
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { HttpError } = require('../http');
const { now, jsonParse, fetchWithTimeout } = require('../util');

const PERMS = {
  storage: 'Store its own small settings/data inside VIPER.',
  notify: 'Show VIPER notifications.',
  'system.read': 'Read CPU, memory and disk usage.',
  ai: 'Ask the local AI model questions (runs on this PC).',
};
const httpPermInfo = (host) => `Send HTTPS requests to ${host}.`;

let quickjsPromise = null;
function quickjs() { if (!quickjsPromise) quickjsPromise = require('quickjs-emscripten').getQuickJS(); return quickjsPromise; }

function validateManifest(m) {
  if (!m || typeof m !== 'object') throw new Error('plugin.json is missing or invalid');
  if (!/^[a-z0-9][a-z0-9._-]{2,63}$/.test(m.id || '')) throw new Error('Plugin id must be 3-64 lowercase letters, numbers, dots, dashes');
  if (!m.name || !m.version) throw new Error('Plugin name and version are required');
  for (const p of m.permissions || []) if (!PERMS[p] && !/^http:[a-z0-9.-]+\.[a-z]{2,}$/i.test(p)) throw new Error(`Unknown permission "${p}"`);
  const c = m.contributes || {};
  for (const t of c.tools || []) if (!/^[a-z][a-z0-9_]{2,40}$/.test(t.name || '')) throw new Error(`Invalid tool name ${t.name}`);
  return { ...m, main: m.main || 'main.js', permissions: m.permissions || [], contributes: c };
}

class Sandbox {
  constructor(plugin, host) { this.plugin = plugin; this.host = host; this.ctx = null; }
  async init() {
    const QuickJS = await quickjs();
    const rt = QuickJS.newRuntime();
    rt.setMemoryLimit(32 * 1024 * 1024);
    rt.setMaxStackSize(1024 * 1024);
    this.rt = rt;
    this.deadline = 0;
    rt.setInterruptHandler(() => this.deadline > 0 && Date.now() > this.deadline);
    const vm = rt.newContext();
    this.ctx = vm;
    const viper = vm.newObject();
    const def = (name, fn) => { const f = vm.newFunction(name, fn); vm.setProp(viper, name, f); f.dispose(); };
    const asyncHost = (name, impl) => def(name, (...args) => {
      const jsArgs = args.map((a) => vm.dump(a));
      const d = vm.newPromise();
      Promise.resolve().then(() => impl(...jsArgs)).then((v) => { const h = vm.newString(JSON.stringify(v ?? null)); d.resolve(h); h.dispose(); }, (e) => { const h = vm.newError(e.message); d.reject(h); h.dispose(); }).finally(() => rt.executePendingJobs());
      return d.handle;
    });
    def('log', (m) => { this.host.log.info(`[plugin ${this.plugin.id}]`, vm.dump(m)); });
    asyncHost('http', (url, opts) => this.host.http(this.plugin, url, opts || {}));
    asyncHost('storageGet', (k) => this.host.storageGet(this.plugin, k));
    asyncHost('storageSet', (k, v) => this.host.storageSet(this.plugin, k, v));
    asyncHost('notify', (t, b) => this.host.notify(this.plugin, t, b));
    asyncHost('system', () => this.host.system(this.plugin));
    asyncHost('ask', (p) => this.host.ask(this.plugin, p));
    vm.setProp(vm.global, '__viper', viper);
    viper.dispose();
    // Friendly wrapper: host functions return JSON strings.
    const boot = vm.evalCode(`
      const viper = {
        log: (...a) => __viper.log(a.map(String).join(' ')),
        http: async (u, o) => JSON.parse(await __viper.http(u, o)),
        storage: { get: async (k) => JSON.parse(await __viper.storageGet(k)), set: async (k, v) => JSON.parse(await __viper.storageSet(k, v)) },
        notify: async (t, b) => JSON.parse(await __viper.notify(t, b)),
        system: async () => JSON.parse(await __viper.system()),
        ask: async (p) => JSON.parse(await __viper.ask(p)),
      };
      globalThis.viper = viper;
      globalThis.plugin = { tools: {}, actions: {}, widgets: {}, pages: {}, notify: {}, readers: {} };
      globalThis.__call = async (kind, name, argJson) => {
        const fn = (plugin[kind] || {})[name];
        if (typeof fn !== 'function') throw new Error('Plugin does not implement ' + kind + '.' + name);
        return JSON.stringify(await fn(JSON.parse(argJson)));
      };`);
    if (boot.error) { const e = vm.dump(boot.error); boot.error.dispose(); throw new Error(`Sandbox boot failed: ${JSON.stringify(e)}`); }
    boot.value.dispose();
    const src = fs.readFileSync(path.join(this.plugin.dir, this.plugin.manifest.main), 'utf8');
    this.deadline = Date.now() + 2000;
    const r = vm.evalCode(src, `${this.plugin.id}/${this.plugin.manifest.main}`);
    this.deadline = 0;
    if (r.error) { const e = vm.dump(r.error); r.error.dispose(); throw new Error(`Plugin failed to load: ${e?.message || JSON.stringify(e)}`); }
    r.value.dispose();
  }
  async call(kind, name, args, timeoutMs = 20000) {
    const vm = this.ctx;
    const fn = vm.getProp(vm.global, '__call');
    const a1 = vm.newString(kind); const a2 = vm.newString(name); const a3 = vm.newString(JSON.stringify(args ?? {}));
    this.deadline = Date.now() + timeoutMs;
    const res = vm.callFunction(fn, vm.undefined, a1, a2, a3);
    [fn, a1, a2, a3].forEach((h) => h.dispose());
    if (res.error) { this.deadline = 0; const e = vm.dump(res.error); res.error.dispose(); throw new Error(e?.message || String(e)); }
    const promise = vm.resolvePromise(res.value);
    res.value.dispose();
    this.rt.executePendingJobs();
    const timer = new Promise((_, rej) => setTimeout(() => rej(new Error('Plugin call timed out')), timeoutMs));
    try {
      const out = await Promise.race([promise, timer]);
      if (out.error) { const e = vm.dump(out.error); out.error.dispose(); throw new Error(e?.message || String(e)); }
      const s = vm.dump(out.value); out.value.dispose();
      return JSON.parse(s);
    } finally { this.deadline = 0; }
  }
  dispose() { try { this.ctx?.dispose(); this.rt?.dispose(); } catch { /* ignore */ } }
}

class PluginManager {
  constructor(svc) { this.svc = svc; this.db = svc.db; this.dir = svc.paths.plugins; this.loaded = new Map(); this.log = svc.logger.scope('plugins'); }
  rows() { return this.db.all('SELECT * FROM plugins ORDER BY name').map((r) => ({ ...r, enabled: !!r.enabled, manifest: jsonParse(r.manifest, {}), granted: jsonParse(r.granted, []) })); }
  list() { return this.rows().map((p) => ({ ...p, loaded: this.loaded.has(p.id), error: this.errors?.[p.id] || null, permissionInfo: p.manifest.permissions.map((x) => ({ id: x, info: x.startsWith('http:') ? httpPermInfo(x.slice(5)) : PERMS[x] })) })); }

  /** Inspect a plugin folder or .zip without installing it. */
  async inspect(src) {
    let folder = src;
    if (/\.zip$/i.test(src)) folder = await this.unzip(src);
    const manifest = validateManifest(jsonParse(fs.readFileSync(path.join(folder, 'plugin.json'), 'utf8')));
    if (!fs.existsSync(path.join(folder, manifest.main))) throw new HttpError(400, `Entry file ${manifest.main} not found`);
    return { folder, manifest, permissions: manifest.permissions.map((x) => ({ id: x, info: x.startsWith('http:') ? httpPermInfo(x.slice(5)) : PERMS[x] })) };
  }
  unzip(zip) {
    const out = path.join(this.svc.paths.data, 'tmp', `plugin-${Date.now()}`);
    fs.mkdirSync(out, { recursive: true });
    return new Promise((resolve, reject) => execFile('tar', ['-xf', zip, '-C', out], { windowsHide: true }, (e) => {
      if (e) return reject(new HttpError(400, `Could not extract: ${e.message}`));
      const inner = fs.readdirSync(out); resolve(inner.length === 1 && fs.statSync(path.join(out, inner[0])).isDirectory() ? path.join(out, inner[0]) : out);
    }));
  }
  async install(src, grant = []) {
    const { folder, manifest } = await this.inspect(src);
    const dest = path.join(this.dir, manifest.id);
    fs.rmSync(dest, { recursive: true, force: true });
    fs.cpSync(folder, dest, { recursive: true, filter: (p) => !/node_modules|\.git/.test(p) });
    const granted = manifest.permissions.filter((p) => grant.includes(p));
    this.db.run(`INSERT INTO plugins (id, name, version, enabled, granted, manifest, path, installed_at) VALUES (?, ?, ?, 0, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET name=excluded.name, version=excluded.version, granted=excluded.granted, manifest=excluded.manifest, path=excluded.path`, manifest.id, manifest.name, manifest.version, JSON.stringify(granted), JSON.stringify(manifest), dest, now());
    this.svc.permissions.audit('user', 'plugin.installed', `${manifest.id}@${manifest.version}`, 'write', `granted: ${granted.join(', ') || 'none'}`);
    this.changed();
    return this.list().find((p) => p.id === manifest.id);
  }
  async uninstall(id) {
    await this.disable(id);
    const r = this.db.get('SELECT path FROM plugins WHERE id = ?', id);
    if (r && path.resolve(r.path).startsWith(path.resolve(this.dir))) fs.rmSync(r.path, { recursive: true, force: true });
    this.db.run('DELETE FROM plugins WHERE id = ?', id);
    this.changed();
  }
  setGrants(id, granted) { const p = this.rows().find((x) => x.id === id); if (!p) throw new HttpError(404, 'Plugin not found'); this.db.run('UPDATE plugins SET granted = ? WHERE id = ?', JSON.stringify(p.manifest.permissions.filter((x) => granted.includes(x))), id); if (p.enabled) return this.enable(id); this.changed(); }
  async enable(id) {
    const p = this.rows().find((x) => x.id === id);
    if (!p) throw new HttpError(404, 'Plugin not found');
    this.unload(id);
    const plugin = { id: p.id, name: p.name, dir: p.path, manifest: p.manifest, granted: new Set(p.granted) };
    const sb = new Sandbox(plugin, this);
    this.errors = this.errors || {};
    try { await sb.init(); } catch (e) { this.errors[id] = e.message; sb.dispose(); this.db.run('UPDATE plugins SET enabled = 0 WHERE id = ?', id); this.changed(); throw new HttpError(400, e.message); }
    delete this.errors[id];
    this.loaded.set(id, { plugin, sb });
    this.db.run('UPDATE plugins SET enabled = 1 WHERE id = ?', id);
    this.registerContributions(plugin, sb);
    this.changed();
    return this.list().find((x) => x.id === id);
  }
  async disable(id) { this.unload(id); this.db.run('UPDATE plugins SET enabled = 0 WHERE id = ?', id); this.changed(); }
  unload(id) {
    const l = this.loaded.get(id); if (!l) return;
    for (const t of l.plugin.manifest.contributes.tools || []) if (this.svc.tools.get(t.name)?.plugin === id) this.svc.tools.unregister(t.name);
    for (const c of l.plugin.manifest.contributes.notificationChannels || []) this.svc.notify.channels.delete(`plugin:${id}:${c.id}`);
    for (const m of l.plugin.manifest.contributes.models || []) delete this.svc.models.backends[`plugin:${id}:${m.id}`];
    l.sb.dispose(); this.loaded.delete(id);
  }
  registerContributions(plugin, sb) {
    const c = plugin.manifest.contributes;
    for (const t of c.tools || []) {
      const existing = this.svc.tools.get(t.name);
      if (existing && existing.plugin !== plugin.id) { this.log.warn(`plugin ${plugin.id}: tool name "${t.name}" is already used by ${existing.plugin ? `plugin ${existing.plugin}` : 'VIPER'}; skipped`); continue; }
      this.svc.tools.register({ name: t.name, label: `${t.label || t.name} (${plugin.name})`, description: `${t.description} [plugin: ${plugin.name}]`, parameters: t.parameters || { type: 'object', properties: {} }, category: 'plugin.tools', risk: t.risk === 'read' ? 'read' : 'write', keywords: t.keywords || [], plugin: plugin.id,
        handler: async (args) => ({ ok: true, result: await sb.call('tools', t.name, args), untrusted: true }) });
    }
    for (const ch of c.notificationChannels || []) this.svc.notify.registerChannel(`plugin:${plugin.id}:${ch.id}`, { label: `${ch.label} (${plugin.name})`, send: async (n) => { try { const r = await sb.call('notify', ch.id, { title: n.title, body: n.body, priority: n.priority }); return r?.ok === false ? { ok: false, error: r.error } : { ok: true }; } catch (e) { return { ok: false, error: e.message }; } } });
    for (const m of c.models || []) {
      if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//.test(`${m.baseUrl}/`)) continue; // plugin model endpoints must be local
      const { OpenAICompatBackend } = require('../llm/openai');
      this.svc.models.backends[`plugin:${plugin.id}:${m.id}`] = new OpenAICompatBackend({ id: `plugin:${plugin.id}:${m.id}`, label: `${m.label} (${plugin.name})`, getBaseUrl: async () => m.baseUrl, log: this.log });
    }
  }
  changed() { this.svc.bus.publish('plugins.changed', {}); }
  async start() { for (const p of this.rows().filter((x) => x.enabled)) { try { await this.enable(p.id); } catch (e) { this.log.warn(`plugin ${p.id} failed`, e.message); } } }

  async call(id, kind, name, args) {
    const l = this.loaded.get(id); if (!l) throw new HttpError(400, 'Plugin is not enabled');
    return l.sb.call(kind, name, args);
  }
  pages() { const out = []; for (const { plugin } of this.loaded.values()) for (const pg of plugin.manifest.contributes.pages || []) out.push({ id: `${plugin.id}/${pg.id}`, title: pg.title, plugin: plugin.name, description: pg.description || '' }); return out; }
  async widgets() {
    const out = [];
    for (const { plugin, sb } of this.loaded.values()) for (const w of plugin.manifest.contributes.widgets || []) {
      try { const r = await sb.call('widgets', w.id, {}, 5000); out.push({ id: `${plugin.id}/${w.id}`, title: r?.title || w.title, lines: (r?.lines || []).slice(0, 8).map(String) }); } catch (e) { out.push({ id: `${plugin.id}/${w.id}`, title: w.title, lines: [`Error: ${e.message}`] }); }
    }
    return out;
  }
  actions() { const out = []; for (const { plugin } of this.loaded.values()) for (const a of plugin.manifest.contributes.actions || []) out.push({ plugin: plugin.id, id: a.id, label: a.label }); return out; }
  readerFor(ext) { for (const { plugin, sb } of this.loaded.values()) for (const r of plugin.manifest.contributes.documentReaders || []) if ((r.extensions || []).includes(ext)) return (text) => sb.call('readers', r.id, { text }); return null; }

  // ---------- host API (permission-checked) ----------
  need(plugin, perm) { if (!plugin.granted.has(perm)) throw new Error(`Permission "${perm}" was not granted to this plugin`); }
  async http(plugin, url, opts) {
    const u = new URL(url);
    if (u.protocol !== 'https:') throw new Error('Plugins may only use HTTPS');
    this.need(plugin, `http:${u.hostname}`);
    const r = await fetchWithTimeout(u.toString(), { method: opts.method || 'GET', headers: { 'User-Agent': 'VIPER-plugin', ...(opts.headers || {}) }, body: opts.body ? String(opts.body) : undefined }, 15000);
    const text = (await r.text()).slice(0, 1_000_000);
    return { status: r.status, text };
  }
  storeFile(plugin) { return path.join(plugin.dir, '.storage.json'); }
  async storageGet(plugin, k) { this.need(plugin, 'storage'); return jsonParse(fs.existsSync(this.storeFile(plugin)) ? fs.readFileSync(this.storeFile(plugin), 'utf8') : '{}', {})[k] ?? null; }
  async storageSet(plugin, k, v) {
    this.need(plugin, 'storage');
    const f = this.storeFile(plugin); const d = jsonParse(fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '{}', {});
    d[k] = v; const s = JSON.stringify(d); if (s.length > 1_000_000) throw new Error('Plugin storage limit (1 MB) exceeded');
    fs.writeFileSync(f, s); return true;
  }
  async notify(plugin, title, body) { this.need(plugin, 'notify'); await this.svc.notify.send({ title: `${plugin.name}: ${title}`, body, category: 'general', channels: ['desktop'] }); return true; }
  async system(plugin) { this.need(plugin, 'system.read'); const s = await this.svc.monitor.snapshot(); return { cpu: s.cpu?.pct, memory: s.mem?.pct, disks: s.disks.map((d) => ({ mount: d.mount, usedPct: d.pct })) }; }
  async ask(plugin, prompt) { this.need(plugin, 'ai'); const r = await this.svc.models.complete({ role: 'chat', messages: [{ role: 'user', content: String(prompt).slice(0, 8000) }], options: { maxTokens: 500 } }); return r.text; }
}

module.exports = {
  name: 'plugins',
  init: (svc) => new PluginManager(svc),
  start: (svc) => svc.plugins.start(),
  routes(r, svc) {
    const P = '/api/v1/plugins';
    r.get(P, async () => svc.plugins.list());
    r.get(`${P}/pages`, async () => ({ pages: svc.plugins.pages() }));
    r.get(`${P}/widgets`, async () => svc.plugins.widgets(), { scope: 'read' });
    r.get(`${P}/actions`, async () => svc.plugins.actions());
    r.get(`${P}/examples`, async () => { const d = path.join(__dirname, '..', '..', '..', 'plugins-examples'); return fs.existsSync(d) ? fs.readdirSync(d).map((x) => ({ folder: path.join(d, x), ...jsonParse(fs.readFileSync(path.join(d, x, 'plugin.json'), 'utf8'), {}) })) : []; });
    r.post(`${P}/inspect`, async ({ body }) => svc.plugins.inspect(body.source));
    r.post(`${P}/install`, async ({ body }) => svc.plugins.install(body.source, body.grant || []));
    r.post(`${P}/:id/enable`, async ({ params }) => svc.plugins.enable(params.id));
    r.post(`${P}/:id/disable`, async ({ params }) => svc.plugins.disable(params.id));
    r.post(`${P}/:id/grants`, async ({ params, body }) => svc.plugins.setGrants(params.id, body.granted || []));
    r.delete(`${P}/:id`, async ({ params }) => svc.plugins.uninstall(params.id));
    r.post(`${P}/:id/page/:page`, async ({ params, body }) => svc.plugins.call(params.id, 'pages', params.page, body || {}));
  },
  PluginManager, validateManifest,
};
