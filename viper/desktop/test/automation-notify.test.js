'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startViper, waitFor } = require('./helpers/env');
const { inQuietHours } = require('../src/server/notify');
const { evalCondition } = require('../src/server/automation');

test('automation engine and notification router', async (t) => {
  const svc = await startViper('auto');
  t.after(() => svc.shutdown());
  const watch = path.join(svc.dataDir, 'Downloads'); fs.mkdirSync(watch);
  svc.settings.set('privacy', { allowedFolders: [svc.dataDir] });
  svc.settings.set('notifications', { defaultChannels: ['desktop'] });

  await t.test('validation rejects bad automations', () => {
    assert.throws(() => svc.automation.create({ name: 'x', trigger: { type: 'cron', cron: 'not cron' }, actions: [{ type: 'notify' }] }), /Invalid cron/);
    assert.throws(() => svc.automation.create({ name: 'x', trigger: { type: 'folder', folder: '/etc' }, actions: [{ type: 'notify' }] }), /allowed folders/);
    assert.throws(() => svc.automation.create({ name: 'x', trigger: { type: 'manual' }, actions: [] }), /at least one action/);
  });
  await t.test('manual run of a system report records history and notifies', async () => {
    const a = svc.automation.create({ name: 'PC status', trigger: { type: 'cron', cron: '0 8 * * *' }, actions: [{ type: 'system_report' }] });
    assert.ok(svc.automation.list().find((x) => x.id === a.id).nextRun > Date.now(), 'next run scheduled');
    const n = waitFor(svc, (e) => e.type === 'notification' && e.data.title === 'PC status report');
    const r = await svc.automation.run(a.id);
    assert.equal(r.status, 'success'); await n;
    assert.equal(svc.automation.history(a.id)[0].status, 'success');
  });
  await t.test('download-finished trigger waits for the file to be complete', async () => {
    const a = svc.automation.create({ name: 'Downloads', trigger: { type: 'download', folder: watch }, actions: [{ type: 'notify', title: 'Download finished', message: '{file}' }] });
    const fired = waitFor(svc, (e) => e.type === 'notification' && e.data.title === 'Download finished', 20000);
    fs.writeFileSync(path.join(watch, 'movie.mp4.crdownload'), 'partial');
    await new Promise((r) => setTimeout(r, 1500));
    fs.renameSync(path.join(watch, 'movie.mp4.crdownload'), path.join(watch, 'movie.mp4'));
    const e = await fired;
    assert.equal(e.data.body, 'movie.mp4');
    svc.automation.delete(a.id);
  });
  await t.test('conditions skip runs when not met', async () => {
    assert.equal(evalCondition({ field: 'system.mem.pct', op: '>', value: 50 }, { system: { mem: { pct: 70 } } }), true);
    assert.equal(evalCondition({ all: [{ field: 'file', op: 'contains', value: '.pdf' }, { field: 'x', op: '<', value: 3 }] }, { file: 'a.PDF', x: 2 }), true);
    const a = svc.automation.create({ name: 'Never', trigger: { type: 'manual' }, condition: { field: 'trigger', op: '==', value: 'nope' }, actions: [{ type: 'notify', title: 'x' }] });
    assert.equal((await svc.automation.run(a.id)).status, 'skipped');
  });
  await t.test('failed automations notify the user', async () => {
    svc.settings.set('proactive', { failedAutomations: true });
    const a = svc.automation.create({ name: 'Broken', trigger: { type: 'manual' }, actions: [{ type: 'tool', tool: 'no_such_tool' }] });
    const n = waitFor(svc, (e) => e.type === 'notification' && /Automation failed: Broken/.test(e.data.title));
    assert.equal((await svc.automation.run(a.id)).status, 'failed'); await n;
  });
  await t.test('pause and resume', () => {
    const a = svc.automation.list()[0];
    svc.automation.setEnabled(a.id, false); assert.equal(svc.automation.get(a.id).enabled, false);
    svc.automation.setEnabled(a.id, true); assert.equal(svc.automation.get(a.id).enabled, true);
  });
  await t.test('reminders fire as high-priority notifications', async () => {
    svc.reminders.add({ text: 'Stretch', dueAt: Date.now() - 1000 });
    const n = waitFor(svc, (e) => e.type === 'notification' && e.data.body === 'Stretch');
    await svc.reminders.check(); await n;
    assert.equal(svc.reminders.list('fired').length, 1);
  });
  await t.test('quiet hours, emergency mute, categories and rate limits', async () => {
    assert.equal(inQuietHours({ enabled: true, start: '22:00', end: '07:00' }, new Date('2026-01-01T23:30:00')), true);
    assert.equal(inQuietHours({ enabled: true, start: '22:00', end: '07:00' }, new Date('2026-01-01T12:00:00')), false);
    svc.settings.set('notifications', { emergencyMute: true });
    let r = await svc.notify.send({ title: 'muted', channels: ['desktop'] });
    assert.deepEqual(r.channels, []); assert.ok(r.suppressed.includes('emergency mute'));
    svc.settings.set('notifications', { emergencyMute: false, categories: { research: false } });
    r = await svc.notify.send({ title: 'cat', category: 'research', channels: ['desktop'] });
    assert.ok(r.suppressed.includes('category disabled'));
    svc.notify.registerChannel('ntfy', { label: 'fake', send: async () => ({ ok: true }) });
    svc.settings.set('notifications', { rateLimitPerHour: 2, retryAttempts: 1 });
    for (let i = 0; i < 2; i++) assert.deepEqual((await svc.notify.send({ title: `n${i}`, channels: ['ntfy'] })).channels, ['ntfy']);
    r = await svc.notify.send({ title: 'n3', channels: ['ntfy'] });
    assert.ok(r.suppressed.includes('rate limit'));
  });
  await t.test('failed deliveries are retried with backoff and can be retried manually', async () => {
    let attempts = 0;
    svc.notify.registerChannel('flaky', { label: 'flaky', send: async () => (++attempts < 2 ? { ok: false, error: 'temporary' } : { ok: true }) });
    svc.settings.set('notifications', { retryAttempts: 3 });
    const r = await svc.notify.send({ title: 'retry me', channels: ['flaky'] });
    assert.equal(r.results.flaky.ok, true); assert.equal(attempts, 2);
    const hist = svc.notify.list().find((x) => x.id === r.id);
    assert.equal(hist.deliveries[0].status, 'delivered');
  });
  await t.test('mobile channel queues when no phone is connected (never claims delivery)', async () => {
    const r = await svc.notify.send({ title: 'phone', channels: ['mobile'] });
    assert.equal(r.results.mobile.ok, false); assert.equal(r.results.mobile.queued, true);
  });
  await t.test('briefing is built from real data', async () => {
    const b = await svc.briefing.build('morning');
    assert.match(b.text, /^Good morning/); assert.match(b.text, /computer is running/);
  });
});
