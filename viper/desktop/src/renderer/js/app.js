// VIPER renderer shell: navigation, live status rail, permission prompts,
// voice integration and the global AI state that drives every core.
import { api } from './api.js';
import { h, $, clear, icon, toast, toastError, modal, bytes, ago } from './ui.js';
import { Voice } from './voice.js';
import { CORE_LABELS } from './core.js';

// Navigation: five categories with collapsible sections. Every page from earlier versions is
// still here; "code" (old Code Studio) opens the new Code Agent workspace.
export const CATEGORIES = [
  { id: 'prompt', label: 'Prompt', icon: 'chat', items: [['home', 'VIPER', 'home'], ['chat', 'Chat', 'chat'], ['voice', 'Voice Assistant', 'voice'], ['vision', 'Live Vision', 'vision'], ['research', 'Research', 'research'], ['conversations', 'AI Conversations', 'chat'], ['memsearch', 'Memory Search', 'memory']] },
  { id: 'make', label: 'Make', icon: 'sparkle', items: [['agent', 'AI Coding Agent', 'code'], ['image', 'Image Studio', 'image'], ['video', 'Video Studio', 'film'], ['audio', 'Audio Studio', 'wave'], ['documents', 'Document Studio', 'doc'], ['studio3d', '3D Studio', 'cube'], ['builder', 'Project Builder', 'grid']] },
  { id: 'manage', label: 'Manage', icon: 'control', items: [['control', 'PC Control', 'control'], ['taskmanager', 'Task Manager', 'list'], ['automation', 'Automations', 'automation'], ['files', 'File Manager', 'files'], ['system', 'System Monitor', 'system'], ['devices', 'Connected Devices', 'phone'], ['notifications', 'Notifications', 'bell'], ['tasks', 'Background Tasks', 'refresh'], ['scheduled', 'Scheduled Tasks', 'clock'], ['comms', 'Communications', 'comms']] },
  { id: 'intel', label: 'Intelligence', icon: 'models', items: [['models', 'Model Manager', 'models'], ['memory', 'Memory', 'memory'], ['benchmark', 'Model Benchmarking', 'gauge'], ['knowledge', 'Knowledge Base', 'research'], ['aiconfig', 'AI Configuration', 'sparkle'], ['permissions', 'Agent Permissions', 'shield'], ['plugins', 'Plugins', 'plugins']] },
  { id: 'settings', label: 'Settings', icon: 'settings', items: [['settings:appearance', 'Appearance', 'eye'], ['settings:voice', 'Voice', 'voice'], ['settings:backend', 'AI Backend', 'models'], ['settings:performance', 'Performance', 'gauge'], ['settings:privacy', 'Privacy', 'shield'], ['settings:security', 'Security', 'shield'], ['settings:mobile', 'Mobile Connection', 'phone'], ['settings:notifications', 'Notifications', 'bell'], ['settings:startup', 'Startup', 'clock'], ['settings:updates', 'Updates', 'refresh']] },
];
const NAV = [...new Map(CATEGORIES.flatMap((c) => c.items).map(([m, l]) => [m.split(':')[0], [m.split(':')[0], l]])).values()];
const ALIASES = { code: 'agent' };
// Pages reachable from inside other pages rather than the sidebar.
const HIDDEN = [['codestudio', 'Classic editor', 'make']];
NAV.push(...HIDDEN.map(([m, l]) => [m, l]));
const labelFor = (mode, params) => {
  const key = params?.tab ? `${mode}:${params.tab}` : mode;
  for (const c of CATEGORIES) for (const [m, l] of c.items) if (m === key) return { label: l, category: c.label };
  for (const c of CATEGORIES) for (const [m, l] of c.items) if (m === mode) return { label: l, category: c.label };
  if (CATEGORIES.find((c) => c.id === mode.split(':')[0])) return { label: mode, category: '' };
  const hidden = HIDDEN.find(([m]) => m === mode); if (hidden) return { label: hidden[1], category: CATEGORIES.find((c) => c.id === hidden[2])?.label || '' };
  if (mode === 'settings') return { label: 'Settings', category: '' };
  return { label: mode, category: '' };
};

export const app = {
  api, settings: null, status: null, sample: null, health: {}, tasks: [], aiTasks: new Map(), notifications: [],
  cores: new Set(), voice: new Voice(), coreState: 'idle', mode: null, cleanup: null, pending: new Map(), phone: null,
  thinking: new Set(), toolsRunning: 0, warningUntil: 0, pluginPages: [],
  history: [],

  registerCore(core) {
    this.cores.add(core);
    core.setMode(this.settings?.ui?.animations || 'full');
    core.setFps(this.settings?.ui?.fpsLimit || 60);
    core.setAdaptive(this.settings?.performance?.adaptiveQuality !== false);
    core.setState(this.coreState);
    return () => { this.cores.delete(core); core.destroy(); };
  },
  updateCore() {
    const be = this.settings?.backend?.active;
    let s = 'idle';
    if (be && this.health[be] && !this.health[be].ok) s = 'offline';
    // Automatic AI start-up drives the core through its real stages.
    const st = this.ai?.stage;
    if (['init', 'engine', 'starting', 'model', 'verify'].includes(st)) s = 'processing';
    else if (st === 'error' || st === 'setup') s = 'offline';
    else if (st === 'ready' && s === 'offline') s = 'idle';
    if (this.thinking.size) s = 'thinking';
    if (this.toolsRunning > 0) s = 'processing';
    if (this.voice.state === 'listening') s = 'listening';
    if (this.voice.speaking) s = 'speaking';
    if (this.pending.size || Date.now() < this.warningUntil) s = 'warning';
    this.coreState = s;
    for (const c of this.cores) c.setState(s);
    document.dispatchEvent(new CustomEvent('viper:core', { detail: { state: s, label: CORE_LABELS[s] } }));
  },

  /** Send a message through the orchestrator. Returns {requestId, conversationId}. */
  async send(text, opts = {}) {
    const r = await api.post('/chat', { text, conversationId: opts.conversationId, mode: opts.mode || 'chat', voice: !!opts.voice, attachments: opts.attachments, private: opts.private, model: opts.model });
    this.thinking.add(r.requestId);
    if (opts.voice) this.voiceRequests.add(r.requestId);
    // The reply may already have completed (fast commands) before this response arrived.
    for (const e of api.replay(r.requestId)) if (['chat.done', 'chat.error', 'chat.cancelled', 'chat.token'].includes(e.type)) app.lateEvent?.(e);
    this.updateCore();
    return r;
  },
  voiceRequests: new Set(),

  go(mode, params) {
    if (ALIASES[mode]) mode = ALIASES[mode];
    if (mode.includes(':') && !mode.startsWith('plugin:')) { const [m, tab] = mode.split(':'); mode = m; params = { ...(params || {}), tab }; }
    if (!NAV.some(([m]) => m === mode) && !mode.startsWith('plugin:')) mode = 'home';
    const hash = `#/${mode}${params?.tab ? `:${params.tab}` : ''}`;
    if (location.hash !== hash) { history.pushState(null, '', hash); }
    this.render(mode, params);
  },
  async render(mode, params) {
    if (this.cleanup) { try { this.cleanup(); } catch { /* ignore */ } this.cleanup = null; }
    this.mode = mode; this.params = params || null;
    markActive();
    const { label, category } = labelFor(mode, params);
    $('#crumbs').textContent = mode === 'home' ? '' : `${category ? `${category} › ` : ''}${label}`;
    const view = $('#view');
    clear(view); view.className = 'view';
    // restart entrance animation
    void view.offsetWidth;
    try {
      const page = mode.startsWith('plugin:') ? await import('./pages/plugin-page.js') : await import(`./pages/${mode}.js`);
      this.cleanup = (await page.render(view, { app, api, params, mode })) || null;
    } catch (e) {
      console.error(e);
      view.append(h('div.empty', {}, h('b', {}, `${label} failed to load`), e.message));
    }
  },
};
window.viperApp = app;

// ---------------- shell ----------------
function navState() { try { return JSON.parse(localStorage.getItem('viper.nav') || '{}'); } catch { return {}; } }
function saveNavState(st) { try { localStorage.setItem('viper.nav', JSON.stringify(st)); } catch { /* storage unavailable */ } }
function markActive() {
  const key = app.params?.tab ? `${app.mode}:${app.params.tab}` : app.mode;
  let activeCat = null;
  for (const el of document.querySelectorAll('.nav-item[data-mode]')) {
    const on = el.dataset.mode === key || (el.dataset.mode === app.mode && !document.querySelector(`.nav-item[data-mode="${key}"]`));
    el.classList.toggle('active', on);
    if (on) activeCat = el.closest('.nav-cat')?.dataset.cat || activeCat;
  }
  for (const c of document.querySelectorAll('.nav-cat')) c.classList.toggle('has-active', c.dataset.cat === activeCat);
  // Open the category of the active page (and remember it as the last used one).
  if (activeCat) { const st = navState(); if (!st.open?.includes(activeCat)) { st.open = [...new Set([...(st.open || []), activeCat])]; } st.last = activeCat; saveNavState(st); document.querySelector(`.nav-cat[data-cat="${activeCat}"]`)?.classList.add('open'); }
}
function buildNav() {
  const nav = $('#nav'); clear(nav);
  const st = navState(); const open = new Set(st.open || ['prompt']);
  for (const cat of CATEGORIES) {
    const inner = h('div.nav-items-in');
    const items = h('div.nav-items', { role: 'group', 'aria-label': cat.label }, inner);
    for (const [mode, label, ico] of cat.items) inner.append(h('button.nav-item', { 'data-mode': mode, onclick: () => app.go(mode), title: label }, icon(ico || mode), h('span.lbl', {}, label)));
    if (cat.id === 'intel') for (const p of app.pluginPages) inner.append(h('button.nav-item', { 'data-mode': `plugin:${p.id}`, onclick: () => app.go(`plugin:${p.id}`), title: p.title }, icon('plugins'), h('span.lbl', {}, p.title)));
    const head = h('button.nav-head', { type: 'button', 'aria-expanded': String(open.has(cat.id)), title: cat.label, onclick: () => {
      const el = head.parentElement; const isOpen = el.classList.toggle('open'); head.setAttribute('aria-expanded', String(isOpen));
      const s2 = navState(); s2.open = [...document.querySelectorAll('.nav-cat.open')].map((x) => x.dataset.cat); saveNavState(s2);
    } }, icon(cat.icon), h('span.lbl', {}, cat.label), h('span.chev', { 'aria-hidden': 'true' }));
    nav.append(h(`div.nav-cat${open.has(cat.id) ? '.open' : ''}`, { 'data-cat': cat.id }, head, items));
  }
  nav.append(h('div.collapse', {},
    h('button.nav-item', { onclick: () => togglePanel('leftPanel'), title: 'Compact sidebar' }, icon('panelL'), h('span.lbl', {}, 'Compact sidebar')),
    h('button.nav-item', { onclick: () => togglePanel('rightPanel'), title: 'Toggle status panel' }, icon('panelR'), h('span.lbl', {}, 'Status panel'))));
  markActive();
}
async function togglePanel(key) {
  // On narrow windows the status panel is shown as an overlay rather than squeezing the page.
  if (key === 'rightPanel' && matchMedia('(max-width: 1279px)').matches) { $('#shell').classList.toggle('rail-open'); renderRail(true); return; }
  const ui = await api.patch('/settings/ui', { [key]: !app.settings.ui[key] });
  app.settings.ui = ui; applyUi();
}
function applyUi() {
  const ui = app.settings.ui;
  $('#shell').classList.toggle('no-left', !ui.leftPanel);
  $('#shell').classList.toggle('no-right', !ui.rightPanel);
  document.body.classList.toggle('reduced', ui.animations !== 'full');
  for (const c of app.cores) { c.setMode(ui.animations); c.setFps(ui.fpsLimit || 60); }
  renderRail();
}
function winControls() {
  const n = window.viperNative; const wc = $('#win-controls'); clear(wc);
  if (!n?.window) return;
  wc.append(
    h('button.tb-btn', { onclick: () => n.window('minimize'), title: 'Minimise', 'aria-label': 'Minimise' }, icon('min')),
    h('button.tb-btn', { onclick: () => n.window('maximize'), title: 'Maximise', 'aria-label': 'Maximise' }, icon('max')),
    h('button.tb-btn.close', { onclick: () => n.window('close'), title: 'Close', 'aria-label': 'Close' }, icon('x')));
}
function micButton() {
  const b = $('#mic-toggle'); const muted = app.settings.voice.micMuted;
  clear(b).append(icon(muted ? 'micoff' : 'mic'), h('span.lbl', {}, muted ? 'Mic off' : (app.voice.state === 'standby' ? 'Wake word on' : 'Mic ready')));
  b.classList.toggle('muted', muted);
  b.setAttribute('aria-pressed', String(muted));
}
$('#mic-toggle').addEventListener('click', async () => {
  if (!app.settings) return; // still starting up
  app.settings.voice = await api.patch('/settings/voice', { micMuted: !app.settings.voice.micMuted });
  await configureVoice(); micButton();
  toast(app.settings.voice.micMuted ? 'Microphone off' : 'Microphone on', app.settings.voice.micMuted ? 'VIPER cannot hear anything until you turn it back on.' : '');
});
$('#hud-btn').addEventListener('click', () => {
  if (!app.settings) return; if (window.viperNative?.toggleHud) window.viperNative.toggleHud(); else toast('Floating HUD', 'Available in the desktop app.'); });

// ---------------- right rail ----------------
const spark = { cpu: [], mem: [] };
function sparkSvg(arr) {
  const w = 240; const hgt = 34; const n = Math.max(2, arr.length);
  const pts = arr.map((v, i) => `${(i / (n - 1)) * w},${hgt - (Math.max(0, Math.min(100, v)) / 100) * (hgt - 2) - 1}`).join(' ');
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${w} ${hgt}`); svg.setAttribute('preserveAspectRatio', 'none'); svg.setAttribute('class', 'spark');
  svg.innerHTML = `<polyline points="${pts}" fill="none" stroke="white" stroke-opacity=".85" stroke-width="1" vector-effect="non-scaling-stroke"/>`;
  return svg;
}
function renderRail(force) {
  const rail = $('#rail'); if (!app.settings) return;
  if (!force && !rail.getClientRects().length && rail.childElementCount) return; // hidden: skip the work
  if (!app.settings.ui.rightPanel) { clear(rail); return; }
  const w = new Set(app.settings.ui.widgets);
  const s = app.sample; const be = app.settings.backend.active; const hl = app.health[be] || {};
  const now = new Date();
  const blocks = [];
  if (w.has('clock')) blocks.push(h('div.widget.clock', {}, h('b', {}, now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })), h('span', {}, now.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }))));
  if (w.has('system')) blocks.push(h('div.widget.panel', {},
    h('h4', {}, 'This PC', h('span.r', {}, s?.static?.hostname || '')),
    h('div.row', {}, h('div.stat.grow', {}, h('b', {}, s?.cpu ? `${Math.round(s.cpu.pct)}%` : '—'), h('span', {}, 'CPU')), h('div.stat.grow', {}, h('b', {}, s?.mem ? `${Math.round(s.mem.pct)}%` : '—'), h('span', {}, `Memory · ${bytes(s?.mem?.used)}`))),
    sparkSvg(spark.cpu), h('small.mist', {}, s?.temp?.cpu ? `CPU ${Math.round(s.temp.cpu)}°C` : 'CPU temperature not exposed', s?.battery ? ` · battery ${s.battery.pct}%` : '')));
  if (w.has('model')) {
    const roles = app.settings.models; const ai = app.ai || {};
    const ok = ai.stage === 'ready';
    blocks.push(h('div.widget.panel', {}, h('h4', {}, 'AI engine', h('span.r', {}, h(`span.dot${ok ? '.on' : ai.stage === 'error' || ai.stage === 'setup' ? '.warn' : ''}`))),
      h('div', {}, { foundry: 'Foundry Local', ollama: 'Ollama', openai: 'OpenAI-compatible' }[be], ai.model ? ` · ${ai.model}` : ''),
      h('small.mist', { style: { display: 'block' } }, ai.label || (hl.ok ? (roles.chat.model || 'auto-selected model') : (hl.error || 'Not reachable'))),
      ai.stage && ai.stage !== 'ready' && ai.detail ? h('small.mist', { style: { display: 'block' } }, ai.detail) : null,
      ai.stage === 'error' ? h('button.btn.sm', { style: { marginTop: '6px' }, onclick: () => api.post('/ai/startup/retry').catch(toastError) }, 'Retry connection') : null,
      app.lastPerf ? h('small.mist', { style: { display: 'block' } }, `Last reply ${app.lastPerf.tokPerS || '?'} tok/s · first token ${app.lastPerf.ttftMs ?? '?'} ms`) : null));
  }
  if (w.has('network')) blocks.push(h('div.widget.row', {}, icon('wifi'), h('span.grow', {}, s?.online ? 'Internet connected' : s ? 'Offline' : '—'), h('small.mist', {}, s?.net ? `↓${bytes(s.net.rxPerSec)}/s` : '')));
  if (w.has('phone')) {
    const rs = app.status?.remote;
    blocks.push(h('div.widget.row', {}, icon('phone'), h('span.grow', {}, rs?.connected?.length ? `${rs.connected.map((d) => d.name).join(', ')} connected` : rs?.enabled ? 'No phone connected' : 'Phone link off'), h(`span.dot${rs?.connected?.length ? '.on' : ''}`)));
  }
  if (w.has('tasks')) {
    const t = app.tasks.filter((x) => x.state === 'running');
    const ai = [...app.aiTasks.values()];
    blocks.push(h('div.widget', {}, h('h4', {}, 'Active tasks', h('span.r', {}, String(t.length + ai.length))),
      !t.length && !ai.length ? h('small.mist', {}, 'Nothing running.') : null,
      ...ai.map((a) => h('div.notif', {}, h('b', {}, a.label || 'AI request'), h('small', {}, `${a.model} · ${a.tokens || 0} tokens`))),
      ...t.map((x) => h('div.notif', {}, h('b', {}, x.label), x.progress != null ? h('div.progress', {}, h('i', { style: { width: `${Math.round(x.progress * 100)}%` } })) : h('div.progress.indet', {}, h('i'))))));
  }
  if (w.has('notifications')) blocks.push(h('div.widget', {}, h('h4', {}, 'Notifications', h('span.r', {}, h('button.btn.sm.ghost', { onclick: () => app.go('comms', { tab: 'alerts' }) }, 'All'))),
    !app.notifications.length ? h('small.mist', {}, 'No recent notifications.') : null,
    ...app.notifications.slice(0, 5).map((n) => h('div.notif', {}, h('b', {}, n.title), h('small', {}, `${n.body ? n.body.slice(0, 80) + ' · ' : ''}${ago(n.created_at)}`)))));
  if (w.has('plugins') && app.pluginWidgets?.length) for (const pw of app.pluginWidgets) blocks.push(h('div.widget.panel', {}, h('h4', {}, pw.title), ...pw.lines.map((l) => h('div.small', {}, l))));
  clear(rail).append(...blocks);
}
async function loadPluginWidgets() { try { app.pluginWidgets = await api.get('/plugins/widgets'); } catch { app.pluginWidgets = []; } renderRail(); }
setInterval(() => { if (!document.hidden && app.settings?.ui.widgets.includes('plugins')) loadPluginWidgets(); }, 60000);
setInterval(() => { if (!document.hidden) renderRail(); }, 15000);

// ---------------- permission prompts (inverted modal) ----------------
function showConfirm(req) {
  if (app.pending.has(req.id)) return;
  const bar = h('i', { style: { width: '100%' } });
  const total = req.expiresAt - Date.now();
  const timer = setInterval(() => { bar.style.width = `${Math.max(0, (req.expiresAt - Date.now()) / total * 100)}%`; }, 1000);
  const answer = async (approved) => { try { await api.post(`/confirm/${req.id}`, { approved }); } catch (e) { toastError(e); } };
  const m = modal({
    title: req.title, cls: 'confirm', dismissable: false,
    body: h('div', {},
      h('p', {}, h('span.risk', {}, req.risk === 'destructive' ? 'Irreversible / destructive' : 'Needs your approval'), ' ', h('span.mist', {}, `Requested from ${req.origin}`)),
      h('p', {}, req.reason), req.preview ? h('pre', {}, req.preview) : null, h('div.timer-bar', {}, bar)),
    actions: [{ label: 'Deny', onClick: () => answer(false) }, { label: 'Allow once', cls: 'primary', onClick: () => answer(true) }],
    onClose: () => clearInterval(timer),
  });
  app.pending.set(req.id, m);
  app.updateCore();
  if (window.viperNative?.flash) window.viperNative.flash();
}

// ---------------- events ----------------
function wireEvents() {
  api.on('system.sample', (s) => {
    app.sample = { ...s, static: app.sample?.static };
    spark.cpu.push(s.cpu?.pct ?? 0); spark.mem.push(s.mem?.pct ?? 0); if (spark.cpu.length > 60) { spark.cpu.shift(); spark.mem.shift(); }
    // Rebuilding the rail is cheap but not free; refresh it at most every 5 s.
    if (!document.hidden && Date.now() - (app.railAt || 0) > 5000) { app.railAt = Date.now(); renderRail(); }
  });
  api.on('models.health', (hl) => { app.health = hl; app.updateCore(); renderRail(); });
  api.on('ai.startup', (st) => {
    const was = app.ai?.stage; app.ai = st; app.updateCore(); renderRail();
    if (st.stage === 'error' && was !== 'error') toast('AI engine offline', st.detail, 'error', 9000);
    // Startup voice greeting: only after the model has passed its readiness check.
    if (st.stage === 'ready' && st.greeting && !app.greeted) { app.greeted = true; app.voice.speak(st.greeting).catch(() => {}); }
  });
  api.on('models.perf', (p) => { if (p.ok) app.lastPerf = p; });
  api.on('models.recovering', (d) => toast('Inference engine restarting', `${d.backend} stopped responding; VIPER is restarting it.`, 'warn'));
  api.on('models.recovered', (d) => toast('Inference engine recovered', `${d.backend} is back online.`));
  api.on('models.recoveryFailed', (d) => toast('Could not restart the AI engine', `${d.backend}: start it manually or switch backend in Models.`, 'error', 8000));
  api.on('ai.task', (t) => { if (t.state === 'started') app.aiTasks.set(t.id, t); else app.aiTasks.delete(t.id); renderRail(); });
  api.on('tasks.changed', async () => { app.tasks = (await api.get('/tasks').catch(() => ({ tasks: [] }))).tasks; renderRail(); });
  api.on('chat.token', (d) => { if (app.thinking.delete(d.requestId)) app.updateCore(); });
  api.on('chat.tool', (d) => { app.toolsRunning += d.state === 'running' ? 1 : -1; app.toolsRunning = Math.max(0, app.toolsRunning); app.thinking.delete(d.requestId); app.updateCore(); });
  const end = (d) => { app.thinking.delete(d.requestId); app.toolsRunning = 0; app.updateCore(); };
  api.on('chat.cancelled', end);
  app.lateEvent = (e) => { if (e.type === 'chat.token') { app.thinking.delete(e.data.requestId); return; } ({ 'chat.done': onDone, 'chat.error': onErr, 'chat.cancelled': end })[e.type](e.data); };
  const onErr = (d) => { end(d); if (app.voiceRequests.delete(d.requestId)) app.voice.speak(`I ran into a problem: ${d.error}`); };
  const handledDone = new Set();
  const onDone = (d) => {
    end(d);
    if (handledDone.has(d.requestId) && !app.voiceRequests.has(d.requestId)) return;
    handledDone.add(d.requestId); if (handledDone.size > 200) handledDone.delete(handledDone.values().next().value);
    if (d.navigate && d.navigate !== app.mode) app.go(d.navigate);
    if (app.voiceRequests.delete(d.requestId) || (d.speak && app.mode === 'voice')) {
      if (!d.silent && d.message?.content && app.settings.voice.speakReplies) app.voice.speak(d.message.content).then(() => app.voice.listenFollowUp());
      else app.voice.listenFollowUp();
    }
  };
  api.on('chat.done', onDone);
  api.on('chat.error', onErr);
  api.on('confirm.request', showConfirm);
  api.on('confirm.closed', (d) => { const m = app.pending.get(d.id); if (m) { m.close(); app.pending.delete(d.id); app.updateCore(); if (d.timeout) toast('Request expired', 'An action was not approved in time and was cancelled.', 'warn'); } });
  api.on('ui.navigate', (d) => app.go(d.mode, d));
  api.on('voice.stop', () => app.voice.stopSpeaking('command'));
  api.on('voice.speak', (d) => app.voice.speak(d.text));
  api.on('notification', (n) => {
    app.notifications.unshift(n); app.notifications = app.notifications.slice(0, 30);
    if (!n.suppressed?.length) toast(`VIPER: ${n.title}`, n.body, n.priority === 'urgent' || n.priority === 'high' ? 'warn' : 'info', 6000);
    if (n.speak && app.settings.voice.speakReplies && !app.settings.voice.micMuted) app.voice.speak(`${n.title}. ${n.body || ''}`);
    renderRail();
  });
  api.on('system.alert', () => { app.warningUntil = Date.now() + 6000; app.updateCore(); setTimeout(() => app.updateCore(), 6100); });
  api.on('settings.changed', async (d) => { app.settings[d.section] = d.value; if (d.section === 'ui') applyUi(); if (d.section === 'performance') for (const c of app.cores) c.setAdaptive(d.value.adaptiveQuality !== false); if (d.section === 'voice') { await configureVoice(); micButton(); } });
  api.on('remote.changed', async () => { app.status = await api.get('/status').catch(() => app.status); renderRail(); });
  api.on('plugins.changed', () => { loadPluginPages(); loadPluginWidgets(); });
  api.on('ws.close', () => { app.health = {}; app.updateCore(); });
  api.on('ws.open', async () => { app.health = await api.post('/models/health').catch(() => ({})); app.ai = await api.get('/ai/startup').catch(() => app.ai); app.updateCore(); renderRail(); });

  // voice → core + commands
  const v = app.voice;
  v.addEventListener('level', (e) => { for (const c of app.cores) if (!v.speaking || !c.analyser) c.setLevel(e.detail); });
  v.addEventListener('analyser', (e) => { for (const c of app.cores) c.setAnalyser(e.detail); });
  v.addEventListener('state', () => { app.updateCore(); micButton(); document.dispatchEvent(new CustomEvent('viper:voice', { detail: { state: v.state } })); });
  v.addEventListener('speaking', () => app.updateCore());
  v.addEventListener('wake', () => { if (window.viperNative?.wake) window.viperNative.wake(); });
  v.addEventListener('command', async (e) => {
    document.dispatchEvent(new CustomEvent('viper:transcript', { detail: { text: e.detail.text, final: true } }));
    try { await app.send(e.detail.text, { voice: true, conversationId: app.voiceConversation, mode: 'chat' }).then((r) => { app.voiceConversation = r.conversationId; }); } catch (err) { toastError(err); }
  });
  v.addEventListener('transcribing', () => document.dispatchEvent(new CustomEvent('viper:transcript', { detail: { text: 'Transcribing…', final: false } })));
  v.addEventListener('error', (e) => { if (!/aborted|Permission/i.test(e.detail?.message)) toast('Voice', e.detail?.message || String(e.detail), 'warn'); });

  document.addEventListener('visibilitychange', () => api.post('/system/visibility', { visible: !document.hidden }).catch(() => {}));
  window.addEventListener('popstate', () => { const [m, tab] = (location.hash.replace('#/', '') || 'home').split(':'); app.render(m, tab ? { tab } : null); });
  document.addEventListener('viper:nav', () => markActive());
  // push-to-talk hotkey (desktop): hold Ctrl+Space inside the app
  document.addEventListener('keydown', (e) => { if (e.code === 'Space' && e.ctrlKey && !e.repeat && !app.pttDown) { app.pttDown = true; app.voice.pttStart().catch(toastError); e.preventDefault(); } });
  document.addEventListener('keyup', (e) => { if (e.code === 'Space' && app.pttDown) { app.pttDown = false; app.voice.pttStop(); } });
  window.viperNative?.onPtt?.((down) => (down ? app.voice.pttStart() : app.voice.pttStop()));
}

async function configureVoice() {
  try {
    const st = await api.get('/voice/status');
    app.voiceStatus = st;
    await app.voice.configure(app.settings.voice, st);
  } catch (e) {
    if (app.settings.voice.wakeEnabled) toast('Wake word unavailable', e.message, 'warn');
  }
}
async function loadPluginPages() {
  try { app.pluginPages = (await api.get('/plugins/pages')).pages || []; } catch { app.pluginPages = []; }
  buildNav();
}

// ---------------- boot ----------------
async function boot() {
  if (!api.token) { document.body.append(h('div.empty', { style: { margin: '20vh auto', maxWidth: '420px' } }, h('b', {}, 'Missing access token'), 'Open VIPER from the desktop app, or use the URL printed by the VIPER server.')); return; }
  api.connect();
  winControls();
  try {
    [app.settings, app.status, app.ai] = await Promise.all([api.get('/settings'), api.get('/status'), api.get('/ai/startup').catch(() => null)]);
    app.health = app.status.health || {};
  } catch (e) { toastError(e, 'VIPER core is not responding'); return; }
  buildNav(); applyUi(); micButton(); wireEvents();
  api.get('/system/snapshot').then((s) => { app.sample = s; renderRail(); }).catch(() => {});
  api.get('/notifications').then((n) => { app.notifications = n; renderRail(); }).catch(() => {});
  api.get('/confirm/pending').then((list) => list.forEach(showConfirm)).catch(() => {});
  loadPluginPages(); loadPluginWidgets();
  configureVoice();
  if (!app.settings.app.setupComplete) {
    const { runSetup } = await import('./pages/setup.js');
    await runSetup(app);
  }
  { const [m, tab] = (location.hash.replace('#/', '') || 'home').split(':'); app.go(m, tab ? { tab } : null); }
  app.updateCore();
  // Fetch and compile every page module while the app is idle so switching pages is instant.
  const idle = window.requestIdleCallback || ((f) => setTimeout(f, 1500));
  idle(() => { for (const [m] of NAV) import(`./pages/${m}.js`).catch(() => {}); }, { timeout: 4000 });
}
boot();
