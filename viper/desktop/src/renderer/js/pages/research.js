import { h, clear, icon, btn, busy, toast, toastError, mdEl, ask, when, download, select, toggle } from '../ui.js';

export async function render(view, { app, api, params }) {
  let current = null;
  const list = h('div.list'); const out = h('div.panel', { style: { minHeight: '300px' } });
  const q = h('textarea.input', { rows: 3, placeholder: 'What should VIPER research?', 'aria-label': 'Research question' });
  let format = 'report'; let useLocal = true;
  const webOn = app.settings.privacy.webAccess;
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Research'), h('div.sub', {}, webOn ? 'Live web research with citations to pages VIPER actually read, plus your indexed documents.' : 'Web access is off: answers come from the local model and your indexed documents, and are labelled as such.')),
    h('div.actions', {}, h('span.tag' + (webOn ? '.on' : ''), {}, webOn ? 'Web access on' : 'Offline'), btn(webOn ? 'Turn web access off' : 'Allow web access', async () => { app.settings.privacy = await api.patch('/settings/privacy', { webAccess: !webOn }); app.go('research'); }, { cls: 'sm' }))),
  h('div.split', {},
    h('div.col', {},
      h('div.panel', {}, h('h3', {}, 'New research'), q,
        h('div.row.wrap', { style: { margin: '8px 0' } }, select([['report', 'Research report'], ['brief', 'Brief answer'], ['table', 'Comparison table'], ['factcheck', 'Fact check a claim']], format, (v) => { format = v; }), h('label.row', {}, toggle(useLocal, (v) => { useLocal = v; }, 'Include my documents'), h('small', {}, 'My documents'))),
        btn('Start research', (e) => busy(e.currentTarget, run), { cls: 'primary', ico: 'research' })),
      h('div.panel', {}, h('h3', {}, 'History'), list),
      h('div.panel', {}, h('h3', {}, 'Saved references'), h('div', { id: 'refs' }))),
    out));
  async function run() {
    if (!q.value.trim()) { toast('Enter a question'); return; }
    clear(out).append(h('div.progress.indet', {}, h('i')), h('p.small.mist', {}, webOn ? 'Searching, reading sources and writing the report…' : 'Writing an offline answer…'));
    try { const r = await api.post('/research', { query: q.value, format, web: true, local: useLocal }); show(r); loadList(); } catch (e) { clear(out).append(h('p', {}, e.message)); }
  }
  function show(r) {
    current = r;
    const label = { web: 'Live web research', local: 'Local documents', offline: 'Offline model knowledge — not verified' }[r.mode];
    clear(out).append(h('h2', {}, r.title), h('div.row', { style: { margin: '6px 0 12px' } }, h(`span.tag${r.mode === 'offline' ? '' : '.on'}`, {}, label), h('span.grow'), btn('Export Markdown', async () => { const res = await api.req('GET', `/research/${r.id}/export`, undefined, { raw: true }); download(`viper-research-${r.id}.md`, await res.text(), 'text/markdown'); }, { cls: 'sm', ico: 'download' })),
      mdEl(r.report),
      r.notes?.length ? h('div', { style: { marginTop: '12px' } }, ...r.notes.map((n) => h('p.small.mist', {}, n))) : null,
      h('h3', { style: { marginTop: '16px' } }, `Sources (${r.sources.length})`),
      r.sources.length ? h('ol', { style: { paddingLeft: '20px' } }, r.sources.map((s) => h('li', { style: { marginBottom: '8px' } }, s.url ? h('a', { href: s.url, onclick: (e) => { e.preventDefault(); window.viperNative?.openExternal ? window.viperNative.openExternal(s.url) : window.open(s.url, '_blank', 'noopener'); } }, s.title) : h('span', {}, s.title), h('small.mist', { style: { display: 'block' } }, s.url ? `${new URL(s.url).hostname}${s.fetchedAt ? ` · retrieved ${when(s.fetchedAt)}` : ''}` : `Local file: ${s.path}`)))) : h('p.small.mist', {}, 'No sources were used.'));
  }
  async function loadList() {
    const items = await api.get('/research').catch(() => []);
    clear(list);
    if (!items.length) list.append(h('small.mist', {}, 'No research yet.'));
    for (const r of items) list.append(h('div.li', {}, h('div.t', { style: { cursor: 'pointer' }, onclick: async () => show(await api.get(`/research/${r.id}`)) }, h('b', {}, r.title), h('small', {}, `${r.mode} · ${when(r.created_at)}`)), btn('', async () => { if (await ask('Delete research?', r.title, { danger: true, confirmLabel: 'Delete' })) { await api.del(`/research/${r.id}`); loadList(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' })));
    const refs = await api.get('/research/references').catch(() => []);
    const box = view.querySelector('#refs'); if (!box) return; // page was left while loading
    clear(box);
    if (!refs.length) box.append(h('small.mist', {}, 'Pages read during research are saved here for offline reference.'));
    for (const x of refs.slice(0, 30)) box.append(h('div.notif', {}, h('b', {}, x.title), h('small', {}, x.url)));
  }
  if (params?.action === 'new') { q.focus(); clear(out).append(h('div.empty', {}, h('b', {}, 'New research session'), 'Type your question on the left.')); }
  else clear(out).append(h('div.empty', {}, h('b', {}, 'Ask a research question'), webOn ? 'VIPER searches the web, reads the top pages and cites them.' : 'Turn on web access for live sources, or research your indexed documents.'));
  loadList();
}
