import { h, clear, icon, btn, busy, toast, toastError, field, toggle, select, ask, prompt, when, download } from '../ui.js';

const TABS = [['general', 'General'], ['personality', 'Personality'], ['privacy', 'Privacy & permissions'], ['performance', 'Performance'], ['proactive', 'Proactive assistant'], ['activity', 'Activity log'], ['about', 'About']];
const WIDGETS = [['clock', 'Date and time'], ['system', 'PC status'], ['model', 'AI engine'], ['network', 'Internet'], ['phone', 'Connected phone'], ['tasks', 'Active tasks'], ['notifications', 'Notifications'], ['plugins', 'Plugin widgets']];

export async function render(view, { app, api, params }) {
  let tab = params?.tab || 'general';
  const tabs = h('div.tabs', { role: 'tablist' }); const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Settings'), h('div.sub', {}, 'Changes apply immediately.'))), tabs, body);
  const save = async (section, patch) => { try { app.settings[section] = await api.patch(`/settings/${section}`, patch); } catch (e) { toastError(e); } };
  const row = (label, desc, control) => h('div.li', {}, h('div.t', {}, h('b', {}, label), desc ? h('small', { style: { whiteSpace: 'normal' } }, desc) : null), control);

  const draw = async () => {
    clear(tabs).append(...TABS.map(([id, l]) => h(`button${tab === id ? '.on' : ''}`, { role: 'tab', 'aria-selected': String(tab === id), onclick: () => { tab = id; draw(); } }, l)));
    clear(body);
    const s = app.settings;
    if (tab === 'general') {
      const ui = s.ui;
      body.append(h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, 'Startup and window'), h('div.list', {},
          row('Launch VIPER when Windows starts', null, toggle(ui.launchAtStartup, (v) => save('ui', { launchAtStartup: v }))),
          row('Start minimised to the tray', null, toggle(ui.startMinimized, (v) => save('ui', { startMinimized: v }))),
          row('Closing the window keeps VIPER running in the tray', 'Wake word, reminders and automations keep working.', toggle(ui.closeToTray, (v) => save('ui', { closeToTray: v }))),
          row('Show the floating HUD on start', null, toggle(ui.showHudOnStart, (v) => save('ui', { showHudOnStart: v }))))),
        h('div.panel', {}, h('h3', {}, 'Floating HUD'), h('div.col', {},
          field('Global shortcut', h('input.input', { value: ui.hudShortcut, onchange: (e) => save('ui', { hudShortcut: e.target.value.trim() }) }), 'Electron accelerator format, e.g. CommandOrControl+Shift+Space'),
          field(`Opacity (${Math.round(ui.hudOpacity * 100)}%)`, h('input', { type: 'range', min: 0.4, max: 1, step: 0.02, value: ui.hudOpacity, onchange: (e) => save('ui', { hudOpacity: Number(e.target.value) }) })),
          row('Compact HUD', 'Shows only the core and a command box.', toggle(ui.hudCompact, (v) => save('ui', { hudCompact: v }))))),
        h('div.panel', {}, h('h3', {}, 'Animation'), h('p.small.mist', {}, 'Reduced lowers the frame rate and removes transitions; Off draws the core as a still image. Animation pauses automatically while VIPER is minimised.'),
          select([['full', 'Full (60 fps)'], ['reduced', 'Reduced (24 fps)'], ['off', 'Off']], ui.animations, (v) => save('ui', { animations: v }))),
        h('div.panel', {}, h('h3', {}, 'Dashboard panels'), h('div.list', {},
          row('Show the left sidebar labels', null, toggle(ui.leftPanel, (v) => save('ui', { leftPanel: v }))),
          row('Show the status panel', null, toggle(ui.rightPanel, (v) => save('ui', { rightPanel: v }))),
          ...WIDGETS.map(([id, l]) => row(l, null, toggle(ui.widgets.includes(id), (v) => save('ui', { widgets: v ? [...new Set([...app.settings.ui.widgets, id])] : app.settings.ui.widgets.filter((x) => x !== id) }))))))));
    }
    if (tab === 'personality') {
      const p = s.personality;
      const slider = (key, label, lo, hi) => h('div', {}, h('div.row', {}, h('span.grow', {}, label), h('small.mist', {}, `${lo} ↔ ${hi}`)), h('input', { type: 'range', min: 0, max: 1, step: 0.05, value: p[key], onchange: (e) => save('personality', { [key]: Number(e.target.value) }) }));
      body.append(h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, 'Identity'), h('div.col', {},
          field('Assistant name', h('input.input', { value: p.name, onchange: (e) => save('personality', { name: e.target.value || 'VIPER' }) })),
          field('Your name', h('input.input', { value: p.userName, onchange: (e) => save('personality', { userName: e.target.value }) })),
          field('Form of address', h('input.input', { value: p.address, placeholder: 'sir', onchange: (e) => save('personality', { address: e.target.value }) })),
          field('Reply length', select([['concise', 'Concise'], ['detailed', 'Detailed']], p.verbosity, (v) => save('personality', { verbosity: v }))))),
        h('div.panel', {}, h('h3', {}, 'Character'), h('div.col', {}, slider('humour', 'Humour', 'none', 'dry wit'), slider('formality', 'Formality', 'casual', 'formal'), slider('proactivity', 'Proactivity', 'only when asked', 'suggests next steps'),
          field('Extra instructions', h('textarea.input', { rows: 4, placeholder: 'e.g. Use metric units. Prefer British spelling.', onchange: (e) => save('personality', { customInstructions: e.target.value }) }, p.customInstructions)))),
        h('div.panel', {}, h('h3', {}, 'Voice'), h('p.small.mist', {}, 'Voice selection, speaking rate and wake words live in the Voice page.'), btn('Open Voice settings', () => app.go('voice'), { cls: 'sm' }))));
    }
    if (tab === 'privacy') {
      const info = await api.get('/permissions/info');
      const perms = s.permissions;
      const permList = h('div.list');
      for (const [cat, desc] of Object.entries(info)) permList.append(row(cat, desc, h('div.seg', {}, ...['allow', 'ask', 'deny'].map((m) => h(`button${perms[cat] === m ? '.on' : ''}`, { onclick: async () => { await save('permissions', { [cat]: m }); draw(); } }, m === 'allow' ? 'Allow' : m === 'ask' ? 'Ask' : 'Deny')))));
      const folders = h('div.list');
      for (const f of s.privacy.allowedFolders) folders.append(h('div.li', {}, icon('folder'), h('div.t', {}, h('b', {}, f)), btn('', async () => { await save('privacy', { allowedFolders: s.privacy.allowedFolders.filter((x) => x !== f) }); draw(); }, { cls: 'sm ghost icon', ico: 'x', title: 'Remove' })));
      const scripts = h('div.list');
      for (const sc of s.approvedScripts) scripts.append(h('div.li', {}, icon('terminal'), h('div.t', {}, h('b', {}, sc.name), h('small', {}, `${sc.path} ${(sc.args || []).join(' ')}`)), btn('', async () => { app.settings.approvedScripts = await api.patch('/settings/approvedScripts', s.approvedScripts.filter((x) => x !== sc)); draw(); }, { cls: 'sm ghost icon', ico: 'trash', title: 'Remove' })));
      body.append(h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, 'Data and privacy'), h('div.list', {},
          row('Web access', 'Research and the assistant may search the web and download pages. Web content is always treated as untrusted.', toggle(s.privacy.webAccess, (v) => save('privacy', { webAccess: v }))),
          row('Save voice transcripts', null, toggle(s.privacy.saveTranscripts, (v) => save('privacy', { saveTranscripts: v }))),
          row('Temporary memory mode', 'New memories are kept in RAM only.', toggle(s.privacy.temporaryMemory, (v) => save('privacy', { temporaryMemory: v }))),
          row('Camera', 'Allow Vision mode to use the webcam when you start it.', toggle(s.privacy.cameraEnabled, (v) => save('privacy', { cameraEnabled: v }))))),
        h('div.panel', {}, h('h3', {}, 'Allowed folders'), h('p.small.mist', {}, 'File tools, search, automations and File Intelligence can only touch these folders.'), folders,
          h('div.row', { style: { marginTop: '8px' } }, btn('Add folder', async () => {
            const p = window.viperNative?.pickFolder ? await window.viperNative.pickFolder() : await prompt('Add allowed folder', { label: 'Full folder path' });
            if (p) { await save('privacy', { allowedFolders: [...new Set([...s.privacy.allowedFolders, p])] }); draw(); }
          }, { cls: 'sm', ico: 'plus' }))),
        h('div.panel', { style: { gridColumn: '1 / -1' } }, h('h3', {}, 'Permissions'), h('p.small.mist', {}, 'Ask shows a confirmation for each action. Destructive actions are always confirmed, and any action following web, email or document content is confirmed regardless of these settings.'), permList),
        h('div.panel', {}, h('h3', {}, 'Approved scripts'), h('p.small.mist', {}, 'VIPER can run only these scripts (.ps1, .bat, .cmd, .py, .js). It cannot run arbitrary commands.'), scripts,
          btn('Add script', async () => {
            const path = window.viperNative?.pickFile ? await window.viperNative.pickFile([{ name: 'Scripts', extensions: ['ps1', 'bat', 'cmd', 'py', 'js', 'sh'] }]) : await prompt('Script path', { label: 'Full path to the script' });
            if (!path) return; const name = await prompt('Script name', { label: 'Name VIPER will use (e.g. "backup photos")' }); if (!name) return;
            app.settings.approvedScripts = await api.patch('/settings/approvedScripts', [...s.approvedScripts, { id: Date.now().toString(36), name, path, args: [] }]); draw();
          }, { cls: 'sm', ico: 'plus' })),
        h('div.panel', {}, h('h3', {}, 'Delete data'), h('p.small.mist', {}, 'Permanently remove conversations, memories, automations, notifications, indexed documents and logs from this PC.'),
          h('div.row.wrap', {}, btn('Clear activity log', async () => { if (await ask('Clear activity log?', 'The record of actions VIPER has taken will be deleted.', { danger: true, confirmLabel: 'Clear' })) { await api.post('/activity/clear'); toast('Activity log cleared'); } }, { cls: 'sm' }),
            btn('Clear transcripts', async () => { await api.post('/transcripts/clear'); toast('Transcripts cleared'); }, { cls: 'sm' }),
            btn('Delete everything', async () => { const t = await prompt('Delete all VIPER data', { label: 'Type DELETE EVERYTHING to confirm' }); if (t === 'DELETE EVERYTHING') { await api.post('/data/delete-all', { confirm: t }); toast('All data deleted'); } }, { cls: 'sm danger' })))));
    }
    if (tab === 'performance') {
      const l = s.limits;
      const num = (key, label, hint, min, max, step = 1) => field(label, h('input.input', { type: 'number', min, max, step, value: l[key], onchange: (e) => save('limits', { [key]: Number(e.target.value) }) }), hint);
      body.append(h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, 'Model resources'), h('div.col', {},
          num('numCtx', 'Context window (tokens)', 'Larger remembers more of the conversation but uses more memory. 4096 suits 8 GB PCs.', 1024, 131072, 512),
          num('numThreads', 'CPU threads (0 = automatic)', 'Limit how many processor threads inference may use.', 0, 128),
          num('gpuLayers', 'GPU layers (-1 = automatic, 0 = CPU only)', 'Ollama only. Lower values reduce GPU memory use.', -1, 999),
          field('Keep model loaded for', h('input.input', { value: l.keepAlive, onchange: (e) => save('limits', { keepAlive: e.target.value }) }), 'e.g. 5m, 30m, 0 to unload immediately after each reply'))),
        h('div.panel', {}, h('h3', {}, 'Generation'), h('div.col', {},
          num('temperature', 'Temperature', 'Lower is more focused; higher is more creative.', 0, 2, 0.05),
          num('maxContextMessages', 'Messages kept in context', 'Older messages are summarised automatically.', 4, 200),
          h('div.list', {}, row('Automatically restart a crashed AI engine', null, toggle(s.backend.autoRecover, (v) => save('backend', { autoRecover: v }))))))));
    }
    if (tab === 'proactive') {
      const p = s.proactive;
      const timeIn = (obj, key) => h('input.input', { type: 'time', value: p[obj].time, style: { width: '120px' }, onchange: (e) => save('proactive', { [obj]: { time: e.target.value } }) });
      body.append(h('div.panel', {}, h('h3', {}, 'Proactive assistant'), h('p.small.mist', {}, 'Everything here is optional, transparent and listed in the activity log. VIPER never reads private content to be proactive — only system metrics, its own reminders and automation results.'),
        h('div.list', {},
          row('Enable proactive assistance', null, toggle(p.enabled, (v) => save('proactive', { enabled: v }))),
          row('Morning briefing', 'Spoken and sent as a notification.', h('div.row', {}, timeIn('morningBriefing'), toggle(p.morningBriefing.enabled, (v) => save('proactive', { morningBriefing: { enabled: v } })))),
          row('Evening summary', null, h('div.row', {}, timeIn('eveningSummary'), toggle(p.eveningSummary.enabled, (v) => save('proactive', { eveningSummary: { enabled: v } })))),
          row('Low disk space warning', `Below ${p.lowDisk.thresholdPct}% free.`, toggle(p.lowDisk.enabled, (v) => save('proactive', { lowDisk: { enabled: v } }))),
          row('High memory warning', `Above ${p.highMemory.thresholdPct}% for ${Math.round(p.highMemory.sustainSec / 60)} min.`, toggle(p.highMemory.enabled, (v) => save('proactive', { highMemory: { enabled: v } }))),
          row('High CPU temperature warning', `Above ${p.highCpuTemp.thresholdC}°C (only if the PC exposes a sensor).`, toggle(p.highCpuTemp.enabled, (v) => save('proactive', { highCpuTemp: { enabled: v } }))),
          row('Tell me when an automation fails', null, toggle(p.failedAutomations, (v) => save('proactive', { failedAutomations: v })))),
        h('div.row', { style: { marginTop: '10px' } }, btn('Preview morning briefing', async (e) => busy(e.currentTarget, async () => { const b = await api.get('/briefing?kind=morning'); toast(b.title, b.text, 'info', 12000); app.voice.speak(b.text); }), { cls: 'sm', ico: 'play' }))));
    }
    if (tab === 'activity') {
      const list = await api.get('/activity?limit=300');
      const tbl = h('table.tbl', {}, h('thead', {}, h('tr', {}, ['When', 'Who', 'Action', 'Detail', 'Risk', 'Outcome'].map((t) => h('th', {}, t)))), h('tbody', {}, list.map((a) => h('tr', {}, h('td', {}, when(a.ts)), h('td', {}, a.actor), h('td', {}, a.action), h('td.mono', { style: { maxWidth: '320px', overflow: 'hidden', textOverflow: 'ellipsis' } }, (a.detail || '').slice(0, 160)), h('td', {}, a.risk), h('td', {}, a.outcome)))));
      body.append(h('div.panel', {}, h('h3', {}, 'Every action VIPER has taken', h('span.r', {}, btn('Export', () => download('viper-activity.json', JSON.stringify(list, null, 2), 'application/json'), { cls: 'sm' }))), list.length ? h('div', { style: { overflowX: 'auto' } }, tbl) : h('div.empty', {}, 'No actions recorded yet.')));
    }
    if (tab === 'about') {
      const st = await api.get('/status');
      const logs = await api.get('/logs/recent');
      body.append(h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, 'VIPER'), h('dl.kv', {}, h('dt', {}, 'Version'), h('dd', {}, st.version), h('dt', {}, 'Platform'), h('dd', {}, st.platform), h('dt', {}, 'Credential storage'), h('dd', {}, st.vault === 'file-key' ? 'Local key file (OS keystore unavailable)' : 'Windows DPAPI (OS keystore)'), h('dt', {}, 'Mode'), h('dd', {}, st.bridge === 'electron' ? 'Desktop app' : 'Headless server')),
          h('div.row.wrap', { style: { marginTop: '10px' } },
            window.viperNative?.checkUpdates ? btn('Check for updates', async (e) => busy(e.currentTarget, async () => { const r = await window.viperNative.checkUpdates(); toast(r.available ? `Update ${r.version} available` : 'VIPER is up to date', r.message || ''); }), { cls: 'sm' }) : null,
            window.viperNative?.openDataDir ? btn('Open data folder', () => window.viperNative.openDataDir(), { cls: 'sm' }) : null,
            btn('Run setup again', async () => { await api.patch('/settings/app', { setupComplete: false, setupStep: 0 }); location.reload(); }, { cls: 'sm' }))),
        h('div.panel', {}, h('h3', {}, 'Recent log (sanitised)'), h('div.mono', { style: { maxHeight: '320px', overflow: 'auto', whiteSpace: 'pre-wrap', fontSize: '11.5px' } }, logs.slice(-80).map((l) => `${new Date(l.ts).toLocaleTimeString()} ${l.level} [${l.scope}] ${l.msg}`).join('\n') || 'Empty'))));
    }
  };
  draw();
}
