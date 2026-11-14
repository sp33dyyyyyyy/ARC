import { h, icon, clear, toast, toastError, btn, busy, bytes, field, select, ask, progress } from '../ui.js';

const BE = { foundry: 'Microsoft Foundry Local', ollama: 'Ollama', openai: 'OpenAI-compatible server' };
const ROLES = [['chat', 'General chat'], ['code', 'Coding'], ['vision', 'Vision'], ['embeddings', 'Embeddings']];

export async function render(view, { app, api }) {
  let hw = null; let rec = null; let installed = []; let perf = []; let catalog = null; let catBackend = app.settings.backend.active;
  const head = h('div.view-head', {}, h('div', {}, h('h1', {}, 'Models'), h('div.sub', {}, 'Local AI engines and the models VIPER runs on this PC. Nothing here uses a cloud service.')),
    h('div.actions', {}, btn('Refresh', () => load(true), { ico: 'refresh' })));
  const backends = h('div.grid.g3'); const hwBox = h('div.panel'); const roles = h('div.panel'); const inst = h('div.panel'); const cat = h('div.panel'); const dl = h('div');
  view.append(head, backends, h('div.grid.g2', { style: { marginTop: '14px' } }, hwBox, roles), dl, h('div', { style: { marginTop: '14px' } }, inst), h('div', { style: { marginTop: '14px' } }, cat));

  async function load(force) {
    try {
      [hw, rec, installed, perf] = await Promise.all([api.get('/hardware'), api.get('/recommendation'), api.get(`/models${force ? '?refresh=1' : ''}`), api.get('/models/perf')]);
      app.health = await api.post('/models/health');
    } catch (e) { toastError(e); }
    drawBackends(); drawHw(); drawRoles(); drawInstalled(); loadCatalog(); drawDownloads();
  }
  function drawBackends() {
    clear(backends);
    for (const id of ['foundry', 'ollama', 'openai']) {
      const hl = app.health[id] || {}; const active = app.settings.backend.active === id;
      const cfg = app.settings.backend[id];
      const urlInput = h('input.input', { value: id === 'foundry' ? cfg.url : cfg.url, placeholder: id === 'foundry' ? 'Auto-detect (foundry service status)' : '', 'aria-label': `${BE[id]} URL` });
      backends.append(h('div.panel', { style: active ? { borderColor: 'var(--line-hot)' } : {} },
        h('h3', {}, h(`span.dot${hl.ok ? '.on' : ''}`), BE[id], active ? h('span.r.tag.on', {}, 'Active') : null),
        h('p.small.mist', {}, hl.ok ? `Connected${hl.version ? ` · v${hl.version}` : ''}${hl.url ? ` · ${hl.url}` : ''}` : (hl.error || 'Not reachable')),
        id === 'foundry' ? h('p.small.mist', {}, 'Windows 11 recommended. Hardware-optimised ONNX models with CPU, GPU and NPU acceleration.') : id === 'ollama' ? h('p.small.mist', {}, 'Works on Windows 10 and 11. Large GGUF model library, vision and embeddings.') : h('p.small.mist', {}, 'Any local server with an OpenAI-style API (llama.cpp server, LM Studio).'),
        field('Endpoint', urlInput),
        h('div.row.wrap', { style: { marginTop: '10px' } },
          btn('Save', async () => { app.settings.backend = await api.patch('/settings/backend', { [id]: { url: urlInput.value.trim() } }); load(); }, { cls: 'sm' }),
          btn('Test', async (e) => busy(e.currentTarget, async () => { const r = await api.post('/backend/test', { backend: id }); r.ok ? toast(`${BE[id]} works`, `${r.model} replied "${r.reply}" in ${r.ms} ms`) : toast(`${BE[id]} test failed`, r.error || 'Not reachable', 'warn'); }), { cls: 'sm' }),
          !active ? btn('Use this engine', async () => { await api.post('/backend/active', { backend: id }); app.settings.backend.active = id; catBackend = id; load(); }, { cls: 'sm primary' }) : null,
          id === 'foundry' && !hl.ok ? btn('Start service', async (e) => busy(e.currentTarget, async () => { try { await api.post('/backend/foundry/start'); toast('Foundry Local started'); load(); } catch (err) { toastError(err, 'Could not start Foundry Local'); } }), { cls: 'sm' }) : null,
          id === 'foundry' && !hl.ok && hl.cliInstalled === false ? btn('Install Foundry Local', () => installEngine('foundry'), { cls: 'sm' }) : null,
          id === 'ollama' && !hl.ok ? btn('Install Ollama', () => installEngine('ollama'), { cls: 'sm' }) : null)));
    }
  }
  async function installEngine(id) {
    try { const r = await api.post(`/backend/${id}/install`); toast(r.started ? 'Installer started' : 'Opening download page', r.message || ''); } catch (e) { toastError(e); }
  }
  function drawHw() {
    if (!hw) return;
    clear(hwBox).append(h('h3', {}, icon('control'), 'Detected hardware', h('span.r', {}, hw.windows11 ? 'Windows 11' : hw.os)),
      h('dl.kv', {}, h('dt', {}, 'Processor'), h('dd', { title: hw.cpu.model }, `${hw.cpu.model} (${hw.cpu.cores} threads)`), h('dt', {}, 'Memory'), h('dd', {}, `${hw.ramGB} GB`),
        h('dt', {}, 'Graphics'), h('dd', {}, hw.gpu ? `${hw.gpu.model}${hw.gpu.vramGB ? ` · ${hw.gpu.vramGB} GB VRAM` : ` · ${hw.gpu.note || 'shared memory'}`}` : 'Not detected')),
      rec ? h('div', { style: { marginTop: '10px' } }, h('b', {}, `Recommended (${rec.tier} tier): `), `chat ${rec.chat}, coding ${rec.code}, vision ${rec.vision}, embeddings ${rec.embeddings}`,
        h('p.small.mist', { style: { marginTop: '4px' } }, `Expected speed: ${rec.expectedSpeed} — an estimate, measured speed appears below after you chat.`),
        ...rec.notes.map((n) => h('p.small', {}, n)),
        btn('Apply recommended setup', async (e) => busy(e.currentTarget, async () => {
          const be = app.settings.backend.active;
          for (const m of [rec.chat, rec.code, be === 'ollama' ? rec.vision : null, be === 'ollama' ? rec.embeddings : null].filter(Boolean)) if (!installed.some((x) => x.id.startsWith(m))) await api.post('/models/pull', { backend: be === 'foundry' && [rec.vision, rec.embeddings].includes(m) ? 'ollama' : be, model: m });
          toast('Downloading recommended models', 'Progress is shown below. Roles are assigned automatically once installed.');
          app.autoAssign = rec; drawDownloads();
        }), { cls: 'sm primary' })) : null);
  }
  function drawRoles() {
    clear(roles).append(h('h3', {}, icon('models'), 'Model per task'), h('p.small.mist', {}, 'Only one model is loaded at a time per request; others are unloaded by the engine when idle.'));
    const opts = (role) => [['', role === 'chat' ? 'Auto (first installed)' : role === 'code' ? 'Same as chat' : 'Auto-detect'], ...installed.filter((m) => role === 'embeddings' ? m.capabilities?.includes('embeddings') : role === 'vision' ? m.capabilities?.includes('vision') : m.capabilities?.includes('chat')).map((m) => [JSON.stringify({ backend: m.backend, model: m.id }), `${m.id} · ${m.backend}`])];
    for (const [role, label] of ROLES) {
      const cur = app.settings.models[role];
      const val = cur.model ? JSON.stringify({ backend: cur.backend || app.settings.backend.active, model: cur.model }) : '';
      roles.append(h('div.row', { style: { margin: '6px 0' } }, h('span', { style: { width: '110px' } }, label), h('div.grow', {}, select(opts(role), val, async (v) => {
        const p = v ? JSON.parse(v) : { backend: '', model: '' };
        app.settings.models = await api.post('/models/role', { role, ...p }); toast(`${label} model updated`, p.model || 'automatic');
      }))));
    }
    roles.append(h('p.small.mist', {}, 'Speech recognition, voices and image models are managed in Voice and Image Studio.'));
  }
  function perfFor(m) { return perf.find((p) => p.backend === m.backend && p.model === m.id); }
  function drawInstalled() {
    clear(inst).append(h('h3', {}, 'Installed models', h('span.r', {}, `${installed.length}`)));
    if (!installed.length) { inst.append(h('div.empty', {}, h('b', {}, 'No models installed'), 'Download one from the catalogue below — the recommended model is a good start.')); return; }
    const tbl = h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Model', 'Engine', 'Size', 'Capabilities', 'Status', 'Measured speed', ''].map((t) => h('th', {}, t)))));
    const tb = h('tbody');
    for (const m of installed) {
      const p = perfFor(m);
      tb.append(h('tr', {},
        h('td', {}, h('b', { style: { fontWeight: 400 } }, m.id), m.family ? h('small.mist', { style: { display: 'block' } }, `${m.family}${m.parameterSize ? ` · ${m.parameterSize}` : ''}${m.quantization ? ` · ${m.quantization}` : ''}`) : null),
        h('td', {}, m.backend), h('td', {}, bytes(m.sizeBytes)),
        h('td', {}, (m.capabilities || []).map((c) => h('span.tag', { style: { marginRight: '4px' } }, c))),
        h('td', {}, m.loaded ? h('span.tag.on', {}, 'Loaded') : h('span.mist', {}, 'Idle')),
        h('td', {}, p ? `${p.avg_tps} tok/s · ${p.avg_ttft} ms first token${p.failures ? ` · ${p.failures} failures` : ''}` : h('span.mist', {}, 'Not measured')),
        h('td', { style: { whiteSpace: 'nowrap' } },
          m.capabilities?.includes('chat') ? btn('', async (e) => busy(e.currentTarget, async () => { const r = await api.post('/models/benchmark', { backend: m.backend, model: m.id }); toast(`${m.id}: ${r.tokPerS} tok/s`, `First token ${r.ttftMs} ms · total ${r.ms} ms`); load(); }), { cls: 'sm ghost icon', ico: 'play', title: 'Benchmark' }) : null,
          btn('', async (e) => busy(e.currentTarget, async () => { await api.post(m.loaded ? '/models/unload' : '/models/load', { backend: m.backend, model: m.id }); load(true); }), { cls: 'sm ghost icon', ico: m.loaded ? 'pause' : 'upload', title: m.loaded ? 'Unload from memory' : 'Load into memory' }),
          btn('', async () => { if (await ask(`Remove ${m.id}?`, 'The model files will be deleted from disk. You can download it again later.', { confirmLabel: 'Remove', danger: true })) { await api.post('/models/remove', { backend: m.backend, model: m.id }).catch(toastError); load(true); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Remove' }))));
    }
    tbl.append(tb); inst.append(h('div', { style: { overflowX: 'auto' } }, tbl));
  }
  async function loadCatalog() {
    clear(cat).append(h('h3', {}, 'Download models', h('span.r', {}, h('div.seg', {}, ...['ollama', 'foundry'].map((b) => h(`button${catBackend === b ? '.on' : ''}`, { onclick: () => { catBackend = b; loadCatalog(); } }, BE[b]))))), progress(null));
    try { catalog = await api.get(`/models/catalog?backend=${catBackend}`); } catch (e) { catalog = { recommended: [], live: [] }; toastError(e); }
    clear(cat).append(h('h3', {}, 'Download models', h('span.r', {}, h('div.seg', {}, ...['ollama', 'foundry'].map((b) => h(`button${catBackend === b ? '.on' : ''}`, { onclick: () => { catBackend = b; loadCatalog(); } }, BE[b]))))));
    if (!app.health[catBackend]?.ok) cat.append(h('p.small', {}, `${BE[catBackend]} is not running, so downloads are unavailable until it starts.`));
    const ram = hw?.ramGB || 8;
    const tbl = h('table.tbl', {}, h('thead', {}, h('tr', {}, ['Model', 'Size', 'Needs', 'Good for', 'Fit on this PC', ''].map((t) => h('th', {}, t)))));
    const tb = h('tbody');
    for (const m of catalog.recommended) {
      const fit = m.minRamGB <= ram * 0.6 ? 'Comfortable' : m.minRamGB <= ram ? 'Tight — close other apps' : 'Too large for this PC';
      tb.append(h('tr', {}, h('td', {}, h('b', { style: { fontWeight: 400 } }, m.id), h('small.mist', { style: { display: 'block' } }, `${m.family} ${m.params} — ${m.note}`)),
        h('td', {}, `${m.sizeGB} GB`), h('td', {}, `${m.minRamGB} GB RAM`), h('td', {}, m.roles.join(', ')),
        h('td', {}, m.minRamGB > ram ? h('span.badge-inv', {}, fit) : fit),
        h('td', {}, m.installed ? h('span.tag.on', {}, 'Installed') : btn('Download', async () => { await api.post('/models/pull', { backend: catBackend, model: m.id }).then(drawDownloads).catch(toastError); }, { cls: 'sm', ico: 'download', disabled: !app.health[catBackend]?.ok }))));
    }
    tbl.append(tb); cat.append(h('div', { style: { overflowX: 'auto' } }, tbl));
    if (catalog.live?.length) {
      cat.append(h('h3', { style: { marginTop: '16px' } }, 'Full Foundry Local catalogue'));
      const l = h('div.list');
      for (const m of catalog.live) l.append(h('div.li', {}, h('div.t', {}, h('b', {}, m.displayName || m.id), h('small', {}, `${m.id} · ${m.device || ''} · ${bytes(m.sizeBytes)}${m.supportsTools ? ' · tool calling' : ''}`)), m.installed ? h('span.tag.on', {}, 'Installed') : btn('Download', () => api.post('/models/pull', { backend: 'foundry', model: m.id }).then(drawDownloads).catch(toastError), { cls: 'sm' })));
      cat.append(l);
    }
    const custom = h('input.input', { placeholder: catBackend === 'ollama' ? 'Any Ollama model tag, e.g. mistral:7b' : 'Foundry model alias, e.g. phi-4-mini' });
    cat.append(h('div.row', { style: { marginTop: '12px' } }, h('div.grow', {}, custom), btn('Download', () => custom.value.trim() && api.post('/models/pull', { backend: catBackend, model: custom.value.trim() }).then(drawDownloads).catch(toastError), { ico: 'download' })));
  }
  async function drawDownloads() {
    const list = await api.get('/models/downloads').catch(() => []);
    clear(dl);
    const act = list.filter((d) => d.status === 'downloading' || Date.now() - d.startedAt < 600000);
    if (!act.length) return;
    const p = h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Downloads'));
    for (const d of act) {
      p.append(h('div.li', { style: { display: 'block', padding: '6px 0' } },
        h('div.row', {}, h('span.grow', {}, `${d.model} · ${d.backend}`), h('small.mist', {}, d.status === 'downloading' ? `${d.detail || ''} ${d.total ? `${bytes(d.completed)} / ${bytes(d.total)}` : ''}` : d.status === 'error' ? d.error : d.status),
          d.status === 'downloading' ? btn('Cancel', () => api.post('/models/cancel', { id: d.id }), { cls: 'sm ghost' }) : null),
        d.status === 'downloading' ? progress(d.total ? d.completed / d.total : null) : null));
    }
    dl.append(p);
  }
  const off = api.on('models.download', async (d) => {
    drawDownloads();
    if (d.status === 'done') {
      toast('Model installed', `${d.model} is ready.`);
      installed = await api.get('/models?refresh=1').catch(() => installed);
      const rr = app.autoAssign;
      if (rr) for (const [role, id] of [['chat', rr.chat], ['code', rr.code], ['vision', rr.vision], ['embeddings', rr.embeddings]]) if (id && d.model.startsWith(id) && !app.settings.models[role].model) app.settings.models = await api.post('/models/role', { role, backend: d.backend, model: installed.find((m) => m.id.startsWith(id))?.id || d.model });
      drawInstalled(); drawRoles(); loadCatalog();
    }
    if (d.status === 'error') toast('Download failed', `${d.model}: ${d.error}`, 'error');
  });
  load();
  return off;
}
