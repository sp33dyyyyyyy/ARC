'use strict';
// Notification router: desktop, in-app, paired phone, email, SMS, ntfy and
// plugin-provided channels. Applies quiet hours, priorities, category
// toggles, emergency mute, rate limits and retries; records every delivery.
const { uid, now, sleep, fetchWithTimeout } = require('./util');

const PRIORITIES = ['low', 'normal', 'high', 'urgent'];

/**
 * Notification kinds: short, natural, JARVIS-style wording. "{, address}" becomes ", sir" (or the
 * form of address set in Settings → Personality; nothing if it is blank). Actions are offered on
 * the phone; none of them approves anything — approvals always open a review screen first.
 */
const KINDS = {
  task_complete:     { title: 'VIPER', text: 'Task complete{, address}.', category: 'general', priority: 'normal', actions: [['view', 'View Results'], ['open', 'Open VIPER']] },
  input_required:    { title: 'VIPER — Input Required', text: 'I need your input{, address}.', category: 'input', priority: 'high', actions: [['respond', 'Respond'], ['view', 'View Task']] },
  approval_required: { title: 'VIPER — Approval Required', text: 'May I proceed{, address}?', category: 'approval', priority: 'high', actions: [['review', 'Review Request'], ['dismiss', 'Dismiss']] },
  error:             { title: 'VIPER — Attention Required', text: "I've encountered an issue{, address}.", category: 'system', priority: 'high', actions: [['view', 'View Details']] },
  project_complete:  { title: 'VIPER — Project Complete', text: 'Your project is ready for review{, address}.', category: 'code', priority: 'normal', actions: [['view', 'View Project'], ['open', 'Open VIPER']] },
  code_complete:     { title: 'VIPER — Code Agent', text: 'Your application has been built{, address}.', category: 'code', priority: 'normal', actions: [['view', 'View Results'], ['open', 'Open VIPER']] },
  download_complete: { title: 'VIPER — Download Complete', text: 'Your download is ready{, address}.', category: 'general', priority: 'low', actions: [['view', 'View']] },
  system_alert:      { title: 'VIPER — System Alert', text: 'Your system requires attention{, address}.', category: 'system', priority: 'high', actions: [['view', 'View Details']] },
};
const phrase = (text, address) => text.replace('{, address}', address ? `, ${address}` : '');
const DEDUPE_MS = 10 * 60000;
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
        // 1) Phones connected right now (app open, or "Stay connected" on): over the encrypted link.
        const delivered = remote.pushToDevices({ type: 'notification', data: n });
        // 2) Paired phones that are not connected: through Firebase Cloud Messaging, if set up.
        const pushed = await remote.pushViaFcm?.(n).catch((e) => ({ sent: 0, error: e.message })) || { sent: 0 };
        if (delivered > 0 || pushed.sent > 0) return { ok: true, detail: [delivered && `${delivered} connected`, pushed.sent && `${pushed.sent} via push`].filter(Boolean).join(', ') };
        return { ok: false, queued: true, error: pushed.error || 'No phone connected; it will receive this when it reconnects (or enable push in Settings → Notifications).' };
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
  /** Compose title/body for a kind, in VIPER's voice. */
  compose(kind, detail) {
    const k = KINDS[kind]; if (!k) return null;
    const address = (this.settings.get('personality').address || '').trim();
    const text = phrase(k.text, address);
    return { title: k.title, body: detail ? `${text} ${detail}` : text, phrase: text, category: k.category, priority: k.priority, actions: k.actions };
  }

  async send(n) {
    const cfg = this.settings.get('notifications');
    const k = n.kind ? this.compose(n.kind, n.detail) : null;
    const priority = PRIORITIES.includes(n.priority) ? n.priority : (k?.priority || 'normal');
    const category = n.category || k?.category || 'general';
    const link = n.link || null;
    const dedupeKey = n.dedupeKey || (n.kind && link ? `${n.kind}:${link.type}:${link.id}` : null);
    // Duplicate prevention: the same unread event within 10 minutes is not sent again.
    if (dedupeKey) {
      const dup = this.db.get('SELECT id FROM notifications WHERE dedupe_key = ? AND read = 0 AND created_at > ?', dedupeKey, now() - DEDUPE_MS);
      if (dup) return { id: dup.id, duplicate: true, channels: [], results: {}, suppressed: ['duplicate'] };
    }
    const rec = {
      id: uid('ntf_'), title: String(n.title || k?.title || 'VIPER').slice(0, 200), body: String(n.body || k?.body || '').slice(0, 4000), category, priority, created_at: now(),
      kind: n.kind || null, phrase: k?.phrase || null, link, actions: n.actions || k?.actions || null,
    };
    let channels = (n.channels && n.channels.length ? n.channels : cfg.defaultChannels).filter((c) => this.channels.has(c));
    const quiet = inQuietHours(cfg.quietHours) && !(priority === 'urgent' && cfg.quietHours.allowUrgent);
    const suppressed = [];
    if (cfg.categories?.[category] === false) { suppressed.push('category disabled'); channels = []; }
    if (cfg.emergencyMute) { suppressed.push('emergency mute'); channels = []; }
    if (quiet) { suppressed.push('quiet hours'); channels = channels.filter((c) => c === 'mobile'); }
    if (channels.some((c) => EXTERNAL.has(c)) && this.rateLimited()) { suppressed.push('rate limit'); channels = channels.filter((c) => !EXTERNAL.has(c)); }
    this.db.run('INSERT INTO notifications (id, title, body, category, priority, channels, status, created_at, kind, link, actions, dedupe_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      rec.id, rec.title, rec.body, rec.category, rec.priority, JSON.stringify(channels), suppressed.length && !channels.length ? 'suppressed' : 'sending', rec.created_at,
      rec.kind, link ? JSON.stringify(link) : null, rec.actions ? JSON.stringify(rec.actions) : null, dedupeKey);
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
    return rows.map((r) => ({ ...this.row(r), deliveries: del.filter((d) => d.notification_id === r.id) }));
  }
  row(r) { return { ...r, channels: JSON.parse(r.channels || '[]'), link: r.link ? JSON.parse(r.link) : null, actions: r.actions ? JSON.parse(r.actions) : null, read: !!r.read }; }
  get(id) { const r = this.db.get('SELECT * FROM notifications WHERE id = ?', id); return r ? this.row(r) : null; }
  since(ts) { return this.db.all('SELECT * FROM notifications WHERE created_at > ? ORDER BY created_at ASC LIMIT 200', ts).map((r) => this.row(r)); }
  markRead(id) { if (id === 'all') this.db.run('UPDATE notifications SET read = 1'); else this.db.run('UPDATE notifications SET read = 1 WHERE id = ?', id); this.bus.publish('notifications.read', { id }); }
  clear() { this.db.run('DELETE FROM deliveries'); this.db.run('DELETE FROM notifications'); }
  channelList() { return [...this.channels.entries()].map(([id, c]) => ({ id, label: c.label })); }
}

module.exports = { Notifier, inQuietHours, PRIORITIES, KINDS };
