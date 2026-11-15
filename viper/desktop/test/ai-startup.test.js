'use strict';
// Automatic AI start-up: VIPER finds, starts, loads and verifies the local AI engine by itself.
// A real stand-in engine process (helpers/fake-ollama.js) is launched, connected to and stopped.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { startViper, waitFor } = require('./helpers/env');

const FAKE = path.join(__dirname, 'helpers', 'fake-ollama.js');
const freePort = () => new Promise((r) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const until = async (fn, ms = 10000) => { const end = Date.now() + ms; while (Date.now() < end) { if (await fn()) return true; await new Promise((r) => setTimeout(r, 50)); } return false; };

/** A VIPER core whose "Ollama" is the fake engine; returns spawn calls for inspection. */
async function viperWithEngine(name, { env = {}, installed = true } = {}) {
  const port = await freePort();
  const spawns = [];
  const spawnFn = (exe, args, o) => { const p = spawn(process.execPath, [FAKE, ...args], { ...o, env: { ...o.env, ...env } }); spawns.push(p); return p; };
  const svc = await startViper(name, { aiStartup: { spawnFn, retryDelays: [50, 50], timeouts: { engine: 8000, model: 20000, verify: 20000 } } });
  svc.settings.set('backend', { active: 'ollama', ollama: { url: `http://127.0.0.1:${port}`, path: installed ? FAKE : path.join(svc.dataDir, 'missing', 'ollama.exe') } });
  svc.settings.set('models', { chat: { backend: '', model: '' } });
  return { svc, port, spawns };
}
const stages = (svc) => { const seen = []; svc.bus.on('event', (e) => { if (e.type === 'ai.startup' && seen[seen.length - 1] !== e.data.stage) seen.push(e.data.stage); }); return seen; };

test('engine not running: VIPER starts it, loads the model, verifies it and reports ready', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-cold');
  t.after(() => svc.shutdown());
  const seen = stages(svc);
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'ready', st.detail);
  assert.ok(seen.indexOf('starting') > seen.indexOf('engine') && seen.indexOf('verify') > seen.indexOf('model') && seen[seen.length - 1] === 'ready', seen.join(' > '));
  assert.equal(spawns.length, 1);
  assert.equal(st.owned, true);
  assert.equal(st.model, 'qwen2.5:3b');
  assert.match(st.detail, /answered in \d+ ms/);
  // remembered for the next launch
  assert.equal(svc.settings.get('models').chat.model, 'qwen2.5:3b');
  assert.equal(svc.settings.get('app').lastWorkingModel.model, 'qwen2.5:3b');
  // a real generated reply right after "ready"
  const r = svc.orchestrator.handle({ text: 'Hello VIPER' }); const res = await r.done;
  assert.match(res.message.content, /Hello! VIPER here/);
  // VIPER started the engine, so VIPER stops it on exit
  const pid = spawns[0].pid; assert.ok(alive(pid));
  await svc.aiStartup.shutdown();
  assert.ok(await until(() => !alive(pid)), 'owned engine stopped on exit');
});

test('engine already running: VIPER connects without starting a second copy, and never stops it', async (t) => {
  const { svc, port, spawns } = await viperWithEngine('start-warm');
  const ext = spawn(process.execPath, [FAKE], { env: { ...process.env, OLLAMA_HOST: `127.0.0.1:${port}` }, stdio: 'ignore' });
  t.after(async () => { await svc.shutdown(); ext.kill(); });
  await until(async () => (await svc.models.backend('ollama').health()).ok);
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'ready');
  assert.equal(spawns.length, 0, 'no duplicate engine process');
  assert.equal(st.owned, false);
  svc.aiStartup.shutdown();
  await new Promise((r) => setTimeout(r, 300));
  assert.ok(alive(ext.pid), 'an engine VIPER did not start keeps running');
});

test('concurrent start-up requests share one run (no duplicate start or warm-up)', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-dedupe');
  t.after(() => svc.shutdown());
  const [a, b, c] = await Promise.all([svc.aiStartup.run('launch'), svc.aiStartup.run('settings'), svc.aiStartup.run('retry')]);
  assert.equal(a.stage, 'ready'); assert.equal(b.stage, 'ready'); assert.equal(c.stage, 'ready');
  assert.equal(spawns.length, 1);
});

test('engine crash after ready: watchdog restarts it automatically', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-crash');
  t.after(() => svc.shutdown());
  assert.equal((await svc.aiStartup.run('launch')).stage, 'ready');
  const recovered = waitFor(svc, (e) => e.type === 'models.recovered', 20000);
  spawns[0].kill('SIGKILL');
  await recovered;
  assert.equal(svc.aiStartup.status().stage, 'ready');
  assert.equal(spawns.length, 2);
  assert.ok(alive(spawns[1].pid));
});

test('recovery is rate-limited: no endless restart loop, and Retry resets it', async (t) => {
  const { svc } = await viperWithEngine('start-ratelimit');
  t.after(() => svc.shutdown());
  assert.equal((await svc.aiStartup.run('launch')).stage, 'ready');
  for (let i = 0; i < 3; i++) assert.equal(await svc.aiStartup.recover('test'), true);
  assert.equal(await svc.aiStartup.recover('test'), false);
  const st = svc.aiStartup.status();
  assert.equal(st.stage, 'error'); assert.equal(st.retry, true); assert.match(st.detail, /Automatic recovery has paused/);
  const again = await svc.call('POST', '/ai/startup/retry');
  assert.equal(again.stage, 'ready');
});

test('engine not installed: setup is required (no retry loop), with an install offer', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-missing', { installed: false });
  const savedPath = process.env.PATH; process.env.PATH = '';
  t.after(() => { process.env.PATH = savedPath; return svc.shutdown(); });
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'setup'); assert.equal(st.need, 'engine'); assert.match(st.detail, /not installed/);
  assert.equal(spawns.length, 0);
});

test('no model installed: setup offers the model recommended for this PC', async (t) => {
  const { svc } = await viperWithEngine('start-nomodel', { env: { FAKE_MODELS: '' } });
  t.after(() => svc.shutdown());
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'setup'); assert.equal(st.need, 'model'); assert.ok(st.recommended, 'a model is recommended');
});

test('preferred model no longer installed: falls back to an installed one and says so', async (t) => {
  const { svc } = await viperWithEngine('start-fallback', { env: { FAKE_MODELS: 'llama3.2:3b,moondream' } });
  t.after(() => svc.shutdown());
  svc.settings.set('models', { chat: { backend: 'ollama', model: 'qwen2.5:7b' } });
  const note = waitFor(svc, (e) => e.type === 'notification' && /no longer installed/.test(e.data.body), 15000);
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'ready'); assert.equal(st.model, 'llama3.2:3b');
  await note;
});

test('engine that cannot start: limited retries, then a clear error with Retry', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-broken', { env: { FAKE_EXIT: '3' } });
  t.after(() => svc.shutdown());
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'error'); assert.equal(st.retry, true);
  assert.match(st.detail, /could not start \(exited with code 3\)/);
  assert.equal(spawns.length, 3, 'exactly 3 attempts');
});

test('an unresponsive engine left by a previous session is cleaned up before starting', async (t) => {
  const { svc, spawns } = await viperWithEngine('start-stale');
  const stale = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
  fs.mkdirSync(path.join(svc.dataDir, 'run'), { recursive: true });
  fs.writeFileSync(path.join(svc.dataDir, 'run', 'engine.pid'), JSON.stringify({ pid: stale.pid }));
  t.after(async () => { stale.kill(); await svc.shutdown(); });
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.stage, 'ready');
  assert.ok(await until(() => !alive(stale.pid)), 'stale process stopped');
  assert.equal(spawns.length, 1);
});

test('a message sent during start-up is answered once the model is ready', async (t) => {
  const { svc } = await viperWithEngine('start-wait', { env: { FAKE_DELAY_MS: '600' } });
  t.after(() => svc.shutdown());
  const run = svc.aiStartup.run('launch');
  await new Promise((r) => setTimeout(r, 100));
  const r = svc.orchestrator.handle({ text: 'Hello VIPER' });
  const res = await r.done;
  assert.equal((await run).stage, 'ready');
  assert.match(res.message.content, /Hello! VIPER here/);
});

test('startup greeting is only offered after a successful launch when enabled', async (t) => {
  const { svc } = await viperWithEngine('start-greet');
  t.after(() => svc.shutdown());
  svc.settings.set('voice', { startupGreeting: true });
  const st = await svc.aiStartup.run('launch');
  assert.equal(st.greeting, 'VIPER systems online. Local intelligence operational.');
  const again = await svc.aiStartup.run('settings changed');
  assert.equal(again.greeting, null, 'not repeated on later re-runs');
});
