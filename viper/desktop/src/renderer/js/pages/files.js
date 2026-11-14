import { h, clear, icon, btn, busy, toast, toastError, mdEl, bytes, when, ask, prompt, readFileAs } from '../ui.js';

export async function render(view, { app, api }) {
  let browsing = null; let selected = new Set();
  const docs = h('div'); const browser = h('div'); const out = h('div.panel', { style: { minHeight: '260px' } });
  const q = h('input.input', { placeholder: 'Ask a question or search your documents', onkeydown: (e) => { if (e.key === 'Enter') askDocs(); } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'File Intelligence'), h('div.sub', {}, 'Read, search and question your documents locally — PDF, Word, Excel, CSV, text and code. File contents are treated as data, never as instructions.')),
    h('div.actions', {}, btn('Read a file now', () => quickFile.click(), { ico: 'upload' }))),
  h('div.panel', { style: { marginBottom: '14px' } }, h('div.row', {}, h('div.grow', {}, q), btn('Ask', (e) => busy(e.currentTarget, askDocs), { cls: 'primary' }), btn('Search', (e) => busy(e.currentTarget, searchDocs), { cls: '' }))),
  h('div.grid.g2', {}, h('div.col', {}, h('div.panel', {}, h('h3', {}, icon('folder'), 'Browse allowed folders'), browser), h('div.panel', {}, h('h3', {}, icon('files'), 'Indexed documents'), docs)), out));
  const quickFile = h('input', { type: 'file', style: { display: 'none' }, onchange: async (e) => {
    const f = e.target.files[0]; if (!f) return; e.target.value = '';
    clear(out).append(h('div.progress.indet', {}, h('i')));
    try { const r = await api.post('/files/extract', { name: f.name, data: await readFileAs(f) }); clear(out).append(h('h3', {}, f.name, h('span.r', {}, `${r.text.length.toLocaleString()} characters`)), btn('Ask VIPER about this file in Chat', async () => { const c = await app.send(`Summarise this document and list its key points.`, { attachments: [{ type: 'document', name: f.name, text: r.text }] }); app.go('chat', { conversationId: c.conversationId }); }, { cls: 'sm primary' }), h('pre.mono', { style: { whiteSpace: 'pre-wrap', maxHeight: '60vh', overflow: 'auto' } }, r.text.slice(0, 20000))); } catch (err) { clear(out).append(h('p', {}, err.message)); }
  } });
  view.append(quickFile);

  async function browse(p) {
    try {
      const r = await api.post('/files/browse', { path: p });
      browsing = r.path; selected = new Set();
      clear(browser).append(h('div.row.wrap', { style: { marginBottom: '6px' } }, ...r.roots.map((root) => btn(root.split(/[\\/]/).pop(), () => browse(root), { cls: 'sm ghost' }))),
        h('div.row', {}, h('small.mist.grow', {}, r.path), r.parent ? btn('Up', () => browse(r.parent), { cls: 'sm' }) : null, btn('Index this folder', (e) => busy(e.currentTarget, async () => { const x = await api.post('/files/index', { path: r.path }); toast('Indexing started', `${x.files} supported files found.`); }), { cls: 'sm primary' })),
        h('div.list', { style: { maxHeight: '320px', overflowY: 'auto' } }, r.entries.map((e) => h('div.li', {}, icon(e.dir ? 'folder' : 'file'), h('div.t', { style: { cursor: e.dir ? 'pointer' : 'default' }, onclick: () => e.dir && browse(e.path) }, h('b', {}, e.name)),
          e.supported ? h('div.row', {}, btn('Summarise', (ev) => busy(ev.currentTarget, () => summarize(e.path)), { cls: 'sm ghost' }), /\.(xlsx|xls|csv|ods)$/i.test(e.name) ? btn('Analyse data', (ev) => busy(ev.currentTarget, () => sheet(e.path)), { cls: 'sm ghost' }) : null, h('input', { type: 'checkbox', title: 'Select for comparison', 'aria-label': `Select ${e.name}`, onchange: (ev) => { ev.target.checked ? selected.add(e.path) : selected.delete(e.path); cmpBtn.disabled = selected.size !== 2; } })) : null))),
        h('div.row', { style: { marginTop: '8px' } }, cmpBtn));
    } catch (e) { clear(browser).append(h('p.small', {}, e.message)); }
  }
  const cmpBtn = btn('Compare 2 selected', (e) => busy(e.currentTarget, async () => { const [a, b] = [...selected]; clear(out).append(h('div.progress.indet', {}, h('i'))); try { const r = await api.post('/files/compare', { a, b }); clear(out).append(h('h3', {}, `${r.a} ↔ ${r.b}`), mdEl(r.analysis), h('details', {}, h('summary', {}, `Line differences (+${r.added.length} / −${r.removed.length})`), h('div.diff', {}, ...r.removed.slice(0, 80).map((l) => h('div.del', {}, `- ${l}`)), ...r.added.slice(0, 80).map((l) => h('div.add', {}, `+ ${l}`))))); } catch (err) { clear(out).append(h('p', {}, err.message)); } }), { cls: 'sm', disabled: true });
  async function summarize(p) { clear(out).append(h('div.progress.indet', {}, h('i')), h('small.mist', {}, 'Reading and summarising…')); try { const r = await api.post('/files/summarize', { path: p }); clear(out).append(h('h3', {}, r.name), mdEl(r.summary)); } catch (e) { clear(out).append(h('p', {}, e.message)); } }
  async function sheet(p) { clear(out).append(h('div.progress.indet', {}, h('i'))); try { const r = await api.post('/files/spreadsheet', { path: p }); clear(out).append(h('h3', {}, r.name), ...(r.sheets || []).map((s) => h('div', {}, h('b', {}, `${s.name}: ${s.rows} rows`), s.numeric.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Column', 'Min', 'Max', 'Mean', 'Sum'].map((t) => h('th', {}, t)))), h('tbody', {}, s.numeric.map((n) => h('tr', {}, [n.column, n.min, n.max, n.mean, n.sum].map((v) => h('td', {}, String(v))))))) : null)), mdEl(r.analysis)); } catch (e) { clear(out).append(h('p', {}, e.message)); } }
  async function askDocs() {
    if (!q.value.trim()) return;
    clear(out).append(h('div.progress.indet', {}, h('i')));
    try {
      const r = await api.post('/files/ask', { question: q.value });
      clear(out).append(h('h3', {}, 'Answer', h('span.r', {}, r.semantic ? 'semantic + keyword search' : 'keyword search')), mdEl(r.answer), r.sources.length ? h('ol', { style: { paddingLeft: '20px', marginTop: '10px' } }, r.sources.map((s) => h('li', {}, h('b', { style: { fontWeight: 400 } }, s.name), h('small.mist', { style: { display: 'block' } }, s.excerpt.slice(0, 160) + '…')))) : null);
    } catch (e) { clear(out).append(h('p', {}, e.message)); }
  }
  async function searchDocs() {
    if (!q.value.trim()) return;
    const r = await api.post('/files/search', { query: q.value });
    clear(out).append(h('h3', {}, `${r.results.length} matches`, h('span.r', {}, r.semantic ? 'semantic' : 'keyword')), h('div.list', {}, r.results.map((x) => h('div.li', {}, h('div.t', {}, h('b', {}, `${x.name} · score ${x.score}`), h('small', { style: { whiteSpace: 'normal' } }, x.text.slice(0, 280)))))));
  }
  async function loadDocs() {
    const list = await api.get('/files/documents').catch(() => []);
    clear(docs).append(list.length ? h('div.list', { style: { maxHeight: '300px', overflowY: 'auto' } }, list.map((d) => h('div.li', {}, h('div.t', {}, h('b', {}, d.name), h('small', {}, d.error ? `Error: ${d.error}` : `${d.chunk_count} chunks · ${bytes(d.size)} · ${d.embedded ? 'semantic' : 'keyword'} · ${when(d.indexed_at)}`)), btn('', async () => { await api.del(`/files/documents/${d.id}`); loadDocs(); }, { cls: 'sm ghost icon', ico: 'x', title: 'Remove from index' })))) : h('small.mist', {}, 'Nothing indexed yet. Browse to a folder and choose Index this folder. With an embeddings model installed (e.g. nomic-embed-text) search becomes semantic.'));
  }
  const off = api.on('files.indexed', (d) => { toast('Indexing finished', `${d.done} files${d.errors ? `, ${d.errors} could not be read` : ''}.`); loadDocs(); });
  browse(); loadDocs();
  clear(out).append(h('div.empty', {}, h('b', {}, 'Ask your documents anything'), 'Index a folder, then ask questions. Answers cite the documents they came from.'));
  return off;
}
