/* Boot, main loop, save/load, menus. */
(function (G) {
  const HS = G.HS, U = HS.UI;
  const $ = (s, el) => (el || document).querySelector(s);
  const KEY = 'mercy_er_save_v2';
  const MS_PER_MIN = 900; // 1x speed: one game minute every 0.9 s
  let acc = 0, last = 0;

  function save() {
    if (!U.g || U.g.over) return;
    try { localStorage.setItem(KEY, HS.serialize(U.g)); } catch (e) { /* storage unavailable */ }
  }
  function loadSave() {
    try { const t = localStorage.getItem(KEY); return t ? HS.deserialize(t) : null; } catch (e) { return null; }
  }
  HS.save = save;

  function startGame(g) {
    U.g = g; U.tab = "er"; U.pid = null; U.speed = 1; U.hold = false; G.__over = false;
    $('#start').classList.add('hidden'); $('#sheet').classList.add('hidden'); U.closeModal();
    U.refresh();
    last = performance.now();
  }

  function showStart() {
    const has = !!loadSave();
    $('#start').classList.remove('hidden');
    $('#start').innerHTML = `<div class="title"><div class="logo">🏥</div><h1>MERCY GENERAL</h1><div class="sub" style="letter-spacing:3px;text-transform:uppercase">Emergency Department Simulator</div>
      <p class="sub" style="max-width:340px;margin:18px auto">You are the attending physician. Walk-ins, ambulances, accidents, surprises. Diagnose, treat, operate — or send them home. Choose wisely.</p>
      <div style="max-width:320px;margin:20px auto 0;display:grid;gap:10px">
        ${has ? '<button class="btn pri block" data-m="cont" style="padding:15px">▶ Continue shift</button>' : ''}
        <button class="btn ${has ? '' : 'pri'} block" data-m="new:1" style="padding:15px">New shift — Attending (normal)</button>
        <button class="btn block" data-m="new:0.7">New shift — Resident (calmer)</button>
        <button class="btn block" data-m="new:1.5">New shift — Chief (chaos)</button>
        <button class="btn block" data-m="help">How to play</button>
        <button class="btn block" data-m="snd">🔊 Sound: ${HS.audio.on ? 'on' : 'off'}</button></div>
      <p class="hint" style="margin-top:22px">Educational game. Medical content is simplified and is not clinical advice.</p></div>`;
  }
  function help() {
    U.modal(`<h3>How to play</h3><div class="help">
      <p><b>The loop:</b> Patients arrive in the <b>Triage</b> tab (🚑 ambulances inbound, walk-ins in the waiting room). Bring them to an ER bay, then take a <b>History</b>, <b>examine</b>, order <b>Tests</b>, <b>Treat</b>, and decide on a <b>Disposition</b>.</p>
      <p><b>Vitals:</b> Patients on a cardiac monitor show live vitals. Others are only updated every ~25 minutes — place sick patients on the monitor.</p>
      <p><b>Emergency kit (the ASAP gear):</b> tourniquets for limb bleeds (right limb, high and tight), pressure dressings, hemostatic gauze, pelvic binders, C-collars, chest seals, needle decompression, chest tubes, O₂/BVM/intubation/cric kits, IV/IO access, blood, TXA, a defibrillator and restraints for violent patients. Stock is limited — restock in <b>Supplies</b>.</p>
      <p><b>Emergencies:</b> Cardiac arrest, anaphylaxis, seizures, airway obstruction, tension pneumothorax, re-bleeds, hypoglycaemia, septic shock and violent patients can strike any patient, any time. A red banner will appear — tap <b>GO</b>.</p>
      <p><b>Cardiac arrest:</b> Start CPR immediately. Shock only VF. Give epinephrine every 3–5 min and treat the cause (blood, decompression, airway, naloxone…).</p>
      <p><b>Surgery:</b> From the Disposition tab choose an operation: pick anaesthesia, finish the checklist, then pick the right instrument and time your cut. Time passes in the rest of the hospital while you operate.</p>
      <p><b>Careful:</b> allergies (ask!), drug doses, giving thrombolytics or heparin to bleeding patients, and sending sick people home will cost lives, money and reputation. Reputation 0 = you're fired.</p></div>
      <button class="btn block pri" data-closemodal="1">Got it</button>`);
  }
  U_menu();
  function U_menu() {
    HS.menu = function () {
      U.modal(`<h3>Menu</h3><div style="display:grid;gap:8px">
        <button class="btn block" data-m="save">💾 Save now</button>
        <button class="btn block" data-m="snd2">🔊 Sound: ${HS.audio.on ? 'on' : 'off'}</button>
        <button class="btn block" data-m="help2">How to play</button>
        <button class="btn block danger" data-m="quit">Quit to title (progress saved)</button>
        <button class="btn block" data-closemodal="1">Close</button></div>`);
    };
  }

  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-m]'); if (!t) return;
    const m = t.dataset.m;
    if (m === 'cont') { const g = loadSave(); if (g) startGame(g); }
    else if (m.startsWith('new:')) { HS.seed(Date.now()); startGame(HS.newGame({ diff: parseFloat(m.slice(4)) })); save(); }
    else if (m === 'help') { $('#start').classList.add('hidden'); help(); U.closeModalHook = () => showStart(); }
    else if (m === 'help2') help();
    else if (m === 'snd') { HS.audio.on = !HS.audio.on; showStart(); }
    else if (m === 'snd2') { HS.audio.on = !HS.audio.on; HS.menu(); }
    else if (m === 'save') { save(); U.closeModal(); U.toast('Game saved', 'good'); }
    else if (m === 'quit') { save(); U.closeModal(); U.g = null; showStart(); }
    else if (m === 'over') { try { localStorage.removeItem(KEY); } catch (e2) {} U.closeModal(); U.g = null; showStart(); }
  });
  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-closemodal]') && U.closeModalHook) { const f = U.closeModalHook; U.closeModalHook = null; setTimeout(f, 0); }
  });

  function gameOver() {
    const g = U.g, st = g.stats;
    U.modal(`<h3>🏚 Your reputation hit zero</h3><div class="sub">The hospital board has terminated your contract.</div>
      <dl class="kv" style="margin:10px 0"><dt>Survived</dt><dd>${HS.dayOf(g.t)} day(s)</dd><dt>Patients saved</dt><dd>${st.saved}</dd><dt>Deaths</dt><dd>${st.died}</dd><dt>Surgeries</dt><dd>${st.surgOk}/${st.surgeries}</dd><dt>Diagnosis acc.</dt><dd>${st.dxN ? Math.round(100 * st.dxOk / st.dxN) + '%' : '—'}</dd></dl>
      <button class="btn block pri" data-m="over">Back to title</button>`);
  }

  function frame(now) {
    requestAnimationFrame(frame);
    const g = U.g;
    if (!g) return;
    const dt = Math.min(250, now - last); last = now;
    U.animate(now);
    if (U.speed > 0 && !U.hold && !g.over) {
      acc += dt * U.speed;
      let n = 0;
      while (acc >= MS_PER_MIN && n < 12) {
        acc -= MS_PER_MIN; n++;
        HS.tick(g);
        if (g.over) break;
      }
      if (n) {
        U.tickUpdate();
        if (g.t % 30 < n) save();
      }
    }
    if (g.over && !G.__over) { G.__over = true; gameOver(); }
  }

  document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });
  G.addEventListener('pagehide', save);
  G.addEventListener('DOMContentLoaded', () => { showStart(); requestAnimationFrame(frame); });
  if (document.readyState !== 'loading') { showStart(); requestAnimationFrame(frame); }
  // Android back button: close the top-most layer. Returns true when something was closed.
  HS.back = function () {
    if (!U.g) return false;
    if (!$('#modal').classList.contains('hidden') && !U.hold) { U.closeModal(); return true; }
    if (U.sheetOpen && U.sheetOpen()) { U.closeSheet(); return true; }
    if (!$('#start').classList.contains('hidden')) return false;
    if (U.tab !== 'er') { U.tab = 'er'; U.refresh(); return true; }
    return false;
  };
  // expose for tests
  HS.debug = { startGame, save };
})(typeof globalThis !== 'undefined' ? globalThis : window);
