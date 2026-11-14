'use strict';
// Real-time system telemetry via systeminformation. Sensors that are not
// available on this machine are reported as null — never invented.
const os = require('node:os');
const dns = require('node:dns').promises;
let si; try { si = require('systeminformation'); } catch { si = null; }

class SystemMonitor {
  constructor({ bus, log, settings, models }) {
    this.bus = bus; this.log = log; this.settings = settings; this.models = models;
    this.history = []; // {t, cpu, mem, netRx, netTx, gpu}
    this.minuteHistory = [];
    this.latest = null;
    this.visible = true;
    this.timer = null;
    this.online = null; this.lastOnlineCheck = 0;
    this.alertState = {};
    this.staticInfo = null;
  }
  start() {
    const tick = async () => {
      try { await this.sample(); } catch (e) { this.log.debug('monitor sample', e.message); }
      this.timer = setTimeout(tick, this.visible ? Math.max(1000, this.settings?.get('performance')?.monitorMs || 2000) : 15000);
    };
    tick();
  }
  stop() { clearTimeout(this.timer); }
  setVisible(v) { this.visible = !!v; }

  async getStatic() {
    if (this.staticInfo) return this.staticInfo;
    const info = { hostname: os.hostname(), platform: `${os.type()} ${os.release()}`, cpuModel: os.cpus()[0]?.model, cores: os.cpus().length, totalMem: os.totalmem() };
    if (si) {
      try { const o = await si.osInfo(); info.platform = `${o.distro} ${o.release} (${o.arch})`; } catch { /* keep */ }
    }
    this.staticInfo = info;
    return info;
  }

  async checkOnline() {
    if (Date.now() - this.lastOnlineCheck < 60000 && this.online !== null) return this.online;
    this.lastOnlineCheck = Date.now();
    try { await dns.lookup('www.msftconnecttest.com'); this.online = true; } catch { this.online = false; }
    return this.online;
  }

  /** CPU % from os.cpus() deltas — no child processes, essentially free. */
  cpuFromOs() {
    const cpus = os.cpus();
    const prev = this.prevCpus; this.prevCpus = cpus;
    if (!prev || prev.length !== cpus.length) return null;
    const per = cpus.map((c, i) => {
      const a = c.times; const b = prev[i].times;
      const total = (a.user + a.nice + a.sys + a.irq + a.idle) - (b.user + b.nice + b.sys + b.irq + b.idle);
      return total > 0 ? Math.round((1 - (a.idle - b.idle) / total) * 100) : 0;
    });
    return { pct: Math.round(per.reduce((x, y) => x + y, 0) / per.length * 10) / 10, perCore: per };
  }

  /**
   * Sampling is tiered so the monitor never competes with local AI inference:
   * CPU/memory every tick from the OS (no processes spawned), network every 10 s,
   * disks every 60 s, and GPU/temperature/battery (which launch PowerShell/WMI or
   * nvidia-smi on Windows) every 30 s — and only while VIPER is visible.
   */
  async sample() {
    const t = Date.now();
    const due = (key, ms) => { if (!this.lastSlow) this.lastSlow = {}; if (t - (this.lastSlow[key] || 0) >= ms) { this.lastSlow[key] = t; return true; } return false; };
    const prev = this.latest || {};
    const s = { t, cpu: this.cpuFromOs() || prev.cpu || null, mem: null, disks: prev.disks || [], net: prev.net || null, gpu: prev.gpu || null, battery: prev.battery ?? null, temp: prev.temp ?? null, online: await this.checkOnline(), uptime: os.uptime() };
    const total = os.totalmem(); const free = os.freemem();
    s.mem = { total, used: total - free, pct: Math.round((1 - free / total) * 1000) / 10 };
    if (si) {
      const jobs = [];
      if (due('disks', 60000)) jobs.push(si.fsSize().then((fsz) => { s.disks = (fsz || []).filter((d) => d.size > 1e9).map((d) => ({ mount: d.mount, fs: d.type, size: d.size, used: d.used, pct: Math.round(d.use * 10) / 10 })); }).catch(() => {}));
      if (due('net', 10000)) jobs.push(si.networkStats().then((net) => {
        const rx = (net || []).reduce((a, n) => a + (n.rx_sec > 0 ? n.rx_sec : 0), 0);
        const tx = (net || []).reduce((a, n) => a + (n.tx_sec > 0 ? n.tx_sec : 0), 0);
        s.net = { rxPerSec: Math.round(rx), txPerSec: Math.round(tx) };
      }).catch(() => {}));
      // Hidden: still read the CPU temperature (every 2 min) so overheating alerts keep working.
      if (!this.visible && this.settings.get('proactive').highCpuTemp?.enabled && due('tempHidden', 120000)) jobs.push(si.cpuTemperature().then((temp) => { s.temp = temp && temp.main > 0 ? { cpu: temp.main, max: temp.max > 0 ? temp.max : null } : null; }).catch(() => {}));
      if (this.visible && due('sensors', 30000)) jobs.push(Promise.all([si.battery().catch(() => null), si.cpuTemperature().catch(() => null), si.graphics().catch(() => null)]).then(([bat, temp, gfx]) => {
        s.battery = bat && bat.hasBattery ? { pct: bat.percent, charging: bat.isCharging, timeRemaining: bat.timeRemaining >= 0 ? bat.timeRemaining : null } : null;
        s.temp = temp && temp.main > 0 ? { cpu: temp.main, max: temp.max > 0 ? temp.max : null } : null;
        const g = gfx?.controllers?.find((c) => c.utilizationGpu != null || c.memoryUsed != null);
        s.gpu = g ? { model: g.model, pct: g.utilizationGpu ?? null, memUsed: g.memoryUsed != null ? g.memoryUsed * 1048576 : null, memTotal: g.memoryTotal != null ? g.memoryTotal * 1048576 : null, temp: g.temperatureGpu ?? null } : null;
      }));
      await Promise.all(jobs);
    }
    if (!s.cpu) { const l = os.loadavg()[0] / os.cpus().length; s.cpu = { pct: Math.round(Math.min(100, l * 100)), perCore: [] }; }
    s.process = { rss: process.memoryUsage().rss };
    this.latest = s;
    this.history.push({ t, cpu: s.cpu?.pct ?? null, mem: s.mem?.pct ?? null, rx: s.net?.rxPerSec ?? 0, tx: s.net?.txPerSec ?? 0, gpu: s.gpu?.pct ?? null });
    if (this.history.length > 900) this.history.shift();
    this.rollMinute(s);
    this.bus.publish('system.sample', s);
    this.checkAlerts(s);
    return s;
  }

  rollMinute(s) {
    const minute = Math.floor(s.t / 60000);
    const last = this.minuteHistory[this.minuteHistory.length - 1];
    if (!last || last.minute !== minute) {
      this.minuteHistory.push({ minute, t: minute * 60000, cpu: s.cpu?.pct ?? 0, mem: s.mem?.pct ?? 0, n: 1 });
      if (this.minuteHistory.length > 1440) this.minuteHistory.shift();
    } else {
      last.cpu = (last.cpu * last.n + (s.cpu?.pct ?? 0)) / (last.n + 1);
      last.mem = (last.mem * last.n + (s.mem?.pct ?? 0)) / (last.n + 1);
      last.n++;
    }
  }

  checkAlerts(s) {
    const p = this.settings.get('proactive');
    const fire = (key, data, cooldownMs = 3600000) => {
      const last = this.alertState[key] || 0;
      if (Date.now() - last < cooldownMs) return;
      this.alertState[key] = Date.now();
      this.bus.publish('system.alert', { key, ...data });
    };
    if (p.lowDisk?.enabled) {
      for (const d of s.disks) if (100 - d.pct < p.lowDisk.thresholdPct) fire(`disk:${d.mount}`, { severity: 'warning', title: 'Low disk space', message: `Drive ${d.mount} has only ${(100 - d.pct).toFixed(1)}% free.` }, 6 * 3600000);
    }
    if (p.highMemory?.enabled && s.mem) {
      const k = 'memHighSince';
      if (s.mem.pct >= p.highMemory.thresholdPct) {
        this.alertState[k] = this.alertState[k] || Date.now();
        if (Date.now() - this.alertState[k] > p.highMemory.sustainSec * 1000) fire('mem', { severity: 'warning', title: 'High memory usage', message: `Memory usage has been above ${p.highMemory.thresholdPct}% (now ${s.mem.pct}%) for over ${Math.round(p.highMemory.sustainSec / 60)} minutes.` });
      } else this.alertState[k] = 0;
    }
    if (p.highCpuTemp?.enabled && s.temp?.cpu >= p.highCpuTemp.thresholdC) fire('temp', { severity: 'warning', title: 'High CPU temperature', message: `CPU temperature is ${s.temp.cpu}°C.` });
  }

  async processes(limit = 25) {
    if (!si) return [];
    const p = await si.processes();
    return p.list.sort((a, b) => (b.cpu - a.cpu) || (b.memRss - a.memRss)).slice(0, limit).map((x) => ({ pid: x.pid, name: x.name, cpu: Math.round(x.cpu * 10) / 10, memBytes: x.memRss * 1024, user: x.user, path: x.path }));
  }
  async allProcesses() { if (!si) return []; return (await si.processes()).list; }

  async snapshot() {
    const s = this.latest || await this.sample();
    return { ...s, static: await this.getStatic() };
  }
}

module.exports = { SystemMonitor };
