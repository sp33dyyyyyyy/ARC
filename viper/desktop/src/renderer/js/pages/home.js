// Home: the core fills the screen while VIPER is idle. As soon as a conversation
// starts, the core fades and shrinks into the corner and the space becomes a chat thread.
import { h, icon, toastError, mdEl, clear } from '../ui.js';
import { Core } from '../core.js';
import { composer } from '../components/composer.js';
import { followRequest } from '../components/stream.js';

const SUGGEST = ['VIPER, are you online?', "What's happening with my computer?", 'Give me my morning briefing', 'Run a system diagnostic', 'Remind me to check my downloads later', 'Open the floating interface'];

export async function render(view, { app, api }) {
  view.className = 'view flush';
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const name = app.settings.personality.userName;
  let convId = sessionStorage.getItem('viper.homeConv') || null;

  const canvas = h('canvas.core', { role: 'img', 'aria-label': 'VIPER core status' });
  const label = h('div.core-label', { 'aria-live': 'polite' }, 'Standing by');
  const coreWrap = h('div.core-wrap', {}, canvas);
  const thread = h('div.home-thread', { 'aria-live': 'polite' });
  const transcript = h('div.transcript-live');
  const newBtn = h('button.btn.sm.ghost', { type: 'button', onclick: () => reset(), title: 'Start a new conversation and bring the core back' }, icon('plus'), 'New conversation');
  const stops = new Set();

  const comp = composer({
    app, placeholder: 'Ask VIPER anything, or give a command…',
    onSend: async (text, attachments, setBusy) => {
      transcript.textContent = '';
      try {
        const r = await app.send(text, { conversationId: convId, attachments });
        convId = r.conversationId; sessionStorage.setItem('viper.homeConv', convId);
        addUser(text, attachments);
        stream(r.requestId, setBusy);
      } catch (e) { toastError(e); }
    },
  });
  const chips = h('div.suggest', {}, SUGGEST.map((s) => h('button', { type: 'button', onclick: () => { comp.value = s; comp.focus(); } }, s)));
  const hint = h('small.mist.home-hint');
  const updHint = () => {
    const v = app.settings.voice;
    hint.textContent = v.micMuted ? 'Microphone is off.' : v.wakeEnabled && app.voice.state !== 'off' ? `Say "${v.wakeWords[0]}" to wake me, or hold Ctrl+Space to talk.` : 'Hold the mic button or Ctrl+Space to talk. Enable the wake word in Voice.';
  };
  updHint();

  const home = h('div.home', {},
    h('div.home-hero', {},
      h('div.greeting', {}, h('h1', {}, `${greet}${name ? `, ${name}` : ''}.`), h('p', {}, new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' }))),
      h('div.home-bar', {}, h('span.home-title', {}, 'VIPER'), label, h('span.grow'), newBtn),
      coreWrap, h('div.hero-label'), ),
    thread,
    h('div.dock', {}, transcript, comp.el, hint, chips));
  home.querySelector('.hero-label').append(label.cloneNode(true));
  view.append(home);

  const core = new Core(canvas);
  core.onState = (s, l) => { label.textContent = l; home.querySelector('.hero-label .core-label').textContent = l; };
  const unreg = app.registerCore(core);
  label.textContent = core.label; home.querySelector('.hero-label .core-label').textContent = core.label;

  function chatting(on) {
    if (home.classList.contains('chatting') === on) return;
    home.classList.toggle('chatting', on);
    // The canvas follows its container's size through the transition.
    setTimeout(() => core.resize(), 650);
  }
  function addUser(text, attachments = []) {
    chatting(true);
    thread.append(h('div.msg.user', {}, h('div.who', {}, 'You'), h('div.body', {}, h('div', { style: { whiteSpace: 'pre-wrap' } }, text || '(attachment)'),
      attachments.length ? h('div', {}, attachments.map((a) => h('span.tag', {}, icon(a.type === 'image' ? 'image' : 'file'), a.name))) : null)));
    thread.scrollTop = thread.scrollHeight;
  }
  function addViper(content) {
    thread.append(h('div.msg.viper', {}, h('div.who', {}, 'V'), h('div.body', {}, mdEl(content))));
  }
  function stream(requestId, setBusy) {
    chatting(true);
    const slot = h('div');
    thread.append(h('div.msg.viper', {}, h('div.who', {}, 'V'), slot));
    thread.scrollTop = thread.scrollHeight;
    setBusy?.(requestId);
    let stop = null;
    const done = () => { setBusy?.(null); stops.delete(stop); };
    stop = followRequest(app, requestId, slot, { scroller: thread, onDone: done, onError: done });
    stops.add(stop);
  }
  function reset() {
    for (const s of stops) s(); stops.clear();
    convId = null; sessionStorage.removeItem('viper.homeConv');
    clear(thread); chatting(false); comp.focus();
  }

  // Restore an ongoing conversation (stays in chat layout).
  if (convId) {
    try {
      const msgs = await api.get(`/conversations/${convId}/messages`);
      if (msgs.length) { home.classList.add('chatting', 'instant'); for (const m of msgs.slice(-40)) (m.role === 'user' ? addUser(m.content, m.attachments || []) : addViper(m.content)); requestAnimationFrame(() => { home.classList.remove('instant'); thread.scrollTop = thread.scrollHeight; core.resize(); }); }
    } catch { convId = null; sessionStorage.removeItem('viper.homeConv'); }
  }

  // Voice requests started while Home is open appear in the thread as well.
  const onTranscript = (e) => { transcript.textContent = e.detail.final ? '' : e.detail.text; transcript.classList.toggle('partial', !e.detail.final); };
  document.addEventListener('viper:transcript', onTranscript);
  const offStart = api.on('chat.start', (d) => {
    if (!d.voice || d.userMessage?.meta?.device) return;
    if (d.conversationId !== convId) { convId = d.conversationId; sessionStorage.setItem('viper.homeConv', convId); }
    addUser(d.userMessage?.content || ''); stream(d.requestId);
  });
  const onVoice = () => updHint();
  document.addEventListener('viper:voice', onVoice);
  comp.focus();
  return () => { unreg(); for (const s of stops) s(); offStart(); document.removeEventListener('viper:transcript', onTranscript); document.removeEventListener('viper:voice', onVoice); };
}
