import { h, clear, btn, bytes, toast, toastError } from '../ui.js';

// MANAGE → Task Manager: the processes running on this PC (live), and closing an application.
// Closing always goes through VIPER's confirmation dialog (it is a destructive action).
export async function render(view, { app, api }) {
  let filter = ''; let sort = 'cpu';
  const body = h('div');
  const search = h('input.input', { type: 'search', placeholder: 'Filter by name', oninput: (e) => { filter = e.target.value.toLowerCase(); draw(); } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Task Manager'), h('div.sub', {}, 'Processes on this PC, refreshed every five seconds.')),
    h('div.actions', {}, btn('System Monitor', () => app.go('system'), { cls: 'sm ghost', ico: 'system' }))),
  h('div.panel', { style: { marginBottom: '14px' } }, h('div.row', {}, h('div.grow', {}, search),
    h('div.seg', {}, ...[['cpu', 'CPU'], ['mem', 'Memory'], ['name', 'Name']].map(([v, l]) => h(`button${sort === v ? '.on' : ''}`, { onclick: (e) => { sort = v; e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === e.currentTarget)); draw(); } }, l))))),
  body);
  let procs = [];
  async function load() { procs = await api.get('/system/processes?limit=200').catch(() => procs); draw(); }
  function draw() {
    let rows = procs.filter((p) => !filter || String(p.name).toLowerCase().includes(filter));
    rows = rows.sort((a, b) => (sort === 'name' ? String(a.name).localeCompare(String(b.name)) : sort === 'mem' ? (b.memBytes || 0) - (a.memBytes || 0) : (b.cpu || 0) - (a.cpu || 0)));
    clear(body).append(h('div.panel', {}, rows.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Process', 'CPU', 'Memory', 'PID', ''].map((t) => h('th', {}, t)))),
      h('tbody', {}, rows.slice(0, 120).map((p) => h('tr', {}, h('td', {}, p.name), h('td', {}, `${p.cpu ?? 0}%`), h('td', {}, bytes(p.memBytes)), h('td.mono', {}, String(p.pid)),
        h('td', {}, btn('Close', async () => {
          try { const r = await api.post('/tools/close_app', { args: { name: String(p.name).replace(/\.exe$/i, '') } }); toast(r?.ok === false ? 'Not closed' : 'Close requested', r?.message || r?.error || p.name, r?.ok === false ? 'warn' : 'info'); setTimeout(load, 1500); } catch (e) { toastError(e); }
        }, { cls: 'sm ghost' })))))) : h('div.empty', {}, 'No processes match.')));
  }
  await load();
  const t = setInterval(() => { if (!document.hidden) load(); }, 5000);
  return () => clearInterval(t);
}
