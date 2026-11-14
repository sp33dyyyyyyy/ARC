'use strict';
// Shared test helpers: isolated data dir per test file, a fake OpenAI-compatible
// LLM server (deterministic, supports streaming + tool calls) and HTTP helpers.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
process.removeAllListeners('warning');

function tmpDir(name) { return fs.mkdtempSync(path.join(os.tmpdir(), `viper-${name}-`)); }

/** Minimal OpenAI-compatible server. `script(messages, tools)` returns {content} or {tool_calls:[{name, arguments}]}. */
function fakeLLM(script) {
  const calls = [];
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    const url = req.url;
    if (url.endsWith('/models')) { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ data: [{ id: 'fake-chat-tools' }, { id: 'fake-embed' }] })); }
    if (url.endsWith('/embeddings')) {
      const j = JSON.parse(body); const input = [].concat(j.input);
      const vec = (t) => { const v = new Array(16).fill(0); for (const w of String(t).toLowerCase().split(/\W+/)) if (w) v[[...w].reduce((a, c) => a + c.charCodeAt(0), 0) % 16] += 1; return v; };
      res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ data: input.map((t, i) => ({ index: i, embedding: vec(t) })) }));
    }
    if (url.endsWith('/chat/completions')) {
      const j = JSON.parse(body); calls.push(j);
      const out = await script(j.messages, j.tools || [], j);
      if (out.status) { res.writeHead(out.status); return res.end(out.body || 'error'); }
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      const send = (o) => res.write(`data: ${JSON.stringify(o)}\n\n`);
      if (out.tool_calls) out.tool_calls.forEach((tc, i) => send({ choices: [{ index: 0, delta: { tool_calls: [{ index: i, id: `call_${i}`, function: { name: tc.name, arguments: JSON.stringify(tc.arguments) } }] } }] }));
      else for (const piece of String(out.content).match(/.{1,6}/gs) || []) send({ choices: [{ index: 0, delta: { content: piece } }] });
      send({ choices: [{ index: 0, delta: {}, finish_reason: out.tool_calls ? 'tool_calls' : 'stop' }], usage: { prompt_tokens: 10, completion_tokens: 5 } });
      res.end('data: [DONE]\n\n');
      return;
    }
    res.writeHead(404); res.end();
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ url: `http://127.0.0.1:${server.address().port}/v1`, calls, close: () => new Promise((r) => server.close(r)) })));
}

async function startViper(name, extra = {}) {
  const { createViper } = require('../../src/server/server');
  const dataDir = tmpDir(name);
  const svc = await createViper({ dataDir, port: 0, noBackground: true, ...extra });
  const H = { Authorization: `Bearer ${svc.localToken}`, 'Content-Type': 'application/json' };
  svc.call = async (method, p, body) => {
    const r = await fetch(`${svc.url}/api/v1${p}`, { method, headers: H, body: body === undefined ? undefined : JSON.stringify(body) });
    const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
    if (!r.ok) { const e = new Error(j?.error || `HTTP ${r.status}`); e.status = r.status; throw e; }
    return j;
  };
  svc.dataDir = dataDir;
  return svc;
}

/** Collect bus events until the predicate returns true. */
function waitFor(svc, pred, ms = 15000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { svc.bus.off('event', f); reject(new Error('timeout waiting for event')); }, ms);
    const f = (e) => { if (pred(e)) { clearTimeout(t); svc.bus.off('event', f); resolve(e); } };
    svc.bus.on('event', f);
  });
}

async function chat(svc, text, extra = {}) {
  const events = [];
  const f = (e) => events.push(e);
  svc.bus.on('event', f);
  const r = svc.orchestrator.handle({ text, ...extra });
  const res = await r.done;
  svc.bus.off('event', f);
  return { ...res, requestId: r.requestId, conversationId: r.conversationId, events: events.filter((e) => e.data?.requestId === r.requestId) };
}

module.exports = { tmpDir, fakeLLM, startViper, waitFor, chat };
