import { h, clear, btn, toast, toastError, ask, prompt, when, download } from '../ui.js';

// PROMPT → AI Conversations: every saved conversation, searchable by title and message text.
export async function render(view, { app, api }) {
  let q = ''; let timer = null;
  const list = h('div');
  const search = h('input.input', { type: 'search', placeholder: 'Search titles and messages', oninput: (e) => { q = e.target.value.trim(); clearTimeout(timer); timer = setTimeout(load, 220); } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'AI Conversations'), h('div.sub', {}, 'Your saved conversations with VIPER, stored on this PC. Open one to continue it.')),
    h('div.actions', {}, btn('New conversation', async () => { try { const c = await api.post('/conversations', { title: 'New conversation' }); app.go('chat', { conversationId: c.id }); } catch (e) { toastError(e); } }, { cls: 'primary', ico: 'plus' }))),
  h('div.panel', { style: { marginBottom: '14px' } }, search), list);
  async function load() {
    let rows;
    try { rows = await api.get(`/conversations${q ? `?q=${encodeURIComponent(q)}` : ''}`); } catch (e) { clear(list).append(h('div.empty', {}, e.message)); return; }
    clear(list).append(rows.length ? h('div.panel', {}, h('div.list', {}, rows.map((c) => h('div.li', {},
      c.pinned ? h('span.tag', {}, 'Pinned') : null,
      h('div.t', {}, h('b', {}, c.title || 'Untitled'), h('small', {}, `${c.mode || 'chat'} · updated ${when(c.updated_at)}`)),
      btn('Open', () => { sessionStorage.setItem('viper.chatConv', c.id); app.go('chat', { conversationId: c.id }); }, { cls: 'sm' }),
      btn('', async () => { const t = await prompt('Rename conversation', { label: 'Title', value: c.title || '' }); if (t) { await api.patch(`/conversations/${c.id}`, { title: t }); load(); } }, { cls: 'sm ghost icon', ico: 'edit', title: 'Rename' }),
      btn('', async () => { try { await api.patch(`/conversations/${c.id}`, { pinned: !c.pinned }); load(); } catch (e) { toastError(e); } }, { cls: 'sm ghost icon', ico: 'pin', title: c.pinned ? 'Unpin' : 'Pin' }),
      btn('', async () => { const r = await api.req('GET', `/conversations/${c.id}/export`, undefined, { raw: true }); download(`${(c.title || 'conversation').replace(/[^\w -]/g, '')}.md`, await r.text(), 'text/markdown'); }, { cls: 'sm ghost icon', ico: 'download', title: 'Export as Markdown' }),
      btn('', async () => { if (await ask('Delete this conversation?', c.title || '', { danger: true, confirmLabel: 'Delete' })) { await api.del(`/conversations/${c.id}`); toast('Conversation deleted'); load(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' }))))) 
      : h('div.empty', {}, q ? 'No conversations match.' : 'No conversations yet.'));
  }
  await load();
  return () => clearTimeout(timer);
}
