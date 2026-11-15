import { h, clear, icon, btn, busy, toast, toastError, mdEl, prompt, ask, modal, field, select } from '../ui.js';

export async function render(view, { app, api }) {
  view.className = 'view flush';
  let ws = null; let file = null; let dirty = false; let runId = null;
  const wsSel = h('select.input', { style: { width: '220px' }, 'aria-label': 'Workspace', onchange: (e) => openWs(e.target.value) });
  const tree = h('div.tree'); const editor = h('textarea', { spellcheck: false, 'aria-label': 'Editor', oninput: () => { dirty = true; fileLabel.textContent = `${file?.path || ''} ●`; } });
  const fileLabel = h('span.grow.mist', {}, 'No file open'); const term = h('div.terminal', { 'aria-live': 'polite' });
  const cmdIn = h('input.input', { placeholder: 'Command, e.g. npm test', style: { fontFamily: 'var(--mono)' }, onkeydown: (e) => { if (e.key === 'Enter') runCmd(cmdIn.value); } });
  const assistOut = h('div', { style: { overflowY: 'auto', flex: 1, padding: '10px 12px' } });
  const assistIn = h('textarea.input', { rows: 3, placeholder: 'Ask about this file, or describe code to write' });
  const lang = h('select.input', {}, ['python', 'javascript', 'typescript', 'html', 'css', 'csharp', 'java', 'cpp', 'gdscript', 'lua', 'go', 'rust', 'bash', 'powershell', 'sql'].map((l) => h('option', { value: l }, l)));
  const gitBox = h('div');
  editor.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') { e.preventDefault(); const s = editor.selectionStart; editor.setRangeText('  ', s, editor.selectionEnd, 'end'); dirty = true; }
    if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); save(); }
  });
  view.append(h('div.row.wrap', { style: { padding: '10px 14px', borderBottom: '1px solid var(--line)' } }, h('h2', {}, 'Code Studio'), wsSel,
    btn('Open folder', addWs, { cls: 'sm', ico: 'folder' }), btn('New project', newProject, { cls: 'sm', ico: 'plus' }),
    h('span.grow'), btn('Analyse codebase', analyse, { cls: 'sm' }), btn('Compare…', compareDialog, { cls: 'sm' })),
  h('div.code-layout', { style: { flex: '1', minHeight: '0' } },
    h('div.tree', {}, tree),
    h('div.editor', {}, h('div.row', { style: { padding: '6px 12px', borderBottom: '1px solid var(--line)' } }, fileLabel, btn('Save', save, { cls: 'sm', title: 'Ctrl+S' }), btn('Preview', previewFile, { cls: 'sm' }), btn('', newFile, { cls: 'sm ghost icon', ico: 'plus', title: 'New file' }), btn('', delFile, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete file' })),
      editor,
      h('div.row', { style: { padding: '6px 12px', borderTop: '1px solid var(--line)' } }, icon('terminal'), h('div.grow', {}, cmdIn), btn('Run', () => runCmd(cmdIn.value), { cls: 'sm' }), btn('Run tests', runTests, { cls: 'sm' }), btn('Stop', () => runId && api.post('/code/kill', { runId }), { cls: 'sm ghost' })),
      term),
    h('div.assist', {},
      h('div.tabs', { style: { margin: 0 } }, h('button.on', {}, 'Assistant'), h('button', { onclick: (e) => { e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === e.currentTarget)); drawGit(); } }, 'Git')),
      assistOut, gitBox,
      h('div.col', { style: { padding: '10px 12px', borderTop: '1px solid var(--line)' } }, assistIn,
        h('div.row.wrap', {}, ...[['explain', 'Explain'], ['debug', 'Debug'], ['refactor', 'Refactor'], ['tests', 'Write tests'], ['review', 'Review'], ['error', 'Explain error']].map(([a, l]) => btn(l, (e) => busy(e.currentTarget, () => assist(a)), { cls: 'sm' }))),
        h('div.row', {}, h('div.grow', {}, lang), btn('Generate', (e) => busy(e.currentTarget, () => assist('generate')), { cls: 'primary sm', ico: 'sparkle' }))))));

  async function loadWorkspaces(selectId) {
    const list = await api.get('/code/workspaces').catch(() => []);
    clear(wsSel).append(h('option', { value: '' }, list.length ? 'Choose workspace' : 'No workspaces yet'), ...list.map((w) => h('option', { value: w.id, selected: w.id === (selectId || ws) }, w.name)));
    if (selectId || (!ws && list[0])) openWs(selectId || list[0].id);
    if (!list.length) clear(assistOut).append(h('div.empty', {}, h('b', {}, 'Open a folder to start'), 'VIPER only reads and changes files inside workspaces you open here. Commands it proposes always need your approval.'));
  }
  async function addWs() {
    const p = window.viperNative?.pickFolder ? await window.viperNative.pickFolder() : await prompt('Open folder as workspace', { label: 'Full folder path' });
    if (!p) return;
    try { const w = await api.post('/code/workspaces', { path: p }); loadWorkspaces(w.id); } catch (e) { toastError(e); }
  }
  async function newProject() {
    const name = h('input.input', { placeholder: 'my-project' }); let tpl = 'python';
    const parent = app.settings.privacy.allowedFolders[0];
    modal({ title: 'New project', body: h('div.col', {}, field('Name', name), field('Template', select([['python', 'Python (with pytest test)'], ['node', 'Node.js (with node:test)'], ['web', 'HTML/CSS/JS'], ['empty', 'Empty']], tpl, (v) => { tpl = v; })), h('small.mist', {}, `Created in ${parent}`)),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Create', cls: 'primary', onClick: async () => { try { const w = await api.post('/code/projects', { parent, name: name.value, template: tpl }); loadWorkspaces(w.id); } catch (e) { toastError(e); return false; } } }] });
  }
  async function openWs(id) {
    if (!id) return; ws = id; file = null; editor.value = ''; fileLabel.textContent = 'No file open'; wsSel.value = id;
    const t = await api.get(`/code/workspaces/${id}/tree`).catch((e) => { toastError(e); return { entries: [] }; });
    clear(tree);
    const collapsed = new Set(t.entries.filter((e) => e.dir && e.depth > 0).map((e) => e.path));
    const draw = () => {
      clear(tree);
      for (const e of t.entries) {
        if ([...collapsed].some((c) => e.path.startsWith(`${c}/`))) continue;
        tree.append(h(`div.node${file?.path === e.path ? '.on' : ''}`, { style: { paddingLeft: `${6 + e.depth * 12}px` }, title: e.path, onclick: () => { if (e.dir) { collapsed.has(e.path) ? collapsed.delete(e.path) : collapsed.add(e.path); draw(); } else openFile(e.path); } }, e.dir ? (collapsed.has(e.path) ? '▸ ' : '▾ ') : '  ', e.name));
      }
    };
    draw();
  }
  async function openFile(p) {
    if (dirty && !(await ask('Discard changes?', `${file.path} has unsaved changes.`, { confirmLabel: 'Discard', danger: true }))) return;
    try { file = await api.get(`/code/workspaces/${ws}/file?path=${encodeURIComponent(p)}`); editor.value = file.content; dirty = false; fileLabel.textContent = file.path; if ([...lang.options].some((o) => o.value === file.language)) lang.value = file.language; } catch (e) { toastError(e); }
    tree.querySelectorAll('.node').forEach((n) => n.classList.toggle('on', n.title === p));
  }
  async function save() { if (!file) return; try { await api.req('PUT', `/code/workspaces/${ws}/file`, { path: file.path, content: editor.value }); dirty = false; fileLabel.textContent = file.path; toast('Saved', file.path); } catch (e) { toastError(e); } }
  async function newFile() { if (!ws) return; const p = await prompt('New file', { label: 'Path inside the workspace', placeholder: 'src/new_file.py' }); if (!p) return; await api.req('PUT', `/code/workspaces/${ws}/file`, { path: p, content: '' }); await openWs(ws); openFile(p); }
  async function delFile() { if (!file) return; try { await api.req('DELETE', `/code/workspaces/${ws}/file?path=${encodeURIComponent(file.path)}`); file = null; editor.value = ''; openWs(ws); } catch (e) { toastError(e); } }
  function previewFile() {
    if (!file) return;
    if (/^(html|css|markdown)$/.test(file.language)) {
      const body = file.language === 'markdown' ? mdEl(editor.value) : h('iframe', { sandbox: '', srcdoc: file.language === 'css' ? `<style>${editor.value}</style><h1>Heading</h1><p>Paragraph text</p><button>Button</button>` : editor.value, style: { width: '100%', height: '60vh', border: '1px solid var(--line)', background: '#fff' }, title: 'Static preview' });
      modal({ title: `Preview — ${file.path}`, wide: true, body: h('div', {}, body, h('small.mist', {}, 'Static preview: scripts are disabled for safety. Run the project from the terminal for full behaviour.')) });
    } else toast('No preview', 'Previews are available for HTML, CSS and Markdown files. Use the terminal to run other code.');
  }
  function runCmd(cmd) { if (!ws || !cmd.trim()) return; api.post(`/code/workspaces/${ws}/run`, { command: cmd }).then((r) => { runId = r.runId; }).catch(toastError); cmdIn.value = ''; }
  async function runTests() { if (!ws) return; const r = await api.get(`/code/workspaces/${ws}/tests`); if (!r.command) { toast('No test runner detected', 'Type the test command in the terminal instead.'); return; } runCmd(r.command); }
  async function assist(action) {
    const text = assistIn.value.trim();
    if (action === 'generate' && !text) { toast('Describe what to write'); return; }
    const selection = editor.selectionEnd > editor.selectionStart ? editor.value.slice(editor.selectionStart, editor.selectionEnd) : null;
    clear(assistOut).append(h('div.progress.indet', {}, h('i')));
    try {
      const r = await api.post('/code/assist', { wsId: ws, path: file?.path, selection: selection || (action === 'generate' || action === 'error' ? null : editor.value), prompt: text, action, language: action === 'generate' ? lang.value : file?.language });
      clear(assistOut).append(mdEl(r.text), r.code ? h('div.row.wrap', { style: { marginTop: '8px' } },
        file && ['refactor', 'debug'].includes(action) ? btn('Review & apply to file', () => applyDiff(file.path, r.code), { cls: 'sm primary' }) : null,
        action === 'tests' || action === 'generate' ? btn('Save as new file…', async () => { const p = await prompt('Save code as', { value: r.suggestedFile || '' }); if (p) applyDiff(p, r.code); }, { cls: 'sm' }) : null,
        btn('Copy code', () => navigator.clipboard?.writeText(r.code), { cls: 'sm' })) : null,
      r.perf?.tokPerS ? h('small.mist', {}, `${r.perf.tokPerS} tok/s`) : null);
    } catch (e) { clear(assistOut).append(h('p', {}, e.message)); }
  }
  async function applyDiff(p, content) {
    if (!ws) { toast('Open a workspace first'); return; }
    const d = await api.post(`/code/workspaces/${ws}/diff`, { path: p, content });
    const pre = h('div.diff', { style: { maxHeight: '55vh', overflow: 'auto', border: '1px solid var(--line)' } }, d.text.split('\n').map((l) => h(`div${l.startsWith('+') && !l.startsWith('+++') ? '.add' : l.startsWith('-') && !l.startsWith('---') ? '.del' : ''}`, {}, l)));
    modal({ title: `Apply changes to ${p}?`, wide: true, body: h('div', {}, h('p.small.mist', {}, `${d.added} lines added, ${d.removed} removed. Nothing is written until you apply.`), pre),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Apply changes', cls: 'primary', onClick: async () => { await api.req('PUT', `/code/workspaces/${ws}/file`, { path: p, content }); toast('Changes applied', p); await openWs(ws); dirty = false; openFile(p); } }] });
  }
  async function drawGit() {
    clear(assistOut); if (!ws) return;
    const s = await api.get(`/code/workspaces/${ws}/git`);
    if (!s.repo) { assistOut.append(h('p', {}, s.error), btn('Initialise repository', async () => { await api.post(`/code/workspaces/${ws}/git/init`); drawGit(); }, { cls: 'sm' })); return; }
    const msg = h('input.input', { placeholder: 'Commit message' });
    assistOut.append(h('h3', {}, icon('git'), s.branch),
      h('div.list', {}, s.changes.length ? s.changes.map((c) => h('div.li', { style: { cursor: 'pointer' }, onclick: async () => { const d = await api.get(`/code/workspaces/${ws}/git/diff?path=${encodeURIComponent(c.path)}`); modal({ title: c.path, wide: true, body: h('div.diff', { style: { maxHeight: '60vh', overflow: 'auto' } }, (d.diff || 'No unstaged diff (new or staged file).').split('\n').map((l) => h(`div${l.startsWith('+') ? '.add' : l.startsWith('-') ? '.del' : ''}`, {}, l))) }); } }, h('span.tag', {}, c.status), h('div.t', {}, h('b', {}, c.path)))) : h('small.mist', {}, 'Working tree clean.')),
      s.changes.length ? h('div.row', { style: { marginTop: '8px' } }, h('div.grow', {}, msg), btn('Commit all', async () => { try { await api.post(`/code/workspaces/${ws}/git/commit`, { message: msg.value }); toast('Committed'); drawGit(); } catch (e) { toastError(e); } }, { cls: 'sm primary' })) : null,
      h('h3', { style: { marginTop: '12px' } }, 'Recent commits'), h('div.mono', { style: { whiteSpace: 'pre-wrap' } }, s.log.join('\n') || 'No commits yet.'));
  }
  async function analyse() {
    if (!ws) return;
    const w = (await api.get('/code/workspaces')).find((x) => x.id === ws);
    clear(assistOut).append(h('div.progress.indet', {}, h('i')), h('small.mist', {}, 'Reading the project…'));
    try { const r = await api.post('/files/codebase', { path: w.path }); clear(assistOut).append(h('p.small.mist', {}, `${r.stats.files} files · ${r.stats.lines.toLocaleString()} lines · ${r.stats.byExtension.slice(0, 5).map((e) => `${e.ext} ${e.files}`).join(', ')}`), mdEl(r.overview)); } catch (e) { clear(assistOut).append(h('p', {}, e.message, ' (The workspace must be inside your allowed folders for codebase analysis.)')); }
  }
  function compareDialog() {
    const a = h('textarea.input', { rows: 10, placeholder: 'Original', style: { fontFamily: 'var(--mono)' } }, file ? editor.value : ''); const b = h('textarea.input', { rows: 10, placeholder: 'Changed', style: { fontFamily: 'var(--mono)' } });
    const out = h('div.diff', { style: { maxHeight: '40vh', overflow: 'auto', marginTop: '10px' } });
    modal({ title: 'Compare code', wide: true, body: h('div', {}, h('div.grid.g2', {}, a, b), btn('Compare', async () => { const d = await api.post('/code/compare', { a: a.value, b: b.value }); clear(out).append(...d.text.split('\n').slice(2).map((l) => h(`div${l.startsWith('+') ? '.add' : l.startsWith('-') ? '.del' : ''}`, {}, l))); }, { cls: 'sm', style: { marginTop: '8px' } }), out) });
  }
  const offOut = api.on('code.output', (d) => { if (d.wsId !== ws) return; term.append(h('span', { style: d.stream === 'err' ? { color: '#9aa0a6' } : d.stream === 'cmd' ? { color: '#fff', fontWeight: 600 } : {} }, d.data)); term.scrollTop = term.scrollHeight; });
  const offExit = api.on('code.exit', (d) => { if (d.wsId !== ws) return; term.append(h('span', { style: { color: '#fff' } }, `\n[exit ${d.code}]\n`)); term.scrollTop = term.scrollHeight; runId = null; });
  loadWorkspaces();
  return () => { offOut(); offExit(); };
}
