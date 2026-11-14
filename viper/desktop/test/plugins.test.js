'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startViper, tmpDir } = require('./helpers/env');

test('sandboxed plugins', async (t) => {
  const svc = await startViper('plugins');
  t.after(() => svc.shutdown());
  svc.settings.set('permissions', { 'plugin.tools': 'allow' });
  const example = path.join(__dirname, '..', 'plugins-examples', 'viper-utilities');

  await t.test('install requires a valid manifest and records granted permissions', async () => {
    const bad = tmpDir('badplugin'); fs.writeFileSync(path.join(bad, 'plugin.json'), JSON.stringify({ id: 'Bad Id', name: 'x', version: '1' }));
    await assert.rejects(svc.plugins.inspect(bad), /Plugin id/);
    const p = await svc.plugins.install(example, ['storage']);
    assert.deepEqual(p.granted, ['storage']); assert.equal(p.enabled, false);
  });
  await t.test('enabled plugin contributes tools, widgets, pages and actions', async () => {
    await svc.plugins.enable('viper.utilities');
    const r = await svc.tools.execute('convert_units', { value: 100, from: 'celsius', to: 'fahrenheit' });
    assert.equal(r.result.result, 212);
    assert.equal((await svc.plugins.widgets())[0].lines.length, 4);
    const page = await svc.plugins.call('viper.utilities', 'pages', 'scratchpad', { text: 'note one' });
    assert.match(page.markdown, /note one/);
    const a = svc.automation.create({ name: 'plugin action', trigger: { type: 'manual' }, actions: [{ type: 'plugin', plugin: 'viper.utilities', action: 'log_note', args: { text: 'from automation' } }] });
    assert.equal((await svc.automation.run(a.id)).status, 'success');
  });
  await t.test('sandbox has no Node/browser globals and ungranted permissions fail', async () => {
    const dir = tmpDir('evil');
    fs.writeFileSync(path.join(dir, 'plugin.json'), JSON.stringify({ id: 'test.evil', name: 'Evil', version: '1.0.0', permissions: ['http:example.com'], contributes: { tools: [{ name: 'probe_env', description: 'probe' }, { name: 'spin_forever', description: 'loop' }, { name: 'net_probe', description: 'net' }] } }));
    fs.writeFileSync(path.join(dir, 'main.js'), `
      plugin.tools.probe_env = async () => [typeof require, typeof process, typeof fetch, typeof XMLHttpRequest, typeof globalThis.__viper.storageGet].join(',');
      plugin.tools.spin_forever = async () => { while (true) {} };
      plugin.tools.net_probe = async () => (await viper.http('https://example.com/')).status;`);
    await svc.plugins.install(dir, []); // grant nothing
    await svc.plugins.enable('test.evil');
    assert.equal((await svc.tools.execute('probe_env', {})).result, 'undefined,undefined,undefined,undefined,function');
    const net = await svc.tools.execute('net_probe', {});
    assert.equal(net.ok, false); assert.match(net.error, /not granted/);
    const t0 = Date.now();
    const loop = await svc.tools.execute('spin_forever', {});
    assert.equal(loop.ok, false); assert.ok(Date.now() - t0 < 25000, 'runaway plugin interrupted');
  });
  await t.test('disable and uninstall remove contributions', async () => {
    await svc.plugins.uninstall('test.evil');
    assert.equal(svc.tools.get('probe_env'), undefined);
    await svc.plugins.disable('viper.utilities');
    assert.equal(svc.tools.get('convert_units'), undefined);
  });
});
