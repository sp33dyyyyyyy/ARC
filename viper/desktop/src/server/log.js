'use strict';
// Sanitised file logger. Secrets, bearer tokens, passwords and API keys are
// redacted before anything touches disk.
const fs = require('node:fs');
const path = require('node:path');

const REDACTIONS = [
  [/(authorization["']?\s*[:=]\s*["']?)(bearer\s+)?[^\s"',}]+/gi, '$1[REDACTED]'],
  [/((?:pass(?:word)?|secret|token|api[_-]?key|access_token|refresh_token|client_secret)["']?\s*[:=]\s*["']?)[^\s"',}&]+/gi, '$1[REDACTED]'],
  [/\b(sk|pk|rk|xox[abp])-[A-Za-z0-9_-]{10,}\b/g, '[REDACTED_KEY]'],
  [/([?&](?:token|key|access_token|code)=)[^&\s]+/gi, '$1[REDACTED]'],
];

function sanitize(text) {
  let s = typeof text === 'string' ? text : safeStringify(text);
  for (const [re, rep] of REDACTIONS) s = s.replace(re, rep);
  return s;
}

function safeStringify(v) {
  if (v instanceof Error) return `${v.name}: ${v.message}${v.stack ? '\n' + v.stack.split('\n').slice(1, 6).join('\n') : ''}`;
  try { return JSON.stringify(v); } catch { return String(v); }
}

class Logger {
  constructor(dir, { echo = false, level = 'info' } = {}) {
    this.dir = dir;
    this.echo = echo;
    this.levels = { debug: 10, info: 20, warn: 30, error: 40 };
    this.level = this.levels[level] || 20;
    this.recent = []; // in-memory ring for the UI
  }
  file() {
    const d = new Date().toISOString().slice(0, 10);
    return path.join(this.dir, `viper-${d}.log`);
  }
  write(level, scope, ...args) {
    if ((this.levels[level] || 20) < this.level) return;
    const msg = args.map((a) => sanitize(a)).join(' ');
    const line = `${new Date().toISOString()} ${level.toUpperCase().padEnd(5)} [${scope}] ${msg}`;
    this.recent.push({ ts: Date.now(), level, scope, msg });
    if (this.recent.length > 500) this.recent.shift();
    if (this.echo) (level === 'error' ? console.error : console.log)(line);
    try { if (this.dir) fs.appendFileSync(this.file(), line + '\n'); } catch { /* disk full etc. */ }
  }
  scope(name) {
    return {
      debug: (...a) => this.write('debug', name, ...a),
      info: (...a) => this.write('info', name, ...a),
      warn: (...a) => this.write('warn', name, ...a),
      error: (...a) => this.write('error', name, ...a),
    };
  }
  prune(days = 14) {
    try {
      const cutoff = Date.now() - days * 86400000;
      for (const f of fs.readdirSync(this.dir)) {
        const fp = path.join(this.dir, f);
        if (fs.statSync(fp).mtimeMs < cutoff) fs.unlinkSync(fp);
      }
    } catch { /* ignore */ }
  }
}

module.exports = { Logger, sanitize };
