import { h, clear, icon, btn, toast, toastError, select } from '../ui.js';
import { modelTable } from '../components/model-table.js';

// INTELLIGENCE → AI Configuration: which installed model does which job. The Code Agent uses the
// coding roles; empty means "automatic" (the best installed model that fits in memory).
const ROLES = [
  ['chat', 'Chat & assistant', 'Conversations, voice and tools.'],
  ['code', 'Code generation', 'Writes files for the Code Agent and Code Studio.'],
  ['planning', 'Planning', 'Breaks a request into a plan. Empty = the code model.'],
  ['debug', 'Debugging', 'Reads build/test failures and writes fixes. Empty = the code model.'],
  ['code_review', 'Code review', 'Reviews changes before they are reported. Empty = the code model.'],
  ['vision', 'Vision', 'Live Vision and image questions.'],
  ['embeddings', 'Embeddings', 'Knowledge Base and memory search.'],
];
export async function render(view, { app, api }) {
  const body = h('div'); const table = h('div.panel', { style: { marginTop: '14px' } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'AI Configuration'), h('div.sub', {}, 'Assign installed models to each job. Using one model for several roles saves memory.')),
    h('div.actions', {}, btn('Model Manager', () => app.go('models'), { cls: 'sm ghost', ico: 'models' }), btn('Benchmark', () => app.go('benchmark'), { cls: 'sm ghost', ico: 'gauge' }))), body, table);
  const [models, perf] = await Promise.all([api.get('/models?refresh=1').catch(() => []), api.get('/models/perf').catch(() => [])]);
  async function draw() {
    const roles = (await api.get('/settings/models').catch(() => app.settings.models)) || {};
    clear(body).append(h('div.panel', {}, h('h3', {}, icon('sparkle'), 'Model roles'), h('div.list', {}, ROLES.map(([id, label, desc]) => {
      const cur = roles[id] || {};
      const opts = [['', 'Automatic'], ...models.filter((m) => (id === 'embeddings' ? (m.capabilities || []).includes('embeddings') : id === 'vision' ? (m.capabilities || []).includes('vision') : !(m.capabilities || []).includes('embeddings'))).map((m) => [`${m.backend}|${m.name}`, `${m.name} (${m.backend})`])];
      const val = cur.model ? `${cur.backend}|${cur.model}` : '';
      if (val && !opts.some(([v]) => v === val)) opts.push([val, `${cur.model} (not installed)`]);
      return h('div.li', {}, h('div.t', {}, h('b', {}, label), h('small', {}, desc)), select(opts, val, async (v) => {
        const [backend, model] = v ? v.split('|') : ['', ''];
        try { app.settings.models = await api.post('/models/role', { role: id, backend, model }); toast('Saved', `${label}: ${model || 'automatic'}`); } catch (e) { toastError(e); }
      }));
    }))));
    clear(table).append(h('h3', {}, 'What each installed model can do'), modelTable(models, perf, app),
      h('p.small.mist', {}, 'Memory needed is an estimate (model weights plus working memory). “Fits well” leaves room for Windows and your other apps.'));
  }
  await draw();
}
