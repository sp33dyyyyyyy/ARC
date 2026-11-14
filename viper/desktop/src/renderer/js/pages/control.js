import { h, clear, icon, btn, busy, toast, toastError, field, bytes, ask } from '../ui.js';

export async function render(view, { app, api }) {
  const run = async (tool, args = {}, quiet) => {
    const r = await api.post(`/tools/${tool}`, { args });
    if (!r.ok && !quiet) toast(r.denied ? 'Not permitted' : 'Action failed', r.error, 'warn');
    return r;
  };
  const appsBox = h('div'); const procBox = h('div'); const winBox = h('div'); const diskBox = h('div'); const volBox = h('div'); const fileRes = h('div');
  const appQ = h('input.input', { placeholder: 'Search installed apps', oninput: () => drawApps() });
  const fileQ = h('input.input', { placeholder: 'File name words' }); const since = h('select.input', {}, ['', 'today', 'yesterday', '7 days', '30 days'].map((v) => h('option', { value: v }, v || 'Any time')));
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Computer Control'), h('div.sub', {}, 'Everything here uses the same permission rules as voice commands. Risky actions always ask first.'))),
    h('div.grid.g2', {},
      h('div.panel', {}, h('h3', {}, icon('grid'), 'Applications', h('span.r', {}, btn('', async () => { await api.post('/apps/refresh'); drawApps(); }, { cls: 'sm ghost icon', ico: 'refresh', title: 'Rescan' }))), appQ, appsBox),
      h('div.col', {},
        h('div.panel', {}, h('h3', {}, icon('voice'), 'Volume'), volBox),
        h('div.panel', {}, h('h3', {}, icon('folder'), 'Quick folders'), h('div.row.wrap', {}, ['downloads', 'documents', 'desktop', 'pictures', 'music', 'videos'].map((f) => btn(f[0].toUpperCase() + f.slice(1), () => run('open_folder', { folder: f }), { cls: 'sm' })))),
        h('div.panel', {}, h('h3', {}, icon('external'), 'Open website'), h('div.row', {}, h('div.grow', {}, h('input.input', { id: 'url-in', placeholder: 'example.com' })), btn('Open', () => run('open_url', { url: view.querySelector('#url-in').value }), { cls: 'sm' }))),
        h('div.panel', {}, h('h3', {}, icon('screen'), 'Screen and clipboard'), h('div.row.wrap', {},
          btn('Take screenshot', async (e) => busy(e.currentTarget, async () => { const r = await run('take_screenshot'); if (r.ok) toast('Screenshot saved', r.result.saved); }), { cls: 'sm' }),
          btn('Explain my screen', () => app.go('vision'), { cls: 'sm' }),
          btn('Read clipboard', async (e) => busy(e.currentTarget, async () => { const r = await run('read_clipboard'); if (r.ok) toast(`Clipboard (${r.result.length} chars)`, r.result.text.slice(0, 200) || '(empty)'); }), { cls: 'sm' }))),
        h('div.panel', {}, h('h3', {}, icon('terminal'), 'Approved scripts'), h('div', { id: 'scripts' })))),
    h('div.grid.g2', { style: { marginTop: '14px' } },
      h('div.panel', {}, h('h3', {}, icon('research'), 'Search files'), h('div.row', {}, h('div.grow', {}, fileQ), since, btn('Search', (e) => busy(e.currentTarget, searchFiles), { cls: 'sm primary' })), fileRes),
      h('div.panel', {}, h('h3', {}, icon('hud'), 'Windows', h('span.r', {}, btn('', drawWindows, { cls: 'sm ghost icon', ico: 'refresh', title: 'Refresh' }))), winBox)),
    h('div.grid.g2', { style: { marginTop: '14px' } },
      h('div.panel', {}, h('h3', {}, icon('system'), 'Running processes', h('span.r', {}, btn('', drawProcs, { cls: 'sm ghost icon', ico: 'refresh', title: 'Refresh' }))), procBox),
      h('div.panel', {}, h('h3', {}, icon('files'), 'Drives'), diskBox)));

  let appsCache = null;
  async function drawApps() {
    if (!appsCache) appsCache = await api.get('/apps').catch(() => []);
    const q = appQ.value.toLowerCase();
    const list = appsCache.filter((a) => !q || a.name.toLowerCase().includes(q)).slice(0, 40);
    clear(appsBox).append(h('div.list', { style: { maxHeight: '360px', overflowY: 'auto' } }, list.length ? list.map((a) => h('div.li', {}, h('div.t', {}, h('b', {}, a.name), h('small', {}, a.kind === 'appid' ? 'Store app' : a.kind)), btn('Open', (e) => busy(e.currentTarget, async () => { const r = await run('open_app', { name: a.name }); if (r.ok) toast(r.result.verifiedRunning ? `${r.result.app} is running` : `${r.result.app} launch requested`, r.result.note); }), { cls: 'sm' }))) : h('small.mist', {}, appsCache.length ? 'No match.' : 'No installed applications were found (application discovery is implemented for Windows, macOS and Linux desktops).')));
  }
  async function drawVolume() {
    const r = await run('set_volume', { action: 'get' }, true);
    if (!r.ok) { clear(volBox).append(h('small.mist', {}, r.error)); return; }
    const slider = h('input', { type: 'range', min: 0, max: 100, value: r.result.verifiedLevel ?? 50, onchange: async (e) => { const x = await run('set_volume', { action: 'set', level: Number(e.target.value) }); if (x.ok) label.textContent = `${x.result.verifiedLevel}%`; } });
    const label = h('b', {}, `${r.result.verifiedLevel}%`);
    clear(volBox).append(h('div.row', {}, h('div.grow', {}, slider), label, btn(r.result.muted ? 'Unmute' : 'Mute', async () => { await run('set_volume', { action: r.result.muted ? 'unmute' : 'mute' }); drawVolume(); }, { cls: 'sm' })));
  }
  async function drawProcs() {
    const list = await api.get('/system/processes?limit=25').catch(() => []);
    clear(procBox).append(h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Process', 'CPU', 'Memory', ''].map((t) => h('th', {}, t)))), h('tbody', {}, list.map((p) => h('tr', {}, h('td', {}, p.name), h('td', {}, `${p.cpu}%`), h('td', {}, bytes(p.memBytes)), h('td', {}, btn('Close', async () => { const r = await run('close_app', { name: p.name.replace(/\.exe$/i, '') }); if (r.ok) { toast('Closed', p.name); drawProcs(); } }, { cls: 'sm ghost' })))))));
  }
  async function drawWindows() {
    const r = await run('manage_window', { action: 'list' }, true);
    if (!r.ok) { clear(winBox).append(h('small.mist', {}, r.error)); return; }
    clear(winBox).append(h('div.list', { style: { maxHeight: '300px', overflowY: 'auto' } }, r.result.map((w) => h('div.li', {}, h('div.t', {}, h('b', {}, w.title), h('small', {}, w.app)), ...['focus', 'minimize', 'maximize'].map((a) => btn(a[0].toUpperCase() + a.slice(1), () => run('manage_window', { action: a, name: w.app }), { cls: 'sm ghost' }))))));
  }
  async function drawDisks() {
    const r = await run('disk_space', {}, true);
    clear(diskBox).append(...(r.ok ? r.result.map((d) => h('div', { style: { marginBottom: '10px' } }, h('div.row', {}, h('span.grow', {}, d.drive), h('small.mist', {}, `${d.free} free of ${d.total}`)), h('div.meter' + (d.usedPercent > 90 ? '.hot' : ''), {}, h('i', { style: { width: `${d.usedPercent}%` } })))) : [h('small.mist', {}, r.error)]));
  }
  async function searchFiles() {
    const r = await run('search_files', { query: fileQ.value, since: since.value || undefined });
    if (!r.ok) return;
    clear(fileRes).append(h('small.mist', {}, `${r.result.matches.length} matches · scanned ${r.result.scanned.toLocaleString()} entries${r.result.truncated ? ' (search limit reached)' : ''}`),
      h('div.list', { style: { maxHeight: '320px', overflowY: 'auto' } }, r.result.matches.map((f) => h('div.li', {}, icon(f.dir ? 'folder' : 'file'), h('div.t', {}, h('b', {}, f.name), h('small', {}, `${f.path} · ${f.size} · ${f.modified}`)), btn('Open folder', () => run('open_folder', { folder: f.dir ? f.path : f.path.replace(/[\\/][^\\/]+$/, '') }), { cls: 'sm ghost' })))));
  }
  function drawScripts() {
    const box = view.querySelector('#scripts');
    const list = app.settings.approvedScripts;
    clear(box).append(list.length ? h('div.list', {}, list.map((s) => h('div.li', {}, h('div.t', {}, h('b', {}, s.name), h('small', {}, s.path)), btn('Run', (e) => busy(e.currentTarget, async () => { const r = await run('run_approved_script', { name: s.name }); if (r.result) toast(`${s.name}: exit ${r.result.exitCode}`, r.result.output.slice(-300)); }), { cls: 'sm' })))) : h('small.mist', {}, 'No scripts approved. Add them in Settings → Privacy & permissions.'));
  }
  drawApps(); drawVolume(); drawProcs(); drawWindows(); drawDisks(); drawScripts();
}
