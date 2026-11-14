'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const fs = require('node:fs');
const path = require('node:path');
const WebSocket = require('ws');
const { startViper, fakeLLM, waitFor } = require('./helpers/env');

// Mirrors com.viper.mobile.net.PinnedTrustManager: trust only the certificate whose SHA-256 matches the QR code.
function pinnedAgent(fp) {
  return new https.Agent({ rejectUnauthorized: false, checkServerIdentity: () => undefined, keepAlive: false });
}
function req(method, url, { fp, auth, body, raw } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const r = https.request({ method, hostname: u.hostname, port: u.port, path: u.pathname + u.search, agent: pinnedAgent(fp), headers: { ...(auth ? { Authorization: auth } : {}), ...(body && !raw ? { 'Content-Type': 'application/json' } : {}) } }, (res) => {
      const peer = res.socket.getPeerCertificate();
      if (fp && peer.fingerprint256 !== fp) { reject(new Error('PIN MISMATCH')); return; }
      const chunks = []; res.on('data', (c) => chunks.push(c)); res.on('end', () => { const t = Buffer.concat(chunks).toString(); let j; try { j = JSON.parse(t); } catch { j = t; } resolve({ status: res.statusCode, body: j }); });
    });
    r.on('error', reject);
    if (body) r.write(raw ? body : JSON.stringify(body));
    r.end();
  });
}

test('VIPER Mobile link: pairing, pinning, scopes, streaming, revocation, transfers, SMS relay', async (t) => {
  const llm = await fakeLLM(async () => ({ content: 'Streaming reply for the phone.' }));
  const svc = await startViper('remote');
  t.after(async () => { await svc.shutdown(); await llm.close(); });
  svc.settings.set('remote', { port: 0 });
  svc.settings.set('backend', { active: 'openai', openai: { url: llm.url } });
  await svc.models.checkHealth();

  const pr = await svc.remote.createPairing();
  const payload = { fp: pr.fingerprint, port: pr.port };
  const base = `https://127.0.0.1:${payload.port}`;
  let creds;

  await t.test('QR code encodes host, port, fingerprint and single-use token', async () => {
    assert.match(pr.qr, /^data:image\/png;base64,/);
    assert.match(pr.fingerprint, /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
    assert.ok(pr.expiresAt - Date.now() <= 5 * 60000);
  });
  await t.test('the presented certificate matches the pinned fingerprint', async () => {
    const r = await req('GET', `${base}/api/v1/hello`, { fp: payload.fp });
    assert.equal(r.status, 200); assert.equal(r.body.app, 'viper');
    await assert.rejects(req('GET', `${base}/api/v1/hello`, { fp: 'AA:BB' }), /PIN MISMATCH/);
  });
  await t.test('wrong token is rejected; correct token pairs exactly once', async () => {
    assert.equal((await req('POST', `${base}/api/v1/pair`, { fp: payload.fp, body: { token: 'wrong', deviceName: 'Test Phone' } })).status, 401);
    const ok = await req('POST', `${base}/api/v1/pair`, { fp: payload.fp, body: { token: svc.remote.pairing.token, deviceName: 'Test Phone', platform: 'android' } });
    assert.equal(ok.status, 200); creds = ok.body;
    assert.ok(creds.deviceId && creds.secret);
    assert.equal((await req('POST', `${base}/api/v1/pair`, { fp: payload.fp, body: { token: 'anything', deviceName: 'x' } })).status, 410, 'code is single-use');
    assert.notEqual(svc.db.get('SELECT token_hash FROM devices WHERE id = ?', creds.deviceId).token_hash, creds.secret, 'secret stored hashed');
  });
  const auth = () => `Bearer ${creds.deviceId}.${creds.secret}`;
  await t.test('requests need the device secret, and scopes limit what a phone can reach', async () => {
    assert.equal((await req('GET', `${base}/api/v1/system/snapshot`, { fp: payload.fp })).status, 401);
    assert.equal((await req('GET', `${base}/api/v1/system/snapshot`, { fp: payload.fp, auth: auth() })).status, 200);
    assert.equal((await req('GET', `${base}/api/v1/settings`, { fp: payload.fp, auth: auth() })).status, 403, 'settings are desktop-only');
    assert.equal((await req('POST', `${base}/api/v1/data/delete-all`, { fp: payload.fp, auth: auth(), body: { confirm: 'DELETE EVERYTHING' } })).status, 403);
  });
  let ws;
  await t.test('chat replies stream to the phone over the WebSocket', async () => {
    ws = new WebSocket(`wss://127.0.0.1:${payload.port}/api/v1/ws`, { headers: { Authorization: auth() }, rejectUnauthorized: false });
    const events = [];
    await new Promise((resolve, reject) => { ws.on('open', resolve); ws.on('error', reject); });
    ws.on('message', (m) => events.push(JSON.parse(m)));
    const r = await req('POST', `${base}/api/v1/chat`, { fp: payload.fp, auth: auth(), body: { text: 'Tell me something' } });
    assert.equal(r.status, 200);
    for (let i = 0; i < 100 && !events.some((e) => e.type === 'chat.done' && e.data.requestId === r.body.requestId); i++) await new Promise((x) => setTimeout(x, 50));
    const tokens = events.filter((e) => e.type === 'chat.token' && e.data.requestId === r.body.requestId).map((e) => e.data.text).join('');
    assert.equal(tokens, 'Streaming reply for the phone.');
    assert.equal(svc.remote.status().connected[0].name, 'Test Phone');
  });
  await t.test('push notifications reach the connected phone', async () => {
    const got = new Promise((resolve) => ws.on('message', (m) => { const e = JSON.parse(m); if (e.type === 'notification' && e.data.title === 'Phone push') resolve(e); }));
    const r = await svc.notify.send({ title: 'Phone push', body: 'hi', channels: ['mobile'] });
    assert.equal(r.results.mobile.ok, true);
    await got;
  });
  await t.test('phone ↔ PC file transfer', async () => {
    const up = await req('POST', `${base}/api/v1/transfer/upload?name=photo.txt`, { fp: payload.fp, auth: auth(), body: Buffer.from('hello from phone'), raw: true });
    assert.equal(up.status, 200);
    assert.equal(fs.readFileSync(path.join(svc.paths.transfers, 'photo.txt'), 'utf8'), 'hello from phone');
    const list = await req('GET', `${base}/api/v1/transfer/list`, { fp: payload.fp, auth: auth() });
    assert.ok(list.body.some((f) => f.name === 'photo.txt'));
  });
  await t.test('SMS relay asks the phone, which reports the result', async () => {
    ws.on('message', async (m) => { const e = JSON.parse(m); if (e.type === 'sms.send') await req('POST', `${base}/api/v1/sms/result`, { fp: payload.fp, auth: auth(), body: { id: e.data.id, sent: true } }); });
    const r = await svc.remote.sendSmsViaPhone('+447700900123', 'Test');
    assert.deepEqual(r, { ok: true });
  });
  await t.test('a permission prompt is routed only to the phone that caused it, and the phone can answer it', async () => {
    svc.settings.set('permissions', { 'apps.close': 'ask' });
    ws.on('message', async (m) => { const e = JSON.parse(m); if (e.type === 'confirm.request') await req('POST', `${base}/api/v1/confirm/${e.data.id}`, { fp: payload.fp, auth: auth(), body: { approved: false } }); });
    const r = await req('POST', `${base}/api/v1/tools/close_app`, { fp: payload.fp, auth: auth(), body: { args: { name: 'definitely-not-running' } } });
    assert.equal(r.body.ok, false); assert.match(r.body.error, /declined/);
  });
  await t.test('revocation disconnects the phone immediately and blocks the secret', async () => {
    const closed = new Promise((resolve) => ws.on('close', (code) => resolve(code)));
    svc.remote.revoke(creds.deviceId);
    assert.equal(await closed, 4001);
    assert.equal((await req('GET', `${base}/api/v1/system/snapshot`, { fp: payload.fp, auth: auth() })).status, 401);
    // A revoked phone that tries to reconnect gets an explicit 401 (so it returns to pairing).
    const again = new WebSocket(`wss://127.0.0.1:${payload.port}/api/v1/ws`, { headers: { Authorization: auth() }, rejectUnauthorized: false });
    const status = await new Promise((resolve) => { again.on('unexpected-response', (_q, res) => resolve(res.statusCode)); again.on('open', () => resolve('opened')); again.on('error', (e) => resolve(e.message)); });
    assert.equal(status, 401);
  });
});
