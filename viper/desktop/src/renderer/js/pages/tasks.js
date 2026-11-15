import { h, clear, icon, btn, toast, toastError, progress, ago, bytes } from '../ui.js';
import { openLink } from './notifications.js';

// MANAGE → Background Tasks: work VIPER is doing right now (Code Agent runs, model downloads,
// automations, research, media jobs, AI requests). Updated live from the task events.
const KIND_ICON = { agent: 'code', download: 'download', automation: 'automation', research: 'research', media: 'film', image: 'image', index: 'files' };
export async function render(view, { app, api }) {
  const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Background Tasks'), h('div.sub', {}, 'Everything VIPER is working on. Finished tasks stay listed for a minute.')),
    h('div.actions', {}, btn('Scheduled tasks', () => app.go('scheduled'), { cls: 'sm ghost', ico: 'clock' }))), body);
  async function draw() {
    const [t, dls] = await Promise.all([api.get('/tasks').catch(() => ({ tasks: [], ai: [] })), api.get('/models/downloads').catch(() => [])]);
    const tasks = t.tasks || []; const ai = t.ai || [];
    const running = tasks.filter((x) => x.state === 'running');
    const done = tasks.filter((x) => x.state !== 'running');
    const row = (x) => {
      const dl = x.kind === 'download' ? dls.find((d) => `dl:${d.id}` === x.id) : null;
      const frac = dl?.total ? dl.completed / dl.total : (typeof x.progress === 'number' ? x.progress : null);
      return h('div.li', {}, icon(KIND_ICON[x.kind] || 'refresh'),
        h('div.t', {}, h('b', {}, x.label), h('small', {}, `${x.state === 'running' ? 'running' : x.state} · started ${ago(x.startedAt)}${x.detail ? ` · ${x.detail}` : ''}${x.error ? ` · ${x.error}` : ''}${dl?.total ? ` · ${bytes(dl.completed)} of ${bytes(dl.total)}` : ''}`),
          x.state === 'running' ? progress(frac) : null),
        x.link ? btn('Open', () => openLink(app, x.link), { cls: 'sm' }) : null,
        x.kind === 'agent' && x.state === 'running' ? btn('Cancel', async () => { try { await api.post(`/agent/runs/${x.runId}/cancel`); toast('Cancelling', x.label); } catch (e) { toastError(e); } }, { cls: 'sm ghost' }) : null,
        dl && x.state === 'running' ? btn('Cancel', async () => { await api.post('/models/cancel', { id: dl.id }); }, { cls: 'sm ghost' }) : null);
    };
    clear(body).append(
      h('div.panel', { style: { marginBottom: '14px' } }, h('h3', {}, 'Running', h('span.r', {}, h('span.tag', {}, String(running.length + ai.length)))),
        running.length || ai.length ? h('div.list', {}, ...running.map(row), ...ai.map((a) => h('div.li', {}, icon('models'), h('div.t', {}, h('b', {}, a.label || a.task || 'AI request'), h('small', {}, `${a.model || ''} · ${ago(a.startedAt)}`), progress(null)))))
          : h('div.empty', {}, 'Nothing running.')),
      ...(done.length ? [h('div.panel', {}, h('h3', {}, 'Recently finished'), h('div.list', {}, done.map(row)))] : []));
  }
  await draw();
  const offs = [api.on('tasks.changed', () => draw()), api.on('ai.task', () => draw())];
  const t = setInterval(() => { if (!document.hidden) draw(); }, 4000);
  return () => { offs.forEach((o) => o()); clearInterval(t); };
}
