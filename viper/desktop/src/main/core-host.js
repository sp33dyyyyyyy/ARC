'use strict';
// Runs the VIPER core in an Electron utility process, separate from the main
// process that owns windows, the tray and the HUD. Heavy work (database, file
// indexing, PDF parsing, streaming) therefore never stalls the interface.
// OS integrations that only the main process can perform are reached over a
// small message-based bridge.
const crypto = require('node:crypto');
const port = process.parentPort;
let svc = null; let seq = 0;
const pending = new Map();

function rpc(method, ...args) {
  return new Promise((resolve) => {
    const id = ++seq;
    pending.set(id, resolve);
    port.postMessage({ type: 'bridge', id, method, args });
  });
}
const bridge = {
  kind: 'electron',
  openPath: (p) => rpc('openPath', p),
  openExternal: (u) => rpc('openExternal', u),
  trash: (p) => rpc('trash', p),
  readClipboard: () => rpc('readClipboard'),
  captureScreen: () => rpc('captureScreen'),
  notify: (t, b) => rpc('notify', t, b),
  toggleHud: (s) => rpc('toggleHud', s),
};

// AES-256-GCM with a master key that the main process keeps encrypted by the
// OS keystore (Windows DPAPI via safeStorage) and hands over at start-up.
function keyEncryptor(keyHex, kind) {
  const key = Buffer.from(keyHex, 'hex');
  return {
    kind,
    encrypt(plain) { const iv = crypto.randomBytes(12); const c = crypto.createCipheriv('aes-256-gcm', key, iv); const enc = Buffer.concat([c.update(Buffer.from(plain, 'utf8')), c.final()]); return Buffer.concat([iv, c.getAuthTag(), enc]); },
    decrypt(buf) { const b = Buffer.from(buf); const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12)); d.setAuthTag(b.subarray(12, 28)); return Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8'); },
  };
}

async function handleCall(m) {
  switch (m.method) {
    case 'settings.set': return svc.settings.set(m.args[0], m.args[1]);
    case 'monitor.setVisible': svc.monitor.setVisible(m.args[0]); return true;
    case 'notify.send': return svc.notify.send(m.args[0]);
    case 'log': svc.logger.write(m.args[0], 'main', ...m.args.slice(1)); return true;
    case 'shutdown': await svc.shutdown(); return true;
    default: throw new Error(`Unknown call ${m.method}`);
  }
}

port.on('message', async (e) => {
  const m = e.data;
  if (m.type === 'bridge-result') { const r = pending.get(m.id); pending.delete(m.id); r?.(m.result); return; }
  if (m.type === 'start') {
    try {
      const { createViper } = require('../server/server');
      svc = await createViper({ bridge, version: m.version, encryptor: m.vaultKey ? keyEncryptor(m.vaultKey, m.vaultKind) : undefined });
      svc.bus.on('settings.changed', (d) => port.postMessage({ type: 'event', name: 'settings.changed', data: d }));
      port.postMessage({ type: 'ready', url: svc.url, token: svc.localToken, paths: svc.paths, settings: svc.settings.all() });
    } catch (err) { port.postMessage({ type: 'fatal', error: err.stack || err.message }); }
    return;
  }
  if (m.type === 'call') {
    try { port.postMessage({ type: 'call-result', id: m.id, result: await handleCall(m) }); } catch (err) { port.postMessage({ type: 'call-result', id: m.id, error: err.message }); }
  }
});
process.on('uncaughtException', (err) => { try { svc?.log.error('uncaught', err); } catch { /* ignore */ } });
process.on('unhandledRejection', (err) => { try { svc?.log.error('unhandled rejection', err); } catch { /* ignore */ } });
