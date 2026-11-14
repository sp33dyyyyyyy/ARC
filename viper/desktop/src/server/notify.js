'use strict';
// Notification router: desktop, in-app, paired phone, email, SMS, ntfy and
// plugin-provided channels. Applies quiet hours, priorities, category
// toggles, emergency mute, rate limits and retries; records every delivery.
const { uid, now, sleep, fetchWithTimeout } = require('./util');

const PRIORITIES = ['low', 'normal', 'high', 'urgent'];
const EXTERNAL = new Set(['email', 'sms', 'ntfy']);

function inQuietHours(q, d = new Date()) {
  if (!q?.enabled) return false;
  const toMin = (s) => { const [h, m] = String(s).split(':').map(Number); return h * 60 + (m || 0); };
  const cur = d.getHours() * 60 + d.getMinutes();
  const a = toMin(q.start); const b = toMin(q.end);
  return a <= b ? cur >= a && cur < b : cur >= a || cur < b;
}

class Notifier {
  constructor({ db, bus, settings, vault, log, bridge }) {
    this.db = db; this.bus = bus; this.settings = settings; this.vault = vault; this.log = log; this.bridge = bridge;
    this.channels = new Map();
    this.sentTimes = [];
    this.registerBuiltins();
  }
  registerChannel(id, impl) { this.channels.set(id, impl); }

  registerBuiltins() {
    this.registerChannel('desktop', { label: 'Desktop notification', send: async (n) => { const r = await this.bridge.notify(n.title, n.body); return r?.ok === false ? { ok: false, error: r.error } : { ok: true }; } });
    this.registerChannel('mobile', {
      label: 'VIPER Mobile push',
      send: async (n) => {
        const remote = this.remote;
        if (!remote) return { ok: false, error: 'Remote service not running' };
        const delivered = remote.pushToDevices({ type: 'notification', data: n });
        return delivered > 0 ? { ok: true, detail: `${delivered} device(s)` } : { ok: false, queued: true, error: 'No phone connected; it will receive this when it reconnects.' };
      },
    });
    this.registerChannel('ntfy', {
      label: 'ntfy push (external service)',
      send: async (n) => {
        const c = this.settings.get('notifications').ntfy;
        if (!c.enabled || !c.topic) return { ok: false, error: 'ntfy is not configured' };
        const token = this.vault.get('ntfy.token');
        const r = await fetchWithTimeout(`${c.server.replace(/\/$/, '')}/${encodeURIComponent(c.topic)}`, {
          method: 'POST', body: n.body || n.title,
          headers: { Title: `VIPER: ${n.title}`.slice(0, 200), Priority: { low: '2', normal: '3', high: '4', urgent: '5' }[n.priority] || '3', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        }, 15000);
        return r.ok ? { ok: true } : { ok: false, error: `ntfy HTTP ${r.status}` };
      },
    });
    this.registerChannel('email', {
      label: 'Email',
      send: async (n) => {
        if (!this.email) return { ok: false, error: 'Email service unavailable' };
        const r = await this.email.sendToSelf({ subject: `VIPER: ${n.title}`, text: `${n.body || ''}\n\n— Sent by VIPER (${new Date(n.created_at).toLocaleString()})` });
        return r;
      },
    });
    this.registerChannel('sms', {
      label: 'SMS',
      send: async (n) => {
        if (!this.sms) return { ok: false, error: 'SMS service unavailable' };
        return this.sms.sendToSelf(`VIPER: ${n.title}${n.body ? ' — ' + n.body : ''}`.slice(0, 480));
      },
    });
  }

  rateLimited() {
    const limit = this.settings.get('notifications').rateLimitPerHour || 30;
    this.sentTimes = this.sentTimes.filter((t) => Date.now() - t < 3600000);
    return this.sentTimes.length >= limit;
  }

  /**
   * @param {{title, body, category, priority, channels?, speak?}} n
   */
  async send(n) {
    const cfg = this.settings.get('notifications');
    const priority = PRIORITIES.includes(n.priority) ? n.priority : 'normal';
    const category = n.category || 'general';
    const rec = { id: uid('ntf_'), title: String(n.title || 'VIPER').slice(0, 200), body: String(n.body || '').slice(0, 4000), category, priority, created_at: now() };
    let channels = (n.channels && n.channels.length ? n.channels : cfg.defaultChannels).filter((c) => this.channels.has(c));
    const quiet = inQuietHours(cfg.quietHours) && !(priority === 'urgent' && cfg.quietHours.allowUrgent);
    const suppressed = [];
    if (cfg.categories?.[category] === false) { suppressed.push('category disabled'); channels = []; }
    if (cfg.emergencyMute) { suppressed.push('emergency mute'); channels = []; }
    if (quiet) { suppressed.push('quiet hours'); channels = channels.filter((c) => c === 'mobile'); }
    if (channels.some((c) => EXTERNAL.has(c)) && this.rateLimited()) { suppressed.push('rate limit'); channels = channels.filter((c) => !EXTERNAL.has(c)); }
    this.db.run('INSERT INTO notifications (id, title, body, category, priority, channels, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      rec.id, rec.title, rec.body, rec.category, rec.priority, JSON.stringify(channels), suppressed.length && !channels.length ? 'suppressed' : 'sending', rec.created_at);
    // In-app feed always gets it (the UI shows it in the notification centre).
    this.bus.publish('notification', { ...rec, channels, suppressed, speak: !!n.speak && !quiet && !cfg.emergencyMute });
    const results = {};
    for (const ch of channels) results[ch] = await this.deliver(rec, ch);
    const allOk = Object.values(results).every((r) => r.ok || r.queued);
    this.db.run('UPDATE notifications SET status = ? WHERE id = ?', channels.length ? (allOk ? 'delivered' : 'partial') : (suppressed.length ? 'suppressed' : 'in-app'), rec.id);
    return { id: rec.id, channels, results, suppressed };
  }

  async deliver(rec, ch, attemptStart = 0) {
    const did = uid('dlv_');
    const maxAttempts = Math.max(1, this.settings.get('notifications').retryAttempts || 1);
    let last = { ok: false, error: 'not attempted' };
    for (let attempt = attemptStart + 1; attempt <= maxAttempts; attempt++) {
      try { last = await this.channels.get(ch).send(rec); } catch (e) { last = { ok: false, error: e.message }; }
      if (last.ok || last.queued) break;
      if (attempt < maxAttempts) await sleep(Math.min(8000, 1000 * 2 ** (attempt - 1)));
    }
    if (last.ok && EXTERNAL.has(ch)) this.sentTimes.push(Date.now());
    this.db.run('INSERT INTO deliveries (id, notification_id, channel, status, attempts, error, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      did, rec.id, ch, last.ok ? 'delivered' : last.queued ? 'queued' : 'failed', maxAttempts, last.error || null, now());
    if (!last.ok && !last.queued) this.log.warn(`notification ${rec.id} via ${ch} failed: ${last.error}`);
    return last;
  }

  async retry(notificationId) {
    const rec = this.db.get('SELECT * FROM notifications WHERE id = ?', notificationId);
    if (!rec) throw new Error('Notification not found');
    const failed = this.db.all("SELECT DISTINCT channel FROM deliveries WHERE notification_id = ? AND status IN ('failed','queued')", notificationId);
    const out = {};
    for (const { channel } of failed) out[channel] = await this.deliver(rec, channel);
    return out;
  }

  list({ limit = 100, unreadOnly = false } = {}) {
    const rows = this.db.all(`SELECT * FROM notifications ${unreadOnly ? 'WHERE read = 0' : ''} ORDER BY created_at DESC LIMIT ?`, limit);
    const ids = rows.map((r) => r.id);
    const del = ids.length ? this.db.all(`SELECT * FROM deliveries WHERE notification_id IN (${ids.map(() => '?').join(',')})`, ...ids) : [];
    return rows.map((r) => ({ ...r, channels: JSON.parse(r.channels || '[]'), deliveries: del.filter((d) => d.notification_id === r.id) }));
  }
  since(ts) { return this.db.all('SELECT * FROM notifications WHERE created_at > ? ORDER BY created_at ASC LIMIT 200', ts); }
  markRead(id) { if (id === 'all') this.db.run('UPDATE notifications SET read = 1'); else this.db.run('UPDATE notifications SET read = 1 WHERE id = ?', id); this.bus.publish('notifications.read', { id }); }
  clear() { this.db.run('DELETE FROM deliveries'); this.db.run('DELETE FROM notifications'); }
  channelList() { return [...this.channels.entries()].map(([id, c]) => ({ id, label: c.label })); }
}

module.exports = { Notifier, inQuietHours, PRIORITIES };
