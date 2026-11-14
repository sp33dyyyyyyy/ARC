'use strict';
// Performance profiles. VIPER picks ECO / BALANCED / PERFORMANCE from the detected hardware
// (CPU cores, RAM, dedicated GPU memory) and applies a coherent set of limits: inference
// context and threads, how long idle models stay in memory, how many models may be resident
// at once, animation quality and frame rate, and how often telemetry is sampled.
const os = require('node:os');
const { detectHardware } = require('./hardware');

const PRESETS = {
  eco: {
    label: 'Eco',
    summary: 'Lowest CPU, memory and battery use. Reduced animations at 30 fps, smaller context, one model in memory, unloaded after 2 minutes idle.',
    limits: { numCtx: 2048, keepAlive: '2m', maxContextMessages: 20, reserveCores: 2 },
    ui: { animations: 'reduced', fpsLimit: 30 },
    performance: { maxLoadedModels: 1, warmup: false, monitorMs: 4000, adaptiveQuality: true },
  },
  balanced: {
    label: 'Balanced',
    summary: 'Recommended. Smooth 60 fps interface (30 fps while the AI is generating), 4K context, one model in memory, kept warm for 10 minutes.',
    limits: { numCtx: 4096, keepAlive: '10m', maxContextMessages: 40, reserveCores: 1 },
    ui: { animations: 'full', fpsLimit: 60 },
    performance: { maxLoadedModels: 1, warmup: true, monitorMs: 2000, adaptiveQuality: true },
  },
  performance: {
    label: 'Performance',
    summary: 'For stronger PCs. 8K context, every core available to inference, up to two models resident, kept warm for 30 minutes.',
    limits: { numCtx: 8192, keepAlive: '30m', maxContextMessages: 60, reserveCores: 0 },
    ui: { animations: 'full', fpsLimit: 60 },
    performance: { maxLoadedModels: 2, warmup: true, monitorMs: 1500, adaptiveQuality: true },
  },
};

/** Choose a preset for the hardware. Integrated graphics count as "no GPU" for inference. */
function autoPreset(hw) {
  const ram = hw?.ramGB || os.totalmem() / 1073741824;
  const cores = hw?.cpu?.physicalCores || Math.max(1, Math.floor((hw?.cpu?.cores || os.cpus().length) / 2));
  const vram = hw?.gpu && !hw.gpu.dynamic ? hw.gpu.vramGB || 0 : 0;
  if (ram < 10 || cores < 4) return 'eco';
  if ((vram >= 8 && ram >= 16) || (ram >= 30 && cores >= 8)) return 'performance';
  return 'balanced';
}

/** Explain the choice in plain words for Settings → Performance. */
function explain(hw, preset) {
  const gpu = hw?.gpu ? `${hw.gpu.model || 'GPU'}${hw.gpu.dynamic || !hw.gpu.vramGB ? ' (integrated, shared memory)' : ` (${hw.gpu.vramGB} GB)`}` : 'no GPU detected';
  const cores = hw?.cpu?.physicalCores ? `${hw.cpu.physicalCores} cores / ${hw.cpu.cores} threads` : `${hw?.cpu?.cores || '?'} threads`;
  return `${hw?.cpu?.model || 'CPU'} (${cores}), ${hw?.ramGB || '?'} GB RAM, ${gpu} → ${PRESETS[preset].label}.`;
}

class PerformanceProfile {
  constructor({ settings, log, bus }) { this.settings = settings; this.log = log; this.bus = bus; this.hw = null; }

  async init() {
    this.hw = await detectHardware().catch(() => null);
    const p = this.settings.get('performance');
    if (!p.applied) this.apply(p.preset || 'auto', { initial: true });
    return this;
  }

  resolve(preset) { return preset === 'auto' || !PRESETS[preset] ? autoPreset(this.hw) : preset; }

  /** Write a preset's limits into settings. Individual values can still be edited afterwards. */
  apply(preset = 'auto', { initial = false } = {}) {
    const name = this.resolve(preset);
    const def = PRESETS[name];
    this.settings.set('limits', def.limits);
    // A user who explicitly turned animations off keeps them off.
    const ui = this.settings.get('ui');
    this.settings.set('ui', { ...def.ui, animations: ui.animations === 'off' && !initial ? 'off' : def.ui.animations });
    this.settings.set('performance', { ...def.performance, preset, applied: name, appliedAt: Date.now() });
    this.log?.info(`performance preset ${preset} → ${name}`);
    this.bus?.publish('performance.applied', { preset, applied: name });
    return this.status();
  }

  status() {
    const p = this.settings.get('performance');
    const recommended = autoPreset(this.hw);
    return {
      ...p, recommended, reason: this.hw ? explain(this.hw, recommended) : null, hardware: this.hw,
      presets: Object.fromEntries(Object.entries(PRESETS).map(([k, v]) => [k, { label: v.label, summary: v.summary, limits: v.limits, ui: v.ui, performance: v.performance }])),
      limits: this.settings.get('limits'), fpsLimit: this.settings.get('ui').fpsLimit, animations: this.settings.get('ui').animations,
    };
  }
}

module.exports = { PRESETS, autoPreset, PerformanceProfile };
