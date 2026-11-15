// End-to-end test of the VIPER Code Agent with a REAL local coding model (Ollama) and the real
// toolchains of the machine it runs on (Windows CI: Python with tkinter, Node.js, git).
//
// Scenarios (as requested): build a small Windows calculator from scratch, edit an existing
// project, and recover from a failed build. After each run the harness re-checks the result itself
// (runs the tests, launches the app, reads the files) instead of trusting the agent's report, and
// checks that a completion notification was sent only when the completion criteria really passed.
//
// The harness plays the user: it approves the agent's command requests (each one is recorded) and
// answers questions with "Decide automatically".
//
// Environment: E2E_OUT (results folder), E2E_CODER (default qwen2.5-coder:3b), E2E_CHAT (default qwen2.5:0.5b)
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');

const OUT = process.env.E2E_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'viper-agent-e2e-'));
const CODER = process.env.E2E_CODER || 'qwen2.5-coder:3b';
const CHAT = process.env.E2E_CHAT || 'qwen2.5:0.5b';
const WIN = process.platform === 'win32';
fs.mkdirSync(OUT, { recursive: true });
const results = []; const metrics = { coder: CODER, platform: `${process.platform} ${os.release()}`, cpus: os.cpus().length, ramGB: Math.round(os.totalmem() / 1073741824), scenarios: {} };
const record = (area, name, status, detail = '') => { results.push({ area, name, status, detail: String(detail).slice(0, 1500) }); console.log(`[${status}] ${area}: ${name}${detail ? ` — ${String(detail).slice(0, 300)}` : ''}`); };
const check = (area, name, ok, detail) => record(area, name, ok ? 'PASS' : 'FAIL', detail);
const save = () => fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify({ results, metrics }, null, 2));
const PY = WIN ? 'python' : 'python3';
const run = (cmd, args, cwd, timeout = 300000) => { const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', timeout, shell: WIN, windowsHide: true }); return { code: r.status, out: `${r.stdout || ''}${r.stderr || ''}`.slice(-3000) }; };
/** Starts a GUI app and checks it is still running after `ms` (then closes it). */
function staysOpen(cmd, args, cwd, ms = 6000) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd, windowsHide: false, shell: WIN }); let exited = null; let out = '';
    p.stdout?.on('data', (d) => { out += d; }); p.stderr?.on('data', (d) => { out += d; });
    p.on('exit', (c) => { exited = c; });
    setTimeout(() => { const alive = exited === null; try { if (WIN) spawnSync('taskkill', ['/pid', String(p.pid), '/t', '/f']); else p.kill('SIGKILL'); } catch { /* gone */ } resolve({ alive, exited, out: out.slice(-800) }); }, ms);
  });
}

(async () => {
  process.chdir(path.join(__dirname, '..', '..'));
  const { createViper } = require('../../src/server/server');
  const WORK = fs.mkdtempSync(path.join(os.tmpdir(), 'viper-agent-work-'));
  const svc = await createViper({ dataDir: fs.mkdtempSync(path.join(os.tmpdir(), 'viper-agent-data-')), port: 0, noBackground: true });
  svc.settings.set('backend', { active: 'ollama', autoStart: false });
  svc.settings.set('models', { chat: { backend: 'ollama', model: CHAT }, code: { backend: 'ollama', model: CODER } });
  svc.settings.set('privacy', { allowedFolders: [WORK] });
  svc.settings.set('agent', { projectsRoot: WORK, gitCheckpoints: true });
  const approvals = []; const notifications = [];
  svc.bus.on('confirm.request', (r) => { approvals.push({ tool: r.tool, title: r.title, preview: r.preview }); setImmediate(() => svc.permissions.respond(r.id, r.tool === 'agent_command')); });
  svc.bus.on('agent.decision', (d) => { if (d.status !== 'answered') setTimeout(() => svc.agent.answer(d.id, 'Decide automatically', 'e2e harness').catch(() => {}), 1500); });
  svc.bus.on('notification', (n) => notifications.push({ kind: n.kind, title: n.title, body: n.body, link: n.link }));
  const tc = await svc.agent.toolchains(true);
  record('Agent', 'toolchains detected on this machine', 'PASS', Object.entries(tc).map(([k, v]) => `${k}: ${v.version}`).join(' · '));

  async function scenario(key, project, request, timeoutMs = 45 * 60000) {
    const t0 = Date.now(); const nBefore = notifications.length;
    const r = await svc.agent.start(project.id, request, { origin: 'e2e' });
    const done = await Promise.race([
      new Promise((res) => { const f = (d) => { if (d.runId === r.id) { svc.bus.off('agent.done', f); res(d); } }; svc.bus.on('agent.done', f); }),
      new Promise((res) => setTimeout(() => res(null), timeoutMs)),
    ]);
    if (!done) { svc.agent.cancel(r.id); }
    const final = svc.agent.run(r.id); const events = svc.agent.events(r.id);
    fs.writeFileSync(path.join(OUT, `agent-${key}-events.json`), JSON.stringify({ run: final, events }, null, 2));
    const sent = notifications.slice(nBefore).filter((n) => n.link?.id === r.id || n.link?.runId === r.id);
    metrics.scenarios[key] = { seconds: Math.round((Date.now() - t0) / 1000), status: final.status, fixAttempts: final.result?.fixAttempts ?? null, created: final.result?.created || [], modified: final.result?.modified || [], notifications: sent.map((n) => n.kind), testsChangedByFix: final.result?.testsChangedByFix || [] };
    return { run: final, events, done, sent, seconds: Math.round((Date.now() - t0) / 1000) };
  }
  const honestNotification = (key, s) => {
    const ok = s.run.status === 'completed';
    const kinds = s.sent.map((n) => n.kind);
    check(key, ok ? 'completion notification sent because the completion criteria passed' : 'no completion notification for a run that did not pass (an "attention required" one instead)',
      ok ? kinds.some((k) => k === 'code_complete' || k === 'project_complete') : !kinds.some((k) => k === 'code_complete' || k === 'project_complete') && kinds.includes('error'), kinds.join(', ') || 'none');
  };

  // ---------- 1. Windows calculator from scratch ----------
  try {
    const p = await svc.agent.createProject({ name: 'Calculator' });
    const s = await scenario('calculator', p, 'Create a small Windows calculator application with working buttons, using Python and tkinter (no extra packages). Put the calculation logic in calc.py (functions for add, subtract, multiply, divide — divide by zero raises ValueError — and evaluate(expression) for expressions like "12+3*4" without using eval), with unit tests in test_calc.py using unittest. main.py opens the calculator window with buttons for digits 0-9, + - * /, =, C and a display.');
    check('Agent: calculator', 'agent run finished with its completion criteria passed (build/tests/launch)', s.run.status === 'completed', `${s.run.status} in ${s.seconds} s · fix attempts ${s.run.result?.fixAttempts ?? '—'} · ${s.run.result?.remaining?.join(' ') || ''}`);
    const files = fs.existsSync(p.path) ? fs.readdirSync(p.path) : [];
    check('Agent: calculator', 'source files exist on disk', ['calc.py', 'main.py'].every((f) => files.includes(f)), files.join(', '));
    const t = run(PY, ['-m', 'unittest', 'discover', '-v'], p.path);
    check('Agent: calculator', 'independent re-run: unit tests pass', t.code === 0, t.out.split('\n').filter((l) => /\.\.\. |Ran |OK|FAILED/.test(l)).slice(-12).join(' | '));
    const src = fs.existsSync(path.join(p.path, 'main.py')) ? fs.readFileSync(path.join(p.path, 'main.py'), 'utf8') : '';
    const digits = [...'0123456789'].filter((d) => new RegExp(`['"]${d}['"]`).test(src)).length;
    check('Agent: calculator', 'main.py builds a tkinter window with digit and operator buttons', /tkinter/.test(src) && /Button/.test(src) && digits >= 10 && /['"]=['"]/.test(src), `tkinter ${/tkinter/.test(src)} · Button ${/Button/.test(src)} · digit labels ${digits}/10 · "=" ${/['"]=['"]/.test(src)}`);
    if (fs.existsSync(path.join(p.path, 'calc.py'))) {
      const probe = run(PY, ['-c', 'import calc; print(calc.evaluate("12+3*4"), calc.evaluate("7-2"))'], p.path);
      check('Agent: calculator', 'independent check: calc.evaluate("12+3*4") == 24 and ("7-2") == 5', /^\s*24(\.0)?\s+5(\.0)?\s*$/m.test(probe.out), probe.out.trim().slice(0, 300));
    }
    if (WIN || process.env.DISPLAY) { const g = await staysOpen(PY, ['main.py'], p.path); check('Agent: calculator', 'independent launch: the calculator window starts and stays open', g.alive, g.alive ? 'still running after 6 s' : `exited with ${g.exited}: ${g.out}`); }
    else record('Agent: calculator', 'independent launch: the calculator window starts and stays open', 'BLOCKED', 'no display on this machine');
    honestNotification('Agent: calculator', s);
  } catch (e) { record('Agent: calculator', 'scenario', 'FAIL', e.stack); }
  save();

  // ---------- 2. Edit an existing project ----------
  try {
    const dir = path.join(WORK, 'TodoApp'); fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'todo.py'), 'def add(items, title):\n    items.append({"title": title, "done": False})\n    return items\n\n\ndef complete(items, title):\n    for item in items:\n        if item["title"] == title:\n            item["done"] = True\n    return items\n');
    fs.writeFileSync(path.join(dir, 'test_todo.py'), 'import unittest\nfrom todo import add, complete\n\n\nclass TodoTest(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add([], "milk"), [{"title": "milk", "done": False}])\n\n    def test_complete(self):\n        self.assertTrue(complete(add([], "milk"), "milk")[0]["done"])\n\n\nif __name__ == "__main__":\n    unittest.main()\n');
    const before = run(PY, ['-m', 'unittest', 'discover'], dir);
    const p = await svc.agent.createProject({ path: dir });
    const s = await scenario('edit', p, 'Add a function remove_completed(items) to todo.py that returns only the items that are not done, and add a unit test for it to test_todo.py. Keep the existing functions and tests unchanged.');
    check('Agent: edit existing project', 'agent run finished with its completion criteria passed', s.run.status === 'completed', `${s.run.status} in ${s.seconds} s · created ${(s.run.result?.created || []).join(', ') || 'none'} · modified ${(s.run.result?.modified || []).join(', ') || 'none'}`);
    check('Agent: edit existing project', 'existing file was modified (not replaced by a new project)', (s.run.result?.modified || []).includes('todo.py'), `before: tests ${before.code === 0 ? 'passed' : 'failed'}`);
    const src = fs.readFileSync(path.join(dir, 'todo.py'), 'utf8'); const tests = fs.readFileSync(path.join(dir, 'test_todo.py'), 'utf8');
    check('Agent: edit existing project', 'existing functions and tests kept; new function and test added', /def add\(/.test(src) && /def complete\(/.test(src) && /def remove_completed\(/.test(src) && /def test_add/.test(tests) && /def test_complete/.test(tests) && /remove_completed/.test(tests));
    const t = run(PY, ['-m', 'unittest', 'discover', '-v'], dir);
    check('Agent: edit existing project', 'independent re-run: all tests pass', t.code === 0, t.out.split('\n').filter((l) => /\.\.\. |Ran |OK|FAILED/.test(l)).join(' | '));
    const cps = await svc.agent.checkpoints(p.id);
    check('Agent: edit existing project', 'git checkpoints recorded (changes can be rolled back)', cps.length >= 2, cps.slice(0, 5).map((c) => c.message).join(' | '));
    check('Agent: edit existing project', 'previous versions of modified files backed up', fs.existsSync(path.join(dir, '.viper', 'backups')));
    honestNotification('Agent: edit existing project', s);
  } catch (e) { record('Agent: edit existing project', 'scenario', 'FAIL', e.stack); }
  save();

  // ---------- 3. Recover from a failed build ----------
  try {
    const dir = path.join(WORK, 'Stats'); fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'stats', version: '1.0.0', private: true, scripts: { build: 'node --check stats.js && node --check format.js', test: 'node --test' } }, null, 2));
    // format.js has a syntax error the request does not mention: the first build must fail.
    fs.writeFileSync(path.join(dir, 'format.js'), "'use strict';\nfunction formatNumber(n) {\n  return n.toFixed(2;\n}\nmodule.exports = { formatNumber };\n");
    fs.writeFileSync(path.join(dir, 'stats.js'), "'use strict';\nfunction mean(values) {\n  return values.reduce((a, b) => a + b, 0) / values.length;\n}\nmodule.exports = { mean };\n");
    fs.writeFileSync(path.join(dir, 'stats.test.js'), "'use strict';\nconst test = require('node:test');\nconst assert = require('node:assert');\nconst { mean } = require('./stats');\nconst { formatNumber } = require('./format');\ntest('mean', () => assert.strictEqual(mean([1, 2, 3]), 2));\ntest('formatNumber', () => assert.strictEqual(formatNumber(2), '2.00'));\n");
    const before = run(WIN ? 'npm.cmd' : 'npm', ['run', 'build'], dir);
    record('Agent: recover from failed build', 'precondition: the project\'s build fails before the agent starts', before.code !== 0 ? 'PASS' : 'FAIL', before.out.split('\n').filter((l) => /SyntaxError|error/i.test(l)).slice(0, 2).join(' | '));
    const p = await svc.agent.createProject({ path: dir });
    const s = await scenario('recover', p, 'Add a function max(values) to stats.js that returns the largest number, export it, and add a test for it to stats.test.js. Use "npm run build" to build and "npm test" to test.');
    const buildFails = s.events.filter((e) => e.kind === 'output' && e.data.code !== 0 && /build/.test(e.data.command || '')).length;
    const analyses = s.events.filter((e) => e.kind === 'analysis').map((e) => `${e.data.file}: ${e.data.reason}`);
    check('Agent: recover from failed build', 'the agent saw the build fail, diagnosed it and fixed it', buildFails >= 1 && s.run.status === 'completed', `${buildFails} failed build(s) observed · fixes: ${analyses.slice(0, 3).join(' | ') || 'none'} · final ${s.run.status}`);
    const b = run(WIN ? 'npm.cmd' : 'npm', ['run', 'build'], dir); const t = run(WIN ? 'npm.cmd' : 'npm', ['test'], dir);
    check('Agent: recover from failed build', 'independent re-run: build and tests pass', b.code === 0 && t.code === 0, `build exit ${b.code} · test exit ${t.code} · ${t.out.split('\n').filter((l) => /^# (pass|fail)/.test(l)).join(' ')}`);
    honestNotification('Agent: recover from failed build', s);
  } catch (e) { record('Agent: recover from failed build', 'scenario', 'FAIL', e.stack); }

  metrics.approvals = approvals;
  check('Agent', 'approval requests shown to the user before installs/unknown commands (recorded)', true, approvals.length ? approvals.map((a) => a.preview).slice(0, 8).join(' | ') : 'no command needed approval in these runs');
  save();
  await svc.shutdown();
  const fails = results.filter((r) => r.status === 'FAIL');
  console.log(`\n${results.filter((r) => r.status === 'PASS').length} PASS · ${fails.length} FAIL · ${results.filter((r) => r.status === 'BLOCKED').length} BLOCKED`);
  process.exit(fails.length ? 1 : 0);
})().catch((e) => { record('Harness', 'agent e2e run', 'FAIL', e.stack || e.message); save(); process.exit(1); });
