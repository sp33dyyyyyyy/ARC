import { h, clear, icon, btn, busy, toast, toastError, ask, prompt, when, mdEl } from '../ui.js';

// INTELLIGENCE → Knowledge Base: folders and documents VIPER has indexed on this PC, semantic
// search over them, and questions answered from them with sources.
export async function render(view, { app, api }) {
  const list = h('div'); const answer = h('div');
  const q = h('input.input', { type: 'search', placeholder: 'Ask a question about your documents', onkeydown: (e) => { if (e.key === 'Enter') askBtn.click(); } });
  const askBtn = btn('Ask', async (e) => busy(e.currentTarget, async () => {
    if (!q.value.trim()) return;
    try {
      const r = await api.post('/files/ask', { question: q.value.trim() });
      clear(answer).append(h('div.panel', { style: { marginTop: '10px' } }, mdEl(r.answer || r.text || ''), (r.sources || []).length ? h('small.mist', {}, `Sources: ${r.sources.map((s) => s.name || s.path).join(', ')}`) : null));
    } catch (err) { toastError(err); }
  }), { cls: 'primary', ico: 'sparkle' });
  const searchBtn = btn('Search', async (e) => busy(e.currentTarget, async () => {
    if (!q.value.trim()) return;
    try {
      const r = await api.post('/files/search', { query: q.value.trim(), limit: 10 }); const hits = Array.isArray(r) ? r : r.results || [];
      clear(answer).append(h('div.panel', { style: { marginTop: '10px' } }, hits.length ? h('div.list', {}, hits.map((x) => h('div.li', {}, h('div.t', {}, h('b', {}, x.name || x.path), h('small', { style: { whiteSpace: 'normal' } }, String(x.text || x.snippet || '').slice(0, 280)))))) : h('small.mist', {}, 'No matches.')));
    } catch (err) { toastError(err); }
  }), { cls: '' });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Knowledge Base'), h('div.sub', {}, 'Documents indexed on this PC for search and questions. Nothing is uploaded.')),
    h('div.actions', {}, btn('Add folder or file', async () => {
      const p = window.viperNative?.pickFolder ? await window.viperNative.pickFolder() : await prompt('Index a folder', { label: 'Full path inside an allowed folder' });
      if (!p) return;
      try { const r = await api.post('/files/index', { path: p, recursive: true }); toast('Indexing started', `${r.files} file(s) — progress is shown in Background Tasks.`); load(); } catch (e) { toastError(e); }
    }, { cls: 'primary', ico: 'plus' }), btn('File Manager', () => app.go('files'), { cls: 'sm ghost', ico: 'files' }))),
  h('div.panel', {}, h('div.row', {}, h('div.grow', {}, q), searchBtn, askBtn)), answer,
  h('div', { style: { marginTop: '14px' } }, list));
  async function load() {
    const docs = await api.get('/files/documents').catch(() => []);
    clear(list).append(h('div.panel', {}, h('h3', {}, icon('files'), 'Indexed documents', h('span.r', {}, h('span.tag', {}, String(docs.length)))),
      docs.length ? h('div.list', {}, docs.slice(0, 300).map((d) => h('div.li', {}, icon('file'), h('div.t', {}, h('b', {}, d.name || d.path), h('small', {}, `${d.path || ''}${d.indexed_at ? ` · indexed ${when(d.indexed_at)}` : ''}${d.chunk_count ? ` · ${d.chunk_count} passages` : ''}${d.error ? ` · ${d.error}` : ''}`)),
        btn('', async () => { if (await ask('Remove from the knowledge base?', 'The file itself is not deleted.', { confirmLabel: 'Remove' })) { await api.del(`/files/documents/${d.id}`); load(); } }, { cls: 'sm ghost icon', ico: 'x', title: 'Remove from index' }))))
        : h('div.empty', {}, 'Nothing indexed yet. Add a folder of documents (PDF, Word, text, Markdown, spreadsheets).')));
  }
  await load();
  const off = api.on('tasks.changed', (d) => { if (d?.task?.kind === 'index' && d.task.state !== 'running') load(); });
  return off;
}
