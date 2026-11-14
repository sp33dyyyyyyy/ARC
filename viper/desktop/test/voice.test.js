'use strict';
// Real speech round-trip when the engines are present (Piper TTS → resample → whisper.cpp STT).
// Set VIPER_COMPONENTS_DIR to a folder with installed components and VIPER_WHISPER_BIN to a
// whisper-cli binary (Windows users get it from VIPER's installer). Skipped otherwise.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { startViper } = require('./helpers/env');
const { speakable, clean } = require('../src/server/voice/index');
const { stripWake } = require('../src/server/intents');

function wavTo16k(buf) {
  const rate = buf.readUInt32LE(24); let off = 12; let data = null;
  while (off < buf.length) { const id = buf.toString('ascii', off, off + 4); const len = buf.readUInt32LE(off + 4); if (id === 'data') { data = buf.subarray(off + 8, off + 8 + len); break; } off += 8 + len; }
  const n = Math.floor(data.length / 2 * 16000 / rate); const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0); out.writeUInt32LE(36 + n * 2, 4); out.write('WAVEfmt ', 8); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22); out.writeUInt32LE(16000, 24); out.writeUInt32LE(32000, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34); out.write('data', 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) out.writeInt16LE(data.readInt16LE(Math.min(data.length / 2 - 1, Math.floor(i * rate / 16000)) * 2), 44 + i * 2);
  return out;
}

test('speech text helpers', () => {
  assert.equal(speakable('**Bold** and `code`\n```js\nx()\n```\n- item https://x.y'), 'Bold and code (code shown on screen) item link');
  assert.equal(clean('[BLANK_AUDIO] hello  (music) world'), 'hello world');
  assert.equal(stripWake('Hey VIPER, open Spotify'), 'open Spotify');
  assert.equal(stripWake('open Spotify, viper.'), 'open Spotify');
});

const comps = process.env.VIPER_COMPONENTS_DIR; const whisper = process.env.VIPER_WHISPER_BIN;
test('Piper TTS → whisper.cpp STT round trip', { skip: !(comps && whisper && fs.existsSync(whisper)) && 'voice engines not installed in this environment' }, async (t) => {
  const svc = await startViper('voice');
  t.after(() => svc.shutdown());
  svc.settings.set('voice', { whisperPath: whisper, sttModel: 'base.en', piperVoice: 'en_GB-alan-medium' });
  assert.equal(svc.voice.status().ready.tts, true); assert.equal(svc.voice.status().ready.stt, true);
  const wav = await svc.voice.speak('Viper, open my downloads folder.');
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF'); assert.ok(wav.length > 20000);
  const r = await svc.voice.transcribe(wavTo16k(wav));
  assert.match(r.text.toLowerCase(), /open my downloads folder/);
  assert.equal(stripWake(r.text.replace(/^(Vipe?r|Piper|Wiper)/i, 'viper')).toLowerCase().replace(/[.!]/g, ''), 'open my downloads folder');
  t.diagnostic(`TTS ${wav.length} bytes; STT "${r.text}" in ${r.ms} ms`);
});
