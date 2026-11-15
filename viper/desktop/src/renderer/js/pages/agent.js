import { h, clear, icon, btn, busy, toast, toastError, ask, prompt, select, when, ago } from '../ui.js';

// MAKE → AI Coding Agent. A four-panel workspace over the real Code Agent service:
// Files (the project on disk) · Development (plan + file viewer) · Agent status (state, decisions,
// controls, results) · Console (every command the agent ran and its real output).
// Panels can be resized by dragging the dividers and collapsed from their headers; the layout is
// remembered. Nothing here simulates progress: every update comes from the agent's event stream.
const STEP_LABEL = { pending: 'Pending', running: 'Running', complete: 'Complete', failed: 'Failed', needs_input: 'Needs input', skipped: 'Skipped' };
const RUN_LABEL = { queued: 'Queued', planning: 'Planning', running: 'Running', needs_input: 'Needs your input', paused: 'Paused', completed: 'Completed', failed: 'Failed', cancelled: 'Cancelled', interrupted: 'Interrupted — resume to continue' };
const LAYOUT_KEY = 'viper.agent.layout';
const outcome = (x, none) => (!x ? none : x.skipped ? 'skipped (no command for this stack)' : x.ok ? 'passed' : `failed (exit ${x.code})`);
const TOOLS = [['python', 'Python'], ['node', 'Node.js'], ['dotnet', '.NET'], ['git', 'git'], ['java', 'Java'], ['godot', 'Godot'], ['rust', 'Rust'], ['go', 'Go']];
const loadLayout = () => { try { return { left: 240, right: 320, bottom: 220, collapsed: {}, ...JSON.parse(localStorage.getItem(LAYOUT_KEY) || '{}') }; } catch { return { left: 240, right: 320, bottom: 220, collapsed: {} }; } };
const saveLayout = (l) => { try { localStorage.setItem(LAYOUT_KEY, JSON.stringify(l)); } catch { /* storage unavailable */ } };

export async function render(view, { app, api, params }) {
  let projects = []; let project = null; let runs = []; let run = null; let events = []; let tree = null; let openFile = null; let devTab = 'plan';
  let lastEventId = 0; let streaming = null;
  const layout = loadLayout();

  const projSel = h('div.row'); const reqBox = h('div.agent-req');
  const filesBody = h('div.ap-body.files'); const devBody = h('div.ap-body.dev'); const statusBody = h('div.ap-body.status'); const consoleBody = h('div.ap-body.console.mono');
  const devTabs = h('div.seg.sm');
  const panel = (id, title, ico, body, extra) => h(`section.ap.ap-${id}${layout.collapsed[id] ? '.collapsed' : ''}`, { 'data-panel': id },
    h('header.ap-head', {}, icon(ico), h('span.lbl', {}, title), extra || null, h('span.grow'),
      h('button.ap-toggle', { type: 'button', title: `Collapse or expand ${title}`, 'aria-label': `Collapse or expand ${title}`, onclick: (e) => { const s = e.currentTarget.closest('.ap'); s.classList.toggle('collapsed'); layout.collapsed[id] = s.classList.contains('collapsed'); saveLayout(layout); applyLayout(); } }, h('span.chev'))),
    body);
  const ws = h('div.agent-ws', {},
    panel('files', 'Files', 'folder', filesBody),
    h('div.ap-split.v', { 'data-split': 'left' }),
    panel('dev', 'Development', 'code', devBody, devTabs),
    h('div.ap-split.v', { 'data-split': 'right' }),
    panel('status', 'Agent status', 'sparkle', statusBody),
    h('div.ap-split.hz', { 'data-split': 'bottom' }),
    panel('console', 'Console', 'terminal', consoleBody));

  view.classList.add('view-agent');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'VIPER Code Agent'), h('div.sub', {}, 'Describe what you want built or changed. VIPER plans it, writes the files, runs the build and tests, fixes failures and tells you when it really works.')),
    h('div.actions', {}, projSel)), reqBox, ws);

  function applyLayout() {
    const c = layout.collapsed;
    ws.style.setProperty('--ap-left', c.files ? '36px' : `${layout.left}px`);
    ws.style.setProperty('--ap-right', c.status ? '36px' : `${layout.right}px`);
    ws.style.setProperty('--ap-bottom', c.console ? '34px' : `${layout.bottom}px`);
  }
  applyLayout();
  for (const sp of ws.querySelectorAll('.ap-split')) {
    sp.addEventListener('pointerdown', (e) => {
      e.preventDefault(); sp.setPointerCapture(e.pointerId); const which = sp.dataset.split; const r = ws.getBoundingClientRect();
      const move = (ev) => {
        if (which === 'left') layout.left = Math.max(160, Math.min(480, ev.clientX - r.left));
        if (which === 'right') layout.right = Math.max(240, Math.min(560, r.right - ev.clientX));
        if (which === 'bottom') layout.bottom = Math.max(110, Math.min(r.height - 160, r.bottom - ev.clientY));
        applyLayout();
      };
      const up = () => { sp.removeEventListener('pointermove', move); sp.removeEventListener('pointerup', up); saveLayout(layout); };
      sp.addEventListener('pointermove', move); sp.addEventListener('pointerup', up);
    });
  }

  // ---------- projects ----------
  async function loadProjects(selectId) {
    projects = await api.get('/agent/projects').catch((e) => { toastError(e); return []; });
    const id = selectId || params?.project || project?.id || projects[0]?.id;
    project = projects.find((p) => p.id === id) || null;
    clear(projSel).append(
      ...(projects.length ? [select(projects.map((p) => [p.id, p.name]), project?.id, (v) => { project = projects.find((p) => p.id === v); run = null; loadProject(); })] : []),
      btn('New project', newProject, { cls: 'sm', ico: 'plus' }),
      btn('Open existing folder', openExisting, { cls: 'sm', ico: 'folder' }),
      btn('Classic editor', () => app.go('codestudio'), { cls: 'sm ghost', ico: 'edit', title: 'The manual Code Studio editor from earlier versions' }));
    drawRequest();
    await loadProject(params?.run);
  }
  async function newProject() {
    const name = await prompt('New project', { label: 'Project name', placeholder: 'e.g. Calculator' });
    if (!name) return;
    try { const p = await api.post('/agent/projects', { name }); toast('Project created', p.path); await loadProjects(p.id); } catch (e) { toastError(e); }
  }
  async function openExisting() {
    const dir = window.viperNative?.pickFolder ? await window.viperNative.pickFolder() : await prompt('Open an existing project', { label: 'Full folder path' });
    if (!dir) return;
    try { const p = await api.post('/agent/projects', { path: dir }); toast('Project added', p.path); await loadProjects(p.id); } catch (e) { toastError(e); }
  }

  async function loadProject(runId) {
    if (!project) { clear(filesBody).append(h('div.empty.small', {}, 'No project yet.')); clear(devBody).append(h('div.empty', {}, 'Create a project, or open an existing folder, then describe what to build.')); clear(statusBody); clear(consoleBody); drawRequest(); return; }
    const full = await api.get(`/agent/projects/${project.id}`).catch(() => null);
    runs = full?.runs || [];
    const pick = runId ? runs.find((r) => r.id === runId) : runs.find((r) => r.live) || runs[0];
    await selectRun(pick?.id || null);
    loadTree();
  }
  async function loadTree() {
    if (!project?.workspace_id) { clear(filesBody).append(h('div.small.mist', {}, project?.path || '')); return; }
    tree = await api.get(`/code/workspaces/${project.workspace_id}/tree`).catch(() => null);
    drawFiles();
  }
  async function selectRun(id) {
    run = id ? await api.get(`/agent/runs/${id}`).catch(() => null) : null;
    events = run ? await api.get(`/agent/runs/${run.id}/events`).catch(() => []) : [];
    lastEventId = events.length ? events[events.length - 1].id : 0;
    drawAll();
  }

  // ---------- drawing ----------
  function drawAll() { drawRequest(); drawDev(); drawStatus(); drawConsole(); }
  function drawRequest() {
    clear(reqBox);
    if (!project) { reqBox.append(h('div.panel.row', {}, h('span.grow.small', {}, 'Start by creating a project. VIPER keeps each project in its own folder with git checkpoints so every change can be rolled back.'), btn('New project', newProject, { cls: 'sm primary', ico: 'plus' }))); return; }
    const ta = h('textarea.input', { rows: 2, placeholder: `What should VIPER build or change in ${project.name}? e.g. "A small Windows calculator with working buttons and unit tests"`, onkeydown: (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) go.click(); } });
    const busyRun = runs.find((r) => r.live && !['completed', 'failed', 'cancelled'].includes(r.status));
    const go = btn(busyRun ? 'Queue task' : 'Start', async (e) => busy(e.currentTarget, async () => {
      const text = ta.value.trim(); if (!text) return toast('Describe the task first', '', 'warn');
      try { const r = await api.post(`/agent/projects/${project.id}/runs`, { request: text }); ta.value = ''; toast(r.status === 'queued' ? 'Task queued' : 'Task started', r.request.slice(0, 80)); runs = [r, ...runs]; await selectRun(r.id); } catch (err) { toastError(err); }
    }), { cls: 'primary', ico: 'play' });
    reqBox.append(h('div.agent-req-row', {}, h('div.grow', {}, ta), go), h('small.mist', {}, `${project.path} · Ctrl+Enter to start · VIPER asks only when a decision really matters, and every install or command outside the project needs your approval.`));
  }

  function drawFiles() {
    clear(filesBody);
    if (!tree) return filesBody.append(h('div.small.mist', {}, 'Files are unavailable.'));
    const changed = new Map([...(run?.result?.created || []).map((f) => [f, 'created']), ...(run?.result?.modified || []).map((f) => [f, 'modified'])]);
    for (const e of events) if (e.kind === 'file') changed.set(e.data.path, e.data.action);
    filesBody.append(h('div.ap-path.small.mist', { title: tree.root }, tree.root));
    if (!tree.entries.length) filesBody.append(h('div.small.mist', {}, 'Empty folder.'));
    for (const e of tree.entries) {
      const c = changed.get(e.path);
      filesBody.append(h(`button.tree-item${openFile?.path === e.path ? '.on' : ''}`, { style: { paddingLeft: `${8 + e.depth * 12}px` }, title: e.path, onclick: () => (e.dir ? null : showFile(e.path)) },
        icon(e.dir ? 'folder' : 'file'), h('span.lbl', {}, e.name), c ? h(`span.chg.${c}`, { title: c }, c === 'created' ? 'A' : 'M') : null));
    }
  }
  async function showFile(rel) {
    try { openFile = await api.get(`/code/workspaces/${project.workspace_id}/file?path=${encodeURIComponent(rel)}`); devTab = 'file'; drawDev(); drawFiles(); } catch (e) { toastError(e); }
  }

  function drawDev() {
    clear(devTabs).append(...[['plan', 'Plan'], ['file', openFile ? openFile.path.split('/').pop() : 'File'], ['changes', 'Changes'], ['history', 'History']].map(([id, l]) => h(`button${devTab === id ? '.on' : ''}`, { type: 'button', onclick: () => { devTab = id; drawDev(); } }, l)));
    clear(devBody);
    if (devTab === 'file') {
      if (!openFile) return devBody.append(h('div.empty.small', {}, 'Choose a file in the Files panel.'));
      const lines = openFile.content.split('\n');
      return devBody.append(h('div.small.mist', { style: { marginBottom: '6px' } }, `${openFile.path} · ${openFile.language} · ${lines.length} lines`), h('pre.code-view', {}, h('code', {}, lines.map((l, i) => `${String(i + 1).padStart(4)}  ${l}`).join('\n'))));
    }
    if (devTab === 'changes') {
      const files = events.filter((e) => e.kind === 'file');
      if (!files.length) return devBody.append(h('div.empty.small', {}, 'No files changed in this task yet.'));
      return devBody.append(h('div.list', {}, files.map((e) => h('div.li', {}, icon('file'), h('div.t', {}, h('b', {}, e.data.path), h('small', {}, `${e.data.action} · ${e.data.lines} lines${e.data.delta ? ` (${e.data.delta > 0 ? '+' : ''}${e.data.delta})` : ''} · ${when(e.ts)}`)), btn('View', () => showFile(e.data.path), { cls: 'sm ghost' })))),
        h('p.small.mist', {}, 'The previous version of every modified file is kept in .viper/backups inside the project, and git checkpoints are listed under History.'));
    }
    if (devTab === 'history') {
      const box = h('div');
      devBody.append(h('h3', {}, 'Tasks'), runs.length ? h('div.list', {}, runs.map((r) => h(`div.li${run?.id === r.id ? '.on' : ''}`, {}, h(`span.dot${r.live ? '.on' : ''}`), h('div.t', {}, h('b', {}, r.plan?.title || r.request.slice(0, 70)), h('small', {}, `${RUN_LABEL[r.status] || r.status} · ${when(r.created_at)} · ${r.origin || 'desktop'}`)), btn('Open', () => selectRun(r.id), { cls: 'sm ghost' })))) : h('div.small.mist', {}, 'No tasks yet.'), h('h3', { style: { marginTop: '14px' } }, 'Checkpoints'), box);
      api.get(`/agent/projects/${project.id}/checkpoints`).then((cps) => {
        if (!cps?.length) return box.append(h('div.small.mist', {}, 'No git checkpoints yet (git may not be installed, or checkpoints are off in Settings → AI Backend).'));
        box.append(h('div.list', {}, cps.map((c) => h('div.li', {}, icon('git'), h('div.t', {}, h('b', {}, c.message), h('small.mono', {}, `${c.commit.slice(0, 8)} · ${when(c.ts)}`)),
          btn('Roll back', async () => { try { await api.post(`/agent/projects/${project.id}/rollback`, { commit: c.commit }); toast('Rolled back', c.message); loadTree(); } catch (e) { toastError(e); } }, { cls: 'sm ghost' })))));
      }).catch((e) => box.append(h('div.small.mist', {}, e.message)));
      return;
    }
    // plan
    if (!run) return devBody.append(h('div.empty', {}, project ? 'No task selected. Describe what to build above.' : ''));
    const plan = run.plan;
    devBody.append(h('div.plan-head', {}, h('b', {}, plan?.title || 'Planning…'), plan?.stack ? h('span.tag', {}, plan.stack) : null, h('small.mist', {}, run.request)));
    if (plan?.summary) devBody.append(h('p.small', {}, plan.summary));
    devBody.append(h('ol.plan', {}, (plan?.steps || []).map((s) => h(`li.step.${s.status}`, {}, h('span.st', { title: STEP_LABEL[s.status] }), h('div.t', {}, h('b', {}, s.title), s.detail ? h('small', {}, s.detail) : null), h('span.tag', {}, STEP_LABEL[s.status] || s.status)))));
    if (streaming && streaming.runId === run.id) devBody.append(h('div.small.mist', { style: { marginTop: '8px' } }, `Model (${streaming.role}) is writing… ${streaming.chars} characters`));
  }

  function drawStatus() {
    clear(statusBody);
    if (!run) { statusBody.append(h('div.small.mist', {}, 'Idle.')); toolchainBox(); return; }
    const live = run.live && !['completed', 'failed', 'cancelled'].includes(run.status);
    const status = run.paused ? 'paused' : run.status;
    statusBody.append(h('div.run-state', {}, h(`span.dot${live ? '.on' : ''}`), h('b', {}, RUN_LABEL[status] || status), h('small.mist', {}, `started ${ago(run.created_at)}${run.origin && run.origin !== 'desktop' ? ` · from ${run.origin}` : ''}`)));
    const current = run.plan?.steps?.find((s) => s.status === 'running' || s.status === 'needs_input');
    if (current) statusBody.append(h('p.small', {}, h('b', {}, 'Now: '), current.title));
    if (run.decision && run.decision.status === 'open') {
      const d = run.decision; const opts = JSON.parse(d.options || '[]');
      statusBody.append(h('div.decision', {}, h('b', {}, icon('chat'), 'I need your input'), h('p', {}, d.question),
        h('div.col', {}, opts.map((o) => btn(o, async (e) => busy(e.currentTarget, async () => { try { await api.post(`/agent/decisions/${d.id}`, { answer: o }); toast('Answer sent', o); } catch (err) { toastError(err); } }), { cls: o === 'Decide automatically' ? 'sm ghost' : 'sm' }))),
        h('small.mist', {}, `If nobody answers by ${new Date(d.expires_at).toLocaleTimeString()}, VIPER decides automatically.`)));
    }
    const ctl = h('div.row.wrap', { style: { margin: '10px 0' } });
    if (live && !run.paused) ctl.append(btn('Pause', () => act('pause'), { cls: 'sm', ico: 'pause' }));
    if (run.paused || run.status === 'interrupted') ctl.append(btn('Resume', () => act('resume'), { cls: 'sm primary', ico: 'play' }));
    if (live || run.paused) ctl.append(btn('Cancel', async () => { if (await ask('Cancel this task?', 'VIPER stops after the current command. Files already written stay; roll back from History if you want them gone.', { danger: true, confirmLabel: 'Cancel task' })) act('cancel'); }, { cls: 'sm danger', ico: 'x' }));
    statusBody.append(ctl);
    const r = run.result;
    if (r) {
      statusBody.append(h(`div.result.${r.status}`, {}, h('b', {}, r.status === 'completed' ? 'Completion criteria passed' : 'Not finished'),
        h('dl.kv', {},
          h('dt', {}, 'Build'), h('dd', {}, outcome(r.build, 'no build step')),
          h('dt', {}, 'Tests'), h('dd', {}, outcome(r.test, 'no tests')),
          h('dt', {}, 'Launch'), h('dd', {}, r.launch?.ok && r.launch.stayedOpen ? 'started and stayed open' : outcome(r.launch, 'not checked')),
          h('dt', {}, 'Created'), h('dd', {}, r.created.length ? r.created.join(', ') : 'none'),
          h('dt', {}, 'Modified'), h('dd', {}, r.modified.length ? r.modified.join(', ') : 'none'),
          h('dt', {}, 'Fix attempts'), h('dd', {}, String(r.fixAttempts ?? 0))),
        r.remaining?.length ? h('p.small', {}, r.remaining.join(' ')) : null,
        r.run ? h('p.small.mist', {}, 'Run it with: ', h('code', {}, r.run)) : null,
        h('div.row.wrap', {}, window.viperNative?.openPath ? btn('Open folder', () => window.viperNative.openPath(r.path), { cls: 'sm', ico: 'folder' }) : null,
          r.status !== 'completed' ? btn('Try again', () => { const ta = reqBox.querySelector('textarea'); if (ta) { ta.value = run.request; ta.focus(); } }, { cls: 'sm' }) : null)));
    }
    toolchainBox();
  }
  async function act(what) {
    try {
      if (what === 'pause') await api.post(`/agent/runs/${run.id}/pause`);
      else if (what === 'resume') await api.post(`/agent/runs/${run.id}/resume`);
      else await api.post(`/agent/runs/${run.id}/cancel`);
      await selectRun(run.id);
    } catch (e) { toastError(e); }
  }
  let tcCache = null;
  function toolchainBox() {
    const box = h('div.toolchains', {}, h('h4', {}, 'Build tools on this PC'));
    statusBody.append(box);
    const fill = (tc) => box.append(h('div.chips', {}, TOOLS.map(([k, l]) => h(`span.chip${tc[k] ? '.on' : ''}`, { title: tc[k] ? tc[k].version : 'not found on this PC' }, `${l}${tc[k]?.bundled ? ' (bundled)' : tc[k] ? '' : ' — missing'}`))),
      h('small.mist', {}, 'VIPER never pretends a project compiled: if a needed tool is missing, the task reports it instead.'));
    if (tcCache) fill(tcCache); else api.get('/agent/toolchains').then((tc) => { tcCache = tc; fill(tc); }).catch(() => {});
  }

  function drawConsole() {
    clear(consoleBody);
    if (!run) return;
    for (const e of events) consoleBody.append(consoleLine(e));
    consoleBody.scrollTop = consoleBody.scrollHeight;
  }
  function consoleLine(e) {
    const t = new Date(e.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const d = e.data || {};
    const text = e.kind === 'command' ? (d.blocked ? `✕ blocked: ${d.command} — ${d.reason}` : d.declined ? `✕ declined: ${d.command}` : `$ ${d.command}`)
      : e.kind === 'output' ? `${d.output || ''}\n[exit ${d.code}]`
        : e.kind === 'file' ? `${d.action} ${d.path} (${d.lines} lines)`
          : d.message || d.text || d.question || JSON.stringify(d);
    return h(`div.cl.${e.kind}`, {}, h('span.ts', {}, t), h('span.k', {}, e.kind), h('span.m', {}, text));
  }

  // ---------- live updates ----------
  const mine = (d) => run && d?.runId === run.id;
  const offs = [
    api.on('agent.log', (d) => { if (!mine(d)) return; const e = { id: d.id, kind: d.kind, ts: d.ts, data: d.data }; if (e.id && e.id <= lastEventId) return; lastEventId = e.id || lastEventId; events.push(e); consoleBody.append(consoleLine(e)); consoleBody.scrollTop = consoleBody.scrollHeight; if (e.kind === 'file') { loadTree(); if (devTab === 'changes') drawDev(); } }),
    api.on('agent.plan', (d) => { if (mine(d)) { run.plan = d.plan || run.plan; drawDev(); } else if (d?.projectId === project?.id) loadProject(run?.id); }),
    api.on('agent.step', (d) => { if (!mine(d) || !run.plan) return; const i = run.plan.steps.findIndex((s) => s.id === d.step.id); if (i >= 0) run.plan.steps[i] = d.step; drawDev(); drawStatus(); }),
    api.on('agent.stream', (d) => { if (!mine(d)) return; streaming = d; if (devTab === 'plan') drawDev(); }),
    api.on('agent.run', async (d) => {
      if (d?.projectId !== project?.id) return;
      if (mine(d)) { run = await api.get(`/agent/runs/${run.id}`).catch(() => run); streaming = null; drawStatus(); drawDev(); drawRequest(); } else { const full = await api.get(`/agent/projects/${project.id}`).catch(() => null); runs = full?.runs || runs; if (!run) selectRun(d.runId); }
    }),
    api.on('agent.decision', async (d) => { if (mine(d)) { run = await api.get(`/agent/runs/${run.id}`).catch(() => run); drawStatus(); } }),
    api.on('agent.done', async (d) => { if (mine(d)) { run = await api.get(`/agent/runs/${run.id}`).catch(() => run); drawAll(); loadTree(); } }),
  ];

  await loadProjects();
  if (params?.decision && run?.decision?.id === params.decision) statusBody.querySelector('.decision')?.scrollIntoView({ block: 'center' });
  return () => offs.forEach((o) => o());
}
