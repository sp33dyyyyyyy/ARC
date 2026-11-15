// AI start-up status: the real stages of VIPER's automatic AI start-up (see server
// llm/startup.js), with Retry on failure and install / download actions when something is missing.
import { h, clear, btn, busy, toastError, bytes } from '../ui.js';

const SHORT = { init: 'Init', engine: 'Engine', starting: 'Backend', model: 'Model', verify: 'Verify', ready: 'Ready' };

export function aiStatus(app, { compact = false } = {}) {
  const el = h(`div.ai-status${compact ? '.compact' : ''}`, { role: 'status', 'aria-live': 'polite' });
  let progress = null;
  const draw = () => {
    const s = app.ai || { stage: 'idle', label: 'STANDING BY', steps: [] };
    el.dataset.stage = s.stage;
    const head = h('div.ai-head', {}, h('span.ai-dot'), h('b.ai-label', {}, s.label), s.model && s.stage !== 'setup' ? h('small.mist', {}, s.model) : null);
    const steps = compact || !s.steps?.length ? null : h('div.ai-steps', {}, s.steps.map((st) => h(`div.ai-step.${st.state}`, { title: st.label }, h('i'), h('span', {}, SHORT[st.id]))));
    const detail = s.detail ? h('div.ai-detail', {}, s.detail) : null;
    const actions = h('div.row.wrap.ai-actions');
    if (s.stage === 'error') {
      actions.append(btn('Retry connection', async (e) => busy(e.currentTarget, () => app.api.post('/ai/startup/retry')), { cls: 'sm primary', ico: 'refresh' }), btn('Open Models', () => app.go('models'), { cls: 'sm' }));
    } else if (s.stage === 'setup' && s.need === 'engine') {
      if (s.canInstall && s.engine === 'ollama') actions.append(btn('Install Ollama (≈1 GB)', async (e) => busy(e.currentTarget, async () => { try { await app.api.post('/backend/ollama/install'); } catch (err) { toastError(err); } }), { cls: 'sm primary', ico: 'download' }));
      else actions.append(btn(s.engine === 'foundry' ? 'Install Foundry Local' : 'Get Ollama', async () => { try { const r = await app.api.post(`/backend/${s.engine || 'ollama'}/install`); if (r?.message) toastError(new Error(r.message), 'Install'); } catch (err) { toastError(err); } }, { cls: 'sm primary', ico: 'download' }));
      actions.append(btn('Retry', async (e) => busy(e.currentTarget, () => app.api.post('/ai/startup/retry')), { cls: 'sm' }), btn('Choose engine', () => app.go('models'), { cls: 'sm ghost' }));
    } else if (s.stage === 'setup' && s.need === 'model') {
      if (s.recommended) actions.append(btn(`Download ${s.recommended}${s.recommendedSizeGB ? ` (${s.recommendedSizeGB} GB)` : ''}`, async (e) => busy(e.currentTarget, async () => { try { await app.api.post('/models/pull', { backend: s.engine || 'ollama', model: s.recommended }); } catch (err) { toastError(err); } }), { cls: 'sm primary', ico: 'download' }));
      actions.append(btn('Choose another model', () => app.go('models'), { cls: 'sm' }));
    }
    const bar = progress ? h('div.ai-progress', {}, h('div.progress', {}, h('i', { style: { width: `${Math.round(progress.pct * 100)}%` } })), h('small.mist', {}, progress.text)) : null;
    clear(el).append(...[head, steps, detail, bar, actions.childElementCount ? actions : null].filter(Boolean));
  };
  const offs = [
    app.api.on('ai.startup', () => { if (app.ai?.stage !== 'setup') progress = null; draw(); }),
    app.api.on('engine.install', (j) => { progress = j.state === 'running' ? { pct: j.total ? j.received / j.total : 0, text: `${j.label}${j.total ? ` · ${bytes(j.received)} of ${bytes(j.total)}` : '…'}` } : null; if (j.state === 'failed') toastError(new Error(j.error), 'Ollama installation failed'); draw(); }),
    app.api.on('models.download', (d) => { if (app.ai?.stage !== 'setup') return; progress = d.status === 'downloading' ? { pct: d.total ? d.completed / d.total : 0, text: `Downloading ${d.model}${d.total ? ` · ${bytes(d.completed)} of ${bytes(d.total)}` : ` · ${d.detail || ''}`}` } : null; if (d.status === 'error') toastError(new Error(d.error), 'Download failed'); draw(); }),
  ];
  draw();
  return { el, draw, destroy: () => offs.forEach((o) => o()) };
}
