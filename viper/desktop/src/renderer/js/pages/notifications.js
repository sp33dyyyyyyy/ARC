import { h, clear, icon, btn, busy, toast, toastError, select, when } from '../ui.js';

// MANAGE → Notifications: everything VIPER has told you, with read/unread state, the action that
// produced it (deep link) and where it was delivered. Test buttons send real notifications through
// the same path as genuine events.
const KIND_LABEL = { task_complete: 'Task complete', input_required: 'Input required', approval_required: 'Approval required', error: 'Attention required', project_complete: 'Project complete', code_complete: 'Code Agent', download_complete: 'Download complete', system_alert: 'System alert' };

/** Open whatever a notification links to. Unknown links fall back to this page. */
export function openLink(app, link) {
  if (!link) return app.go('notifications');
  if (link.type === 'agent_run') return app.go('agent', { project: link.projectId, run: link.id });
  if (link.type === 'decision') return app.go('agent', { project: link.projectId, run: link.runId, decision: link.id });
  if (link.type === 'agent_project') return app.go('agent', { project: link.id });
  if (link.type === 'confirm') return toast('Approval request', 'It is shown in the approval dialog on this PC.');
  if (link.type === 'download') return app.go('models');
  if (link.type === 'system') return app.go('system');
  if (link.type === 'automation') return app.go('automation');
  return app.go('notifications');
}

export async function render(view, { app, api }) {
  let filter = 'all'; let kind = '';
  const bar = h('div.row.wrap', { style: { marginBottom: '12px' } }); const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Notifications'), h('div.sub', {}, 'Alerts from VIPER on this PC and your phone. Opening one marks it as read.')),
    h('div.actions', {}, btn('Mark all read', async (e) => busy(e.currentTarget, async () => { await api.post('/notifications/all/read'); draw(); }), { cls: 'sm' }),
      btn('Notification settings', () => app.go('settings', { tab: 'notifications' }), { cls: 'sm ghost', ico: 'settings' }))),
  bar, body);
  const kinds = await api.get('/notifications/kinds').catch(() => []);
  const testKind = select(kinds.map((k) => [k.kind, KIND_LABEL[k.kind] || k.kind]), kinds[0]?.kind || 'task_complete', () => {});
  clear(bar).append(
    h('div.seg', {}, ...[['all', 'All'], ['unread', 'Unread']].map(([v, l]) => h(`button${filter === v ? '.on' : ''}`, { onclick: (e) => { filter = v; e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === e.currentTarget)); draw(); } }, l))),
    select([['', 'Every kind'], ...Object.entries(KIND_LABEL)], '', (v) => { kind = v; draw(); }),
    h('span.grow'),
    h('span.small.mist', {}, 'Send a test:'), testKind,
    btn('Send', async (e) => busy(e.currentTarget, async () => {
      try {
        const r = await api.post('/notifications/test', { kind: testKind.value || testKind.querySelector('select')?.value, channels: app.settings.notifications.defaultChannels });
        const res = Object.entries(r.results || {}).map(([c, x]) => `${c}: ${x.ok ? 'delivered' : x.queued ? 'queued' : x.skipped ? 'skipped' : 'failed'}${x.error ? ` (${x.error})` : ''}`).join(' · ');
        toast('Test notification sent', res || 'Logged'); draw();
      } catch (err) { toastError(err); }
    }), { cls: 'sm' }));

  async function draw() {
    let list;
    try { list = await api.get(`/notifications${filter === 'unread' ? '?unread=1' : ''}`); } catch (e) { clear(body).append(h('div.empty', {}, e.message)); return; }
    if (kind) list = list.filter((n) => n.kind === kind);
    clear(body).append(list.length ? h('div.ntf-list', {}, list.map((n) => item(n))) : h('div.empty', {}, filter === 'unread' ? 'No unread notifications.' : 'No notifications yet.'));
  }
  function item(n) {
    const delivered = (n.deliveries || []).map((d) => `${d.channel} ${d.status}`).join(' · ');
    const open = async () => { if (!n.read) await api.post(`/notifications/${n.id}/read`).catch(() => {}); openLink(app, n.link); };
    return h(`div.ntf${n.read ? '' : '.unread'}`, {},
      h('span.ntf-dot', { 'aria-label': n.read ? 'Read' : 'Unread' }),
      h('div.t', {}, h('b', {}, n.title), h('span', {}, n.body || ''), h('small.mist', {}, `${when(n.created_at)}${n.kind ? ` · ${KIND_LABEL[n.kind] || n.kind}` : ` · ${n.category}`}${delivered ? ` · ${delivered}` : ''}`)),
      h('div.row', {},
        n.link && n.link.type !== 'notifications' ? btn('Open', open, { cls: 'sm' }) : null,
        !n.read ? btn('Mark read', async () => { await api.post(`/notifications/${n.id}/read`); draw(); }, { cls: 'sm ghost' }) : null));
  }
  await draw();
  const offs = [api.on('notification', () => draw()), api.on('notifications.read', () => draw())];
  return () => offs.forEach((o) => o());
}
