'use strict';
// VIPER Code Agent: real files, real build/test commands, real failures and fixes. The model is
// scripted here so every branch is exercised deterministically; Windows CI also runs the agent
// with a real local coding model (test/e2e).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { fakeLLM, startViper, waitFor } = require('./helpers/env');
const { classify } = require('../src/server/agent/policy');

const lastUser = (m) => m.filter((x) => x.role === 'user').pop()?.content || '';
const fence = (code) => `Here you go:\n\`\`\`js\n${code}\n\`\`\``;
const BUGGY = 'function add(a, b) { return a - b; }\nfunction mul(a, b) { return a * b; }\nmodule.exports = { add, mul };';
const FIXED = 'function add(a, b) { return a + b; }\nfunction mul(a, b) { return a * b; }\nmodule.exports = { add, mul };';
const TEST = "const test = require('node:test'); const assert = require('node:assert');\nconst { add, mul } = require('./calc.js');\ntest('add', () => assert.strictEqual(add(2, 3), 5));\ntest('mul', () => assert.strictEqual(mul(2, 3), 6));";

async function setup(name, script) {
  const calls = [];
  const llm = await fakeLLM(async (messages, tools, body) => { calls.push({ text: lastUser(messages), json: !!body.response_format }); return script(lastUser(messages), body, calls); });
  const svc = await startViper(name);
  svc.settings.set('backend', { active: 'openai', openai: { url: llm.url } });
  svc.settings.set('models', { code: { backend: 'openai', model: 'fake-chat-tools' } });
  svc.settings.set('agent', { projectsRoot: path.join(svc.dataDir, 'projects') });
  await svc.models.checkHealth();
  const close = async () => { await svc.shutdown(); await llm.close(); };
  return { svc, llm, calls, close };
}
const waitRun = (svc, runId, statuses, ms = 60000) => new Promise((resolve, reject) => {
  const check = () => { const r = svc.agent.run(runId); if (statuses.includes(r.status)) { clearInterval(t); clearTimeout(to); resolve(r); } };
  const t = setInterval(check, 50); const to = setTimeout(() => { clearInterval(t); reject(new Error(`timeout; status ${svc.agent.run(runId).status}`)); }, ms); check();
});
const PLAN = (extra = {}) => JSON.stringify({ title: 'Calculator', stack: 'node', summary: 'A small calculator module with tests', files: [{ path: 'calc.js', purpose: 'add and multiply' }, { path: 'calc.test.js', purpose: 'unit tests' }], install: '', build: 'node --check calc.js', test: 'node --test', run: '', gui: false, question: '', options: [], ...extra });

test('builds a project from scratch: writes files, real tests fail, it fixes the bug, tests pass', async (t) => {
  let fixedOnce = false;
  const { svc, calls, close } = await setup('agent-new', (u) => {
    if (u.includes('PLAN_JSON')) return { content: PLAN() };
    if (u.includes('WRITE_FILE: calc.js')) return { content: fence(BUGGY) };
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    if (u.includes('FIX_TARGET_JSON')) return { content: JSON.stringify({ file: 'calc.js', reason: 'add() subtracts instead of adding' }) };
    if (u.includes('FIX_FILE: calc.js')) { fixedOnce = true; return { content: fence(FIXED) }; }
    return { content: 'unexpected' };
  });
  t.after(close);
  const notes = []; svc.bus.on('notification', (n) => notes.push(n));
  const p = await svc.agent.createProject({ name: 'Calculator' });
  const run = svc.agent.start(p.id, 'Create a small calculator with add and multiply, with tests');
  const done = await waitRun(svc, run.id, ['completed', 'failed']);
  assert.equal(done.status, 'completed', JSON.stringify(done.result));
  assert.ok(fixedOnce, 'the failing test was analysed and fixed');
  // files really are on disk, and the fixed version is what remains
  assert.equal(fs.readFileSync(path.join(p.path, 'calc.js'), 'utf8').trim(), FIXED);
  assert.ok(fs.existsSync(path.join(p.path, 'calc.test.js')));
  const steps = Object.fromEntries(done.plan.steps.map((s) => [s.id, s.status]));
  assert.deepEqual([steps.inspect, steps.plan, steps['file:calc.js'], steps['file:calc.test.js'], steps.build, steps.test, steps.launch, steps.report], ['complete', 'complete', 'complete', 'complete', 'complete', 'complete', 'skipped', 'complete']);
  assert.equal(done.result.test.ok, true); assert.equal(done.result.fixAttempts, 1);
  assert.deepEqual(done.result.created.sort(), ['calc.js', 'calc.test.js']);
  // real output from the real test runner was recorded, including the failure before the fix
  const ev = svc.agent.events(run.id);
  assert.ok(ev.some((e) => e.kind === 'output' && e.data.command === 'node --test' && e.data.code !== 0), 'failing test output recorded');
  assert.ok(ev.some((e) => e.kind === 'analysis' && e.data.file === 'calc.js'));
  assert.ok(calls.some((c) => c.text.includes('PLAN_JSON') && c.json), 'planning uses JSON mode');
  // completion notification only after the criteria passed
  const n = notes.find((x) => x.link?.id === run.id);
  assert.equal(n.kind, 'code_complete'); assert.equal(n.title, 'VIPER — Code Agent');
  // git checkpoints (when git is installed) allow rollback
  const cps = await svc.agent.checkpoints(p.id);
  if (cps.length) assert.ok(cps.some((c) => /VIPER checkpoint: write calc\.js/.test(c.message)));
});

test('asks a critical question, waits for the answer (desktop or phone) and plans with it', async (t) => {
  let answered = null;
  const { svc, close } = await setup('agent-ask', (u) => {
    if (u.includes('PLAN_JSON') && !u.includes('USER ANSWERED')) return { content: PLAN({ question: 'Godot or Unity?', options: ['Godot', 'Unity'] }) };
    if (u.includes('PLAN_JSON')) { answered = u.match(/USER ANSWERED YOUR QUESTION: (.*)/)[1]; return { content: PLAN() }; }
    if (u.includes('WRITE_FILE: calc.js')) return { content: fence(FIXED) };
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    return { content: '{}' };
  });
  t.after(close);
  const notes = []; svc.bus.on('notification', (n) => notes.push(n));
  const p = await svc.agent.createProject({ name: 'Game' });
  const run = svc.agent.start(p.id, 'Make a small game');
  const waiting = await waitRun(svc, run.id, ['needs_input']);
  assert.equal(waiting.decision.question, 'Godot or Unity?');
  assert.deepEqual(JSON.parse(waiting.decision.options), ['Godot', 'Unity', 'Decide automatically']);
  const n = notes.find((x) => x.kind === 'input_required');
  assert.equal(n.body, 'I need your input, sir. Godot or Unity?'); assert.equal(n.phrase, 'I need your input, sir.'); assert.deepEqual(n.link.type, 'decision');
  assert.deepEqual(n.actions.map((a) => a[1]), ['Respond', 'View Task']);
  await assert.rejects(svc.call('POST', `/agent/decisions/${waiting.decision.id}`, {}), /Choose one/);
  await svc.call('POST', `/agent/decisions/${waiting.decision.id}`, { answer: 'Godot' });
  const done = await waitRun(svc, run.id, ['completed', 'failed']);
  assert.equal(done.status, 'completed'); assert.equal(answered, 'Godot');
  await assert.rejects(svc.call('POST', `/agent/decisions/${waiting.decision.id}`, { answer: 'Unity' }), /already been answered/);
});

test('installing packages needs approval; a declined install is reported, not hidden', async (t) => {
  const { svc, close } = await setup('agent-install', (u) => {
    if (u.includes('PLAN_JSON')) return { content: PLAN({ install: 'npm install left-pad' }) };
    if (u.includes('WRITE_FILE: calc.js')) return { content: fence(FIXED) };
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    return { content: '{}' };
  });
  t.after(close);
  const asked = []; svc.bus.on('confirm.request', (r) => { if (r.tool === 'agent_command') { asked.push(r); setImmediate(() => svc.permissions.respond(r.id, false)); } });
  const p = await svc.agent.createProject({ name: 'Deps' });
  const run = svc.agent.start(p.id, 'calculator');
  const done = await waitRun(svc, run.id, ['completed', 'failed']);
  assert.equal(asked.length, 1); assert.equal(asked[0].preview, 'npm install left-pad'); assert.match(asked[0].reason, /internet/);
  assert.equal(asked[0].agent, true, 'agent approvals can be answered from the phone');
  assert.equal(done.plan.steps.find((s) => s.id === 'install').status, 'failed');
  assert.match(done.plan.steps.find((s) => s.id === 'install').detail, /Declined/);
});

test('pause, resume and cancel act on the real run', async (t) => {
  let release; const gate = new Promise((r) => { release = r; });
  const { svc, close } = await setup('agent-pause', async (u) => {
    if (u.includes('PLAN_JSON')) return { content: PLAN() };
    if (u.includes('WRITE_FILE: calc.js')) { await gate; return { content: fence(FIXED) }; }
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    return { content: '{}' };
  });
  t.after(close);
  const p = await svc.agent.createProject({ name: 'Pausable' });
  const run = svc.agent.start(p.id, 'calculator');
  await waitRun(svc, run.id, ['running']);
  svc.agent.pause(run.id);
  assert.equal(svc.agent.run(run.id).status, 'paused');
  release();
  await new Promise((r) => setTimeout(r, 600));
  // the step in progress finishes, then the run waits: the test file is not written yet
  assert.ok(!fs.existsSync(path.join(p.path, 'calc.test.js')), 'paused before the next step');
  svc.agent.resume(run.id);
  assert.equal((await waitRun(svc, run.id, ['completed', 'failed'])).status, 'completed');
  const run2 = svc.agent.start(p.id, 'again');
  await waitRun(svc, run2.id, ['running', 'planning']);
  svc.agent.cancel(run2.id);
  assert.equal((await waitRun(svc, run2.id, ['cancelled'])).status, 'cancelled');
});

test('a run interrupted by a crash is recoverable and resumes from the first unfinished step', async (t) => {
  const { svc, calls, close } = await setup('agent-recover', (u) => {
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    return { content: '{}' };
  });
  t.after(close);
  const p = await svc.agent.createProject({ name: 'Recover' });
  fs.writeFileSync(path.join(p.path, 'calc.js'), FIXED);
  const spec = JSON.parse(PLAN());
  const steps = svc.agent.buildSteps(spec).map((s) => ({ ...s, status: ['inspect', 'plan', 'file:calc.js'].includes(s.id) ? 'complete' : 'pending' }));
  svc.db.run("INSERT INTO agent_runs (id, project_id, request, status, plan, origin, created_at, updated_at) VALUES ('run_crash', ?, 'calculator', 'running', ?, 'desktop', 1, 1)", p.id, JSON.stringify({ title: 'Calculator', spec, steps }));
  // what VIPER does on the next start:
  const { init } = require('../src/server/agent/index');
  svc.agent = init(svc);
  assert.equal(svc.agent.run('run_crash').status, 'interrupted');
  svc.agent.resume('run_crash');
  const done = await waitRun(svc, 'run_crash', ['completed', 'failed']);
  assert.equal(done.status, 'completed');
  assert.ok(!calls.some((c) => c.text.includes('WRITE_FILE: calc.js')), 'completed steps are not redone');
});

test('edits an existing project to fix a failing test, writing changes to disk', async (t) => {
  const { svc, close } = await setup('agent-edit', (u) => {
    if (u.includes('PLAN_JSON')) { assert.match(u, /calc\.js/); return { content: JSON.stringify({ title: 'Fix', stack: 'node', files: [{ path: 'calc.js', purpose: 'fix add' }], build: 'node --check calc.js', test: 'node --test', run: '' }) }; }
    if (u.includes('WRITE_FILE: calc.js')) { assert.match(u, /CURRENT CONTENT OF calc\.js/); assert.match(u, /return a - b/); return { content: fence(FIXED) }; }
    return { content: '{}' };
  });
  t.after(close);
  const dir = path.join(svc.dataDir, 'existing'); fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'calc.js'), BUGGY); fs.writeFileSync(path.join(dir, 'calc.test.js'), TEST);
  svc.settings.set('privacy', { allowedFolders: [svc.dataDir] });
  const p = await svc.agent.createProject({ name: 'Existing', path: dir });
  const run = svc.agent.start(p.id, 'Fix every error in this project');
  const done = await waitRun(svc, run.id, ['completed', 'failed']);
  assert.equal(done.status, 'completed');
  assert.deepEqual(done.result.modified, ['calc.js']);
  assert.equal(fs.readFileSync(path.join(dir, 'calc.js'), 'utf8').trim(), FIXED);
  assert.equal(fs.readFileSync(path.join(dir, '.viper', 'backups', run.id, 'calc.js'), 'utf8'), BUGGY, 'previous version backed up');
});

test('a build that keeps failing ends as failed with an error notification — never "complete"', async (t) => {
  const { svc, close } = await setup('agent-fail', (u) => {
    if (u.includes('PLAN_JSON')) return { content: PLAN() };
    if (u.includes('WRITE_FILE: calc.js') || u.includes('FIX_FILE')) return { content: fence('function add(a, b) { return a +; }') };
    if (u.includes('WRITE_FILE: calc.test.js')) return { content: fence(TEST) };
    if (u.includes('FIX_TARGET_JSON')) return { content: JSON.stringify({ file: 'calc.js', reason: 'syntax error' }) };
    return { content: '{}' };
  });
  t.after(close);
  const notes = []; svc.bus.on('notification', (n) => notes.push(n));
  const p = await svc.agent.createProject({ name: 'Broken' });
  const run = svc.agent.start(p.id, 'calculator');
  const done = await waitRun(svc, run.id, ['completed', 'failed']);
  assert.equal(done.status, 'failed');
  assert.equal(done.result.fixAttempts, 4);
  assert.equal(done.plan.steps.find((s) => s.id === 'build').status, 'failed');
  assert.equal(done.plan.steps.find((s) => s.id === 'test').status, 'pending', 'tests not run on a broken build');
  const n = notes.find((x) => x.link?.id === run.id);
  assert.equal(n.kind, 'error'); assert.equal(n.title, 'VIPER — Attention Required');
  assert.ok(!notes.some((x) => ['code_complete', 'project_complete'].includes(x.kind)));
});

test('command policy: builds allowed; installs, risky git and unknown programs need approval; system tools denied', () => {
  const root = path.resolve('/tmp/proj');
  assert.equal(classify('python -m py_compile main.py', root).verdict, 'allow');
  assert.equal(classify('node --test', root).verdict, 'allow');
  assert.equal(classify('dotnet build && dotnet test', root).verdict, 'allow');
  assert.equal(classify('npm run build', root).verdict, 'allow');
  assert.equal(classify('git add -A && git commit -m x', root).verdict, 'allow');
  assert.equal(classify('pip install requests', root).verdict, 'approve');
  assert.equal(classify('pip install requests', root, { allowInstall: true }).verdict, 'allow');
  assert.equal(classify('npm install', root).verdict, 'approve');
  assert.equal(classify('git reset --hard HEAD~3', root).verdict, 'approve');
  assert.equal(classify('git push origin main', root).verdict, 'approve');
  assert.equal(classify('notepad.exe', root).verdict, 'approve');
  assert.equal(classify('python ../../secret.py', root).verdict, 'approve');
  assert.equal(classify('rm -rf /', root).verdict, 'deny');
  assert.equal(classify('del /s /q C:\\', root).verdict, 'deny');
  assert.equal(classify('powershell -c "iwr evil"', root).verdict, 'deny');
  assert.equal(classify('node build.js && shutdown /s', root).verdict, 'deny');
  assert.equal(classify('reg add HKLM\\x', root).verdict, 'deny');
});

test('guards: runaway repetition is detected; a fix that removes tests is recognised', () => {
  const { isDegenerate, testNames, isTestFile } = require('../src/server/agent/index');
  const good = Array.from({ length: 40 }, (_, i) => `    self.assertEqual(add(${i}, 1), ${i + 1})`).join('\n');
  assert.equal(isDegenerate(good), false, 'varied lines are fine');
  const loop = `import unittest\n${'        self.assertEqual(evaluate("100 * 100"), 10000)\n        self.assertEqual(evaluate("100 + 100"), 200)\n'.repeat(30)}`;
  assert.equal(isDegenerate(loop), true, 'the same lines over and over are stopped');
  const before = 'def test_add(self): pass\ndef test_divide(self): pass\n';
  const after = 'def test_add(self): pass\n';
  assert.deepEqual(testNames(before).filter((n) => !testNames(after).includes(n)), ['test_divide']);
  assert.deepEqual(testNames("test('mean', () => {}); it('formats', () => {});"), ['mean', 'formats']);
  assert.ok(isTestFile('test_calc.py') && isTestFile('stats.test.js') && isTestFile('tests/x.py') && !isTestFile('calc.py'));
});

test('model-written commands: known mistakes are corrected', () => {
  const { normalizeCommand } = require('../src/server/agent/index');
  assert.equal(normalizeCommand('python3 -m unittest discover test_calc.py'), 'python3 -m unittest discover -v');
  assert.equal(normalizeCommand('python -m unittest discover -s tests.py'), 'python -m unittest discover -v');
  assert.equal(normalizeCommand('python -m unittest discover -s tests'), 'python -m unittest discover -s tests', 'a folder is fine');
  assert.equal(normalizeCommand('npm test'), 'npm test');
  const root = require('node:fs').mkdtempSync(require('node:path').join(require('node:os').tmpdir(), 'viper-norm-'));
  require('node:fs').mkdirSync(require('node:path').join(root, 'tests'));
  assert.equal(normalizeCommand('python -m unittest discover test', 'linux', root), 'python -m unittest discover -s .', 'a missing folder would run Python\'s own "test" package');
  assert.equal(normalizeCommand('python -m unittest discover tests', 'linux', root), 'python -m unittest discover tests', 'an existing folder is kept');
  assert.equal(normalizeCommand('python -m unittest discover -v', 'linux', root), 'python -m unittest discover -v');
  assert.equal(normalizeCommand("python -m unittest discover -s . -p 'test_*.py'", 'win32'), 'python -m unittest discover -s . -p "test_*.py"', 'cmd.exe has no single quotes');
  assert.equal(normalizeCommand("python -m unittest discover -s . -p 'test_*.py'", 'linux'), "python -m unittest discover -s . -p 'test_*.py'");
});

test('placeholders left in a command are recognised (they would be shell redirects)', () => {
  const { PLACEHOLDER } = require('../src/server/agent/index');
  assert.ok(PLACEHOLDER.test('python3 calc.py <expression>'));
  assert.ok(PLACEHOLDER.test('node cli.js < input file >'));
  assert.ok(!PLACEHOLDER.test('python3 calc.py "2 + 3 * 4"'));
  assert.ok(!PLACEHOLDER.test('node -e "console.log(1<2)"'));
});

test('the same failure is recognised even when the model only edited comments or moved lines', () => {
  const { errorSignature } = require('../src/server/agent/index');
  const a = 'FAIL: test_eval (test_calc.T.test_eval)\n  File "test_calc.py", line 20, in test_eval\n    self.assertAlmostEqual(evaluate("2 + 3 * 4"), 14.0)\nAssertionError: 6.0 != 14.0 within 7 places\nRan 5 tests in 0.001s';
  const b = 'FAIL: test_eval (test_calc.T.test_eval)\n  File "test_calc.py", line 21, in test_eval\n    self.assertAlmostEqual(evaluate("2 + 3 * 4"), 14.0)  # Fixed expected value\nAssertionError: 6.0 != 14.0 within 7 places\nRan 5 tests in 0.002s';
  assert.equal(errorSignature(a), errorSignature(b));
  assert.notEqual(errorSignature(a), errorSignature(a.replace('6.0 != 14.0', '13.0 != 14.0')));
});

test('error locations: the file and line a compiler or traceback points at', () => {
  const fs = require('node:fs'); const os = require('node:os'); const path = require('node:path');
  const { errorLocations } = require('../src/server/agent/index');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'viper-loc-'));
  for (const f of ['format.js', 'stats.js', 'calc.py', 'test_calc.py']) fs.writeFileSync(path.join(root, f), '');
  assert.deepEqual(errorLocations(`${path.join(root, 'format.js')}:3\n  return n.toFixed(2;\nSyntaxError: missing ) after argument list`, root)[0], { file: 'format.js', line: 3 });
  const tb = `Traceback (most recent call last):\n  File "${path.join(root, 'test_calc.py')}", line 9, in test_x\n  File "${path.join(root, 'calc.py')}", line 21, in evaluate\nZeroDivisionError`;
  assert.deepEqual(errorLocations(tb, root)[0], { file: 'calc.py', line: 21 }, 'innermost Python frame first');
  assert.deepEqual(errorLocations('/usr/lib/node/internal.js:10 at foo', root), [], 'files outside the project are ignored');
  assert.deepEqual(errorLocations('C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\x\\format.js:3\nSyntaxError: missing )', root)[0], { file: 'format.js', line: 3 }, 'Windows short paths');
  assert.deepEqual(errorLocations('C:\\Users\\John Smith\\proj\\stats.js:7\nSyntaxError', root)[0], { file: 'stats.js', line: 7 }, 'paths with spaces');
});
