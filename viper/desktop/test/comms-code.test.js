'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { startViper, fakeLLM, waitFor } = require('./helpers/env');

// Minimal SMTP server that records messages (stands in for Gmail/Outlook SMTP in tests).
function fakeSMTP() {
  const mails = [];
  const server = net.createServer((s) => {
    let data = false; let buf = ''; let cur = { rcpt: [] }; let authed = false;
    s.write('220 fake.smtp ESMTP\r\n');
    s.on('data', (chunk) => {
      buf += chunk.toString();
      let i;
      while ((i = buf.indexOf('\r\n')) >= 0) {
        if (data) {
          const end = buf.indexOf('\r\n.\r\n');
          if (end < 0) return;
          cur.body = buf.slice(0, end); buf = buf.slice(end + 5); data = false; mails.push({ ...cur, authed }); cur = { rcpt: [] };
          s.write('250 OK queued\r\n'); continue;
        }
        const line = buf.slice(0, i); buf = buf.slice(i + 2);
        if (/^EHLO/i.test(line)) s.write('250-fake.smtp\r\n250-AUTH PLAIN LOGIN\r\n250 8BITMIME\r\n');
        else if (/^AUTH PLAIN/i.test(line)) { authed = Buffer.from(line.split(' ')[2], 'base64').toString().includes('app-password'); s.write(authed ? '235 OK\r\n' : '535 bad\r\n'); }
        else if (/^MAIL FROM/i.test(line)) { cur.from = line; s.write('250 OK\r\n'); }
        else if (/^RCPT TO/i.test(line)) { cur.rcpt.push(line.match(/<(.+)>/)[1]); s.write('250 OK\r\n'); }
        else if (/^DATA/i.test(line)) { data = true; s.write('354 go\r\n'); }
        else if (/^QUIT/i.test(line)) { s.write('221 bye\r\n'); s.end(); }
        else s.write('250 OK\r\n');
      }
    });
  });
  return new Promise((r) => server.listen(0, '127.0.0.1', () => r({ port: server.address().port, mails, close: () => new Promise((x) => server.close(x)) })));
}

test('communications: SMTP sending, confirmation, scheduling, self notifications', async (t) => {
  const smtp = await fakeSMTP();
  const llm = await fakeLLM(async () => ({ content: 'Subject: Meeting moved\n\nHi Sam,\nCould we move Thursday to Friday afternoon?\nThanks' }));
  const svc = await startViper('comms');
  t.after(async () => { await svc.shutdown(); await smtp.close(); await llm.close(); });
  svc.settings.set('backend', { active: 'openai', openai: { url: llm.url } });
  await svc.models.checkHealth();
  const acct = svc.comms.addAccount({ provider: 'imap', label: 'Test', address: 'me@example.com', password: 'app-password', imap: { host: '127.0.0.1', port: 1 }, smtp: { host: '127.0.0.1', port: smtp.port, secure: false, allowInsecure: true } });
  const answer = (v) => { const f = (r) => setImmediate(() => svc.permissions.respond(r.id, v)); svc.bus.once('confirm.request', f); };

  await t.test('password stored encrypted, never in the accounts table', () => {
    assert.ok(!JSON.stringify(svc.db.all('SELECT * FROM email_accounts')).includes('app-password'));
    assert.equal(svc.vault.get(`email.${acct.id}.password`), 'app-password');
  });
  await t.test('AI drafting returns subject and body', async () => {
    const d = await svc.comms.draft({ instructions: 'move the meeting', to: 'sam@example.com' });
    assert.equal(d.subject, 'Meeting moved'); assert.match(d.body, /Friday afternoon/);
  });
  await t.test('declined send does not reach the SMTP server', async () => {
    answer(false);
    await assert.rejects(svc.comms.send({ to: ['sam@example.com'], subject: 'x', body: 'y' }), /declined/);
    assert.equal(smtp.mails.length, 0);
  });
  await t.test('approved send delivers via authenticated SMTP and is logged', async () => {
    answer(true);
    const r = await svc.comms.send({ to: ['sam@example.com'], subject: 'Hello', body: 'Body text' });
    assert.ok(r.ok); assert.equal(smtp.mails.length, 1);
    assert.deepEqual(smtp.mails[0].rcpt, ['sam@example.com']); assert.equal(smtp.mails[0].authed, true);
    assert.match(smtp.mails[0].body, /Subject: Hello/);
    assert.equal(svc.comms.outbox()[0].status, 'sent');
  });
  await t.test('notifications by email go to the "Me" recipient without extra prompts once configured', async () => {
    svc.comms.saveRecipient({ name: 'Me', email: 'owner@example.com', isSelf: true });
    const r = await svc.notify.send({ title: 'Disk low', body: 'C: is 95% full', channels: ['email'] });
    assert.equal(r.results.email.ok, true);
    assert.deepEqual(smtp.mails[1].rcpt, ['owner@example.com']);
  });
  await t.test('scheduled email is sent by the outbox worker at the right time', async () => {
    answer(true);
    const s = await svc.comms.schedule({ to: ['sam@example.com'], subject: 'Later', body: 'Scheduled', sendAt: Date.now() + 300 });
    await new Promise((r) => setTimeout(r, 400));
    await svc.comms.processOutbox();
    assert.equal(svc.comms.outbox().find((o) => o.id === s.id).status, 'sent');
    assert.ok(smtp.mails.some((m) => /Subject: Later/.test(m.body)));
  });
  await t.test('templates and recipients CRUD; SMS refuses when not configured', async () => {
    const tpl = svc.comms.saveTemplate({ name: 'Status', subject: 'Status update', body: 'All good.' });
    assert.equal(svc.comms.templates()[0].id, tpl.id);
    const r = await svc.comms.sendSms({ to: ['me'], body: 'hi' });
    assert.equal(r.ok, false); assert.match(r.error, /not configured/);
  });
});

test('code studio: workspaces, sandboxed paths, terminal, git, diff', async (t) => {
  const svc = await startViper('code');
  t.after(() => svc.shutdown());
  svc.settings.set('privacy', { allowedFolders: [svc.dataDir] });
  const ws = await svc.code.createProject({ parent: svc.dataDir, name: 'demo', template: 'node' });

  await t.test('project scaffold and tree', async () => {
    const tree = await svc.code.tree(ws.id);
    assert.deepEqual(tree.entries.map((e) => e.name).sort(), ['README.md', 'index.js', 'index.test.js', 'package.json']);
  });
  await t.test('paths cannot escape the workspace', async () => {
    await assert.rejects(svc.code.read(ws.id, '../../etc/passwd'), /escapes the workspace/);
  });
  await t.test('editor save + AI diff preview', async () => {
    await svc.code.write(ws.id, 'index.js', 'export const x = 1;\n');
    const d = await svc.code.proposeDiff(ws.id, 'index.js', 'export const x = 2;\n');
    assert.equal(d.added, 1); assert.equal(d.removed, 1);
  });
  await t.test('test detection and terminal execution stream output', async () => {
    await svc.code.write(ws.id, 'index.js', 'export function greet(n) { return `Hello, ${n}`; }\n');
    assert.equal(svc.code.detectTests(ws.id), 'npm test');
    const out = []; const f = (d) => out.push(d); svc.bus.on('code.output', f);
    const done = waitFor(svc, (e) => e.type === 'code.exit', 60000);
    svc.code.run(ws.id, 'node --test');
    const exit = await done; svc.bus.off('code.output', f);
    assert.equal(exit.data.code, 0, out.map((o) => o.data).join(''));
    assert.match(out.map((o) => o.data).join(''), /pass 1/);
  });
  await t.test('git init, status and confirmed commit', async () => {
    execFileSync('git', ['config', '--global', 'user.email', 'test@example.com']); execFileSync('git', ['config', '--global', 'user.name', 'VIPER Test']);
    await svc.code.gitInit(ws.id);
    const st = await svc.code.gitStatus(ws.id);
    assert.equal(st.repo, true); assert.ok(st.changes.length >= 4);
    svc.bus.once('confirm.request', (r) => setImmediate(() => svc.permissions.respond(r.id, true)));
    await svc.code.gitCommit(ws.id, 'Initial commit');
    assert.equal((await svc.code.gitStatus(ws.id)).changes.length, 0);
  });
});
