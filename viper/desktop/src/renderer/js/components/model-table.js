import { h, bytes } from '../ui.js';

// Installed models with what they are good for, how much memory they need, whether they fit
// this PC, their context window and measured speed. Shared by Model Manager and AI Configuration.
const CODE_RE = /coder|code|starcoder|codestral|deepseek-coder|codegemma|devstral/i;
export function modelRows(models, perf, app) {
  const totalRam = app.sample?.mem?.total || app.sample?.static?.memTotal || 0;
  return models.map((m) => {
    const caps = new Set(m.capabilities || []);
    if (CODE_RE.test(m.name)) caps.add('code');
    const p = perf.find((x) => x.model === m.name);
    const need = m.sizeBytes ? m.sizeBytes * 1.25 + 0.6e9 : null; // weights + KV cache/runtime headroom
    const fit = !need || !totalRam ? 'unknown' : need < totalRam * 0.45 ? 'good' : need < totalRam * 0.7 ? 'tight' : 'too large';
    return { m, caps: [...caps], p, need, fit };
  });
}
export function modelTable(models, perf, app) {
  const rows = modelRows(models, perf, app);
  if (!rows.length) return h('div.empty.small', {}, 'No models installed yet.');
  return h('div', { style: { overflowX: 'auto' } }, h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Model', 'Good for', 'Memory needed', 'On this PC', 'Context', 'Speed'].map((t) => h('th', {}, t)))),
    h('tbody', {}, rows.map(({ m, caps, p, need, fit }) => h('tr', {},
      h('td', {}, h('b', { style: { fontWeight: 500 } }, m.name), h('small.mist', { style: { display: 'block' } }, [m.backend, m.parameterSize, m.quantization].filter(Boolean).join(' · '))),
      h('td', {}, h('div.chips', {}, caps.map((c) => h(`span.chip${c === 'code' ? '.on' : ''}`, {}, c === 'code' ? 'coding' : c)))),
      h('td', {}, need ? `≈ ${bytes(need)}` : '—'),
      h('td', {}, h(`span.fit.${fit.replace(' ', '-')}`, {}, fit === 'good' ? 'Fits well' : fit === 'tight' ? 'Fits, little headroom' : fit === 'too large' ? 'Too large for RAM' : 'Unknown')),
      h('td', {}, m.contextLength ? `${Math.round(m.contextLength / 1024)}K tokens` : '—'),
      h('td', {}, p?.avg_tps ? `${p.avg_tps} tok/s` : 'not measured'))))));
}
