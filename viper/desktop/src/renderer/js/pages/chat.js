import { h, icon, clear, mdEl, toast, toastError, prompt, ask, download, when, btn } from '../ui.js';
import { composer } from '../components/composer.js';
import { followRequest } from '../components/stream.js';

export async function render(view, { app, api, params }) {
  view.className = 'view flush';
  let current = params?.conversationId || sessionStorage.getItem('viper.chatConv') || null;
  let q = ''; let models = []; let override = null;
  const items = h('div.items');
  const search = h('input.input', { placeholder: 'Search conversations', 'aria-label': 'Search conversations', oninput: (e) => { q = e.target.value; loadList(); } });
  const msgs = h('div.msgs', { 'aria-live': 'polite' });
  const title = h('div.title.grow', {}, 'New conversation');
  const modelSel = h('select.input', { style: { width: '220px' }, 'aria-label': 'Model for this conversation', onchange: (e) => { override = e.target.value ? JSON.parse(e.target.value) : null; } });
  const privTag = h('span.badge-inv.hidden', {}, 'Private — not saved');
  const barActions = h('div.row', {},
    btn('', () => current && rename(current), { cls: 'ghost sm icon', ico: 'edit', title: 'Rename' }),
    btn('', () => current && exportConv('markdown'), { cls: 'ghost sm icon', ico: 'download', title: 'Export as Markdown' }),
    btn('', () => current && exportConv('json'), { cls: 'ghost sm icon', ico: 'copy', title: 'Export as JSON' }));
  const comp = composer({
    app,
    onSend: async (text, attachments, setBusy) => {
      const isPrivate = current?.startsWith('pc_') || pendingPrivate;
      try {
        const r = await app.send(text, { conversationId: current, attachments, mode: 'chat', model: override, private: isPrivate });
        pendingPrivate = false;
        if (r.conversationId !== current) { current = r.conversationId; if (!current.startsWith('pc_')) sessionStorage.setItem('viper.chatConv', current); }
        addMsg({ role: 'user', content: text || '(attachment)', attachments: attachments.map((a) => ({ type: a.type, name: a.name })), created_at: Date.now() });
        const slot = h('div.msg.viper', {}, h('div.who', {}, 'V'), h('div'));
        msgs.append(slot); msgs.scrollTop = msgs.scrollHeight;
        setBusy(r.requestId);
        followRequest(app, r.requestId, slot.lastChild, { scroller: msgs, onDone: () => { setBusy(null); loadList(); }, onError: () => setBusy(null) });
      } catch (e) { toastError(e); }
    },
  });
  let pendingPrivate = false;

  view.append(h('div.chat', {},
    h('div.sessions', {},
      h('div.head', {}, h('div.row', {}, btn('New chat', () => open(null), { cls: 'primary sm grow', ico: 'plus' }), btn('', () => { open(null); pendingPrivate = true; privTag.classList.remove('hidden'); title.textContent = 'Private conversation'; }, { cls: 'sm icon', ico: 'shield', title: 'New private chat (never saved)' })), search),
      items),
    h('div.convo', {},
      h('div.bar', {}, title, privTag, modelSel, barActions),
      msgs,
      h('div.compose-wrap', {}, comp.el))));

  async function loadList() {
    let list = [];
    try { list = await api.get(`/conversations?mode=chat${q ? `&q=${encodeURIComponent(q)}` : ''}`); } catch (e) { toastError(e); }
    if (q) list = list.filter(Boolean);
    clear(items);
    if (!list.length) items.append(h('div.empty', { style: { margin: '10px' } }, q ? 'No conversations match.' : 'No conversations yet. Say hello.'));
    for (const c of list) {
      items.append(h(`div.sess${c.id === current ? '.on' : ''}`, { onclick: () => open(c.id), tabindex: 0, onkeydown: (e) => { if (e.key === 'Enter') open(c.id); } },
        c.pinned ? icon('pin') : c.private ? icon('shield') : null,
        h('span.ttl', {}, c.title),
        h('span.acts', {},
          h('button.btn.sm.ghost.icon', { title: c.pinned ? 'Unpin' : 'Pin', 'aria-label': 'Pin', onclick: async (e) => { e.stopPropagation(); await api.patch(`/conversations/${c.id}`, { pinned: !c.pinned }); loadList(); } }, icon('pin')),
          h('button.btn.sm.ghost.icon', { title: 'Delete', 'aria-label': 'Delete', onclick: async (e) => { e.stopPropagation(); if (await ask('Delete conversation?', `"${c.title}" and its messages will be permanently deleted.`, { confirmLabel: 'Delete', danger: true })) { await api.del(`/conversations/${c.id}`); if (current === c.id) open(null); else loadList(); } } }, icon('trash')))));
    }
  }
  async function open(id) {
    current = id; pendingPrivate = false; privTag.classList.add('hidden');
    if (id && !id.startsWith('pc_')) sessionStorage.setItem('viper.chatConv', id); else if (!id) sessionStorage.removeItem('viper.chatConv');
    clear(msgs);
    title.textContent = 'New conversation';
    if (id) {
      try {
        const list = await api.get('/conversations?mode=chat');
        const c = list.find((x) => x.id === id);
        if (c) { title.textContent = c.title; privTag.classList.toggle('hidden', !c.private); }
        for (const m of await api.get(`/conversations/${id}/messages`)) addMsg(m);
      } catch (e) { toastError(e); }
    }
    if (!msgs.children.length) msgs.append(h('div.empty', { style: { margin: '10vh auto', maxWidth: '460px' } }, h('b', {}, 'Start a conversation'), 'Type below, attach documents or images, or hold the mic button to talk. VIPER remembers what you ask it to.'));
    loadList(); comp.focus();
  }
  function addMsg(m) {
    msgs.querySelector('.empty')?.remove();
    const isUser = m.role === 'user';
    const meta = h('div.meta', {}, when(m.created_at));
    if (!isUser) {
      if (m.model) meta.append(h('span', {}, m.model.split(':').slice(1).join(':') || m.model));
      if (m.meta?.perf?.tokPerS) meta.append(h('span', {}, `${m.meta.perf.tokPerS} tok/s`));
      if (m.meta?.route === 'intent') meta.append(h('span', {}, 'direct command'));
      meta.append(h('button', { onclick: () => navigator.clipboard?.writeText(m.content) }, 'Copy'), h('button', { onclick: () => app.voice.speak(m.content) }, 'Speak'));
    }
    const tools = (m.meta?.tools || []).map((t) => h(`span.toolcard${t.ok ? '' : '.failed'}`, {}, icon(t.ok ? 'check' : 'x'), `${t.name.replace(/_/g, ' ')} — ${t.summary}`));
    msgs.append(h(`div.msg.${isUser ? 'user' : 'viper'}`, {}, h('div.who', {}, isUser ? 'You' : 'V'),
      h('div.body', {}, tools.length ? h('div', {}, tools) : null, isUser ? h('div', { style: { whiteSpace: 'pre-wrap' } }, m.content) : mdEl(m.content),
        (m.attachments || []).length ? h('div', {}, m.attachments.map((a) => h('span.tag', {}, icon(a.type === 'image' ? 'image' : 'file'), a.name))) : null, meta)));
    msgs.scrollTop = msgs.scrollHeight;
  }
  async function rename(id) {
    const v = await prompt('Rename conversation', { value: title.textContent });
    if (v) { await api.patch(`/conversations/${id}`, { title: v }); title.textContent = v; loadList(); }
  }
  async function exportConv(fmt) {
    if (current.startsWith('pc_')) { toast('Private conversation', 'Private chats can still be exported while open.'); }
    const r = await api.req('GET', `/conversations/${current}/export?format=${fmt}`, undefined, { raw: true });
    download(`viper-${title.textContent.replace(/[^\w-]+/g, '_').slice(0, 40)}.${fmt === 'json' ? 'json' : 'md'}`, await r.text());
  }
  // model selector (switch models mid-conversation)
  try {
    models = (await api.get('/models')).filter((m) => m.capabilities?.includes('chat'));
    modelSel.append(h('option', { value: '' }, 'Auto (configured chat model)'), ...models.map((m) => h('option', { value: JSON.stringify({ backend: m.backend, model: m.id }) }, `${m.id} · ${m.backend}`)));
  } catch { modelSel.append(h('option', { value: '' }, 'Auto')); }
  open(current);
  const offRemote = api.on('chat.start', (d) => { if (d.conversationId === current && d.userMessage?.meta?.device) { addMsg(d.userMessage); const slot = h('div.msg.viper', {}, h('div.who', {}, 'V'), h('div')); msgs.append(slot); followRequest(app, d.requestId, slot.lastChild, { scroller: msgs }); } });
  return () => offRemote();
}
