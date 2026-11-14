import { h, clear, icon, btn, busy, toast, toastError, field, select, progress, readFileAs, ask, when } from '../ui.js';

export async function render(view, { app, api }) {
  const abort = new AbortController(); // removes window listeners when leaving the page
  let status = null; let styles = { styles: [], aspects: [] }; let selected = null; let reference = null;
  const st = { prompt: '', negative: '', style: 'none', aspect: '1:1', resolution: 768, steps: app.settings.image.defaultSteps, cfg: app.settings.image.defaultCfg, count: 1, seed: -1, strength: 0.6 };
  const statusBox = h('div.panel'); const stage = h('div.panel', { style: { minHeight: '360px' } }); const gallery = h('div.imgs'); const prog = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Image Studio'), h('div.sub', {}, 'Generate and edit images with Stable Diffusion running on this PC.'))),
    h('div.split', {}, h('div.col', {}, statusBox, h('div.panel', { id: 'gen' })), h('div.col', {}, prog, stage, h('div.panel', {}, h('h3', {}, 'History'), gallery))));
  try { [status, styles] = await Promise.all([api.get('/image/status'), api.get('/image/styles')]); } catch (e) { status = { ok: false, error: e.message }; }

  function drawStatus() {
    clear(statusBox).append(h('h3', {}, h(`span.dot${status.ok ? '.on' : ''}`), 'Image engine', h('span.r', {}, status.ok ? 'Connected' : 'Not running')),
      status.ok ? h('div', {}, field('Model', select(status.models.map((m) => [m.title, m.name]), status.current, async (v) => { toast('Switching model', 'This can take a minute.'); await api.post('/image/model', { title: v }).catch(toastError); })))
        : h('div', {}, h('p.small', {}, status.error), h('p.small.mist', {}, 'VIPER works with any local engine that offers the AUTOMATIC1111 API: Stable Diffusion WebUI Forge (recommended), AUTOMATIC1111 or SD.Next. Start it with the --api flag, then press Check again.')),
      h('p.small.mist', {}, status.advice || ''),
      h('div.row', {}, field('Engine address', h('input.input', { value: app.settings.image.a1111Url, onchange: async (e) => { app.settings.image = await api.patch('/settings/image', { a1111Url: e.target.value.trim() }); } })), btn('Check again', async (e) => busy(e.currentTarget, async () => { status = await api.get('/image/status'); drawStatus(); }), { cls: 'sm' })));
  }
  function drawGen() {
    const box = view.querySelector('#gen');
    const refEl = h('div');
    const drawRef = () => clear(refEl).append(reference ? h('div.row', {}, h('img', { src: reference, alt: 'Reference', style: { width: '64px', height: '64px', objectFit: 'cover', border: '1px solid var(--line)' } }), h('div.grow', {}, field(`Reference strength (${st.strength})`, h('input', { type: 'range', min: 0.1, max: 0.95, step: 0.05, value: st.strength, oninput: (e) => { st.strength = Number(e.target.value); } }))), btn('', () => { reference = null; drawRef(); }, { cls: 'sm ghost icon', ico: 'x', title: 'Remove reference' })) : btn('Add reference image', () => refIn.click(), { cls: 'sm', ico: 'upload' }));
    const refIn = h('input', { type: 'file', accept: 'image/*', style: { display: 'none' }, onchange: async (e) => { reference = await readFileAs(e.target.files[0]); drawRef(); } });
    drawRef();
    clear(box).append(h('h3', {}, 'Generate'),
      h('div.col', {},
        field('Prompt', h('textarea.input', { rows: 4, placeholder: 'A minimalist black and white control room with glowing holographic displays', oninput: (e) => { st.prompt = e.target.value; } }, st.prompt)),
        field('Avoid (negative prompt)', h('input.input', { value: st.negative, oninput: (e) => { st.negative = e.target.value; } })),
        h('div.grid.g2', {},
          field('Style', select(styles.styles.map((s) => [s.id, s.label]), st.style, (v) => { st.style = v; })),
          field('Aspect ratio', select(styles.aspects.map((a) => [a, a]), st.aspect, (v) => { st.aspect = v; })),
          field('Resolution', select([['512', '512 (fast, SD 1.5)'], ['768', '768'], ['1024', '1024 (SDXL)']], String(st.resolution), (v) => { st.resolution = Number(v); })),
          field('Images', select([['1', '1'], ['2', '2'], ['4', '4']], String(st.count), (v) => { st.count = Number(v); })),
          field('Steps', h('input.input', { type: 'number', min: 1, max: 150, value: st.steps, onchange: (e) => { st.steps = Number(e.target.value); } })),
          field('Guidance (CFG)', h('input.input', { type: 'number', min: 1, max: 30, step: 0.5, value: st.cfg, onchange: (e) => { st.cfg = Number(e.target.value); } }))),
        field('Seed (-1 = random)', h('input.input', { type: 'number', value: st.seed, onchange: (e) => { st.seed = Number(e.target.value); } })),
        refEl, refIn,
        h('div.row', {}, btn('Generate', (e) => busy(e.currentTarget, generate), { cls: 'primary grow', ico: 'sparkle', disabled: !status.ok }), btn('Stop', () => api.post('/image/interrupt'), { cls: 'sm' }))));
  }
  async function generate() {
    if (!st.prompt.trim()) { toast('Write a prompt first'); return; }
    try { const imgs = await api.post('/image/generate', { ...st, reference }); if (imgs[0]) select_(imgs[0]); loadHistory(); } catch (e) { toastError(e, 'Generation failed'); }
    clear(prog);
  }
  function src(img) { return api.url(img.url); }
  function select_(img) {
    selected = img;
    const parent = img.parent_id ? { url: `/images/${img.parent_id}/file` } : null;
    const view_ = parent ? compareView(src(parent), src(img)) : h('img', { src: src(img), alt: img.prompt || 'Generated image', style: { maxWidth: '100%', maxHeight: '58vh', display: 'block', margin: '0 auto' } });
    clear(stage).append(h('h3', {}, img.kind, h('span.r', {}, when(img.created_at || Date.now()))), view_, img.prompt ? h('p.small.mist', { style: { marginTop: '6px' } }, img.prompt) : null,
      h('div.row.wrap', { style: { marginTop: '10px' } },
        btn('Variations', (e) => busy(e.currentTarget, async () => { await act('/image/variations', { imageId: img.id, count: 3 }); }), { cls: 'sm', disabled: !status.ok }),
        btn('Edit with prompt', () => editDialog(img, false), { cls: 'sm', disabled: !status.ok }),
        btn('Inpaint area', () => editDialog(img, true), { cls: 'sm', disabled: !status.ok }),
        btn('Upscale ×2', (e) => busy(e.currentTarget, async () => { status.ok && status.upscalers?.length ? await act('/image/upscale', { imageId: img.id, scale: 2, upscaler: status.upscalers.find((u) => /ESRGAN/i.test(u)) || status.upscalers[0] }) : await localUpscale(img); }), { cls: 'sm' }),
        btn('Remove background', (e) => busy(e.currentTarget, async () => { if (!status.rembg) { toast('Background removal unavailable', 'Install the rembg extension in your Stable Diffusion WebUI; VIPER uses its /rembg API.', 'warn'); return; } await act('/image/remove-background', { imageId: img.id }); }), { cls: 'sm' }),
        h('a.btn.sm', { href: src(img), download: `viper-${img.id}.png` }, icon('download'), 'Save'),
        btn('Use as reference', () => { fetch(src(img)).then((r) => r.blob()).then((b) => readFileAs(b)).then((d) => { reference = d; drawGen(); }); }, { cls: 'sm' }),
        btn('', async () => { if (await ask('Delete image?', 'It will be removed from history and disk.', { danger: true, confirmLabel: 'Delete' })) { await api.del(`/image/history/${img.id}`); clear(stage); loadHistory(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' })));
  }
  async function act(path, body) { try { const r = await api.post(path, body); if (r[0]) select_(r[0]); loadHistory(); } catch (e) { toastError(e); } }
  async function localUpscale(img) {
    // Fallback when no AI upscaler is installed: high-quality canvas resampling (not AI super-resolution).
    const im = new Image(); im.src = src(img); await im.decode();
    const c = document.createElement('canvas'); c.width = im.naturalWidth * 2; c.height = im.naturalHeight * 2;
    const g = c.getContext('2d'); g.imageSmoothingQuality = 'high'; g.drawImage(im, 0, 0, c.width, c.height);
    const r = await api.post('/image/import', { data: c.toDataURL('image/png'), kind: 'resize', parentId: img.id, prompt: img.prompt });
    toast('Resized ×2', 'No AI upscaler found, so a standard high-quality resize was used.');
    select_(r); loadHistory();
  }
  function compareView(a, b) {
    const after = h('div.after', {}, h('img', { src: b, alt: 'After' }));
    const handle = h('div.handle', { style: { left: '50%' } });
    const wrap = h('div.compare', {}, h('img', { src: a, alt: 'Before' }), after, handle);
    const set = (x) => { const r = wrap.getBoundingClientRect(); const p = Math.max(0, Math.min(1, (x - r.left) / r.width)); after.style.clipPath = `inset(0 0 0 ${p * 100}%)`; handle.style.left = `${p * 100}%`; };
    after.style.inset = '0'; after.querySelector('img').style.cssText = 'width:100%;height:100%;object-fit:contain'; after.style.clipPath = 'inset(0 0 0 50%)';
    let drag = false; wrap.addEventListener('pointerdown', (e) => { drag = true; set(e.clientX); }); window.addEventListener('pointerup', () => { drag = false; }, { signal: abort.signal }); wrap.addEventListener('pointermove', (e) => drag && set(e.clientX));
    return h('div', {}, wrap, h('small.mist', {}, 'Drag to compare before and after.'));
  }
  function editDialog(img, inpaint) {
    const canvas = h('canvas', { style: { maxWidth: '100%', cursor: inpaint ? 'crosshair' : 'default', border: '1px solid var(--line)' } });
    const promptIn = h('input.input', { placeholder: inpaint ? 'What should appear in the painted area?' : 'Describe the change' });
    let strength = 0.6; const im = new Image(); im.src = src(img);
    let mask = null; let mctx = null;
    im.onload = () => { canvas.width = im.naturalWidth; canvas.height = im.naturalHeight; const g = canvas.getContext('2d'); g.drawImage(im, 0, 0); if (inpaint) { mask = document.createElement('canvas'); mask.width = canvas.width; mask.height = canvas.height; mctx = mask.getContext('2d'); mctx.fillStyle = '#000'; mctx.fillRect(0, 0, mask.width, mask.height); } };
    let painting = false;
    const paint = (e) => { if (!painting || !mctx) return; const r = canvas.getBoundingClientRect(); const x = (e.clientX - r.left) * canvas.width / r.width; const y = (e.clientY - r.top) * canvas.height / r.height; const rad = canvas.width / 24; mctx.fillStyle = '#fff'; mctx.beginPath(); mctx.arc(x, y, rad, 0, 7); mctx.fill(); const g = canvas.getContext('2d'); g.fillStyle = 'rgba(255,255,255,.45)'; g.beginPath(); g.arc(x, y, rad, 0, 7); g.fill(); };
    canvas.addEventListener('pointerdown', (e) => { painting = true; paint(e); }); canvas.addEventListener('pointermove', paint); window.addEventListener('pointerup', () => { painting = false; }, { signal: abort.signal });
    import('../ui.js').then(({ modal }) => modal({ title: inpaint ? 'Inpaint' : 'Edit image', wide: true, body: h('div.col', {}, inpaint ? h('p.small.mist', {}, 'Paint over the area to replace.') : null, canvas, promptIn, field('Change strength', h('input', { type: 'range', min: 0.1, max: 0.95, step: 0.05, value: strength, oninput: (e) => { strength = Number(e.target.value); } }))),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Apply', cls: 'primary', onClick: () => act('/image/edit', { imageId: img.id, prompt: promptIn.value, strength, mask: inpaint ? mask.toDataURL('image/png') : null }) }] }));
  }
  async function loadHistory() {
    const list = await api.get('/image/history').catch(() => []);
    clear(gallery);
    if (!list.length) gallery.append(h('div.empty', { style: { gridColumn: '1 / -1' } }, 'Generated images are saved here and on disk in VIPER\'s data folder.'));
    for (const img of list) gallery.append(h('figure', { onclick: () => select_(img), title: img.prompt || img.kind }, h('img', { src: src(img), alt: img.prompt || img.kind, loading: 'lazy' })));
    if (!selected && list[0]) select_(list[0]);
    else if (!list.length) clear(stage).append(h('div.empty', {}, h('b', {}, 'No images yet'), status.ok ? 'Write a prompt and press Generate.' : 'Start a local Stable Diffusion engine to begin.'));
  }
  const off = api.on('image.progress', (p) => { clear(prog).append(h('div.panel', {}, h('div.row', {}, h('span.grow', {}, `Generating… ${Math.round((p.progress || 0) * 100)}%${p.step ? ` · step ${p.step}/${p.steps}` : ''}`), h('small.mist', {}, p.eta ? `${Math.round(p.eta)} s left` : '')), progress(p.progress || 0), p.preview ? h('img', { src: p.preview, alt: 'Preview', style: { maxHeight: '160px', marginTop: '8px' } }) : null)); });
  drawStatus(); drawGen(); loadHistory();
  return () => { off(); abort.abort(); };
}
