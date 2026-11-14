// First-run setup wizard. Every step shows real results; optional steps can be skipped.
import { h, clear, icon, btn, busy, toast, toastError, field, toggle, progress, bytes, meter } from '../ui.js';
import { Core } from '../core.js';
import { Voice } from '../voice.js';

const STEPS = ['Welcome', 'Scan hardware', 'Choose AI engine', 'Set up the engine', 'Download a chat model', 'Test the connection', 'Voice', 'Personality', 'Notifications', 'Pair a phone', 'Privacy', 'Launch'];

export function runSetup(app) {
  return new Promise((resolve) => {
    const { api } = app;
    let step = Math.min(app.settings.app.setupStep || 0, STEPS.length - 1);
    const state = { hw: null, rec: null };
    const stepsEl = h('div.steps');
    const pane = h('div.pane');
    const root = h('div.wizard', { role: 'dialog', 'aria-label': 'VIPER setup' }, stepsEl, pane);
    document.body.append(root);
    let cleanupStep = null;

    const go = async (n) => {
      cleanupStep?.(); cleanupStep = null;
      step = n; api.patch('/settings/app', { setupStep: n }).catch(() => {});
      clear(stepsEl).append(h('div', { style: { marginBottom: '18px' } }, h('div.brand', {}, 'VIPER'), h('small.mist', {}, 'First-time setup')),
        ...STEPS.map((s, i) => h(`div.s${i < n ? '.done' : i === n ? '.cur' : ''}`, {}, h('i', {}, i < n ? '✓' : String(i + 1)), s)));
      clear(pane);
      const body = h('div.body'); const nav = h('div.nav');
      pane.append(body, nav);
      const next = (label = 'Continue', cls = 'primary') => btn(label, () => go(n + 1), { cls });
      const back = n > 0 ? btn('Back', () => go(n - 1), { cls: 'ghost' }) : null;
      const skip = (label = 'Skip for now') => btn(label, () => go(n + 1), { cls: 'ghost' });
      try { cleanupStep = await RENDER[n]({ body, nav, next, back, skip, state, app, api, finish }); } catch (e) { body.append(h('p', {}, `This step failed: ${e.message}`)); nav.append(back, skip('Continue anyway')); }
    };
    async function finish() {
      cleanupStep?.();
      app.settings.app = await api.post('/setup/complete');
      root.style.transition = 'opacity .5s'; root.style.opacity = '0';
      setTimeout(() => { root.remove(); resolve(); }, 500);
    }
    go(step);
  });
}

const RENDER = [
  // 0 Welcome
  async ({ body, nav, next }) => {
    const c = h('canvas.core'); const wrap = h('div.core-wrap', { style: { width: '260px', height: '260px', margin: '0 0 18px' } }, c);
    body.append(wrap, h('h1', {}, 'Welcome to VIPER.'), h('p.lede', {}, 'A personal AI that runs on this computer. Conversations, memory and files stay on your PC; nothing is sent to a cloud service unless you switch on a feature that needs one, and VIPER will say when that happens.'),
      h('p.ink2', {}, 'Setup takes a few minutes. It checks your hardware, installs a local AI engine and a model that suits it, and lets you choose how VIPER sounds and behaves. Optional steps can be skipped and revisited in Settings.'));
    nav.append(next('Begin setup'));
    const core = new Core(c); core.setMode('full'); core.start(); setTimeout(() => core.setState('thinking'), 300); setTimeout(() => core.setState('idle'), 1800);
    return () => core.destroy();
  },
  // 1 Hardware
  async ({ body, nav, next, back, state, api }) => {
    body.append(h('h1', {}, 'Scanning hardware'), h('p.lede', {}, 'VIPER sizes its AI models to your processor, memory and graphics card.'));
    const box = h('div.panel', {}, progress(null)); body.append(box); nav.append(back);
    state.hw = await api.get('/hardware?refresh=1'); state.rec = await api.get('/recommendation');
    const hw = state.hw;
    clear(box).append(h('dl.kv', {},
      h('dt', {}, 'Operating system'), h('dd', {}, `${hw.os}${hw.windows11 ? ' (Windows 11)' : ''}`),
      h('dt', {}, 'Processor'), h('dd', {}, `${hw.cpu.model} · ${hw.cpu.cores} threads`),
      h('dt', {}, 'Memory'), h('dd', {}, `${hw.ramGB} GB`),
      h('dt', {}, 'Graphics'), h('dd', {}, hw.gpu ? `${hw.gpu.model}${hw.gpu.vramGB ? ` · ${hw.gpu.vramGB} GB` : ' · shared memory'}` : 'None detected')),
    h('p', { style: { marginTop: '12px' } }, `This PC suits ${state.rec.tier === 'standard' ? '7–8 billion parameter models' : state.rec.tier === 'light' ? '3–4 billion parameter models' : 'small 0.5–1.5 billion parameter models'}. Expected speed: ${state.rec.expectedSpeed}.`),
    ...state.rec.notes.map((n) => h('p.small.mist', {}, n)));
    nav.append(next());
  },
  // 2 Choose backend
  async ({ body, nav, next, back, state, app, api }) => {
    const win11 = state.hw?.windows11;
    let pick = app.settings.backend.active === 'ollama' && win11 && !app.settings.app.setupStep ? 'foundry' : app.settings.backend.active;
    const health = await api.post('/models/health');
    body.append(h('h1', {}, 'Choose an AI engine'), h('p.lede', {}, 'Both are free and run entirely on this PC. You can switch at any time without restarting VIPER.'));
    const opts = [
      ['foundry', 'Microsoft Foundry Local', `${win11 ? 'Recommended for Windows 11.' : 'Best on Windows 11.'} Hardware-optimised models that use your CPU, GPU or NPU automatically.`],
      ['ollama', 'Ollama', 'Works on Windows 10 and 11. Wider model library including vision and embedding models used by Vision and File Intelligence.'],
      ['openai', 'Another local server', 'Already running llama.cpp, LM Studio or similar? Point VIPER at its OpenAI-compatible address.'],
    ];
    const list = h('div.col');
    const draw = () => { clear(list); for (const [id, t, d] of opts) list.append(h(`label.choice${pick === id ? '.on' : ''}`, {}, h('input', { type: 'radio', name: 'be', checked: pick === id, onchange: () => { pick = id; draw(); } }), h('div', {}, h('b', { style: { fontWeight: 500 } }, t, health[id]?.ok ? h('span.tag.on', { style: { marginLeft: '8px' } }, 'Detected') : null), h('p.small.mist', {}, d)))); };
    draw(); body.append(list, h('p.small.mist', { style: { marginTop: '10px' } }, 'Tip: many people use Foundry Local for chat and Ollama alongside it for vision and embeddings.'));
    nav.append(back, btn('Continue', async () => { await api.post('/backend/active', { backend: pick }); app.settings.backend.active = pick; next().click(); }, { cls: 'primary' }));
  },
  // 3 Engine setup
  async ({ body, nav, next, back, skip, app, api }) => {
    const be = app.settings.backend.active;
    const name = { foundry: 'Foundry Local', ollama: 'Ollama', openai: 'your local server' }[be];
    body.append(h('h1', {}, `Set up ${name}`));
    const status = h('div.panel'); body.append(status);
    const check = async () => {
      clear(status).append(progress(null));
      const hl = (await api.post('/models/health'))[be];
      clear(status);
      if (hl.ok) { status.append(h('p', {}, icon('check'), ` ${name} is running at ${hl.url || 'its default address'}.`)); nextBtn.disabled = false; return; }
      status.append(h('p', {}, `${name} isn't reachable yet: ${hl.error || 'no response'}.`));
      if (be === 'foundry') {
        status.append(h('p.small.mist', {}, hl.cliInstalled ? 'The Foundry Local CLI is installed but its service is stopped.' : 'Foundry Local is installed with the official Windows Package Manager command: winget install Microsoft.FoundryLocal'),
          h('div.row', {}, hl.cliInstalled ? btn('Start the service', async (e) => busy(e.currentTarget, async () => { try { await api.post('/backend/foundry/start'); } catch (er) { toastError(er); } check(); }), { cls: 'primary' }) : btn('Install Foundry Local', async () => { try { const r = await api.post('/backend/foundry/install'); toast('Installer', r.message); } catch (er) { toastError(er); } }, { cls: 'primary' }), btn('Check again', check)));
      } else if (be === 'ollama') {
        status.append(h('p.small.mist', {}, 'Install Ollama from ollama.com (free). It runs in the background after installation.'), h('div.row', {}, btn('Open the Ollama download page', () => api.post('/backend/ollama/install'), { cls: 'primary' }), btn('Check again', check)));
      } else {
        const url = h('input.input', { value: app.settings.backend.openai.url });
        status.append(field('Server address (OpenAI-compatible, ending in /v1)', url), h('div.row', { style: { marginTop: '8px' } }, btn('Save and check', async () => { await api.patch('/settings/backend', { openai: { url: url.value } }); check(); }, { cls: 'primary' })));
      }
    };
    const nextBtn = next(); nextBtn.disabled = true;
    nav.append(back, skip('Skip — I\'ll set it up later'), nextBtn);
    check();
  },
  // 4 Download model
  async ({ body, nav, next, back, skip, state, app, api }) => {
    const be = app.settings.backend.active;
    body.append(h('h1', {}, 'Download a chat model'), h('p.lede', {}, 'Models are downloaded once and then work offline.'));
    const box = h('div.col'); body.append(box);
    const installed = (await api.get('/models?refresh=1').catch(() => [])).filter((m) => m.backend === be && m.capabilities?.includes('chat'));
    const rec = state.rec || await api.get('/recommendation');
    const nextBtn = next(); nextBtn.disabled = !installed.length;
    if (installed.length) box.append(h('p', {}, icon('check'), ` Already installed: ${installed.map((m) => m.id).join(', ')}`));
    if (be === 'openai') { box.append(h('p.mist', {}, 'Models are managed by your own server.')); nextBtn.disabled = false; }
    else {
      const cat = await api.get(`/models/catalog?backend=${be}`).catch(() => ({ recommended: [] }));
      let pick = rec.chat;
      const choices = cat.recommended.filter((m) => m.roles.includes('chat')).slice(0, 7);
      const list = h('div.col');
      const draw = () => { clear(list); for (const m of choices) list.append(h(`label.choice${pick === m.id ? '.on' : ''}`, {}, h('input', { type: 'radio', name: 'm', checked: pick === m.id, onchange: () => { pick = m.id; draw(); } }), h('div.grow', {}, h('b', { style: { fontWeight: 500 } }, m.id, m.id === rec.chat ? h('span.tag.on', { style: { marginLeft: '8px' } }, 'Recommended') : null, m.installed ? h('span.tag', { style: { marginLeft: '6px' } }, 'Installed') : null), h('p.small.mist', {}, `${m.sizeGB} GB download · needs ${m.minRamGB} GB RAM · ${m.note}`)))); };
      draw(); box.append(list);
      const prog = h('div'); box.append(prog);
      const dlBtn = btn('Download selected model', async () => {
        dlBtn.disabled = true;
        try { await api.post('/models/pull', { backend: be, model: pick }); } catch (e) { toastError(e); dlBtn.disabled = false; }
      }, { cls: 'primary', ico: 'download' });
      box.append(h('div.row', {}, dlBtn));
      const off = api.on('models.download', async (d) => {
        clear(prog).append(h('p.small', {}, d.status === 'downloading' ? `${d.detail || 'Downloading'} — ${d.total ? `${bytes(d.completed)} of ${bytes(d.total)}` : ''}` : d.status === 'done' ? 'Installed.' : `Failed: ${d.error}`), d.status === 'downloading' ? progress(d.total ? d.completed / d.total : null) : null);
        if (d.status === 'done') { app.settings.models = await api.post('/models/role', { role: 'chat', backend: be, model: (await api.get('/models?refresh=1')).find((m) => m.id.startsWith(d.model))?.id || d.model }); nextBtn.disabled = false; }
        if (d.status === 'error') dlBtn.disabled = false;
      });
      nav.append(back, skip(), nextBtn);
      return off;
    }
    nav.append(back, skip(), nextBtn);
  },
  // 5 Test
  async ({ body, nav, next, back, app, api }) => {
    body.append(h('h1', {}, 'Testing the AI connection'), h('p.lede', {}, 'VIPER sends a short prompt to the local model and measures the reply.'));
    const box = h('div.panel', {}, progress(null)); body.append(box);
    nav.append(back);
    const run = async () => {
      clear(box).append(progress(null));
      try {
        const r = await api.post('/backend/test', { backend: app.settings.backend.active });
        clear(box).append(r.ok ? h('div', {}, h('p', {}, icon('check'), ` ${r.model} replied: “${r.reply}”`), h('p.small.mist', {}, `Round trip ${r.ms} ms${r.perf?.tokPerS ? ` · ${r.perf.tokPerS} tokens/s` : ''}. The first reply is slower while the model loads into memory.`))
          : h('div', {}, h('p', {}, `The test did not pass at the ${r.stage} stage: ${r.error || 'no response'}.`), h('p.small.mist', {}, 'You can continue; chat will work once the engine and a model are available.')));
      } catch (e) { clear(box).append(h('p', {}, `Test failed: ${e.message}`)); }
      box.append(btn('Run again', run, { cls: 'sm', ico: 'refresh' }));
    };
    run(); nav.append(next());
  },
  // 6 Voice
  async ({ body, nav, next, back, skip, app, api }) => {
    body.append(h('h1', {}, 'Voice'), h('p.lede', {}, 'Speech recognition (whisper.cpp) and the speaking voice (Piper) run locally. Downloads are about 200 MB in total. Skip this to use typing only — voice can be added later in Voice settings.'));
    const st = h('div.col'); body.append(st);
    const levelBar = h('div'); const devSel = h('div');
    const draw = async () => {
      const s = await api.get('/voice/status');
      clear(st);
      const item = (ok, label, action) => h('div.check-line', {}, h('span.st', {}, ok ? '✓' : '·'), h('span.grow', {}, label), ok ? null : action);
      const inst = (kind, id) => btn('Install', async (e) => { e.currentTarget.disabled = true; try { await api.post('/voice/install', { kind, id }); } catch (er) { toastError(er); } }, { cls: 'sm' });
      st.append(h('div.panel', {},
        item(s.stt.whisperInstalled, 'Speech recognition engine (whisper.cpp, 9 MB)', s.stt.whisperAvailableForPlatform ? inst('engine', 'whisper') : h('small.mist', {}, 'Windows only')),
        item(s.stt.models.find((m) => m.id === app.settings.voice.sttModel)?.installed, `Speech model ${app.settings.voice.sttModel} (${s.stt.models.find((m) => m.id === app.settings.voice.sttModel)?.sizeMB} MB)`, inst('stt-model', app.settings.voice.sttModel)),
        item(s.tts.piperInstalled, 'Speaking engine (Piper, 25 MB)', inst('engine', 'piper')),
        item(s.tts.voices.find((v) => v.id === app.settings.voice.piperVoice)?.installed, `British voice: ${s.tts.voices.find((v) => v.id === app.settings.voice.piperVoice)?.label}`, inst('voice', app.settings.voice.piperVoice)),
        ...s.installs.filter((i) => i.state === 'running').map((i) => h('div', {}, h('small.mist', {}, i.label), progress(i.total ? i.received / i.total : null)))));
      st.append(h('div.panel', {}, h('h3', {}, 'Microphone check'), devSel, levelBar,
        h('div.row', { style: { marginTop: '8px' } }, btn('Test microphone', testMic, { cls: 'sm', ico: 'mic' }), btn('Test voice', () => app.voice.speak('Online and operational. All local systems are available.'), { cls: 'sm', ico: 'play' }))));
    };
    let v = null;
    const testMic = async () => {
      v?.stopMic(); v = new Voice(); v.cfg = app.settings.voice;
      try {
        await v.startMic();
        const m = h('div.meter', {}, h('i')); clear(levelBar).append(h('small.mist', {}, 'Speak now — the bar should move.'), m);
        v.addEventListener('level', (e) => { m.firstChild.style.width = `${Math.round(e.detail * 100)}%`; });
        setTimeout(() => { v?.stopMic(); clear(levelBar).append(h('small.mist', {}, 'Microphone test finished.')); }, 6000);
      } catch (e) { clear(levelBar).append(h('p.small', {}, `Microphone unavailable: ${e.message}`)); }
    };
    const devs = await Voice.devices();
    clear(devSel).append(field('Microphone', h('select.input', { onchange: (e) => api.patch('/settings/voice', { inputDevice: e.target.value }) }, h('option', { value: '' }, 'System default'), ...devs.inputs.map((d) => h('option', { value: d.deviceId, selected: d.deviceId === app.settings.voice.inputDevice }, d.label || 'Microphone')))));
    await draw();
    const off = api.on('voice.install', () => draw());
    nav.append(back, skip(), next());
    return () => { off(); v?.stopMic(); };
  },
  // 7 Personality
  async ({ body, nav, next, back, app, api }) => {
    const p = { ...app.settings.personality };
    body.append(h('h1', {}, 'Personality'), h('p.lede', {}, 'Shape how VIPER talks to you. Everything here can be changed later.'));
    const slider = (key, label, lo, hi) => h('div', {}, h('div.row', {}, h('span.grow', {}, label), h('small.mist', {}, `${lo} ↔ ${hi}`)), h('input', { type: 'range', min: 0, max: 1, step: 0.05, value: p[key], oninput: (e) => { p[key] = Number(e.target.value); } }));
    body.append(h('div.grid.g2', {}, field('Your name (optional)', h('input.input', { value: p.userName, oninput: (e) => { p.userName = e.target.value; } })), field('How VIPER addresses you', h('input.input', { value: p.address, placeholder: 'e.g. sir, ma\'am, boss — or leave blank', oninput: (e) => { p.address = e.target.value; } }))),
      h('div.col', { style: { marginTop: '14px' } }, slider('humour', 'Humour', 'none', 'dry wit'), slider('formality', 'Formality', 'casual', 'formal'), slider('proactivity', 'Proactivity', 'only when asked', 'suggests next steps')),
      h('div.row', { style: { marginTop: '14px' } }, h('span', {}, 'Replies'), h('div.seg', {}, ...[['concise', 'Concise'], ['detailed', 'Detailed']].map(([v, l]) => h(`button${p.verbosity === v ? '.on' : ''}`, { onclick: (e) => { p.verbosity = v; e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b === e.currentTarget)); } }, l)))));
    nav.append(back, btn('Continue', async () => { app.settings.personality = await api.patch('/settings/personality', p); next().click(); }, { cls: 'primary' }));
  },
  // 8 Notifications
  async ({ body, nav, next, back, skip, api }) => {
    body.append(h('h1', {}, 'Notifications'), h('p.lede', {}, 'VIPER can alert you on the desktop and on your paired phone. Email and SMS need an account you configure yourself in Communications; VIPER never sends external messages until you set them up.'));
    const res = h('p.small.mist');
    body.append(h('div.panel', {}, h('div.row', {}, h('span.grow', {}, 'Send a test desktop notification'), btn('Send test', async () => { const r = await api.post('/notifications/test', { channels: ['desktop'], title: 'VIPER test', body: 'Desktop notifications are working.' }); res.textContent = r.results.desktop?.ok ? 'Delivered.' : `Not delivered: ${r.results.desktop?.error || r.suppressed.join(', ')}`; }, { cls: 'sm' })), res));
    nav.append(back, skip(), next());
  },
  // 9 Pair phone
  async ({ body, nav, next, back, skip, app, api }) => {
    body.append(h('h1', {}, 'Pair VIPER Mobile'), h('p.lede', {}, 'Install the VIPER Mobile app on your Android phone and scan the code. Pairing uses a one-time token that expires after five minutes, and an encrypted connection pinned to this PC.'));
    const box = h('div.panel'); body.append(box);
    try {
      const pr = await api.post('/remote/pairing');
      box.append(h('div.row', { style: { alignItems: 'flex-start', gap: '20px' } }, h('div.qr', {}, h('img', { src: pr.qr, alt: 'Pairing QR code' })),
        h('div', {}, h('p', {}, `Address: ${pr.host}:${pr.port}`), h('p.small.mist', {}, `Code expires ${new Date(pr.expiresAt).toLocaleTimeString()}. Your phone must be on the same Wi-Fi network, or connected through your own VPN.`), h('p.small.mist', {}, `Certificate fingerprint ${pr.fingerprint.slice(0, 23)}…`))));
      const off = api.on('remote.paired', (d) => { toast('Phone paired', d.name); next().click(); });
      nav.append(back, skip(), next());
      return off;
    } catch (e) { box.append(h('p', {}, `Phone link unavailable: ${e.message}`)); nav.append(back, skip('Continue')); }
  },
  // 10 Privacy
  async ({ body, nav, next, back, app, api }) => {
    const pv = { ...app.settings.privacy }; const pr = { ...app.settings.proactive };
    body.append(h('h1', {}, 'Privacy'), h('p.lede', {}, 'Defaults are private. Turn on only what you want.'));
    const line = (label, desc, val, set) => h('div.li', {}, h('div.t', {}, h('b', {}, label), h('small', { style: { whiteSpace: 'normal' } }, desc)), toggle(val, set, label));
    body.append(h('div.panel', {}, h('div.list', {},
      line('Web access', 'Allow Research mode and the assistant to search the web and fetch pages. Off means fully offline answers from the local model.', pv.webAccess, (v) => { pv.webAccess = v; }),
      line('Save voice transcripts', 'Keep a local log of what you said and what VIPER replied.', pv.saveTranscripts, (v) => { pv.saveTranscripts = v; }),
      line('Temporary memory', 'New memories are forgotten when VIPER closes.', pv.temporaryMemory, (v) => { pv.temporaryMemory = v; }),
      line('Proactive assistant', 'Let VIPER warn you about low disk space, high memory and failed automations.', pr.enabled, (v) => { pr.enabled = v; }))),
    h('p.small.mist', { style: { marginTop: '10px' } }, `VIPER can only search and read files inside: ${pv.allowedFolders.join(', ')}. Change this in Settings → Privacy.`));
    nav.append(back, btn('Continue', async () => { app.settings.privacy = await api.patch('/settings/privacy', pv); app.settings.proactive = await api.patch('/settings/proactive', pr); next().click(); }, { cls: 'primary' }));
  },
  // 11 Launch
  async ({ body, nav, back, finish }) => {
    body.append(h('h1', {}, 'VIPER is ready.'), h('p.lede', {}, 'Try saying or typing “VIPER, are you online?”. Hold Ctrl+Space anywhere in the app to talk, or open the floating HUD with Ctrl+Shift+Space.'));
    nav.append(back, btn('Launch VIPER', finish, { cls: 'primary', ico: 'play' }));
  },
];
