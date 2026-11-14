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
    const v = m.find((x) => x.id.startsWith('moondream')); if (v) assert.ok(v.capabilities.includes('vision'));
    const e = m.find((x) => x.id.startsWith('all-minilm')); if (e) assert.ok(e.capabilities.includes('embeddings'));
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
  const has = async (prefix) => (await svc.models.listInstalled(true)).some((x) => x.id.startsWith(prefix));
  await t.test('real embeddings power semantic search', async (st) => {
    if (!await has('all-minilm')) return st.skip('all-minilm not installed');
    const v = await svc.models.embed(['hello world', 'greetings planet']);
    assert.equal(v.length, 2); assert.ok(v[0].length >= 256);
  });
  await t.test('vision model reads a screenshot', async (st) => {
    if (!await has('moondream')) return st.skip('moondream not installed');
    const img = fs.readFileSync(path.join(__dirname, 'fixtures', 'error-screen.png')).toString('base64');
    const r = await svc.orchestrator.analyzeImage({ prompt: 'What text is written in this image?', image: img });
    t.diagnostic(`moondream: ${r.text.slice(0, 120)}`);
    assert.match(r.text, /404|error/i);
  });
  await t.test('memory policy: running chat after vision unloads the vision model (one model in RAM)', async (st) => {
    if (!await has('moondream')) return st.skip('moondream not installed');
    svc.settings.set('performance', { maxLoadedModels: 1 }); svc.models._resident = null;
    const before = (await svc.models.backend('ollama').loaded()).map((m) => m.name);
    await chat(svc, 'Say ok.');
    const after = (await svc.models.backend('ollama').loaded()).map((m) => m.name);
    t.diagnostic(`resident before chat: ${before.join(', ')} · after: ${after.join(', ')}`);
    assert.ok(before.some((n) => n.startsWith('moondream')), 'vision model was resident');
    assert.deepEqual(after, ['qwen2.5:0.5b']);
  });
  await t.test('model download reports progress (re-pull of an installed model)', async (st) => {
    if (!await has('all-minilm')) return st.skip('all-minilm not installed');
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
