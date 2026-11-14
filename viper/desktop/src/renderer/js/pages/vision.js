import { h, clear, icon, btn, busy, toast, toastError, mdEl, readFileAs } from '../ui.js';

export async function render(view, { app, api }) {
  let image = null; let stream = null; let liveTimer = null;
  const preview = h('div.compare', { style: { minHeight: '280px', display: 'grid', placeItems: 'center' } }, h('span.mist', {}, 'Drop an image, paste a screenshot, capture your screen or use the camera.'));
  const answer = h('div.panel', { style: { minHeight: '120px' } }, h('span.mist', {}, 'Ask a question about the image.'));
  const q = h('textarea.input', { rows: 3, placeholder: 'e.g. Explain this error and how to fix it', 'aria-label': 'Question' });
  const status = h('small.mist');
  const fileIn = h('input', { type: 'file', accept: 'image/*', style: { display: 'none' }, onchange: async (e) => { if (e.target.files[0]) setImage(await readFileAs(e.target.files[0]), e.target.files[0].name); } });
  const setImage = (dataUrl, label) => { image = dataUrl; clear(preview).append(h('img', { src: dataUrl, alt: label || 'Image to analyse', style: { maxWidth: '100%', maxHeight: '60vh', display: 'block', margin: '0 auto' } }), h('div.scan-line')); };
  let target = null;
  try { target = await api.get('/models'); } catch { target = []; }
  const visionModels = target.filter((m) => m.capabilities?.includes('vision'));
  status.textContent = visionModels.length ? `Vision model: ${app.settings.models.vision.model || visionModels[0].id}` : 'No vision model installed — install one (e.g. moondream or qwen2.5vl:3b) in Models.';

  async function capture() {
    try { const r = await api.post('/vision/capture'); setImage(r.dataUrl, 'Screenshot'); } catch (e) { toast('No screenshot', e.message, 'warn'); }
  }
  async function region() {
    await capture();
    const img = preview.querySelector('img'); if (!img) return;
    toast('Select a region', 'Drag over the screenshot to crop it.');
    const box = h('div', { style: { position: 'absolute', border: '1px solid #fff', boxShadow: '0 0 0 9999px rgba(0,0,0,.5)', pointerEvents: 'none' } });
    preview.style.position = 'relative'; preview.append(box);
    let start = null;
    const rect = () => img.getBoundingClientRect();
    const down = (e) => { start = { x: e.clientX, y: e.clientY }; };
    const move = (e) => { if (!start) return; const pr = preview.getBoundingClientRect(); Object.assign(box.style, { left: `${Math.min(start.x, e.clientX) - pr.left}px`, top: `${Math.min(start.y, e.clientY) - pr.top}px`, width: `${Math.abs(e.clientX - start.x)}px`, height: `${Math.abs(e.clientY - start.y)}px` }); };
    const up = (e) => {
      if (!start) return;
      const r = rect(); const sx = img.naturalWidth / r.width; const sy = img.naturalHeight / r.height;
      const x = (Math.min(start.x, e.clientX) - r.left) * sx; const y = (Math.min(start.y, e.clientY) - r.top) * sy; const w = Math.abs(e.clientX - start.x) * sx; const hh = Math.abs(e.clientY - start.y) * sy;
      start = null; preview.removeEventListener('pointerdown', down); preview.removeEventListener('pointermove', move); preview.removeEventListener('pointerup', up); box.remove();
      if (w < 10 || hh < 10) return;
      const c = document.createElement('canvas'); c.width = w; c.height = hh; c.getContext('2d').drawImage(img, x, y, w, hh, 0, 0, w, hh);
      setImage(c.toDataURL('image/png'), 'Screen region');
    };
    preview.addEventListener('pointerdown', down); preview.addEventListener('pointermove', move); preview.addEventListener('pointerup', up);
  }
  async function camera() {
    if (!app.settings.privacy.cameraEnabled) { toast('Camera is off', 'Enable the camera in Settings → Privacy first.', 'warn'); return; }
    stopCamera();
    try { stream = await navigator.mediaDevices.getUserMedia({ video: true }); } catch (e) { toastError(e, 'Camera unavailable'); return; }
    const vid = h('video', { autoplay: true, muted: true, playsinline: true, style: { maxWidth: '100%', maxHeight: '60vh' } }); vid.srcObject = stream;
    clear(preview).append(vid, h('div.row', { style: { position: 'absolute', bottom: '10px', left: '10px' } }, btn('Capture frame', () => snap(vid), { cls: 'primary sm', ico: 'camera' }), btn('Live assist (every 8 s)', () => toggleLive(vid), { cls: 'sm' }), btn('Stop camera', stopCamera, { cls: 'sm' })));
    preview.style.position = 'relative';
  }
  const snap = (vid) => { const c = document.createElement('canvas'); c.width = vid.videoWidth; c.height = vid.videoHeight; c.getContext('2d').drawImage(vid, 0, 0); image = c.toDataURL('image/jpeg', 0.85); return image; };
  function toggleLive(vid) {
    if (liveTimer) { clearInterval(liveTimer); liveTimer = null; toast('Live assist stopped'); return; }
    toast('Live assist on', 'VIPER describes a new camera frame every 8 seconds until you stop it.');
    const tick = async () => { if (busyAsk) return; snap(vid); await ask(q.value || 'Briefly describe what you see and anything noteworthy.'); };
    tick(); liveTimer = setInterval(tick, 8000);
  }
  function stopCamera() { if (liveTimer) { clearInterval(liveTimer); liveTimer = null; } stream?.getTracks().forEach((t) => t.stop()); stream = null; }
  let busyAsk = false;
  async function ask(question) {
    if (!image) { toast('No image yet', 'Add an image, screenshot or camera frame first.', 'warn'); return; }
    busyAsk = true; clear(answer).append(h('div.progress.indet', {}, h('i')), h('small.mist', {}, 'Analysing…'));
    try {
      const r = await api.post('/vision/analyze', { prompt: question || 'Describe this image in detail.', image });
      clear(answer).append(mdEl(r.text || '(no answer)'), h('small.mist', {}, r.model ? `Answered by ${r.model} on this PC.` : ''));
    } catch (e) { clear(answer).append(h('p', {}, e.message)); }
    busyAsk = false;
  }
  view.addEventListener('paste', async (e) => { const it = [...(e.clipboardData?.items || [])].find((x) => x.type.startsWith('image/')); if (it) setImage(await readFileAs(it.getAsFile()), 'Pasted image'); });
  preview.addEventListener('dragover', (e) => e.preventDefault());
  preview.addEventListener('drop', async (e) => { e.preventDefault(); const f = [...e.dataTransfer.files].find((x) => x.type.startsWith('image/')); if (f) setImage(await readFileAs(f), f.name); });
  const presets = ['Describe this image in detail.', 'Explain the error shown and how to fix it.', 'Interpret this chart: what trend does it show?', 'Explain this diagram step by step.', 'Explain this user interface: what can I do here?', 'Read all the text in this image.'];
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Vision'), h('div.sub', {}, 'Analyse images, screenshots, charts and diagrams with a local vision model.')), h('div.actions', {}, status)),
    h('div.split', {},
      h('div.col', {},
        h('div.panel', {}, h('h3', {}, 'Source'), h('div.col', {}, btn('Upload image', () => fileIn.click(), { ico: 'upload' }), btn('Capture whole screen', capture, { ico: 'screen' }), btn('Select a screen region', region, { ico: 'grid' }), btn('Use camera', camera, { ico: 'camera' })), fileIn),
        h('div.panel', {}, h('h3', {}, 'Question'), q, h('div.row.wrap', { style: { margin: '8px 0' } }, presets.map((p) => h('button.tag', { style: { cursor: 'pointer', background: 'none' }, onclick: () => { q.value = p; } }, p.replace(/\.$/, '')))), btn('Analyse', (e) => busy(e.currentTarget, () => ask(q.value)), { cls: 'primary', ico: 'vision' }))),
      h('div.col', {}, preview, answer)));
  return () => stopCamera();
}
