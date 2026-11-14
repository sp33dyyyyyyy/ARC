'use strict';
// SQLite persistence via Node's built-in node:sqlite (bundled with Electron 45 / Node 24).
// Versioned migrations; FTS5 indexes for conversation, memory and document search.
process.removeAllListeners('warning'); // silence the "SQLite is experimental" notice
const { DatabaseSync } = require('node:sqlite');

const MIGRATIONS = [
  // v1 — core schema
  `
  CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS secrets (name TEXT PRIMARY KEY, value BLOB NOT NULL, updated_at INTEGER);

  CREATE TABLE conversations (
    id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT 'New conversation', mode TEXT NOT NULL DEFAULT 'chat',
    pinned INTEGER NOT NULL DEFAULT 0, private INTEGER NOT NULL DEFAULT 0, model TEXT, summary TEXT, summary_upto INTEGER,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
  CREATE TABLE messages (
    id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL, content TEXT NOT NULL DEFAULT '', tool_calls TEXT, tool_call_id TEXT, name TEXT,
    attachments TEXT, model TEXT, meta TEXT, created_at INTEGER NOT NULL);
  CREATE INDEX idx_messages_conv ON messages(conversation_id, created_at);
  CREATE VIRTUAL TABLE messages_fts USING fts5(content, message_id UNINDEXED, conversation_id UNINDEXED);

  CREATE TABLE memories (
    id TEXT PRIMARY KEY, category TEXT NOT NULL DEFAULT 'fact', content TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'user', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
  CREATE VIRTUAL TABLE memories_fts USING fts5(content, category, memory_id UNINDEXED);

  CREATE TABLE reminders (
    id TEXT PRIMARY KEY, text TEXT NOT NULL, due_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
    channels TEXT, created_at INTEGER NOT NULL, fired_at INTEGER);

  CREATE TABLE automations (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, enabled INTEGER NOT NULL DEFAULT 1,
    trigger TEXT NOT NULL, condition TEXT, actions TEXT NOT NULL, channels TEXT,
    last_run INTEGER, last_status TEXT, failures INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
  CREATE TABLE automation_runs (
    id TEXT PRIMARY KEY, automation_id TEXT NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER,
    status TEXT NOT NULL, output TEXT, error TEXT, trigger_data TEXT);
  CREATE INDEX idx_runs_auto ON automation_runs(automation_id, started_at);

  CREATE TABLE notifications (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT, category TEXT NOT NULL DEFAULT 'general',
    priority TEXT NOT NULL DEFAULT 'normal', channels TEXT, status TEXT NOT NULL DEFAULT 'pending',
    read INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
  CREATE TABLE deliveries (
    id TEXT PRIMARY KEY, notification_id TEXT NOT NULL, channel TEXT NOT NULL, recipient TEXT,
    status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, error TEXT, updated_at INTEGER NOT NULL);
  CREATE TABLE recipients (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT, phone TEXT, is_self INTEGER NOT NULL DEFAULT 0,
    approved_sms INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);

  CREATE TABLE devices (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, platform TEXT, token_hash TEXT NOT NULL,
    permissions TEXT, created_at INTEGER NOT NULL, last_seen INTEGER, last_ip TEXT, revoked INTEGER NOT NULL DEFAULT 0,
    push_token TEXT);

  CREATE TABLE activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, actor TEXT NOT NULL, action TEXT NOT NULL,
    detail TEXT, risk TEXT, outcome TEXT);
  CREATE INDEX idx_activity_ts ON activity(ts);

  CREATE TABLE model_perf (
    id INTEGER PRIMARY KEY AUTOINCREMENT, backend TEXT NOT NULL, model TEXT NOT NULL, ts INTEGER NOT NULL,
    ttft_ms INTEGER, tokens INTEGER, tok_per_s REAL, ok INTEGER NOT NULL DEFAULT 1);

  CREATE TABLE documents (
    id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, type TEXT, size INTEGER, mtime INTEGER,
    indexed_at INTEGER, chunk_count INTEGER NOT NULL DEFAULT 0, embedded INTEGER NOT NULL DEFAULT 0, summary TEXT, error TEXT);
  CREATE TABLE chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    idx INTEGER NOT NULL, text TEXT NOT NULL, embedding BLOB);
  CREATE INDEX idx_chunks_doc ON chunks(document_id);
  CREATE VIRTUAL TABLE chunks_fts USING fts5(text, chunk_id UNINDEXED, document_id UNINDEXED);

  CREATE TABLE research (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, query TEXT NOT NULL, mode TEXT NOT NULL, report TEXT,
    sources TEXT, status TEXT NOT NULL DEFAULT 'done', created_at INTEGER NOT NULL);

  CREATE TABLE images (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL, prompt TEXT, negative TEXT, params TEXT, path TEXT NOT NULL,
    parent_id TEXT, backend TEXT, created_at INTEGER NOT NULL);

  CREATE TABLE email_accounts (
    id TEXT PRIMARY KEY, label TEXT NOT NULL, provider TEXT NOT NULL, address TEXT NOT NULL,
    imap TEXT, smtp TEXT, auth_type TEXT NOT NULL, created_at INTEGER NOT NULL);
  CREATE TABLE email_templates (id TEXT PRIMARY KEY, name TEXT NOT NULL, subject TEXT, body TEXT, created_at INTEGER NOT NULL);
  CREATE TABLE outbox (
    id TEXT PRIMARY KEY, account_id TEXT, channel TEXT NOT NULL DEFAULT 'email', recipients TEXT NOT NULL,
    subject TEXT, body TEXT, send_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'scheduled',
    error TEXT, created_at INTEGER NOT NULL, sent_at INTEGER);

  CREATE TABLE plugins (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, version TEXT, enabled INTEGER NOT NULL DEFAULT 0,
    granted TEXT, manifest TEXT NOT NULL, path TEXT NOT NULL, installed_at INTEGER NOT NULL);

  CREATE TABLE workspaces (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL);

  CREATE TABLE transcripts (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, speaker TEXT NOT NULL, text TEXT NOT NULL, source TEXT);
  `,
];

class Database {
  constructor(file) {
    this.file = file;
    this.db = new DatabaseSync(file);
    this.db.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=3000;');
    this.migrate();
    this._stmts = new Map();
  }
  migrate() {
    this.db.exec('CREATE TABLE IF NOT EXISTS schema_version (v INTEGER NOT NULL)');
    const row = this.db.prepare('SELECT v FROM schema_version').get();
    let v = row ? row.v : 0;
    if (!row) this.db.prepare('INSERT INTO schema_version (v) VALUES (0)').run();
    while (v < MIGRATIONS.length) {
      this.db.exec('BEGIN');
      try {
        this.db.exec(MIGRATIONS[v]);
        v++;
        this.db.prepare('UPDATE schema_version SET v = ?').run(v);
        this.db.exec('COMMIT');
      } catch (e) { this.db.exec('ROLLBACK'); throw e; }
    }
    this.version = v;
  }
  stmt(sql) {
    let s = this._stmts.get(sql);
    if (!s) { s = this.db.prepare(sql); this._stmts.set(sql, s); }
    return s;
  }
  // After shutdown, late events (closing sockets, timers) must not crash the process.
  all(sql, ...params) { return this.closed ? [] : this.stmt(sql).all(...params); }
  get(sql, ...params) { return this.closed ? undefined : this.stmt(sql).get(...params); }
  run(sql, ...params) { return this.closed ? { changes: 0 } : this.stmt(sql).run(...params); }
  exec(sql) { return this.db.exec(sql); }
  tx(fn) {
    this.db.exec('BEGIN');
    try { const r = fn(); this.db.exec('COMMIT'); return r; } catch (e) { this.db.exec('ROLLBACK'); throw e; }
  }
  close() { this.closed = true; try { this.db.close(); } catch { /* already closed */ } }
}

// Escape user text for an FTS5 MATCH query: every term quoted, prefix-matched.
function ftsQuery(q) {
  const terms = String(q || '').toLowerCase().match(/[\p{L}\p{N}_]+/gu) || [];
  if (!terms.length) return null;
  return terms.slice(0, 12).map((t) => `"${t}"*`).join(' OR ');
}

module.exports = { Database, ftsQuery };
