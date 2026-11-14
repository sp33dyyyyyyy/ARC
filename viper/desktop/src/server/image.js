'use strict';
// Image Studio backend. Uses a locally running Stable Diffusion server that
// exposes the AUTOMATIC1111-compatible API (AUTOMATIC1111, Forge, SD.Next).
// VIPER does not pretend to generate images when no such engine is running.
const fs = require('node:fs');
const path = require('node:path');
const { uid, now, fetchWithTimeout, jsonParse } = require('./util');
const { HttpError } = require('./http');
const { detectHardware } = require('./hardware');

const STYLES = {
  none: { label: 'No style', pos: '', neg: '' },
  cinematic: { label: 'Cinematic', pos: 'cinematic film still, dramatic lighting, shallow depth of field, high detail', neg: 'cartoon, low quality' },
  photo: { label: 'Photographic', pos: 'professional photograph, 35mm, natural light, sharp focus, realistic', neg: 'illustration, painting, cartoon' },
  mono: { label: 'Monochrome', pos: 'black and white, high contrast monochrome, fine grain', neg: 'color, saturated' },
  lineart: { label: 'Line art', pos: 'clean line art, ink drawing, white background, minimal', neg: 'shading, color, photo' },
  concept: { label: 'Concept art', pos: 'concept art, digital painting, detailed environment, artstation', neg: 'photo, blurry' },
  anime: { label: 'Anime', pos: 'anime style, cel shading, vibrant', neg: 'photo, realistic' },
  render3d: { label: '3D render', pos: '3d render, octane, studio lighting, physically based materials', neg: 'flat, sketch' },
  pixel: { label: 'Pixel art', pos: 'pixel art, 16-bit, crisp pixels, limited palette', neg: 'blurry, smooth gradients' },
  hud: { label: 'Futuristic HUD', pos: 'futuristic holographic interface, thin white lines, technical diagram, black background', neg: 'clutter, color noise' },
};
const ASPECTS = { '1:1': [1, 1], '4:3': [4, 3], '3:4': [3, 4], '16:9': [16, 9], '9:16': [9, 16], '3:2': [3, 2], '2:3': [2, 3] };
function dims(aspect, base) { const [a, b] = ASPECTS[aspect] || [1, 1]; const area = base * base; let w = Math.sqrt(area * a / b); let h = w * b / a; const r = (x) => Math.max(256, Math.round(x / 64) * 64); return [r(w), r(h)]; }

class ImageStudio {
  constructor(svc) { this.svc = svc; this.db = svc.db; this.dir = svc.paths.images; this.busy = null; }
  base() { return (this.svc.settings.get('image').a1111Url || 'http://127.0.0.1:7860').replace(/\/+$/, ''); }
  async status() {
    const hw = await detectHardware();
    const vram = hw.gpu?.vramGB || 0;
    const advice = vram >= 8 ? 'Your GPU can run SDXL models (about 6–8 GB VRAM).' : vram >= 4 ? 'Your GPU suits Stable Diffusion 1.5 or SDXL-Turbo at 512–768 px.' : 'No GPU with enough dedicated memory was found. CPU generation works but takes several minutes per image; use SD 1.5 at 512 px or a Turbo/LCM model with 4–8 steps.';
    try {
      const r = await fetchWithTimeout(`${this.base()}/sdapi/v1/sd-models`, {}, 4000);
      if (!r.ok) return { ok: false, url: this.base(), error: `Engine responded ${r.status}`, advice };
      const models = (await r.json()).map((m) => ({ title: m.title, name: m.model_name }));
      const opts = await (await fetchWithTimeout(`${this.base()}/sdapi/v1/options`, {}, 4000)).json().catch(() => ({}));
      let upscalers = []; try { upscalers = (await (await fetchWithTimeout(`${this.base()}/sdapi/v1/upscalers`, {}, 4000)).json()).map((u) => u.name).filter((n) => n && n !== 'None'); } catch { /* optional */ }
      let rembg = false; try { const o = await fetchWithTimeout(`${this.base()}/openapi.json`, {}, 4000); rembg = o.ok && (await o.text()).includes('/rembg'); } catch { /* optional */ }
      return { ok: true, url: this.base(), models, current: opts.sd_model_checkpoint, upscalers, rembg, advice, busy: !!this.busy };
    } catch (e) {
      return { ok: false, url: this.base(), error: 'No local image engine is running. Install Stable Diffusion WebUI Forge (free) and start it with the --api flag.', advice };
    }
  }
  async call(pathname, body, label) {
    if (this.busy) throw new HttpError(409, 'An image is already being generated');
    const taskId = uid('img_');
    this.busy = { taskId, label, startedAt: now() };
    this.svc.bus.publish('task.update', { id: taskId, label, kind: 'image', state: 'running', progress: 0 });
    const poll = setInterval(async () => {
      try {
        const p = await (await fetchWithTimeout(`${this.base()}/sdapi/v1/progress?skip_current_image=false`, {}, 3000)).json();
        this.svc.bus.publish('image.progress', { taskId, progress: p.progress, eta: p.eta_relative, preview: p.current_image ? `data:image/png;base64,${p.current_image}` : null, step: p.state?.sampling_step, steps: p.state?.sampling_steps });
        this.svc.bus.publish('task.update', { id: taskId, label, kind: 'image', state: 'running', progress: p.progress });
      } catch { /* engine busy */ }
    }, 1000);
    try {
      const r = await fetchWithTimeout(`${this.base()}${pathname}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, 30 * 60000);
      if (!r.ok) throw new HttpError(502, `Image engine error ${r.status}: ${(await r.text()).slice(0, 300)}`);
      const j = await r.json();
      this.svc.bus.publish('task.update', { id: taskId, label, kind: 'image', state: 'done' });
      return j;
    } catch (e) {
      this.svc.bus.publish('task.update', { id: taskId, label, kind: 'image', state: 'failed', error: e.message });
      if (e.status) throw e;
      throw new HttpError(503, `Image engine unavailable: ${e.message}`);
    } finally { clearInterval(poll); this.busy = null; }
  }
  save(b64, rec) {
    const id = uid('im_');
    const file = path.join(this.dir, `${id}.png`);
    fs.writeFileSync(file, Buffer.from(String(b64).replace(/^data:[^,]*,/, ''), 'base64'));
    this.db.run('INSERT INTO images (id, kind, prompt, negative, params, path, parent_id, backend, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', id, rec.kind, rec.prompt || null, rec.negative || null, JSON.stringify(rec.params || {}), file, rec.parentId || null, rec.backend || 'a1111', now());
    return { id, kind: rec.kind, prompt: rec.prompt, url: `/images/${id}/file` };
  }
  readB64(id) { const r = this.db.get('SELECT path FROM images WHERE id = ?', id); if (!r) throw new HttpError(404, 'Image not found'); return fs.readFileSync(r.path).toString('base64'); }
  prompt(p, style, negative) { const s = STYLES[style] || STYLES.none; return { prompt: [p, s.pos].filter(Boolean).join(', '), negative: [negative, s.neg].filter(Boolean).join(', ') }; }

  async generate(o) {
    const cfg = this.svc.settings.get('image');
    const [w, h] = o.width && o.height ? [o.width, o.height] : dims(o.aspect || '1:1', o.resolution || 768);
    const { prompt, negative } = this.prompt(o.prompt, o.style, o.negative);
    const params = { prompt, negative_prompt: negative, width: w, height: h, steps: o.steps || cfg.defaultSteps, cfg_scale: o.cfg || cfg.defaultCfg, seed: o.seed ?? -1, batch_size: Math.min(4, o.count || 1), sampler_name: o.sampler || undefined };
    let j;
    if (o.reference) j = await this.call('/sdapi/v1/img2img', { ...params, init_images: [o.reference.replace(/^data:[^,]*,/, '')], denoising_strength: o.strength ?? 0.6 }, 'Generating image from reference');
    else j = await this.call('/sdapi/v1/txt2img', params, 'Generating image');
    const info = jsonParse(j.info, {});
    return (j.images || []).map((b, i) => this.save(b, { kind: o.reference ? 'img2img' : 'txt2img', prompt: o.prompt, negative, params: { ...params, seed: info.all_seeds?.[i] ?? info.seed, style: o.style } }));
  }
  async edit({ imageId, prompt, mask, strength = 0.6, style }) {
    const src = this.readB64(imageId);
    const p = this.prompt(prompt || '', style);
    const body = { init_images: [src], prompt: p.prompt, negative_prompt: p.negative, denoising_strength: strength, steps: this.svc.settings.get('image').defaultSteps };
    if (mask) Object.assign(body, { mask: mask.replace(/^data:[^,]*,/, ''), inpainting_fill: 1, inpaint_full_res: true, mask_blur: 4 });
    const j = await this.call('/sdapi/v1/img2img', body, mask ? 'Inpainting' : 'Editing image');
    return (j.images || []).slice(0, 1).map((b) => this.save(b, { kind: mask ? 'inpaint' : 'img2img', prompt, parentId: imageId, params: { strength } }));
  }
  async variations({ imageId, count = 3 }) {
    const row = this.db.get('SELECT * FROM images WHERE id = ?', imageId);
    const src = this.readB64(imageId);
    const j = await this.call('/sdapi/v1/img2img', { init_images: [src], prompt: row?.prompt || '', negative_prompt: row?.negative || '', denoising_strength: 0.45, batch_size: Math.min(4, count), seed: -1, steps: this.svc.settings.get('image').defaultSteps }, 'Creating variations');
    return (j.images || []).map((b) => this.save(b, { kind: 'variation', prompt: row?.prompt, parentId: imageId }));
  }
  async upscale({ imageId, scale = 2, upscaler }) {
    const j = await this.call('/sdapi/v1/extra-single-image', { image: this.readB64(imageId), upscaling_resize: scale, upscaler_1: upscaler || 'R-ESRGAN 4x+' }, 'Upscaling');
    return [this.save(j.image, { kind: 'upscale', parentId: imageId, params: { scale, upscaler } })];
  }
  async removeBackground({ imageId }) {
    const j = await this.call('/rembg', { input_image: this.readB64(imageId), model: 'u2net', return_mask: false, alpha_matting: false }, 'Removing background');
    return [this.save(j.image, { kind: 'nobg', parentId: imageId })];
  }
  /** Save an image produced in the renderer (e.g. basic canvas resize) into history. */
  importImage({ data, kind = 'import', parentId, prompt }) { return this.save(data, { kind, parentId, prompt, backend: 'local' }); }
  history() { return this.db.all('SELECT id, kind, prompt, params, parent_id, created_at FROM images ORDER BY created_at DESC LIMIT 500').map((r) => ({ ...r, params: jsonParse(r.params, {}), url: `/images/${r.id}/file` })); }
  delete(id) { const r = this.db.get('SELECT path FROM images WHERE id = ?', id); if (r) fs.rmSync(r.path, { force: true }); this.db.run('DELETE FROM images WHERE id = ?', id); }
}

module.exports = {
  name: 'image',
  init: (svc) => {
    const st = new ImageStudio(svc);
    svc.tools.register({
      name: 'generate_image', label: 'Generate image', category: 'ui.control', risk: 'write', keywords: ['image', 'picture', 'draw', 'generate an', 'illustration', 'wallpaper'],
      description: 'Generate an image from a text prompt with the local Stable Diffusion engine (if installed). Opens Image Studio.',
      parameters: { type: 'object', properties: { prompt: { type: 'string' }, style: { type: 'string', enum: Object.keys(STYLES) }, aspect: { type: 'string', enum: Object.keys(ASPECTS) } }, required: ['prompt'] },
      handler: async (a) => { const s = await st.status(); if (!s.ok) return { ok: false, error: s.error }; svc.bus.publish('ui.navigate', { mode: 'image' }); const imgs = await st.generate(a); return { ok: true, result: { images: imgs.length, note: 'Shown in Image Studio' } }; },
    });
    return st;
  },
  routes(r, svc) {
    const P = '/api/v1/image';
    r.get(`${P}/status`, async () => svc.image.status(), { scope: 'image' });
    r.get(`${P}/styles`, async () => ({ styles: Object.entries(STYLES).map(([id, s]) => ({ id, label: s.label })), aspects: Object.keys(ASPECTS) }), { scope: 'image' });
    r.post(`${P}/generate`, async ({ body }) => svc.image.generate(body), { scope: 'image' });
    r.post(`${P}/edit`, async ({ body }) => svc.image.edit(body), { scope: 'image' });
    r.post(`${P}/variations`, async ({ body }) => svc.image.variations(body), { scope: 'image' });
    r.post(`${P}/upscale`, async ({ body }) => svc.image.upscale(body), { scope: 'image' });
    r.post(`${P}/remove-background`, async ({ body }) => svc.image.removeBackground(body), { scope: 'image' });
    r.post(`${P}/import`, async ({ body }) => svc.image.importImage(body), { scope: 'image' });
    r.post(`${P}/model`, async ({ body }) => { const res = await fetchWithTimeout(`${svc.image.base()}/sdapi/v1/options`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ sd_model_checkpoint: body.title }) }, 600000); if (!res.ok) throw new HttpError(502, 'Model switch failed'); });
    r.post(`${P}/interrupt`, async () => { await fetchWithTimeout(`${svc.image.base()}/sdapi/v1/interrupt`, { method: 'POST' }, 5000).catch(() => {}); });
    r.get(`${P}/history`, async () => svc.image.history(), { scope: 'image' });
    r.delete(`${P}/history/:id`, async ({ params }) => svc.image.delete(params.id), { scope: 'image' });
    r.get('/api/v1/images/:id/file', async ({ params }) => { const row = svc.db.get('SELECT path FROM images WHERE id = ?', params.id); if (!row || !fs.existsSync(row.path)) throw new HttpError(404, 'Not found'); return { __raw: fs.readFileSync(row.path), type: 'image/png' }; }, { scope: 'image' });
  },
  STYLES, dims,
};
