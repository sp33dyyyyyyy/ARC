import { h, clear, icon, bytes, meter, btn, when } from '../ui.js';

function chart(series, { max = 100, labels = [] } = {}) {
  const w = 600; const hh = 150;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${w} ${hh}`); svg.setAttribute('preserveAspectRatio', 'none'); svg.setAttribute('class', 'chart'); svg.setAttribute('role', 'img');
  let inner = '';
  for (const g of [0.25, 0.5, 0.75]) inner += `<line x1="0" x2="${w}" y1="${hh * g}" y2="${hh * g}" stroke="white" stroke-opacity=".08"/>`;
  series.forEach((s, si) => {
    const n = Math.max(2, s.data.length);
    const pts = s.data.map((v, i) => `${(i / (n - 1)) * w},${hh - (Math.max(0, Math.min(max, v ?? 0)) / max) * (hh - 4) - 2}`).join(' ');
    inner += `<polyline points="${pts}" fill="none" stroke="white" stroke-opacity="${si === 0 ? 0.9 : 0.45}" stroke-width="1.2" ${si ? 'stroke-dasharray="4 3"' : ''} vector-effect="non-scaling-stroke"/>`;
  });
  svg.innerHTML = inner;
  svg.setAttribute('aria-label', labels.join(', '));
  return svg;
}

export async function render(view, { app, api }) {
  let range = 'live'; let hist = [];
  const top = h('div.grid.g4'); const charts = h('div.grid.g2', { style: { marginTop: '14px' } }); const lower = h('div.grid.g2', { style: { marginTop: '14px' } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'System Intelligence'), h('div.sub', {}, 'Live readings from this PC. Sensors the hardware does not expose are shown as unavailable, never estimated.')),
    h('div.actions', {}, h('div.seg', {}, ...[['live', 'Last 30 min'], ['day', 'Last 24 h']].map(([v, l]) => h(`button${range === v ? '.on' : ''}`, { onclick: async (e) => { range = v; e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === e.currentTarget)); await loadHist(); draw(); } }, l))), btn('Run diagnostic', () => app.send('Run a system diagnostic').then(() => app.go('home')), { cls: 'sm' }))),
  top, charts, lower);
  async function loadHist() { hist = await api.get(`/system/history${range === 'day' ? '?range=day' : ''}`).catch(() => []); }
  let perf = []; let loaded = []; let procs = [];
  async function slow() { [perf, loaded, procs] = await Promise.all([api.get('/models/perf').catch(() => []), api.get('/models/loaded').catch(() => []), api.get('/system/processes?limit=12').catch(() => [])]); draw(); }
  function stat(label, value, sub, pct) { return h('div.panel', {}, h('div.stat', {}, h('b', {}, value), h('span', {}, label)), pct != null ? meter(pct, pct > 90) : null, sub ? h('small.mist', {}, sub) : null); }
  function draw() {
    const s = app.sample || {};
    clear(top).append(
      stat('CPU', s.cpu ? `${Math.round(s.cpu.pct)}%` : '—', s.static?.cpuModel || `${s.cpu?.perCore?.length || ''} cores`, s.cpu?.pct),
      stat('Memory', s.mem ? `${Math.round(s.mem.pct)}%` : '—', s.mem ? `${bytes(s.mem.used)} of ${bytes(s.mem.total)}` : '', s.mem?.pct),
      stat('GPU', s.gpu?.pct != null ? `${Math.round(s.gpu.pct)}%` : 'n/a', s.gpu ? `${s.gpu.model}${s.gpu.memUsed != null ? ` · ${bytes(s.gpu.memUsed)} / ${bytes(s.gpu.memTotal)}` : ''}` : 'Utilisation not reported by this GPU/driver', s.gpu?.pct),
      stat('CPU temperature', s.temp?.cpu ? `${Math.round(s.temp.cpu)}°C` : 'n/a', s.temp?.cpu ? (s.gpu?.temp ? `GPU ${s.gpu.temp}°C` : '') : 'Not exposed by this PC', null));
    const label = (t) => new Date(t).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const span = hist.length ? `${label(hist[0].t)} – ${label(hist[hist.length - 1].t)}` : '';
    clear(charts).append(
      h('div.panel', {}, h('h3', {}, 'CPU and memory', h('span.r', {}, span)), chart([{ data: hist.map((x) => x.cpu) }, { data: hist.map((x) => x.mem) }], { labels: ['CPU solid', 'memory dashed'] }), h('small.mist', {}, 'Solid: CPU · Dashed: memory')),
      h('div.panel', {}, h('h3', {}, 'Network', h('span.r', {}, s.net ? `↓ ${bytes(s.net.rxPerSec)}/s · ↑ ${bytes(s.net.txPerSec)}/s` : '')), range === 'live' ? chart([{ data: hist.map((x) => x.rx) }, { data: hist.map((x) => x.tx) }], { max: Math.max(1024, ...hist.map((x) => Math.max(x.rx || 0, x.tx || 0))) }) : h('p.small.mist', {}, 'Network history is kept for the last 30 minutes.'), h('small.mist', {}, s.online ? 'Internet reachable' : 'Offline')));
    clear(lower).append(
      h('div.panel', {}, h('h3', {}, icon('files'), 'Storage'), ...(s.disks || []).map((d) => h('div', { style: { marginBottom: '10px' } }, h('div.row', {}, h('span.grow', {}, `${d.mount} (${d.fs})`), h('small.mist', {}, `${bytes(d.size - d.used)} free of ${bytes(d.size)}`)), meter(d.pct, d.pct > 90))),
        s.battery ? h('div', { style: { marginTop: '10px' } }, h('div.row', {}, h('span.grow', {}, 'Battery'), h('small.mist', {}, `${s.battery.pct}%${s.battery.charging ? ' · charging' : ''}${s.battery.timeRemaining ? ` · ${s.battery.timeRemaining} min left` : ''}`)), meter(s.battery.pct)) : h('small.mist', {}, 'No battery detected.')),
      h('div.panel', {}, h('h3', {}, icon('models'), 'AI resources'),
        h('dl.kv', {}, h('dt', {}, 'VIPER process memory'), h('dd', {}, bytes(s.process?.rss)), h('dt', {}, 'Models in memory'), h('dd', {}, loaded.length ? loaded.map((m) => `${m.name}${m.sizeBytes ? ` (${bytes(m.sizeBytes)}${m.vramBytes ? `, ${bytes(m.vramBytes)} VRAM` : ''})` : ''}`).join(', ') : 'none loaded'),
          h('dt', {}, 'Current AI tasks'), h('dd', {}, app.aiTasks.size ? [...app.aiTasks.values()].map((t) => t.label).join(', ') : 'idle')),
        perf.length ? h('table.tbl', { style: { marginTop: '8px' } }, h('thead', {}, h('tr', {}, ['Model', 'Avg speed', 'First token', 'Runs'].map((t) => h('th', {}, t)))), h('tbody', {}, perf.slice(0, 6).map((p) => h('tr', {}, h('td', {}, p.model), h('td', {}, (p.avg_tps ? `${p.avg_tps} tok/s` : '—')), h('td', {}, (p.avg_ttft != null ? `${p.avg_ttft} ms` : '—')), h('td', {}, String(p.runs)))))) : h('small.mist', {}, 'Inference speed appears after your first conversation.')),
      h('div.panel', { style: { gridColumn: '1 / -1' } }, h('h3', {}, icon('system'), 'Heaviest processes'), h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Process', 'CPU', 'Memory', 'PID'].map((t) => h('th', {}, t)))), h('tbody', {}, procs.map((p) => h('tr', {}, h('td', {}, p.name), h('td', {}, `${p.cpu}%`), h('td', {}, bytes(p.memBytes)), h('td', {}, String(p.pid))))))));
  }
  await loadHist(); slow();
  const off = api.on('system.sample', (s) => { if (range === 'live') { hist.push({ t: s.t, cpu: s.cpu?.pct, mem: s.mem?.pct, rx: s.net?.rxPerSec, tx: s.net?.txPerSec }); if (hist.length > 900) hist.shift(); } if (!document.hidden) draw(); });
  const t = setInterval(slow, 10000);
  return () => { off(); clearInterval(t); };
}
