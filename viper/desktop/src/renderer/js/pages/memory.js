import { h, clear, icon, btn, toast, toastError, ask, prompt, when, download, select, toggle, readFileAs, field, modal } from '../ui.js';
const CATS = ['preference', 'fact', 'project', 'app', 'workflow', 'person', 'reminder', 'other'];

export async function render(view, { app, api }) {
  let q = ''; let cat = '';
  const list = h('div');
  const search = h('input.input', { placeholder: 'Search memories', oninput: (e) => { q = e.target.value; load(); } });
  const importIn = h('input', { type: 'file', accept: 'application/json', style: { display: 'none' }, onchange: async (e) => { try { const r = await api.post('/memory/import', JSON.parse(await readFileAs(e.target.files[0], 'text'))); toast('Memories imported', `${r.added} new of ${r.total}`); load(); } catch (err) { toastError(err); } e.target.value = ''; } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Memory'), h('div.sub', {}, 'Only what you ask VIPER to remember is stored, on this PC. You can edit or delete anything.')),
    h('div.actions', {}, btn('Add memory', add, { cls: 'primary', ico: 'plus' }), btn('Export', async () => { const r = await api.req('GET', '/memory/export', undefined, { raw: true }); download('viper-memory.json', await r.text(), 'application/json'); }, { ico: 'download' }), btn('Import', () => importIn.click(), { ico: 'upload' }),
      btn('Clear all', async () => { const t = await prompt('Clear all memories', { label: 'Type DELETE ALL to permanently erase every memory' }); if (t === 'DELETE ALL') { await api.post('/memory/clear', { confirm: t }); toast('All memories erased'); load(); } }, { cls: 'danger' }))),
  h('div.panel', { style: { marginBottom: '14px' } }, h('div.row', {}, h('div.grow', {}, search), select([['', 'All categories'], ...CATS.map((c) => [c, c])], cat, (v) => { cat = v; load(); }),
    h('label.row', {}, toggle(app.settings.privacy.temporaryMemory, async (v) => { app.settings.privacy = await api.patch('/settings/privacy', { temporaryMemory: v }); toast(v ? 'Temporary memory on' : 'Temporary memory off', v ? 'New memories are forgotten when VIPER closes.' : 'New memories are saved permanently.'); }, 'Temporary memory mode'), h('small', {}, 'Temporary mode')))),
  list, importIn);
  async function load() {
    const items = await api.get(q ? `/memory?q=${encodeURIComponent(q)}` : `/memory${cat ? `?category=${cat}` : ''}`).catch(() => []);
    const shown = cat ? items.filter((m) => m.category === cat) : items;
    clear(list);
    if (!shown.length) { list.append(h('div.empty', {}, h('b', {}, q ? 'No memories match' : 'Nothing remembered yet'), 'Say “VIPER, remember that I prefer short responses” or add one here.')); return; }
    list.append(h('div.panel', {}, h('div.list', {}, shown.map((m) => h('div.li', {}, h('span.tag', {}, m.category), h('div.t', {}, h('b', { style: { whiteSpace: 'normal' } }, m.content), h('small', {}, `${m.source} · ${when(m.updated_at || m.created_at)}${m.temporary ? ' · temporary' : ''}`)),
      btn('', () => edit(m), { cls: 'sm ghost icon', ico: 'edit', title: 'Edit' }),
      btn('', async () => { if (await ask('Forget this?', m.content, { danger: true, confirmLabel: 'Forget' })) { await api.del(`/memory/${m.id}`); load(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' }))))));
  }
  function edit(m) {
    const t = h('textarea.input', { rows: 3 }, m?.content || ''); let c = m?.category || 'fact';
    modal({ title: m ? 'Edit memory' : 'Add memory', body: h('div.col', {}, field('Memory', t), field('Category', select(CATS.map((x) => [x, x]), c, (v) => { c = v; }))),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Save', cls: 'primary', onClick: async () => { try { if (m) await api.patch(`/memory/${m.id}`, { content: t.value, category: c }); else await api.post('/memory', { content: t.value, category: c }); load(); } catch (e) { toastError(e); return false; } } }] });
  }
  function add() { edit(null); }
  const off = api.on('memory.changed', load);
  load();
  return off;
}
