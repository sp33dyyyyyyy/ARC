import { h, clear, icon, btn, busy, toast, toastError, select, field, prompt as ask } from '../ui.js';

// MAKE → Video Studio: builds slideshow videos from your images and converts media between
// formats, using FFmpeg on this PC. If FFmpeg is not installed the page says so — it never
// pretends to render.
export async function render(view, { app, api }) {
  const tools = await api.get('/studio/media/tools').catch(() => ({ ffmpeg: null }));
  const slide = h('div.panel'); const conv = h('div.panel'); const jobs = h('div.panel', { style: { marginTop: '14px' } });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Video Studio'), h('div.sub', {}, tools.ffmpeg ? `Using ${tools.ffmpeg.split(' Copyright')[0]}` : 'FFmpeg was not found on this PC.'))),
    ...(tools.ffmpeg ? [] : [h('div.panel', { style: { marginBottom: '14px' } }, h('h3', {}, 'Install FFmpeg to enable Video Studio'), h('p.small', {}, 'Run this in a terminal, then reopen this page:'), h('pre.mono', {}, 'winget install Gyan.FFmpeg'), btn('Check again', () => app.go('video'), { cls: 'sm', ico: 'refresh' }))]),
    h('div.grid.g2', {}, slide, conv), jobs);
  const images = []; const list = h('div.list');
  const drawList = () => clear(list).append(...(images.length ? images.map((p, i) => h('div.li', {}, h('span.tag', {}, String(i + 1)), h('div.t', {}, h('b', {}, p.split(/[\\/]/).pop()), h('small', {}, p)), btn('', () => { images.splice(i, 1); drawList(); }, { cls: 'sm ghost icon', ico: 'x', title: 'Remove' }))) : [h('small.mist', {}, 'No images yet.')]));
  const secs = h('input.input', { type: 'number', min: 1, max: 30, value: 3, style: { width: '90px' } });
  const res = select([['1280x720', '720p'], ['1920x1080', '1080p'], ['1080x1920', 'Vertical 1080×1920']], '1280x720', () => {});
  const pick = async (filters) => (window.viperNative?.pickFile ? window.viperNative.pickFile(filters) : ask('File path', { label: 'Full path inside an allowed folder' }));
  slide.append(h('h3', {}, icon('film'), 'Slideshow from images'), list,
    h('div.row.wrap', { style: { marginTop: '8px' } }, btn('Add image', async () => { const p = await pick([{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'] }]); if (p) { images.push(p); drawList(); } }, { cls: 'sm', ico: 'plus', disabled: !tools.ffmpeg }), field('Seconds each', secs), field('Size', res)),
    h('div.row', { style: { marginTop: '8px' } }, btn('Render video', async (e) => busy(e.currentTarget, async () => {
      const [w, hh] = res.value.split('x').map(Number);
      try { const r = await api.post('/studio/media/slideshow', { images, seconds: Number(secs.value), width: w, height: hh, name: 'VIPER slideshow' }); toast('Video ready', r.path); loadJobs(); } catch (err) { toastError(err, 'Render failed'); }
    }), { cls: 'primary', ico: 'play', disabled: !tools.ffmpeg })));
  drawList();
  let src = ''; const srcLbl = h('small.mist', {}, 'No file chosen');
  const fmt = select([['mp4', 'MP4 (H.264)'], ['webm', 'WebM'], ['gif', 'Animated GIF'], ['mp3', 'MP3 audio'], ['wav', 'WAV audio']], 'mp4', () => {});
  conv.append(h('h3', {}, icon('refresh'), 'Convert a file'), h('div.col', {},
    h('div.row', {}, btn('Choose file', async () => { const p = await pick([{ name: 'Media', extensions: ['mp4', 'mov', 'mkv', 'avi', 'webm', 'gif', 'mp3', 'wav', 'm4a', 'ogg', 'flac'] }]); if (p) { src = p; srcLbl.textContent = p; } }, { cls: 'sm', ico: 'upload', disabled: !tools.ffmpeg }), srcLbl),
    field('Convert to', fmt),
    h('div.row', {}, btn('Convert', async (e) => busy(e.currentTarget, async () => { if (!src) return toast('Choose a file first', '', 'warn'); try { const r = await api.post('/studio/media/convert', { path: src, format: fmt.value }); toast('Converted', r.path); loadJobs(); } catch (err) { toastError(err, 'Conversion failed'); } }), { cls: 'primary', disabled: !tools.ffmpeg })),
    h('p.small.mist', {}, 'The converted file is saved next to the original. Files must be inside your allowed folders.')));
  async function loadJobs() {
    const j = await api.get('/studio/media/jobs').catch(() => []);
    clear(jobs).append(h('h3', {}, 'Recent jobs'), j.length ? h('div.list', {}, j.map((x) => h('div.li', {}, h('div.t', {}, h('b', {}, x.label), h('small', {}, `${x.status}${x.finishedAt ? ` · ${Math.round((x.finishedAt - x.startedAt) / 1000)} s` : ''}`))))) : h('small.mist', {}, 'None yet.'));
  }
  loadJobs();
}
