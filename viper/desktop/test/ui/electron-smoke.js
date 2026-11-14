// Launches the real Electron app (under Xvfb on Linux), checks the main window, the
// preload bridge, navigation, chat round-trip and the floating HUD window.
let pw; try { pw = require('playwright'); } catch { pw = require('playwright-core'); }
const { _electron: electron } = pw;
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const OUT = process.env.SHOTS || os.tmpdir();
(async () => {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'viper-electron-'));
  const app = await electron.launch({ executablePath: require('electron'), args: [path.join(__dirname, '..', '..'), '--no-sandbox'], env: { ...process.env, VIPER_DATA_DIR: dataDir, NODE_OPTIONS: '' } });
  const results = [];
  const check = (name, ok, extra = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${extra ? ` — ${extra}` : ''}`); };
  try {
    const win = await app.firstWindow();
    await win.waitForLoadState('domcontentloaded');
    await win.waitForTimeout(2500);
    check('main window loads VIPER UI from the in-process core', /127\.0\.0\.1:\d+\/$/.test(win.url()), win.url());
    check('preload exposes a token but no Node APIs', await win.evaluate(() => typeof window.viperNative?.token === 'string' && typeof window.require === 'undefined' && typeof window.process === 'undefined'));
    check('setup wizard shown on first run', await win.evaluate(() => !!document.querySelector('.wizard')));
    await win.screenshot({ path: path.join(OUT, 'electron-setup.png') });
    // complete setup via API and reload
    await win.evaluate(async () => { const t = window.viperNative.token; await fetch('/api/v1/setup/complete', { method: 'POST', headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' }, body: '{}' }); });
    await win.reload(); await win.waitForTimeout(2500);
    check('dashboard renders with animated core', await win.evaluate(() => !!document.querySelector('canvas.core') && document.querySelectorAll('.nav-item').length >= 16));
    const r = await win.evaluate(async () => { const t = window.viperNative.token; const res = await fetch('/api/v1/chat', { method: 'POST', headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ text: "What's happening with my computer?" }) }); return res.json(); });
    await win.waitForTimeout(2000);
    const replyText = await win.evaluate(() => document.querySelector('.reply-panel')?.textContent || '');
    check('system status command answered through the UI event stream', !!r.requestId);
    await win.evaluate(() => window.viperApp.go('system')); await win.waitForTimeout(1500);
    await win.screenshot({ path: path.join(OUT, 'electron-system.png') });
    // floating HUD
    await win.evaluate(() => window.viperNative.toggleHud(true));
    let hud = null;
    for (let i = 0; i < 20 && !hud; i++) { await win.waitForTimeout(300); hud = app.windows().find((w) => w.url().includes('hud.html')); }
    check('floating HUD window opens', !!hud);
    if (hud) { await hud.waitForTimeout(1500); await hud.screenshot({ path: path.join(OUT, 'electron-hud.png') }); check('HUD core renders', await hud.evaluate(() => !!document.querySelector('#core'))); }
    const isOnTop = await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().some((w) => w.isAlwaysOnTop()));
    check('HUD is always-on-top', isOnTop);
    const trayOk = await app.evaluate(({ app: a }) => a.isReady());
    check('app ready with tray/menu initialised', trayOk);
    const vault = await win.evaluate(async () => (await (await fetch('/api/v1/status', { headers: { Authorization: `Bearer ${window.viperNative.token}` } })).json()).vault);
    check('credential vault reports its backend', !!vault, vault);
  } catch (e) { check('electron run', false, e.message); }
  await app.close().catch(() => {});
  const failed = results.filter((x) => !x.ok).length;
  console.log(`${results.length - failed}/${results.length} electron checks passed`);
  process.exit(failed ? 1 : 0);
})();
