'use strict';
// Automatic AI start-up. When VIPER launches it finds the local inference engine, starts it if
// it is not running, picks the model (the one you chose, else the last one that worked, else the
// best installed model for this PC), loads and warms it, runs a real generation check, and only
// then reports "VIPER ONLINE — READY". Every stage is a real operation and is published as an
// `ai.startup` event. Failures retry a limited number of times; a watchdog recovers from engine
// crashes with a rate limit, so VIPER never loops endlessly. An engine process that VIPER starts
// is VIPER's to stop on exit; an engine that was already running is never stopped.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn, execFile } = require('node:child_process');
const { detectHardware } = require('../hardware');
const { recommend, OLLAMA_RECOMMENDED } = require('./catalog');
const { sleep } = require('../util');

const STAGES = {
  idle: 'STANDING BY',
  init: 'INITIALISING VIPER',
  engine: 'CHECKING LOCAL AI ENGINE',
  starting: 'STARTING AI BACKEND',
  model: 'LOADING AI MODEL',
  verify: 'VERIFYING CONNECTION',
  ready: 'VIPER ONLINE — READY',
  setup: 'AI SETUP REQUIRED',
  error: 'AI OFFLINE',
};
const ORDER = ['init', 'engine', 'starting', 'model', 'verify', 'ready'];
const LABEL = { ollama: 'Ollama', foundry: 'Foundry Local', openai: 'the local AI server' };
const GREETING = 'VIPER systems online. Local intelligence operational.';

class StartupError extends Error {
  constructor(message, { final = false, need = null, detail = null } = {}) { super(message); this.final = final; this.need = need; this.detail = detail; }
}

function withTimeout(promise, ms, message) {
  let t; return Promise.race([promise, new Promise((_, rej) => { t = setTimeout(() => rej(new StartupError(message)), ms); t.unref?.(); })]).finally(() => clearTimeout(t));
}
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

class AIStartup {
  constructor(svc, { spawnFn = spawn, retryDelays = [2000, 6000], timeouts = {} } = {}) {
    this.svc = svc; this.log = svc.logger.scope('ai-start');
    this.spawnFn = spawnFn; this.retryDelays = retryDelays;
    this.timeouts = { engine: 45000, model: 300000, verify: 120000, ...timeouts };
    this.state = { stage: 'idle', label: STAGES.idle, steps: [] };
    this.running = null; this.owned = null; this.recoveries = []; this.launched = false;
    this.pidFile = path.join(svc.paths.data, 'run', 'engine.pid');
  }

  status() { return { ...this.state, owned: !!this.owned }; }

  set(stage, detail = '', extra = {}) {
    const steps = ORDER.map((s) => ({ id: s, label: STAGES[s], state: s === stage ? (stage === 'ready' ? 'done' : 'active') : ORDER.indexOf(s) < ORDER.indexOf(stage) ? 'done' : 'pending' }));
    if (stage === 'error' || stage === 'setup') { const prev = this.state.steps || []; for (const st of steps) st.state = (prev.find((p) => p.id === st.id)?.state === 'done') ? 'done' : 'pending'; }
    this.state = { stage, label: STAGES[stage], detail, at: Date.now(), steps, backend: this.state.backend, model: this.state.model, ...extra };
    this.state.owned = !!this.owned;
    if (stage !== 'error') delete this.state.error;
    this.svc.bus.publish('ai.startup', this.state);
    if (detail) this.log.info(`${STAGES[stage]}: ${detail}`);
  }

  /** Run the start-up sequence (deduplicated: concurrent callers share one run). */
  run(reason = 'launch') {
    if (this.running) return this.running;
    this.running = this._run(reason).finally(() => { this.running = null; });
    return this.running;
  }

  async _run(reason) {
    const attempts = this.retryDelays.length + 1;
    let last = null;
    for (let attempt = 1; attempt <= attempts; attempt++) {
      try {
        await this.sequence(reason, attempt);
        return this.status();
      } catch (e) {
        last = e;
        this.log.warn(`start-up attempt ${attempt}/${attempts} failed: ${e.message}`);
        if (e.final || attempt === attempts) break;
        this.set(this.state.stage === 'idle' ? 'init' : this.state.stage, `Attempt ${attempt} failed (${e.message}). Retrying…`, { attempt });
        await sleep(this.retryDelays[attempt - 1]);
      }
    }
    if (last?.need) this.set('setup', last.message, { need: last.need, ...last.detail });
    else this.set('error', last?.message || 'The AI engine could not be started.', { error: last?.message, retry: true });
    return this.status();
  }

  async sequence(reason, attempt) {
    const { svc } = this;
    const cfg = svc.settings.get('backend');
    const backend = cfg.active;
    this.state.backend = backend;
    this.set('init', attempt > 1 ? `Attempt ${attempt}` : 'Detecting hardware', { attempt, reason });
    const hw = await detectHardware().catch(() => null);

    // 1-3. Engine: running? installed? start it.
    this.set('engine', `Looking for ${LABEL[backend] || backend}`);
    let h = await svc.models.backend(backend).health();
    if (!h.ok) {
      if (backend === 'openai') throw new StartupError(`No AI server is answering at ${cfg.openai.url}. Start it, or choose Ollama or Foundry Local in Models.`, { final: attempt > 1 });
      const inst = await this.engineInstalled(backend);
      if (!inst.ok) throw new StartupError(`${LABEL[backend]} is not installed on this PC.`, { final: true, need: 'engine', detail: { engine: backend, canInstall: backend === 'ollama' ? process.platform === 'win32' : backend === 'foundry' && process.platform === 'win32' } });
      if (cfg.autoStart === false) throw new StartupError(`${LABEL[backend]} is installed but not running, and automatic start is off (Settings → Performance → AI start-up).`, { final: true });
      this.set('starting', `Starting ${LABEL[backend]}`);
      await this.startEngine(backend, inst.path);
      h = await svc.models.backend(backend).health();
    } else this.set('engine', `${LABEL[backend]} ${h.version || ''} is running`.trim());
    await svc.models.checkHealth();
    if (!svc.models.health[backend]?.ok) throw new StartupError(`${LABEL[backend]} stopped responding.`);

    // 4-5. Models: installed → preferred → last working → best compatible.
    this.set('model', 'Finding installed models');
    svc.models.modelCache.at = 0;
    const pick = await this.chooseModel(backend, hw);
    if (!pick.model) throw new StartupError('No AI model is installed yet.', { final: true, need: 'model', detail: { engine: backend, recommended: pick.recommended, recommendedSizeGB: pick.recommendedSizeGB } });
    this.state.model = pick.model;
    if (pick.note) svc.bus.publish('notification', { title: 'AI model changed', body: pick.note, created_at: Date.now() });

    // 6. Load + warm (pre-fills the prompt cache with VIPER's instructions).
    this.set('model', `Loading ${pick.model}${pick.why ? ` (${pick.why})` : ''}`);
    const warm = await withTimeout(svc.orchestrator.warmup('startup', { force: true, target: { backend, model: pick.model } }), this.timeouts.model, `${pick.model} took too long to load.`);
    if (!warm || warm.error) throw new StartupError(`${pick.model} could not be loaded: ${warm?.error || 'no response'}`);

    // 7-8. Real readiness check: the model must generate text.
    this.set('verify', `Asking ${pick.model} to respond`);
    const t0 = Date.now();
    const check = await withTimeout(svc.models.complete({ backend, model: pick.model, messages: [{ role: 'user', content: 'Reply with the single word: ready' }], options: { maxTokens: 8, temperature: 0 }, measure: false, label: 'Readiness check' }), this.timeouts.verify, `${pick.model} did not answer the readiness check in time.`);
    if (!check.text?.trim()) throw new StartupError(`${pick.model} returned an empty answer to the readiness check.`);
    const ms = Date.now() - t0;

    // Remember what works, so the next launch reconnects to it directly.
    const roles = svc.settings.get('models');
    if (!roles.chat.model || roles.chat.backend !== backend) svc.settings.set('models', { chat: { backend, model: pick.model } });
    svc.settings.set('app', { lastWorkingModel: { backend, model: pick.model, at: Date.now() } });

    const greet = reason === 'launch' && !this.launched && svc.settings.get('voice').startupGreeting;
    this.launched = true;
    this.set('ready', `${pick.model} on ${LABEL[backend]} · answered in ${ms} ms`, { model: pick.model, readyMs: ms, warmMs: warm.ms, greeting: greet ? GREETING : null });
  }

  /** Is the engine installed? Returns { ok, path }. */
  async engineInstalled(backend) {
    if (backend === 'foundry') { const c = await this.svc.models.backends.foundry.cliInstalled(); return { ok: c.installed, path: null }; }
    const custom = this.svc.settings.get('backend').ollama.path;
    const exe = process.platform === 'win32' ? 'ollama.exe' : 'ollama';
    const cands = [
      custom,
      process.platform === 'win32' && path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Ollama', exe),
      process.platform === 'win32' && path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Ollama', exe),
      ...String(process.env.PATH || '').split(path.delimiter).map((d) => d && path.join(d, exe)),
      process.platform !== 'win32' && '/usr/local/bin/ollama', process.platform !== 'win32' && '/usr/bin/ollama',
    ].filter(Boolean);
    for (const c of cands) { try { if (fs.statSync(c).isFile()) return { ok: true, path: c }; } catch { /* next */ } }
    return { ok: false, path: null };
  }

  /** Start the engine and wait until it answers. Never starts a second copy. */
  async startEngine(backend, exe) {
    const be = this.svc.models.backend(backend);
    if (backend === 'foundry') {
      await withTimeout(this.svc.models.backends.foundry.startService(), this.timeouts.engine, 'Foundry Local did not start in time.');
      return;
    }
    // Another copy may just be starting (e.g. the Ollama tray app at login): give it a moment.
    for (let i = 0; i < 4; i++) { if ((await be.health()).ok) return; await sleep(1000); }
    // A process VIPER started in an earlier session that no longer answers is ours to clean up.
    this.killStale();
    if (this.owned && alive(this.owned.pid)) { this.stopOwned(); await sleep(500); }
    const url = new URL(this.svc.settings.get('backend').ollama.url || 'http://127.0.0.1:11434');
    const logFile = path.join(this.svc.paths.logs, 'engine.log');
    const out = fs.openSync(logFile, 'a');
    const child = this.spawnFn(exe, ['serve'], { env: { ...process.env, OLLAMA_HOST: `${url.hostname}:${url.port || 11434}` }, stdio: ['ignore', out, out], windowsHide: true, detached: false });
    fs.closeSync(out);
    let exited = null;
    child.on('error', (e) => { exited = e.message; });
    child.on('exit', (code) => { exited = exited || `exited with code ${code}`; if (this.owned?.pid === child.pid) { this.owned = null; this.removePidFile(); if (this.state.stage === 'ready') this.watchdog('engine process exited'); } });
    this.owned = { pid: child.pid, child, backend, startedAt: Date.now() };
    fs.mkdirSync(path.dirname(this.pidFile), { recursive: true });
    fs.writeFileSync(this.pidFile, JSON.stringify({ pid: child.pid, exe, startedAt: Date.now() }));
    this.log.info(`started ${exe} serve (pid ${child.pid})`);
    const end = Date.now() + this.timeouts.engine;
    while (Date.now() < end) {
      if (exited) throw new StartupError(`${LABEL[backend]} could not start (${exited}). ${this.tail(logFile)}`.trim());
      if ((await be.health()).ok) return;
      await sleep(500);
    }
    throw new StartupError(`${LABEL[backend]} did not start within ${Math.round(this.timeouts.engine / 1000)} s. ${this.tail(logFile)}`.trim());
  }

  tail(file) { try { const t = fs.readFileSync(file, 'utf8').trim().split('\n').slice(-2).join(' ').slice(-220); return t ? `Last engine message: ${t}` : ''; } catch { return ''; } }

  killStale() {
    try {
      const { pid } = JSON.parse(fs.readFileSync(this.pidFile, 'utf8'));
      if (pid && pid !== this.owned?.pid && alive(pid)) { this.log.warn(`stopping unresponsive engine left by a previous session (pid ${pid})`); this.killTree(pid); }
    } catch { /* none */ }
    this.removePidFile();
  }
  removePidFile() { try { fs.rmSync(this.pidFile, { force: true }); } catch { /* ignore */ } }
  killTree(pid) {
    if (process.platform === 'win32') execFile('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true }, () => {});
    else { try { process.kill(pid, 'SIGTERM'); } catch { /* gone */ } }
  }

  /** Stop the engine only if VIPER started it (an engine you started yourself keeps running). */
  stopOwned() {
    if (!this.owned) return false;
    const { pid } = this.owned; this.owned = null;
    if (this.svc.settings.get('backend').stopOwnedOnExit === false) return false;
    this.log.info(`stopping the engine VIPER started (pid ${pid})`);
    this.killTree(pid); this.removePidFile();
    return true;
  }

  /** Pick the model to use and explain the choice. */
  async chooseModel(backend, hw) {
    const svc = this.svc;
    const installed = (await svc.models.listInstalled(true)).filter((m) => m.backend === backend && m.capabilities?.includes('chat') && !m.capabilities?.includes('embeddings'));
    const has = (id) => id && installed.find((m) => m.id === id || m.id === `${id}:latest` || m.alias === id);
    const roles = svc.settings.get('models'); const last = svc.settings.get('app').lastWorkingModel;
    if (roles.chat.model && (!roles.chat.backend || roles.chat.backend === backend) && has(roles.chat.model)) return { model: has(roles.chat.model).id, why: 'your selection' };
    const totalGB = hw?.ramGB || os.totalmem() / 1073741824;
    const fits = (m) => !m.sizeBytes || m.sizeBytes / 1073741824 <= totalGB * 0.45;
    let pick = null; let why = '';
    if (last?.model && last.backend === backend && has(last.model)) { pick = has(last.model); why = 'last model that worked'; }
    if (!pick) {
      const rec = recommend(hw, backend);
      const order = [rec.chat, ...OLLAMA_RECOMMENDED.filter((m) => m.roles.includes('chat')).map((m) => m.id)];
      // Prefer: fits in RAM, tool calling, the model recommended for this hardware, a known-good
      // general model; avoid vision-only and code-only models for conversation.
      const known = (m) => order.some((id) => m.id === id || m.id.startsWith(`${id}:`) || m.id.startsWith(id));
      const score = (m) => (fits(m) ? 10 : -10) + (m.capabilities.includes('tools') ? 4 : 0) - (m.capabilities.includes('vision') ? 3 : 0) - (m.capabilities.includes('code') ? 1 : 0) + (m.id.startsWith(rec.chat) ? 2 : 0) + (known(m) ? 1 : 0);
      pick = [...installed].sort((a, b) => score(b) - score(a))[0] || null;
      why = pick ? 'best installed model for this PC' : '';
      if (!pick) { const r = OLLAMA_RECOMMENDED.find((m) => m.id === rec.chat); return { model: null, recommended: rec.chat, recommendedSizeGB: r?.sizeGB }; }
    }
    const note = roles.chat.model && !has(roles.chat.model) ? `Your chosen model ${roles.chat.model} is no longer installed, so VIPER is using ${pick.id}. Choose another in Models.` : null;
    return { model: pick.id, why, note };
  }

  /**
   * Recover after the engine died, a request failed to connect or the model stopped responding.
   * Limited to 3 automatic recoveries in 10 minutes; after that VIPER shows the error and a Retry
   * button instead of restarting in a loop.
   */
  async recover(reason) {
    if (this.running) return this.running.then((s) => s.stage === 'ready');
    const now = Date.now();
    this.recoveries = this.recoveries.filter((t) => now - t < 600000);
    if (this.recoveries.length >= 3) {
      this.set('error', `The AI engine keeps failing (${reason}). Automatic recovery has paused — press Retry when ready.`, { error: reason, retry: true });
      return false;
    }
    this.recoveries.push(now);
    this.svc.bus.publish('models.recovering', { backend: this.state.backend, reason });
    const st = await this.run(`recovery: ${reason}`);
    if (st.stage === 'ready') this.svc.bus.publish('models.recovered', { backend: st.backend });
    else this.svc.bus.publish('models.recoveryFailed', { backend: st.backend, error: st.detail });
    return st.stage === 'ready';
  }

  watchdog(reason) {
    if (this.svc.settings.get('backend').autoRecover === false || this.stopped) return;
    setTimeout(() => this.recover(reason).catch(() => {}), 1000).unref?.();
  }

  /** Health events: if the engine disappears while VIPER is ready, reconnect automatically. */
  onHealth(h) {
    const b = this.svc.settings.get('backend').active;
    if (this.state.stage === 'ready' && h?.[b] && !h[b].ok && !this.running) this.watchdog(`${LABEL[b] || b} stopped responding`);
  }

  shutdown() { this.stopped = true; return this.stopOwned(); }
}

module.exports = { AIStartup, STAGES, GREETING };
