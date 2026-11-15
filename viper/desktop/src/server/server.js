'use strict';
// Composition root. Creates every VIPER service, the local API server
// (127.0.0.1 only, per-launch token) and the WebSocket event stream.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer } = require('ws');

const { makePaths } = require('./paths');
const { Logger } = require('./log');
const { Bus } = require('./bus');
const { Database } = require('./db');
const { Settings } = require('./settings');
const { Vault, fileKeyEncryptor } = require('./secrets');
const { Permissions } = require('./permissions');
const { ModelManager } = require('./llm/manager');
const { SystemMonitor } = require('./system/monitor');
const { AppCatalog } = require('./system/apps');
const { ToolRegistry } = require('./tools/registry');
const { MemoryStore } = require('./memory');
const { Notifier } = require('./notify');
const { Reminders } = require('./reminders');
const { AutomationEngine } = require('./automation');
const { Briefing } = require('./briefing');
const { TaskWatch } = require('./tasks');
const { Orchestrator } = require('./orchestrator');
const { PerformanceProfile } = require('./performance');
const { AIStartup } = require('./llm/startup');
const { EngineInstaller } = require('./llm/installer');
const { Router, dispatch, send } = require('./http');
const { coreRoutes } = require('./api');
const { headlessBridge } = require('./bridge');
const { timingSafeEqualStr } = require('./util');

const FEATURE_MODULES = ['./files/index', './research', './image', './code', './agent/index', './voice/index', './comms/index', './remote/index', './plugins/index'];
const RENDERER_DIR = path.join(__dirname, '..', 'renderer');
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon', '.json': 'application/json', '.woff2': 'font/woff2', '.wav': 'audio/wav', '.webp': 'image/webp' };
const CSP = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' data: blob:; connect-src 'self' ws://127.0.0.1:* ws://localhost:*; font-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'";

async function createViper(opts = {}) {
  const paths = makePaths(opts.dataDir);
  const logger = new Logger(paths.logs, { echo: !!opts.echoLogs, level: opts.logLevel || 'info' });
  logger.prune();
  const log = logger.scope('core');
  const bus = new Bus();
  const db = new Database(paths.db);
  const settings = new Settings(db, bus);
  const vault = new Vault(db, opts.encryptor || fileKeyEncryptor(paths.data));
  // Repair allowed folders saved by older versions that point at a Documents/Desktop folder
  // which Windows moved into OneDrive.
  {
    const pv = settings.get('privacy');
    const known = require('./settings').defaultFolders(require('node:os').homedir());
    const fixed = [...new Set(pv.allowedFolders.map((f) => (fs.existsSync(f) ? f : known.find((k) => path.basename(k) === path.basename(f) && fs.existsSync(k)) || f)))];
    if (fixed.join('|') !== pv.allowedFolders.join('|')) settings.set('privacy', { allowedFolders: fixed });
  }
  const bridge = opts.bridge || headlessBridge(paths);

  const svc = { version: opts.version || require('../../package.json').version, paths, logger, log, bus, db, settings, vault, bridge, events: {} };
  svc.performance = await new PerformanceProfile({ settings, log: logger.scope('perf'), bus }).init();
  svc.permissions = new Permissions({ settings, bus, db, log: logger.scope('perm') });
  svc.models = new ModelManager({ settings, vault, db, bus, log: logger.scope('models') });
  svc.monitor = new SystemMonitor({ bus, log: logger.scope('monitor'), settings, models: svc.models });
  svc.apps = new AppCatalog({ log });
  svc.tools = new ToolRegistry({ permissions: svc.permissions, bus, log: logger.scope('tools') });
  svc.memory = new MemoryStore({ db, settings, bus });
  svc.notify = new Notifier({ db, bus, settings, vault, log: logger.scope('notify'), bridge });
  svc.reminders = new Reminders({ db, bus, notify: svc.notify, log });
  svc.taskWatch = new TaskWatch({ bus, notify: svc.notify });
  svc.automation = new AutomationEngine({ ...svc, log: logger.scope('automation'), get tools() { return svc.tools; } });
  svc.automation.svc = svc;
  svc.briefing = new Briefing(svc);
  svc.orchestrator = new Orchestrator(svc);
  svc.aiStartup = new AIStartup(svc, opts.aiStartup || {});
  svc.engineInstaller = new EngineInstaller(svc);
  svc.models.recoverHook = (backendId) => svc.aiStartup.recover(`${backendId} connection lost`);
  svc.models.onStall = (model) => svc.aiStartup.watchdog(`${model} stopped responding`);

  require('./tools/computer').register(svc.tools, svc);
  require('./tools/assistant').register(svc.tools, svc);

  const router = new Router();
  coreRoutes(router, svc);
  svc.router = router;

  // Feature modules: each exports { init(svc), routes?(router, svc) }.
  for (const m of FEATURE_MODULES) {
    let mod;
    try { mod = require(m); } catch (e) { if (e.code === 'MODULE_NOT_FOUND' && e.message.includes(m.replace('./', ''))) continue; throw e; }
    try {
      const inst = await mod.init(svc);
      if (mod.name && inst) svc[mod.name] = inst;
      mod.routes?.(router, svc);
    } catch (e) { log.error(`module ${m} failed to initialise`, e); }
  }

  // System alerts → notifications (proactive).
  bus.on('system.alert', (a) => { if (settings.get('proactive').enabled || a.severity === 'critical') svc.notify.send({ kind: 'system_alert', detail: a.message, link: { type: 'system', id: a.kind || 'alert' }, dedupeKey: `alert:${a.kind || a.title}` }); });
  // Approval requests that wait unanswered at the PC go to the phone ("I require your
  // authorisation"). The notification only opens a review screen; it never approves anything.
  bus.on('confirm.request', (req) => {
    const toPhone = () => {
      const p = svc.permissions.pending.get(req.id); if (!p) return;
      p.req.remoteApprovable = true;
      bus.publish('confirm.request', { id: req.id, ...p.req, expiresAt: req.expiresAt });
      svc.notify.send({ kind: 'approval_required', detail: req.title, channels: ['mobile'], link: { type: 'confirm', id: req.id } });
    };
    if (String(req.origin || '').startsWith('phone') || req.remoteApprovable || req.tool === 'pair_device') return; // phone already has it / PC-only
    const t = setTimeout(toPhone, req.agent ? 0 : 20000); t.unref?.();
  });
  // Long model downloads finishing: "Your download is ready."
  bus.on('models.download', (d) => { if (d.status === 'done' && d.startedAt && Date.now() - d.startedAt > 60000) svc.notify.send({ kind: 'download_complete', detail: d.model, link: { type: 'model', id: d.model } }); });
  svc.events.onSettingsChanged = (section) => {
    if (section === 'proactive') svc.briefing.scheduleProactive();
    if (section === 'remote') svc.remote?.applySettings?.();
    // A different engine or chat model: run the start-up sequence again (start, load, verify).
    if (section === 'backend' || section === 'models') { svc.models.modelCache.at = 0; scheduleStartup('settings changed'); }
  };
  let startTimer = null;
  const scheduleStartup = (reason, ms = 800) => {
    if (opts.noBackground) return;
    clearTimeout(startTimer);
    startTimer = setTimeout(() => svc.aiStartup.run(reason).catch((e) => log.warn('AI start-up', e)), ms);
    startTimer.unref?.();
  };
  svc.scheduleWarmup = (reason) => scheduleStartup(reason, 500);
  svc.scheduleStartup = scheduleStartup;
  bus.on('event', (e) => {
    if (e.type === 'models.health') svc.aiStartup.onHealth(e.data);
    // A model downloaded while setup was required: continue start-up automatically.
    if (e.type === 'models.download' && e.data.status === 'done' && svc.aiStartup.state.stage === 'setup') scheduleStartup('model installed', 300);
  });

  // ---------- local HTTP server ----------
  const token = opts.token || crypto.randomBytes(24).toString('base64url');
  svc.localToken = token;
  const port = opts.port ?? settings.get('remote').localPort ?? 47800;

  const server = http.createServer((req, res) => {
    const host = String(req.headers.host || '');
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/i.test(host)) { res.writeHead(421); return res.end('Misdirected request'); } // DNS-rebinding guard
    const url = new URL(req.url, 'http://x');
    if (url.pathname.startsWith('/api/')) {
      const given = (req.headers.authorization || '').replace(/^Bearer\s+/i, '') || url.searchParams.get('token') || '';
      if (!timingSafeEqualStr(given, token)) return send(res, 401, { error: 'Unauthorized' });
      return dispatch(router, req, res, { local: true, scopes: ['*'] }, { log });
    }
    serveStatic(url.pathname, res);
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 1 << 20 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://x');
    const host = String(req.headers.host || '');
    if (url.pathname !== '/api/v1/ws' || !/^(127\.0\.0\.1|localhost)(:\d+)?$/i.test(host) || !timingSafeEqualStr(url.searchParams.get('token') || '', token)) { socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });
  wss.on('connection', (ws) => {
    ws.send(JSON.stringify({ type: 'hello', data: { version: svc.version }, ts: Date.now() }));
    ws.on('message', (m) => { try { const j = JSON.parse(m); if (j.type === 'ping') ws.send(JSON.stringify({ type: 'pong', ts: Date.now() })); } catch { /* ignore */ } });
  });
  bus.on('event', (evt) => {
    const s = JSON.stringify(evt);
    for (const c of wss.clients) if (c.readyState === 1) c.send(s);
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => { server.off('error', reject); resolve(); });
  }).catch(async (e) => {
    if (e.code !== 'EADDRINUSE' || opts.port) throw e;
    await new Promise((res2) => server.listen(0, '127.0.0.1', res2)); // fall back to a free port
  });
  svc.port = server.address().port;
  svc.url = `http://127.0.0.1:${svc.port}`;
  log.info(`VIPER core listening on ${svc.url}`);

  // Start background services. The AI start-up runs in the background: the UI is usable
  // immediately and shows each real stage until "VIPER ONLINE — READY".
  await svc.models.checkHealth().catch(() => {});
  if (!opts.noBackground && opts.autoStartAI !== false) scheduleStartup('launch', 0);
  if (!opts.noBackground) {
    svc.monitor.start();
    svc.reminders.start();
    svc.automation.start();
    svc.briefing.scheduleProactive();
    svc.healthTimer = setInterval(() => svc.models.checkHealth().catch(() => {}), 20000);
    svc.apps.refresh().catch(() => {});
    const tidy = () => { const r = db.housekeeping(); if (r && Object.values(r).some(Boolean)) log.info('database housekeeping', JSON.stringify(r)); };
    svc.tidyTimer = setTimeout(function again() { tidy(); svc.tidyTimer = setTimeout(again, 86400000); svc.tidyTimer.unref?.(); }, 60000);
    svc.tidyTimer.unref?.();
  }
  for (const m of FEATURE_MODULES) { try { const mod = require(m); await mod.start?.(svc); } catch { /* optional */ } }

  svc.shutdown = async () => {
    clearInterval(svc.healthTimer); clearTimeout(startTimer); clearTimeout(svc.tidyTimer);
    svc.aiStartup.shutdown();
    svc.orchestrator.cancelAll();
    svc.monitor.stop(); svc.reminders.stop(); svc.automation.stop();
    for (const m of FEATURE_MODULES) { try { await require(m).stop?.(svc); } catch { /* optional */ } }
    for (const c of wss.clients) c.terminate();
    await new Promise((r) => server.close(r));
    db.close();
  };
  return svc;
}

function serveStatic(pathname, res) {
  let rel = decodeURIComponent(pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  const file = path.normalize(path.join(RENDERER_DIR, rel));
  if (!file.startsWith(RENDERER_DIR + path.sep)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    const ext = path.extname(file).toLowerCase();
    const headers = { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' };
    if (ext === '.html') { headers['Content-Security-Policy'] = CSP; headers['X-Frame-Options'] = 'DENY'; }
    res.writeHead(200, headers);
    res.end(data);
  });
}

module.exports = { createViper };
