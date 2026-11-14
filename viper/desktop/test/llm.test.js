'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fakeLLM, startViper, chat } = require('./helpers/env');
const { parseEndpoint } = require('../src/server/llm/foundry');
const { OpenAICompatBackend } = require('../src/server/llm/openai');

test('OpenAI-compatible backend (Foundry Local protocol) streams tokens and tool calls', async (t) => {
  const llm = await fakeLLM(async (msgs, tools) => (tools.length && !msgs.some((m) => m.role === 'tool') ? { tool_calls: [{ name: 'system_status', arguments: {} }] } : { content: 'Hello from the fake model.' }));
  t.after(() => llm.close());
  const be = new OpenAICompatBackend({ getBaseUrl: async () => llm.url });
  const tokens = []; let calls = null; let done = null;
  for await (const ev of be.chat({ model: 'fake-chat-tools', messages: [{ role: 'user', content: 'hi' }] })) { if (ev.type === 'token') tokens.push(ev.text); if (ev.type === 'done') done = ev; }
  assert.ok(tokens.length > 1, 'streamed in several chunks'); assert.equal(tokens.join(''), 'Hello from the fake model.'); assert.ok(done);
  for await (const ev of be.chat({ model: 'x', messages: [{ role: 'user', content: 'status' }], tools: [{ name: 'system_status', description: 'd', parameters: { type: 'object', properties: {} } }] })) if (ev.type === 'tool_calls') calls = ev.calls;
  assert.equal(calls[0].name, 'system_status');
  assert.deepEqual((await be.listModels()).map((m) => m.id), ['fake-chat-tools', 'fake-embed']);
});

test('Foundry Local endpoint discovery parses CLI output', () => {
  assert.equal(parseEndpoint('🟢 Model management service is running on http://localhost:5273/openai/status'), 'http://127.0.0.1:5273');
  assert.equal(parseEndpoint('Service is not running'), null);
});

test('model manager: role resolution, switching, metrics and crash recovery', async (t) => {
  let down = false;
  const llm = await fakeLLM(async () => (down ? { status: 500, body: 'boom' } : { content: 'ok' }));
  const svc = await startViper('llm');
  t.after(async () => { await svc.shutdown(); await llm.close(); });
  svc.settings.set('backend', { active: 'openai', openai: { url: llm.url } });
  await svc.models.checkHealth();
  const r = await svc.models.resolve('chat');
  assert.deepEqual(r, { backend: 'openai', model: 'fake-chat-tools' });
  const out = await svc.models.complete({ messages: [{ role: 'user', content: 'x' }] });
  assert.equal(out.text, 'ok'); assert.ok(out.perf.tokens >= 1);
  assert.ok(svc.models.perfSummary().some((p) => p.model === 'fake-chat-tools'));
  // switch model for a single conversation without restarting
  const res = await chat(svc, 'Tell me a fact', { model: { backend: 'openai', model: 'fake-embed' } });
  assert.match(res.message.model, /fake-embed/);
  // recovery: unreachable backend triggers the recovery hook once, then surfaces a clear error
  svc.settings.set('backend', { openai: { url: 'http://127.0.0.1:9/v1' } });
  let recovered = 0; svc.models.recover = async () => { recovered++; return false; };
  await assert.rejects(svc.models.complete({ backend: 'openai', model: 'fake-chat-tools', messages: [{ role: 'user', content: 'x' }] }));
  assert.equal(recovered, 1);
});

test('no installed model produces an honest message, not a fake answer', async (t) => {
  const svc = await startViper('nomodel');
  t.after(() => svc.shutdown());
  svc.settings.set('backend', { active: 'openai', openai: { url: 'http://127.0.0.1:9/v1' } });
  await svc.models.checkHealth();
  const r = await chat(svc, 'Explain quantum computing');
  assert.match(r.message.content, /No chat model is installed|not configured|not running/i);
});
