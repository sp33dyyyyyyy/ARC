/* Scrolling ECG strip + tiny audio beeps. */
(function (G) {
  const HS = G.HS;
  const gauss = (x, m, s) => Math.exp(-((x - m) * (x - m)) / (2 * s * s));
  function beat(ph, o) {
    let y = 0;
    y += o.p * gauss(ph, 0.1, 0.025);
    y -= 0.12 * gauss(ph, 0.19, 0.008);
    y += 1.0 * gauss(ph, 0.21, 0.011);
    y -= 0.22 * gauss(ph, 0.235, 0.01);
    y += o.t * gauss(ph, 0.42, 0.05);
    return y;
  }
  function wide(ph) { return 0.7 * gauss(ph, 0.2, 0.05) - 0.3 * gauss(ph, 0.33, 0.06); }

  HS.Ecg = function (canvas) {
    this.c = canvas; this.ctx = canvas.getContext('2d');
    this.pxs = 95; this.buf = []; this.phase = 0; this.rr = 1; this.last = performance.now(); this.vf = 0; this.carry = 0; this.onBeat = null;
  };
  HS.Ecg.prototype.frame = function (now, st) {
    const c = this.c, ctx = this.ctx;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const W = c.clientWidth, H = c.clientHeight;
    if (!W) return;
    if (c.width !== Math.round(W * dpr)) { c.width = Math.round(W * dpr); c.height = Math.round(H * dpr); }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const dt = Math.min(0.1, (now - this.last) / 1000); this.last = now;
    const n = dt * this.pxs + this.carry; const k = Math.floor(n); this.carry = n - k;
    const hr = Math.max(0, st.hr || 0);
    for (let i = 0; i < k; i++) {
      const sdt = 1 / this.pxs; let y = 0;
      const r = st.rhythm;
      if (r === 'VF') { this.vf += sdt * 11; y = 0.55 * Math.sin(this.vf * 3.1) * (0.6 + 0.4 * Math.sin(this.vf * 0.7)) + 0.25 * Math.sin(this.vf * 7.3) + (Math.random() - 0.5) * 0.15; }
      else if (r === 'ASYS' || hr <= 0) { y = (Math.random() - 0.5) * 0.03 + 0.02 * Math.sin(now / 900); }
      else {
        const prev = this.phase;
        this.phase += sdt * hr / 60 / this.rr;
        if (this.phase >= 1) { this.phase -= 1; if (r === 'AF') this.rr = 0.65 + Math.random() * 0.7; else this.rr = 1; if (this.onBeat) this.onBeat(); }
        if (r === 'PEA') y = wide(this.phase);
        else if (r === 'SVT') y = beat(this.phase, { p: 0, t: 0.1 }) * 0.9;
        else if (r === 'AF') y = beat(this.phase, { p: 0, t: 0.2 }) + (Math.random() - 0.5) * 0.08;
        else y = beat(this.phase, { p: 0.14, t: 0.26 });
        y += (Math.random() - 0.5) * 0.015;
      }
      if (st.cpr) y += 0.7 * Math.sin(now / 1000 * Math.PI * 2 * 1.8 + i * 0.01) + (Math.random() - 0.5) * 0.1;
      this.buf.push(y);
    }
    const maxN = Math.ceil(W);
    if (this.buf.length > maxN) this.buf.splice(0, this.buf.length - maxN);
    ctx.clearRect(0, 0, W, H);
    // grid
    ctx.strokeStyle = '#0d2a1c'; ctx.lineWidth = 1; ctx.beginPath();
    for (let x = 0; x < W; x += 20) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
    for (let y = 0; y < H; y += 20) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
    ctx.stroke();
    ctx.strokeStyle = st.bad ? '#ff5c6c' : '#5cff8a'; ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.beginPath();
    const base = H * 0.68, amp = H * 0.5;
    for (let i = 0; i < this.buf.length; i++) { const x = i + (maxN - this.buf.length) * 0; const yy = base - this.buf[i] * amp; if (i === 0) ctx.moveTo(x, yy); else ctx.lineTo(x, yy); }
    ctx.stroke();
  };

  // ---- audio
  let ac = null;
  HS.audio = { on: true };
  function ctx() { if (!ac) { try { ac = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return null; } } if (ac.state === 'suspended') ac.resume(); return ac; }
  HS.beep = function (freq, ms, vol, type) {
    if (!HS.audio.on) return;
    const a = ctx(); if (!a) return;
    const o = a.createOscillator(), gn = a.createGain();
    o.type = type || 'sine'; o.frequency.value = freq; gn.gain.value = vol || 0.05;
    o.connect(gn); gn.connect(a.destination);
    const t = a.currentTime; gn.gain.setValueAtTime(vol || 0.05, t); gn.gain.exponentialRampToValueAtTime(0.0001, t + ms / 1000);
    o.start(t); o.stop(t + ms / 1000 + 0.02);
  };
  HS.alarm = function () { HS.beep(880, 160, 0.09, 'square'); setTimeout(() => HS.beep(660, 160, 0.09, 'square'), 190); setTimeout(() => HS.beep(880, 160, 0.09, 'square'), 380); if (navigator.vibrate) { try { navigator.vibrate([200, 100, 200]); } catch (e) {} } };
  HS.siren = function () { HS.beep(700, 220, 0.05, 'triangle'); setTimeout(() => HS.beep(950, 220, 0.05, 'triangle'), 240); };
  HS.ding = function () { HS.beep(1200, 140, 0.05, 'sine'); };
})(typeof globalThis !== 'undefined' ? globalThis : window);
