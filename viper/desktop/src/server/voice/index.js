'use strict';
// Local voice stack:
//   STT: whisper.cpp (whisper-cli) with ggml models, or Foundry Local's
//        OpenAI-compatible /v1/audio/transcriptions when a Whisper model is loaded there.
//   TTS: Piper neural voices (British English by default). Falls back to the
//        operating system voices in the renderer when Piper is not installed.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { downloadFile, extract, findFile } = require('../download');
const { HttpError } = require('../http');
const { uid } = require('../util');

const WIN = process.platform === 'win32';
const WHISPER_RELEASE = 'v1.9.0';
const PIPER_RELEASE = '2023.11.14-2';
const COMPONENTS = {
  whisper: {
    label: 'whisper.cpp speech recognition engine',
    url: WIN ? `https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_RELEASE}/whisper-bin-x64.zip` : null,
    archive: 'whisper-bin-x64.zip', bins: WIN ? ['whisper-cli.exe'] : ['whisper-cli', 'main'], sizeMB: 9,
  },
  piper: {
    label: 'Piper neural text-to-speech engine',
    url: `https://github.com/rhasspy/piper/releases/download/${PIPER_RELEASE}/${WIN ? 'piper_windows_amd64.zip' : process.platform === 'darwin' ? 'piper_macos_x64.tar.gz' : 'piper_linux_x86_64.tar.gz'}`,
    archive: WIN ? 'piper.zip' : 'piper.tar.gz', bins: WIN ? ['piper.exe'] : ['piper'], sizeMB: 25,
  },
};
const STT_MODELS = {
  'tiny.en': { file: 'ggml-tiny.en.bin', sizeMB: 75, note: 'Fastest; fine for commands on low-end PCs.' },
  'base.en': { file: 'ggml-base.en.bin', sizeMB: 142, note: 'Recommended balance of speed and accuracy.' },
  'small.en': { file: 'ggml-small.en.bin', sizeMB: 466, note: 'More accurate; needs a faster CPU.' },
};
const VOICES = {
  'en_GB-alan-medium': { lang: 'en/en_GB', name: 'alan', q: 'medium', label: 'Alan — British male (default)', sizeMB: 63 },
  'en_GB-northern_english_male-medium': { lang: 'en/en_GB', name: 'northern_english_male', q: 'medium', label: 'Northern English male', sizeMB: 63 },
  'en_GB-jenny_dioco-medium': { lang: 'en/en_GB', name: 'jenny_dioco', q: 'medium', label: 'Jenny — British female', sizeMB: 63 },
  'en_GB-cori-high': { lang: 'en/en_GB', name: 'cori', q: 'high', label: 'Cori — British female (high quality)', sizeMB: 114 },
  'en_GB-alba-medium': { lang: 'en/en_GB', name: 'alba', q: 'medium', label: 'Alba — Scottish female', sizeMB: 63 },
  'en_US-ryan-high': { lang: 'en/en_US', name: 'ryan', q: 'high', label: 'Ryan — American male', sizeMB: 116 },
  'en_US-lessac-medium': { lang: 'en/en_US', name: 'lessac', q: 'medium', label: 'Lessac — American female', sizeMB: 63 },
};
const voiceUrl = (id, ext) => { const v = VOICES[id]; return `https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${v.lang}/${v.name}/${v.q}/${id}${ext}`; };

class VoiceService {
  constructor(svc) {
    this.svc = svc; this.dir = svc.paths.components; this.log = svc.logger.scope('voice');
    this.installs = new Map();
  }
  cfg() { return this.svc.settings.get('voice'); }
  binPath(comp) {
    const override = this.cfg()[`${comp}Path`];
    if (override && fs.existsSync(override)) return override;
    return findFile(path.join(this.dir, comp), COMPONENTS[comp].bins);
  }
  sttModelPath(id) { const m = STT_MODELS[id]; return m ? path.join(this.dir, 'whisper-models', m.file) : null; }
  voicePath(id) { return path.join(this.dir, 'voices', `${id}.onnx`); }

  status() {
    const cfg = this.cfg();
    return {
      stt: {
        engine: this.svc.settings.get('models').stt.backend || 'whisper.cpp',
        whisperInstalled: !!this.binPath('whisper'), whisperAvailableForPlatform: !!COMPONENTS.whisper.url || !!cfg.whisperPath,
        models: Object.entries(STT_MODELS).map(([id, m]) => ({ id, ...m, installed: fs.existsSync(this.sttModelPath(id)) })),
        selected: cfg.sttModel,
      },
      tts: {
        engine: cfg.ttsEngine, piperInstalled: !!this.binPath('piper'),
        voices: Object.entries(VOICES).map(([id, v]) => ({ id, label: v.label, sizeMB: v.sizeMB, installed: fs.existsSync(this.voicePath(id)) })),
        selected: cfg.piperVoice,
      },
      installs: [...this.installs.values()],
      ready: { stt: this.sttReady(), tts: this.ttsReady() },
    };
  }
  sttReady() {
    const eng = this.svc.settings.get('models').stt.backend;
    if (eng === 'foundry') return !!this.svc.settings.get('models').stt.model;
    return !!this.binPath('whisper') && fs.existsSync(this.sttModelPath(this.cfg().sttModel) || '');
  }
  ttsReady() { return !!this.binPath('piper') && fs.existsSync(this.voicePath(this.cfg().piperVoice)); }

  /** Install engine binaries, STT models or voices. Progress is published as task updates. */
  install(kind, id) {
    const key = `${kind}:${id || ''}`;
    if (this.installs.get(key)?.state === 'running') return this.installs.get(key);
    const job = { key, kind, id, state: 'running', received: 0, total: 0, label: '' };
    const jobs = [];
    if (kind === 'engine') {
      const c = COMPONENTS[id]; if (!c) throw new HttpError(400, 'Unknown component');
      if (!c.url) throw new HttpError(400, `${c.label} has no prebuilt download for this platform; set a custom binary path in Settings → Voice.`);
      job.label = `Installing ${c.label}`;
      jobs.push(async (p) => { const a = path.join(this.dir, 'downloads', c.archive); await downloadFile(c.url, a, { onProgress: p }); fs.rmSync(path.join(this.dir, id), { recursive: true, force: true }); await extract(a, path.join(this.dir, id)); fs.rmSync(a, { force: true }); const bin = this.binPath(id); if (!bin) throw new Error('Engine binary not found after extraction'); if (!WIN) fs.chmodSync(bin, 0o755); });
    } else if (kind === 'stt-model') {
      const m = STT_MODELS[id]; if (!m) throw new HttpError(400, 'Unknown model');
      job.label = `Downloading speech model ${id}`;
      jobs.push((p) => downloadFile(`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${m.file}`, this.sttModelPath(id), { onProgress: p }));
    } else if (kind === 'voice') {
      if (!VOICES[id]) throw new HttpError(400, 'Unknown voice');
      job.label = `Downloading voice ${VOICES[id].label}`;
      jobs.push((p) => downloadFile(voiceUrl(id, '.onnx.json'), `${this.voicePath(id)}.json`, { onProgress: () => {} }).then(() => downloadFile(voiceUrl(id, '.onnx'), this.voicePath(id), { onProgress: p })));
    } else throw new HttpError(400, 'Unknown install kind');
    this.installs.set(key, job);
    const taskId = `install:${key}`;
    const progress = (rec, total) => { job.received = rec; job.total = total; this.svc.bus.publish('task.update', { id: taskId, label: job.label, kind: 'install', state: 'running', progress: total ? rec / total : null }); this.svc.bus.publish('voice.install', job); };
    (async () => {
      try { for (const j of jobs) await j(progress); job.state = 'done'; } catch (e) { job.state = 'failed'; job.error = e.message; this.log.warn('install failed', e); }
      this.svc.bus.publish('task.update', { id: taskId, label: job.label, kind: 'install', state: job.state === 'done' ? 'done' : 'failed', error: job.error });
      this.svc.bus.publish('voice.install', job);
    })();
    return job;
  }

  async transcribe(wav, { language } = {}) {
    if (!wav || wav.length < 1000) throw new HttpError(400, 'Audio is empty');
    const lang = language || this.cfg().language || 'en';
    const stt = this.svc.settings.get('models').stt;
    const t0 = Date.now();
    if (stt.backend === 'foundry') {
      const ep = await this.svc.models.backends.foundry.endpoint();
      if (!ep) throw new HttpError(503, 'Foundry Local is not running');
      const fd = new FormData();
      fd.append('file', new Blob([wav], { type: 'audio/wav' }), 'speech.wav'); fd.append('model', stt.model); fd.append('language', lang);
      const r = await fetch(`${ep}/v1/audio/transcriptions`, { method: 'POST', body: fd });
      if (!r.ok) throw new HttpError(502, `Foundry transcription failed (${r.status})`);
      return { text: clean((await r.json()).text), engine: 'foundry', ms: Date.now() - t0 };
    }
    const bin = this.binPath('whisper');
    const model = this.sttModelPath(this.cfg().sttModel);
    if (!bin) throw new HttpError(503, 'Speech recognition engine is not installed. Install it in Voice settings.', 'STT_MISSING');
    if (!model || !fs.existsSync(model)) throw new HttpError(503, `Speech model ${this.cfg().sttModel} is not downloaded.`, 'STT_MODEL_MISSING');
    const tmp = path.join(os.tmpdir(), `viper-${uid()}.wav`);
    fs.writeFileSync(tmp, wav);
    try {
      const threads = String(Math.max(2, Math.min(8, os.cpus().length - 1)));
      const out = await runProc(bin, ['-m', model, '-f', tmp, '-l', lang, '-nt', '-np', '-t', threads], 60000);
      return { text: clean(out), engine: 'whisper.cpp', ms: Date.now() - t0 };
    } finally { fs.rmSync(tmp, { force: true }); }
  }

  async speak(text, { voice, rate } = {}) {
    const cfg = this.cfg();
    const bin = this.binPath('piper');
    const v = voice || cfg.piperVoice;
    if (!bin) throw new HttpError(503, 'Piper TTS is not installed.', 'TTS_MISSING');
    if (!fs.existsSync(this.voicePath(v))) throw new HttpError(503, `Voice ${v} is not downloaded.`, 'VOICE_MISSING');
    const clip = speakable(text);
    if (!clip) throw new HttpError(400, 'Nothing to speak');
    const out = path.join(os.tmpdir(), `viper-tts-${uid()}.wav`);
    const lengthScale = (1 / Math.max(0.5, Math.min(2, rate || cfg.rate || 1))).toFixed(2);
    try {
      await runProc(bin, ['--model', this.voicePath(v), '--output_file', out, '--length_scale', lengthScale, '--sentence_silence', '0.15'], 60000, clip, path.dirname(bin));
      return fs.readFileSync(out);
    } finally { fs.rmSync(out, { force: true }); }
  }
}

function runProc(bin, args, timeout, stdin, cwd) {
  return new Promise((resolve, reject) => {
    const p = spawn(bin, args, { windowsHide: true, cwd: cwd || path.dirname(bin) });
    let out = ''; let err = '';
    const t = setTimeout(() => { p.kill(); reject(new Error('Voice engine timed out')); }, timeout);
    p.stdout.on('data', (d) => { out += d; }); p.stderr.on('data', (d) => { err += d; });
    p.on('error', (e) => { clearTimeout(t); reject(e); });
    p.on('close', (code) => { clearTimeout(t); code === 0 ? resolve(out) : reject(new Error(`Voice engine exited ${code}: ${err.slice(-300)}`)); });
    if (stdin != null) { p.stdin.write(stdin); p.stdin.end(); }
  });
}
function clean(t) { return String(t || '').replace(/\[(BLANK_AUDIO|MUSIC|NOISE|SOUND|silence)[^\]]*\]|\((?:music|noise|silence|inaudible)[^)]*\)/gi, '').replace(/\s+/g, ' ').trim(); }
// Strip markdown/code so TTS reads naturally; long code blocks are summarised.
function speakable(md) {
  return String(md || '').replace(/```[\s\S]*?```/g, ' (code shown on screen) ').replace(/`([^`]+)`/g, '$1').replace(/\*\*|__|\*|#+\s/g, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/https?:\/\/\S+/g, 'link').replace(/^\s*[-*]\s+/gm, '').replace(/\|/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 2500);
}

module.exports = {
  name: 'voice',
  init: (svc) => new VoiceService(svc),
  routes(r, svc) {
    const P = '/api/v1/voice';
    r.get(`${P}/status`, async () => svc.voice.status(), { scope: 'voice' });
    r.post(`${P}/install`, async ({ body }) => svc.voice.install(body.kind, body.id));
    r.post(`${P}/transcribe`, async ({ raw, query }) => svc.voice.transcribe(raw, { language: query.language }), { scope: 'voice' });
    r.post(`${P}/speak`, async ({ body }) => ({ __raw: await svc.voice.speak(body.text, body), type: 'audio/wav' }), { scope: 'voice' });
  },
  speakable, clean, VOICES, STT_MODELS,
};
