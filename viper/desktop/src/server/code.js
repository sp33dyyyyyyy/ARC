'use strict';
// Code Studio backend: user-registered workspaces, file tree/read/write,
// a workspace terminal, git integration, test detection/execution and AI
// assistance. AI-proposed file changes are returned as diffs for the user to
// apply; AI-proposed commands always require confirmation.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { spawn, execFile } = require('node:child_process');
const { uid, now } = require('./util');
const { HttpError } = require('./http');
const { unified } = require('./diff');

// Child commands get the user's environment minus VIPER/Electron/test-runner internals.
function childEnv() { const e = { ...process.env, FORCE_COLOR: '0' }; for (const k of ['NODE_TEST_CONTEXT', 'ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS']) delete e[k]; return e; }
const IGNORE = new Set(['node_modules', '.git', '__pycache__', '.venv', 'venv', 'dist', 'build', 'bin', 'obj', 'target', '.godot', '.idea', '.vs', '.next', '.cache']);
const LANG = { js: 'javascript', mjs: 'javascript', cjs: 'javascript', ts: 'typescript', tsx: 'typescript', jsx: 'javascript', py: 'python', cs: 'csharp', java: 'java', cpp: 'cpp', cc: 'cpp', c: 'c', h: 'c', hpp: 'cpp', gd: 'gdscript', lua: 'lua', html: 'html', css: 'css', json: 'json', md: 'markdown', go: 'go', rs: 'rust', rb: 'ruby', php: 'php', kt: 'kotlin', swift: 'swift', sh: 'bash', ps1: 'powershell', sql: 'sql', yaml: 'yaml', yml: 'yaml', xml: 'xml' };

class CodeStudio {
  constructor(svc) { this.svc = svc; this.db = svc.db; this.procs = new Map(); this.log = svc.logger.scope('code'); }
  workspaces() { return this.db.all('SELECT * FROM workspaces ORDER BY created_at DESC'); }
  addWorkspace({ name, path: p }) {
    const full = path.resolve(p);
    if (!fs.existsSync(full) || !fs.statSync(full).isDirectory()) throw new HttpError(400, 'Folder does not exist');
    const id = uid('ws_');
    this.db.run('INSERT INTO workspaces (id, name, path, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(path) DO NOTHING', id, name || path.basename(full), full, now());
    return this.db.get('SELECT * FROM workspaces WHERE path = ?', full);
  }
  async createProject({ parent, name, template }) {
    if (!/^[\w.-]{1,60}$/.test(name)) throw new HttpError(400, 'Project name may only use letters, numbers, dot, dash and underscore');
    if (!this.svc.permissions.isPathAllowed(parent)) throw new HttpError(403, 'Parent folder must be inside the allowed folders');
    const dir = path.join(parent, name);
    if (fs.existsSync(dir)) throw new HttpError(409, 'Folder already exists');
    const T = {
      python: { 'main.py': 'def main():\n    print("Hello from VIPER")\n\n\nif __name__ == "__main__":\n    main()\n', 'test_main.py': 'from main import main\n\n\ndef test_main(capsys):\n    main()\n    assert "Hello" in capsys.readouterr().out\n', 'README.md': `# ${name}\n` },
      node: { 'package.json': JSON.stringify({ name: name.toLowerCase(), version: '0.1.0', type: 'module', scripts: { start: 'node index.js', test: 'node --test' } }, null, 2) + '\n', 'index.js': 'export function greet(n) { return `Hello, ${n}`; }\nconsole.log(greet("VIPER"));\n', 'index.test.js': "import { test } from 'node:test';\nimport assert from 'node:assert';\nimport { greet } from './index.js';\ntest('greet', () => assert.equal(greet('x'), 'Hello, x'));\n", 'README.md': `# ${name}\n` },
      web: { 'index.html': '<!doctype html>\n<html><head><meta charset="utf-8"><title>App</title><link rel="stylesheet" href="style.css"></head>\n<body><h1>Hello</h1><script src="app.js"></script></body></html>\n', 'style.css': 'body { font-family: system-ui; background: #000; color: #fff; }\n', 'app.js': "console.log('ready');\n" },
      empty: { 'README.md': `# ${name}\n` },
    }[template || 'empty'];
    if (!T) throw new HttpError(400, 'Unknown template');
    await fsp.mkdir(dir, { recursive: true });
    for (const [f, c] of Object.entries(T)) await fsp.writeFile(path.join(dir, f), c);
    return this.addWorkspace({ name, path: dir });
  }
  removeWorkspace(id) { this.db.run('DELETE FROM workspaces WHERE id = ?', id); }
  ws(id) { const w = this.db.get('SELECT * FROM workspaces WHERE id = ?', id); if (!w) throw new HttpError(404, 'Workspace not found'); return w; }
  resolve(wsId, rel = '') {
    const w = this.ws(wsId);
    const full = path.resolve(w.path, rel);
    const r = path.relative(w.path, full);
    if (r.startsWith('..') || path.isAbsolute(r)) throw new HttpError(403, 'Path escapes the workspace');
    return { w, full, rel: r };
  }
  async tree(wsId) {
    const { w } = this.resolve(wsId);
    const out = []; let count = 0;
    const walk = async (d, depth) => {
      if (depth > 12 || count > 4000) return;
      const entries = (await fsp.readdir(d, { withFileTypes: true }).catch(() => [])).filter((e) => !IGNORE.has(e.name) && !e.name.startsWith('.git'));
      entries.sort((a, b) => (b.isDirectory() - a.isDirectory()) || a.name.localeCompare(b.name));
      for (const e of entries) {
        count++;
        const p = path.join(d, e.name);
        out.push({ path: path.relative(w.path, p).split(path.sep).join('/'), name: e.name, dir: e.isDirectory(), depth });
        if (e.isDirectory()) await walk(p, depth + 1);
      }
    };
    await walk(w.path, 0);
    return { root: w.path, name: w.name, entries: out, truncated: count > 4000 };
  }
  async read(wsId, rel) {
    const { full } = this.resolve(wsId, rel);
    const st = await fsp.stat(full);
    if (st.size > 2 * 1024 * 1024) throw new HttpError(413, 'File larger than 2 MB');
    const buf = await fsp.readFile(full);
    if (buf.includes(0)) throw new HttpError(415, 'Binary file');
    return { path: rel, content: buf.toString('utf8'), language: LANG[path.extname(rel).slice(1).toLowerCase()] || 'text', mtime: st.mtimeMs };
  }
  /** Direct save from the editor (user's own action). */
  async write(wsId, rel, content) {
    const { full } = this.resolve(wsId, rel);
    await fsp.mkdir(path.dirname(full), { recursive: true });
    await fsp.writeFile(full, content);
    this.svc.permissions.audit('user', 'code.write', rel, 'write', 'ok');
    return { saved: rel };
  }
  async remove(wsId, rel) {
    const { full } = this.resolve(wsId, rel);
    const ok = await this.svc.permissions.requestConfirmation({ tool: 'code_delete', title: `Delete ${rel}?`, preview: full, risk: 'destructive', category: 'files.delete', reason: 'The file will be sent to the Recycle Bin.', origin: 'desktop' });
    if (!ok) throw new HttpError(403, 'Declined');
    const r = await this.svc.bridge.trash(full);
    if (r?.ok === false) throw new HttpError(500, r.error);
  }
  async proposeDiff(wsId, rel, content) {
    let before = '';
    try { before = (await this.read(wsId, rel)).content; } catch { before = ''; }
    return unified(before, content, rel);
  }

  // ---- terminal ----
  run(wsId, command, { actor = 'user' } = {}) {
    const { w } = this.resolve(wsId);
    if (!command?.trim()) throw new HttpError(400, 'Empty command');
    const runId = uid('run_');
    const isWin = process.platform === 'win32';
    const p = spawn(isWin ? 'cmd.exe' : 'bash', isWin ? ['/d', '/s', '/c', command] : ['-lc', command], { cwd: w.path, windowsHide: true, env: childEnv() });
    this.procs.set(runId, p);
    this.svc.permissions.audit(actor, 'code.run', `${w.name}: ${command}`, 'write', 'started');
    const pub = (stream, data) => this.svc.bus.publish('code.output', { runId, wsId, stream, data: String(data) });
    this.svc.bus.publish('code.output', { runId, wsId, stream: 'cmd', data: `$ ${command}\n` });
    p.stdout.on('data', (d) => pub('out', d)); p.stderr.on('data', (d) => pub('err', d));
    const timer = setTimeout(() => p.kill(), 30 * 60000);
    p.on('error', (e) => pub('err', `${e.message}\n`));
    p.on('close', (code) => { clearTimeout(timer); this.procs.delete(runId); this.svc.bus.publish('code.exit', { runId, wsId, code }); });
    return { runId };
  }
  async runAndCollect(wsId, command, timeout = 600000) {
    const { w } = this.resolve(wsId);
    return new Promise((resolve) => {
      const isWin = process.platform === 'win32';
      const p = spawn(isWin ? 'cmd.exe' : 'bash', isWin ? ['/d', '/s', '/c', command] : ['-lc', command], { cwd: w.path, windowsHide: true, env: childEnv() });
      let out = ''; const t = setTimeout(() => p.kill(), timeout);
      p.stdout.on('data', (d) => { out += d; }); p.stderr.on('data', (d) => { out += d; });
      p.on('error', (e) => { clearTimeout(t); resolve({ code: -1, output: e.message }); });
      p.on('close', (code) => { clearTimeout(t); resolve({ code, output: out.slice(-20000) }); });
    });
  }
  kill(runId) { const p = this.procs.get(runId); if (p) { p.kill(); return true; } return false; }

  // ---- git ----
  git(wsId, args) {
    const { w } = this.resolve(wsId);
    return new Promise((resolve) => execFile('git', args, { cwd: w.path, windowsHide: true, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => resolve({ ok: !err, out: String(stdout), err: String(stderr || err?.message || '') })));
  }
  async gitStatus(wsId) {
    const r = await this.git(wsId, ['status', '--porcelain=v1', '-b']);
    if (!r.ok) return { repo: false, error: /not a git repository/i.test(r.err) ? 'Not a git repository' : r.err };
    const lines = r.out.split('\n').filter(Boolean);
    const branch = (lines.shift() || '').replace(/^## /, '');
    const log = await this.git(wsId, ['log', '--oneline', '-n', '15']);
    return { repo: true, branch, changes: lines.map((l) => ({ status: l.slice(0, 2).trim(), path: l.slice(3) })), log: log.ok ? log.out.split('\n').filter(Boolean) : [] };
  }
  async gitDiff(wsId, file) { return (await this.git(wsId, ['diff', '--no-color', ...(file ? ['--', file] : [])])).out.slice(0, 200000); }
  async gitCommit(wsId, message, files) {
    if (!message?.trim()) throw new HttpError(400, 'Commit message required');
    const ok = await this.svc.permissions.requestConfirmation({ tool: 'git_commit', title: 'Create git commit?', preview: `${message}\n\nFiles: ${(files?.length ? files : ['all changes']).join(', ')}`, risk: 'write', category: 'shell.workspace', reason: 'Stages the listed files and commits them to the local repository. Nothing is pushed.', origin: 'desktop' });
    if (!ok) throw new HttpError(403, 'Declined');
    const add = await this.git(wsId, ['add', '--', ...(files?.length ? files : ['.'])]);
    if (!add.ok) throw new HttpError(500, add.err);
    const c = await this.git(wsId, ['commit', '-m', message]);
    if (!c.ok) throw new HttpError(500, c.err || c.out);
    return { output: c.out };
  }
  async gitInit(wsId) { return this.git(wsId, ['init']); }

  detectTests(wsId) {
    const { w } = this.resolve(wsId);
    const has = (f) => fs.existsSync(path.join(w.path, f));
    if (has('package.json')) { try { const pj = JSON.parse(fs.readFileSync(path.join(w.path, 'package.json'), 'utf8')); if (pj.scripts?.test) return 'npm test'; } catch { /* ignore */ } return 'node --test'; }
    if (has('pytest.ini') || has('pyproject.toml') || fs.readdirSync(w.path).some((f) => /^test_.*\.py$|_test\.py$/.test(f))) return 'python -m pytest -q';
    if (fs.readdirSync(w.path).some((f) => f.endsWith('.sln') || f.endsWith('.csproj'))) return 'dotnet test';
    if (has('Cargo.toml')) return 'cargo test';
    if (has('go.mod')) return 'go test ./...';
    return null;
  }

  // ---- AI assistance ----
  async assist({ wsId, action, path: rel, selection, prompt, language, requestId }) {
    let file = null;
    if (wsId && rel) file = await this.read(wsId, rel).catch(() => null);
    const lang = language || file?.language || 'text';
    const code = selection || file?.content || '';
    const tasks = {
      explain: `Explain what this ${lang} code does, step by step, and point out anything surprising.`,
      debug: `Find bugs in this ${lang} code. For each: the problem, why it happens, and the fix. Then give the corrected code in one fenced block.`,
      refactor: `Refactor this ${lang} code for clarity and maintainability without changing behaviour. Return the complete refactored file in one fenced code block, then a short list of changes.`,
      tests: `Write thorough automated tests for this ${lang} code using the idiomatic test framework (pytest for Python, node:test for JavaScript, xUnit for C#, JUnit for Java, GUT for GDScript, busted for Lua). Return the complete test file in one fenced code block and state its file name on the first line as: File: <name>.`,
      generate: `Write ${lang} code for the following request. Return complete, runnable code in fenced blocks.`,
      error: 'Interpret this error message or stack trace. Explain the cause in plain language and how to fix it.',
      review: `Review this ${lang} code like a senior engineer: correctness, security, performance, readability.`,
    };
    const instr = tasks[action] || tasks.generate;
    const user = `${instr}${prompt ? `\n\nUser request: ${prompt}` : ''}${code ? `\n\n${rel ? `File: ${rel}\n` : ''}\`\`\`${lang}\n${code.slice(0, 24000)}\n\`\`\`` : ''}`;
    const r = await this.svc.models.complete({ role: 'code', requestId, label: `Code: ${action}`, messages: [{ role: 'system', content: this.svc.orchestrator.systemPrompt({ mode: 'code' }) }, { role: 'user', content: user }], options: { temperature: 0.2 } });
    const blocks = [...r.text.matchAll(/```[\w+#.-]*\n([\s\S]*?)```/g)].map((m) => m[1]);
    const suggestedFile = (r.text.match(/File:\s*([\w./-]+)/) || [])[1] || null;
    return { text: r.text, code: blocks[0] || null, suggestedFile, perf: r.perf };
  }
}

module.exports = {
  name: 'code',
  init: (svc) => {
    const cs = new CodeStudio(svc);
    svc.tools.register({
      name: 'run_workspace_command', label: 'Run command in workspace', category: 'shell.workspace', risk: 'destructive', keywords: ['run the tests', 'npm', 'pytest', 'build the project', 'compile'],
      description: 'Run a shell command inside a registered Code Studio workspace (e.g. run tests). Always requires the user to approve the exact command.',
      parameters: { type: 'object', properties: { workspace: { type: 'string', description: 'Workspace name' }, command: { type: 'string' } }, required: ['workspace', 'command'] },
      preview: (a) => `Workspace: ${a.workspace}\n$ ${a.command}`, confirmTitle: () => 'Run this command?',
      handler: async ({ workspace, command }) => {
        const w = cs.workspaces().find((x) => x.name.toLowerCase() === workspace.toLowerCase());
        if (!w) return { ok: false, error: `No workspace named ${workspace}` };
        const r = await cs.runAndCollect(w.id, command, 300000);
        return { ok: r.code === 0, result: { exitCode: r.code, output: r.output.slice(-6000) }, error: r.code === 0 ? undefined : `Exit code ${r.code}` };
      },
    });
    return cs;
  },
  routes(r, svc) {
    const P = '/api/v1/code';
    r.get(`${P}/workspaces`, async () => svc.code.workspaces(), { scope: 'code' });
    r.post(`${P}/workspaces`, async ({ body }) => svc.code.addWorkspace(body));
    r.post(`${P}/projects`, async ({ body }) => svc.code.createProject(body));
    r.delete(`${P}/workspaces/:id`, async ({ params }) => svc.code.removeWorkspace(params.id));
    r.get(`${P}/workspaces/:id/tree`, async ({ params }) => svc.code.tree(params.id), { scope: 'code' });
    r.get(`${P}/workspaces/:id/file`, async ({ params, query }) => svc.code.read(params.id, query.path), { scope: 'code' });
    r.put(`${P}/workspaces/:id/file`, async ({ params, body }) => svc.code.write(params.id, body.path, body.content));
    r.delete(`${P}/workspaces/:id/file`, async ({ params, query }) => svc.code.remove(params.id, query.path));
    r.post(`${P}/workspaces/:id/diff`, async ({ params, body }) => svc.code.proposeDiff(params.id, body.path, body.content), { scope: 'code' });
    r.post(`${P}/workspaces/:id/run`, async ({ params, body }) => svc.code.run(params.id, body.command));
    r.post(`${P}/kill`, async ({ body }) => ({ killed: svc.code.kill(body.runId) }));
    r.get(`${P}/workspaces/:id/tests`, async ({ params }) => ({ command: svc.code.detectTests(params.id) }));
    r.get(`${P}/workspaces/:id/git`, async ({ params }) => svc.code.gitStatus(params.id), { scope: 'code' });
    r.get(`${P}/workspaces/:id/git/diff`, async ({ params, query }) => ({ diff: await svc.code.gitDiff(params.id, query.path) }), { scope: 'code' });
    r.post(`${P}/workspaces/:id/git/commit`, async ({ params, body }) => svc.code.gitCommit(params.id, body.message, body.files));
    r.post(`${P}/workspaces/:id/git/init`, async ({ params }) => svc.code.gitInit(params.id));
    r.post(`${P}/assist`, async ({ body }) => svc.code.assist(body), { scope: 'code' });
    r.post(`${P}/compare`, async ({ body }) => require('./diff').unified(body.a || '', body.b || '', body.name || 'compare'), { scope: 'code' });
  },
};
