'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { autoPreset, PRESETS } = require('../src/server/performance');
const { inferenceThreads } = require('../src/server/llm/ollama');
const { startViper } = require('./helpers/env');

test('auto preset: Core i7 laptop, 16 GB, Intel integrated graphics → Balanced', () => {
  const hw = { ramGB: 15.7, cpu: { model: 'Intel Core i7-1165G7', cores: 8, physicalCores: 4 }, gpu: { model: 'Intel Iris Xe Graphics', vramGB: 0, dynamic: true } };
  assert.equal(autoPreset(hw), 'balanced');
  // 12th-gen hybrid i7 with integrated graphics is still Balanced (no dedicated VRAM)
  assert.equal(autoPreset({ ramGB: 16, cpu: { cores: 16, physicalCores: 12 }, gpu: { model: 'Intel UHD', vramGB: 0, dynamic: true } }), 'balanced');
});
test('auto preset: small machines → Eco, strong machines → Performance', () => {
  assert.equal(autoPreset({ ramGB: 8, cpu: { cores: 8, physicalCores: 4 } }), 'eco');
  assert.equal(autoPreset({ ramGB: 16, cpu: { cores: 4, physicalCores: 2 } }), 'eco');
  assert.equal(autoPreset({ ramGB: 32, cpu: { cores: 16, physicalCores: 8 }, gpu: { vramGB: 8 } }), 'performance');
  assert.equal(autoPreset({ ramGB: 16, cpu: { cores: 12, physicalCores: 6 }, gpu: { model: 'RTX 4060', vramGB: 8, dynamic: false } }), 'performance');
});
test('presets keep one model resident except Performance, and Eco lowers fps', () => {
  assert.equal(PRESETS.eco.performance.maxLoadedModels, 1);
  assert.equal(PRESETS.balanced.performance.maxLoadedModels, 1);
  assert.equal(PRESETS.performance.performance.maxLoadedModels, 2);
  assert.equal(PRESETS.eco.ui.fpsLimit, 30);
  assert.ok(PRESETS.eco.limits.numCtx < PRESETS.balanced.limits.numCtx);
});

test('inference threads: physical cores minus reserve; hybrid CPUs use P-cores only', () => {
  assert.equal(inferenceThreads({ reserveCores: 1 }, { physicalCores: 4 }), 3);
  assert.equal(inferenceThreads({ reserveCores: 2 }, { physicalCores: 4 }), 2);
  assert.equal(inferenceThreads({ reserveCores: 0 }, { physicalCores: 8 }), 8);
  assert.equal(inferenceThreads({ reserveCores: 1 }, { physicalCores: 10, performanceCores: 2 }), 2);
  assert.equal(inferenceThreads({ reserveCores: 1 }, { physicalCores: 12, performanceCores: 4 }), 4);
  assert.equal(inferenceThreads({ numThreads: 5 }, { physicalCores: 4 }), 5);
  assert.equal(inferenceThreads({ reserveUiCore: false }, { physicalCores: 4 }), 0);
  assert.equal(inferenceThreads({ reserveCores: 1 }, { physicalCores: 2 }), 0); // tiny CPUs: engine default
});

test('performance API applies presets to limits, UI and model policy', async (t) => {
  const svc = await startViper('perf');
  t.after(() => svc.shutdown());
  const st = await svc.call('GET', '/performance');
  assert.ok(['eco', 'balanced', 'performance'].includes(st.applied), 'a preset is applied on first run');
  assert.equal(st.preset, 'auto');
  const eco = await svc.call('POST', '/performance/preset', { preset: 'eco' });
  assert.equal(eco.applied, 'eco');
  assert.equal(svc.settings.get('limits').numCtx, 2048);
  assert.equal(svc.settings.get('limits').keepAlive, '2m');
  assert.equal(svc.settings.get('ui').fpsLimit, 30);
  assert.equal(svc.settings.get('ui').animations, 'reduced');
  const perf = await svc.call('POST', '/performance/preset', { preset: 'performance' });
  assert.equal(perf.maxLoadedModels, 2);
  assert.equal(svc.settings.get('limits').numCtx, 8192);
  await assert.rejects(svc.call('POST', '/performance/preset', { preset: 'turbo' }), /preset must be/);
});

test('model residency: other models are unloaded before a new one runs', async (t) => {
  const svc = await startViper('resident');
  t.after(() => svc.shutdown());
  const unloaded = [];
  const fake = {
    id: 'fake', label: 'Fake', health: async () => ({ ok: true }),
    loaded: async () => [{ name: 'vision:3b', expiresAt: '2026-01-01T10:00:00Z' }, { name: 'coder:7b', expiresAt: '2026-01-01T11:00:00Z' }, { name: 'chat:7b' }],
    unload: async (n) => { unloaded.push(n); },
    listModels: async () => [],
    async *chat() { yield { type: 'token', text: 'hi' }; yield { type: 'done', usage: { completion_tokens: 1 } }; },
  };
  svc.models.backends.fake = fake; svc.models.health.fake = { ok: true };
  svc.settings.set('performance', { maxLoadedModels: 1 });
  assert.deepEqual((await svc.models.ensureResident('fake', 'chat:7b')).sort(), ['coder:7b', 'vision:3b']);
  // Performance preset (2 resident): keep the most recently used other model
  unloaded.length = 0; svc.models._resident = null;
  svc.settings.set('performance', { maxLoadedModels: 2 });
  await svc.models.ensureResident('fake', 'chat:7b');
  assert.deepEqual(unloaded, ['vision:3b']);
  // a model that is generating for another request is never unloaded
  unloaded.length = 0; svc.models._resident = null;
  svc.settings.set('performance', { maxLoadedModels: 1 });
  svc.models.active.set('rq1', { backend: 'fake', model: 'coder:7b' });
  await svc.models.ensureResident('fake', 'chat:7b');
  assert.deepEqual(unloaded, ['vision:3b']);
  svc.models.active.delete('rq1');
  // streaming through the manager applies the policy too
  unloaded.length = 0; svc.models._resident = null;
  const out = await svc.models.complete({ backend: 'fake', model: 'chat:7b', messages: [{ role: 'user', content: 'x' }] });
  assert.equal(out.text, 'hi');
  assert.deepEqual(unloaded.sort(), ['coder:7b', 'vision:3b']);
});
