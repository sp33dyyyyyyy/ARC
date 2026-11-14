'use strict';
// Long-term memory: explicit, user-controlled facts and preferences stored in
// SQLite with FTS5 search. Temporary-memory mode keeps new memories in RAM only.
const { uid, now } = require('./util');
const { ftsQuery } = require('./db');

const CATEGORIES = ['preference', 'fact', 'project', 'app', 'reminder', 'workflow', 'person', 'other'];

class MemoryStore {
  constructor({ db, settings, bus }) { this.db = db; this.settings = settings; this.bus = bus; this.temp = []; }
  isTemporary() { return !!this.settings.get('privacy').temporaryMemory; }

  add({ content, category = 'fact', source = 'user' }) {
    content = String(content || '').trim();
    if (!content) throw new Error('Memory content is empty');
    if (!CATEGORIES.includes(category)) category = 'other';
    const dup = this.search(content, 3).find((m) => m.content.toLowerCase() === content.toLowerCase());
    if (dup) return { ...dup, duplicate: true };
    const m = { id: uid('mem_'), category, content, source, created_at: now(), updated_at: now() };
    if (this.isTemporary()) { this.temp.push({ ...m, temporary: true }); this.bus.publish('memory.changed', {}); return { ...m, temporary: true }; }
    this.db.tx(() => {
      this.db.run('INSERT INTO memories (id, category, content, source, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)', m.id, m.category, m.content, m.source, m.created_at, m.updated_at);
      this.db.run('INSERT INTO memories_fts (content, category, memory_id) VALUES (?, ?, ?)', m.content, m.category, m.id);
    });
    this.bus.publish('memory.changed', {});
    return m;
  }
  update(id, { content, category }) {
    const cur = this.get(id);
    if (!cur) throw new Error('Memory not found');
    const next = { content: content ?? cur.content, category: category ?? cur.category };
    this.db.tx(() => {
      this.db.run('UPDATE memories SET content = ?, category = ?, updated_at = ? WHERE id = ?', next.content, next.category, now(), id);
      this.db.run('DELETE FROM memories_fts WHERE memory_id = ?', id);
      this.db.run('INSERT INTO memories_fts (content, category, memory_id) VALUES (?, ?, ?)', next.content, next.category, id);
    });
    this.bus.publish('memory.changed', {});
    return this.get(id);
  }
  get(id) { return this.db.get('SELECT * FROM memories WHERE id = ?', id) || this.temp.find((t) => t.id === id) || null; }
  delete(id) {
    const t = this.temp.findIndex((x) => x.id === id);
    if (t >= 0) { this.temp.splice(t, 1); this.bus.publish('memory.changed', {}); return true; }
    const r = this.db.tx(() => { this.db.run('DELETE FROM memories_fts WHERE memory_id = ?', id); return this.db.run('DELETE FROM memories WHERE id = ?', id); });
    this.bus.publish('memory.changed', {});
    return r.changes > 0;
  }
  clear() {
    this.db.tx(() => { this.db.run('DELETE FROM memories_fts'); this.db.run('DELETE FROM memories'); });
    this.temp = [];
    this.bus.publish('memory.changed', {});
  }
  list({ category, limit = 500 } = {}) {
    const rows = category ? this.db.all('SELECT * FROM memories WHERE category = ? ORDER BY updated_at DESC LIMIT ?', category, limit)
      : this.db.all('SELECT * FROM memories ORDER BY updated_at DESC LIMIT ?', limit);
    return [...this.temp.filter((t) => !category || t.category === category), ...rows];
  }
  search(query, limit = 8) {
    const q = ftsQuery(query);
    if (!q) return [];
    const rows = this.db.all(`SELECT m.*, bm25(memories_fts) AS rank FROM memories_fts JOIN memories m ON m.id = memories_fts.memory_id
      WHERE memories_fts MATCH ? ORDER BY rank LIMIT ?`, q, limit);
    const terms = String(query).toLowerCase().split(/\W+/).filter((t) => t.length > 2);
    const temp = this.temp.filter((t) => terms.some((w) => t.content.toLowerCase().includes(w)));
    return [...temp, ...rows];
  }
  /** Memories to inject into the system prompt: preferences always, plus query-relevant ones. */
  relevant(query, limit = 8) {
    const prefs = this.db.all("SELECT * FROM memories WHERE category = 'preference' ORDER BY updated_at DESC LIMIT 8");
    const rel = query ? this.search(query, limit) : [];
    const seen = new Set(); const out = [];
    for (const m of [...prefs, ...this.temp.slice(-5), ...rel]) { if (!seen.has(m.id)) { seen.add(m.id); out.push(m); } }
    return out.slice(0, 14);
  }
  export() { return { format: 'viper-memory', version: 1, exportedAt: new Date().toISOString(), memories: this.list({ limit: 100000 }).filter((m) => !m.temporary).map(({ id, category, content, source, created_at }) => ({ id, category, content, source, created_at })) }; }
  import(data) {
    if (!data || data.format !== 'viper-memory' || !Array.isArray(data.memories)) throw new Error('Not a VIPER memory export file');
    let added = 0;
    for (const m of data.memories) { const r = this.add({ content: m.content, category: m.category, source: 'import' }); if (!r.duplicate) added++; }
    return { added, total: data.memories.length };
  }
}

module.exports = { MemoryStore, CATEGORIES };
