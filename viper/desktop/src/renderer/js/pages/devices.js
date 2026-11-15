import { h, clear, icon, btn, busy, toast, toastError, toggle, ask, when, ago } from '../ui.js';

// MANAGE → Connected Devices. Every action here talks to the real phone-link service:
// pairing creates a single-use, five-minute token shown as a QR code; the phone must also be
// approved on this PC; revoking closes the phone's connection at once.
export const SCOPES = [
  ['read', 'View status', 'Dashboard, notifications and history'],
  ['chat', 'Chat', 'Send messages to VIPER'],
  ['voice', 'Voice', 'Push-to-talk from the phone'],
  ['reminders', 'Reminders', 'Create and view reminders'],
  ['automation', 'Automations', 'Run your saved automations'],
  ['control', 'PC control', 'Open apps, media keys, lock the PC'],
  ['research', 'Research', 'Start research tasks'],
  ['image', 'Images', 'Generate images'],
  ['files', 'Files', 'Send and receive files'],
  ['models', 'Models', 'See and switch the AI model'],
  ['code', 'Code Studio', 'Code help'],
  ['agent', 'Code Agent', 'Start, pause and cancel coding projects'],
  ['approve', 'Approve actions', 'Answer approval requests from the phone (after a review screen)'],
];
const EVENT_LABEL = { paired: 'Paired', rejected: 'Pairing rejected', declined: 'Pairing declined on the PC', revoked: 'Access revoked', connected: 'Connected', disconnected: 'Disconnected', removed: 'Removed', permissions: 'Permissions changed' };

export async function render(view, { app, api }) {
  const status = h('div'); const pairBox = h('div'); const list = h('div'); const hist = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Connected Devices'), h('div.sub', {}, 'Phones paired with this PC, their permissions and connection history.')),
    h('div.actions', {}, btn('Add new device', () => startPairing(), { cls: 'sm primary', ico: 'plus' }))),
  status, pairBox, list, hist);

  let pairing = null; let tick = null;
  async function startPairing() {
    try {
      pairing = await api.post('/remote/pairing');
      drawPair();
    } catch (e) { toastError(e); }
  }
  function drawPair() {
    clearInterval(tick); clear(pairBox);
    if (!pairing) return;
    const left = h('b'); const upd = () => { const s = Math.max(0, Math.round((pairing.expiresAt - Date.now()) / 1000)); left.textContent = s ? `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}` : 'expired'; if (!s) { clearInterval(tick); } };
    upd(); tick = setInterval(upd, 1000);
    pairBox.append(h('div.panel.pair-panel', { style: { marginTop: '14px' } },
      h('h3', {}, icon('phone'), 'Pair a new phone', h('span.r', {}, btn('Cancel', async () => { await api.post('/remote/pairing/cancel').catch(() => {}); pairing = null; drawPair(); }, { cls: 'sm ghost' }))),
      h('div.pair-grid', {},
        h('div.qr', {}, h('img', { src: pairing.qr, alt: 'Pairing QR code' })),
        h('ol.steps', {},
          h('li', {}, 'Open VIPER Mobile on your Android phone and tap ', h('b', {}, 'Scan QR Code'), '.'),
          h('li', {}, 'Point the camera at this code. It works once and expires in ', left, '.'),
          h('li', {}, 'Approve the phone when VIPER asks on this PC. Nothing is paired until you do.'),
          h('li.mist', {}, `Addresses in the code: ${(pairing.hosts || []).map((x) => x.address).join(', ') || 'none'} · port ${pairing.port}. Certificate fingerprint ${String(pairing.fingerprint || '').slice(0, 23)}…`)))));
  }

  async function draw() {
    let st; let devices; let events;
    try { [st, devices, events] = await Promise.all([api.get('/remote/status'), api.get('/remote/devices'), api.get('/remote/events?limit=80')]); } catch (e) { clear(list).append(h('div.empty', {}, e.message)); return; }
    clear(status).append(h('div.grid.g3', {},
      h('div.panel', {}, h('div.stat', {}, h('b', {}, st.running ? 'Online' : 'Off'), h('span', {}, 'Phone link service')), h('small.mist', {}, st.running ? `Port ${st.port} · ${(st.addresses || []).map((a) => a.address).join(', ') || 'no network'}` : 'Turn it on to pair or reconnect phones.'),
        h('div.row', { style: { marginTop: '8px' } }, toggle(st.enabled, async (v) => { try { await api.patch('/settings/remote', { enabled: v }); } catch (e) { toastError(e); } }, 'Phone link service'), h('span.small', {}, 'Enabled'))),
      h('div.panel', {}, h('div.stat', {}, h('b', {}, String(devices.filter((d) => d.online).length)), h('span', {}, 'Connected now')), h('small.mist', {}, `${devices.filter((d) => !d.revoked).length} paired · ${devices.filter((d) => d.revoked).length} revoked`)),
      h('div.panel', {}, h('div.stat', {}, h('b', {}, devices.some((d) => d.push_registered) ? 'Ready' : 'LAN only'), h('span', {}, 'Closed-app notifications')), h('small.mist', {}, devices.some((d) => d.push_registered) ? 'Firebase push is registered for at least one phone.' : 'Notifications reach the phone while VIPER Mobile is connected (or its “Stay connected” service runs). Set up Firebase push in Settings → Notifications for a closed app.'))));

    clear(list).append(h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Devices'),
      devices.length ? h('div.dev-list', {}, devices.map((d) => deviceCard(d))) : h('div.empty', {}, 'No phones paired yet. Choose “Add new device” and scan the code with VIPER Mobile.')));

    clear(hist).append(h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Pairing and connection history'),
      events.length ? h('table.tbl', {}, h('thead', {}, h('tr', {}, ['When', 'Device', 'Event', 'Detail', 'Address'].map((t) => h('th', {}, t)))),
        h('tbody', {}, events.map((e) => h('tr', {}, h('td', {}, when(e.ts)), h('td', {}, e.device_name || '—'), h('td', {}, EVENT_LABEL[e.event] || e.event), h('td.small', {}, e.detail || ''), h('td.mono', {}, e.ip || '')))))
        : h('div.empty', {}, 'Nothing recorded yet.')));
  }

  function deviceCard(d) {
    const scopes = new Set(d.scopes || []);
    const permBox = h('div.scope-grid');
    for (const [id, label, desc] of SCOPES) {
      permBox.append(h('label.scope', { title: desc }, toggle(scopes.has(id), async (v) => {
        const next = v ? [...scopes, id] : [...scopes].filter((x) => x !== id);
        try { const r = await api.patch(`/remote/devices/${d.id}`, { scopes: next }); scopes.clear(); for (const s of r.scopes) scopes.add(s); toast('Permissions updated', d.name); } catch (e) { toastError(e); }
      }, label, d.revoked), h('span', {}, h('b', {}, label), h('small', {}, desc))));
    }
    const state = d.revoked ? 'Revoked' : d.online ? 'Connected' : 'Offline';
    return h(`div.dev${d.revoked ? '.revoked' : ''}`, {},
      h('div.dev-head', {}, h(`span.dot${d.online ? '.on' : ''}`), icon('phone'),
        h('div.t', {}, h('b', {}, d.name), h('small', {}, `${d.platform || 'android'} · paired ${when(d.created_at)}`)),
        h('span.tag', {}, state),
        d.revoked ? btn('Remove', async () => { try { await api.del(`/remote/devices/${d.id}`); draw(); } catch (e) { toastError(e); } }, { cls: 'sm ghost' })
          : btn('Revoke', async (ev) => { if (await ask(`Revoke ${d.name}?`, 'The phone is disconnected immediately, its credentials stop working and it must be paired again.', { danger: true, confirmLabel: 'Revoke' })) busy(ev.currentTarget, async () => { await api.post(`/remote/devices/${d.id}/revoke`); toast('Access revoked', d.name); draw(); }); }, { cls: 'sm danger' })),
      h('dl.kv', {}, h('dt', {}, 'Connection'), h('dd', {}, d.online ? 'Connected now' : d.revoked ? 'Credentials revoked' : 'Not connected'),
        h('dt', {}, 'Last connected'), h('dd', {}, d.lastConnected ? `${when(d.lastConnected)} (${ago(d.lastConnected)})` : d.last_seen ? ago(d.last_seen) : 'never'),
        h('dt', {}, 'Last address'), h('dd', {}, d.last_ip || '—'),
        h('dt', {}, 'Push when app closed'), h('dd', {}, d.push_registered ? `Registered (${d.push_provider || 'fcm'})` : 'Not registered')),
      d.revoked ? null : h('details.perm', {}, h('summary', {}, 'Permissions'), permBox));
  }

  await draw();
  const offs = [api.on('remote.changed', draw), api.on('remote.paired', (dv) => { pairing = null; drawPair(); toast('Phone paired', dv?.name || ''); draw(); }), api.on('remote.device', draw)];
  return () => { clearInterval(tick); offs.forEach((o) => o()); };
}
