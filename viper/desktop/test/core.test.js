'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { startViper } = require('./helpers/env');
const { parseDue, parseSchedule } = require('../src/server/timeparse');
const { sanitize } = require('../src/server/log');

test('database, settings, vault and memory', async (t) => {
  const svc = await startViper('core');
  t.after(() => svc.shutdown());

  await t.test('schema migrated', () => { assert.equal(svc.db.version, 2); assert.ok(svc.db.get("SELECT name FROM sqlite_master WHERE name = 'memories_fts'")); });
  await t.test('settings persist and deep-merge', () => {
    svc.settings.set('personality', { userName: 'Tony', humour: 0.9 });
    const p = svc.settings.get('personality');
    assert.equal(p.userName, 'Tony'); assert.equal(p.formality, 0.7);
    const { Settings } = require('../src/server/settings');
    assert.equal(new Settings(svc.db, svc.bus).get('personality').humour, 0.9);
  });
  await t.test('vault encrypts at rest', () => {
    svc.vault.set('test.secret', 'hunter2');
    assert.equal(svc.vault.get('test.secret'), 'hunter2');
    const raw = svc.db.get("SELECT value FROM secrets WHERE name = 'test.secret'").value;
    assert.ok(!Buffer.from(raw).toString('utf8').includes('hunter2'));
  });
  await t.test('memory add / search / dedupe / update / export / import / delete', () => {
    const m = svc.memory.add({ content: 'The user prefers short responses', category: 'preference' });
    assert.equal(svc.memory.add({ content: 'the user prefers short responses' }).duplicate, true);
    svc.memory.add({ content: 'Project Falcon launches in March', category: 'project' });
    assert.equal(svc.memory.search('falcon')[0].category, 'project');
    assert.ok(svc.memory.relevant('anything').some((x) => x.id === m.id), 'preferences always injected');
    svc.memory.update(m.id, { content: 'The user prefers very short responses' });
    assert.match(svc.memory.get(m.id).content, /very short/);
    const exp = svc.memory.export();
    svc.memory.clear();
    assert.equal(svc.memory.list().length, 0);
    assert.equal(svc.memory.import(exp).added, 2);
    assert.equal(svc.memory.delete(svc.memory.list()[0].id), true);
  });
  await t.test('temporary memory mode keeps memories out of the database', () => {
    svc.settings.set('privacy', { temporaryMemory: true });
    const m = svc.memory.add({ content: 'Temporary note' });
    assert.equal(m.temporary, true);
    assert.equal(svc.db.get('SELECT COUNT(*) AS n FROM memories WHERE id = ?', m.id).n, 0);
    svc.settings.set('privacy', { temporaryMemory: false });
  });
  await t.test('API rejects missing/invalid token and foreign Host headers', async () => {
    assert.equal((await fetch(`${svc.url}/api/v1/status`)).status, 401);
    assert.equal((await fetch(`${svc.url}/api/v1/status`, { headers: { Authorization: 'Bearer nope' } })).status, 401);
    const http = require('node:http');
    const status = await new Promise((resolve) => { http.get({ host: '127.0.0.1', port: svc.port, path: '/api/v1/status', headers: { Host: 'evil.example:80', Authorization: `Bearer ${svc.localToken}` } }, (r) => resolve(r.statusCode)); });
    assert.equal(status, 421, 'DNS-rebinding guard');
  });
  await t.test('static server blocks path traversal and sets CSP', async () => {
    const r = await fetch(`${svc.url}/`); assert.match(r.headers.get('content-security-policy'), /default-src 'self'/);
    const http = require('node:http');
    const code = await new Promise((resolve) => http.get({ host: '127.0.0.1', port: svc.port, path: '/../../server/server.js' }, (res) => resolve(res.statusCode)));
    assert.notEqual(code, 200);
  });
});

test('natural-language time parsing', () => {
  const now = new Date('2026-11-13T10:00:00');
  assert.equal(new Date(parseDue('in 20 minutes', now)).getMinutes(), 20);
  assert.equal(new Date(parseDue('at 8 PM', now)).getHours(), 20);
  const tom = new Date(parseDue('tomorrow at 9:30am', now)); assert.equal(tom.getDate(), 14); assert.equal(tom.getMinutes(), 30);
  assert.equal(parseDue('later', now), null);
  assert.deepEqual(parseSchedule('every 30 minutes'), { type: 'interval', minutes: 30 });
  assert.equal(parseSchedule('every morning').cron, '0 8 * * *');
  assert.equal(parseSchedule('weekdays at 7:30am').cron, '30 7 * * 1-5');
  assert.equal(parseSchedule('at 8pm'), null, 'one-off times are not recurring');
});

test('log sanitiser redacts secrets', () => {
  const s = sanitize('Authorization: Bearer abc.def password=hunter2 {"api_key":"sk-1234567890abcdef"} https://x?token=zzz');
  for (const leak of ['abc.def', 'hunter2', 'sk-1234567890abcdef', 'zzz']) assert.ok(!s.includes(leak), `leaked ${leak}: ${s}`);
});
