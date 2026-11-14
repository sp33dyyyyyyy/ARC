// The VIPER core: an original animated energy-core visualisation drawn on canvas.
// It reflects real state (idle/listening/thinking/speaking/processing/warning/offline)
// and real audio (microphone level while listening, TTS analyser while speaking).
const TAU = Math.PI * 2;
const STATES = {
  idle:       { spin: 0.10, glow: 0.55, bars: 0.15, particles: 0.25, inward: 0,   ringScale: 1.00, jitter: 0, dash: 0 },
  listening:  { spin: 0.35, glow: 0.95, bars: 0.90, particles: 0.55, inward: 0,   ringScale: 1.05, jitter: 0, dash: 0 },
  thinking:   { spin: 0.70, glow: 0.75, bars: 0.35, particles: 0.80, inward: 1,   ringScale: 0.98, jitter: 0, dash: 0 },
  processing: { spin: 1.10, glow: 0.80, bars: 0.45, particles: 1.00, inward: 0.4, ringScale: 1.00, jitter: 0, dash: 1 },
  speaking:   { spin: 0.40, glow: 1.00, bars: 1.00, particles: 0.60, inward: 0,   ringScale: 1.03, jitter: 0, dash: 0 },
  warning:    { spin: 0.25, glow: 0.70, bars: 0.40, particles: 0.30, inward: 0,   ringScale: 1.00, jitter: 1, dash: 1 },
  offline:    { spin: 0.03, glow: 0.18, bars: 0.00, particles: 0.08, inward: 0,   ringScale: 0.96, jitter: 0, dash: 1 },
};
const LABELS = { idle: 'Standing by', listening: 'Listening', thinking: 'Thinking', processing: 'Working', speaking: 'Speaking', warning: 'Attention required', offline: 'Inference offline' };

export class Core {
  constructor(canvas, { compact = false } = {}) {
    this.c = canvas; this.ctx = canvas.getContext('2d');
    this.compact = compact;
    this.state = 'idle'; this.p = { ...STATES.idle };
    this.level = 0; this.levelTarget = 0; this.analyser = null; this.freq = null;
    this.t = 0; this.last = performance.now(); this.running = false; this.mode = 'full';
    this.particles = Array.from({ length: compact ? 40 : 140 }, () => this.spawn());
    this.ro = new ResizeObserver(() => this.resize()); this.ro.observe(canvas.parentElement || canvas);
    this.resize();
    this.onState = null;
    document.addEventListener('visibilitychange', () => (document.hidden ? this.stop() : this.start()));
  }
  spawn() { return { a: Math.random() * TAU, r: 0.35 + Math.random() * 0.75, s: (Math.random() * 0.5 + 0.2) * (Math.random() < 0.5 ? -1 : 1), z: Math.random(), life: Math.random() }; }
  resize() {
    const box = (this.c.parentElement || this.c).getBoundingClientRect();
    const size = Math.max(60, Math.floor(Math.min(box.width, box.height || box.width)));
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.c.width = size * dpr; this.c.height = size * dpr; this.c.style.width = `${size}px`; this.c.style.height = `${size}px`;
    this.dpr = dpr; this.size = size;
    if (!this.running) this.draw(0);
  }
  setMode(m) { this.mode = m; if (m === 'off') { this.stop(); this.draw(0); } else this.start(); }
  setState(s) { if (!STATES[s] || s === this.state) return; this.state = s; this.onState?.(s, LABELS[s]); }
  get label() { return LABELS[this.state]; }
  setLevel(v) { this.levelTarget = Math.max(0, Math.min(1, v)); }
  setAnalyser(a) { this.analyser = a; this.freq = a ? new Uint8Array(a.frequencyBinCount) : null; }
  start() { if (this.running || this.mode === 'off' || document.hidden) return; this.running = true; this.last = performance.now(); const loop = (now) => { if (!this.running) return; const fpsCap = this.mode === 'reduced' ? 24 : 60; if (now - this.last >= 1000 / fpsCap - 1) { const dt = Math.min(0.05, (now - this.last) / 1000); this.last = now; this.draw(dt); } this.raf = requestAnimationFrame(loop); }; this.raf = requestAnimationFrame(loop); }
  stop() { this.running = false; cancelAnimationFrame(this.raf); }
  destroy() { this.stop(); this.ro.disconnect(); }

  draw(dt) {
    const { ctx } = this; const W = this.c.width; const R = W / 2; const d = this.dpr;
    const tgt = STATES[this.state];
    for (const k of Object.keys(tgt)) this.p[k] += (tgt[k] - this.p[k]) * Math.min(1, dt * 3.5);
    const p = this.p;
    // audio level: analyser (speech) or mic level
    let lvl = this.levelTarget;
    if (this.analyser) { this.analyser.getByteFrequencyData(this.freq); let s = 0; for (let i = 2; i < 64 && i < this.freq.length; i++) s += this.freq[i]; lvl = Math.min(1, s / (62 * 160)); }
    this.level += (lvl - this.level) * Math.min(1, dt * 12);
    this.t += dt;
    const t = this.t; const L = this.level;
    const breathe = 0.5 + 0.5 * Math.sin(t * 1.4);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, W, W);
    ctx.translate(R, R);
    const jit = p.jitter > 0.05 ? (Math.random() - 0.5) * p.jitter * 3 * d : 0;
    ctx.translate(jit, 0);
    const base = R * 0.92 * p.ringScale;
    const white = (a) => `rgba(255,255,255,${Math.max(0, Math.min(1, a))})`;

    // 1. outer tick ring
    ctx.save(); ctx.rotate(t * 0.05 * p.spin * 3);
    const ticks = this.compact ? 60 : 120;
    for (let i = 0; i < ticks; i++) {
      const a = (i / ticks) * TAU; const long = i % 10 === 0; const mid = i % 5 === 0;
      const r1 = base; const r2 = base - (long ? 12 : mid ? 7 : 4) * d;
      ctx.strokeStyle = white(long ? 0.55 : 0.22); ctx.lineWidth = d * (long ? 1.2 : 0.8);
      ctx.beginPath(); ctx.moveTo(Math.cos(a) * r1, Math.sin(a) * r1); ctx.lineTo(Math.cos(a) * r2, Math.sin(a) * r2); ctx.stroke();
    }
    ctx.restore();

    // 2. technical markings ring (degree labels) — full size only
    if (!this.compact && this.size > 220) {
      ctx.save(); ctx.rotate(-t * 0.03 * p.spin * 3);
      ctx.fillStyle = white(0.32); ctx.font = `${9 * d}px Bahnschrift, Segoe UI, sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      const rr = base - 24 * d;
      for (let i = 0; i < 12; i++) { const a = (i / 12) * TAU; ctx.save(); ctx.rotate(a); ctx.translate(0, -rr); ctx.fillText(String(i * 30).padStart(3, '0'), 0, 0); ctx.restore(); }
      ctx.restore();
    }

    // 3. segmented arc ring
    ctx.save(); ctx.rotate(-t * 0.25 * p.spin);
    const segR = base * 0.74; const segs = 12;
    ctx.lineWidth = 2.2 * d; ctx.lineCap = 'butt';
    for (let i = 0; i < segs; i++) {
      const a0 = (i / segs) * TAU + 0.05; const span = TAU / segs - 0.1;
      const lit = (Math.sin(t * 2 + i * 0.9) * 0.5 + 0.5) * p.glow;
      ctx.strokeStyle = white(0.18 + 0.5 * lit);
      if (p.dash > 0.5) ctx.setLineDash([3 * d, 4 * d]); else ctx.setLineDash([]);
      ctx.beginPath(); ctx.arc(0, 0, segR, a0, a0 + span * (0.55 + 0.45 * ((i % 3) / 2))); ctx.stroke();
    }
    ctx.setLineDash([]);
    // fast inner sweep arc
    ctx.rotate(t * 1.2 * p.spin);
    ctx.strokeStyle = white(0.7 * p.glow); ctx.lineWidth = 1.2 * d;
    ctx.beginPath(); ctx.arc(0, 0, segR - 8 * d, 0, 0.9); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0, segR - 8 * d, Math.PI, Math.PI + 0.35); ctx.stroke();
    ctx.restore();

    // 4. thin concentric rings
    ctx.strokeStyle = white(0.12); ctx.lineWidth = d;
    for (const f of [0.86, 0.62, 0.47]) { ctx.beginPath(); ctx.arc(0, 0, base * f, 0, TAU); ctx.stroke(); }

    // 5. radial audio visualiser
    const bars = this.compact ? 48 : 96; const inner = base * 0.40; const maxLen = base * 0.2;
    ctx.save(); ctx.rotate(t * 0.1);
    ctx.lineWidth = Math.max(1, 1.5 * d);
    for (let i = 0; i < bars; i++) {
      let v;
      if (this.analyser && this.freq) { const bin = 2 + Math.floor((i < bars / 2 ? i : bars - i) / (bars / 2) * 60); v = this.freq[bin] / 255; }
      else v = L * (0.55 + 0.45 * Math.sin(i * 0.7 + t * 9)) * (0.6 + 0.4 * Math.sin(i * 1.7 - t * 5));
      const idleWave = 0.08 * (0.5 + 0.5 * Math.sin(i * 0.4 + t * 1.6));
      const len = (idleWave * (1 - p.bars) + v * p.bars) * maxLen + 1.5 * d;
      const a = (i / bars) * TAU;
      ctx.strokeStyle = white(0.25 + 0.6 * Math.min(1, v * 1.4 + 0.1));
      ctx.beginPath(); ctx.moveTo(Math.cos(a) * inner, Math.sin(a) * inner); ctx.lineTo(Math.cos(a) * (inner + len), Math.sin(a) * (inner + len)); ctx.stroke();
    }
    ctx.restore();

    // 6. particles
    const np = Math.floor(this.particles.length * Math.max(0.15, p.particles));
    for (let i = 0; i < np; i++) {
      const q = this.particles[i];
      q.a += q.s * dt * (0.3 + p.spin * 1.2);
      if (p.inward > 0.05) { q.r -= dt * 0.25 * p.inward; if (q.r < 0.22) Object.assign(q, this.spawn(), { r: 1.05 }); }
      q.life += dt * 0.2; if (q.life > 1) q.life -= 1;
      const rr = base * q.r * (1 + 0.04 * Math.sin(t + q.z * 6));
      const x = Math.cos(q.a) * rr; const y = Math.sin(q.a) * rr;
      const alpha = (0.15 + 0.6 * q.z) * Math.sin(q.life * Math.PI) * (0.4 + p.glow * 0.6);
      ctx.fillStyle = white(alpha);
      ctx.fillRect(x, y, (0.8 + q.z * 1.4) * d, (0.8 + q.z * 1.4) * d);
    }

    // 7. luminous core
    const coreR = base * (0.22 + 0.02 * breathe * (1 - p.bars) + 0.08 * L);
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, coreR * 1.9);
    g.addColorStop(0, white(0.85 * p.glow + 0.1)); g.addColorStop(0.25, white(0.35 * p.glow)); g.addColorStop(0.6, white(0.07 * p.glow)); g.addColorStop(1, white(0));
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, coreR * 1.9, 0, TAU); ctx.fill();
    ctx.strokeStyle = white(0.5 + 0.4 * p.glow); ctx.lineWidth = 1.2 * d;
    ctx.beginPath(); ctx.arc(0, 0, coreR, 0, TAU); ctx.stroke();
    // hex lattice in the core
    ctx.save(); ctx.rotate(-t * 0.4 * p.spin); ctx.strokeStyle = white(0.25 + 0.3 * p.glow); ctx.lineWidth = d;
    ctx.beginPath(); for (let i = 0; i <= 6; i++) { const a = (i / 6) * TAU; const rr = coreR * 0.62; i ? ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr) : ctx.moveTo(Math.cos(a) * rr, Math.sin(a) * rr); } ctx.stroke();
    ctx.restore();
    if (this.state === 'warning' || this.state === 'offline') {
      ctx.strokeStyle = white(this.state === 'warning' ? 0.5 + 0.5 * Math.sign(Math.sin(t * 6)) : 0.25); ctx.lineWidth = 2 * d;
      ctx.beginPath(); ctx.arc(0, 0, base * 0.98, 0, TAU); ctx.stroke();
    }
  }
}
export { LABELS as CORE_LABELS };
