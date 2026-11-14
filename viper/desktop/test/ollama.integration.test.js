'use strict';
// Integration tests against a real local Ollama server (skipped when none is running).
// Uses small models: qwen2.5:0.5b (chat/tools), all-minilm (embeddings), moondream (vision).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startViper, chat, waitFor } = require('./helpers/env');

let available = false;
try { const r = require('node:child_process').execFileSync('curl', ['-s', '--max-time', '2', 'http://127.0.0.1:11434/api/tags']).toString(); available = /qwen2\.5:0\.5b/.test(r); } catch { available = false; }

test('real local inference through Ollama', { skip: !available && 'Ollama with qwen2.5:0.5b not running' }, async (t) => {
  const svc = await startViper('ollama');
  t.after(() => svc.shutdown());
  svc.settings.set('backend', { active: 'ollama' });
  await svc.models.checkHealth();

  await t.test('installed models and capabilities come from the engine', async () => {
    const m = await svc.models.listInstalled(true);
    const q = m.find((x) => x.id === 'qwen2.5:0.5b');
    assert.ok(q.capabilities.includes('tools'));
    assert.ok(m.find((x) => x.id.startsWith('moondream')).capabilities.includes('vision'));
    assert.ok(m.find((x) => x.id.startsWith('all-minilm')).capabilities.includes('embeddings'));
  });
  await t.test('auto-selected chat model is a tool-capable text model', async () => {
    assert.deepEqual(await svc.models.resolve('chat'), { backend: 'ollama', model: 'qwen2.5:0.5b' });
  });
  await t.test('streams a real answer and records tokens/sec', async () => {
    const r = await chat(svc, 'What is the capital of France? Answer with one word.');
    assert.match(r.message.content, /Paris/i);
    assert.ok(r.events.filter((e) => e.type === 'chat.token').length >= 1);
    const p = svc.models.perfSummary().find((x) => x.model === 'qwen2.5:0.5b');
    assert.ok(p.avg_tps > 0);
    t.diagnostic(`qwen2.5:0.5b ~${p.avg_tps} tok/s, first token ${p.avg_ttft} ms (CPU)`);
  });
  await t.test('real embeddings power semantic search', async () => {
    const v = await svc.models.embed(['hello world', 'greetings planet']);
    assert.equal(v.length, 2); assert.ok(v[0].length >= 256);
  });
  await t.test('vision model reads a screenshot', async () => {
    const img = fs.readFileSync(path.join(__dirname, 'fixtures', 'error-screen.png')).toString('base64');
    const r = await svc.orchestrator.analyzeImage({ prompt: 'What text is written in this image?', image: img });
    t.diagnostic(`moondream: ${r.text.slice(0, 120)}`);
    assert.match(r.text, /404|error/i);
  });
  await t.test('model download reports progress (re-pull of an installed model)', async () => {
    const done = waitFor(svc, (e) => e.type === 'models.download' && e.data.status !== 'downloading', 120000);
    svc.models.startDownload('ollama', 'all-minilm');
    assert.equal((await done).data.status, 'done');
  });
  await t.test('model can be unloaded and reloaded without restarting VIPER', async () => {
    await svc.models.backend('ollama').unload('qwen2.5:0.5b');
    const r = await chat(svc, 'Say hi.');
    assert.ok(r.message.content.length > 0);
  });
});
