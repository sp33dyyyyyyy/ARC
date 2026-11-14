import { h, clear, icon, btn, busy, toast, toastError, field, select, ask, when, ago, toggle, modal } from '../ui.js';

const TRIGGERS = [['cron', 'On a schedule'], ['interval', 'Every N minutes'], ['once', 'Once at a time'], ['download', 'When a download finishes'], ['folder', 'When a new file appears'], ['system', 'When a system metric crosses a threshold'], ['startup', 'When VIPER starts'], ['manual', 'Only when run manually']];
const ACTIONS = [['notify', 'Send a notification'], ['briefing', 'Give a briefing'], ['system_report', 'PC status report'], ['ai_prompt', 'Ask VIPER (AI prompt)'], ['open_app', 'Open an application'], ['email_report', 'Email me a report'], ['research', 'Run web research'], ['speak', 'Speak a message'], ['plugin', 'Plugin action']];
const CHANNELS = ['desktop', 'mobile', 'email', 'sms', 'ntfy'];

export async function render(view, { app, api }) {
  const list = h('div'); const hist = h('div');
  const nl = h('input.input', { placeholder: 'e.g. Every morning at 8, tell me my PC status', 'aria-label': 'Describe an automation' });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Automation'), h('div.sub', {}, 'Scheduled and event-driven workflows. Each run is logged; failures notify you.')), h('div.actions', {}, btn('New automation', () => editor(), { cls: 'primary', ico: 'plus' }))),
    h('div.panel', { style: { marginBottom: '14px' } }, h('h3', {}, 'Describe it in plain language'), h('div.row', {}, h('div.grow', {}, nl), btn('Create', (e) => busy(e.currentTarget, async () => { if (!nl.value.trim()) return; const r = await api.post('/automations/from-text', { text: nl.value }); toast('VIPER', r.reply || r.error || 'Done', r.error ? 'warn' : 'info', 8000); nl.value = ''; load(); }), { cls: 'primary' })),
      h('p.small.mist', { style: { marginTop: '6px' } }, 'Examples: “At 8 PM, remind me to shut down my computer”, “Notify my phone when a download finishes”, “Check my Documents folder for new files”.')),
    list, h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Run history'), hist));
  async function load() {
    const items = await api.get('/automations').catch(() => []);
    clear(list);
    if (!items.length) { list.append(h('div.empty', {}, h('b', {}, 'No automations yet'), 'Describe one above or create it step by step.')); }
    const grid = h('div.grid.g2'); list.append(grid);
    for (const a of items) {
      grid.append(h('div.panel', {}, h('h3', {}, h(`span.dot${a.enabled ? '.on' : ''}`), a.name, h('span.r', {}, toggle(a.enabled, async (v) => { await api.patch(`/automations/${a.id}`, { enabled: v }); load(); }, `Enable ${a.name}`))),
        h('p.small.mist', {}, describe(a)),
        h('dl.kv', {}, h('dt', {}, 'Last run'), h('dd', {}, a.last_run ? `${ago(a.last_run)} · ${a.last_status}` : 'never'), h('dt', {}, 'Next run'), h('dd', {}, a.nextRun ? when(a.nextRun) : (a.enabled ? 'on event' : 'paused')), h('dt', {}, 'Channels'), h('dd', {}, a.channels.length ? a.channels.join(', ') : 'default')),
        a.last_status === 'failed' ? h('p.small', {}, h('span.badge-inv', {}, 'Last run failed'), ' Check history below.') : null,
        h('div.row.wrap', { style: { marginTop: '8px' } }, btn('Run now', (e) => busy(e.currentTarget, async () => { const r = await api.post(`/automations/${a.id}/run`); toast(`${a.name}: ${r.status}`, (r.error || r.outputs?.join(' ') || '').slice(0, 200), r.status === 'failed' ? 'error' : 'info'); load(); }), { cls: 'sm', ico: 'play' }),
          btn('Edit', () => editor(a), { cls: 'sm' }), btn('History', async () => showHist(a), { cls: 'sm' }),
          btn('', async () => { if (await ask('Delete automation?', a.name, { danger: true, confirmLabel: 'Delete' })) { await api.del(`/automations/${a.id}`); load(); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' }))));
    }
    const runs = await api.get('/automations/history').catch(() => []);
    clear(hist).append(runs.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['When', 'Automation', 'Trigger', 'Status', 'Output'].map((t) => h('th', {}, t)))), h('tbody', {}, runs.slice(0, 40).map((r) => h('tr', {}, h('td', {}, when(r.started_at)), h('td', {}, r.name), h('td', {}, (JSON.parse(r.trigger_data || '{}').trigger) || ''), h('td', {}, r.status === 'failed' ? h('span.badge-inv', {}, 'failed') : r.status), h('td.small', { style: { maxWidth: '360px' } }, (r.error || r.output || '').slice(0, 160)))))) : h('small.mist', {}, 'No runs yet.'));
  }
  function describe(a) {
    const t = a.trigger;
    const tr = t.type === 'cron' ? (t.description || `cron ${t.cron}`) : t.type === 'interval' ? `every ${t.minutes} min` : t.type === 'once' ? `once at ${when(t.at)}` : t.type === 'download' ? `when a download finishes in ${t.folder}` : t.type === 'folder' ? `when a file appears in ${t.folder}` : t.type === 'system' ? `when ${t.metric} ${t.op} ${t.value}` : t.type;
    return `${tr[0].toUpperCase()}${tr.slice(1)} → ${a.actions.map((x) => ACTIONS.find(([k]) => k === x.type)?.[1].toLowerCase()).join(', ')}${a.condition ? ' (with condition)' : ''}`;
  }
  async function showHist(a) {
    const runs = await api.get(`/automations/${a.id}/history`);
    modal({ title: `${a.name} — history`, wide: true, body: runs.length ? h('div.list', {}, runs.map((r) => h('div.li', {}, h('div.t', {}, h('b', {}, `${when(r.started_at)} · ${r.status}`), h('small', { style: { whiteSpace: 'pre-wrap' } }, (r.error || r.output || '').slice(0, 600)))))) : h('p.mist', {}, 'Never run.') });
  }
  async function editor(a) {
    const plugActs = await api.get('/plugins/actions').catch(() => []);
    const m = a ? JSON.parse(JSON.stringify(a)) : { name: '', trigger: { type: 'cron', cron: '0 8 * * *' }, actions: [{ type: 'notify', title: '', message: '' }], channels: [], condition: null, enabled: true };
    const body = h('div.col');
    const draw = () => {
      const t = m.trigger; const act = m.actions[0];
      clear(body).append(field('Name', h('input.input', { value: m.name, oninput: (e) => { m.name = e.target.value; } })),
        field('Trigger', select(TRIGGERS, t.type, (v) => { m.trigger = { type: v, ...(v === 'cron' ? { cron: '0 8 * * *' } : v === 'interval' ? { minutes: 60 } : v === 'once' ? { at: Date.now() + 3600000 } : v === 'system' ? { metric: 'mem.pct', op: '>', value: 90, cooldownMin: 30 } : ['download', 'folder'].includes(v) ? { folder: app.settings.privacy.allowedFolders.find((f) => /download/i.test(f)) || app.settings.privacy.allowedFolders[0] } : {}) }; draw(); })),
        t.type === 'cron' ? h('div.grid.g2', {}, field('Schedule (plain words)', h('input.input', { placeholder: 'every weekday at 7:30am', onchange: async (e) => { const r = await api.post('/automations/parse-schedule', { text: e.target.value }); if (r.trigger) { m.trigger = r.trigger; draw(); } else toast('Could not understand that schedule', 'Try e.g. "every day at 8pm"', 'warn'); } })), field('Cron expression', h('input.input', { value: t.cron, oninput: (e) => { t.cron = e.target.value; } }), t.description || 'minute hour day month weekday')) : null,
        t.type === 'interval' ? field('Minutes', h('input.input', { type: 'number', min: 1, value: t.minutes, oninput: (e) => { t.minutes = Number(e.target.value); } })) : null,
        t.type === 'once' ? field('When', h('input.input', { type: 'datetime-local', value: new Date(t.at - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16), oninput: (e) => { t.at = new Date(e.target.value).getTime(); } })) : null,
        ['download', 'folder'].includes(t.type) ? h('div.grid.g2', {}, field('Folder', select(app.settings.privacy.allowedFolders.map((f) => [f, f]), t.folder, (v) => { t.folder = v; })), field('File name pattern (optional)', h('input.input', { value: t.pattern || '', placeholder: '*.pdf', oninput: (e) => { t.pattern = e.target.value || undefined; } }))) : null,
        t.type === 'system' ? h('div.grid.g3', {}, field('Metric', select([['mem.pct', 'Memory %'], ['cpu.pct', 'CPU %'], ['temp.cpu', 'CPU °C'], ['battery.pct', 'Battery %']], t.metric, (v) => { t.metric = v; })), field('Condition', select([['>', 'above'], ['<', 'below']], t.op, (v) => { t.op = v; })), field('Value', h('input.input', { type: 'number', value: t.value, oninput: (e) => { t.value = Number(e.target.value); } }))) : null,
        field('Action', select(ACTIONS, act.type, (v) => { m.actions = [{ type: v }]; draw(); })),
        act.type === 'notify' ? h('div.grid.g2', {}, field('Title', h('input.input', { value: act.title || '', oninput: (e) => { act.title = e.target.value; } })), field('Message ({file} inserts the file name)', h('input.input', { value: act.message || '', oninput: (e) => { act.message = e.target.value; } }))) : null,
        act.type === 'speak' ? field('Message', h('input.input', { value: act.message || '', oninput: (e) => { act.message = e.target.value; } })) : null,
        act.type === 'ai_prompt' ? field('Prompt', h('textarea.input', { rows: 3, oninput: (e) => { act.prompt = e.target.value; } }, act.prompt || '')) : null,
        act.type === 'research' ? field('Research question', h('input.input', { value: act.query || '', oninput: (e) => { act.query = e.target.value; } })) : null,
        act.type === 'open_app' ? field('Application', h('input.input', { value: act.app || '', oninput: (e) => { act.app = e.target.value; } })) : null,
        ['briefing', 'email_report'].includes(act.type) ? field('Kind', select([['morning', 'Morning briefing'], ['evening', 'Evening summary'], ['daily', 'Daily summary'], ['system', 'System report']], act.kind || 'morning', (v) => { act.kind = v; })) : null,
        act.type === 'plugin' ? field('Plugin action', select(plugActs.map((p) => [`${p.plugin}|${p.id}`, `${p.label} (${p.plugin})`]), act.plugin ? `${act.plugin}|${act.action}` : '', (v) => { const [p, id] = v.split('|'); act.plugin = p; act.action = id; })) : null,
        field('Notify via', h('div.row.wrap', {}, CHANNELS.map((c) => h('label.row', {}, h('input', { type: 'checkbox', checked: m.channels.includes(c), onchange: (e) => { m.channels = e.target.checked ? [...m.channels, c] : m.channels.filter((x) => x !== c); } }), c)))),
        h('details', {}, h('summary', { style: { cursor: 'pointer', color: 'var(--mist)' } }, 'Condition (optional)'),
          h('div.grid.g3', { style: { marginTop: '8px' } }, field('Only if', select([['', 'always'], ['system.mem.pct', 'memory %'], ['system.cpu.pct', 'CPU %'], ['file', 'file name']], m.condition?.field || '', (v) => { m.condition = v ? { field: v, op: m.condition?.op || '>', value: m.condition?.value ?? 80 } : null; draw(); })),
            m.condition ? field('is', select([['>', 'above'], ['<', 'below'], ['contains', 'contains'], ['==', 'equals']], m.condition.op, (v) => { m.condition.op = v; })) : null,
            m.condition ? field('value', h('input.input', { value: m.condition.value, oninput: (e) => { m.condition.value = isNaN(Number(e.target.value)) ? e.target.value : Number(e.target.value); } })) : null)));
    };
    draw();
    modal({ title: a ? 'Edit automation' : 'New automation', wide: true, body, actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Save', cls: 'primary', onClick: async () => { try { if (a) await api.patch(`/automations/${a.id}`, m); else await api.post('/automations', m); toast('Automation saved', m.name); load(); } catch (e) { toastError(e); return false; } } }] });
  }
  const off = api.on('automations.changed', load);
  load();
  return off;
}
