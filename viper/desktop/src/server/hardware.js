'use strict';
const os = require('node:os');
let si; try { si = require('systeminformation'); } catch { si = null; }

let cached = null;
async function detectHardware(force = false) {
  if (cached && !force) return cached;
  const hw = {
    os: `${os.type()} ${os.release()}`, platform: process.platform, arch: process.arch,
    cpu: { model: os.cpus()[0]?.model || 'Unknown', cores: os.cpus().length },
    ramGB: Math.round(os.totalmem() / 1073741824 * 10) / 10,
    gpu: null, gpus: [], windows11: false,
  };
  if (process.platform === 'win32') {
    const build = parseInt(os.release().split('.')[2] || '0', 10);
    hw.windows11 = build >= 22000;
  }
  if (si) {
    try {
      const [cpu, g] = await Promise.all([si.cpu(), si.graphics()]);
      hw.cpu.model = `${cpu.manufacturer} ${cpu.brand}`.trim();
      hw.cpu.physicalCores = cpu.physicalCores;
      // Intel 12th gen+ hybrid CPUs: inference runs best on the performance cores only.
      if (cpu.performanceCores && cpu.efficiencyCores && cpu.performanceCores < cpu.physicalCores) { hw.cpu.performanceCores = cpu.performanceCores; hw.cpu.efficiencyCores = cpu.efficiencyCores; }
      hw.gpus = (g.controllers || []).map((c) => ({ model: c.model, vendor: c.vendor, vramGB: c.vram ? Math.round(c.vram / 1024 * 10) / 10 : 0, dynamic: !!c.vramDynamic }));
      // Pick the GPU with the most dedicated VRAM; integrated GPUs report shared memory (vramDynamic).
      const dedicated = hw.gpus.filter((x) => !x.dynamic).sort((a, b) => b.vramGB - a.vramGB);
      hw.gpu = dedicated[0] || hw.gpus[0] || null;
      if (hw.gpu?.dynamic) hw.gpu = { ...hw.gpu, vramGB: 0, note: 'integrated (shared memory)' };
    } catch { /* keep basic info */ }
  }
  cached = hw;
  return hw;
}
module.exports = { detectHardware };
