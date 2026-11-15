import { h, clear, icon, btn, busy, toastError } from '../ui.js';

// INTELLIGENCE → Model Benchmarking: times each installed model on the same short prompts on
// this PC. The coding test checks whether the answer is valid JavaScript (it is compiled,
// never run). Results are real measurements and are kept with every other reply's speed.
export async function render(view, { app, api }) {
  const results = new Map();
  const body = h('div'); const perfBox = h('div.panel', { style: { marginTop: '14px' } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Model Benchmarking'), h('div.sub', {}, 'Measure how fast each model answers on this PC. Only one model runs at a time.'))), body, perfBox);
  const models = (await api.get('/models').catch(() => [])).filter((m) => !(m.capabilities || []).includes('embeddings'));
  async function bench(m, kind, button) {
    return busy(button, async () => {
      try { const r = await api.post(kind === 'code' ? '/studio/benchmark/code' : '/models/benchmark', { backend: m.backend, model: m.name }); results.set(`${m.name}:${kind}`, r); draw(); loadPerf(); } catch (e) { toastError(e, `${m.name} failed`); }
    });
  }
  function cell(r, kind) {
    if (!r) return h('small.mist', {}, '—');
    const tps = r.tokPerS ?? r.tok_per_s; const ttft = r.ttftMs ?? r.ttft_ms;
    return h('div', {}, h('b', { style: { fontWeight: 500 } }, `${(r.ms / 1000).toFixed(1)} s`), h('small.mist', { style: { display: 'block' } }, [tps ? `${Number(tps).toFixed(1)} tok/s` : null, ttft != null ? `first token ${ttft} ms` : null].filter(Boolean).join(' · ')),
      kind === 'code' ? h('small', { style: { display: 'block' } }, r.syntaxValid && r.definesFunction ? '✓ valid fizzBuzz function' : r.syntaxValid ? '△ valid JS, function not found' : `✕ invalid JS${r.error ? `: ${r.error}` : ''}`) : null);
  }
  function draw() {
    clear(body).append(h('div.panel', {}, h('h3', {}, icon('gauge'), 'Installed models'),
      models.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Model', 'General answer', 'Coding task', ''].map((t) => h('th', {}, t)))),
        h('tbody', {}, models.map((m) => h('tr', {}, h('td', {}, m.name, h('small.mist', { style: { display: 'block' } }, m.backend)), h('td', {}, cell(results.get(`${m.name}:general`))), h('td', {}, cell(results.get(`${m.name}:code`), 'code')),
          h('td', {}, h('div.row', {}, btn('General', (e) => bench(m, 'general', e.currentTarget), { cls: 'sm' }), btn('Coding', (e) => bench(m, 'code', e.currentTarget), { cls: 'sm' })))))))
        : h('div.empty', {}, 'No chat models installed. Download one in the Model Manager.', h('div', { style: { marginTop: '8px' } }, btn('Model Manager', () => app.go('models'), { cls: 'sm' })))));
  }
  async function loadPerf() {
    const rows = await api.get('/models/perf').catch(() => []);
    clear(perfBox).append(h('h3', {}, 'Measured on real replies (last 30 days)'), rows.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Model', 'Replies', 'Avg tokens/s', 'Avg first token', 'Failures'].map((t) => h('th', {}, t)))),
      h('tbody', {}, rows.map((r) => h('tr', {}, h('td', {}, `${r.model} (${r.backend})`), h('td', {}, String(r.runs)), h('td', {}, String(r.avg_tps ?? '—')), h('td', {}, r.avg_ttft != null ? `${r.avg_ttft} ms` : '—'), h('td', {}, String(r.failures)))))) : h('small.mist', {}, 'Nothing measured yet.'));
  }
  draw(); loadPerf();
}
