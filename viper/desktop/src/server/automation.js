'use strict';
// Automation engine. An automation = trigger + optional condition + actions.
// Triggers: once | interval | cron | folder (new files) | download (finished download in a folder)
//           | system (metric threshold) | startup | manual
// Actions:  notify | speak | briefing | system_report | ai_prompt | tool | open_app | email_report
// Conditions are structured comparisons (never eval'd code).
const fs = require('node:fs');
const path = require('node:path');
const { Cron } = require('croner');
const { uid, now, jsonParse } = require('./util');

const PARTIAL_EXT = /\.(crdownload|part|partial|download|tmp|!ut|opdownload)$/i;
const OPS = { '>': (a, b) => a > b, '>=': (a, b) => a >= b, '<': (a, b) => a < b, '<=': (a, b) => a <= b, '==': (a, b) => a == b, '!=': (a, b) => a != b, contains: (a, b) => String(a).toLowerCase().includes(String(b).toLowerCase()) }; // eslint-disable-line eqeqeq

function getPath(obj, p) { return String(p).split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj); }

function evalCondition(cond, data) {
  if (!cond) return true;
  if (Array.isArray(cond.all)) return cond.all.every((c) => evalCondition(c, data));
  if (Array.isArray(cond.any)) return cond.any.some((c) => evalCondition(c, data));
  const op = OPS[cond.op];
  if (!op) return false;
  return op(getPath(data, cond.field), cond.value);
}

class AutomationEngine {
  constructor(svc) {
    this.svc = svc; this.db = svc.db; this.bus = svc.bus; this.log = svc.log.scope ? svc.log : svc.log;
    this.jobs = new Map(); // id -> { stop() }
    this.running = new Set();
  }
  rows() { return this.db.all('SELECT * FROM automations ORDER BY created_at DESC'); }
  parse(r) { return r && { ...r, enabled: !!r.enabled, trigger: jsonParse(r.trigger, {}), condition: jsonParse(r.condition), actions: jsonParse(r.actions, []), channels: jsonParse(r.channels, []) }; }
  list() {
    return this.rows().map((r) => {
      const a = this.parse(r);
      a.nextRun = this.jobs.get(a.id)?.next?.() || null;
      return a;
    });
  }
  get(id) { return this.parse(this.db.get('SELECT * FROM automations WHERE id = ?', id)); }

  validate(a) {
    const T = ['once', 'interval', 'cron', 'folder', 'download', 'system', 'startup', 'manual'];
    if (!a.name) throw new Error('Automation needs a name');
    if (!a.trigger || !T.includes(a.trigger.type)) throw new Error(`Trigger type must be one of ${T.join(', ')}`);
    if (a.trigger.type === 'cron') { try { new Cron(a.trigger.cron, { paused: true }).stop(); } catch { throw new Error(`Invalid cron expression "${a.trigger.cron}"`); } }
    if (a.trigger.type === 'interval' && !(a.trigger.minutes >= 1)) throw new Error('Interval must be at least 1 minute');
    if (a.trigger.type === 'once' && !(a.trigger.at > 0)) throw new Error('One-off trigger needs a time');
    if (['folder', 'download'].includes(a.trigger.type)) {
      if (!a.trigger.folder) throw new Error('Folder trigger needs a folder');
      if (!this.svc.permissions.isPathAllowed(a.trigger.folder)) throw new Error('Watched folder must be inside the allowed folders');
    }
    if (!Array.isArray(a.actions) || !a.actions.length) throw new Error('Automation needs at least one action');
    const A = ['notify', 'speak', 'briefing', 'system_report', 'ai_prompt', 'tool', 'open_app', 'email_report', 'research', 'plugin'];
    for (const act of a.actions) if (!A.includes(act.type)) throw new Error(`Unknown action "${act.type}"`);
  }

  create(a) {
    this.validate(a);
    const id = uid('auto_');
    this.db.run(`INSERT INTO automations (id, name, description, enabled, trigger, condition, actions, channels, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, a.name, a.description || '', a.enabled === false ? 0 : 1, JSON.stringify(a.trigger),
    a.condition ? JSON.stringify(a.condition) : null, JSON.stringify(a.actions), JSON.stringify(a.channels || []), now(), now());
    this.schedule(this.get(id));
    this.bus.publish('automations.changed', {});
    return this.get(id);
  }
  update(id, patch) {
    const cur = this.get(id);
    if (!cur) throw new Error('Automation not found');
    const next = { ...cur, ...patch };
    this.validate(next);
    this.db.run('UPDATE automations SET name=?, description=?, enabled=?, trigger=?, condition=?, actions=?, channels=?, updated_at=? WHERE id=?',
      next.name, next.description || '', next.enabled ? 1 : 0, JSON.stringify(next.trigger), next.condition ? JSON.stringify(next.condition) : null,
      JSON.stringify(next.actions), JSON.stringify(next.channels || []), now(), id);
    this.unschedule(id); this.schedule(this.get(id));
    this.bus.publish('automations.changed', {});
    return this.get(id);
  }
  setEnabled(id, enabled) { return this.update(id, { enabled }); }
  delete(id) { this.unschedule(id); this.db.run('DELETE FROM automations WHERE id = ?', id); this.db.run('DELETE FROM automation_runs WHERE automation_id = ?', id); this.bus.publish('automations.changed', {}); }
  history(id, limit = 50) { return id ? this.db.all('SELECT * FROM automation_runs WHERE automation_id = ? ORDER BY started_at DESC LIMIT ?', id, limit) : this.db.all('SELECT r.*, a.name FROM automation_runs r LEFT JOIN automations a ON a.id = r.automation_id ORDER BY r.started_at DESC LIMIT ?', limit); }

  start() {
    for (const r of this.rows()) this.schedule(this.parse(r));
    // Built-in proactive jobs are scheduled by the proactive module.
  }
  stop() { for (const id of [...this.jobs.keys()]) this.unschedule(id); }
  unschedule(id) { const j = this.jobs.get(id); if (j) { try { j.stop(); } catch { /* ignore */ } this.jobs.delete(id); } }

  schedule(a) {
    if (!a || !a.enabled) return;
    const t = a.trigger;
    const fire = (data) => this.run(a.id, data).catch((e) => this.log.warn('automation run', e));
    try {
      if (t.type === 'cron') {
        const c = new Cron(t.cron, () => fire({ trigger: 'cron' }));
        this.jobs.set(a.id, { stop: () => c.stop(), next: () => c.nextRun()?.getTime() || null });
      } else if (t.type === 'interval') {
        const ms = t.minutes * 60000;
        let next = Date.now() + ms;
        const h = setInterval(() => { next = Date.now() + ms; fire({ trigger: 'interval' }); }, ms);
        this.jobs.set(a.id, { stop: () => clearInterval(h), next: () => next });
      } else if (t.type === 'once') {
        const delay = t.at - Date.now();
        if (delay <= 0 && a.last_run) return;
        const h = setTimeout(() => { fire({ trigger: 'once' }); this.update(a.id, { enabled: false }); }, Math.max(0, Math.min(delay, 2 ** 31 - 1)));
        this.jobs.set(a.id, { stop: () => clearTimeout(h), next: () => t.at });
      } else if (t.type === 'folder' || t.type === 'download') {
        this.watchFolder(a, fire);
      } else if (t.type === 'system') {
        const handler = (s) => {
          const val = getPath(s, t.metric);
          if (val == null) return;
          const hit = OPS[t.op || '>'](val, t.value);
          const st = this.jobs.get(a.id);
          if (hit && !st.active && Date.now() - (st.lastFired || 0) > (t.cooldownMin || 30) * 60000) { st.active = true; st.lastFired = Date.now(); fire({ trigger: 'system', metric: t.metric, value: val }); }
          if (!hit) st.active = false;
        };
        this.bus.on('system.sample', handler);
        this.jobs.set(a.id, { stop: () => this.bus.off('system.sample', handler), active: false, next: () => null });
      } else if (t.type === 'startup') {
        if (!this.startedOnce) setTimeout(() => fire({ trigger: 'startup' }), 5000);
        this.jobs.set(a.id, { stop: () => {}, next: () => null });
      }
    } catch (e) { this.log.warn(`schedule ${a.name}`, e); }
  }

  watchFolder(a, fire) {
    const t = a.trigger;
    if (!fs.existsSync(t.folder)) { this.log.warn(`watch folder missing: ${t.folder}`); return; }
    const known = new Set(fs.readdirSync(t.folder));
    const pendingTimers = new Map();
    let watcher;
    const check = (name) => {
      if (!name || known.has(name)) return;
      const full = path.join(t.folder, name);
      if (!fs.existsSync(full)) return;
      if (t.type === 'download' && PARTIAL_EXT.test(name)) return; // still downloading
      if (t.pattern && !new RegExp(t.pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.'), 'i').test(name)) return;
      // Wait until the file size is stable (download/copy finished).
      clearTimeout(pendingTimers.get(name));
      let lastSize = -1;
      const stableCheck = () => {
        let st; try { st = fs.statSync(full); } catch { return; }
        if (st.size === lastSize) { known.add(name); fire({ trigger: t.type, file: name, path: full, size: st.size }); }
        else { lastSize = st.size; pendingTimers.set(name, setTimeout(stableCheck, 2000)); }
      };
      pendingTimers.set(name, setTimeout(stableCheck, 1500));
    };
    try { watcher = fs.watch(t.folder, (_ev, name) => check(name)); } catch (e) { this.log.warn('fs.watch failed', e); }
    // Polling fallback (network drives / missed events).
    const poll = setInterval(() => { try { for (const n of fs.readdirSync(t.folder)) check(n); } catch { /* ignore */ } }, 10000);
    this.jobs.set(a.id, { stop: () => { watcher?.close(); clearInterval(poll); for (const h of pendingTimers.values()) clearTimeout(h); }, next: () => null });
  }

  async run(id, triggerData = { trigger: 'manual' }) {
    const a = this.get(id);
    if (!a) throw new Error('Automation not found');
    if (this.running.has(id)) return { skipped: 'already running' };
    this.running.add(id);
    const runId = uid('run_');
    this.db.run('INSERT INTO automation_runs (id, automation_id, started_at, status, trigger_data) VALUES (?, ?, ?, ?, ?)', runId, id, now(), 'running', JSON.stringify(triggerData));
    this.bus.publish('automation.run', { id, runId, name: a.name, state: 'started' });
    const outputs = [];
    let status = 'success'; let error = null;
    try {
      const data = { ...triggerData, system: this.svc.monitor.latest };
      if (a.condition && !evalCondition(a.condition, data)) { status = 'skipped'; outputs.push('Condition not met.'); }
      else {
        for (const act of a.actions) outputs.push(await this.runAction(act, a, data));
      }
    } catch (e) { status = 'failed'; error = e.message; }
    this.db.run('UPDATE automation_runs SET finished_at = ?, status = ?, output = ?, error = ? WHERE id = ?', now(), status, outputs.join('\n---\n').slice(0, 20000), error, runId);
    this.db.run('UPDATE automations SET last_run = ?, last_status = ?, failures = CASE WHEN ? = \'failed\' THEN failures + 1 ELSE 0 END WHERE id = ?', now(), status, status, id);
    this.running.delete(id);
    this.bus.publish('automation.run', { id, runId, name: a.name, state: status, error });
    this.bus.publish('automations.changed', {});
    if (status === 'failed' && this.svc.settings.get('proactive').failedAutomations) {
      await this.svc.notify.send({ title: `Automation failed: ${a.name}`, body: error, category: 'automation', priority: 'high', channels: a.channels.length ? a.channels : undefined });
    }
    return { status, outputs, error };
  }

  async runAction(act, a, data) {
    const svc = this.svc;
    const channels = act.channels || (a.channels.length ? a.channels : undefined);
    const fill = (s) => String(s || '').replace(/\{(\w+(?:\.\w+)*)\}/g, (_, k) => { const v = getPath(data, k); return v == null ? '' : String(v); });
    switch (act.type) {
      case 'notify': {
        const r = await svc.notify.send({ title: fill(act.title || a.name), body: fill(act.message || ''), category: 'automation', priority: act.priority || 'normal', channels, speak: !!act.speak });
        return `Notification sent via ${r.channels.join(', ') || 'in-app only'}${r.suppressed.length ? ` (suppressed: ${r.suppressed.join(', ')})` : ''}`;
      }
      case 'speak': this.bus.publish('voice.speak', { text: fill(act.message) }); return `Spoke: ${fill(act.message)}`;
      case 'briefing': {
        const b = await svc.briefing.build(act.kind || 'morning');
        await svc.notify.send({ title: b.title, body: b.text, category: 'system', channels, speak: act.speak !== false });
        return b.text;
      }
      case 'system_report': {
        const b = await svc.briefing.systemReport();
        await svc.notify.send({ title: 'PC status report', body: b, category: 'system', channels });
        return b;
      }
      case 'email_report': {
        const b = act.kind === 'system' ? await svc.briefing.systemReport() : (await svc.briefing.build(act.kind || 'daily')).text;
        const r = await svc.email.sendToSelf({ subject: `VIPER: ${a.name}`, text: b });
        if (!r.ok) throw new Error(r.error);
        return 'Email report sent.';
      }
      case 'ai_prompt': {
        const r = await svc.models.complete({ role: 'chat', messages: [{ role: 'system', content: svc.orchestrator.systemPrompt({ automation: true }) }, { role: 'user', content: fill(act.prompt) }], options: { maxTokens: 600 } });
        if (act.notify !== false) await svc.notify.send({ title: a.name, body: r.text.slice(0, 1500), category: 'automation', channels });
        return r.text;
      }
      case 'research': {
        const r = await svc.research.run({ query: fill(act.query), web: true, actor: 'automation' });
        await svc.notify.send({ title: `Research complete: ${r.title}`, body: r.report.slice(0, 600), category: 'research', channels });
        return r.report;
      }
      case 'tool': {
        const r = await svc.tools.execute(act.tool, act.args || {}, { actor: `automation:${a.name}`, noInteractive: true, origin: 'automation' });
        if (!r.ok) throw new Error(r.error);
        return JSON.stringify(r.result).slice(0, 2000);
      }
      case 'open_app': {
        const r = await svc.tools.execute('open_app', { name: act.app }, { actor: `automation:${a.name}`, noInteractive: true });
        if (!r.ok) throw new Error(r.error);
        return `Opened ${act.app}`;
      }
      case 'plugin': {
        const r = await svc.plugins.call(act.plugin, 'actions', act.action, { ...(act.args || {}), trigger: data.trigger, file: data.file });
        return `Plugin action ${act.plugin}/${act.action}: ${JSON.stringify(r).slice(0, 500)}`;
      }
      default: throw new Error(`Unknown action ${act.type}`);
    }
  }
}

module.exports = { AutomationEngine, evalCondition, PARTIAL_EXT };
