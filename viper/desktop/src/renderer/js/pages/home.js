import { h, icon, toastError } from '../ui.js';
import { Core } from '../core.js';
import { composer } from '../components/composer.js';
import { followRequest } from '../components/stream.js';

const SUGGEST = ['VIPER, are you online?', "What's happening with my computer?", 'Give me my morning briefing', 'Run a system diagnostic', 'Remind me to check my downloads later', 'Open the floating interface'];

export async function render(view, { app }) {
  view.className = 'view flush';
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const name = app.settings.personality.userName;
  const canvas = h('canvas.core', { role: 'img', 'aria-label': 'VIPER core status' });
  const label = h('div.core-label', { 'aria-live': 'polite' }, 'Standing by');
  const coreWrap = h('div.core-wrap', {}, canvas, label);
  const transcript = h('div.transcript-live');
  const reply = h('div.reply-panel.panel.quiet.hidden');
  let convId = sessionStorage.getItem('viper.homeConv') || null;
  let stopFollow = null;
  const comp = composer({
    app, placeholder: 'Ask VIPER anything, or give a command…',
    onSend: async (text, attachments, setBusy) => {
      transcript.textContent = text; transcript.classList.remove('partial');
      try {
        const r = await app.send(text, { conversationId: convId, attachments });
        convId = r.conversationId; sessionStorage.setItem('viper.homeConv', convId);
        show(r.requestId, setBusy);
      } catch (e) { toastError(e); }
    },
  });
  function show(requestId, setBusy) {
    reply.classList.remove('hidden');
    setBusy?.(requestId);
    stopFollow?.();
    stopFollow = followRequest(app, requestId, reply, { scroller: reply, onDone: () => setBusy?.(null), onError: () => setBusy?.(null) });
  }
  const chips = h('div.suggest', {}, SUGGEST.map((s) => h('button', { type: 'button', onclick: () => { comp.value = s; comp.focus(); } }, s)));
  const voiceHint = h('small.mist', { style: { textAlign: 'center' } });
  const updHint = () => {
    const v = app.settings.voice;
    voiceHint.textContent = v.micMuted ? 'Microphone is off.' : v.wakeEnabled && app.voice.state !== 'off' ? `Say "${v.wakeWords[0]}" to wake me, or hold Ctrl+Space to talk.` : 'Hold the mic button or Ctrl+Space to talk. Enable the wake word in Voice.';
  };
  updHint();
  view.append(h('div.home', {},
    h('div', { style: { position: 'relative', minHeight: 0, display: 'grid' } },
      h('div.greeting', {}, h('h1', {}, `${greet}${name ? `, ${name}` : ''}.`), h('p', {}, new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' }))),
      coreWrap),
    h('div.dock', {}, transcript, reply, comp.el, voiceHint, chips)));
  const core = new Core(canvas);
  core.onState = (s, l) => { label.textContent = l; };
  const unreg = app.registerCore(core);
  label.textContent = core.label;
  // voice: show requests initiated by voice here too
  const onTranscript = (e) => { transcript.textContent = e.detail.text; transcript.classList.toggle('partial', !e.detail.final); };
  document.addEventListener('viper:transcript', onTranscript);
  const offStart = app.api.on('chat.start', (d) => { if (d.voice && !d.userMessage?.meta?.device) show(d.requestId); });
  const onVoice = () => updHint();
  document.addEventListener('viper:voice', onVoice);
  comp.focus();
  return () => { unreg(); stopFollow?.(); offStart(); document.removeEventListener('viper:transcript', onTranscript); document.removeEventListener('viper:voice', onVoice); };
}
