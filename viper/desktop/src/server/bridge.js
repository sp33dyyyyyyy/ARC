'use strict';
// Platform bridge: OS integrations that differ between the Electron app and
// the headless server. Electron's main process supplies a richer bridge.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function openWithOS(target) {
  return new Promise((resolve) => {
    let p;
    try {
      if (process.platform === 'win32') p = spawn('explorer.exe', [target], { detached: true, stdio: 'ignore' });
      else if (process.platform === 'darwin') p = spawn('open', [target], { detached: true, stdio: 'ignore' });
      else p = spawn('xdg-open', [target], { detached: true, stdio: 'ignore' });
    } catch (e) { return resolve({ ok: false, error: e.message }); }
    p.on('error', (e) => resolve({ ok: false, error: e.message }));
    p.unref();
    setTimeout(() => resolve({ ok: true }), 300);
  });
}

function headlessBridge(paths) {
  return {
    kind: 'headless',
    openPath: openWithOS,
    openExternal: openWithOS,
    async trash(p) {
      const dest = path.join(paths.data, 'recycle', `${Date.now()}-${path.basename(p)}`);
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      try { fs.renameSync(p, dest); return { ok: true, movedTo: dest }; } catch (e) { return { ok: false, error: e.message }; }
    },
    async readClipboard() { return null; },
    async captureScreen() { return { error: 'Screen capture requires the VIPER desktop app.' }; },
    async notify() { return { ok: false, error: 'Desktop notifications require the VIPER desktop app.' }; },
    async toggleHud() { return { ok: false, error: 'The floating HUD requires the VIPER desktop app.' }; },
    async setLoginItem() { return { ok: false, error: 'Not available headless' }; },
  };
}

module.exports = { headlessBridge, openWithOS };
