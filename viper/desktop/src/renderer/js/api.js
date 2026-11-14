// API client for the local VIPER core (same origin) with a reconnecting event stream.
const params = new URLSearchParams(location.search);
let token = window.viperNative?.token || params.get('token') || sessionStorage.getItem('viper.token') || '';
if (params.get('token')) { sessionStorage.setItem('viper.token', token); history.replaceState(null, '', location.pathname + location.hash); }

const listeners = new Map();
// Chat stream events can arrive before the POST /chat response; keep a short replay buffer.
const recent = [];
let ws = null; let wsBackoff = 500; let connected = false;

export const api = {
  get token() { return token; },
  base: '/api/v1',
  async req(method, path, body, { raw = false, signal } = {}) {
    const isForm = body instanceof Blob || body instanceof ArrayBuffer;
    const r = await fetch(this.base + path, {
      method, signal,
      headers: { Authorization: `Bearer ${token}`, ...(body !== undefined && !isForm ? { 'Content-Type': 'application/json' } : {}), ...(body instanceof Blob ? { 'Content-Type': body.type || 'application/octet-stream' } : {}) },
      body: body === undefined ? undefined : isForm ? body : JSON.stringify(body),
    });
    if (raw) { if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`); return r; }
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { const e = new Error(j.error || `HTTP ${r.status}`); e.status = r.status; e.code = j.code; throw e; }
    return j;
  },
  get(p, o) { return this.req('GET', p, undefined, o); },
  post(p, b = {}, o) { return this.req('POST', p, b, o); },
  patch(p, b = {}) { return this.req('PATCH', p, b); },
  del(p) { return this.req('DELETE', p); },
  url(p) { return `${this.base}${p}${p.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`; },
  on(type, fn) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type).add(fn); return () => listeners.get(type).delete(fn); },
  emitLocal(type, data) { for (const k of [type, '*']) for (const fn of listeners.get(k) || []) { try { fn(data, type); } catch (e) { console.error(e); } } },
  get connected() { return connected; },
  replay(requestId) { return recent.filter((e) => e.data?.requestId === requestId); },
  connect() {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    ws = new WebSocket(`${proto}://${location.host}/api/v1/ws?token=${encodeURIComponent(token)}`);
    ws.onopen = () => { connected = true; wsBackoff = 500; this.emitLocal('ws.open', {}); };
    ws.onmessage = (m) => { try { const e = JSON.parse(m.data); if (e.type.startsWith('chat.')) { recent.push(e); if (recent.length > 400) recent.shift(); } this.emitLocal(e.type, e.data); } catch { /* ignore */ } };
    ws.onclose = () => { connected = false; this.emitLocal('ws.close', {}); setTimeout(() => this.connect(), wsBackoff); wsBackoff = Math.min(wsBackoff * 2, 8000); };
  },
};
