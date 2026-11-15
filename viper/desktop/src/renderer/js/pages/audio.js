import { h, clear, icon, btn, busy, toast, toastError, select, field } from '../ui.js';
import { encodeWav } from '../voice.js';

// MAKE → Audio Studio: text-to-speech with VIPER's local Piper voices (save as WAV) and
// transcription of an audio file with the local Whisper model. Nothing leaves this PC.
export async function render(view, { app, api }) {
  const st = await api.get('/voice/status').catch(() => null);
  const ttsBox = h('div.panel'); const sttBox = h('div.panel');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Audio Studio'), h('div.sub', {}, 'Local speech synthesis and transcription.')),
    h('div.actions', {}, btn('Voice settings', () => app.go('voice'), { cls: 'sm ghost', ico: 'voice' }))),
  h('div.grid.g2', {}, ttsBox, sttBox));
  // --- text to speech
  const voices = (st?.tts?.voices || []).filter((v) => v.installed);
  const text = h('textarea.input', { rows: 6, placeholder: 'Type what VIPER should say…' });
  const voiceSel = voices.length ? select(voices.map((v) => [v.id, v.label]), app.settings.voice.piperVoice, () => {}) : null;
  const rate = h('input', { type: 'range', min: 0.6, max: 1.6, step: 0.05, value: app.settings.voice.rate || 1 });
  const player = h('div');
  ttsBox.append(h('h3', {}, icon('wave'), 'Text to speech'),
    st?.tts?.piperInstalled && voices.length ? h('div.col', {}, text, field('Voice', voiceSel), field('Rate', rate),
      h('div.row', {}, btn('Generate', async (e) => busy(e.currentTarget, async () => {
        if (!text.value.trim()) return toast('Type some text first', '', 'warn');
        try {
          const r = await api.req('POST', '/voice/speak', { text: text.value, voice: voiceSel.value, rate: Number(rate.value) }, { raw: true });
          const url = URL.createObjectURL(await r.blob());
          clear(player).append(h('audio', { controls: true, src: url, style: { width: '100%' } }), h('a.btn.sm', { href: url, download: 'viper-speech.wav' }, icon('download'), h('span.lbl', {}, 'Save WAV')));
          player.querySelector('audio').play().catch(() => {});
        } catch (err) { toastError(err); }
      }), { cls: 'primary', ico: 'play' })), player)
      : h('div.empty.small', {}, 'Piper and at least one voice must be installed. Install them in the Voice Assistant page.', h('div', { style: { marginTop: '8px' } }, btn('Open Voice Assistant', () => app.go('voice'), { cls: 'sm' }))));
  // --- transcription
  const out = h('textarea.input', { rows: 8, readonly: true, placeholder: 'The transcript appears here.' });
  const fileIn = h('input', { type: 'file', accept: 'audio/*,video/*', style: { display: 'none' }, onchange: async (e) => { const f = e.target.files[0]; if (f) await transcribe(f); e.target.value = ''; } });
  const status = h('small.mist');
  async function transcribe(f) {
    status.textContent = `Decoding ${f.name}…`;
    try {
      const ctx = new OfflineAudioContext(1, 16000, 16000);
      const buf = await ctx.decodeAudioData(await f.arrayBuffer());
      // Resample to 16 kHz mono for Whisper.
      const oc = new OfflineAudioContext(1, Math.ceil(buf.duration * 16000), 16000);
      const src = oc.createBufferSource(); src.buffer = buf; src.connect(oc.destination); src.start();
      const rendered = await oc.startRendering();
      if (buf.duration > 600) throw new Error('Files longer than 10 minutes are not supported here yet.');
      status.textContent = `Transcribing ${Math.round(buf.duration)} s of audio…`;
      const r = await api.req('POST', '/voice/transcribe', encodeWav(rendered.getChannelData(0), 16000));
      out.value = r.text || ''; status.textContent = r.text ? `Done (${Math.round(buf.duration)} s).` : 'No speech detected.';
    } catch (err) { status.textContent = ''; toastError(err, 'Transcription failed'); }
  }
  sttBox.append(h('h3', {}, icon('mic'), 'Transcribe audio'),
    st?.stt?.whisperInstalled ? h('div.col', {}, h('p.small.mist', {}, 'Choose an audio or video file (WAV, MP3, M4A, OGG, WebM…). It is decoded in VIPER and transcribed locally with Whisper.'),
      h('div.row', {}, btn('Choose file', () => fileIn.click(), { cls: 'primary', ico: 'upload' }), btn('Copy', () => { navigator.clipboard.writeText(out.value); toast('Copied'); }, { cls: 'sm ghost', ico: 'copy' })), status, out, fileIn)
      : h('div.empty.small', {}, 'The Whisper speech-recognition model is not installed. Install it in the Voice Assistant page.', h('div', { style: { marginTop: '8px' } }, btn('Open Voice Assistant', () => app.go('voice'), { cls: 'sm' }))));
}
