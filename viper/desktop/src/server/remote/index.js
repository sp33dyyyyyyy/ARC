'use strict';
// VIPER Mobile link.
//  - HTTPS + WSS with a self-signed certificate generated on this PC. The phone
//    pins the certificate's SHA-256 fingerprint received through the QR code.
//  - Pairing: single-use token, 5-minute expiry, shown only as a QR code on the desktop.
//  - Every request carries a per-device secret (stored hashed); devices can be revoked instantly.
//  - Remote access away from home is supported through a user-configured VPN
//    (e.g. WireGuard / Tailscale); VIPER never opens ports on your router.
const https = require('node:https');
const dgram = require('node:dgram');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer } = require('ws');
const { dispatch, send, HttpError, readBody } = require('../http');
const { uid, now, sha256, timingSafeEqualStr, jsonParse } = require('../util');
const { FcmSender } = require('../fcm');

const DEFAULT_SCOPES = ['read', 'chat', 'voice', 'reminders', 'automation', 'control', 'research', 'image', 'files', 'models', 'code', 'agent', 'approve'];
const PAIR_TTL = 5 * 60000;

function lanAddresses() {
  const out = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) for (const a of list || []) if (a.family === 'IPv4' && !a.internal) out.push({ name, address: a.address });
  // Prefer typical home LAN ranges first, then VPN ranges (100.64/10 = Tailscale).
  const rank = (ip) => (/^192\.168\./.test(ip) ? 0 : /^10\./.test(ip) ? 1 : /^172\.(1[6-9]|2\d|3[01])\./.test(ip) ? 2 : /^100\./.test(ip) ? 3 : 4);
  return out.sort((a, b) => rank(a.address) - rank(b.address));
}

function ensureCert(dir) {
  const keyF = path.join(dir, 'remote-key.pem'); const certF = path.join(dir, 'remote-cert.pem');
  if (!fs.existsSync(keyF) || !fs.existsSync(certF)) {
    const forge = require('node-forge');
    const keys = forge.pki.rsa.generateKeyPair(2048);
    const cert = forge.pki.createCertificate();
    cert.publicKey = keys.publicKey;
    cert.serialNumber = `01${crypto.randomBytes(8).toString('hex')}`;
    cert.validity.notBefore = new Date(Date.now() - 86400000);
    cert.validity.notAfter = new Date(Date.now() + 10 * 365 * 86400000);
    const attrs = [{ name: 'commonName', value: `VIPER ${os.hostname()}` }, { name: 'organizationName', value: 'VIPER local' }];
    cert.setSubject(attrs); cert.setIssuer(attrs);
    cert.setExtensions([{ name: 'basicConstraints', cA: false }, { name: 'keyUsage', digitalSignature: true, keyEncipherment: true }, { name: 'extKeyUsage', serverAuth: true }, { name: 'subjectAltName', altNames: [{ type: 2, value: os.hostname() }, { type: 7, ip: '127.0.0.1' }, ...lanAddresses().map((a) => ({ type: 7, ip: a.address }))] }]);
    cert.sign(keys.privateKey, forge.md.sha256.create());
    fs.writeFileSync(keyF, forge.pki.privateKeyToPem(keys.privateKey), { mode: 0o600 });
    fs.writeFileSync(certF, forge.pki.certificateToPem(cert));
  }
  const certPem = fs.readFileSync(certF, 'utf8');
  const fp = new crypto.X509Certificate(certPem).fingerprint256; // "AA:BB:..."
  return { key: fs.readFileSync(keyF), cert: certPem, fingerprint: fp };
}

class RemoteLink {
  constructor(svc) {
    this.svc = svc; this.db = svc.db; this.log = svc.logger.scope('remote');
    this.server = null; this.wss = null; this.sockets = new Map(); // deviceId -> Set(ws)
    this.pairing = null; this.failures = new Map(); this.pendingSms = new Map();
    this.lastSampleSent = 0;
    this.fcm = new FcmSender({ getServiceAccount: () => svc.vault.get('fcm.serviceAccount') });
  }
  event(device, event, detail = null, ip = null) {
    this.db.run('INSERT INTO device_events (device_id, device_name, event, detail, ip, ts) VALUES (?, ?, ?, ?, ?, ?)', device?.id || null, device?.name || null, event, detail, ip, now());
  }
  events(deviceId, limit = 100) { return deviceId ? this.db.all('SELECT * FROM device_events WHERE device_id = ? ORDER BY ts DESC LIMIT ?', deviceId, limit) : this.db.all('SELECT * FROM device_events ORDER BY ts DESC LIMIT ?', limit); }
  cfg() { return this.svc.settings.get('remote'); }
  status() {
    return {
      enabled: this.cfg().enabled, running: !!this.server, port: this.port || this.cfg().port, addresses: lanAddresses(),
      fingerprint: this.tls?.fingerprint || null, connected: this.devices().filter((d) => this.sockets.get(d.id)?.size).map((d) => ({ id: d.id, name: d.name })),
      pairingActive: !!(this.pairing && this.pairing.expiresAt > Date.now()),
    };
  }
  devices() {
    return this.db.all('SELECT id, name, platform, permissions, created_at, last_seen, last_ip, revoked, push_provider, CASE WHEN push_token IS NULL THEN 0 ELSE 1 END AS push_registered FROM devices ORDER BY created_at DESC')
      .map((d) => { const perms = jsonParse(d.permissions, {}); return { ...d, permissions: perms, scopes: perms.scopes || DEFAULT_SCOPES, online: !!this.sockets.get(d.id)?.size, push_registered: !!d.push_registered, lastConnected: this.db.get("SELECT ts FROM device_events WHERE device_id = ? AND event = 'connected' ORDER BY ts DESC LIMIT 1", d.id)?.ts || null }; });
  }

  async applySettings() {
    if (this.cfg().enabled || this.pairing) await this.start(); else await this.stop();
    this.svc.bus.publish('remote.changed', this.status());
  }
  async start() {
    if (this.server) return;
    this.tls = ensureCert(this.svc.paths.certs);
    const server = https.createServer({ key: this.tls.key, cert: this.tls.cert, minVersion: 'TLSv1.2' }, (req, res) => this.handle(req, res));
    this.wss = new WebSocketServer({ noServer: true, maxPayload: 8 << 20 });
    server.on('upgrade', (req, socket, head) => {
      const url = new URL(req.url, 'https://x');
      const dev = url.pathname === '/api/v1/ws' && this.authenticate(req.headers.authorization || `Bearer ${url.searchParams.get('auth') || ''}`, req.socket.remoteAddress);
      // Tell the phone plainly that its credentials are no longer valid, so it can return to pairing.
      if (!dev) { try { socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); } catch { socket.destroy(); } return; }
      this.wss.handleUpgrade(req, socket, head, (ws) => this.onSocket(ws, dev));
    });
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(this.cfg().port, '0.0.0.0', resolve); });
    this.server = server; this.port = server.address().port;
    this.forward = (evt) => this.forwardEvent(evt);
    this.svc.bus.on('event', this.forward);
    this.startDiscovery();
    this.log.info(`Remote link listening on port ${this.port}`);
  }

  /**
   * LAN discovery: a paired phone that cannot reach the PC at its known addresses (the PC's IP
   * changed, new Wi-Fi) broadcasts {viper:"discover", fp} on UDP. The PC answers only if the
   * fingerprint is its own certificate's, so it never announces itself to strangers; the phone
   * still verifies the pinned certificate when it connects.
   */
  startDiscovery() {
    const port = this.cfg().discoveryPort ?? 47802;
    if (!port || this.udp) return;
    const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });
    sock.on('message', (msg, rinfo) => {
      const j = jsonParse(msg.toString('utf8').slice(0, 512), null);
      if (j?.viper !== 'discover' || !j.fp) return;
      const norm = (f) => String(f).replace(/[^0-9a-f]/gi, '').toUpperCase();
      if (norm(j.fp) !== norm(this.tls.fingerprint)) return;
      const reply = Buffer.from(JSON.stringify({ viper: 'here', port: this.port, name: os.hostname() }));
      sock.send(reply, rinfo.port, rinfo.address, () => {});
    });
    sock.on('error', (e) => { this.log.debug('discovery socket', e.message); try { sock.close(); } catch { /* closed */ } if (this.udp === sock) this.udp = null; });
    sock.bind(port, () => { try { sock.setBroadcast(true); } catch { /* ignore */ } });
    this.udp = sock; this.discoveryPort = port;
  }
  async stop() {
    this.pairing = null;
    if (!this.server) return;
    this.svc.bus.off('event', this.forward);
    for (const set of this.sockets.values()) for (const ws of set) ws.terminate();
    this.sockets.clear();
    try { this.udp?.close(); } catch { /* closed */ } this.udp = null;
    await new Promise((r) => this.server.close(r));
    this.server = null;
  }

  // ---------- auth ----------
  rateLimited(ip) {
    const f = this.failures.get(ip) || { n: 0, t: Date.now() };
    if (Date.now() - f.t > 60000) { f.n = 0; f.t = Date.now(); }
    return f.n >= 10;
  }
  fail(ip) { const f = this.failures.get(ip) || { n: 0, t: Date.now() }; f.n++; this.failures.set(ip, f); }
  authenticate(header, ip) {
    if (this.rateLimited(ip)) return null;
    const tok = String(header || '').replace(/^Bearer\s+/i, '');
    const [id, secret] = tok.split('.');
    if (!id || !secret) { this.fail(ip); return null; }
    const d = this.db.get('SELECT * FROM devices WHERE id = ? AND revoked = 0', id);
    if (!d || !timingSafeEqualStr(sha256(secret), d.token_hash)) { this.fail(ip); return null; }
    this.db.run('UPDATE devices SET last_seen = ?, last_ip = ? WHERE id = ?', now(), ip, id);
    const perms = jsonParse(d.permissions, {});
    return { id: d.id, name: d.name, permissions: perms.tools || {}, scopes: perms.scopes || DEFAULT_SCOPES };
  }

  async createPairing() {
    await this.start();
    const token = crypto.randomBytes(24).toString('base64url');
    const addrs = lanAddresses();
    this.pairing = { token, expiresAt: Date.now() + PAIR_TTL, attempts: 0 };
    const payload = { v: 1, app: 'viper', name: os.hostname(), hosts: addrs.map((a) => a.address), port: this.port, fp: this.tls.fingerprint, token, exp: this.pairing.expiresAt };
    const QR = require('qrcode');
    const qr = await QR.toDataURL(JSON.stringify(payload), { errorCorrectionLevel: 'M', margin: 1, scale: 6, color: { dark: '#000000', light: '#ffffff' } });
    setTimeout(() => { if (this.pairing?.token === token) { this.pairing = null; if (!this.cfg().enabled) this.stop(); this.svc.bus.publish('remote.changed', this.status()); } }, PAIR_TTL + 1000).unref();
    this.svc.bus.publish('remote.changed', this.status());
    // The same payload as text, for phones without a working camera (paste or share it to VIPER Mobile).
    const code = Buffer.from(JSON.stringify(payload)).toString('base64url');
    return { qr, code, host: addrs[0]?.address || '127.0.0.1', hosts: addrs, port: this.port, fingerprint: this.tls.fingerprint, expiresAt: this.pairing.expiresAt };
  }
  cancelPairing() { this.pairing = null; if (!this.cfg().enabled) this.stop(); }

  async completePairing(body, ip) {
    const p = this.pairing;
    const name = String(body.deviceName || 'Android phone').slice(0, 60);
    if (!p || p.expiresAt < Date.now()) { this.event({ name }, 'rejected', 'expired or unknown pairing code', ip); throw new HttpError(410, 'Pairing code expired. Generate a new code on the PC.'); }
    if (++p.attempts > 5) { this.pairing = null; throw new HttpError(429, 'Too many attempts'); }
    if (!timingSafeEqualStr(body.token || '', p.token)) { this.fail(ip); this.event({ name }, 'rejected', 'invalid pairing code', ip); throw new HttpError(401, 'Invalid pairing code'); }
    this.pairing = null; // single use
    // The person at the PC confirms the new device (shows its name and network address).
    if (this.cfg().confirmPairing !== false) {
      this.svc.bus.publish('remote.pairing', { name, ip, state: 'awaiting-confirmation' });
      const ok = await this.svc.permissions.requestConfirmation({ tool: 'pair_device', title: `Pair "${name}" with this PC?`, preview: `Device: ${name}\nPlatform: ${String(body.platform || 'android')}\nNetwork address: ${String(ip || '').replace(/^::ffff:/, '')}`, risk: 'write', category: 'remote.pair', reason: 'Only allow this if you are pairing your own phone right now. It will be able to chat with VIPER, receive notifications and use the permissions shown in Connected Devices.', origin: 'desktop' }, 90000);
      if (!ok) { this.event({ name }, 'rejected', 'declined on the PC', ip); this.svc.bus.publish('remote.pairing', { name, state: 'declined' }); throw new HttpError(403, 'Pairing was declined on the PC.'); }
    }
    const id = uid('dev_');
    const secret = crypto.randomBytes(32).toString('base64url');
    this.db.run('INSERT INTO devices (id, name, platform, token_hash, permissions, created_at, last_seen, last_ip) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', id, name, String(body.platform || 'android').slice(0, 20), sha256(secret), JSON.stringify({ scopes: DEFAULT_SCOPES, tools: {} }), now(), now(), ip);
    if (!this.cfg().enabled) this.svc.settings.set('remote', { enabled: true });
    this.svc.permissions.audit('system', 'device.paired', name, 'write', 'ok');
    this.event({ id, name }, 'paired', String(body.platform || 'android'), ip);
    this.svc.bus.publish('remote.paired', { id, name });
    this.svc.bus.publish('remote.changed', this.status());
    return { deviceId: id, secret, serverName: os.hostname(), apiVersion: 1 };
  }
  revoke(id) {
    const d = this.db.get('SELECT id, name FROM devices WHERE id = ?', id);
    this.db.run('UPDATE devices SET revoked = 1, push_token = NULL WHERE id = ?', id);
    if (d) this.event(d, 'revoked', 'access revoked on the PC');
    for (const ws of this.sockets.get(id) || []) ws.close(4001, 'revoked');
    this.sockets.delete(id);
    this.svc.permissions.audit('user', 'device.revoked', id, 'write', 'ok');
    this.svc.bus.publish('remote.changed', this.status());
  }
  remove(id) { this.revoke(id); this.db.run('DELETE FROM devices WHERE id = ?', id); this.svc.bus.publish('remote.changed', this.status()); }
  setDevicePermissions(id, perms) {
    const d = this.db.get('SELECT permissions FROM devices WHERE id = ?', id);
    if (!d) throw new HttpError(404, 'Device not found');
    const cur = jsonParse(d.permissions, {});
    const next = { scopes: Array.isArray(perms.scopes) ? perms.scopes.filter((s) => DEFAULT_SCOPES.includes(s)) : cur.scopes, tools: perms.tools || cur.tools || {} };
    this.db.run('UPDATE devices SET permissions = ? WHERE id = ?', JSON.stringify(next), id);
    return next;
  }

  // ---------- HTTP ----------
  async handle(req, res) {
    const ip = req.socket.remoteAddress;
    const url = new URL(req.url, 'https://x');
    res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    if (url.pathname === '/api/v1/hello' && req.method === 'GET') return send(res, 200, { app: 'viper', apiVersion: 1, name: os.hostname() });
    if (url.pathname === '/api/v1/pair' && req.method === 'POST') {
      if (this.rateLimited(ip)) return send(res, 429, { error: 'Too many attempts' });
      try { const body = JSON.parse((await readBody(req, 64 * 1024)).toString() || '{}'); return send(res, 200, await this.completePairing(body, ip)); } catch (e) { return send(res, e.status || 400, { error: e.message }); }
    }
    const dev = this.authenticate(req.headers.authorization, ip);
    if (!dev) return send(res, 401, { error: 'Unauthorized' });
    // device-only endpoints
    if (url.pathname === '/api/v1/device/me') return send(res, 200, { id: dev.id, name: dev.name, scopes: dev.scopes });
    if (url.pathname === '/api/v1/device/push-config') { const f = this.svc.settings.get('notifications').fcm; return send(res, 200, f.enabled && f.projectId && f.appId && f.apiKey && f.senderId ? { provider: 'fcm', projectId: f.projectId, appId: f.appId, apiKey: f.apiKey, senderId: f.senderId } : { provider: null }); }
    if (url.pathname === '/api/v1/device/push' && req.method === 'POST') {
      const b = jsonParse((await readBody(req, 8192)).toString(), {});
      const token = typeof b.token === 'string' ? b.token.slice(0, 4096) : null;
      this.db.run('UPDATE devices SET push_token = ?, push_provider = ? WHERE id = ?', token, token ? String(b.provider || 'fcm').slice(0, 20) : null, dev.id);
      this.event(dev, token ? 'push_registered' : 'push_unregistered', b.provider || 'fcm', ip);
      return send(res, 200, { ok: true });
    }
    if (url.pathname === '/api/v1/transfer/upload' && req.method === 'POST') return this.upload(req, res, dev, url);
    if (url.pathname === '/api/v1/transfer/list') return send(res, 200, this.transfers());
    if (url.pathname.startsWith('/api/v1/transfer/file/')) return this.download(res, decodeURIComponent(url.pathname.slice('/api/v1/transfer/file/'.length)));
    if (url.pathname === '/api/v1/sms/result' && req.method === 'POST') { const b = JSON.parse((await readBody(req, 65536)).toString() || '{}'); const p = this.pendingSms.get(b.id); if (p) { this.pendingSms.delete(b.id); p.resolve(b); } return send(res, 200, { ok: true }); }
    return dispatch(this.svc.router, req, res, { device: dev, scopes: dev.scopes }, { log: this.log });
  }
  transfers() { const d = this.svc.paths.transfers; return fs.readdirSync(d).map((f) => { const st = fs.statSync(path.join(d, f)); return { name: f, size: st.size, modified: st.mtimeMs }; }).sort((a, b) => b.modified - a.modified); }
  async upload(req, res, dev, url) {
    const name = path.basename(String(url.searchParams.get('name') || `upload-${Date.now()}`)).replace(/[<>:"|?*\\]/g, '_');
    const buf = await readBody(req, 200 * 1024 * 1024).catch((e) => { send(res, e.status || 400, { error: e.message }); return null; });
    if (!buf) return;
    let dest = path.join(this.svc.paths.transfers, name);
    if (fs.existsSync(dest)) dest = path.join(this.svc.paths.transfers, `${Date.now()}-${name}`);
    fs.writeFileSync(dest, buf);
    this.svc.permissions.audit(`device:${dev.name}`, 'transfer.upload', path.basename(dest), 'write', 'ok');
    this.svc.notify.send({ title: 'File received from phone', body: `${path.basename(dest)} (${Math.round(buf.length / 1024)} KB) saved to VIPER transfers.`, category: 'general', channels: ['desktop'] });
    send(res, 200, { saved: path.basename(dest), size: buf.length });
  }
  download(res, name) {
    const file = path.join(this.svc.paths.transfers, path.basename(name));
    if (!fs.existsSync(file)) return send(res, 404, { error: 'Not found' });
    res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Disposition': `attachment; filename="${path.basename(file).replace(/"/g, '')}"` });
    fs.createReadStream(file).pipe(res);
  }

  // ---------- WebSocket ----------
  onSocket(ws, dev) {
    if (!this.sockets.has(dev.id)) this.sockets.set(dev.id, new Set());
    this.sockets.get(dev.id).add(ws);
    ws.device = dev;
    if (this.sockets.get(dev.id).size === 1) this.event(dev, 'connected', null, ws._socket?.remoteAddress);
    ws.send(JSON.stringify({ type: 'hello', data: { device: dev.name, server: os.hostname() }, ts: Date.now() }));
    this.svc.bus.publish('remote.changed', this.status());
    ws.on('message', (m) => { try { const j = JSON.parse(m); if (j.type === 'ping') ws.send(JSON.stringify({ type: 'pong', ts: Date.now() })); } catch { /* ignore */ } });
    ws.on('close', () => { this.sockets.get(dev.id)?.delete(ws); if (!this.sockets.get(dev.id)?.size) this.event(dev, 'disconnected'); this.svc.bus.publish('remote.changed', this.status()); });
    // heartbeat
    ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; });
    const hb = setInterval(() => { if (!ws.isAlive) { ws.terminate(); clearInterval(hb); return; } ws.isAlive = false; try { ws.ping(); } catch { /* closed */ } }, 30000);
    ws.on('close', () => clearInterval(hb));
  }
  forwardEvent(evt) {
    const t = evt.type;
    const allowed = /^(chat\.|agent\.(run|plan|step|decision|done|log)|notification$|tasks\.changed|models\.(download|health)|reminders\.changed|automations?\.|ui\.navigate|voice\.(stop|speak)|confirm\.(request|closed)|system\.(sample|alert)|image\.progress|conversations\.changed)/.test(t);
    if (!allowed || !this.sockets.size) return;
    if (t === 'system.sample') { if (Date.now() - this.lastSampleSent < 5000) return; this.lastSampleSent = Date.now(); }
    for (const [, set] of this.sockets) for (const ws of set) {
      // permission prompts only go to the phone that triggered them
      if (t === 'confirm.request' && evt.data.origin !== `phone: ${ws.device.name}` && !(evt.data.remoteApprovable && ws.device.scopes.includes('approve'))) continue;
      if (t.startsWith('agent.') && !ws.device.scopes.includes('agent')) continue;
      if (ws.readyState === 1) ws.send(JSON.stringify(evt));
    }
  }
  pushToDevices(msg) {
    let n = 0;
    for (const set of this.sockets.values()) for (const ws of set) if (ws.readyState === 1) { ws.send(JSON.stringify({ ...msg, ts: Date.now() })); n++; break; }
    return n;
  }
  /** Push a notification through FCM to paired phones that are not connected right now. */
  async pushViaFcm(n) {
    const f = this.svc.settings.get('notifications').fcm;
    if (!f.enabled || !this.fcm.configured()) return { sent: 0, error: f.enabled ? 'Push is enabled but no Firebase service account key is saved.' : null };
    const targets = this.db.all("SELECT id, name, push_token FROM devices WHERE revoked = 0 AND push_token IS NOT NULL AND push_provider = 'fcm'").filter((d) => !this.sockets.get(d.id)?.size);
    let sent = 0; let error = null;
    for (const d of targets) {
      // Minimal payload: no task contents pass through Google's servers.
      const r = await this.fcm.send(d.push_token, { id: n.id, kind: n.kind || 'general', title: n.title, body: n.phrase || n.title, link: n.link ? JSON.stringify(n.link) : '', actions: n.actions ? JSON.stringify(n.actions) : '', priority: n.priority });
      if (r.ok) sent++; else { error = r.error; if (r.unregistered) this.db.run('UPDATE devices SET push_token = NULL WHERE id = ?', d.id); }
    }
    return { sent, error };
  }
  /** Ask a connected phone to send an SMS (the phone shows its own approval prompt). */
  sendSmsViaPhone(to, body, timeoutMs = 120000) {
    const id = uid('sms_');
    const n = this.pushToDevices({ type: 'sms.send', data: { id, to, body } });
    if (!n) return Promise.resolve({ ok: false, error: 'No paired phone is connected' });
    return new Promise((resolve) => {
      const t = setTimeout(() => { this.pendingSms.delete(id); resolve({ ok: false, error: 'Phone did not confirm sending in time' }); }, timeoutMs);
      this.pendingSms.set(id, { resolve: (r) => { clearTimeout(t); resolve(r.sent ? { ok: true } : { ok: false, error: r.error || 'Declined on phone' }); } });
    });
  }
}

module.exports = {
  name: 'remote',
  init: (svc) => { const rl = new RemoteLink(svc); svc.notify.remote = rl; return rl; },
  start: (svc) => (svc.remote.cfg().enabled ? svc.remote.start().catch((e) => svc.remote.log.error('remote start failed', e)) : null),
  stop: (svc) => svc.remote.stop(),
  routes(r, svc) {
    const P = '/api/v1/remote';
    r.get(`${P}/status`, async () => svc.remote.status());
    r.post(`${P}/pairing`, async () => svc.remote.createPairing());
    r.post(`${P}/pairing/cancel`, async () => svc.remote.cancelPairing());
    r.get(`${P}/devices`, async () => svc.remote.devices());
    r.get(`${P}/events`, async ({ query }) => svc.remote.events(query.device || null, Number(query.limit) || 100));
    r.post(`${P}/devices/:id/revoke`, async ({ params }) => svc.remote.revoke(params.id));
    r.delete(`${P}/devices/:id`, async ({ params }) => svc.remote.remove(params.id));
    r.patch(`${P}/devices/:id`, async ({ params, body }) => svc.remote.setDevicePermissions(params.id, body));
    r.get(`${P}/transfers`, async () => svc.remote.transfers());
    r.post(`${P}/transfers`, async ({ body }) => {
      const name = path.basename(String(body.name || 'file'));
      fs.writeFileSync(path.join(svc.paths.transfers, name), Buffer.from(String(body.data).replace(/^data:[^,]*,/, ''), 'base64'));
      svc.remote.pushToDevices({ type: 'transfer.available', data: { name } });
      return { name };
    });
    r.delete(`${P}/transfers/:name`, async ({ params }) => fs.rmSync(path.join(svc.paths.transfers, path.basename(params.name)), { force: true }));
    // Notifications the phone missed while offline.
    r.get('/api/v1/notifications/since/:ts', async ({ params }) => svc.notify.since(Number(params.ts) || 0), { scope: 'read' });
  },
  ensureCert, lanAddresses, DEFAULT_SCOPES,
};
