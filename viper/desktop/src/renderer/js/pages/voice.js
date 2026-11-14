import { h, clear, icon, btn, toast, toastError, field, toggle, select, progress, when, prompt as askText } from '../ui.js';
import { Core } from '../core.js';
import { Voice } from '../voice.js';

export async function render(view, { app, api }) {
  const v = () => app.settings.voice;
  const save = async (patch) => { app.settings.voice = await api.patch('/settings/voice', patch); };
  const canvas = h('canvas.core');
  const stateEl = h('div.mist', { style: { textAlign: 'center' } });
  const level = h('div.meter', { style: { width: '220px', margin: '6px auto' } }, h('i'));
  const transcript = h('div.list', { style: { maxHeight: '260px', overflowY: 'auto' } });
  const comps = h('div'); const prefs = h('div'); const devs = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Voice'), h('div.sub', {}, 'Hands-free conversation. Speech recognition and the speaking voice run on this PC; audio never leaves it.')),
    h('div.actions', {}, btn(v().micMuted ? 'Turn microphone on' : 'Turn microphone off', async () => { await save({ micMuted: !v().micMuted }); toast(v().micMuted ? 'Microphone off' : 'Microphone on'); app.go('voice'); }, { cls: v().micMuted ? 'primary' : '', ico: v().micMuted ? 'mic' : 'micoff' }))),
  h('div.grid.g2', {},
    h('div.panel', {}, h('div.core-wrap', { style: { height: '260px' } }, canvas), stateEl, level,
      h('div.row', { style: { justifyContent: 'center', marginTop: '8px' } }, (() => {
        const b = h('button.btn.primary.mic-btn', { type: 'button' }, icon('mic'), 'Hold to talk');
        b.addEventListener('pointerdown', async () => { if (await app.voice.pttStart().catch((e) => { toastError(e); return false; })) b.classList.add('live'); });
        const up = () => { if (b.classList.contains('live')) { b.classList.remove('live'); app.voice.pttStop(); } };
        b.addEventListener('pointerup', up); b.addEventListener('pointerleave', up);
        return b;
      })(), btn('Stop speaking', () => app.voice.stopSpeaking('button'), { ico: 'stop' })),
      h('h3', { style: { marginTop: '14px' } }, 'Live transcript'), transcript),
    h('div.col', {}, comps, prefs, devs)));
  const core = new Core(canvas); const unreg = app.registerCore(core);
  const st = () => { stateEl.textContent = `${core.label} · ${{ off: 'microphone idle', standby: `listening for "${v().wakeWords[0]}"`, listening: 'capturing speech', processing: 'processing' }[app.voice.state] || app.voice.state}`; };
  core.onState = st; st();
  const onLevel = (e) => { level.firstChild.style.width = `${Math.round(e.detail * 100)}%`; };
  app.voice.addEventListener('level', onLevel);
  const onVs = () => st(); document.addEventListener('viper:voice', onVs);
  const addLine = (who, text) => { transcript.prepend(h('div.li', {}, h('b', { style: { width: '54px', fontWeight: 400, color: who === 'You' ? 'var(--ink)' : 'var(--mist)' } }, who), h('div.t', {}, h('span', { style: { whiteSpace: 'normal' } }, text)), h('small.mist', {}, new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })))); };
  const onTr = (e) => { if (e.detail.final) addLine('You', e.detail.text); };
  document.addEventListener('viper:transcript', onTr);
  const offDone = api.on('chat.done', (d) => { if (d.speak && d.message?.content) addLine('VIPER', d.message.content); });
  const onIgnored = (e) => addLine('(heard)', `${e.detail} — no wake word`); app.voice.addEventListener('ignored', onIgnored);
  try { for (const t of (await api.get('/transcripts')).slice(0, 12).reverse()) transcript.prepend(h('div.li', {}, h('b', { style: { width: '54px', fontWeight: 400 } }, t.speaker === 'user' ? 'You' : 'VIPER'), h('div.t', {}, h('span', { style: { whiteSpace: 'normal' } }, t.text)), h('small.mist', {}, when(t.ts)))); } catch { /* none */ }

  async function drawComps() {
    let s; try { s = await api.get('/voice/status'); } catch (e) { clear(comps).append(h('div.panel', {}, `Voice service unavailable: ${e.message}`)); return; }
    app.voiceStatus = s;
    const inst = (kind, id, label = 'Install') => btn(label, async (e) => { e.currentTarget.disabled = true; try { await api.post('/voice/install', { kind, id }); } catch (er) { toastError(er); } }, { cls: 'sm' });
    const running = s.installs.filter((i) => i.state === 'running');
    clear(comps).append(h('div.panel', {}, h('h3', {}, icon('voice'), 'Speech engines', h('span.r', {}, s.ready.stt && s.ready.tts ? 'Ready' : 'Setup needed')),
      h('div.list', {},
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Speech recognition — whisper.cpp'), h('small', {}, s.stt.whisperInstalled ? 'Installed' : s.stt.whisperAvailableForPlatform ? 'Not installed (9 MB)' : 'No prebuilt engine for this OS; set a binary path in settings')), s.stt.whisperInstalled ? h('span.tag.on', {}, 'Ready') : s.stt.whisperAvailableForPlatform ? inst('engine', 'whisper') : null),
        ...s.stt.models.map((m) => h('div.li', {}, h('div.t', {}, h('b', {}, `Model ${m.id}`, m.id === v().sttModel ? h('span.tag', { style: { marginLeft: '6px' } }, 'Selected') : null), h('small', {}, `${m.sizeMB} MB · ${m.note}`)), m.installed ? (m.id === v().sttModel ? h('span.tag.on', {}, 'Installed') : btn('Use', async () => { await save({ sttModel: m.id }); drawComps(); }, { cls: 'sm' })) : inst('stt-model', m.id, 'Download'))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Speaking voice — Piper'), h('small', {}, s.tts.piperInstalled ? 'Installed' : 'Not installed (25 MB). Without it, Windows voices are used.')), s.tts.piperInstalled ? h('span.tag.on', {}, 'Ready') : inst('engine', 'piper')),
        ...s.tts.voices.map((x) => h('div.li', {}, h('div.t', {}, h('b', {}, x.label, x.id === v().piperVoice ? h('span.tag', { style: { marginLeft: '6px' } }, 'Selected') : null), h('small', {}, `${x.sizeMB} MB`)),
          x.installed ? h('div.row', {}, btn('', () => { app.voice.ttsReady = true; save({ piperVoice: x.id }).then(() => app.voice.speak('Good evening. All systems are operating normally.')); }, { cls: 'sm ghost icon', ico: 'play', title: 'Preview' }), x.id !== v().piperVoice ? btn('Use', async () => { await save({ piperVoice: x.id }); drawComps(); }, { cls: 'sm' }) : null) : inst('voice', x.id, 'Download')))),
      ...running.map((i) => h('div', { style: { marginTop: '8px' } }, h('small.mist', {}, i.label), progress(i.total ? i.received / i.total : null))),
      h('p.small.mist', { style: { marginTop: '8px' } }, 'If you use Foundry Local, it can also run Whisper models (whisper-tiny/base/small); choose “Foundry Local” as the recognition engine below after loading one there.')));
  }
  async function drawPrefs() {
    const x = v(); const voicesSys = speechSynthesis.getVoices();
    clear(prefs).append(h('div.panel', {}, h('h3', {}, 'Conversation'),
      h('div.list', {},
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Wake word'), h('small', {}, 'Listen continuously and respond when you say the activation phrase. Needs speech recognition installed. Uses CPU only while you speak.')), toggle(x.wakeEnabled, async (val) => { await save({ wakeEnabled: val }); if (val && !app.voiceStatus?.ready?.stt) toast('Install speech recognition first', 'The wake word needs whisper.cpp and a speech model.', 'warn'); })),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Continuous conversation'), h('small', {}, 'After VIPER replies, keep listening briefly for a follow-up without the wake word.')), toggle(x.continuous, (val) => save({ continuous: val }))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Speak replies to voice requests')), toggle(x.speakReplies, (val) => save({ speakReplies: val }))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Save transcripts')), toggle(app.settings.privacy.saveTranscripts, async (val) => { app.settings.privacy = await api.patch('/settings/privacy', { saveTranscripts: val }); }))),
      h('div.grid.g2', { style: { marginTop: '10px' } },
        field('Activation phrases', h('input.input', { value: x.wakeWords.join(', '), onchange: (e) => save({ wakeWords: e.target.value.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean) }) }), 'Comma separated, e.g. viper, hey viper'),
        field('Recognition engine', select([['whisper.cpp', 'whisper.cpp (local)'], ['foundry', 'Foundry Local Whisper']], app.settings.models.stt.backend, async (val) => { app.settings.models = await api.post('/models/role', { role: 'stt', backend: val, model: val === 'foundry' ? ((await askText('Foundry Local Whisper model', { label: 'Model id as loaded in Foundry Local', value: app.settings.models.stt.model || 'whisper-base' })) || '') : x.sttModel }); drawComps(); })),
        field(`Microphone sensitivity (${Math.round(x.sensitivity * 100)}%)`, h('input', { type: 'range', min: 0, max: 1, step: 0.05, value: x.sensitivity, onchange: (e) => save({ sensitivity: Number(e.target.value) }) })),
        field(`End-of-speech pause (${x.silenceMs} ms)`, h('input', { type: 'range', min: 400, max: 2000, step: 100, value: x.silenceMs, onchange: (e) => save({ silenceMs: Number(e.target.value) }) })),
        field(`Speaking rate (${x.rate.toFixed(2)}×)`, h('input', { type: 'range', min: 0.7, max: 1.4, step: 0.05, value: x.rate, onchange: (e) => save({ rate: Number(e.target.value) }) })),
        field('Voice engine', select([['piper', 'Piper (neural, local)'], ['system', 'Windows voices']], x.ttsEngine, (val) => save({ ttsEngine: val })))),
      h('div.list', { style: { marginTop: '6px' } },
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Noise suppression')), toggle(x.noiseSuppression, (val) => save({ noiseSuppression: val }))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Echo cancellation and barge-in'), h('small', {}, 'Lets you interrupt VIPER by speaking over it.')), toggle(x.echoCancellation, (val) => save({ echoCancellation: val })))),
      voicesSys.length ? field('Windows voice (fallback)', select([['', 'Automatic (British English if available)'], ...voicesSys.map((s) => [s.name, `${s.name} (${s.lang})`])], x.systemVoice, (val) => save({ systemVoice: val }))) : null));
  }
  async function drawDevs() {
    const d = await Voice.devices();
    clear(devs).append(h('div.panel', {}, h('h3', {}, 'Audio devices'), h('div.grid.g2', {},
      field('Microphone', select([['', 'System default'], ...d.inputs.map((x) => [x.deviceId, x.label || 'Microphone'])], v().inputDevice, (val) => save({ inputDevice: val }))),
      field('Speaker', select([['', 'System default'], ...d.outputs.map((x) => [x.deviceId, x.label || 'Speaker'])], v().outputDevice, (val) => save({ outputDevice: val })))),
    !d.inputs.some((x) => x.label) ? h('p.small.mist', {}, 'Device names appear after microphone permission is granted (use Hold to talk once).') : null));
  }
  drawComps(); drawPrefs(); drawDevs();
  const offInst = api.on('voice.install', (j) => { drawComps(); if (j.state === 'done') toast('Installed', j.label.replace(/^(Installing|Downloading) /, '')); if (j.state === 'failed') toast('Install failed', j.error, 'error'); });
  const offSet = api.on('settings.changed', (d) => { if (d.section === 'voice') drawPrefs(); });
  return () => { unreg(); offInst(); offSet(); offDone(); app.voice.removeEventListener('level', onLevel); app.voice.removeEventListener('ignored', onIgnored); document.removeEventListener('viper:voice', onVs); document.removeEventListener('viper:transcript', onTr); };
}
