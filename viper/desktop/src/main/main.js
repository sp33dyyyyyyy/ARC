'use strict';
// VIPER desktop shell (Electron main process). Hosts the VIPER core in-process,
// and provides the window, tray, floating HUD, global shortcut, OS credential
// vault (DPAPI via safeStorage), screen capture, notifications and updates.
const { app, BrowserWindow, Tray, Menu, ipcMain, shell, globalShortcut, clipboard, desktopCapturer, Notification, safeStorage, dialog, screen, nativeImage, session, crashReporter } = require('electron');
const path = require('node:path');
const fs = require('node:fs');

const ROOT = path.join(__dirname, '..', '..');
const ICON = path.join(ROOT, 'build', process.platform === 'win32' ? 'icon.ico' : 'icon.png');
let svc = null; let mainWin = null; let hudWin = null; let tray = null; let quitting = false; let currentShortcut = null;
const startHidden = process.argv.includes('--hidden');

crashReporter.start({ uploadToServer: false }); // crash dumps stay local
if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0); }
app.on('second-instance', () => showMain());
app.setAppUserModelId('com.viper.desktop');
// Chromium speech/microphone needs no Google services; disable background throttling only for audio.
app.commandLine.appendSwitch('disable-features', 'HardwareMediaKeyHandling');

function dpapiEncryptor() {
  if (!safeStorage.isEncryptionAvailable()) return null;
  return { kind: process.platform === 'win32' ? 'dpapi' : 'os-keystore', encrypt: (s) => safeStorage.encryptString(s), decrypt: (b) => safeStorage.decryptString(Buffer.from(b)) };
}

// ---------------- bridge used by the core ----------------
const bridge = {
  kind: 'electron',
  async openPath(p) { const err = await shell.openPath(p); return err ? { ok: false, error: err } : { ok: true }; },
  async openExternal(url) { if (!/^https?:\/\//i.test(url)) return { ok: false, error: 'Only web links can be opened' }; await shell.openExternal(url); return { ok: true }; },
  async trash(p) { try { await shell.trashItem(p); return { ok: true }; } catch (e) { return { ok: false, error: e.message }; } },
  async readClipboard() { return clipboard.readText(); },
  async captureScreen() {
    const d = screen.getPrimaryDisplay();
    const size = { width: Math.round(d.size.width * d.scaleFactor), height: Math.round(d.size.height * d.scaleFactor) };
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: size });
    const src = sources.find((s) => s.display_id === String(d.id)) || sources[0];
    if (!src) return { error: 'No screen available to capture' };
    const png = src.thumbnail.toPNG();
    const file = path.join(svc.paths.screenshots, `screen-${new Date().toISOString().replace(/[:.]/g, '-')}.png`);
    fs.writeFileSync(file, png);
    return { path: file, width: size.width, height: size.height };
  },
  async notify(title, body) {
    if (!Notification.isSupported()) return { ok: false, error: 'Notifications not supported' };
    const n = new Notification({ title: `VIPER: ${title}`, body: body || '', icon: ICON, silent: false });
    n.on('click', () => showMain());
    n.show();
    return { ok: true };
  },
  async toggleHud(show) { toggleHud(show); return { ok: true }; },
};

// ---------------- windows ----------------
function secureWebContents(win) {
  const wc = win.webContents;
  wc.setWindowOpenHandler(({ url }) => { if (/^https?:\/\//.test(url) && !url.startsWith(svc.url)) shell.openExternal(url); return { action: 'deny' }; });
  wc.on('will-navigate', (e, url) => { if (!url.startsWith(svc.url)) { e.preventDefault(); if (/^https?:\/\//.test(url)) shell.openExternal(url); } });
}

function createMain() {
  const ui = svc.settings.get('ui');
  mainWin = new BrowserWindow({
    width: 1440, height: 900, minWidth: 920, minHeight: 600, frame: false, backgroundColor: '#000000', show: false, icon: ICON, title: 'VIPER',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: false, backgroundThrottling: true },
  });
  secureWebContents(mainWin);
  mainWin.loadURL(`${svc.url}/`);
  mainWin.once('ready-to-show', () => { if (!(startHidden || ui.startMinimized)) mainWin.show(); });
  mainWin.on('close', (e) => { if (!quitting && svc.settings.get('ui').closeToTray) { e.preventDefault(); mainWin.hide(); } });
  mainWin.on('closed', () => { mainWin = null; });
  for (const ev of ['minimize', 'hide']) mainWin.on(ev, () => svc.monitor.setVisible(false));
  for (const ev of ['restore', 'show', 'focus']) mainWin.on(ev, () => svc.monitor.setVisible(true));
}
function showMain() { if (!mainWin) createMain(); if (mainWin.isMinimized()) mainWin.restore(); mainWin.show(); mainWin.focus(); }

function hudSize(compact) { return compact ? { width: 168, height: 208 } : { width: 340, height: 460 }; }
function createHud() {
  const ui = svc.settings.get('ui');
  const s = hudSize(ui.hudCompact);
  const wa = screen.getPrimaryDisplay().workArea;
  const b = ui.hudBounds && screen.getDisplayMatching(ui.hudBounds) ? ui.hudBounds : { x: wa.x + wa.width - s.width - 24, y: wa.y + wa.height - s.height - 24 };
  hudWin = new BrowserWindow({
    ...s, x: b.x, y: b.y, frame: false, transparent: true, resizable: false, alwaysOnTop: true, skipTaskbar: true, show: false, hasShadow: false, focusable: true, backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  hudWin.setAlwaysOnTop(true, 'floating');
  hudWin.setOpacity(ui.hudOpacity || 0.92);
  secureWebContents(hudWin);
  hudWin.loadURL(`${svc.url}/hud.html`);
  hudWin.once('ready-to-show', () => hudWin.showInactive());
  hudWin.on('moved', () => { const [x, y] = hudWin.getPosition(); svc.settings.set('ui', { hudBounds: { x, y } }); });
  hudWin.on('closed', () => { hudWin = null; });
}
function toggleHud(show) {
  if (show === false || (show === undefined && hudWin && hudWin.isVisible())) { hudWin?.hide(); return; }
  if (!hudWin) createHud(); else { hudWin.showInactive(); hudWin.focus(); }
}

function createTray() {
  const img = nativeImage.createFromPath(path.join(ROOT, 'build', 'tray.png'));
  try { img.addRepresentation({ scaleFactor: 2, buffer: fs.readFileSync(path.join(ROOT, 'build', 'tray@2x.png')) }); } catch { /* optional */ }
  tray = new Tray(img);
  tray.setToolTip('VIPER');
  const build = () => {
    const v = svc.settings.get('voice');
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: 'Open VIPER', click: showMain },
      { label: 'Floating HUD', click: () => toggleHud() },
      { type: 'separator' },
      { label: v.micMuted ? 'Turn microphone on' : 'Turn microphone off', click: () => { svc.settings.set('voice', { micMuted: !v.micMuted }); build(); } },
      { label: svc.settings.get('notifications').emergencyMute ? 'Resume notifications' : 'Mute all notifications', click: () => { svc.settings.set('notifications', { emergencyMute: !svc.settings.get('notifications').emergencyMute }); build(); } },
      { type: 'separator' },
      { label: 'Quit VIPER', click: () => { quitting = true; app.quit(); } },
    ]));
  };
  build();
  tray.on('click', showMain);
  svc.bus.on('settings.changed', ({ section }) => { if (section === 'voice' || section === 'notifications') build(); });
}

function applyShortcut() {
  const acc = svc.settings.get('ui').hudShortcut;
  if (currentShortcut) { globalShortcut.unregister(currentShortcut); currentShortcut = null; }
  try { if (acc && globalShortcut.register(acc, () => toggleHud())) currentShortcut = acc; else svc.log.warn(`Could not register shortcut ${acc}`); } catch (e) { svc.log.warn('shortcut', e.message); }
  // Global talk toggle: press once to start listening, again to stop.
  try { globalShortcut.register('CommandOrControl+Shift+V', () => { const w = hudWin?.isVisible() ? hudWin : mainWin; w?.webContents.send('viper:ptt-toggle'); }); } catch { /* taken */ }
}
function applyLoginItem() {
  if (process.platform !== 'win32' && process.platform !== 'darwin') return;
  app.setLoginItemSettings({ openAtLogin: !!svc.settings.get('ui').launchAtStartup, args: ['--hidden'] });
}

// ---------------- updates ----------------
let updater = null;
function getUpdater() {
  if (updater !== null) return updater;
  try { updater = require('electron-updater').autoUpdater; updater.autoDownload = false; updater.logger = null; } catch { updater = false; }
  return updater;
}
async function checkUpdates() {
  const u = getUpdater();
  if (!u || !app.isPackaged) return { available: false, message: 'Update checks run in the installed app.' };
  try {
    const r = await u.checkForUpdates();
    const v = r?.updateInfo?.version;
    return v && v !== app.getVersion() ? { available: true, version: v, message: 'Choose Install to download it. The download is verified with its published SHA-512 checksum before installing.' } : { available: false, message: `You have the latest version (${app.getVersion()}).` };
  } catch (e) { return { available: false, message: `Update check failed: ${e.message}` }; }
}

// ---------------- IPC ----------------
function senderOk(e) { return e.senderFrame && svc && e.senderFrame.url.startsWith(svc.url); }
ipcMain.on('viper:token', (e) => { e.returnValue = senderOk(e) ? svc.localToken : null; });
ipcMain.handle('viper:window', (e, action) => {
  if (!senderOk(e)) return;
  const w = BrowserWindow.fromWebContents(e.sender);
  if (action === 'minimize') w.minimize(); else if (action === 'maximize') (w.isMaximized() ? w.unmaximize() : w.maximize()); else if (action === 'close') w.close(); else if (action === 'hide') w.hide();
});
ipcMain.handle('viper:hud', (e, show) => { if (senderOk(e)) toggleHud(show); });
ipcMain.handle('viper:hud-size', (e, compact) => { if (!senderOk(e) || !hudWin) return; const s = hudSize(compact); const [x, y] = hudWin.getPosition(); hudWin.setBounds({ x, y: y + (hudWin.getSize()[1] - s.height), ...s }); });
ipcMain.handle('viper:show-main', (e, mode) => { if (!senderOk(e)) return; showMain(); if (mode) mainWin.webContents.executeJavaScript(`window.viperApp && window.viperApp.go(${JSON.stringify(String(mode))})`); });
ipcMain.handle('viper:open-external', (e, url) => { if (senderOk(e)) return bridge.openExternal(url); });
ipcMain.handle('viper:pick-folder', async (e) => { if (!senderOk(e)) return null; const r = await dialog.showOpenDialog(mainWin, { properties: ['openDirectory'] }); return r.canceled ? null : r.filePaths[0]; });
ipcMain.handle('viper:pick-file', async (e, filters) => { if (!senderOk(e)) return null; const r = await dialog.showOpenDialog(mainWin, { properties: ['openFile'], filters: filters || [] }); return r.canceled ? null : r.filePaths[0]; });
ipcMain.handle('viper:check-updates', (e) => (senderOk(e) ? checkUpdates() : null));
ipcMain.handle('viper:install-update', async (e) => { if (!senderOk(e)) return; const u = getUpdater(); if (!u) return; await u.downloadUpdate(); quitting = true; u.quitAndInstall(); });
ipcMain.handle('viper:open-data', (e) => { if (senderOk(e)) shell.openPath(svc.paths.data); });
ipcMain.handle('viper:flash', (e) => { if (senderOk(e) && mainWin && !mainWin.isFocused()) mainWin.flashFrame(true); });
ipcMain.handle('viper:wake', (e) => { if (senderOk(e) && hudWin && !hudWin.isVisible()) hudWin.showInactive(); });

// ---------------- lifecycle ----------------
app.whenReady().then(async () => {
  const { createViper } = require('../server/server');
  try {
    svc = await createViper({ bridge, encryptor: dpapiEncryptor() || undefined, version: app.getVersion() });
  } catch (e) {
    dialog.showErrorBox('VIPER could not start', `${e.message}\n\nLogs: ${path.join(app.getPath('appData'), 'VIPER', 'logs')}`);
    app.exit(1); return;
  }
  process.on('uncaughtException', (err) => svc.log.error('uncaught', err));
  process.on('unhandledRejection', (err) => svc.log.error('unhandled rejection', err));
  // Microphone/camera only for VIPER's own pages; camera only if enabled in Privacy.
  session.defaultSession.setPermissionRequestHandler((wc, permission, cb, details) => {
    const ours = (details.requestingUrl || wc.getURL()).startsWith(svc.url);
    if (!ours) return cb(false);
    if (permission === 'media') { const wantsVideo = (details.mediaTypes || []).includes('video'); return cb(!wantsVideo || svc.settings.get('privacy').cameraEnabled); }
    cb(['clipboard-sanitized-write', 'notifications', 'fullscreen'].includes(permission));
  });
  session.defaultSession.setPermissionCheckHandler((wc, permission, origin) => origin.startsWith(svc.url) && ['media', 'clipboard-sanitized-write', 'notifications'].includes(permission));
  createMain();
  createTray();
  applyShortcut();
  applyLoginItem();
  if (svc.settings.get('ui').showHudOnStart) createHud();
  svc.bus.on('settings.changed', ({ section }) => {
    if (section !== 'ui') return;
    applyShortcut(); applyLoginItem();
    const ui = svc.settings.get('ui');
    if (hudWin) { hudWin.setOpacity(ui.hudOpacity || 0.92); }
  });
  if (svc.settings.get('updates').checkOnStartup && app.isPackaged) setTimeout(async () => { const r = await checkUpdates(); if (r.available) svc.notify.send({ title: `Update ${r.version} available`, body: 'Open Settings → About to install it.', category: 'system', channels: ['desktop'] }); }, 15000);
});
app.on('window-all-closed', (e) => { if (!quitting) e.preventDefault?.(); });
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', async (e) => {
  globalShortcut.unregisterAll();
  if (svc && !svc._stopped) { e.preventDefault(); svc._stopped = true; try { await svc.shutdown(); } catch { /* ignore */ } app.exit(0); }
});
