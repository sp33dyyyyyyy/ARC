// Floating HUD: compact always-on-top core with quick commands, mic, task indicator and pop-up notifications.
import { api } from './api.js';
import { $, icon, mdEl, clear, h } from './ui.js';
import { Core, CORE_LABELS } from './core.js';
import { Voice } from './voice.js';

const core = new Core($('#core'), { compact: true });
const voice = new Voice();
let settings = null; let state = { thinking: new Set(), tools: 0, health: {} };
let currentReq = null; let buf = ''; let convId = sessionStorage.getItem('viper.hudConv');
const out = $('#out');

$('#b-compact').append(icon('hud')); $('#b-main').append(icon('external')); $('#b-close').append(icon('x')); $('#mic').append(icon('mic'));
const setCompact = (c) => { document.body.classList.toggle('compact', c); window.viperNative?.hudSize(c); setTimeout(() => core.resize(), 80); };
$('#b-compact').onclick = async () => { const c = !document.body.classList.contains('compact'); setCompact(c); settings.ui = await api.patch('/settings/ui', { hudCompact: c }); };
$('#b-main').onclick = () => window.viperNative?.showMain();
$('#b-close').onclick = () => window.viperNative?.toggleHud(false);

function coreState() {
  let s = 'idle';
  const be = settings?.backend?.active;
  if (be && state.health[be] && !state.health[be].ok) s = 'offline';
  if (state.thinking.size) s = 'thinking';
  if (state.tools) s = 'processing';
  if (voice.state === 'listening') s = 'listening';
  if (voice.speaking) s = 'speaking';
  if (state.confirm) s = 'warning';
  core.setState(s);
  $('#status').textContent = CORE_LABELS[s];
}
function pop(title, body) {
  const p = h('div.hud-pop', {}, h('b', {}, title), body ? h('span', {}, body.slice(0, 140)) : null);
  $('#pops').append(p); setTimeout(() => p.remove(), 6000);
}
async function send(text) {
  if (!text.trim()) return;
  clear(out).append(h('div.q', {}, text));
  buf = '';
  const r = await api.post('/chat', { text, conversationId: convId, voice: !!send.voice });
  send.voice = false;
  convId = r.conversationId; sessionStorage.setItem('viper.hudConv', convId);
  currentReq = r.requestId; state.thinking.add(r.requestId); coreState();
  for (const e of api.replay(r.requestId)) handle(e.type, e.data);
}
function handle(type, d) {
  if (d.requestId !== currentReq) return;
  if (type === 'chat.token') { state.thinking.delete(d.requestId); buf += d.text; out.lastChild?.classList?.contains('md') ? out.lastChild.replaceWith(mdEl(buf)) : out.append(mdEl(buf)); out.scrollTop = out.scrollHeight; }
  if (type === 'chat.tool') { state.tools = Math.max(0, state.tools + (d.state === 'running' ? 1 : -1)); }
  if (type === 'chat.done' || type === 'chat.error' || type === 'chat.cancelled') {
    state.thinking.delete(d.requestId); state.tools = 0;
    const text = type === 'chat.done' ? (d.message?.content || '') : (d.error || 'Stopped');
    if (!d.silent) { const q = out.querySelector('.q'); clear(out); if (q) out.append(q); out.append(mdEl(text)); }
    if ((d.speak || voiceReq.has(d.requestId)) && !d.silent && settings.voice.speakReplies && text) voice.speak(text).then(() => voice.listenFollowUp());
    voiceReq.delete(d.requestId);
  }
  coreState();
}
const voiceReq = new Set();
for (const t of ['chat.token', 'chat.tool', 'chat.done', 'chat.error', 'chat.cancelled']) api.on(t, (d) => handle(t, d));

$('#cmd').addEventListener('submit', (e) => { e.preventDefault(); const v = $('#cmd-in').value; $('#cmd-in').value = ''; send(v).catch((err) => pop('Error', err.message)); });
$('#mic').onclick = async () => {
  if (voice.mode === 'ptt') { $('#mic').classList.remove('mic-btn', 'live'); voice.pttStop(); }
  else if (await voice.pttStart().catch((e) => { pop('Microphone', e.message); return false; })) $('#mic').classList.add('mic-btn', 'live');
};
window.viperNative?.onPtt?.((down) => (down ? voice.pttStart() : voice.pttStop()));
voice.addEventListener('command', async (e) => { send.voice = true; await send(e.detail.text).catch(() => {}); voiceReq.add(currentReq); });
voice.addEventListener('level', (e) => core.setLevel(e.detail));
voice.addEventListener('analyser', (e) => core.setAnalyser(e.detail));
voice.addEventListener('state', coreState); voice.addEventListener('speaking', coreState);

api.on('notification', (n) => { if (!n.suppressed?.length) pop(`VIPER: ${n.title}`, n.body); });
api.on('models.health', (hl) => { state.health = hl; coreState(); });
api.on('confirm.request', () => { state.confirm = true; coreState(); pop('Approval needed', 'Open VIPER to approve or deny the requested action.'); window.viperNative?.showMain(); });
api.on('confirm.closed', () => { state.confirm = false; coreState(); });
api.on('voice.stop', () => voice.stopSpeaking());
api.on('tasks.changed', async () => {
  const t = (await api.get('/tasks').catch(() => ({ tasks: [] }))).tasks.filter((x) => x.state === 'running');
  const el = $('#task'); el.classList.toggle('hidden', !t.length); el.textContent = t.length ? `${t[0].label}${t[0].progress != null ? ` · ${Math.round(t[0].progress * 100)}%` : ''}${t.length > 1 ? ` (+${t.length - 1})` : ''}` : '';
});
api.on('settings.changed', (d) => { settings[d.section] = d.value; if (d.section === 'ui') { core.setMode(d.value.animations); core.setFps(d.value.fpsLimit || 60); } if (d.section === 'performance') core.setAdaptive(d.value.adaptiveQuality !== false); if (d.section === 'voice') voice.configure(d.value).catch(() => {}); });

(async () => {
  api.connect();
  settings = await api.get('/settings');
  state.health = (await api.get('/status')).health || {};
  core.setMode(settings.ui.animations); core.setFps(settings.ui.fpsLimit || 60); core.setAdaptive(settings.performance?.adaptiveQuality !== false); core.start();
  if (settings.ui.hudCompact) setCompact(true);
  try { await voice.configure({ ...settings.voice, wakeEnabled: false }, await api.get('/voice/status')); } catch { /* voice optional */ }
  coreState();
  $('#cmd-in').focus();
})();
