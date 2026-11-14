'use strict';
const { uid, now } = require('./util');

class Reminders {
  constructor({ db, bus, notify, log }) { this.db = db; this.bus = bus; this.notify = notify; this.log = log; this.timer = null; }
  start() { const tick = () => { this.check().catch((e) => this.log.warn('reminder check', e)); this.timer = setTimeout(tick, 15000); }; tick(); }
  stop() { clearTimeout(this.timer); }
  add({ text, dueAt, channels }) {
    if (!text) throw new Error('Reminder text required');
    if (!dueAt || Number.isNaN(dueAt)) throw new Error('A due time is required');
    const r = { id: uid('rem_'), text, due_at: dueAt, status: 'pending', channels: JSON.stringify(channels || []), created_at: now() };
    this.db.run('INSERT INTO reminders (id, text, due_at, status, channels, created_at) VALUES (?, ?, ?, ?, ?, ?)', r.id, r.text, r.due_at, r.status, r.channels, r.created_at);
    this.bus.publish('reminders.changed', {});
    return r;
  }
  list(status) {
    return status ? this.db.all('SELECT * FROM reminders WHERE status = ? ORDER BY due_at', status) : this.db.all('SELECT * FROM reminders ORDER BY CASE status WHEN \'pending\' THEN 0 ELSE 1 END, due_at DESC LIMIT 200');
  }
  update(id, patch) {
    const r = this.db.get('SELECT * FROM reminders WHERE id = ?', id);
    if (!r) throw new Error('Not found');
    this.db.run('UPDATE reminders SET text = ?, due_at = ?, status = ? WHERE id = ?', patch.text ?? r.text, patch.dueAt ?? r.due_at, patch.status ?? r.status, id);
    this.bus.publish('reminders.changed', {});
  }
  delete(id) { this.db.run('DELETE FROM reminders WHERE id = ?', id); this.bus.publish('reminders.changed', {}); }
  async check() {
    const due = this.db.all("SELECT * FROM reminders WHERE status = 'pending' AND due_at <= ?", now());
    for (const r of due) {
      this.db.run("UPDATE reminders SET status = 'fired', fired_at = ? WHERE id = ?", now(), r.id);
      let channels = []; try { channels = JSON.parse(r.channels || '[]'); } catch { /* none */ }
      await this.notify.send({ title: 'Reminder', body: r.text, category: 'reminder', priority: 'high', channels: channels.length ? channels : undefined, speak: true });
      this.bus.publish('reminders.changed', {});
    }
  }
}
module.exports = { Reminders };
