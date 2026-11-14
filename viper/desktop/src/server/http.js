'use strict';
// Minimal router + JSON helpers shared by the local (desktop) and remote (phone) servers.
class HttpError extends Error { constructor(status, message, code) { super(message); this.status = status; this.code = code; } }

class Router {
  constructor() { this.routes = []; }
  add(method, pattern, handler, opts = {}) {
    const keys = [];
    const re = new RegExp('^' + pattern.replace(/\/:([a-zA-Z_]+)/g, (_, k) => { keys.push(k); return '/([^/]+)'; }) + '/?$');
    this.routes.push({ method, re, keys, handler, pattern, opts });
  }
  get(p, h, o) { this.add('GET', p, h, o); } post(p, h, o) { this.add('POST', p, h, o); }
  patch(p, h, o) { this.add('PATCH', p, h, o); } delete(p, h, o) { this.add('DELETE', p, h, o); } put(p, h, o) { this.add('PUT', p, h, o); }
  match(method, pathname) {
    for (const r of this.routes) {
      if (r.method !== method) continue;
      const m = pathname.match(r.re);
      if (m) { const params = {}; r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); }); return { route: r, params }; }
    }
    return null;
  }
}

function readBody(req, limit = 60 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0;
    req.on('data', (c) => { size += c.length; if (size > limit) { reject(new HttpError(413, 'Request too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

async function dispatch(router, req, res, auth, { log } = {}) {
  const url = new URL(req.url, 'http://x');
  const found = router.match(req.method, url.pathname);
  if (!found) return send(res, 404, { error: 'Not found' });
  // Paired devices may only use routes that declare a scope they were granted; local-only routes have no scope.
  if (auth.device && (!found.route.opts.scope || !auth.scopes.includes(found.route.opts.scope))) return send(res, 403, { error: 'Not permitted for this device' });
  try {
    const raw = ['POST', 'PATCH', 'PUT', 'DELETE'].includes(req.method) ? await readBody(req) : Buffer.alloc(0);
    let body = {};
    const ct = String(req.headers['content-type'] || '');
    if (raw.length && ct.includes('application/json')) { try { body = JSON.parse(raw.toString('utf8')); } catch { throw new HttpError(400, 'Invalid JSON'); } }
    const out = await found.route.handler({ params: found.params, query: Object.fromEntries(url.searchParams), body, raw, headers: req.headers, auth, req, res });
    if (out && out.__stream) return; // handler wrote the response itself
    if (out && out.__raw) {
      res.writeHead(200, { 'Content-Type': out.type || 'application/octet-stream', 'Cache-Control': 'no-store', ...(out.filename ? { 'Content-Disposition': `attachment; filename="${out.filename.replace(/"/g, '')}"` } : {}) });
      return res.end(out.__raw);
    }
    send(res, 200, out === undefined ? { ok: true } : out);
  } catch (e) {
    const status = e.status || 500;
    if (status >= 500) log?.warn(`${req.method} ${url.pathname}`, e);
    send(res, status, { error: e.message, code: e.code });
  }
}

function send(res, status, obj) {
  if (res.headersSent) return;
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(body);
}

module.exports = { Router, HttpError, dispatch, send, readBody };
