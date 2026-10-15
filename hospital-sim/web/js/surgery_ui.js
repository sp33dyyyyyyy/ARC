/* Operating theatre + bedside procedure mini-game. */
(function (G) {
  const HS = G.HS, U = HS.UI;
  const $ = (s, el) => (el || document).querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  let SX = null, raf = 0;

  const monitor = (p) => {
    const v = p.v, f = HS.vitalFlag(v);
    const c = (k) => (f[k] === 2 ? 'color:var(--crit)' : f[k] === 1 ? 'color:var(--warn)' : '');
    return `<div class="monitor"><div class="vgrid" style="grid-template-columns:repeat(4,1fr)">
      <div class="vt hr"><label>HR</label><b style="${c('hr')}">${Math.round(v.hr)}</b></div><div class="vt bp"><label>BP</label><b style="font-size:18px;${c('sbp')}">${Math.round(v.sbp)}/${Math.round(v.dbp)}</b></div>
      <div class="vt sp"><label>SpO₂</label><b style="${c('spo2')}">${Math.round(v.spo2)}</b></div><div class="vt rr"><label>Blood lost</label><b style="font-size:18px">${Math.round(p.blood)}<small> mL</small></b></div></div></div>`;
  };

  // ---------------------------------------------------------------- entry points
  HS.openSurgery = function (pid, sid) {
    const g = U.g, p = g.patients[pid], S = HS.SURGERIES[sid];
    if (!p || p.arrest) return U.toast('Cannot operate during a cardiac arrest.', 'warn');
    const free = g.beds.or.some((b) => !b.pid && !!b.cath === !!S.cath);
    if (!free) return U.toast(S.cath ? 'The cath lab is busy.' : 'Both operating rooms are busy.', 'warn');
    SX = { mode: 'or', pid, sid, S, phase: 'preop', an: null, checks: {}, step: 0, q: [], t0: g.t, evs: 0 };
    U.hold = true;
    renderPre();
  };
  HS.startProcedure = function (pid, aid, sid) {
    const S = HS.SURGERIES[sid];
    SX = { mode: 'bed', pid, aid, sid, S, phase: 'step', step: 0, q: [], t0: U.g.t, evs: 0 };
    U.hold = true;
    renderStep();
  };

  // ---------------------------------------------------------------- pre-op
  function prepScore(p) {
    const n = Object.values(SX.checks).filter(Boolean).length / 4;
    const emergency = HS.sevEff(p) >= 55 || HS.bleedRate(p) > 20;
    return emergency ? Math.max(n, 0.75) : n;
  }
  function renderPre() {
    const g = U.g, p = g.patients[SX.pid], S = SX.S;
    const chk = (k, l, sub) => `<button class="btn block ${SX.checks[k] ? 'pri' : ''}" style="text-align:left;margin-bottom:6px" data-px="chk:${k}">${SX.checks[k] ? '☑' : '☐'} ${l}<div class="sub" style="color:inherit;opacity:.8">${sub}</div></button>`;
    const ans = S.cath ? ['local'] : ['GA', 'regional', 'local'];
    U.modal(`<div class="row sb"><h3>${esc(S.name)}</h3><button class="btn sm" data-px="cancel">Cancel</button></div>
      <div class="sub">${esc(p.name)} · ${p.age}${p.sex} · ${p.wt} kg · ${esc(S.desc)}</div>${monitor(p)}
      <h2 class="sec">Anaesthesia</h2>
      ${ans.map((a) => `<button class="btn block ${SX.an === a ? 'pri' : ''}" style="margin-bottom:6px" data-px="an:${a}">${HS.ANAES[a]}</button>`).join('')}
      <h2 class="sec">Pre-op checklist</h2>
      ${chk('consent', 'Consent', p.v.gcs < 15 ? 'Patient cannot consent — emergency exception' : 'Patient agrees to the operation')}
      ${chk('abx', 'Antibiotic prophylaxis', p.tags.abx ? 'Already given' : 'Give a single dose before incision')}
      ${chk('blood', 'Blood available', `${g.supplies.blood} O-neg units in stock`)}
      ${chk('timeout', 'Surgical time-out', 'Right patient, right procedure, right site')}
      <div class="hint">Skipping safety checks is tolerated only in true emergencies. Time keeps running elsewhere while you operate.</div>
      <div class="spacer"></div><button class="btn block pri ${SX.an ? '' : 'dis'}" data-px="start">Scrub in & start</button>`, true);
  }

  // ---------------------------------------------------------------- steps
  function renderStep() {
    const g = U.g, p = g.patients[SX.pid], S = SX.S;
    if (SX.step >= S.steps.length) return finish();
    const st = S.steps[SX.step];
    if (!SX.opts || SX.opts.i !== SX.step) {
      const pool = Object.keys(HS.TOOLS).filter((k) => k !== st[1]);
      SX.opts = { i: SX.step, list: HS.shuffle([st[1]].concat(HS.shuffle(pool).slice(0, 3))) };
    }
    const prog = (SX.step / S.steps.length) * 100;
    U.modal(`<div class="row sb"><b>${esc(S.name)}</b><span class="sub">Step ${SX.step + 1}/${S.steps.length}</span></div>
      <div class="opbar"><i style="width:${prog}%"></i></div>${monitor(p)}
      <div class="card"><div class="sub">NOW</div><div class="name" style="font-size:18px">${esc(st[0])}</div></div>
      <div class="sub" style="margin:6px 2px">Choose the right instrument:</div>
      <div class="tools">${SX.opts.list.map((k) => `<button class="btn" data-px="tool:${k}"><i>${HS.TOOLS[k][1]}</i>${HS.TOOLS[k][0]}</button>`).join('')}</div>
      ${SX.msg ? `<div class="note ${SX.msgBad ? 'bad' : ''}" style="margin-top:10px">${SX.msg}</div>` : ''}`, true);
  }
  function renderMeter(tool) {
    const g = U.g, p = g.patients[SX.pid], st = SX.S.steps[SX.step];
    const crit = st[3] >= 300;
    SX.meter = { tool, zone: crit ? 0.15 : 0.23, center: 0.25 + Math.random() * 0.5, speed: crit ? 3.2 : 2.3, t: performance.now() };
    const M = SX.meter;
    U.modal(`<div class="row sb"><b>${esc(st[0])}</b><span class="sub">${HS.TOOLS[tool][1]} ${HS.TOOLS[tool][0]}</span></div>${monitor(p)}
      <div class="center sub" style="margin-top:10px">Tap when the marker is inside the green zone${crit ? ' — delicate!' : ''}</div>
      <div class="meter" id="meter"><div class="zone" style="left:${(M.center - M.zone / 2) * 100}%;width:${M.zone * 100}%"></div><div class="cur" id="cur"></div></div>
      <button class="bigbtn" data-px="go">${SX.mode === 'bed' ? 'GO' : 'CUT'}</button>`, true);
    cancelAnimationFrame(raf);
    const loop = (now) => {
      if (!SX || !SX.meter) return;
      const cur = $('#cur'); if (!cur) return;
      const pos = 0.5 + 0.5 * Math.sin(((now - M.t) / 1000) * M.speed);
      M.pos = pos; cur.style.left = pos * 100 + '%';
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
  }
  function accuracy(M) {
    const d = Math.abs(M.pos - M.center), half = M.zone / 2;
    return d <= half ? 1 - 0.4 * (d / half) : Math.max(0, 0.6 * (1 - (d - half) / (half * 1.6)));
  }
  function doStep(tool) {
    cancelAnimationFrame(raf);
    const g = U.g, p = g.patients[SX.pid], st = SX.S.steps[SX.step];
    const acc = accuracy(SX.meter);
    const ok = tool === st[1];
    const q = ok ? acc : acc * 0.25;
    const loss = Math.round(st[3] * Math.pow(1 - q, 1.2) + 10);
    p.blood += loss;
    SX.q.push(q);
    SX.msg = `${ok ? '✔ Right instrument' : `✘ Wrong instrument — you needed the ${HS.TOOLS[st[1]][0].toLowerCase()}`}, technique ${Math.round(acc * 100)}% — ${loss} mL blood lost.`;
    SX.msgBad = !ok || acc < 0.55;
    const mins = st[2];
    HS.advance(g, mins);
    SX.step++;
    SX.meter = null;
    if (p.dead || g.over) return finish();
    // intra-op event
    if (SX.step < SX.S.steps.length && SX.mode === 'or' && Math.random() < 0.32) return renderEvent();
    renderStep();
  }
  const EVENTS = [
    { t: '🩸 A vessel is spurting!', opts: [['Clamp it', 1, 0], ['Cautery it', 1, 0], ['Suction and look', 0.5, 150], ['Irrigate', 0.1, 400]] },
    { t: '📉 Anaesthetist: "Systolic is in the 70s and falling!"', opts: [['Transfuse a unit of blood', 1, 0, 'blood'], ['Fluid bolus', 0.6, 100], ['Carry on operating', 0.1, 350]] },
    { t: '😬 The patient is moving — anaesthesia is too light!', opts: [['Deepen anaesthesia', 1, 0], ['Give more local', 0.5, 40], ['Ignore it', 0.05, 200]] },
  ];
  function renderEvent() {
    const e = EVENTS[Math.floor(Math.random() * EVENTS.length)];
    SX.ev = e;
    const p = U.g.patients[SX.pid];
    U.modal(`<h3 style="color:var(--crit)">${e.t}</h3>${monitor(p)}<div class="sub" style="margin-bottom:8px">Decide quickly:</div>
      ${HS.shuffle(e.opts.map((o, i) => [o, i])).map(([o, i]) => `<button class="btn block" style="margin-bottom:6px" data-px="ev:${i}">${o[0]}</button>`).join('')}`, true);
  }
  function doEvent(i) {
    const g = U.g, p = g.patients[SX.pid], o = SX.ev.opts[i];
    let q = o[1];
    if (o[3] === 'blood') {
      if (g.supplies.blood > 0) { HS.act(g, p.id, 'prbc', { quick: true }); p.iv = true; HS.advance(g, 1); }
      else { q = 0.2; SX.msg = 'No blood in stock!'; SX.msgBad = true; }
    }
    p.blood += o[2];
    SX.q.push(q);
    SX.msg = `${o[0]} — ${q >= 0.9 ? 'good call.' : q >= 0.5 ? 'it helped partly.' : 'that made things worse.'}`;
    SX.msgBad = q < 0.5;
    renderStep();
  }

  // ---------------------------------------------------------------- finish
  function finish() {
    cancelAnimationFrame(raf);
    const g = U.g, p = g.patients[SX.pid], S = SX.S;
    const avg = SX.q.length ? SX.q.reduce((a, b) => a + b, 0) / SX.q.length : 0;
    const mins = g.t - SX.t0;
    let html = '';
    if (SX.mode === 'bed') {
      const r = HS.act(g, SX.pid, SX.aid, { score: Math.round(avg * 100) });
      html = `<h3>${esc(S.name)}</h3><div class="card ${avg > 0.5 ? '' : 'crit'}"><div class="big">${Math.round(avg * 100)}%</div><div class="sub">Technique quality</div></div><div class="note">${esc(r.msg || 'Procedure queued.')}</div>`;
    } else if (p.dead) {
      html = `<h3>Operation ended</h3><div class="card crit"><b>${esc(p.name)} died.</b><div class="sub">${esc(p.cause || '')}</div></div>`;
    } else {
      const an = SX.an === S.an ? 1 : (S.ok || []).includes(SX.an) ? 0.65 : 0.1;
      const out = HS.finishSurgery(g, SX.pid, { sid: SX.sid, score: Math.round(avg * 100), blood: 0, prep: prepScore(p), anaes: an });
      const good = out.outcome === 'success', bad = out.outcome === 'death' || out.outcome === 'wrong';
      html = `<h3>${good ? '✅ Operation successful' : out.outcome === 'complication' ? '⚠ Completed with complications' : out.outcome === 'wrong' ? '❌ Wrong operation' : '☠ Patient died'}</h3>
        <div class="card ${bad ? 'crit' : ''}"><div class="big">${Math.round(avg * 100)}%</div><div class="sub">Surgical performance · ${mins} min · ${Math.round(SX.q.length)} checks</div></div>
        <div class="note ${bad ? 'bad' : ''}">${esc(out.msg)}</div>
        <div class="note">Anaesthesia: ${an === 1 ? 'ideal' : an > 0.5 ? 'acceptable' : 'poor choice'} · Prep: ${Math.round(prepScore(p) * 100)}%</div>`;
    }
    html += `<div class="note"><small>While you were in theatre (${mins} min) the department kept running — check the board!</small></div><button class="btn block pri" data-px="done">Back to the department</button>`;
    U.modal(html, true);
    SX.finished = true;
  }

  // ---------------------------------------------------------------- clicks
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-px]'); if (!t || !SX) return;
    const [k, v] = t.dataset.px.split(':');
    if (k === 'cancel') { SX = null; U.hold = false; U.closeModal(); return; }
    if (k === 'an') { SX.an = v; return renderPre(); }
    if (k === 'chk') { SX.checks[v] = !SX.checks[v]; return renderPre(); }
    if (k === 'start') {
      const g = U.g, p = g.patients[SX.pid];
      if (SX.checks.abx && !p.tags.abx) { p.tags.abx = { t: g.t, str: 1 }; p.tags.abx_broad = { t: g.t, str: 1 }; }
      const r = HS.toOR(g, SX.pid, SX.sid);
      if (!r.ok) { U.toast(r.msg, 'warn'); SX = null; U.hold = false; U.closeModal(); return; }
      p.iv = true; SX.phase = 'step';
      HS.advance(g, 6); // transport + induction
      return renderStep();
    }
    if (k === 'tool') return renderMeter(v);
    if (k === 'go') return doStep(SX.meter.tool);
    if (k === 'ev') return doEvent(+v);
    if (k === 'done') { SX = null; U.hold = false; U.closeModal(); const open = U.pid; U.closeSheet(); U.drainEvents(); U.refresh(); return; }
  });
})(typeof globalThis !== 'undefined' ? globalThis : window);
