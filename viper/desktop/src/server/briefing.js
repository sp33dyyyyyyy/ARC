'use strict';
// Morning briefing / evening summary / system reports assembled from real data.
const { Cron } = require('croner');
const { formatBytes } = require('./util');

class Briefing {
  constructor(svc) { this.svc = svc; this.jobs = []; }

  async systemReport() {
    const s = await this.svc.monitor.snapshot();
    const lines = [
      `CPU ${s.cpu?.pct ?? '?'}% · Memory ${s.mem?.pct ?? '?'}% (${formatBytes(s.mem?.used)} of ${formatBytes(s.mem?.total)})`,
      ...s.disks.map((d) => `Drive ${d.mount}: ${d.pct}% used, ${formatBytes(d.size - d.used)} free`),
      s.temp?.cpu ? `CPU temperature ${s.temp.cpu}°C` : 'CPU temperature: sensor not available',
      s.battery ? `Battery ${s.battery.pct}%${s.battery.charging ? ' (charging)' : ''}` : null,
      `Internet: ${s.online ? 'connected' : 'offline'}`,
    ].filter(Boolean);
    return lines.join('\n');
  }

  assess(s) {
    const issues = [];
    if (s.mem?.pct > 85) issues.push('memory consumption is high');
    else if (s.mem?.pct > 70) issues.push('memory consumption is slightly elevated');
    if (s.cpu?.pct > 80) issues.push('the processor is under heavy load');
    for (const d of s.disks) if (d.pct > 90) issues.push(`drive ${d.mount} is nearly full`);
    if (s.temp?.cpu > 85) issues.push('the CPU is running hot');
    return issues;
  }

  async build(kind = 'morning') {
    const svc = this.svc;
    const s = await svc.monitor.snapshot();
    const issues = this.assess(s);
    const pendingRem = svc.reminders.list('pending');
    const todayEnd = new Date(); todayEnd.setHours(23, 59, 59, 999);
    const dueToday = pendingRem.filter((r) => r.due_at <= todayEnd.getTime());
    const autos = svc.automation.list();
    const failed = autos.filter((a) => a.last_status === 'failed');
    const since = Date.now() - (kind === 'evening' ? 14 : 24) * 3600000;
    const notes = svc.db.all('SELECT title FROM notifications WHERE created_at > ? AND category != ? ORDER BY created_at DESC LIMIT 5', since, 'system');
    const runs = svc.db.get('SELECT COUNT(*) AS n, SUM(CASE WHEN status = \'failed\' THEN 1 ELSE 0 END) AS f FROM automation_runs WHERE started_at > ?', since);
    const p = svc.settings.get('personality');
    const greet = kind === 'evening' ? 'Good evening' : kind === 'morning' ? 'Good morning' : 'Here is your summary';
    const name = p.userName ? `, ${p.userName}` : '';
    const parts = [];
    parts.push(`${greet}${name}. ${issues.length ? `Your computer is running, though ${issues.join(' and ')}.` : 'Your computer is running normally.'}`);
    parts.push(dueToday.length ? `You have ${dueToday.length} reminder${dueToday.length > 1 ? 's' : ''} due today: ${dueToday.slice(0, 3).map((r) => `${r.text} at ${new Date(r.due_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`).join('; ')}.` : (pendingRem.length ? `You have ${pendingRem.length} upcoming reminder${pendingRem.length > 1 ? 's' : ''}, none due today.` : 'No reminders are scheduled.'));
    if (failed.length) parts.push(`${failed.length} automation${failed.length > 1 ? 's need' : ' needs'} review: ${failed.map((a) => a.name).join(', ')}.`);
    else if (runs?.n) parts.push(`${runs.n} automation run${runs.n > 1 ? 's' : ''} completed${runs.f ? `, ${runs.f} failed` : ' without errors'}.`);
    if (notes.length) parts.push(`Recent notices: ${notes.map((n) => n.title).join('; ')}.`);
    const enabled = autos.filter((a) => a.enabled).length;
    if (kind === 'morning' && enabled) parts.push(`${enabled} automation${enabled > 1 ? 's are' : ' is'} active today.`);
    return { title: kind === 'evening' ? 'Evening summary' : kind === 'morning' ? 'Morning briefing' : 'Daily summary', text: parts.join(' '), data: { issues, dueToday: dueToday.length, failed: failed.length } };
  }

  /** (Re)schedule the proactive morning/evening jobs from settings. */
  scheduleProactive() {
    for (const j of this.jobs) j.stop();
    this.jobs = [];
    const p = this.svc.settings.get('proactive');
    if (!p.enabled) return;
    const add = (cfg, kind) => {
      if (!cfg?.enabled || !/^\d{1,2}:\d{2}$/.test(cfg.time)) return;
      const [h, m] = cfg.time.split(':').map(Number);
      this.jobs.push(new Cron(`${m} ${h} * * *`, async () => {
        const b = await this.build(kind);
        await this.svc.notify.send({ title: b.title, body: b.text, category: 'system', channels: cfg.channels, speak: true });
      }));
    };
    add(p.morningBriefing, 'morning');
    add(p.eveningSummary, 'evening');
  }
}

module.exports = { Briefing };
