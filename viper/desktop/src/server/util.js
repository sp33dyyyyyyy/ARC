'use strict';
const crypto = require('node:crypto');

const uid = (prefix = '') => prefix + crypto.randomBytes(9).toString('base64url');
const now = () => Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

function jsonParse(s, fallback = null) {
  if (s == null) return fallback;
  try { return JSON.parse(s); } catch { return fallback; }
}

// Rough token estimate (~4 chars/token English). Used only for context budgeting.
const estimateTokens = (s) => Math.ceil((s || '').length / 4);

function sha256(s) { return crypto.createHash('sha256').update(s).digest('hex'); }

function timingSafeEqualStr(a, b) {
  const ba = Buffer.from(String(a)); const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

function formatBytes(n) {
  if (n == null || isNaN(n)) return '—';
  const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0; let v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 10 || i === 0 ? 0 : 1)} ${u[i]}`;
}

async function fetchWithTimeout(url, opts = {}, ms = 15000) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(new Error('timeout')), ms);
  if (opts.signal) opts.signal.addEventListener('abort', () => ctl.abort(opts.signal.reason), { once: true });
  try { return await fetch(url, { ...opts, signal: ctl.signal }); } finally { clearTimeout(t); }
}

module.exports = { uid, now, sleep, clamp, jsonParse, estimateTokens, sha256, timingSafeEqualStr, formatBytes, fetchWithTimeout };
