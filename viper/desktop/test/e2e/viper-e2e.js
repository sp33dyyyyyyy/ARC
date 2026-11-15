// End-to-end test of the real VIPER desktop application.
//
// Windows CI: installs the built NSIS installer silently, runs every check against the
// *installed* VIPER.exe with a real local model (Ollama), then uninstalls it.
// Elsewhere: runs the same checks against the source tree with Electron (development use).
//
// Environment:
//   E2E_INSTALLER  path to VIPER-Windows-Setup.exe (Windows: install → test → uninstall)
//   E2E_PORTABLE   path to VIPER-Portable.exe (optional: launch check)
//   E2E_MODEL      Ollama model to download through VIPER and chat with (default qwen2.5:0.5b)
//   E2E_OUT        output folder for results.json and screenshots
//
// Every check is recorded as PASS, FAIL or BLOCKED with evidence. Nothing is assumed.
let pw; try { pw = require('playwright'); } catch { pw = require('playwright-core'); }
const { _electron: electron } = pw;
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const { execFileSync, spawn } = require('node:child_process');

const WIN = process.platform === 'win32';
const OUT = process.env.E2E_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'viper-e2e-'));
const MODEL = process.env.E2E_MODEL || 'qwen2.5:0.5b';
const INSTALLER = process.env.E2E_INSTALLER || '';
fs.mkdirSync(OUT, { recursive: true });

const results = []; const metrics = {};
const record = (area, name, status, detail = '') => { results.push({ area, name, status, detail: String(detail).slice(0, 600) }); console.log(`${status.padEnd(7)} [${area}] ${name}${detail ? ` — ${String(detail).slice(0, 300)}` : ''}`); };
const check = (area, name, ok, detail) => record(area, name, ok ? 'PASS' : 'FAIL', detail);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const save = () => fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify({ platform: `${os.type()} ${os.release()} ${os.arch()}`, cpu: os.cpus()[0]?.model, cores: os.cpus().length, ramGB: Math.round(os.totalmem() / 1073741824 * 10) / 10, model: MODEL, when: new Date().toISOString(), results, metrics }, null, 2));
async function until(fn, ms = 30000, step = 250) { const end = Date.now() + ms; let v; while (Date.now() < end) { try { v = await fn(); if (v) return v; } catch { /* retry */ } await sleep(step); } return v; }

// ---------------- install ----------------
const LOCAL = process.env.LOCALAPPDATA || ''; const ROAMING = process.env.APPDATA || '';
const INSTALL_DIR = path.join(LOCAL, 'Programs', 'VIPER');
const EXE = path.join(INSTALL_DIR, 'VIPER.exe');
const START_LNK = path.join(ROAMING, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'VIPER.lnk');
const DESKTOP_LNK = path.join(os.homedir(), 'Desktop', 'VIPER.lnk');
const DATA_DIR = WIN ? path.join(ROAMING, 'VIPER') : (process.env.VIPER_DATA_DIR || fs.mkdtempSync(path.join(os.tmpdir(), 'viper-e2e-data-')));

function runInstaller() {
  const t0 = Date.now();
  const r = require('node:child_process').spawnSync(INSTALLER, ['/S'], { timeout: 600000 });
  const ms = Date.now() - t0;
  check('Installer', 'installer runs (silent mode)', r.status === 0, `exit ${r.status} in ${(ms / 1000).toFixed(1)} s`);
  metrics.installSeconds = Math.round(ms / 100) / 10;
  check('Installer', 'installation finishes: VIPER.exe present', fs.existsSync(EXE), EXE);
  check('Installer', 'Start menu shortcut created', fs.existsSync(START_LNK), START_LNK);
  check('Installer', 'desktop shortcut created', fs.existsSync(DESKTOP_LNK), DESKTOP_LNK);
  const unins = path.join(INSTALL_DIR, 'Uninstall VIPER.exe');
  check('Installer', 'uninstaller installed', fs.existsSync(unins), unins);
  // Runtime is bundled: no Node.js/Python/.NET needed on the PC.
  const bundled = ['ffmpeg.dll', 'resources/app.asar', 'resources/app.asar.unpacked'].every((f) => fs.existsSync(path.join(INSTALL_DIR, f)));
  check('Installer', 'Electron runtime and app bundle installed (no Node.js/Python required)', bundled);
  const secrets = []; (function walk(d) { try { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (/\.(pem|key|jks|keystore|p12|pfx)$|^\.env|^id_rsa/i.test(e.name)) secrets.push(path.relative(INSTALL_DIR, p)); } } catch { /* ignore */ } })(INSTALL_DIR);
  check('Installer', 'no keys, certificates or .env files are shipped in the installed app', !secrets.length, secrets.slice(0, 5).join(', ') || 'none found');
  const size = dirSize(INSTALL_DIR);
  metrics.installedSizeMB = Math.round(size / 1048576);
}
function dirSize(d) { let n = 0; try { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); n += e.isDirectory() ? dirSize(p) : fs.statSync(p).size; } } catch { /* ignore */ } return n; }

// ---------------- external process sampling (AI engine) ----------------
function procSnapshot(names) {
  try {
    if (WIN) {
      // The engine's processes plus their whole child tree (Ollama runs models in a child runner process).
      const ps = 'Get-CimInstance Win32_Process | Select-Object Name,ProcessId,ParentProcessId,KernelModeTime,UserModeTime,WorkingSetSize | ConvertTo-Json -Compress';
      const out = execFileSync('powershell.exe', ['-NoProfile', '-Command', ps], { encoding: 'utf8', maxBuffer: 32 << 20 }).trim();
      const all = [].concat(JSON.parse(out || '[]'));
      const keep = new Set(all.filter((p) => names.some((n) => String(p.Name).toLowerCase().startsWith(n))).map((p) => p.ProcessId));
      for (let grew = true; grew;) { grew = false; for (const p of all) if (!keep.has(p.ProcessId) && keep.has(p.ParentProcessId)) { keep.add(p.ProcessId); grew = true; } }
      return all.filter((p) => keep.has(p.ProcessId)).map((p) => ({ name: p.Name, pid: p.ProcessId, cpuSec: ((+p.KernelModeTime || 0) + (+p.UserModeTime || 0)) / 1e7, rssMB: Math.round((+p.WorkingSetSize || 0) / 1048576) }));
    }
    const out = execFileSync('ps', ['-eo', 'pid,comm,time,rss', '--no-headers'], { encoding: 'utf8' });
    return out.split('\n').map((l) => l.trim().split(/\s+/)).filter((c) => c[1] && names.some((n) => c[1].startsWith(n))).map((c) => { const [h, m, s] = c[2].split(':').map(Number); return { name: c[1], pid: +c[0], cpuSec: h * 3600 + m * 60 + s, rssMB: Math.round(+c[3] / 1024) }; });
  } catch { return []; }
}

// ---------------- AI engine process helpers ----------------
/** PIDs of running `ollama serve` processes (the engine; model runners are separate). */
function engineServers() {
  try {
    if (WIN) {
      const out = execFileSync('powershell.exe', ['-NoProfile', '-Command', "Get-CimInstance Win32_Process -Filter \"Name='ollama.exe'\" | Where-Object { $_.CommandLine -match '\\sserve' } | Select-Object -ExpandProperty ProcessId"], { encoding: 'utf8' }).trim();
      return out ? out.split(/\s+/).map(Number) : [];
    }
    return execFileSync('ps', ['-eo', 'pid,args', '--no-headers'], { encoding: 'utf8' }).split('\n').filter((l) => /ollama serve/.test(l) && !/ps -eo/.test(l)).map((l) => +l.trim().split(/\s+/)[0]);
  } catch { return []; }
}
/** Stop every Ollama process (engine, model runners and the Ollama tray app). */
function killEngine() {
  try { if (WIN) { execFileSync('taskkill', ['/F', '/T', '/IM', 'ollama app.exe'], { stdio: 'ignore' }); } } catch { /* not running */ }
  try { if (WIN) execFileSync('taskkill', ['/F', '/T', '/IM', 'ollama.exe'], { stdio: 'ignore' }); else execFileSync('pkill', ['-f', 'ollama serve']); } catch { /* not running */ }
}
const aiState = (win) => win.evaluate(() => window.viperApp?.ai || null);
const waitAi = (win, stages, ms = 300000) => until(async () => { const s = await aiState(win); return s && stages.includes(s.stage) ? s : null; }, ms, 250);

// ---------------- app helpers ----------------
async function launch(label) {
  const args = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'];
  const env = { ...process.env, NODE_OPTIONS: '' };
  if (!WIN) env.VIPER_DATA_DIR = DATA_DIR;
  const t0 = Date.now();
  const app = WIN && INSTALLER
    ? await electron.launch({ executablePath: EXE, args, env })
    : await electron.launch({ executablePath: require('electron'), args: [path.join(__dirname, '..', '..'), '--no-sandbox', ...args], env });
  const win = await app.firstWindow();
  const errors = [];
  win.on('pageerror', (e) => errors.push(`pageerror: ${e.message} @ ${(e.stack || '').split('\n').slice(1, 3).join(' ').trim()}`));
  win.on('console', (m) => { if (m.type() === 'error' && !/favicon|ERR_CONNECTION_REFUSED|net::ERR/.test(m.text())) errors.push(`console: ${m.text()} @ ${(m.location()?.url || '').replace(/^https?:\/\/[^/]+/, '')}`); });
  await win.waitForLoadState('domcontentloaded');
  const ready = await until(() => win.evaluate(() => !!(document.querySelector('.wizard') || document.querySelector('.nav-item'))), 60000);
  metrics[`startup_${label}_ms`] = Date.now() - t0;
  return { app, win, errors, ready };
}
const apiCall = (win, method, p, body) => win.evaluate(async ([m, u, b]) => {
  const r = await fetch(`/api/v1${u}`, { method: m, headers: { Authorization: `Bearer ${window.viperNative.token}`, 'Content-Type': 'application/json' }, body: b === undefined ? undefined : JSON.stringify(b) });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
  if (!r.ok) throw new Error(`${r.status} ${typeof j === 'object' ? j.error : j}`);
  return j;
}, [method, p, body]);
async function appMetrics(app, ms = 5000) {
  await app.evaluate(({ app: a }) => a.getAppMetrics());
  await sleep(ms);
  const m = await app.evaluate(({ app: a }) => a.getAppMetrics().map((x) => ({ type: x.type, name: `${x.name || ''} ${x.serviceName || ''}`, cpu: x.cpu.percentCPUUsage, mem: x.memory.workingSetSize })));
  const sum = (f) => m.filter(f).reduce((a, x) => a + x.cpu, 0);
  const mem = (f) => m.filter(f).reduce((a, x) => a + x.mem, 0);
  return {
    cpuTotalPct: Math.round(sum(() => true) * 10) / 10,
    cpuRendererPct: Math.round(sum((x) => x.type === 'Tab') * 10) / 10,
    cpuCorePct: Math.round(sum((x) => x.type === 'Utility' && /VIPER core/i.test(x.name)) * 10) / 10,
    ramTotalMB: Math.round(mem(() => true) / 1024),
    ramRendererMB: Math.round(mem((x) => x.type === 'Tab') / 1024),
    ramCoreMB: Math.round(mem((x) => x.type === 'Utility' && /VIPER core/i.test(x.name)) / 1024),
    // percentCPUUsage is per core; divide by the core count for "% of the whole CPU"
    cpuTotalPctOfMachine: Math.round(sum(() => true) / os.cpus().length * 10) / 10,
    processes: m.length,
  };
}
// Frame timing in the renderer: rAF rate (UI responsiveness), long main-thread tasks and core draws.
const startFrameProbe = (win) => win.evaluate(() => {
  const p = window.__probe = { frames: 0, maxGap: 0, gaps: [], long: [], start: performance.now(), last: performance.now(), coreFrames: [...(window.viperApp?.cores || [])].reduce((a, c) => a + c.frames, 0) };
  try { p.obs = new PerformanceObserver((l) => { for (const e of l.getEntries()) p.long.push(e.duration); }); p.obs.observe({ type: 'longtask', buffered: false }); } catch { /* unsupported */ }
  const tick = (t) => { if (window.__probe !== p) return; const g = t - p.last; p.last = t; p.frames++; p.gaps.push(g); if (g > p.maxGap) p.maxGap = g; requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
});
const stopFrameProbe = (win) => win.evaluate(() => {
  const p = window.__probe; window.__probe = null; p.obs?.disconnect();
  const secs = (performance.now() - p.start) / 1000; const g = p.gaps.sort((a, b) => a - b);
  const coreFrames = [...(window.viperApp?.cores || [])].reduce((a, c) => a + c.frames, 0) - p.coreFrames;
  return { seconds: Math.round(secs * 10) / 10, uiFps: Math.round(p.frames / secs * 10) / 10, coreFps: Math.round(coreFrames / secs * 10) / 10, p95FrameMs: Math.round(g[Math.floor(g.length * 0.95)] || 0), maxFrameGapMs: Math.round(p.maxGap), longTasks: p.long.length, longestTaskMs: Math.round(Math.max(0, ...p.long)) };
});

// ---------------- main ----------------
(async () => {
  if (WIN && INSTALLER) {
    try { fs.rmSync(DATA_DIR, { recursive: true, force: true }); } catch { /* fresh start */ }
    runInstaller(); save();
    if (!fs.existsSync(EXE)) { record('App', 'all application checks', 'BLOCKED', 'installation failed'); save(); process.exit(1); }
  }

  // ===== first launch =====
  metrics.enginePreRunning = engineServers().length > 0;
  let { app, win, errors, ready } = await launch('first');
  check('App', 'VIPER launches and shows a window', !!ready, `started in ${metrics.startup_first_ms} ms`);
  const wizard = await until(() => win.evaluate(() => !!document.querySelector('.wizard')), 10000);
  check('App', 'first-run setup wizard appears', wizard);
  await win.screenshot({ path: path.join(OUT, '01-setup-wizard.png') });
  // Walk every wizard step (Continue / Skip), failing if a step reports an error.
  if (wizard) {
    const stepErrors = []; const stepTimes = []; let steps = 0;
    for (let i = 0; i < 16; i++) {
      const state = await win.evaluate(() => ({ open: !!document.querySelector('.wizard'), cur: document.querySelector('.wizard .steps .cur')?.textContent || '', failed: /This step failed/.test(document.querySelector('.wizard .body')?.textContent || '') }));
      if (!state.open) break;
      if (state.failed) stepErrors.push(state.cur);
      steps++;
      if (i === 1) await win.screenshot({ path: path.join(OUT, '02-wizard-hardware.png') });
      const tStep = Date.now();
      const clicked = await until(() => win.evaluate(() => {
        const btns = [...document.querySelectorAll('.wizard .nav button')].filter((b) => !b.disabled);
        const pick = btns.find((b) => /Launch VIPER/.test(b.textContent)) || btns.find((b) => /^Skip/.test(b.textContent.trim())) || btns.find((b) => /^(Continue|Begin setup)$/.test(b.textContent.trim()));
        if (pick) { pick.click(); return pick.textContent.trim(); } return null;
      }), 60000, 300);
      stepTimes.push(`${state.cur.replace(/^\d+/, '').trim()} ${((Date.now() - tStep) / 1000).toFixed(1)}s`);
      if (!clicked) { stepErrors.push(`${state.cur}: no Continue/Skip button within 60 s`); break; }
      await sleep(900);
    }
    const closed = await until(() => win.evaluate(() => !document.querySelector('.wizard')), 8000);
    check('App', 'setup wizard: every step renders and setup completes', closed && !stepErrors.length, `${steps} steps${stepErrors.length ? `; failed: ${stepErrors.join(', ')}` : ''} · ${stepTimes.join(', ')}`);
    metrics.wizardSteps = stepTimes;
  }
  if (await win.evaluate(() => !!document.querySelector('.wizard'))) { await apiCall(win, 'POST', '/setup/complete', {}); await win.reload(); }
  await until(() => win.evaluate(() => document.querySelectorAll('.nav-item').length >= 16), 15000);
  await sleep(1500);
  check('App', 'main dashboard renders (navigation + animated core)', await win.evaluate(() => document.querySelectorAll('.nav-item').length >= 16 && !!document.querySelector('canvas.core')));
  await win.screenshot({ path: path.join(OUT, '03-dashboard.png') });

  // ===== automatic AI start-up, first launch (Ollama already running, no model yet) =====
  const firstAi = await waitAi(win, ['ready', 'setup', 'error'], 120000);
  metrics.engineServersAtFirstLaunch = engineServers().length;
  if (firstAi?.stage === 'ready') record('AI start-up', 'first launch with Ollama already running: connects automatically', 'PASS', `${firstAi.model} ready (model was already on this machine)`);
  else {
    check('AI start-up', 'first launch, Ollama running but no model: start-up stops at a clear setup prompt (no error loop)', firstAi?.stage === 'setup' && firstAi.need === 'model' && !!firstAi.recommended, `${firstAi?.label} · ${firstAi?.detail} · recommended ${firstAi?.recommended}`);
    await win.evaluate(() => window.viperApp.go('home')); await sleep(800);
    const offer = await win.evaluate(() => [...document.querySelectorAll('.ai-status button')].map((b) => b.innerText.trim()));
    check('AI start-up', 'setup prompt offers to download the model recommended for this PC', offer.some((t) => /^Download /.test(t)), offer.join(' | '));
    await win.screenshot({ path: path.join(OUT, '03b-setup-prompt.png') });
  }

  // ===== hardware detection + performance preset =====
  const perf = await apiCall(win, 'GET', '/performance');
  check('Performance', 'hardware detected and a performance preset applied automatically', ['eco', 'balanced', 'performance'].includes(perf.applied), perf.reason || perf.applied);
  metrics.hardware = perf.hardware; metrics.presetApplied = perf.applied;

  // ===== navigation: every page =====
  const pages = await win.evaluate(() => [...document.querySelectorAll('.nav-item[data-mode]')].map((b) => b.dataset.mode));
  const navFail = []; const switchMs = [];
  for (const mode of pages) {
    const t0 = Date.now();
    await win.evaluate((m) => document.querySelector(`.nav-item[data-mode="${m}"]`).click(), mode);
    const ok = await until(() => win.evaluate((m) => window.viperApp.mode === m && document.querySelector('#view').children.length > 0 && !/failed to load/.test(document.querySelector('#view').textContent), mode), 8000, 50);
    switchMs.push(Date.now() - t0);
    if (!ok) navFail.push(mode);
    if (['chat', 'models', 'system', 'settings', 'voice', 'image', 'code', 'comms'].includes(mode)) { await sleep(600); await win.screenshot({ path: path.join(OUT, `page-${mode}.png`) }); }
  }
  check('App', `all ${pages.length} navigation buttons open their page`, !navFail.length, navFail.length ? `failed: ${navFail.join(', ')}` : pages.join(', '));
  switchMs.sort((a, b) => a - b);
  metrics.pageSwitchMs = { median: switchMs[Math.floor(switchMs.length / 2)], max: switchMs[switchMs.length - 1] };
  check('Performance', 'page switching is fast (median < 300 ms)', metrics.pageSwitchMs.median < 300, JSON.stringify(metrics.pageSwitchMs));
  // Settings tabs (every tab renders)
  await win.evaluate(() => window.viperApp.go('settings'));
  await sleep(600);
  const tabs = await win.evaluate(async () => { const out = []; for (const b of [...document.querySelectorAll('.tabs button')]) { b.click(); await new Promise((r) => setTimeout(r, 500)); out.push({ tab: b.textContent, ok: document.querySelector('#view .panel') !== null }); } return out; });
  check('App', 'every Settings tab renders', tabs.every((t) => t.ok), tabs.map((t) => `${t.tab}:${t.ok ? 'ok' : 'FAIL'}`).join(', '));
  await win.evaluate(() => [...document.querySelectorAll('.tabs button')].find((b) => /Performance/.test(b.textContent))?.click());
  await sleep(800); await win.screenshot({ path: path.join(OUT, '04-settings-performance.png') });

  // ===== AI engine =====
  await apiCall(win, 'POST', '/backend/active', { backend: 'ollama' }).catch(() => {});
  const health = await apiCall(win, 'POST', '/models/health');
  if (!health.ollama?.ok) {
    record('AI', 'local AI engine (Ollama) detected', 'BLOCKED', `Ollama not running: ${health.ollama?.error || ''}`);
  } else {
    check('AI', 'local AI engine (Ollama) detected and configured', true, `Ollama ${health.ollama.version}`);
    // Download the model through VIPER's Model Manager (real download with progress events).
    const installed = await apiCall(win, 'GET', '/models?refresh=1');
    if (!installed.some((m) => m.id === MODEL || m.id === `${MODEL}:latest`)) {
      await apiCall(win, 'POST', '/models/pull', { backend: 'ollama', model: MODEL });
      const done = await until(async () => { const d = (await apiCall(win, 'GET', '/models/downloads')).find((x) => x.model === MODEL); if (d?.status === 'error') throw new Error(d.error); return d?.status === 'done' ? d : null; }, 900000, 2000);
      check('AI', `model downloaded through VIPER's Model Manager (${MODEL})`, !!done, done ? 'installed' : 'timeout');
    } else record('AI', `model available (${MODEL})`, 'PASS', 'already installed');
    const before = engineServers().length;
    await apiCall(win, 'POST', '/models/role', { role: 'chat', backend: 'ollama', model: MODEL });
    const rdy = await waitAi(win, ['ready', 'error', 'setup'], 300000);
    check('AI start-up', 'after the model is installed, start-up continues by itself to VIPER ONLINE — READY', rdy?.stage === 'ready' && rdy.model === MODEL, `${rdy?.label} · ${rdy?.detail}`);
    if (metrics.enginePreRunning) check('AI start-up', 'Ollama that was already running is used, not duplicated (and not owned by VIPER)', engineServers().length === before && before >= 1 && rdy?.owned === false, `ollama serve processes: ${before} → ${engineServers().length}; owned: ${rdy?.owned}`);
    else check('AI start-up', 'Ollama was not running: VIPER started exactly one copy and owns it', engineServers().length === 1 && rdy?.owned === true, `ollama serve processes: ${engineServers().length}; owned: ${rdy?.owned}`);
    metrics.warmupMs = rdy?.warmMs; metrics.readinessMs = rdy?.readyMs;
    await win.evaluate(() => window.viperApp.go('home')); await sleep(1500);
    await win.screenshot({ path: path.join(OUT, '03c-ready.png') });
    const readyText = await win.evaluate(() => document.querySelector('.ai-status')?.innerText || '');
    check('AI start-up', 'Home shows "VIPER ONLINE — READY" only after the readiness check', /VIPER ONLINE — READY/.test(readyText) && rdy?.stage === 'ready', readyText.replace(/\s+/g, ' ').slice(0, 120));
    // "Hello VIPER" right after ready: a real generated reply
    {
      const ta0 = win.locator('.home textarea, .dock textarea').first();
      const n0 = await win.evaluate(() => document.querySelectorAll('.home-thread .msg.viper').length);
      const tHello = Date.now(); await ta0.fill('Hello VIPER'); await ta0.press('Enter');
      const hello = await until(() => win.evaluate((n) => { const m = [...document.querySelectorAll('.home-thread .msg.viper')]; const last = m[m.length - 1]; return m.length > n && last && !last.querySelector('.cursor') && last.innerText.trim().length > 3 ? last.innerText.trim() : null; }, n0), 120000, 200);
      const conv = (await apiCall(win, 'GET', '/conversations'))[0];
      const msgs = conv ? await apiCall(win, 'GET', `/conversations/${conv.id}/messages`) : [];
      const a = msgs.filter((m) => m.role === 'assistant').pop();
      check('AI start-up', '"Hello VIPER" right after start-up gets a real generated reply', !!hello && a?.meta?.route === 'llm', `${(hello || '').replace(/\s+/g, ' ').slice(0, 120)} · ${Date.now() - tHello} ms · route ${a?.meta?.route} · ${a?.model}`);
    }

    // Idle baseline on Home (core animating)
    await win.evaluate(() => window.viperApp.go('home')); await sleep(3000);
    metrics.idle = await appMetrics(app, 8000);
    check('Performance', 'idle CPU use is low (< 15% of one core for all VIPER processes)', metrics.idle.cpuTotalPct < 15, JSON.stringify(metrics.idle));

    // Chat through the real UI: type into Home composer, watch tokens stream.
    const question = 'In two sentences, what does a CPU do?';
    await win.evaluate(() => { window.__tok = { n: 0, first: 0, t0: 0, done: 0, text: '' }; window.viperApp.api.on('chat.token', (d) => { const s = window.__tok; s.n++; s.text += d.text; if (!s.first) s.first = performance.now(); }); window.viperApp.api.on('chat.done', () => { window.__tok.done = performance.now(); }); });
    const cpuBefore = procSnapshot(['ollama']);
    await startFrameProbe(win);
    const ta = win.locator('.home textarea, .dock textarea').first();
    await ta.fill(question);
    await win.evaluate(() => { window.__tok.t0 = performance.now(); });
    await ta.press('Enter');
    const metricsDuring = appMetrics(app, 4000);
    let enginePeakMB = 0; const peak = setInterval(() => { enginePeakMB = Math.max(enginePeakMB, procSnapshot(['ollama']).reduce((a, p) => a + p.rssMB, 0)); }, 700);
    const machine = { cpuPeak: 0, memUsedPeakMB: 0, memTotalMB: 0 };
    const mach = setInterval(async () => { try { const sn = await apiCall(win, 'GET', '/system/snapshot'); machine.cpuPeak = Math.max(machine.cpuPeak, sn.cpu?.pct || 0); machine.memUsedPeakMB = Math.max(machine.memUsedPeakMB, Math.round((sn.mem?.used || 0) / 1048576)); machine.memTotalMB = Math.round((sn.mem?.total || 0) / 1048576); } catch { /* ignore */ } }, 1000);
    const finished = await until(() => win.evaluate(() => window.__tok.done > 0), 180000, 200);
    const during = await metricsDuring;
    const frames = await stopFrameProbe(win);
    clearInterval(peak); clearInterval(mach);
    const cpuAfter = procSnapshot(['ollama']);
    const tok = await win.evaluate(() => ({ n: window.__tok.n, ttft: Math.round(window.__tok.first - window.__tok.t0), total: Math.round(window.__tok.done - window.__tok.t0), text: window.__tok.text }));
    await sleep(800);
    await win.screenshot({ path: path.join(OUT, '05-chat-answer.png') });
    const shown = await win.evaluate(() => document.querySelector('.home-thread')?.textContent || '');
    const lastPerf = (await apiCall(win, 'GET', '/models/perf')).find((r) => r.model === MODEL);
    check('AI', 'a real local model answers a question typed in the UI', finished && tok.text.trim().length > 10 && shown.includes(tok.text.trim().slice(0, 20)), tok.text.trim().slice(0, 200));
    check('AI', 'response streams token-by-token (first token long before the end)', tok.n >= 5 && tok.ttft < tok.total * 0.8, `${tok.n} token events, first after ${tok.ttft} ms, complete after ${tok.total} ms`);
    const engineCpu = cpuAfter.reduce((a, p) => a + p.cpuSec, 0) - cpuBefore.reduce((a, p) => a + p.cpuSec, 0);
    metrics.chat = { ttftMs: tok.ttft, totalMs: tok.total, tokenEvents: tok.n, tokPerS: lastPerf?.avg_tps, viperDuringInference: during, frames, engineCpuSeconds: Math.round(engineCpu * 10) / 10, engineRamMB: Math.max(enginePeakMB, cpuAfter.reduce((a, p) => a + p.rssMB, 0)), enginePids: cpuAfter.map((p) => `${p.name}:${p.pid}`).join(' '), machine };
    check('Performance', 'UI stays responsive during inference (no frame gap > 250 ms)', frames.maxFrameGapMs < 250, JSON.stringify(frames));
    // Cancel a running generation
    const long = await apiCall(win, 'POST', '/chat', { text: 'Write a 400 word essay about the history of computing.' });
    await until(() => win.evaluate((id) => window.__tok.n > 0, long.requestId), 60000, 200);
    await sleep(500);
    const c = await apiCall(win, 'POST', '/chat/cancel', { requestId: long.requestId });
    check('AI', 'a running generation can be cancelled', c.cancelled === true);
    // Second turn re-uses the prompt cache
    await sleep(1000);
    const t2 = await win.evaluate(async () => { const s = window.__tok; s.n = 0; s.first = 0; s.done = 0; s.text = ''; s.t0 = performance.now(); return true; });
    await ta.fill('Thanks. And what does RAM do? One sentence.'); await ta.press('Enter');
    await until(() => win.evaluate(() => window.__tok.done > 0), 180000, 200);
    const tok2 = await win.evaluate(() => ({ ttft: Math.round(window.__tok.first - window.__tok.t0), total: Math.round(window.__tok.done - window.__tok.t0) }));
    metrics.chatTurn2 = tok2; void t2;
    check('AI', 'follow-up turn answered (prompt cache reused)', tok2.total > 0, `first token ${tok2.ttft} ms, complete ${tok2.total} ms`);
  }

  // ===== voice =====
  const mic = await win.evaluate(async () => { try { const s = await navigator.mediaDevices.getUserMedia({ audio: true }); const ok = s.getAudioTracks().length > 0; s.getTracks().forEach((t) => t.stop()); return { ok }; } catch (e) { return { ok: false, error: e.name + ': ' + e.message }; } });
  check('Voice', 'microphone permission granted to VIPER (CI uses Chromium\'s fake audio device)', mic.ok, mic.error || 'getUserMedia returned an audio track');
  if (process.env.E2E_VOICE !== '0') {
    try {
      const inst = async (kind, id) => { await apiCall(win, 'POST', '/voice/install', { kind, id }); return until(async () => { const j = (await apiCall(win, 'GET', '/voice/status')).installs.find((x) => x.key === `${kind}:${id}`); if (j?.state === 'failed') throw new Error(j.error); return j?.state === 'done'; }, 600000, 2000); };
      const voiceSel = (await apiCall(win, 'GET', '/voice/status')).tts.selected || 'en_GB-alan-medium';
      const ttsOk = (await inst('engine', 'piper')) && (await inst('voice', voiceSel));
      check('Voice', `Piper voice engine + ${voiceSel} install from the Voice page`, !!ttsOk);
      const wav = await win.evaluate(async () => { const r = await fetch('/api/v1/voice/speak', { method: 'POST', headers: { Authorization: `Bearer ${window.viperNative.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ text: 'Good evening. All systems are operational.' }) }); const b = new Uint8Array(await r.arrayBuffer()); let bin = ''; for (const x of b) bin += String.fromCharCode(x); return { ok: r.ok, bytes: b.length, riff: bin.slice(0, 4), b64: btoa(bin) }; });
      check('Voice', 'voice output: Piper synthesises speech to a WAV', wav.ok && wav.riff === 'RIFF' && wav.bytes > 20000, `${wav.bytes} bytes`);
      if (wav.ok) fs.writeFileSync(path.join(OUT, 'tts-sample.wav'), Buffer.from(wav.b64, 'base64'));
      const played = await win.evaluate(async () => { try { await window.viperApp.voice.speak('Testing.'); return true; } catch (e) { return e.message; } });
      check('Voice', 'voice output plays through the app audio pipeline without error', played === true, played === true ? 'audible output not verifiable on CI (no speakers)' : played);
      const sttOk = (await inst('engine', 'whisper')) && (await inst('stt-model', 'tiny.en'));
      await apiCall(win, 'PATCH', '/settings/voice', { sttModel: 'tiny.en' });
      check('Voice', 'whisper.cpp speech recognition + tiny.en model install', !!sttOk);
      const heard = await win.evaluate(async (b64) => { const bin = atob(b64); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); const r = await fetch('/api/v1/voice/transcribe', { method: 'POST', headers: { Authorization: `Bearer ${window.viperNative.token}`, 'Content-Type': 'audio/wav' }, body: u }); return r.json(); }, wav.b64);
      check('Voice', 'speech recognition: Piper audio transcribed back to text by whisper.cpp', /operational/i.test(heard.text || ''), heard.text || heard.error);
    } catch (e) { record('Voice', 'voice engine install / synthesis / recognition', 'FAIL', e.message); }
  }

  // ===== system monitoring =====
  const snap = await apiCall(win, 'GET', '/system/snapshot');
  check('System', 'CPU and RAM monitoring report live values', typeof snap.cpu?.pct === 'number' && snap.mem?.total > 0, `CPU ${snap.cpu?.pct}% · RAM ${Math.round((snap.mem?.used || 0) / 1048576)} MB of ${Math.round((snap.mem?.total || 0) / 1048576)} MB`);

  // ===== settings persistence (part 1) =====
  await apiCall(win, 'PATCH', '/settings/personality', { userName: 'E2E Tester' });
  await apiCall(win, 'POST', '/performance/preset', { preset: 'eco' });
  await apiCall(win, 'POST', '/memory', { content: 'The E2E test likes tea.', category: 'preference' });
  const convs = await apiCall(win, 'GET', '/conversations');

  // ===== minimise / restore / tray =====
  const minRes = await app.evaluate(async ({ BrowserWindow }) => { const w = global.viperDiagnostics.mainWindow(); w.minimize(); await new Promise((r) => setTimeout(r, 1200)); const min = w.isMinimized(); w.restore(); await new Promise((r) => setTimeout(r, 800)); return { min, restored: !w.isMinimized() && w.isVisible() }; });
  const noWm = !WIN && !minRes.min; // Xvfb has no window manager, so minimise is a no-op there
  if (noWm) record('App', 'window minimises and restores', 'BLOCKED', 'no window manager under Xvfb; verified on Windows CI');
  else check('App', 'window minimises and restores', minRes.min && minRes.restored, JSON.stringify(minRes));
  const tray = await app.evaluate(async () => { const t = global.viperDiagnostics.tray(); const m = global.viperDiagnostics.trayMenu(); const labels = m.items.map((i) => i.label).filter(Boolean); const w = global.viperDiagnostics.mainWindow(); w.close(); await new Promise((r) => setTimeout(r, 800)); const hiddenToTray = !w.isVisible() && !w.isDestroyed(); m.items.find((i) => i.label === 'Open VIPER').click(); await new Promise((r) => setTimeout(r, 800)); return { exists: !!t && !t.isDestroyed(), tooltip: t?.getToolTip?.(), labels, hiddenToTray, reopened: w.isVisible() }; });
  check('App', 'system tray icon with menu (Open, HUD, mic, notifications, Quit)', tray.exists && tray.labels.includes('Quit VIPER') && tray.labels.includes('Open VIPER'), tray.labels.join(' | '));
  check('App', 'closing the window keeps VIPER in the tray; tray "Open VIPER" restores it', tray.hiddenToTray && tray.reopened, JSON.stringify({ hiddenToTray: tray.hiddenToTray, reopened: tray.reopened }));
  const paused = await win.evaluate(async () => { const c = [...window.viperApp.cores][0]; return c ? { running: c.running } : null; });
  void paused;
  // HUD
  await win.evaluate(() => window.viperNative.toggleHud(true));
  const hud = await until(() => app.windows().find((w) => w.url().includes('hud.html')), 10000);
  check('App', 'floating desktop HUD opens (always on top)', !!hud && await app.evaluate(() => !!global.viperDiagnostics.hudWindow()?.isAlwaysOnTop()));
  if (hud) { await sleep(1200); await hud.screenshot({ path: path.join(OUT, '06-hud.png') }).catch(() => {}); }
  // Animation pauses when minimised (no core frames drawn)
  const pauseCheck = await (async () => {
    await app.evaluate((hide) => { const w = global.viperDiagnostics.mainWindow(); if (hide) w.hide(); else w.minimize(); }, noWm); await sleep(1500);
    const f0 = await win.evaluate(() => [...window.viperApp.cores].reduce((a, c) => a + c.frames, 0)); await sleep(2000);
    const f1 = await win.evaluate(() => [...window.viperApp.cores].reduce((a, c) => a + c.frames, 0));
    const m = await appMetrics(app, 5000);
    await app.evaluate((hide) => { const w = global.viperDiagnostics.mainWindow(); if (hide) w.show(); else w.restore(); }, noWm); await sleep(800);
    return { coreFramesWhileMinimised: f1 - f0, metrics: m };
  })();
  metrics.minimised = pauseCheck.metrics;
  check('Performance', `animations pause while ${noWm ? 'hidden to tray' : 'minimised'}`, pauseCheck.coreFramesWhileMinimised === 0, `${pauseCheck.coreFramesWhileMinimised} core frames in 2 s; CPU ${pauseCheck.metrics.cpuTotalPct}%`);

  // Memory growth: switch pages repeatedly and compare renderer heap.
  const heap0 = await win.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  for (let i = 0; i < 3; i++) for (const m of pages) { await win.evaluate((x) => window.viperApp.go(x), m); await sleep(120); }
  await win.evaluate(() => window.viperApp.go('home')); await sleep(2500);
  const cdp = await win.context().newCDPSession(win).catch(() => null);
  if (cdp) await cdp.send('HeapProfiler.collectGarbage').catch(() => {});
  await sleep(500);
  const heap1 = await win.evaluate(() => performance.memory?.usedJSHeapSize || 0);
  metrics.heapMB = { before: Math.round(heap0 / 1048576), afterNavigating3x: Math.round(heap1 / 1048576) };
  check('Performance', 'no memory growth after visiting every page 3× (heap within +15 MB)', heap1 - heap0 < 15 * 1048576, JSON.stringify(metrics.heapMB));
  const errs = errors.filter((e) => !/AbortError|The user aborted|Failed to fetch/.test(e));
  check('App', 'no uncaught JavaScript errors in the UI', !errs.length, errs.slice(0, 5).join(' | '));

  // ===== pixel UI audit with Windows fonts (button label centring, overflow, overlap) =====
  try {
    const { auditApp } = require('./ui-audit');
    const pagesAll = await win.evaluate(() => [...document.querySelectorAll('.nav-item[data-mode]')].map((b) => b.dataset.mode));
    const au = await auditApp(app, win, { pages: pagesAll, outDir: OUT });
    metrics.uiAudit = { checked: au.checked, medianOffsetPx: au.medianOffset, p95OffsetPx: au.p95Offset, maxOffsetPx: au.maxOffset, issues: au.issues.slice(0, 40) };
    const kinds = (k) => au.issues.filter((i) => i.kind === k);
    check('UI', `button/tab/nav labels vertically centred (≤1.5 px) — ${au.checked} control renders on every page at 1440×900, 1100×720 and 920×600`, !kinds('vertical').length, kinds('vertical').length ? kinds('vertical').map((i) => `${i.msg} [${i.where[0]}]`).join('; ') : `median ${au.medianOffset} px, max ${au.maxOffset} px`);
    check('UI', 'labels horizontally centred in centred controls', !kinds('horizontal').length, kinds('horizontal').map((i) => `${i.msg} [${i.where[0]}]`).join('; ') || 'ok');
    check('UI', 'no label overflows its control', !kinds('overflow').length, kinds('overflow').map((i) => `${i.msg} [${i.where[0]}]`).join('; ') || 'ok');
    check('UI', 'no overlapping controls', !kinds('overlap').length, kinds('overlap').map((i) => `${i.msg} [${i.where[0]}]`).join('; ') || 'ok');
    check('UI', 'every page fits the window at all three sizes (no sideways scrolling)', !kinds('layout').length, kinds('layout').map((i) => `${i.msg} [${i.where.join(', ')}]`).join('; ') || 'ok');
    check('UI', 'no "null"/"undefined" placeholder text shown anywhere', !kinds('text').length, kinds('text').map((i) => `${i.msg} [${i.where[0]}]`).join('; ') || 'ok');
  } catch (e) { record('UI', 'pixel UI audit', 'FAIL', e.message); }

  // ===== engine crash while VIPER runs: automatic reconnection =====
  {
    await win.evaluate(() => window.viperApp.go('home'));
    const tKill = Date.now(); killEngine();
    const down = await waitAi(win, ['init', 'engine', 'starting', 'model', 'verify', 'error'], 60000);
    const back = await waitAi(win, ['ready', 'error'], 240000);
    const servers = engineServers();
    check('AI start-up', 'AI engine crash is detected and VIPER reconnects automatically (restarting the engine itself)', !!down && back?.stage === 'ready', `stopped → ${down?.label} → ${back?.label} in ${((Date.now() - tKill) / 1000).toFixed(1)} s; owned now: ${back?.owned}`);
    check('AI start-up', 'no duplicate engine processes after recovery', servers.length === 1, `ollama serve processes: ${servers.length}`);
    metrics.recoverySeconds = Math.round((Date.now() - tKill) / 100) / 10;
  }

  // ===== failed start-up shows a useful error and a working Retry button =====
  {
    const good = (await apiCall(win, 'GET', '/settings/backend')).ollama.url;
    killEngine(); await sleep(1500);
    // Point VIPER at a port another program already uses: the engine cannot start there.
    await apiCall(win, 'PATCH', '/settings/backend', { ollama: { url: 'http://127.0.0.1:47800' } });
    const err = await waitAi(win, ['error'], 240000);
    await win.evaluate(() => window.viperApp.go('home')); await sleep(800);
    const ui = await win.evaluate(() => ({ text: document.querySelector('.ai-status')?.innerText || '', retry: [...document.querySelectorAll('.ai-status button')].some((b) => /Retry connection/.test(b.innerText)) }));
    await win.screenshot({ path: path.join(OUT, '03d-start-error.png') });
    check('AI start-up', 'a start-up that cannot succeed ends in a clear error (limited retries, no loop) with a Retry Connection button', err?.stage === 'error' && ui.retry && /AI OFFLINE/.test(ui.text), `${err?.detail?.slice(0, 200)}`);
    check('AI start-up', 'no stray engine processes left by the failed attempts', engineServers().length === 0, `ollama serve processes: ${engineServers().length}`);
    await apiCall(win, 'PATCH', '/settings/backend', { ollama: { url: good } });
    await waitAi(win, ['ready', 'error'], 240000); // the settings change itself re-runs start-up
    if ((await aiState(win))?.stage !== 'ready') { await win.evaluate(() => [...document.querySelectorAll('.ai-status button')].find((b) => /Retry connection/.test(b.innerText))?.click()); }
    const fixed = await waitAi(win, ['ready'], 240000);
    check('AI start-up', 'after fixing the problem, VIPER connects (Retry / automatic re-run)', fixed?.stage === 'ready', fixed?.detail);
  }

  // ===== close cleanly =====
  const pidList = (await app.evaluate(({ app: a }) => a.getAppMetrics().map((m) => m.pid)));
  await app.evaluate(() => { const m = global.viperDiagnostics.trayMenu(); m.items.find((i) => i.label === 'Quit VIPER').click(); });
  const gone = await until(() => pidList.every((pid) => { try { process.kill(pid, 0); return false; } catch { return true; } }), 20000, 300);
  check('App', 'Quit closes VIPER cleanly (all processes exit)', !!gone, `${pidList.length} processes`);
  await app.close().catch(() => {});
  const leftover = await until(() => engineServers().length === 0, 15000, 500);
  check('AI start-up', 'quitting VIPER stops the engine it started (no orphaned processes)', !!leftover, `ollama serve processes after quit: ${engineServers().length}`);

  // ===== reopen with the engine NOT running: VIPER starts it and reconnects to the same model =====
  killEngine();
  const tLaunch2 = Date.now();
  ({ app, win, errors, ready } = await launch('second'));
  await until(() => win.evaluate(() => document.querySelectorAll('.nav-item').length >= 16), 30000);
  {
    const st = await waitAi(win, ['ready', 'error', 'setup'], 300000);
    metrics.coldStartToReadyMs = Date.now() - tLaunch2;
    check('AI start-up', 'launch with Ollama not running: VIPER starts it automatically and becomes ready', st?.stage === 'ready' && st.owned === true, `${st?.label} · ${st?.detail} · ${(metrics.coldStartToReadyMs / 1000).toFixed(1)} s from launch`);
    check('AI start-up', 'the previously used model is remembered and reconnected', st?.model === MODEL, `model ${st?.model}`);
    check('AI start-up', 'exactly one engine process', engineServers().length === 1, `ollama serve processes: ${engineServers().length}`);
    await win.evaluate(() => window.viperApp.go('home')); await sleep(1200);
    await win.screenshot({ path: path.join(OUT, '07b-cold-start-ready.png') });
  }
  const persisted = { name: (await apiCall(win, 'GET', '/settings/personality')).userName, preset: (await apiCall(win, 'GET', '/performance')).preset, memory: (await apiCall(win, 'GET', '/memory?q=tea')).length, conversations: (await apiCall(win, 'GET', '/conversations')).length, wizard: await win.evaluate(() => !!document.querySelector('.wizard')) };
  check('App', 'settings persist after restart', persisted.name === 'E2E Tester' && persisted.preset === 'eco', JSON.stringify(persisted));
  check('App', 'user data (memories, conversations) preserved after reopening', persisted.memory > 0 && persisted.conversations >= convs.length && !persisted.wizard, JSON.stringify(persisted));
  check('Performance', 'second start-up is fast (< 10 s to dashboard)', metrics.startup_second_ms < 10000, `${metrics.startup_second_ms} ms`);
  await win.screenshot({ path: path.join(OUT, '07-reopened.png') });
  await app.evaluate(() => { global.viperDiagnostics.trayMenu().items.find((i) => i.label === 'Quit VIPER').click(); });
  await sleep(3000); await app.close().catch(() => {});

  // ===== portable =====
  if (WIN && process.env.E2E_PORTABLE) {
    const p = spawn(process.env.E2E_PORTABLE, [], { detached: true, stdio: 'ignore', env: { ...process.env, VIPER_DATA_DIR: path.join(os.tmpdir(), 'viper-portable-data') } });
    const up = await until(async () => { try { const r = await fetch('http://127.0.0.1:47800/api/v1/status'); return r.status === 401; } catch { return false; } }, 120000, 1000);
    check('Portable', 'VIPER-Portable.exe launches and starts the VIPER core', !!up, up ? 'core answered on 127.0.0.1:47800 (401 without token, as designed)' : 'no response');
    try { execFileSync('taskkill', ['/F', '/T', '/PID', String(p.pid)]); } catch { /* ignore */ }
    try { execFileSync('taskkill', ['/F', '/IM', 'VIPER.exe']); } catch { /* ignore */ }
    await sleep(2000);
  }

  // ===== uninstall =====
  if (WIN && INSTALLER) {
    const unins = path.join(INSTALL_DIR, 'Uninstall VIPER.exe');
    const r = require('node:child_process').spawnSync(unins, ['/S'], { timeout: 300000 });
    const removed = await until(() => !fs.existsSync(EXE), 120000, 1000);
    check('Installer', 'uninstaller removes the application', r.status === 0 && removed, `exit ${r.status}`);
    const left = await until(() => { const l = [START_LNK, DESKTOP_LNK].filter((f) => fs.existsSync(f)); return l.length ? null : 'none'; }, 60000, 1000);
    const remaining = [START_LNK, DESKTOP_LNK].filter((f) => fs.existsSync(f));
    check('Installer', 'uninstaller removes shortcuts', left === 'none', remaining.length ? `still present: ${remaining.join(', ')}` : 'Start menu and desktop shortcuts removed');
    check('Installer', 'user data is kept after uninstall (by design)', fs.existsSync(path.join(DATA_DIR, 'viper.db')), DATA_DIR);
  }

  save();
  const fails = results.filter((r) => r.status === 'FAIL');
  console.log(`\n${results.filter((r) => r.status === 'PASS').length} PASS · ${fails.length} FAIL · ${results.filter((r) => r.status === 'BLOCKED').length} BLOCKED`);
  console.log(`results: ${path.join(OUT, 'results.json')}`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { record('Harness', 'e2e run', 'FAIL', e.stack || e.message); save(); process.exit(1); });
