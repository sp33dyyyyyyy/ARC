'use strict';
// Smart notifications (JARVIS-style kinds, links, actions, duplicate prevention, FCM push for a
// closed app) and pairing services (LAN discovery, push registration, escalated approvals).
const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const http = require('node:http');
const dgram = require('node:dgram');
const crypto = require('node:crypto');
const WebSocket = require('ws');
const { startViper } = require('./helpers/env');
const { FcmSender } = require('../src/server/fcm');

function req(method, url, { auth, body } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const r = https.request({ method, hostname: u.hostname, port: u.port, path: u.pathname, rejectUnauthorized: false, headers: { ...(auth ? { Authorization: auth } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) } }, (res) => {
      let t = ''; res.on('data', (c) => { t += c; }); res.on('end', () => { let j; try { j = JSON.parse(t); } catch { j = t; } resolve({ status: res.statusCode, body: j }); });
    });
    r.on('error', reject); if (body) r.write(JSON.stringify(body)); r.end();
  });
}
async function pairedPhone(svc, name = 'Pixel Test') {
  svc.bus.on('confirm.request', (r) => { if (r.tool === 'pair_device') setImmediate(() => svc.permissions.respond(r.id, true)); });
  const pr = await svc.remote.createPairing();
  const base = `https://127.0.0.1:${pr.port}`;
  const ok = await req('POST', `${base}/api/v1/pair`, { body: { token: svc.remote.pairing.token, deviceName: name, platform: 'android' } });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  return { base, pr, auth: `Bearer ${ok.body.deviceId}.${ok.body.secret}`, id: ok.body.deviceId };
}

test('notification kinds use natural JARVIS-style wording with a configurable form of address', async (t) => {
  const svc = await startViper('ntf-kinds');
  t.after(() => svc.shutdown());
  assert.equal(svc.notify.compose('task_complete').body, 'Task complete, sir.');
  assert.equal(svc.notify.compose('input_required').title, 'VIPER — Input Required');
  assert.equal(svc.notify.compose('error').body, "I've encountered an issue, sir.");
  assert.equal(svc.notify.compose('code_complete').body, 'Your application has been built, sir.');
  svc.settings.set('personality', { address: 'boss' });
  assert.equal(svc.notify.compose('project_complete').body, 'Your project is ready for review, boss.');
  svc.settings.set('personality', { address: '' });
  assert.equal(svc.notify.compose('approval_required').body, 'May I proceed?');
  // approval actions never approve: they open the review screen or dismiss
  assert.deepEqual(svc.notify.compose('approval_required').actions.map((a) => a[0]), ['review', 'dismiss']);
});

test('deep links, actions, read state and duplicate prevention', async (t) => {
  const svc = await startViper('ntf-dedupe');
  t.after(() => svc.shutdown());
  const link = { type: 'agent_run', id: 'run_1', projectId: 'prj_1' };
  const a = await svc.notify.send({ kind: 'code_complete', detail: 'Calculator: build and tests passed.', link, channels: ['desktop'] });
  const stored = svc.notify.get(a.id);
  assert.equal(stored.kind, 'code_complete'); assert.deepEqual(stored.link, link);
  assert.deepEqual(stored.actions.map((x) => x[1]), ['View Results', 'Open VIPER']);
  assert.equal(stored.title, 'VIPER — Code Agent'); assert.match(stored.body, /^Your application has been built, sir\. Calculator/);
  const b = await svc.notify.send({ kind: 'code_complete', link, channels: ['desktop'] });
  assert.equal(b.duplicate, true); assert.equal(b.id, a.id);
  svc.notify.markRead(a.id);
  assert.equal(svc.notify.get(a.id).read, true);
  const c = await svc.notify.send({ kind: 'code_complete', link, channels: ['desktop'] });
  assert.notEqual(c.id, a.id, 'after it was read, a new event is delivered');
});

test('FCM HTTP v1: signed service-account JWT, minimal data-only payload', async (t) => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const seen = { token: null, messages: [] };
  const fake = http.createServer(async (rq, rs) => {
    let b = ''; for await (const c of rq) b += c;
    if (rq.url === '/token') {
      const assertion = new URLSearchParams(b).get('assertion'); const [h, c, sig] = assertion.split('.');
      const valid = crypto.createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, Buffer.from(sig, 'base64url'));
      seen.token = { valid, claims: JSON.parse(Buffer.from(c, 'base64url').toString()) };
      rs.writeHead(valid ? 200 : 401, { 'Content-Type': 'application/json' }); return rs.end(JSON.stringify(valid ? { access_token: 'ya29.test', expires_in: 3600 } : { error: 'bad' }));
    }
    if (rq.url === '/v1/projects/viper-test/messages:send') {
      seen.messages.push({ auth: rq.headers.authorization, body: JSON.parse(b) });
      rs.writeHead(200, { 'Content-Type': 'application/json' }); return rs.end(JSON.stringify({ name: 'projects/viper-test/messages/1' }));
    }
    rs.writeHead(404); rs.end();
  });
  await new Promise((r) => fake.listen(0, '127.0.0.1', r));
  t.after(() => fake.close());
  const base = `http://127.0.0.1:${fake.address().port}`;
  const sa = { project_id: 'viper-test', client_email: 'viper@viper-test.iam.gserviceaccount.com', private_key: pem, token_uri: `${base}/token` };

  const svc = await startViper('ntf-fcm');
  t.after(() => svc.shutdown());
  svc.settings.set('remote', { port: 0, discoveryPort: 0 });
  svc.vault.set('fcm.serviceAccount', JSON.stringify(sa));
  svc.settings.set('notifications', { fcm: { enabled: true, projectId: 'viper-test', appId: '1:2:android:3', apiKey: 'AIzaTest', senderId: '2' } });
  const phone = await pairedPhone(svc);
  svc.remote.fcm = new FcmSender({ getServiceAccount: () => svc.vault.get('fcm.serviceAccount'), apiBase: base });
  // the phone fetches the client config over the paired link and registers its FCM token
  const cfg = await req('GET', `${phone.base}/api/v1/device/push-config`, { auth: phone.auth });
  assert.equal(cfg.body.provider, 'fcm'); assert.equal(cfg.body.projectId, 'viper-test');
  assert.equal((await req('POST', `${phone.base}/api/v1/device/push`, { auth: phone.auth, body: { provider: 'fcm', token: 'fcm-registration-token-1' } })).status, 200);
  // phone not connected (app closed) → delivered through FCM
  const r = await svc.notify.send({ kind: 'input_required', detail: 'Which engine should I use for "Secret Project X"?', link: { type: 'decision', id: 'dec_1' }, channels: ['mobile'] });
  assert.equal(r.results.mobile.ok, true, JSON.stringify(r.results));
  assert.equal(seen.token.valid, true); assert.equal(seen.token.claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  const m = seen.messages[0];
  assert.equal(m.auth, 'Bearer ya29.test');
  assert.equal(m.body.message.token, 'fcm-registration-token-1');
  assert.equal(m.body.message.android.priority, 'high');
  assert.equal(m.body.message.data.title, 'VIPER — Input Required');
  assert.equal(m.body.message.data.body, 'I need your input, sir.');
  assert.ok(!JSON.stringify(m.body).includes('Secret Project X'), 'task details never leave the PC through push');
  assert.deepEqual(JSON.parse(m.body.message.data.link), { type: 'decision', id: 'dec_1' });
});

test('LAN discovery answers only a phone that knows this PC\'s certificate fingerprint', async (t) => {
  const svc = await startViper('discovery');
  t.after(() => svc.shutdown());
  const port = 40000 + Math.floor(Math.random() * 20000);
  svc.settings.set('remote', { port: 0, discoveryPort: port });
  await svc.remote.start();
  const ask = (fp) => new Promise((resolve) => {
    const s = dgram.createSocket('udp4');
    const timer = setTimeout(() => { s.close(); resolve(null); }, 700);
    s.on('message', (m) => { clearTimeout(timer); s.close(); resolve(JSON.parse(m.toString())); });
    s.send(Buffer.from(JSON.stringify({ viper: 'discover', fp })), port, '127.0.0.1');
  });
  const ok = await ask(svc.remote.tls.fingerprint.toLowerCase().replace(/:/g, ''));
  assert.equal(ok.viper, 'here'); assert.equal(ok.port, svc.remote.port);
  assert.equal(await ask('00'.repeat(32)), null, 'no answer for a different fingerprint');
});

test('approval escalated from the PC reaches the phone, which may answer it only with the approve permission', async (t) => {
  const svc = await startViper('escalate');
  t.after(() => svc.shutdown());
  svc.settings.set('remote', { port: 0, discoveryPort: 0 });
  const phone = await pairedPhone(svc);
  const ws = new WebSocket(`wss://127.0.0.1:${phone.pr.port}/api/v1/ws`, { headers: { Authorization: phone.auth }, rejectUnauthorized: false });
  await new Promise((r) => ws.on('open', r));
  const got = []; ws.on('message', (m) => got.push(JSON.parse(m)));
  const decision = svc.permissions.requestConfirmation({ tool: 'agent_command', title: 'Run npm install?', preview: 'npm install', risk: 'write', origin: 'code agent', agent: true });
  const pushed = await (async () => { for (let i = 0; i < 60; i++) { const e = got.find((x) => x.type === 'confirm.request' && x.data.remoteApprovable); if (e) return e; await new Promise((r) => setTimeout(r, 50)); } return null; })();
  assert.ok(pushed, 'phone received the approval request'); assert.equal(pushed.data.preview, 'npm install');
  assert.ok(got.some((e) => e.type === 'notification' && e.data.kind === 'approval_required' && e.data.link.id === pushed.data.id), 'with an "approval required" notification');
  // without the approve permission the phone cannot answer
  svc.remote.setDevicePermissions(phone.id, { scopes: ['read', 'chat'] });
  assert.equal((await req('POST', `${phone.base}/api/v1/confirm/${pushed.data.id}`, { auth: phone.auth, body: { approved: true } })).status, 403);
  svc.remote.setDevicePermissions(phone.id, { scopes: ['read', 'chat', 'approve'] });
  assert.equal((await req('POST', `${phone.base}/api/v1/confirm/${pushed.data.id}`, { auth: phone.auth, body: { approved: true } })).status, 200);
  assert.equal(await decision, true);
  ws.close();
});
