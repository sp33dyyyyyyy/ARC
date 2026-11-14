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
    // Frame-rate cap (Settings → Performance) and adaptive quality: when drawing gets
    // expensive (slow integrated GPU, busy CPU) detail is reduced before frames are dropped.
    this.fpsLimit = 60; this.adaptive = true; this.quality = 1; this.cost = 0; this.costAt = 0; this.cheapSince = 0;
    this.frames = 0; this.visible = true;
    this.particles = Array.from({ length: compact ? 40 : 140 }, () => this.spawn());
    this.ro = new ResizeObserver(() => this.resize()); this.ro.observe(canvas.parentElement || canvas);
    // Pause when the canvas is scrolled away or hidden by layout, and when the window is hidden/minimised.
    this.io = new IntersectionObserver((es) => { this.visible = es.some((e) => e.isIntersecting); if (this.visible) this.start(); else this.stop(); });
    this.io.observe(canvas);
    this.onVis = () => (document.hidden ? this.stop() : this.start());
    document.addEventListener('visibilitychange', this.onVis);
    this.resize();
    this.onState = null;
  }
  spawn() { return { a: Math.random() * TAU, r: 0.35 + Math.random() * 0.75, s: (Math.random() * 0.5 + 0.2) * (Math.random() < 0.5 ? -1 : 1), z: Math.random(), life: Math.random() }; }
  resize() {
    const box = (this.c.parentElement || this.c).getBoundingClientRect();
    const size = Math.max(40, Math.floor(Math.min(box.width, box.height || box.width)));
    // Follow size changes visually right away (cheap CSS scaling) and re-allocate the
    // backing store only once the size has settled, e.g. after the Home transition.
    this.c.style.width = `${size}px`; this.c.style.height = `${size}px`;
    if (!this.size) return this.realloc(size);
    clearTimeout(this._rt);
    this._rt = setTimeout(() => this.realloc(size), 140);
  }
  realloc(size) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (size === this.size && dpr === this.dpr) return;
    this.c.width = size * dpr; this.c.height = size * dpr;
    this.dpr = dpr; this.size = size;
    if (!this.running) this.draw(0);
  }
  setMode(m) { this.mode = m; if (m === 'off') { this.stop(); this.draw(0); } else this.start(); }
  setFps(n) { this.fpsLimit = Math.max(15, Math.min(120, Number(n) || 60)); }
  setAdaptive(on) { this.adaptive = on !== false; if (!this.adaptive) this.quality = 1; }
  setState(s) { if (!STATES[s] || s === this.state) return; this.state = s; this.onState?.(s, LABELS[s]); }
  get label() { return LABELS[this.state]; }
  setLevel(v) { this.levelTarget = Math.max(0, Math.min(1, v)); }
  setAnalyser(a) { this.analyser = a; this.freq = a ? new Uint8Array(a.frequencyBinCount) : null; }
  start() {
    if (this.running || this.mode === 'off' || document.hidden || !this.visible) return;
    this.running = true; this.last = performance.now();
    const loop = (now) => {
      if (!this.running) return;
      const busy = this.state === 'thinking' || this.state === 'processing';
      // While a local model is generating, ease to 30 fps so inference keeps the CPU/GPU.
      const cap = Math.min(this.fpsLimit, this.mode === 'reduced' ? 24 : busy ? 30 : 60);
      if (now - this.last >= 1000 / cap - 1) {
        const dt = Math.min(0.05, (now - this.last) / 1000); this.last = now;
        const t0 = performance.now(); this.draw(dt); this.adapt(performance.now() - t0, now);
        this.frames++;
      }
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  }
  adapt(ms, now) {
    this.cost = this.cost ? this.cost * 0.9 + ms * 0.1 : ms;
    if (!this.adaptive || now - this.costAt < 1500) return;
    this.costAt = now;
    if (this.cost > 6 && this.quality > 0.4) { this.quality = Math.max(0.4, this.quality - 0.2); this.cheapSince = now; }
    else if (this.cost < 2.5 && this.quality < 1) { if (now - this.cheapSince > 8000) { this.quality = Math.min(1, this.quality + 0.2); this.cheapSince = now; } }
    else this.cheapSince = now;
  }
  stop() { this.running = false; cancelAnimationFrame(this.raf); }
  destroy() { this.stop(); this.ro.disconnect(); this.io.disconnect(); document.removeEventListener('visibilitychange', this.onVis); clearTimeout(this._rt); }

  staticLayers(W, base, d) {
    const key = `${W}|${Math.round(base)}|${this.compact}`;
    if (this._layers?.key === key) return this._layers;
    const mk = () => { const c = document.createElement('canvas'); c.width = W; c.height = W; const g = c.getContext('2d'); g.translate(W / 2, W / 2); return [c, g]; };
    const [ticks, g] = mk();
    const n = this.compact ? 60 : 120;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * TAU; const long = i % 10 === 0; const mid = i % 5 === 0;
      const r2 = base - (long ? 12 : mid ? 7 : 4) * d;
      g.strokeStyle = `rgba(255,255,255,${long ? 0.55 : 0.22})`; g.lineWidth = d * (long ? 1.2 : 0.8);
      g.beginPath(); g.moveTo(Math.cos(a) * base, Math.sin(a) * base); g.lineTo(Math.cos(a) * r2, Math.sin(a) * r2); g.stroke();
    }
    let labels = null;
    if (!this.compact && this.size > 220) {
      const [lc, lg] = mk(); labels = lc;
      lg.fillStyle = 'rgba(255,255,255,.32)'; lg.font = `${9 * d}px Bahnschrift, Segoe UI, sans-serif`; lg.textAlign = 'center'; lg.textBaseline = 'middle';
      const rr = base - 24 * d;
      for (let i = 0; i < 12; i++) { lg.save(); lg.rotate((i / 12) * TAU); lg.translate(0, -rr); lg.fillText(String(i * 30).padStart(3, '0'), 0, 0); lg.restore(); }
    }
    // Pre-rendered glow (replaces a radial gradient allocated every frame).
    const glow = document.createElement('canvas'); const G = 256; glow.width = G; glow.height = G;
    const gg = glow.getContext('2d'); const rg = gg.createRadialGradient(G / 2, G / 2, 0, G / 2, G / 2, G / 2);
    rg.addColorStop(0, 'rgba(255,255,255,1)'); rg.addColorStop(0.25, 'rgba(255,255,255,0.4)'); rg.addColorStop(0.6, 'rgba(255,255,255,0.08)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
    gg.fillStyle = rg; gg.fillRect(0, 0, G, G);
    this._layers = { key, ticks, labels, glow };
    return this._layers;
  }

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

    // 1-2. static rings (tick marks, degree labels) are pre-rendered once per size and
    // only rotated each frame — far cheaper than redrawing 130 strokes + text at 60 fps.
    const layers = this.staticLayers(W, base, d);
    ctx.save(); ctx.rotate(t * 0.05 * p.spin * 3); ctx.drawImage(layers.ticks, -R, -R); ctx.restore();
    if (layers.labels && this.quality > 0.6) { ctx.save(); ctx.rotate(-t * 0.03 * p.spin * 3); ctx.drawImage(layers.labels, -R, -R); ctx.restore(); }

    // 3. segmented arc ring
    ctx.save(); ctx.rotate(-t * 0.25 * p.spin);
    const segR = base * 0.74; const segs = 12;
    ctx.lineWidth = 2.2 * d; ctx.lineCap = 'butt';
    ctx.strokeStyle = '#fff';
    ctx.setLineDash(p.dash > 0.5 ? [3 * d, 4 * d] : []);
    for (let i = 0; i < segs; i++) {
      const a0 = (i / segs) * TAU + 0.05; const span = TAU / segs - 0.1;
      const lit = (Math.sin(t * 2 + i * 0.9) * 0.5 + 0.5) * p.glow;
      ctx.globalAlpha = Math.min(1, 0.18 + 0.5 * lit);
      ctx.beginPath(); ctx.arc(0, 0, segR, a0, a0 + span * (0.55 + 0.45 * ((i % 3) / 2))); ctx.stroke();
    }
    ctx.globalAlpha = 1;
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
    // Bars are batched into a few opacity buckets: ~6 strokes per frame instead of 96.
    const bars = (this.compact || this.size < 160) ? 48 : this.quality < 0.7 ? 64 : 96; const inner = base * 0.40; const maxLen = base * 0.2;
    ctx.save(); ctx.rotate(t * 0.1);
    ctx.lineWidth = Math.max(1, 1.5 * d); ctx.strokeStyle = '#fff';
    const BUCKETS = 6; const paths = this._paths || (this._paths = []);
    for (let b = 0; b < BUCKETS; b++) paths[b] = new Path2D();
    for (let i = 0; i < bars; i++) {
      let v;
      if (this.analyser && this.freq) { const bin = 2 + Math.floor((i < bars / 2 ? i : bars - i) / (bars / 2) * 60); v = this.freq[bin] / 255; }
      else v = L * (0.55 + 0.45 * Math.sin(i * 0.7 + t * 9)) * (0.6 + 0.4 * Math.sin(i * 1.7 - t * 5));
      const idleWave = 0.08 * (0.5 + 0.5 * Math.sin(i * 0.4 + t * 1.6));
      const len = (idleWave * (1 - p.bars) + v * p.bars) * maxLen + 1.5 * d;
      const a = (i / bars) * TAU; const c = Math.cos(a); const sn = Math.sin(a);
      const bk = Math.min(BUCKETS - 1, Math.floor(Math.min(1, v * 1.4 + 0.1) * BUCKETS));
      paths[bk].moveTo(c * inner, sn * inner); paths[bk].lineTo(c * (inner + len), sn * (inner + len));
    }
    for (let b = 0; b < BUCKETS; b++) { ctx.globalAlpha = 0.25 + 0.6 * ((b + 0.5) / BUCKETS); ctx.stroke(paths[b]); }
    ctx.globalAlpha = 1;
    ctx.restore();

    // 6. particles
    const np = Math.floor(this.particles.length * Math.max(0.15, p.particles) * (this.size < 160 ? 0.35 : this.quality));
    ctx.fillStyle = '#fff';
    for (let i = 0; i < np; i++) {
      const q = this.particles[i];
      q.a += q.s * dt * (0.3 + p.spin * 1.2);
      if (p.inward > 0.05) { q.r -= dt * 0.25 * p.inward; if (q.r < 0.22) Object.assign(q, this.spawn(), { r: 1.05 }); }
      q.life += dt * 0.2; if (q.life > 1) q.life -= 1;
      const rr = base * q.r * (1 + 0.04 * Math.sin(t + q.z * 6));
      const x = Math.cos(q.a) * rr; const y = Math.sin(q.a) * rr;
      const alpha = (0.15 + 0.6 * q.z) * Math.sin(q.life * Math.PI) * (0.4 + p.glow * 0.6);
      if (alpha <= 0.01) continue;
      ctx.globalAlpha = Math.min(1, alpha);
      ctx.fillRect(x, y, (0.8 + q.z * 1.4) * d, (0.8 + q.z * 1.4) * d);
    }
    ctx.globalAlpha = 1;

    // 7. luminous core
    const coreR = base * (0.22 + 0.02 * breathe * (1 - p.bars) + 0.08 * L);
    const gr = coreR * 1.9;
    ctx.globalAlpha = Math.min(1, 0.85 * p.glow + 0.1); ctx.drawImage(layers.glow, -gr, -gr, gr * 2, gr * 2); ctx.globalAlpha = 1;
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
