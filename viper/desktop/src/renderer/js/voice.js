// Voice engine (renderer side): microphone capture, voice-activity detection,
// wake-phrase detection (local Whisper transcription of VAD-gated speech),
// push-to-talk, continuous conversation, barge-in and audio-synced playback.
import { api } from './api.js';

const TARGET_RATE = 16000;

function encodeWav(float32, rate) {
  // downsample to 16 kHz mono PCM16
  const ratio = rate / TARGET_RATE; const n = Math.floor(float32.length / ratio);
  const buf = new ArrayBuffer(44 + n * 2); const v = new DataView(buf);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  w(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); w(8, 'WAVE'); w(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, TARGET_RATE, true); v.setUint32(28, TARGET_RATE * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) {
    const start = Math.floor(i * ratio); const end = Math.min(float32.length, Math.floor((i + 1) * ratio));
    let s = 0; for (let j = start; j < end; j++) s += float32[j]; s /= Math.max(1, end - start);
    v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, s)) * 0x7fff, true);
  }
  return new Blob([buf], { type: 'audio/wav' });
}

export class Voice extends EventTarget {
  constructor() {
    super();
    this.cfg = null; this.ctx = null; this.stream = null; this.node = null; this.src = null;
    this.state = 'off'; // off | standby (wake listening) | listening (capturing command) | processing
    this.level = 0; this.noise = 0.004; this.speaking = false;
    this.frames = []; this.pre = []; this.inSpeech = false; this.silenceMs = 0; this.speechMs = 0;
    this.mode = null; // 'wake' | 'ptt' | 'followup'
    this.followUntil = 0; this.playing = null; this.outCtx = null; this.analyser = null;
    this.queue = Promise.resolve();
    this.sttReady = false; this.ttsReady = false;
  }
  emit(type, detail) { this.dispatchEvent(new CustomEvent(type, { detail })); }
  setState(s) { if (this.state !== s) { this.state = s; this.emit('state', s); } }

  async configure(cfg, status) {
    this.cfg = cfg;
    if (status) { this.sttReady = !!status.ready?.stt; this.ttsReady = !!status.ready?.tts; }
    if (cfg.micMuted) { this.stopMic(); this.setState('off'); return; }
    if (cfg.wakeEnabled && this.sttReady) { await this.startMic(); this.mode = this.mode === 'ptt' ? 'ptt' : 'wake'; this.setState('standby'); }
    else if (this.mode !== 'ptt') { this.stopMic(); this.setState('off'); }
  }

  async startMic() {
    if (this.stream) return;
    const c = this.cfg || {};
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: { deviceId: c.inputDevice ? { exact: c.inputDevice } : undefined, noiseSuppression: c.noiseSuppression !== false, echoCancellation: c.echoCancellation !== false, autoGainControl: true, channelCount: 1 } });
    this.ctx = new AudioContext();
    await this.ctx.audioWorklet.addModule('/js/capture-worklet.js');
    this.src = this.ctx.createMediaStreamSource(this.stream);
    this.node = new AudioWorkletNode(this.ctx, 'viper-capture');
    this.node.port.onmessage = (e) => this.onFrame(e.data);
    this.src.connect(this.node);
    this.emit('mic', true);
  }
  stopMic() {
    try { this.src?.disconnect(); this.node?.disconnect(); } catch { /* ignore */ }
    this.stream?.getTracks().forEach((t) => t.stop());
    this.ctx?.close().catch(() => {});
    this.stream = null; this.ctx = null; this.node = null; this.src = null; this.level = 0;
    this.emit('level', 0); this.emit('mic', false);
  }
  static async devices() {
    try { const d = await navigator.mediaDevices.enumerateDevices(); return { inputs: d.filter((x) => x.kind === 'audioinput'), outputs: d.filter((x) => x.kind === 'audiooutput') }; } catch { return { inputs: [], outputs: [] }; }
  }

  onFrame(f) {
    const rate = this.ctx.sampleRate; const ms = (f.length / rate) * 1000;
    let s = 0; for (let i = 0; i < f.length; i++) s += f[i] * f[i];
    const rms = Math.sqrt(s / f.length);
    this.level = this.level * 0.7 + Math.min(1, rms * 12) * 0.3;
    this.emit('level', this.level);
    const sens = this.cfg?.sensitivity ?? 0.5; // 0..1 (higher = more sensitive)
    const thresh = Math.max(0.006, this.noise * (4.5 - sens * 3));
    const loud = rms > thresh;
    if (!this.inSpeech && !loud) this.noise = this.noise * 0.995 + rms * 0.005; // adapt noise floor
    const capturing = this.mode === 'ptt' || this.state === 'standby' || this.state === 'listening';
    if (!capturing) return;
    if (this.mode === 'ptt') { this.frames.push(f); return; }
    // VAD gating
    this.pre.push(f); let preMs = this.pre.length * ms; while (preMs > 350) { this.pre.shift(); preMs -= ms; }
    if (loud) {
      this.speechMs += ms; this.silenceMs = 0;
      if (!this.inSpeech && this.speechMs > 90) {
        this.inSpeech = true; this.frames = [...this.pre];
        if (this.speaking && this.cfg?.echoCancellation !== false) this.stopSpeaking('barge-in'); // user talked over VIPER
        this.emit('speechstart');
      }
    } else { this.speechMs = Math.max(0, this.speechMs - ms); if (this.inSpeech) this.silenceMs += ms; }
    if (this.inSpeech) {
      this.frames.push(f);
      const total = this.frames.length * ms;
      if (this.silenceMs > (this.cfg?.silenceMs || 900) || total > 15000) this.endUtterance();
    }
    if (this.mode === 'followup' && !this.inSpeech && Date.now() > this.followUntil) { this.mode = 'wake'; this.setState(this.cfg?.wakeEnabled ? 'standby' : 'off'); if (!this.cfg?.wakeEnabled) this.stopMic(); }
  }

  endUtterance() {
    this.inSpeech = false; this.silenceMs = 0; this.speechMs = 0;
    const frames = this.frames; this.frames = [];
    const total = frames.reduce((a, f) => a + f.length, 0);
    if (total / this.ctx.sampleRate < 0.35) return; // too short
    const all = new Float32Array(total); let o = 0; for (const f of frames) { all.set(f, o); o += f.length; }
    const wav = encodeWav(all, this.ctx.sampleRate);
    const mode = this.mode;
    this.queue = this.queue.then(() => this.handleUtterance(wav, mode));
  }

  async handleUtterance(wav, mode) {
    const prev = this.state;
    this.emit('transcribing');
    let text = '';
    try { text = (await api.req('POST', '/voice/transcribe', wav)).text || ''; } catch (e) { this.emit('error', e); this.setState(prev === 'listening' ? 'standby' : prev); return; }
    if (!text) { if (prev === 'listening') this.setState('standby'); return; }
    if (mode === 'followup' || prev === 'listening') { this.mode = 'wake'; this.setState(this.cfg?.wakeEnabled ? 'standby' : 'off'); this.emit('command', { text, viaWake: false }); return; }
    // wake mode: does the utterance begin with (or consist of) a wake phrase?
    const norm = text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
    const words = (this.cfg?.wakeWords || ['viper', 'hey viper']).map((w) => w.toLowerCase().trim()).sort((a, b) => b.length - a.length);
    // tolerate common mis-hearings of "viper"
    const variants = (w) => [w, w.replace('viper', 'vyper'), w.replace('viper', 'wiper'), w.replace('viper', 'piper'), w.replace('viper', 'diaper')];
    let hit = null;
    outer: for (const w of words) { for (const v of variants(w)) { const i = norm.indexOf(v); if (i >= 0 && i <= 12) { hit = { w: v, i }; break outer; } } }
    if (!hit) { this.emit('ignored', text); return; }
    const rest = norm.slice(hit.i + hit.w.length).trim();
    this.emit('wake', { text });
    if (rest.split(' ').length >= 2) { this.emit('command', { text: text.replace(/^[^,.!?]*?\b(hey\s+)?(viper|vyper|wiper|piper)\b[\s,.!?]*/i, ''), viaWake: true }); }
    else { this.setState('listening'); this.followUntil = Date.now() + 8000; this.mode = 'followup'; }
  }

  // ---- push-to-talk ----
  async pttStart() {
    if (this.cfg?.micMuted) { this.emit('error', new Error('Microphone is muted')); return false; }
    if (this.speaking) this.stopSpeaking('ptt');
    await this.startMic();
    this.mode = 'ptt'; this.frames = []; this.setState('listening');
    return true;
  }
  async pttStop() {
    if (this.mode !== 'ptt') return;
    const frames = this.frames; this.frames = []; this.mode = 'wake';
    this.setState(this.cfg?.wakeEnabled ? 'standby' : 'processing');
    const total = frames.reduce((a, f) => a + f.length, 0);
    const rate = this.ctx?.sampleRate || 48000;
    if (!this.cfg?.wakeEnabled) this.stopMic();
    if (total / rate < 0.3) { this.setState(this.cfg?.wakeEnabled ? 'standby' : 'off'); return; }
    const all = new Float32Array(total); let o = 0; for (const f of frames) { all.set(f, o); o += f.length; }
    this.emit('transcribing');
    try {
      const r = await api.req('POST', '/voice/transcribe', encodeWav(all, rate));
      if (r.text) this.emit('command', { text: r.text, viaWake: false });
    } catch (e) { this.emit('error', e); }
    if (!this.cfg?.wakeEnabled) this.setState('off');
  }

  /** After VIPER replies in continuous mode, listen for a follow-up without the wake word. */
  async listenFollowUp(ms = 7000) {
    if (!this.cfg?.continuous || this.cfg?.micMuted || !this.sttReady) return;
    await this.startMic(); this.mode = 'followup'; this.followUntil = Date.now() + ms; this.setState('listening');
  }

  // ---- speech output ----
  async speak(text) {
    if (!text) return;
    this.stopSpeaking('replace');
    const cfg = this.cfg || {};
    const token = Symbol('speech'); this.playing = token;
    this.speaking = true; this.emit('speaking', true);
    try {
      if (cfg.ttsEngine === 'piper' && this.ttsReady) {
        const res = await api.req('POST', '/voice/speak', { text }, { raw: true });
        if (this.playing !== token) return;
        const buf = await res.arrayBuffer();
        if (!this.outCtx) this.outCtx = new AudioContext();
        if (cfg.outputDevice && this.outCtx.setSinkId) { try { await this.outCtx.setSinkId(cfg.outputDevice); } catch { /* device gone */ } }
        const audio = await this.outCtx.decodeAudioData(buf);
        const src = this.outCtx.createBufferSource(); src.buffer = audio;
        this.analyser = this.outCtx.createAnalyser(); this.analyser.fftSize = 256; this.analyser.smoothingTimeConstant = 0.6;
        src.connect(this.analyser); this.analyser.connect(this.outCtx.destination);
        this.emit('analyser', this.analyser);
        this.source = src;
        await new Promise((resolve) => { src.onended = resolve; src.start(); });
      } else if ('speechSynthesis' in window) {
        await new Promise((resolve) => {
          const u = new SpeechSynthesisUtterance(text.replace(/```[\s\S]*?```/g, ' code shown on screen ').replace(/[*#`_>|]/g, '').slice(0, 2500));
          const voices = speechSynthesis.getVoices();
          u.voice = voices.find((v) => v.name === cfg.systemVoice) || voices.find((v) => /en-GB/i.test(v.lang)) || null;
          u.rate = cfg.rate || 1;
          u.onboundary = () => { this.emit('level', 0.6 + Math.random() * 0.4); setTimeout(() => this.emit('level', 0.15), 120); };
          u.onend = resolve; u.onerror = resolve;
          speechSynthesis.speak(u);
        });
      }
    } catch (e) { this.emit('error', e); }
    finally {
      if (this.playing === token) { this.speaking = false; this.playing = null; this.emit('analyser', null); this.emit('speaking', false); }
    }
  }
  stopSpeaking(reason = 'stop') {
    this.playing = null;
    try { this.source?.stop(); } catch { /* already stopped */ }
    try { speechSynthesis.cancel(); } catch { /* ignore */ }
    if (this.speaking) { this.speaking = false; this.emit('analyser', null); this.emit('speaking', false); this.emit('interrupted', reason); }
  }
}
export { encodeWav };
