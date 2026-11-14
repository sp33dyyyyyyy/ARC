import { h, clear, icon, btn, busy, toast, toastError, field, select, toggle, ask, when, ago, modal, mdEl, readFileAs, prompt } from '../ui.js';

const TABS = [['inbox', 'Mail'], ['compose', 'Compose'], ['outbox', 'Sent & scheduled'], ['recipients', 'Recipients'], ['templates', 'Templates'], ['alerts', 'Notifications'], ['phone', 'Phone link']];

export async function render(view, { app, api, params }) {
  let tab = params?.tab || 'inbox';
  const tabs = h('div.tabs'); const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Communications'), h('div.sub', {}, 'Email, SMS, notifications and your phone link. VIPER never sends anything external without setup and your approval.'))), tabs, body);
  const draw = async () => {
    clear(tabs).append(...TABS.map(([id, l]) => h(`button${tab === id ? '.on' : ''}`, { onclick: () => { tab = id; draw(); } }, l)));
    clear(body);
    try { await PANES[tab](body, { app, api, go: (t) => { tab = t; draw(); } }); } catch (e) { body.append(h('div.empty', {}, e.message)); }
  };
  draw();
  const off = api.on('remote.changed', () => { if (tab === 'phone') draw(); });
  return off;
}

const PANES = {
  async inbox(body, { api, app, go }) {
    const accounts = await api.get('/comms/accounts');
    const acctBox = h('div.panel', {}, h('h3', {}, icon('comms'), 'Accounts', h('span.r', {}, btn('Add account', () => addAccount(api, () => go('inbox')), { cls: 'sm primary', ico: 'plus' }))),
      accounts.length ? h('div.list', {}, accounts.map((a) => h('div.li', {}, h('div.t', {}, h('b', {}, a.label), h('small', {}, `${a.address} · ${a.provider} · ${a.auth_type === 'oauth' ? 'signed in with OAuth' : 'app password'}${a.connected ? '' : ' · not connected'}`)),
        a.auth_type === 'oauth' || ['gmail', 'outlook'].includes(a.provider) ? btn(a.connected && a.auth_type === 'oauth' ? 'Re-authorise' : 'Sign in', async (e) => busy(e.currentTarget, async () => { try { await api.post(`/comms/accounts/${a.id}/oauth`); toast('Signed in', a.address); go('inbox'); } catch (er) { toastError(er); } }), { cls: 'sm' }) : null,
        btn('Test', async (e) => busy(e.currentTarget, async () => { const r = await api.post(`/comms/accounts/${a.id}/test`); toast(`${a.address}`, `SMTP: ${r.smtp} · IMAP: ${r.imap}`, r.smtp === 'ok' && String(r.imap).startsWith('ok') ? 'info' : 'warn', 9000); }), { cls: 'sm' }),
        btn('', async () => { if (await ask('Remove account?', `${a.address} will be disconnected and its stored credentials deleted.`, { danger: true, confirmLabel: 'Remove' })) { await api.del(`/comms/accounts/${a.id}`); go('inbox'); } }, { cls: 'sm ghost icon', ico: 'trash', title: 'Remove' })))) : h('p.small.mist', {}, 'No mailbox connected. Gmail and Outlook work with an app password, or with OAuth using your own client ID (see docs/COMMUNICATIONS.md).'));
    body.append(acctBox);
    if (!accounts.length) return;
    let acct = app.settings.notifications.emailAccountId || accounts[0].id; let msgs = []; const chosen = new Set();
    const listBox = h('div'); const readBox = h('div.panel', { style: { minHeight: '240px' } }, h('span.mist', {}, 'Select a message.'));
    const qIn = h('input.input', { placeholder: 'Search mail', onkeydown: (e) => { if (e.key === 'Enter') load(); } });
    const load = async () => {
      clear(listBox).append(h('div.progress.indet', {}, h('i')));
      try { msgs = await api.get(`/comms/accounts/${acct}/messages${qIn.value ? `?q=${encodeURIComponent(qIn.value)}` : ''}`); } catch (e) { clear(listBox).append(h('p.small', {}, e.message)); return; }
      clear(listBox).append(h('div.list', { style: { maxHeight: '420px', overflowY: 'auto' } }, msgs.map((m) => h('div.li', {}, h('input', { type: 'checkbox', 'aria-label': 'Select', onchange: (e) => (e.target.checked ? chosen.add(m.uid) : chosen.delete(m.uid)) }),
        h('div.t', { style: { cursor: 'pointer' }, onclick: () => read(m.uid) }, h('b', { style: { fontWeight: m.seen ? 300 : 500 } }, m.subject), h('small', {}, `${m.from} · ${m.date ? when(m.date) : ''}`))))));
    };
    const read = async (uid) => {
      clear(readBox).append(h('div.progress.indet', {}, h('i')));
      try { const m = await api.get(`/comms/accounts/${acct}/messages/${uid}`); clear(readBox).append(h('h3', {}, m.subject), h('small.mist', {}, `From ${m.from} · ${when(m.date)}`), h('div', { style: { whiteSpace: 'pre-wrap', marginTop: '10px', maxHeight: '50vh', overflow: 'auto' } }, m.text), m.attachments.length ? h('p.small.mist', {}, `Attachments: ${m.attachments.map((x) => x.name).join(', ')}`) : null,
        h('div.row', { style: { marginTop: '10px' } }, btn('Summarise', (e) => busy(e.currentTarget, async () => { const r = await api.post(`/comms/accounts/${acct}/summarize`, { uids: [uid] }); readBox.append(h('div.panel', { style: { marginTop: '10px' } }, mdEl(r.summary))); }), { cls: 'sm' }), btn('Draft reply', () => { sessionStorage.setItem('viper.reply', JSON.stringify({ to: (m.from.match(/<([^>]+)>/) || [])[1] || m.from, subject: `Re: ${m.subject}`, quote: m.text.slice(0, 4000) })); go('compose'); }, { cls: 'sm' }))); } catch (e) { clear(readBox).append(h('p', {}, e.message)); }
    };
    body.append(h('div.grid.g2', { style: { marginTop: '14px' } },
      h('div.panel', {}, h('div.row', { style: { marginBottom: '8px' } }, select(accounts.map((a) => [a.id, a.address]), acct, (v) => { acct = v; load(); }), h('div.grow', {}, qIn), btn('', load, { cls: 'sm icon', ico: 'refresh', title: 'Refresh' })),
        listBox, h('div.row', { style: { marginTop: '8px' } }, btn('Summarise selected', async (e) => busy(e.currentTarget, async () => { if (!chosen.size) { toast('Select emails first'); return; } const r = await api.post(`/comms/accounts/${acct}/summarize`, { uids: [...chosen] }); clear(readBox).append(h('h3', {}, `Summary of ${r.count} emails`), mdEl(r.summary)); }), { cls: 'sm' }))),
      readBox));
    load();
  },
  async compose(body, { api, app }) {
    const [accounts, templates, recipients] = await Promise.all([api.get('/comms/accounts'), api.get('/comms/templates'), api.get('/comms/recipients')]);
    const reply = JSON.parse(sessionStorage.getItem('viper.reply') || 'null'); sessionStorage.removeItem('viper.reply');
    const st = { accountId: app.settings.notifications.emailAccountId || accounts[0]?.id, to: reply?.to || '', subject: reply?.subject || '', body: '', templateId: '' };
    const toIn = h('input.input', { value: st.to, list: 'rcpts', placeholder: 'name@example.com, or a saved recipient name' });
    const subjIn = h('input.input', { value: st.subject }); const bodyIn = h('textarea.input', { rows: 12 });
    const instr = h('textarea.input', { rows: 3, placeholder: 'Describe the email: e.g. politely ask Sam to move Thursday\'s meeting to Friday afternoon' });
    const when_ = h('input.input', { type: 'datetime-local' });
    body.append(h('datalist', { id: 'rcpts' }, recipients.map((r) => h('option', { value: r.name })), recipients.filter((r) => r.email).map((r) => h('option', { value: r.email }))),
      !accounts.length ? h('div.empty', {}, h('b', {}, 'No email account'), 'Add one in the Mail tab before sending.') : null,
      h('div.grid.g2', {},
        h('div.panel', {}, h('h3', {}, icon('sparkle'), 'Draft with VIPER'), instr, field('Template (optional)', select([['', 'None'], ...templates.map((t) => [t.id, t.name])], '', (v) => { st.templateId = v; })),
          btn('Write draft', (e) => busy(e.currentTarget, async () => { const d = await api.post('/comms/draft', { instructions: instr.value, to: toIn.value, templateId: st.templateId || undefined, replyTo: reply?.quote }); subjIn.value = d.subject; bodyIn.value = d.body; }), { cls: 'primary', ico: 'sparkle' }),
          h('p.small.mist', {}, 'Drafts are written by your local model. Review before sending.')),
        h('div.panel', {}, h('h3', {}, 'Message'), accounts.length ? field('From', select(accounts.map((a) => [a.id, a.address]), st.accountId, (v) => { st.accountId = v; })) : null, field('To', toIn), field('Subject', subjIn), field('Body', bodyIn),
          h('div.row.wrap', { style: { marginTop: '8px' } }, btn('Send', (e) => busy(e.currentTarget, async () => { try { await api.post('/comms/send', { accountId: st.accountId, to: toIn.value.split(',').map((x) => x.trim()), subject: subjIn.value, body: bodyIn.value }); toast('Email sent'); } catch (er) { toastError(er); } }), { cls: 'primary', ico: 'send', disabled: !accounts.length }),
            h('div.row', {}, when_, btn('Schedule', (e) => busy(e.currentTarget, async () => { try { await api.post('/comms/schedule', { accountId: st.accountId, to: toIn.value.split(',').map((x) => x.trim()), subject: subjIn.value, body: bodyIn.value, sendAt: new Date(when_.value).getTime() }); toast('Scheduled', new Date(when_.value).toLocaleString()); } catch (er) { toastError(er); } }), { cls: 'sm', disabled: !accounts.length })),
            btn('Save as template', async () => { await api.post('/comms/templates', { name: subjIn.value || 'Template', subject: subjIn.value, body: bodyIn.value }); toast('Template saved'); }, { cls: 'sm ghost' })))));
  },
  async outbox(body, { api }) {
    const items = await api.get('/comms/outbox');
    body.append(h('div.panel', {}, items.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['When', 'Channel', 'To', 'Subject', 'Status', ''].map((t) => h('th', {}, t)))), h('tbody', {}, items.map((o) => h('tr', {}, h('td', {}, when(o.sent_at || o.send_at)), h('td', {}, o.channel), h('td', {}, o.recipients.join(', ')), h('td', {}, o.subject || (o.body || '').slice(0, 40)), h('td', {}, o.status === 'failed' ? h('span.badge-inv', { title: o.error }, 'failed') : o.status), h('td', {}, o.status === 'scheduled' ? btn('Cancel', async () => { await api.post(`/comms/outbox/${o.id}/cancel`); body.replaceChildren(); PANES.outbox(body, { api }); }, { cls: 'sm ghost' }) : null))))) : h('div.empty', {}, 'Nothing sent yet.')));
  },
  async recipients(body, { api }) {
    const list = await api.get('/comms/recipients');
    const edit = (r) => {
      const m = { id: r?.id, name: r?.name || '', email: r?.email || '', phone: r?.phone || '', isSelf: !!r?.is_self, approvedSms: !!r?.approved_sms };
      modal({ title: r ? 'Edit recipient' : 'Add recipient', body: h('div.col', {}, field('Name', h('input.input', { value: m.name, oninput: (e) => { m.name = e.target.value; } })), field('Email', h('input.input', { value: m.email, oninput: (e) => { m.email = e.target.value; } })), field('Mobile number (international format)', h('input.input', { value: m.phone, placeholder: '+44 7700 900123', oninput: (e) => { m.phone = e.target.value; } })),
        h('label.row', {}, h('input', { type: 'checkbox', checked: m.isSelf, onchange: (e) => { m.isSelf = e.target.checked; } }), 'This is me (used for email/SMS notifications to yourself)')),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Save', cls: 'primary', onClick: async () => { await api.post('/comms/recipients', m); body.replaceChildren(); PANES.recipients(body, { api }); } }] });
    };
    body.append(h('div.panel', {}, h('h3', {}, 'Recipients', h('span.r', {}, btn('Add', () => edit(null), { cls: 'sm primary', ico: 'plus' }))),
      list.length ? h('div.list', {}, list.map((r) => h('div.li', {}, r.is_self ? h('span.tag.on', {}, 'Me') : null, h('div.t', {}, h('b', {}, r.name), h('small', {}, [r.email, r.phone].filter(Boolean).join(' · '))), btn('Edit', () => edit(r), { cls: 'sm ghost' }), btn('', async () => { await api.del(`/comms/recipients/${r.id}`); body.replaceChildren(); PANES.recipients(body, { api }); }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' })))) : h('p.small.mist', {}, 'Add yourself first so VIPER can email or text you reports and alerts.')));
  },
  async templates(body, { api }) {
    const list = await api.get('/comms/templates');
    body.append(h('div.panel', {}, h('h3', {}, 'Message templates'), list.length ? h('div.list', {}, list.map((t) => h('div.li', {}, h('div.t', {}, h('b', {}, t.name), h('small', {}, t.subject)), btn('', async () => { await api.del(`/comms/templates/${t.id}`); body.replaceChildren(); PANES.templates(body, { api }); }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' })))) : h('p.small.mist', {}, 'Save a template from the Compose tab.')));
  },
  async alerts(body, { api, app }) {
    const n = app.settings.notifications;
    const save = async (patch) => { app.settings.notifications = await api.patch('/settings/notifications', patch); };
    const [hist, channels, accounts] = await Promise.all([api.get('/notifications'), api.get('/notifications/channels'), api.get('/comms/accounts')]);
    const testCh = h('select.input', {}, channels.map((c) => h('option', { value: c.id }, c.label)));
    body.append(h('div.grid.g2', {},
      h('div.panel', {}, h('h3', {}, icon('bell'), 'Delivery rules'), h('div.list', {},
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Emergency mute'), h('small', {}, 'Stop all notifications immediately (they are still logged).')), toggle(n.emergencyMute, (v) => save({ emergencyMute: v }))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Quiet hours'), h('small', {}, 'Only urgent alerts and phone notifications get through.')), h('div.row', {}, h('input.input', { type: 'time', value: n.quietHours.start, style: { width: '110px' }, onchange: (e) => save({ quietHours: { start: e.target.value } }) }), h('input.input', { type: 'time', value: n.quietHours.end, style: { width: '110px' }, onchange: (e) => save({ quietHours: { end: e.target.value } }) }), toggle(n.quietHours.enabled, (v) => save({ quietHours: { enabled: v } })))),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'External messages per hour'), h('small', {}, 'Rate limit for email, SMS and ntfy.')), h('input.input', { type: 'number', min: 1, max: 500, value: n.rateLimitPerHour, style: { width: '90px' }, onchange: (e) => save({ rateLimitPerHour: Number(e.target.value) }) })),
        h('div.li', {}, h('div.t', {}, h('b', {}, 'Retry failed deliveries'), h('small', {}, 'Attempts with backoff.')), h('input.input', { type: 'number', min: 1, max: 6, value: n.retryAttempts, style: { width: '90px' }, onchange: (e) => save({ retryAttempts: Number(e.target.value) }) }))),
      h('h3', { style: { marginTop: '12px' } }, 'Default channels'), h('div.row.wrap', {}, channels.map((c) => h('label.row', {}, h('input', { type: 'checkbox', checked: n.defaultChannels.includes(c.id), onchange: (e) => save({ defaultChannels: e.target.checked ? [...new Set([...app.settings.notifications.defaultChannels, c.id])] : app.settings.notifications.defaultChannels.filter((x) => x !== c.id) }) }), c.label))),
      h('h3', { style: { marginTop: '12px' } }, 'Categories'), h('div.row.wrap', {}, Object.entries(n.categories).map(([c, on]) => h('label.row', {}, toggle(on, (v) => save({ categories: { [c]: v } }), c), c)))),
      h('div.col', {},
        h('div.panel', {}, h('h3', {}, 'Email notifications'), accounts.length ? field('Send from account', select(accounts.map((a) => [a.id, a.address]), n.emailAccountId, (v) => save({ emailAccountId: v }))) : h('p.small.mist', {}, 'Add an email account in the Mail tab.'), h('p.small.mist', {}, 'Notifications are sent to the recipient marked “Me”.')),
        h('div.panel', {}, h('h3', {}, 'SMS'), smsConfig(api, app)),
        h('div.panel', {}, h('h3', {}, 'ntfy push (optional, external)'), h('p.small.mist', {}, 'Reach your phone away from home through an ntfy server (ntfy.sh or self-hosted). Messages pass through that server.'),
          h('div.grid.g2', {}, field('Server', h('input.input', { value: n.ntfy.server, onchange: (e) => save({ ntfy: { server: e.target.value } }) })), field('Topic (keep it secret)', h('input.input', { value: n.ntfy.topic, onchange: (e) => save({ ntfy: { topic: e.target.value } }) }))),
          h('div.row', {}, h('label.row', {}, toggle(n.ntfy.enabled, (v) => save({ ntfy: { enabled: v } })), 'Enabled'), btn('Set access token', async () => { const t = await prompt('ntfy access token', { label: 'Stored encrypted with Windows DPAPI' }); if (t != null) { await api.post('/comms/ntfy-token', { token: t }); toast('Token saved'); } }, { cls: 'sm ghost' }))),
        h('div.panel', {}, h('h3', {}, 'Test a channel'), h('div.row', {}, h('div.grow', {}, testCh), btn('Send test', async (e) => busy(e.currentTarget, async () => { const r = await api.post('/notifications/test', { channels: [testCh.value], title: 'Test notification', body: 'If you can read this, the channel works.' }); const res = r.results[testCh.value]; toast(res?.ok ? 'Delivered' : res?.queued ? 'Queued' : 'Not delivered', res?.error || r.suppressed.join(', ') || '', res?.ok ? 'info' : 'warn'); }), { cls: 'sm' }))))),
    h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Delivery history', h('span.r', {}, btn('Mark all read', () => api.post('/notifications/all/read'), { cls: 'sm ghost' }))),
      hist.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['When', 'Notification', 'Priority', 'Deliveries', ''].map((t) => h('th', {}, t)))), h('tbody', {}, hist.slice(0, 60).map((x) => h('tr', {}, h('td', {}, when(x.created_at)), h('td', {}, h('b', { style: { fontWeight: 400 } }, x.title), h('small.mist', { style: { display: 'block' } }, (x.body || '').slice(0, 90))), h('td', {}, x.priority), h('td', {}, x.deliveries.length ? x.deliveries.map((d) => `${d.channel}: ${d.status}${d.error ? ` (${d.error.slice(0, 50)})` : ''}`).join(' · ') : x.status), h('td', {}, x.deliveries.some((d) => d.status === 'failed') ? btn('Retry', async () => { await api.post(`/notifications/${x.id}/retry`); toast('Retried'); }, { cls: 'sm ghost' }) : null))))) : h('small.mist', {}, 'No notifications yet.')));
  },
  async phone(body, { api }) {
    const [st, devices] = await Promise.all([api.get('/remote/status'), api.get('/remote/devices')]);
    const qrBox = h('div');
    body.append(h('div.grid.g2', {},
      h('div.panel', {}, h('h3', {}, icon('phone'), 'Pair VIPER Mobile', h('span.r', {}, h(`span.dot${st.running ? '.on' : ''}`))),
        h('p.small.mist', {}, 'Install the VIPER Mobile APK, open it and scan this code. The code works once and expires after five minutes. The connection is encrypted with TLS and pinned to this PC\'s certificate.'),
        qrBox, btn('Show pairing code', async (e) => busy(e.currentTarget, async () => { const p = await api.post('/remote/pairing'); clear(qrBox).append(h('div.row', { style: { alignItems: 'flex-start', gap: '16px', margin: '10px 0' } }, h('div.qr', {}, h('img', { src: p.qr, alt: 'Pairing QR code' })), h('div', {}, h('p', {}, `${p.hosts.map((x) => x.address).join(', ')} : ${p.port}`), h('p.small.mist', {}, `Expires ${new Date(p.expiresAt).toLocaleTimeString()}`), h('p.small.mist', { style: { wordBreak: 'break-all' } }, `Fingerprint ${p.fingerprint}`), btn('Copy pairing code', async () => { try { await navigator.clipboard.writeText(p.code); toast('Pairing code copied', 'Paste it into VIPER Mobile (or share it to the app) if you cannot scan the QR code. It works once and expires in 5 minutes.'); } catch (err) { toastError(err); } }, { cls: 'sm', ico: 'copy' })))); }), { cls: 'primary', ico: 'link' }),
        h('div.list', { style: { marginTop: '10px' } }, h('div.li', {}, h('div.t', {}, h('b', {}, 'Phone link service'), h('small', {}, st.running ? `Listening on port ${st.port} (${st.addresses.map((a) => a.address).join(', ') || 'no network'})` : 'Stopped')), toggle(st.enabled, async (v) => { await api.patch('/settings/remote', { enabled: v }); })))),
      h('div.panel', {}, h('h3', {}, 'Away from home'), h('p.small', {}, 'VIPER never opens ports on your router. To use your phone away from home, install a private VPN on both devices — for example WireGuard, or Tailscale — then pair or connect using the PC\'s VPN address (shown above when the VPN is active). All traffic stays end-to-end encrypted and authenticated.'),
        h('p.small.mist', {}, 'For notifications without a VPN, enable ntfy in the Notifications tab.'))),
    h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Paired devices'),
      devices.length ? h('div.list', {}, devices.map((d) => h('div.li', {}, h(`span.dot${d.online ? '.on' : ''}`), h('div.t', {}, h('b', {}, d.name, d.revoked ? h('span.badge-inv', { style: { marginLeft: '8px' } }, 'Revoked') : null), h('small', {}, `${d.platform} · paired ${when(d.created_at)} · last seen ${ago(d.last_seen)}${d.last_ip ? ` from ${d.last_ip}` : ''}`)),
        !d.revoked ? btn('Revoke access', async () => { if (await ask(`Revoke ${d.name}?`, 'The phone is disconnected immediately and must be paired again to reconnect.', { danger: true, confirmLabel: 'Revoke' })) { await api.post(`/remote/devices/${d.id}/revoke`); toast('Access revoked', d.name); } }, { cls: 'sm danger' }) : btn('Remove', async () => { await api.del(`/remote/devices/${d.id}`); }, { cls: 'sm ghost' })))) : h('p.small.mist', {}, 'No phones paired yet.')),
    h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'File transfer'), h('div', { id: 'xfer' })));
    const xfer = body.querySelector('#xfer');
    const files = await api.get('/remote/transfers');
    const up = h('input', { type: 'file', style: { display: 'none' }, onchange: async (e) => { const f = e.target.files[0]; if (!f) return; await api.post('/remote/transfers', { name: f.name, data: await readFileAs(f) }); toast('Sent to phone', `${f.name} is available in VIPER Mobile → Files.`); body.replaceChildren(); PANES.phone(body, { api }); } });
    xfer.append(up, btn('Send a file to the phone', () => up.click(), { cls: 'sm', ico: 'upload' }), h('div.list', {}, files.map((f) => h('div.li', {}, icon('file'), h('div.t', {}, h('b', {}, f.name), h('small', {}, `${Math.round(f.size / 1024)} KB · ${when(f.modified)}`)), btn('', async () => { await api.del(`/remote/transfers/${encodeURIComponent(f.name)}`); body.replaceChildren(); PANES.phone(body, { api }); }, { cls: 'sm ghost icon', ico: 'trash', title: 'Delete' })))), h('p.small.mist', {}, 'Files sent from the phone land here and in VIPER\'s transfers folder.'));
  },
};

function smsConfig(api, app) {
  const s = app.settings.notifications.sms;
  const m = { provider: s.provider, accountSid: s.twilio.accountSid, from: s.twilio.from, twilioToken: '' };
  const box = h('div.col');
  const draw = () => clear(box).append(field('Provider', select([['none', 'Off'], ['phone', 'My paired Android phone (carrier rates apply)'], ['twilio', 'Twilio SMS gateway (paid)']], m.provider, (v) => { m.provider = v; draw(); })),
    m.provider === 'twilio' ? h('div.grid.g2', {}, field('Account SID', h('input.input', { value: m.accountSid, oninput: (e) => { m.accountSid = e.target.value; } })), field('From number', h('input.input', { value: m.from, oninput: (e) => { m.from = e.target.value; } })), field('Auth token (stored encrypted)', h('input.input', { type: 'password', placeholder: '••••••', oninput: (e) => { m.twilioToken = e.target.value; } }))) : null,
    m.provider === 'phone' ? h('p.small.mist', {}, 'Your phone asks you to approve every SMS before it is sent, and needs the SMS permission enabled in VIPER Mobile.') : null,
    btn('Save SMS settings', async () => { app.settings.notifications = await api.post('/comms/sms/config', m); toast('SMS settings saved'); }, { cls: 'sm' }));
  draw();
  return box;
}

function addAccount(api, done) {
  const m = { provider: 'gmail', label: '', address: '', authType: 'password', password: '', imapHost: '', imapPort: 993, smtpHost: '', smtpPort: 465, smtpSecure: true, clientId: '', clientSecret: '' };
  const body = h('div.col');
  const draw = () => clear(body).append(
    field('Provider', select([['gmail', 'Gmail'], ['outlook', 'Outlook / Microsoft 365'], ['imap', 'Other (IMAP/SMTP)']], m.provider, (v) => { m.provider = v; if (v === 'imap') m.authType = 'password'; draw(); })),
    h('div.grid.g2', {}, field('Email address', h('input.input', { value: m.address, oninput: (e) => { m.address = e.target.value; } })), field('Label', h('input.input', { value: m.label, placeholder: 'Personal', oninput: (e) => { m.label = e.target.value; } }))),
    m.provider !== 'imap' ? field('Sign-in method', select([['password', 'App password'], ['oauth', 'OAuth (your own client ID)']], m.authType, (v) => { m.authType = v; draw(); })) : null,
    m.authType === 'password' ? field('App password (stored encrypted)', h('input.input', { type: 'password', oninput: (e) => { m.password = e.target.value; } }), m.provider === 'gmail' ? 'Create one at myaccount.google.com/apppasswords (requires 2-Step Verification).' : m.provider === 'outlook' ? 'Microsoft may require OAuth for Outlook.com; use OAuth if the password is rejected.' : '') : null,
    m.authType === 'oauth' ? h('div.grid.g2', {}, field('OAuth client ID', h('input.input', { value: m.clientId, oninput: (e) => { m.clientId = e.target.value; } }), 'See docs/COMMUNICATIONS.md'), field('Client secret (Google desktop clients only)', h('input.input', { type: 'password', oninput: (e) => { m.clientSecret = e.target.value; } }))) : null,
    m.provider === 'imap' ? h('div.grid.g2', {}, field('IMAP server', h('input.input', { value: m.imapHost, oninput: (e) => { m.imapHost = e.target.value; } })), field('IMAP port', h('input.input', { type: 'number', value: m.imapPort, oninput: (e) => { m.imapPort = Number(e.target.value); } })), field('SMTP server', h('input.input', { value: m.smtpHost, oninput: (e) => { m.smtpHost = e.target.value; } })), field('SMTP port (465 SSL / 587 STARTTLS)', h('input.input', { type: 'number', value: m.smtpPort, oninput: (e) => { m.smtpPort = Number(e.target.value); m.smtpSecure = m.smtpPort === 465; } }))) : null);
  draw();
  modal({ title: 'Add email account', body, actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Add account', cls: 'primary', onClick: async () => {
    try {
      const provider = { gmail: 'google', outlook: 'microsoft' }[m.provider];
      if (m.authType === 'oauth') await api.post('/comms/oauth-client', { provider, clientId: m.clientId, clientSecret: m.clientSecret || undefined });
      const a = await api.post('/comms/accounts', { provider: m.provider, label: m.label || m.address, address: m.address, authType: m.authType, password: m.password || undefined,
        ...(m.provider === 'imap' ? { imap: { host: m.imapHost, port: m.imapPort, secure: true }, smtp: { host: m.smtpHost, port: m.smtpPort, secure: m.smtpSecure } } : {}) });
      if (m.authType === 'oauth') { toast('Opening sign-in', 'Complete the sign-in in your browser.'); await api.post(`/comms/accounts/${a.id}/oauth`); }
      toast('Account added', a.address); done();
    } catch (e) { toastError(e); return false; }
  } }] });
}
