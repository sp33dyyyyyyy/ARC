import { h, clear, icon, btn, toast, toastError, ask, prompt, toggle, when } from '../ui.js';

// MANAGE → Scheduled Tasks: reminders and automations that run on a schedule.
export async function render(view, { app, api }) {
  const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Scheduled Tasks'), h('div.sub', {}, 'Reminders and scheduled automations. They run while VIPER is running (including from the tray).')),
    h('div.actions', {},
      btn('New reminder', async () => {
        const text = await prompt('New reminder', { label: 'Remind me to…' }); if (!text) return;
        const w = await prompt('When?', { label: 'e.g. in 20 minutes, tomorrow at 9am, Friday 17:30' }); if (!w) return;
        try { const r = await api.post('/reminders', { text, when: w }); toast('Reminder set', `${text} — ${when(r.due_at || r.dueAt)}`); draw(); } catch (e) { toastError(e); }
      }, { cls: 'sm primary', ico: 'plus' }),
      btn('New automation', () => app.go('automation'), { cls: 'sm', ico: 'automation' }))), body);
  async function draw() {
    const [rem, autos] = await Promise.all([api.get('/reminders').catch(() => []), api.get('/automations').catch(() => [])]);
    const pending = rem.filter((r) => r.status === 'pending');
    const scheduled = autos.filter((a) => ['cron', 'interval', 'once', 'startup'].includes(a.trigger?.type));
    clear(body).append(
      h('div.panel', { style: { marginBottom: '14px' } }, h('h3', {}, icon('clock'), 'Reminders', h('span.r', {}, h('span.tag', {}, String(pending.length)))),
        pending.length ? h('div.list', {}, pending.map((r) => h('div.li', {}, h('div.t', {}, h('b', {}, r.text), h('small', {}, `due ${when(r.due_at)}`)),
          btn('', async () => { if (await ask('Delete reminder?', r.text, { danger: true, confirmLabel: 'Delete' })) { await api.del(`/reminders/${r.id}`); draw(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' }))))
          : h('div.empty', {}, 'No upcoming reminders.')),
      h('div.panel', {}, h('h3', {}, icon('automation'), 'Scheduled automations', h('span.r', {}, h('span.tag', {}, String(scheduled.length)))),
        scheduled.length ? h('div.list', {}, scheduled.map((a) => h('div.li', {}, toggle(a.enabled, async (v) => { try { await api.patch(`/automations/${a.id}`, { enabled: v }); draw(); } catch (e) { toastError(e); } }, `Enable ${a.name}`),
          h('div.t', {}, h('b', {}, a.name), h('small', {}, `${describe(a.trigger)}${a.nextRun ? ` · next ${when(a.nextRun)}` : ''}${a.last_run_at ? ` · last ran ${when(a.last_run_at)}` : ''}`)),
          btn('Run now', async (e) => { try { await api.post(`/automations/${a.id}/run`); toast('Automation started', a.name); } catch (err) { toastError(err); } }, { cls: 'sm' }))))
          : h('div.empty', {}, 'No scheduled automations. Create one in Automations, e.g. “every weekday at 8am, give me a briefing”.')));
  }
  await draw();
  const offs = [api.on('reminder', draw), api.on('automation.run', draw)];
  return () => offs.forEach((o) => o());
}
function describe(t) {
  if (!t) return 'manual';
  if (t.type === 'once') return `once at ${when(t.at)}`;
  if (t.type === 'cron') return t.label || `schedule “${t.cron}”`;
  if (t.type === 'interval') return `every ${t.minutes} min`;
  if (t.type === 'startup') return 'when VIPER starts';
  return t.label || t.type;
}
