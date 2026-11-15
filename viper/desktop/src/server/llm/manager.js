'use strict';
// Model manager: owns the inference backends, resolves which model serves
// each role (chat, code, vision, embeddings), streams completions with
// performance measurement, and recovers from backend crashes.
const { spawn } = require('node:child_process');
const os = require('node:os');
const { OllamaBackend } = require('./ollama');
const { FoundryBackend } = require('./foundry');
const { OpenAICompatBackend } = require('./openai');
const { OLLAMA_RECOMMENDED, FOUNDRY_RECOMMENDED, recommend } = require('./catalog');
const { sleep } = require('../util');

class ModelManager {
  constructor({ settings, vault, db, bus, log }) {
    this.settings = settings; this.vault = vault; this.db = db; this.bus = bus; this.log = log;
    this.backends = {
      ollama: new OllamaBackend({ getUrl: () => settings.get('backend').ollama.url, getLimits: () => settings.get('limits'), log }),
      foundry: new FoundryBackend({ getConfig: () => settings.get('backend').foundry, log }),
      openai: new OpenAICompatBackend({
        id: 'openai', label: 'OpenAI-compatible (local)',
        getBaseUrl: async () => settings.get('backend').openai.url,
        getApiKey: () => { const s = settings.get('backend').openai.apiKeySecret; return s ? vault.get(s) : null; },
        log,
      }),
    };
    this.health = {};
    this.downloads = new Map(); // id -> {model, backend, status, completed, total, controller}
    this.active = new Map(); // requestId -> info (current AI tasks)
    this.modelCache = { at: 0, list: [] };
    this.recovering = false;
    require('../hardware').detectHardware().then((hw) => { this.backends.ollama.cpu = hw.cpu; }).catch(() => {});
  }

  backend(id) {
    const b = this.backends[id || this.settings.get('backend').active];
    if (!b) throw new Error(`Unknown backend "${id}"`);
    return b;
  }

  async checkHealth() {
    const out = {};
    await Promise.all(Object.entries(this.backends).map(async ([id, b]) => {
      out[id] = await b.health().catch((e) => ({ ok: false, error: e.message }));
    }));
    this.health = out;
    this.bus.publish('models.health', out);
    return out;
  }

  async listInstalled(force = false) {
    if (!force && Date.now() - this.modelCache.at < 10000) return this.modelCache.list;
    const all = [];
    for (const [id, b] of Object.entries(this.backends)) {
      if (this.health[id] && !this.health[id].ok) continue;
      try { all.push(...await b.listModels()); } catch (e) { this.log.debug(`listModels ${id}:`, e.message); }
    }
    this.modelCache = { at: Date.now(), list: all };
    return all;
  }

  async catalog(backendId) {
    const installed = await this.listInstalled(true);
    const isInstalled = (id, be) => installed.some((m) => m.backend === be && (m.id === id || m.id === `${id}:latest` || m.alias === id || m.id.startsWith(id + '-')));
    if (backendId === 'foundry') {
      let live = [];
      try { live = await this.backends.foundry.catalog(); } catch (e) { this.log.debug('foundry catalog', e.message); }
      const rec = FOUNDRY_RECOMMENDED.map((m) => ({ ...m, backend: 'foundry', installed: live.some((l) => l.alias === m.id && l.installed) || isInstalled(m.id, 'foundry'), recommended: true }));
      return { recommended: rec, live };
    }
    return { recommended: OLLAMA_RECOMMENDED.map((m) => ({ ...m, backend: 'ollama', installed: isInstalled(m.id, 'ollama'), recommended: true })), live: [] };
  }

  /** Which backend+model serves a role. Falls back sensibly and never invents a model. */
  async resolve(role = 'chat') {
    const models = this.settings.get('models');
    const active = this.settings.get('backend').active;
    const want = models[role] || {};
    let backend = want.backend && this.backends[want.backend] ? want.backend : active;
    let model = want.model;
    if (!model && role !== 'chat') {
      const chat = models.chat || {};
      if (role === 'code' || role === 'vision') {
        if (role === 'vision') {
          const inst = await this.listInstalled();
          const v = inst.find((m) => m.capabilities?.includes('vision'));
          if (v) return { backend: v.backend, model: v.id };
          return { backend, model: null, reason: 'No vision-capable model installed. Install one (e.g. moondream or gemma3:4b) in the Model Manager.' };
        }
        backend = chat.backend && this.backends[chat.backend] ? chat.backend : active; model = chat.model;
      }
      if (role === 'embeddings') {
        const inst = await this.listInstalled();
        const e = inst.find((m) => m.capabilities?.includes('embeddings'));
        if (e) return { backend: e.backend, model: e.id };
        return { backend, model: null, reason: 'No embeddings model installed; keyword search will be used instead.' };
      }
    }
    if (!model) {
      // Prefer general chat models with tool calling; vision-only models (e.g. moondream) last.
      const score = (m) => (m.capabilities.includes('tools') ? 4 : 0) + (m.capabilities.includes('vision') ? -3 : 0) + (m.capabilities.includes('code') && role !== 'code' ? -1 : 0) + (role === 'code' && m.capabilities.includes('code') ? 3 : 0);
      const inst = (await this.listInstalled()).filter((m) => m.backend === backend && m.capabilities?.includes('chat')).sort((a, b) => score(b) - score(a));
      if (inst.length) model = inst[0].id;
    }
    if (!model) return { backend, model: null, reason: `No chat model is installed on ${this.backends[backend].label}. Open Model Manager to download one.` };
    return { backend, model };
  }

  /**
   * Model for a Code Agent role. planning / debug / code_review use their own model if one is set,
   * otherwise the code model; the code model falls back to an installed coding model (e.g.
   * qwen2.5-coder), then to the chat model. One shared model is normal on 16 GB machines.
   */
  async resolveAgent(role) {
    const roles = this.settings.get('models');
    const pick = (r) => (r?.model ? { backend: r.backend && this.backends[r.backend] ? r.backend : this.settings.get('backend').active, model: r.model } : null);
    const explicit = pick(roles[role]) || pick(roles.code);
    if (explicit) return explicit;
    const active = this.settings.get('backend').active;
    const inst = (await this.listInstalled()).filter((m) => m.backend === active && m.capabilities?.includes('chat'));
    const coder = inst.filter((m) => m.capabilities.includes('code') || /coder|code/i.test(m.id)).sort((a, b) => (a.sizeBytes || 0) - (b.sizeBytes || 0));
    if (coder.length) {
      // the largest coding model that fits comfortably in RAM
      const ram = require('node:os').totalmem();
      const fit = coder.filter((m) => !m.sizeBytes || m.sizeBytes < ram * 0.35);
      const m = (fit.length ? fit : coder)[(fit.length ? fit : coder).length - 1];
      return { backend: active, model: m.id };
    }
    return this.resolve('chat');
  }

  async modelInfo(backend, model) {
    const inst = await this.listInstalled();
    return inst.find((m) => m.backend === backend && m.id === model) || null;
  }

  /**
   * Stream a chat completion with metrics + one automatic recovery attempt.
   */
  async *chat({ role = 'chat', backend, model, messages, tools, options, signal, requestId, label, measure = true }) {
    if (!model) {
      const r = await this.resolve(role);
      backend = r.backend; model = r.model;
      if (!model) throw Object.assign(new Error(r.reason), { code: 'NO_MODEL' });
    }
    const be = this.backend(backend);
    await this.ensureResident(backend, model).catch((e) => this.log.debug('residency', e.message));
    const info = { id: requestId, backend, model, role, label: label || role, startedAt: Date.now(), tokens: 0 };
    if (requestId) { this.active.set(requestId, info); this.bus.publish('ai.task', { ...info, state: 'started' }); }
    let attempt = 0;
    try {
      while (true) {
        const t0 = Date.now(); let first = 0; let tokens = 0; let emitted = false;
        // Watchdog: a model that stops producing output is treated as unresponsive (first token
        // may take long while the model loads; between tokens it should keep flowing).
        const stall = new AbortController();
        const sig = signal ? AbortSignal.any([signal, stall.signal]) : stall.signal;
        const lim = this.settings.get('limits');
        let stallTimer = setTimeout(() => stall.abort(new Error('The AI model stopped responding')), (lim.firstTokenTimeoutSec || 300) * 1000);
        const bump = () => { clearTimeout(stallTimer); stallTimer = setTimeout(() => stall.abort(new Error('The AI model stopped responding')), (lim.tokenTimeoutSec || 90) * 1000); };
        try {
          for await (const ev of be.chat({ model, messages, tools, options, signal: sig })) {
            bump();
            if (ev.type === 'token') {
              if (!first) first = Date.now();
              tokens++; emitted = true; info.tokens = tokens;
            }
            if (ev.type === 'done') {
              const genMs = Date.now() - (first || t0);
              const outTokens = ev.usage?.completion_tokens || tokens;
              const tps = ev.stats?.evalDurationNs ? ev.stats.evalCount / (ev.stats.evalDurationNs / 1e9) : (genMs > 0 ? outTokens / (genMs / 1000) : 0);
              const perf = { backend, model, ttftMs: first ? first - t0 : null, tokens: outTokens, tokPerS: Math.round(tps * 10) / 10, promptTokens: ev.usage?.prompt_tokens ?? null, loadMs: ev.stats?.loadDurationNs ? Math.round(ev.stats.loadDurationNs / 1e6) : null, promptMs: ev.stats?.promptDurationNs ? Math.round(ev.stats.promptDurationNs / 1e6) : null };
              if (measure) this.recordPerf(perf, true);
              yield { ...ev, perf };
              continue;
            }
            yield ev;
          }
          clearTimeout(stallTimer);
          return;
        } catch (e) {
          clearTimeout(stallTimer);
          if (signal?.aborted) throw e;
          if (stall.signal.aborted) {
            const err = Object.assign(new Error(`${model} stopped responding. VIPER is reconnecting to the AI engine.`), { code: 'STALLED' });
            this.recordPerf({ backend, model, ttftMs: null, tokens: 0, tokPerS: 0 }, false);
            this.onStall?.(model);
            throw err;
          }
          const connErr = /fetch failed|ECONNREFUSED|ECONNRESET|socket hang up|not running|other side closed|terminated/i.test(e.message + (e.cause?.message || ''));
          if (measure) this.recordPerf({ backend, model, ttftMs: null, tokens: 0, tokPerS: 0 }, false);
          if (connErr && !emitted && attempt === 0 && this.settings.get('backend').autoRecover) {
            attempt++;
            this.bus.publish('models.recovering', { backend, model, error: e.message });
            const ok = await this.recover(backend);
            if (ok) continue;
          }
          if (e.code === 'NO_TOOLS' && tools?.length) { e.retryWithoutTools = true; }
          throw e;
        }
      }
    } finally {
      if (requestId) { this.active.delete(requestId); this.bus.publish('ai.task', { ...info, state: 'finished', durationMs: Date.now() - info.startedAt }); }
    }
  }

  inUse(backend, name) { for (const t of this.active.values()) if (t.backend === backend && t.model === name) return true; return false; }

  /**
   * Keep memory bounded. Before a model runs, other resident models beyond the profile's
   * limit are unloaded (least recently used first) — or all of them when free RAM would not
   * fit the incoming model — so chat, code and vision models are never all in RAM at once
   * on a 16 GB laptop. Idle models are also released by the engine after `keepAlive`.
   */
  async ensureResident(backendId, model) {
    const be = this.backends[backendId];
    const max = this.settings.get('performance').maxLoadedModels;
    if (!be?.loaded || !be.unload || !(max >= 1) || !this.health[backendId]?.ok) return [];
    const key = `${backendId}:${model}`;
    if (this._resident === key && Date.now() - this._residentAt < 5000) return [];
    const loaded = await be.loaded();
    const self = loaded.find((m) => m.name === model);
    const others = loaded.filter((m) => m.name !== model && !this.inUse(backendId, m.name))
      .sort((a, b) => String(b.expiresAt || '').localeCompare(String(a.expiresAt || ''))); // most recently used first
    let keep = Math.max(0, max - 1);
    if (!self && others.length) {
      const info = await this.modelInfo(backendId, model).catch(() => null);
      const need = (info?.sizeBytes || 0) * 1.25 + 1.5 * 1073741824;
      if (os.freemem() < need) keep = 0;
    }
    const dropped = [];
    for (const m of others.slice(keep)) {
      try { await be.unload(m.name); dropped.push(m.name); this.log.info(`unloaded ${m.name} to make room for ${model}`); this.bus.publish('models.unloaded', { backend: backendId, model: m.name, reason: `make room for ${model}` }); }
      catch (e) { this.log.debug(`unload ${m.name}`, e.message); }
    }
    this._resident = key; this._residentAt = Date.now();
    return dropped;
  }

  /** Non-streaming convenience wrapper. */
  async complete(args) {
    let text = ''; let toolCalls = null; let perf = null;
    for await (const ev of this.chat(args)) {
      if (ev.type === 'token') text += ev.text;
      if (ev.type === 'tool_calls') toolCalls = ev.calls;
      if (ev.type === 'done') perf = ev.perf;
    }
    return { text, toolCalls, perf };
  }

  async embed(texts) {
    const r = await this.resolve('embeddings');
    if (!r.model) throw Object.assign(new Error(r.reason), { code: 'NO_MODEL' });
    return this.backend(r.backend).embed({ model: r.model, input: texts });
  }

  recordPerf(p, ok) {
    try {
      this.db.run('INSERT INTO model_perf (backend, model, ts, ttft_ms, tokens, tok_per_s, ok) VALUES (?, ?, ?, ?, ?, ?, ?)', p.backend, p.model, Date.now(), p.ttftMs, p.tokens, p.tokPerS, ok ? 1 : 0);
      this.bus.publish('models.perf', { ...p, ok });
    } catch { /* non-fatal */ }
  }
  perfSummary() {
    return this.db.all(`SELECT backend, model, COUNT(*) AS runs, ROUND(AVG(tok_per_s),1) AS avg_tps, ROUND(AVG(ttft_ms)) AS avg_ttft,
      SUM(CASE WHEN ok=0 THEN 1 ELSE 0 END) AS failures, MAX(ts) AS last FROM model_perf WHERE ts > ? GROUP BY backend, model ORDER BY last DESC`, Date.now() - 30 * 86400000);
  }

  /** Attempt to bring a crashed/stopped backend back. */
  async recover(backendId) {
    // The AI start-up service owns engine processes and rate-limits recovery.
    if (this.recoverHook) return this.recoverHook(backendId);
    if (this.recovering) return false;
    this.recovering = true;
    try {
      this.log.warn(`Backend ${backendId} unreachable; attempting recovery`);
      if (backendId === 'foundry') {
        await this.backends.foundry.startService();
      } else if (backendId === 'ollama') {
        const h = await this.backends.ollama.health();
        if (!h.ok) {
          try {
            const p = spawn(process.platform === 'win32' ? 'ollama.exe' : 'ollama', ['serve'], { detached: true, stdio: 'ignore', windowsHide: true });
            p.on('error', () => {});
            p.unref();
          } catch { /* not installed */ }
        }
      }
      for (let i = 0; i < 20; i++) {
        await sleep(750);
        const h = await this.backend(backendId).health();
        if (h.ok) { this.bus.publish('models.recovered', { backend: backendId }); this.log.info(`Backend ${backendId} recovered`); return true; }
      }
      this.bus.publish('models.recoveryFailed', { backend: backendId });
      return false;
    } catch (e) {
      this.log.error('recovery failed', e);
      this.bus.publish('models.recoveryFailed', { backend: backendId, error: e.message });
      return false;
    } finally { this.recovering = false; }
  }

  startDownload(backendId, model) {
    const id = `${backendId}:${model}`;
    if (this.downloads.has(id) && this.downloads.get(id).status === 'downloading') return this.downloads.get(id);
    const controller = new AbortController();
    const d = { id, backend: backendId, model, status: 'downloading', completed: 0, total: 0, detail: 'starting', startedAt: Date.now() };
    this.downloads.set(id, { ...d, controller });
    const publish = () => { const x = this.downloads.get(id); this.bus.publish('models.download', { id, backend: backendId, model, status: x.status, completed: x.completed, total: x.total, detail: x.detail, error: x.error, startedAt: x.startedAt }); };
    let lastPub = 0;
    this.backend(backendId).pull(model, (p) => {
      const x = this.downloads.get(id);
      Object.assign(x, { completed: p.completed, total: p.total, detail: p.status });
      if (Date.now() - lastPub > 250) { lastPub = Date.now(); publish(); }
    }, controller.signal).then(() => {
      Object.assign(this.downloads.get(id), { status: 'done', detail: 'installed' });
      this.modelCache.at = 0; publish();
    }).catch((e) => {
      Object.assign(this.downloads.get(id), { status: controller.signal.aborted ? 'cancelled' : 'error', error: e.message });
      publish();
    });
    publish();
    return d;
  }
  cancelDownload(id) { const d = this.downloads.get(id); if (d?.controller) d.controller.abort(); }
  listDownloads() { return [...this.downloads.values()].map(({ controller, ...d }) => d); }

  async loadedModels() {
    const out = [];
    for (const [id, b] of Object.entries(this.backends)) {
      if (!this.health[id]?.ok || !b.loaded) continue;
      try { for (const m of await b.loaded()) out.push({ backend: id, ...m }); } catch { /* skip */ }
    }
    return out;
  }

  async recommendation(hw) { return recommend(hw, this.settings.get('backend').active); }

  /** Run a short benchmark prompt to compare models. */
  async benchmark(backend, model) {
    const t0 = Date.now();
    const r = await this.complete({ backend, model, messages: [{ role: 'user', content: 'In two sentences, explain what a CPU cache is.' }], options: { maxTokens: 120 } });
    return { backend, model, ms: Date.now() - t0, ...r.perf, sample: r.text.slice(0, 400) };
  }

  status() {
    return {
      active: this.settings.get('backend').active, health: this.health, roles: this.settings.get('models'),
      tasks: [...this.active.values()], downloads: this.listDownloads(),
    };
  }
}

module.exports = { ModelManager };
