import { h, clear, icon, btn, when } from '../ui.js';

// PROMPT → Memory Search: one search across what VIPER remembers, your conversations and the
// documents in your Knowledge Base.
export async function render(view, { app, api }) {
  let timer = null;
  const out = h('div');
  const input = h('input.input', { type: 'search', placeholder: 'Search memories, conversations and documents', autofocus: true, oninput: () => { clearTimeout(timer); timer = setTimeout(run, 260); } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Memory Search'), h('div.sub', {}, 'Searches only data stored on this PC.')),
    h('div.actions', {}, btn('Manage memories', () => app.go('memory'), { cls: 'sm ghost', ico: 'memory' }))),
  h('div.panel', { style: { marginBottom: '14px' } }, input), out);
  setTimeout(() => input.focus(), 50);
  async function run() {
    const q = input.value.trim();
    if (q.length < 2) { clear(out).append(h('div.empty', {}, 'Type at least two characters.')); return; }
    const [mem, conv, docs] = await Promise.all([
      api.get(`/memory?q=${encodeURIComponent(q)}`).catch(() => []),
      api.get(`/conversations?q=${encodeURIComponent(q)}`).catch(() => []),
      api.post('/files/search', { query: q, limit: 8 }).catch(() => []),
    ]);
    const docHits = Array.isArray(docs) ? docs : docs.results || [];
    const sec = (title, ico, items, row) => h('div.panel', { style: { marginBottom: '14px' } }, h('h3', {}, icon(ico), title, h('span.r', {}, h('span.tag', {}, String(items.length)))), items.length ? h('div.list', {}, items.slice(0, 12).map(row)) : h('small.mist', {}, 'No matches.'));
    clear(out).append(
      sec('Memories', 'memory', mem, (m) => h('div.li', {}, h('span.tag', {}, m.category), h('div.t', {}, h('b', { style: { whiteSpace: 'normal' } }, m.content), h('small', {}, when(m.created_at))))),
      sec('Conversations', 'chat', conv, (c) => h('div.li', {}, h('div.t', {}, h('b', {}, c.title || 'Untitled'), h('small', {}, when(c.updated_at))), btn('Open', () => { sessionStorage.setItem('viper.chatConv', c.id); app.go('chat', { conversationId: c.id }); }, { cls: 'sm' }))),
      sec('Documents', 'files', docHits, (d) => h('div.li', {}, h('div.t', {}, h('b', {}, d.name || d.path || d.title || 'Document'), h('small', { style: { whiteSpace: 'normal' } }, String(d.text || d.snippet || '').slice(0, 220))))));
  }
  return () => clearTimeout(timer);
}
