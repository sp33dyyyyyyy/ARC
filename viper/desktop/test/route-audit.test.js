'use strict';
// Dead-button audit: every API call written in the desktop UI, the HUD and the Android app
// must reach a real route on the VIPER core. A missing route means a button that does nothing.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startViper } = require('./helpers/env');

const ROOT = path.join(__dirname, '..');
const MOBILE = path.join(ROOT, '..', 'mobile', 'app', 'src', 'main', 'java');

function walk(dir, ext, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, ext, out); else if (p.endsWith(ext)) out.push(p);
  }
  return out;
}
// `${cond ? 'enable' : 'disable'}` path segments expand to both variants; a `${...}` glued to
// the end of a segment builds a query string and is dropped; other `${...}` are parameters.
function expand(p) {
  const m = p.match(/\$\{[^}]*\?\s*'([\w-]+)'\s*:\s*'([\w-]+)'\s*\}/);
  return m ? [...expand(p.replace(m[0], m[1])), ...expand(p.replace(m[0], m[2]))] : [p];
}
const normalise = (p) => {
  const q = p.search(/[^/]\$\{/); if (q >= 0) p = p.slice(0, q + 1);
  return p.replace(/\$\{[^}]*\}/g, 'X').replace(/\$[a-zA-Z_][\w.]*(\(\))?/g, 'X').split('?')[0].replace(/\/+$/, '') || '/';
};

function rendererCalls() {
  const calls = [];
  const METHOD = { get: 'GET', post: 'POST', patch: 'PATCH', del: 'DELETE', url: 'GET' };
  for (const f of walk(path.join(ROOT, 'src', 'renderer'), '.js')) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/\bapi\.(get|post|patch|del|url)\(\s*(['`])((?:(?!\2).)*)\2/g)) {
      for (const v of expand(m[3])) calls.push({ file: path.relative(ROOT, f), method: METHOD[m[1]], path: `/api/v1${normalise(v)}` });
    }
  }
  return calls;
}
function mobileCalls() {
  const calls = [];
  const METHOD = { getObj: 'GET', getArr: 'GET', getBytes: 'GET', post: 'POST', postBytes: 'POST', postForBytes: 'POST', patch: 'PATCH', delete: 'DELETE' };
  for (const f of walk(MOBILE, '.kt')) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/\.(getObj|getArr|getBytes|post|postBytes|postForBytes|patch|delete)\(\s*"(\/api\/v1(?:[^"$]|\$\{[^}]*\}|\$\w+)*)"/g)) {
      calls.push({ file: path.relative(path.join(ROOT, '..'), f), method: METHOD[m[1]], path: normalise(m[2]) });
    }
  }
  return calls;
}

test('every UI and phone API call has a server route', async (t) => {
  const svc = await startViper('routes');
  t.after(() => svc.shutdown());
  const calls = [...rendererCalls(), ...mobileCalls()];
  assert.ok(calls.length > 150, `found ${calls.length} API calls to audit`);
  // Routes served by the phone link's own HTTPS listener (pairing, handshake, event stream).
  const remoteOnly = new Set(['POST /api/v1/pair', 'GET /api/v1/hello', 'GET /api/v1/device/me', 'POST /api/v1/transfer/upload', 'GET /api/v1/transfer/list', 'POST /api/v1/sms/result']);
  const servedByPhoneLink = (c) => remoteOnly.has(`${c.method} ${c.path}`) || (c.method === 'GET' && c.path.startsWith('/api/v1/transfer/file/'));
  const missing = calls.filter((c) => !servedByPhoneLink(c) && !svc.router.match(c.method, c.path));
  assert.deepEqual(missing, [], `API calls with no route:\n${missing.map((m) => `${m.method} ${m.path}  (${m.file})`).join('\n')}`);
});

test('every phone API call targets a route a paired device may use', async (t) => {
  const svc = await startViper('routes-phone');
  t.after(() => svc.shutdown());
  const phoneOnly = /^\/api\/v1\/(pair|hello|device\/me|transfer\/|sms\/result)/;
  const bad = mobileCalls().filter((c) => !phoneOnly.test(c.path)).map((c) => ({ ...c, route: svc.router.match(c.method, c.path)?.route }))
    .filter((c) => !c.route?.opts?.scope).map((c) => `${c.method} ${c.path} (${c.file})`);
  assert.deepEqual(bad, [], `phone calls to desktop-only routes (would return 403):\n${bad.join('\n')}`);
});
