'use strict';
// Tracks long-running VIPER tasks (model downloads, automations, research,
// image generation, indexing) for the "Active tasks" panel and
// "notify me when this finishes" requests.
class TaskWatch {
  constructor({ bus, notify }) {
    this.bus = bus; this.notify = notify;
    this.tasks = new Map();
    this.watchers = [];
    bus.on('task.update', (t) => this.update(t));
    bus.on('models.download', (d) => this.update({ id: `dl:${d.id}`, label: `Downloading ${d.model}`, kind: 'download', state: d.status === 'downloading' ? 'running' : d.status === 'done' ? 'done' : 'failed', progress: d.total ? d.completed / d.total : null, error: d.error }));
    bus.on('automation.run', (r) => this.update({ id: `auto:${r.runId}`, label: `Automation: ${r.name}`, kind: 'automation', state: r.state === 'started' ? 'running' : r.state === 'failed' ? 'failed' : 'done', error: r.error }));
  }
  update(t) {
    const prev = this.tasks.get(t.id) || { startedAt: Date.now() };
    const cur = { ...prev, ...t, updatedAt: Date.now() };
    this.tasks.set(t.id, cur);
    this.bus.publish('tasks.changed', { task: cur });
    if (cur.state !== 'running') {
      setTimeout(() => { if (this.tasks.get(t.id)?.state !== 'running') this.tasks.delete(t.id); this.bus.publish('tasks.changed', {}); }, 60000);
      for (const w of [...this.watchers]) {
        if (w.ids.has(t.id)) {
          w.ids.delete(t.id);
          this.notify.send({ title: cur.state === 'done' ? `${cur.label} — complete` : `${cur.label} — failed`, body: cur.error || 'Task finished.', category: 'general', priority: 'high', channels: w.channels });
          if (!w.ids.size) this.watchers.splice(this.watchers.indexOf(w), 1);
        }
      }
    }
  }
  activeTasks() { return [...this.tasks.values()].filter((t) => t.state === 'running'); }
  list() { return [...this.tasks.values()].sort((a, b) => b.startedAt - a.startedAt); }
  notifyOnCompletion(tasks, channels) { this.watchers.push({ ids: new Set(tasks.map((t) => t.id)), channels }); }
}
module.exports = { TaskWatch };
