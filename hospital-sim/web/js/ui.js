/* Mercy General ER — UI (vanilla JS). */
(function (G) {
  const HS = G.HS;
  const $ = (s, el) => (el || document).querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const U = (HS.UI = { g: null, tab: 'er', pid: null, ptab: 'ov', speed: 1, ecg: null, toastN: 0, lastRender: 0 });

  // ------------------------------------------------------------ helpers
  const esiChip = (p) => `<span class="esi esi${p.esi}">ESI ${p.esi}</span>`;
  const flagCls = (n) => (n >= 2 ? 'crit' : n === 1 ? 'warn' : '');
  function bleedingVisible(p) {
    const b = p.bleed;
    return !!(b && !b.stopped && !p.cured && b.kind !== 'torso' && b.kind !== 'internal_thigh' && HS.bleedRate(p) > 8);
  }
  function isCrit(p) {
    if (p.dead || p.loc === 'gone') return false;
    if (p.arrest || p.crisis) return true;
    const s = HS.shown(p); if (!s) return false;
    const f = HS.vitalFlag(s);
    return f.sbp === 2 || f.spo2 === 2 || f.hr === 2 && s.hr > 130 || f.gcs === 2;
  }
  function miniVitals(p) {
    const s = HS.shown(p); if (!s) return '';
    const f = HS.vitalFlag(s);
    const c = (k) => (f[k] === 2 ? 'c' : f[k] === 1 ? 'w' : '');
    return `<div class="mini"><span class="${c('hr')}">♥ ${Math.round(s.hr)}</span><span class="${c('sbp')}">${Math.round(s.sbp)}/${Math.round(s.dbp)}</span><span class="${c('spo2')}">O₂ ${Math.round(s.spo2)}%</span><span class="${c('rr')}">RR ${Math.round(s.rr)}</span></div>`;
  }
  function statusChips(p, g) {
    const c = [];
    if (p.arrest) c.push(`<span class="chip crit">CARDIAC ARREST ${p.arrest.rhythm}</span>`);
    if (p.crisis) c.push(`<span class="chip crit">${HS.CRISES[p.crisis.type].label}</span>`);
    if (bleedingVisible(p)) c.push('<span class="chip crit">🩸 BLEEDING</span>');
    if (p.tq) c.push(`<span class="chip warn">🎗 TQ ${g.t - p.tq.t}m</span>`);
    if (p.restrainedAt) c.push('<span class="chip warn">⛓ restrained</span>');
    if (p.o2) c.push('<span class="chip info">O₂</span>');
    if (p.io) c.push('<span class="chip info">IO</span>'); else if (p.iv) c.push('<span class="chip info">IV</span>');
    if (p.airway) c.push('<span class="chip info">ETT</span>');
    if (p.dev.collar) c.push('<span class="chip info">C-collar</span>');
    if (p.dev.binder) c.push('<span class="chip info">binder</span>');
    if (p.dev.splint) c.push('<span class="chip info">splint</span>');
    if (p.dev.chestseal) c.push('<span class="chip info">chest seal</span>');
    if (p.onMonitor) c.push('<span class="chip ok">monitor</span>');
    if (p.cured) c.push('<span class="chip ok">post-op</span>');
    return c.length ? `<div class="chips">${c.join('')}</div>` : '';
  }
  function patientCard(p, bed, g) {
    const crit = isCrit(p);
    return `<div class="card tap ${crit ? 'crit' : ''}" data-open="${p.id}">
      <div class="row"><span class="bed ${bed && bed.resus ? 'resus' : ''}">${esc(bed ? bed.id : p.bedId || '—')}</span>
        <div class="grow"><div class="name">${esc(p.name)} <span class="sub">${p.age}${p.sex} · ${p.wt}kg</span></div>
        <div class="sub">${esc(p.dx ? 'Dx: ' + HS.CONDS[p.dx].name : p.cc)}</div></div>${esiChip(p)}</div>
      ${miniVitals(p)}${statusChips(p, g)}</div>`;
  }

  // ------------------------------------------------------------ top bar / tabs / alerts
  U.renderTop = function () {
    const g = U.g;
    const rep = Math.round(g.rep);
    $('#topbar').innerHTML = `
      <div class="clock"><small>Day ${HS.dayOf(g.t)}</small>${HS.fmtTime(g.t)}</div>
      <div class="speed">${[[0, '⏸'], [1, '1×'], [2, '2×'], [4, '4×'], [8, '8×']].map(([s, l]) => `<button data-speed="${s}" class="${U.speed === s ? 'on' : ''}">${l}</button>`).join('')}</div>
      <div class="stats"><b style="color:${g.funds < 0 ? 'var(--crit)' : 'var(--ok)'}">${HS.money(g.funds)}</b><br><span>Rep ${rep}</span><div class="repbar"><i style="width:${rep}%;background:${rep < 30 ? 'var(--crit)' : rep < 55 ? 'var(--warn)' : 'var(--ok)'}"></i></div></div>`;
  };
  U.renderTabs = function () {
    const g = U.g, s = HS.summary(g);
    const T = [['er', '🏥', 'ER'], ['tri', '🚑', 'Triage', s.waiting + s.inbound], ['ward', '🛏️', 'Wards'], ['sup', '📦', 'Supplies'], ['log', '📋', 'Log']];
    $('#tabbar').innerHTML = T.map(([k, i, l, n]) => `<button data-tab="${k}" class="${U.tab === k ? 'on' : ''}"><i>${i}</i>${l}${n ? `<span class="badge">${n}</span>` : ''}</button>`).join('');
  };
  U.renderAlerts = function () {
    const g = U.g, out = [];
    for (const id in g.patients) {
      const p = g.patients[id];
      if (p.dead || p.loc === 'gone' || p.loc === 'inbound') continue;
      if (p.arrest) out.push(`<div class="alert"><span>🚨 CARDIAC ARREST — ${esc(p.name)} (${esc(p.bedId || p.loc)}) ${p.arrest.rhythm}${p.arrest.cpr ? '' : ' · NO CPR!'}</span><button class="go" data-open="${p.id}">GO</button></div>`);
      else if (p.crisis) out.push(`<div class="alert"><span>🚨 ${HS.CRISES[p.crisis.type].label} — ${esc(p.name)} (${esc(p.bedId || p.loc)})</span><button class="go" data-open="${p.id}">GO</button></div>`);
    }
    for (const id of g.inbound) {
      const p = g.patients[id];
      if (p.crit) out.push(`<div class="alert ok" style="background:#3a2a00;border-color:var(--warn);color:#ffe3a3"><span>🚑 ${esc(p.cc)} — ETA ${p.eta} min</span><button class="go" style="background:var(--warn);color:#000" data-open="${p.id}">PREP</button></div>`);
    }
    $('#alerts').innerHTML = out.slice(0, 3).join('');
  };

  // ------------------------------------------------------------ views
  U.renderView = function () {
    const el = $('#view'); const top = el.scrollTop;
    el.innerHTML = ({ er: viewEr, tri: viewTri, ward: viewWard, sup: viewSup, log: viewLog })[U.tab]();
    el.scrollTop = top;
  };

  function viewEr() {
    const g = U.g;
    let h = `<h2 class="sec">Emergency department <span class="n">${g.beds.er.filter((b) => b.pid).length}/${g.beds.er.length} beds</span></h2>`;
    for (const bed of g.beds.er) {
      if (bed.pid && g.patients[bed.pid] && !g.patients[bed.pid].dead) h += patientCard(g.patients[bed.pid], bed, g);
      else h += `<div class="card empty">${bed.resus ? '🔴 RESUS ' : ''}${bed.id} — free</div>`;
    }
    const wait = Object.values(g.patients).filter((p) => p.loc === 'waiting');
    if (wait.length) h += `<div class="card warn tap" data-tab="tri"><b>${wait.length} patient${wait.length > 1 ? 's' : ''} in the waiting room</b><div class="sub">Tap to triage</div></div>`;
    return h;
  }

  function viewTri() {
    const g = U.g;
    let h = `<h2 class="sec">Ambulances inbound <span class="n">${g.inbound.length}</span></h2>`;
    if (!g.inbound.length) h += '<div class="card empty">No ambulances en route</div>';
    for (const id of g.inbound) {
      const p = g.patients[id];
      h += `<div class="card tap ${p.crit ? 'crit' : 'warn'}" data-open="${p.id}">
        <div class="row"><span class="chip crit">🚑 ETA ${p.eta} min</span><div class="grow name">${p.age}${p.sex}</div>${esiChip(p)}</div>
        <div class="sub" style="margin-top:4px">${esc(HS.handover(p))}</div>
        <div class="btnrow"><button class="btn sm pri" data-hold="${p.id}:resus">Hold RESUS bay</button><button class="btn sm" data-hold="${p.id}:bay">Hold normal bay</button></div>
        ${p.reserved ? `<div class="chips"><span class="chip ok">Bed ${p.reserved} held — equipment laid out</span></div>` : ''}</div>`;
    }
    const wait = Object.values(g.patients).filter((p) => p.loc === 'waiting').sort((a, b) => a.esi - b.esi || a.t0 - b.t0);
    h += `<h2 class="sec">Waiting room <span class="n">${wait.length}</span></h2>`;
    if (!wait.length) h += '<div class="card empty">Waiting room is empty</div>';
    for (const p of wait) {
      const s = p.seen; const f = HS.vitalFlag(s);
      h += `<div class="card ${p.esi <= 2 ? 'crit' : p.esi === 3 ? 'warn' : ''}">
        <div class="row"><div class="grow"><div class="name">${esc(p.name)} <span class="sub">${p.age}${p.sex}${p.amb ? ' · ambulance' : ''}</span></div><div class="sub">"${esc(p.cc)}"</div></div>${esiChip(p)}</div>
        ${miniVitals(p)}<div class="row sb"><span class="sub">Waiting ${HS.fmtDur(g.t - p.t0)}</span>
        <button class="btn sm pri" data-bring="${p.id}">Bring to bay →</button></div></div>`;
    }
    return h;
  }

  function viewWard() {
    const g = U.g;
    let h = '';
    for (const [k, title] of [['icu', 'Intensive care'], ['ward', 'General ward'], ['or', 'Operating theatres']]) {
      h += `<h2 class="sec">${title} <span class="n">${g.beds[k].filter((b) => b.pid).length}/${g.beds[k].length}</span></h2>`;
      for (const bed of g.beds[k]) {
        const p = bed.pid && g.patients[bed.pid];
        if (p && !p.dead) h += patientCard(p, bed, g);
        else h += `<div class="card empty">${bed.id}${bed.cath ? ' (cath lab)' : ''} — free</div>`;
      }
    }
    return h;
  }

  function viewSup() {
    const g = U.g, st = g.stats;
    let h = `<h2 class="sec">Finances & performance</h2><div class="card"><dl class="kv">
      <dt>Funds</dt><dd><b>${HS.money(g.funds)}</b></dd><dt>Earned</dt><dd>${HS.money(st.earned)}</dd><dt>Supplies/tests</dt><dd>${HS.money(st.spent)}</dd>
      <dt>Reputation</dt><dd>${Math.round(g.rep)}/100</dd><dt>Patients seen</dt><dd>${st.seen}</dd><dt>Sent home</dt><dd>${st.home}</dd><dt>Admitted</dt><dd>${st.admitted}</dd>
      <dt>Surgeries</dt><dd>${st.surgOk}/${st.surgeries} successful</dd><dt>Saved</dt><dd>${st.saved}</dd><dt>Died</dt><dd>${st.died}</dd>
      <dt>Emergencies</dt><dd>${st.crisesOk}/${st.crises} handled</dd><dt>Diagnosis acc.</dt><dd>${st.dxN ? Math.round((100 * st.dxOk) / st.dxN) + '%' : '—'}</dd></dl></div>`;
    h += '<h2 class="sec">Emergency supplies</h2>';
    for (const k in HS.SUPPLIES) {
      const S = HS.SUPPLIES[k], n = g.supplies[k];
      h += `<div class="card"><div class="row"><div class="grow"><b>${S.n}</b> <span class="stock ${n <= 2 ? 'low' : ''}">${n}/${S.max}</span><div class="sub">${HS.money(S.cost)} each</div></div>
        <button class="btn sm" data-restock="${k}:1">+1</button><button class="btn sm pri" data-restock="${k}:${S.max}">Fill</button></div></div>`;
    }
    return h;
  }

  function viewLog() {
    const g = U.g;
    let h = '<h2 class="sec">Hospital log</h2>';
    for (const l of g.log.slice(0, 80)) h += `<div class="note ${l.lvl === 'crit' ? 'bad' : ''}"><small>Day ${HS.dayOf(l.t)} ${HS.fmtTime(l.t)}</small><br>${esc(l.text)}</div>`;
    h += `<div class="btnrow"><button class="btn" data-menu="1">☰ Menu / Save / Quit</button></div>`;
    return h;
  }

  // ------------------------------------------------------------ toasts
  U.toast = function (text, lvl, pid) {
    const el = document.createElement('div');
    el.className = 'toast ' + (lvl || '');
    el.textContent = text;
    if (pid) el.dataset.open = pid;
    const box = $('#toasts');
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => { el.style.transition = 'opacity .4s'; el.style.opacity = 0; setTimeout(() => el.remove(), 450); }, lvl === 'crit' ? 9000 : 5500);
  };
  U.drainEvents = function () {
    const g = U.g; if (!g.events.length) return false;
    let refreshSheet = false;
    for (const e of g.events) {
      if (e.k === 'result' || e.k === 'act' || e.k === 'bad') refreshSheet = true;
      if (e.k === 'act' && (!U.pid || U.pid !== e.pid)) { /* quiet unless the sheet is open elsewhere */ }
      if (e.k === 'act' && U.pid === e.pid) { U.toast(e.text, '', e.pid); continue; }
      U.toast(e.text, e.lvl === 'crit' ? 'crit' : e.lvl === 'warn' ? 'warn' : e.lvl === 'good' ? 'good' : '', e.pid);
      if (e.k === 'crisis' || e.k === 'arrest') { HS.alarm(); U.setSpeed(1); }
      else if (e.k === 'inbound') HS.siren();
      else if (e.k === 'alarm') HS.beep(1000, 120, 0.08, 'square');
      else if (e.k === 'death' || e.k === 'sued' || e.k === 'mci') { HS.alarm(); if (e.k === 'mci') U.setSpeed(1); }
      else if (e.k === 'rosc' || e.k === 'crisis_ok' || e.k === 'recovered') HS.ding();
    }
    g.events.length = 0;
    return refreshSheet;
  };

  // ------------------------------------------------------------ speed
  U.setSpeed = function (s) { U.speed = s; U.renderTop(); };

  // ------------------------------------------------------------ patient sheet
  U.open = function (pid) {
    const p = U.g.patients[pid]; if (!p) return;
    U.pid = pid; U.ptab = 'ov';
    $('#sheet').classList.remove('hidden');
    U.renderSheet(true);
  };
  U.closeSheet = function () {
    U.pid = null; U.ecg = null;
    $('#sheet').classList.add('hidden'); $('#sheet').innerHTML = '';
    U.refresh();
  };

  function allergyChip(p) {
    const asked = p.hxDone && p.hxDone[2] !== undefined;
    if (!asked) return '<span class="chip warn">Allergies: not yet asked</span>';
    if (p.v.gcs <= 8 || p.unconscious) return '<span class="chip crit">Allergies UNKNOWN</span>';
    return p.allergies.length ? `<span class="chip crit">ALLERGY: ${esc(p.allergies.join(', ').toUpperCase())}</span>` : '<span class="chip ok">NKDA</span>';
  }

  U.renderSheet = function (full) {
    const g = U.g, p = g.patients[U.pid];
    if (!p) return U.closeSheet();
    const sh = $('#sheet');
    const body = sh.querySelector('.sbody'); const top = body ? body.scrollTop : 0;
    const bed = HS.bedOf(g, p);
    const head = `<div class="shead"><div class="row"><button class="back" data-close="1">‹ Back</button>
      <div class="grow"><div class="name">${esc(p.name)} <span class="sub">${p.age}${p.sex} · ${p.wt} kg</span></div>
      <div class="sub">${p.loc === 'inbound' ? '🚑 inbound ETA ' + p.eta + ' min' : esc(p.dead ? 'DECEASED' : (p.bedId || p.loc))}${p.dx ? ' · Dx: ' + esc(HS.CONDS[p.dx].name) : ''}</div></div>${esiChip(p)}</div></div>`;
    const tabs = [['ov', 'Overview'], ['hx', 'History'], ['test', 'Tests'], ['tx', 'Treat'], ['dispo', 'Dispo / OR']];
    const tb = `<div class="stabs">${tabs.map(([k, l]) => `<button data-ptab="${k}" class="${U.ptab === k ? 'on' : ''}">${l}</button>`).join('')}</div>`;
    let content = '';
    if (p.dead) content = deadView(p);
    else if (p.loc === 'inbound') content = inboundView(p);
    else content = ({ ov: tabOv, hx: tabHx, test: tabTest, tx: tabTx, dispo: tabDispo })[U.ptab](p, g);
    sh.innerHTML = head + (p.loc === 'inbound' || p.dead ? '' : tb) + `<div class="sbody">${content}</div>`;
    const nb = sh.querySelector('.sbody'); nb.scrollTop = full ? 0 : top;
    if (U.ptab === 'ov' && !p.dead && p.loc !== 'inbound') {
      const cv = $('#ecg'); if (cv) { U.ecg = new HS.Ecg(cv); U.ecg.onBeat = () => { if (HS.audio.on && p.onMonitor && U.speed === 1 && p.v.hr > 0) HS.beep(p.v.spo2 < 90 ? 600 : 880, 50, 0.025); }; }
    } else U.ecg = null;
  };
  U.sheetOpen = () => !$('#sheet').classList.contains('hidden');

  function deadView(p) {
    return `<div class="card crit center"><div class="big">☠ Deceased</div><p>${esc(p.cause || '')}</p><div class="sub">Died ${HS.fmtTime(p.doneAt)}</div></div>
    <div class="note">Condition: <b>${esc(p.condDef.name)}</b>${p.preventable ? ' — this was preventable with faster care.' : ''}</div>
    <button class="btn block" data-close="1">Close</button>`;
  }
  function inboundView(p) {
    return `<div class="sbody"><div class="card crit"><b>🚑 Ambulance inbound — ETA ${p.eta} min</b><p>${esc(HS.handover(p))}</p></div>
      <div class="note">Hold a bay now: the team lays out equipment and everything you do in the first minutes is instant.</div>
      <div class="btnrow"><button class="btn pri" data-hold="${p.id}:resus">Hold RESUS bay</button><button class="btn" data-hold="${p.id}:bay">Hold normal bay</button></div>
      ${p.reserved ? `<div class="chips"><span class="chip ok">Bed ${p.reserved} held</span></div>` : ''}</div>`;
  }

  // ---- overview
  function vitalsGrid(p) {
    const s = HS.shown(p);
    const g = U.g;
    if (!s) return '';
    const f = HS.vitalFlag(s);
    const T = (cls, lab, val, unit, k) => `<div class="vt ${cls} ${flagCls(f[k])}"><label>${lab}</label><b>${val}</b> <small>${unit}</small></div>`;
    let h = `<div class="vgrid">
      ${T('hr', 'HR', Math.round(s.hr), 'bpm', 'hr')}${T('bp', 'BP', `${Math.round(s.sbp)}/${Math.round(s.dbp)}`, 'mmHg', 'sbp')}${T('sp', 'SpO₂', Math.round(s.spo2), '%', 'spo2')}
      ${T('rr', 'RR', Math.round(s.rr), '/min', 'rr')}${T('tm', 'TEMP', s.temp.toFixed(1), '°C', 'temp')}${T('gc', 'GCS', Math.round(s.gcs), '/15', 'gcs')}</div>`;
    if (!p.onMonitor) h += `<div class="stale">⚠ Not on a monitor — vitals last checked ${HS.fmtDur(g.t - s.t)} ago. <button class="btn sm" data-act="monitor">Monitor</button> <button class="btn sm" data-act="recheck">Recheck</button></div>`;
    return h;
  }
  function resusBar(p) {
    if (p.arrest) {
      const a = p.arrest;
      return `<div class="resus"><h4>🚨 Cardiac arrest — ${a.rhythm} · ${HS.fmtDur(U.g.t - a.t0)} · shocks ${a.shocks} · epi ${a.epi}</h4><div class="kit">
        <button class="btn ${a.cpr ? 'danger' : 'pri'}" data-act="cpr">${a.cpr ? '⏹ Stop CPR' : '❤ START CPR'}</button>
        <button class="btn danger" data-act="defib">⚡ SHOCK<small>VF/pVT only</small></button>
        <button class="btn" data-act="epi_iv" data-quick="1">Epi 1 mg<small>every 3–5 min</small></button>
        <button class="btn" data-act="io" data-quick="1">IO access</button><button class="btn" data-act="iv" data-quick="1">IV access</button>
        <button class="btn" data-act="bvm" data-quick="1">BVM / O₂</button>
        <button class="btn" data-act="amio" data-quick="1">Amiodarone</button><button class="btn" data-act="needle" data-quick="1">Needle decomp<small>Tension?</small></button>
        <button class="btn" data-act="prbc" data-quick="1">Blood<small>H: hypovolemia</small></button></div></div>`;
    }
    const crit = isCrit(p) || p.sev >= 45 || bleedingVisible(p);
    if (!crit) return '';
    return `<div class="resus"><h4>⚡ Emergency kit — act fast</h4><div class="kit">
      <button class="btn" data-act="o2" data-quick="1">O₂ mask</button><button class="btn" data-act="iv" data-quick="1">IV access</button><button class="btn" data-act="io" data-quick="1">IO drill</button>
      <button class="btn danger" data-act="tourniquet">🎗 Tourniquet</button><button class="btn" data-act="pressure" data-quick="1">Pressure dressing</button><button class="btn" data-act="hemogauze" data-quick="1">Hemostatic gauze</button>
      <button class="btn" data-act="fluids" data-quick="1">Fluids 500 mL</button><button class="btn" data-act="prbc" data-quick="1">Blood O-neg</button><button class="btn" data-act="txa" data-quick="1">TXA 1 g</button>
      <button class="btn" data-act="needle" data-quick="1">Needle decomp</button><button class="btn" data-act="epi_im" data-quick="1">Epi IM</button><button class="btn" data-act="monitor" data-quick="1">Monitor</button></div></div>`;
  }
  function tabOv(p, g) {
    let h = resusBar(p);
    h += `<div class="monitor"><canvas id="ecg"></canvas>${p.onMonitor ? '' : ''}${vitalsGrid(p)}</div>`;
    h += `<div class="card"><div class="row sb"><b>"${esc(p.cc)}"</b></div>
      <div class="chips">${allergyChip(p)}<span class="chip">Pain ${Math.round(p.pain)}/10</span><span class="chip">Arrived ${HS.fmtTime(p.t0)}</span><span class="chip">Costs ${HS.money(p.cost)}</span></div>${statusChips(p, g)}</div>`;
    if (p.crisis) h += `<div class="card crit"><b>🚨 ${HS.CRISES[p.crisis.type].label}</b><div class="sub">${esc(p.name)} ${esc(HS.CRISES[p.crisis.type].msg)}. Deadline in ${Math.max(0, HS.CRISES[p.crisis.type].deadline - (g.t - p.crisis.t0))} min.</div>
      <div class="btnrow"><button class="btn sm" data-hint="${p.id}">Show hint</button></div></div>`;
    if (p.tq) h += `<div class="card warn"><b>🎗 Tourniquet on ${esc(p.tq.site)}</b> · ${g.t - p.tq.t} min <div class="sub">Note the time. Ischaemia risk after 2 h. Release only in theatre/under control.</div><div class="btnrow"><button class="btn sm warn" data-rmtq="1">Release tourniquet</button></div></div>`;
    if (p.restrainedAt) h += `<div class="card warn"><b>⛓ Restrained for ${g.t - p.restrainedAt} min</b><div class="sub">Check circulation, sedate if still violent, release when calm.</div><div class="btnrow"><button class="btn sm" data-act="unrestrain" data-quick="1">Release restraints</button></div></div>`;
    h += '<h2 class="sec">Notes</h2>';
    if (!p.notes.length) h += '<div class="sub">No interventions yet.</div>';
    for (const n of p.notes.slice(0, 8)) h += `<div class="note ${n.bad ? 'bad' : ''}"><small>${HS.fmtTime(n.t)}</small> ${esc(n.text)}</div>`;
    return h;
  }

  // ---- history & exam
  function tabHx(p) {
    const asked = p.hxAsked || [];
    const lab = ['What happened?', 'Past history & meds', 'Allergies'];
    let h = '<h2 class="sec">Ask the patient</h2><div class="btnrow">';
    lab.forEach((l, i) => { h += `<button class="btn sm ${asked[i] ? 'dis' : ''}" data-ask="${i}">${l}</button>`; });
    h += '</div>';
    const done = p.hxDone || [];
    for (let i = 0; i < 3; i++) {
      if (done[i] !== undefined) h += `<div class="note"><b>${lab[i]}</b><br>${esc(done[i])}</div>`;
      else if (asked[i]) h += `<div class="note"><b>${lab[i]}</b><br><i class="sub">Asking…</i></div>`;
    }
    h += '<h2 class="sec">Examine</h2><div class="grid2">';
    for (const [k, l] of HS.EXAM_SYSTEMS) {
      const e = p.exam[k];
      h += `<button class="btn ${e && (e.text || e.pending) ? 'dis' : ''}" data-exam="${k}">${l}</button>`;
    }
    h += '</div>';
    for (const [k, l] of HS.EXAM_SYSTEMS) {
      const e = p.exam[k];
      if (e && e.text) h += `<div class="note"><b>${l}</b> <small>${HS.fmtTime(e.t)}</small><br>${esc(e.text)}</div>`;
      else if (e && e.pending) h += `<div class="note"><b>${l}</b><br><i class="sub">Examining…</i></div>`;
    }
    h += '<div class="hint">Findings are a snapshot — re-examine after interventions by tapping Examine again later (re-exam resets after 10 min).</div>';
    return h;
  }

  // ---- tests
  function tabTest(p, g) {
    let h = '';
    const res = Object.entries(p.orders).sort((a, b) => b[1].due - a[1].due);
    if (res.length) {
      h += '<h2 class="sec">Orders & results</h2>';
      for (const [id, o] of res) {
        const T = HS.TESTS[id];
        if (o.done) h += `<div class="note res ${o.abn ? 'abn' : ''}"><b>${T.n}</b> <small>${HS.fmtTime(o.due)}</small>${o.abn ? ' <span class="chip crit">abnormal</span>' : ''}<br>${esc(o.text)}</div>`;
        else h += `<div class="note"><b>${T.n}</b> — pending, ready in ${Math.max(0, o.due - g.t)} min</div>`;
      }
    }
    const groups = {};
    for (const id in HS.TESTS) (groups[HS.TESTS[id].grp] = groups[HS.TESTS[id].grp] || []).push(id);
    for (const grp in groups) {
      h += `<h2 class="sec">${grp}</h2>`;
      for (const id of groups[grp]) {
        const T = HS.TESTS[id], o = p.orders[id];
        const busy = o && !o.done;
        h += `<div class="card"><div class="row"><div class="grow"><b>${T.n}</b><div class="sub">${HS.fmtDur(T.min)} · ${HS.money(T.cost)}</div></div>
          <button class="btn sm ${busy ? 'dis' : 'pri'}" data-order="${id}">${busy ? 'Ordered' : o ? 'Repeat' : 'Order'}</button></div></div>`;
      }
    }
    return h;
  }

  // ---- treat
  function tabTx(p, g) {
    let h = `<div class="hint" style="margin-bottom:8px">Check allergies and vitals first. Drugs need IV/IO unless oral/IM/neb. Some items have limited stock.</div>`;
    for (const [title, ids] of HS.ACTION_GROUPS) {
      h += `<details class="acc" ${title === 'Emergency kit' ? 'open' : ''}><summary>${title}</summary>`;
      for (const id of ids) {
        const a = HS.ACTIONS[id];
        const st = a.stock ? g.supplies[a.stock] : null;
        let label = 'Do';
        if (a.group === 'drug') label = 'Give'; else if (id === 'cpr') label = p.arrest && p.arrest.cpr ? 'Stop' : 'Start'; else if (id === 'o2') label = p.o2 ? 'Off' : 'On';
        h += `<div class="act"><div class="t"><b>${a.name}</b>${st !== null ? `<span class="stock ${st <= 1 ? 'low' : ''}">${st} left</span>` : ''}<div>${esc(a.desc || '')}</div></div>
          <button class="btn sm ${a.group === 'equip' ? 'warn' : 'pri'} ${st === 0 ? 'dis' : ''}" data-act="${id}">${label}</button></div>`;
      }
      h += '</details>';
    }
    return h;
  }

  // ---- disposition
  function tabDispo(p, g) {
    const byCat = {};
    for (const id in HS.CONDS) (byCat[HS.CONDS[id].cat] = byCat[HS.CONDS[id].cat] || []).push(HS.CONDS[id]);
    let sel = '<option value="">— Working diagnosis —</option>';
    for (const cat of Object.keys(byCat).sort()) sel += `<optgroup label="${cat}">${byCat[cat].sort((a, b) => a.name.localeCompare(b.name)).map((c) => `<option value="${c.id}" ${p.dx === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</optgroup>`;
    let h = `<h2 class="sec">Working diagnosis</h2><select id="dxsel">${sel}</select>
      <div class="hint" style="margin:6px 2px">Correct diagnoses earn a bonus and train your accuracy score. There's no hint system — you decide.</div>`;
    h += `<h2 class="sec">Where does this patient go?</h2>
      <div class="grid2"><button class="btn pri" data-dispo="home">🏠 Discharge home</button><button class="btn blue" data-dispo="ward">🛏 Admit to ward<div class="sub">${g.beds.ward.filter((b) => !b.pid).length} free</div></button>
      <button class="btn warn" data-dispo="icu">🫀 Admit to ICU<div class="sub">${g.beds.icu.filter((b) => !b.pid).length} free</div></button><button class="btn" data-dispo="${p.loc === 'er' ? 'er' : 'er'}" ${p.loc === 'er' ? 'disabled' : ''}>↩ Back to ER bay</button></div>`;
    h += '<h2 class="sec">Operating theatre</h2>';
    for (const id in HS.SURGERIES) {
      const S = HS.SURGERIES[id];
      if (S.bed) continue;
      h += `<div class="card"><div class="row"><div class="grow"><b>${esc(S.name)}</b><div class="sub">${esc(S.desc)} · ${S.steps.reduce((a, s) => a + s[2], 0)} min · ${S.cath ? 'cath lab' : HS.ANAES[S.an]}</div></div>
        <button class="btn sm danger" data-surg="${id}">Operate</button></div></div>`;
    }
    h += `<div class="spacer"></div><button class="btn block danger" data-dispo="declare" ${p.arrest ? '' : 'hidden'}>Stop resuscitation — declare death</button>`;
    return h;
  }

  // ------------------------------------------------------------ modals
  U.modal = function (html, full) {
    const m = $('#modal'); m.classList.toggle('full', !!full); m.classList.remove('hidden');
    m.innerHTML = `<div class="box">${html}</div>`;
  };
  U.closeModal = function () { $('#modal').classList.add('hidden'); $('#modal').innerHTML = ''; };

  U.doseModal = function (pid, aid) {
    const p = U.g.patients[pid], a = HS.ACTIONS[aid];
    const doses = HS.dosesFor(p, a);
    const labels = ['Low', 'Standard', 'High'];
    const asked = p.hxDone && p.hxDone[2] !== undefined;
    let warn = '';
    if (a.allergy && asked && p.allergies.includes(a.allergy)) warn = `<div class="note bad"><b>⚠ Patient allergy: ${a.allergy.toUpperCase()}</b></div>`;
    else if (!asked) warn = '<div class="note"><b>Allergies not yet asked.</b></div>';
    U.modal(`<h3>${esc(a.name)}</h3><div class="sub">${esc(a.desc)}</div>${warn}
      <div class="sub" style="margin:6px 0">${esc(p.name)}, ${p.age}${p.sex}, ${p.wt} kg${p.peds ? ' (child — weight-based doses)' : ''} · Route: ${a.route.toUpperCase()}</div>
      ${doses.map((d, i) => `<button class="btn block ${i === a.stdIdx ? 'pri' : ''}" style="margin-bottom:6px" data-dose="${pid}:${aid}:${i}:${d} ${a.unit}">${labels[i]} — ${d} ${a.unit}</button>`).join('')}
      <button class="btn block" data-closemodal="1">Cancel</button>`);
  };
  U.sitesModal = function (pid) {
    const p = U.g.patients[pid];
    U.modal(`<h3>🎗 Apply tourniquet</h3><div class="sub">High and tight, 5–7 cm above the wound, on the correct limb. Tighten until bleeding stops. Stock left: ${U.g.supplies.tourniquet}.</div>
      <div class="grid2" style="margin-top:10px">${['left arm', 'right arm', 'left thigh', 'right thigh'].map((s) => `<button class="btn warn" data-site="${pid}:${s}">${s}</button>`).join('')}</div>
      <div class="spacer"></div><button class="btn block" data-closemodal="1">Cancel</button>`);
  };

  // ------------------------------------------------------------ actions
  U.doAct = function (pid, aid, o = {}) {
    const g = U.g, p = g.patients[pid], a = HS.ACTIONS[aid];
    if (!p || !a) return;
    if (aid === 'tourniquet' && !o.site) return U.sitesModal(pid);
    if (a.doses && o.idx === undefined && !o.quick) return U.doseModal(pid, aid);
    if (a.doses && o.idx === undefined) { o.idx = a.stdIdx; o.dose = HS.dosesFor(p, a)[a.stdIdx] + ' ' + a.unit; }
    const r = HS.act(g, pid, aid, o);
    if (r.minigame) return HS.startProcedure(pid, aid, r.minigame);
    if (!r.ok || !r.pending) U.toast(r.msg, r.bad || !r.ok ? 'crit' : '', pid);
    else if (r.pending && U.speed === 0) U.toast(r.msg, '', pid);
    U.refresh();
  };

  U.refresh = function () {
    U.renderTop(); U.renderTabs(); U.renderAlerts(); U.renderView();
    if (U.sheetOpen()) U.renderSheet(false);
  };

  // live tick-time light update (called each game tick)
  U.tickUpdate = function () {
    U.renderTop(); U.renderAlerts();
    const refreshSheet = U.drainEvents();
    if (U.g.t % 2 === 0 || refreshSheet) { U.renderTabs(); if (!U.sheetOpen()) U.renderView(); }
    if (U.sheetOpen()) {
      const p = U.g.patients[U.pid];
      if (p && U.ptab === 'ov' && !refreshSheet && U.g.t % 1 === 0) {
        // update only the monitor numbers without destroying the canvas
        const vg = $('.vgrid'); if (vg) { const tmp = document.createElement('div'); tmp.innerHTML = vitalsGrid(p); const nv = tmp.querySelector('.vgrid'); if (nv) vg.innerHTML = nv.innerHTML; const st = $('.stale'); if (st) st.remove(); const ns = tmp.querySelector('.stale'); if (ns) vg.parentNode.appendChild(ns); }
        if (U.g.t % 3 === 0) U.renderSheet(false);
      } else if (refreshSheet || U.g.t % 4 === 0) U.renderSheet(false);
    }
  };

  // ecg animation
  U.animate = function (now) {
    if (U.ecg && U.pid) {
      const p = U.g.patients[U.pid];
      if (p && p.onMonitor && !p.dead) {
        let rh = 'NSR';
        const ecg = p.condDef.ecg;
        if (p.arrest) rh = p.arrest.rhythm;
        else if (ecg === 'svt' && p.v.hr > 120) rh = 'SVT';
        else if (ecg === 'af') rh = 'AF';
        U.ecg.frame(now, { rhythm: rh, hr: p.v.hr, cpr: p.arrest && p.arrest.cpr, bad: p.v.spo2 < 90 || p.v.sbp < 80 });
      } else if (p && !p.onMonitor) {
        const cv = $('#ecg'); if (cv) { const c = cv.getContext('2d'); const W = cv.clientWidth, H = cv.clientHeight; cv.width = W; cv.height = H; c.fillStyle = '#5b7488'; c.font = '14px system-ui'; c.fillText('NO MONITOR — place patient on cardiac monitor', 12, H / 2); }
      }
    }
  };

  // ------------------------------------------------------------ delegated clicks
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-open],[data-tab],[data-speed],[data-ptab],[data-act],[data-close],[data-bring],[data-hold],[data-order],[data-ask],[data-exam],[data-dose],[data-site],[data-closemodal],[data-restock],[data-dispo],[data-surg],[data-rmtq],[data-hint],[data-menu]');
    if (!t || !U.g) return;
    const g = U.g, ds = t.dataset;
    if (ds.open) { if (e.target.closest('[data-hold],[data-bring]')) return; return U.open(+ds.open); }
    if (ds.tab) { U.tab = ds.tab; U.refresh(); return; }
    if (ds.speed !== undefined) return U.setSpeed(+ds.speed);
    if (ds.ptab) { U.ptab = ds.ptab; U.renderSheet(true); return; }
    if (ds.close) return U.closeSheet();
    if (ds.closemodal) return U.closeModal();
    if (ds.menu) return HS.menu();
    if (ds.act) { if (!U.pid) return; return U.doAct(U.pid, ds.act, ds.quick ? { quick: true } : {}); }
    if (ds.bring) {
      const p = g.patients[ds.bring]; const r = HS.place(g, p.id, 'er');
      if (!r.ok) U.toast('ER is full — discharge or admit someone to free a bay.', 'warn'); else { U.toast(r.msg); U.open(p.id); }
      return U.refresh();
    }
    if (ds.hold) {
      const [id, kind] = ds.hold.split(':'); const p = g.patients[id];
      const bed = g.beds.er.find((b) => !b.pid && (kind === 'resus' ? b.resus : !b.resus)) || g.beds.er.find((b) => !b.pid);
      if (!bed) U.toast('No free bays to hold.', 'warn'); else { const r = HS.reserveBed(g, +id, bed.id); U.toast(r.msg, 'good'); }
      return U.refresh();
    }
    if (ds.order) { const r = HS.orderTest(g, U.pid, ds.order); U.toast(r.msg || 'Failed', r.ok ? '' : 'warn'); return U.renderSheet(false); }
    if (ds.ask !== undefined) { const r = HS.askHistory(g, U.pid, +ds.ask); if (!r.ok && r.msg) U.toast(r.msg, 'warn'); return U.renderSheet(false); }
    if (ds.exam) { const p = g.patients[U.pid]; const e0 = p.exam[ds.exam]; if (e0 && e0.text && g.t - e0.t < 10) return; p.exam[ds.exam] = null; const r = HS.examine(g, U.pid, ds.exam); return U.renderSheet(false); }
    if (ds.dose) { const [pid, aid, idx, dose] = ds.dose.split(':'); U.closeModal(); return U.doAct(+pid, aid, { idx: +idx, dose }); }
    if (ds.site) { const [pid, ...rest] = ds.site.split(':'); U.closeModal(); return U.doAct(+pid, 'tourniquet', { site: rest.join(':') }); }
    if (ds.restock) { const [k, n] = ds.restock.split(':'); const r = HS.restock(g, k, +n); U.toast(r.msg, r.ok ? 'good' : 'warn'); return U.refresh(); }
    if (ds.rmtq) { const r = HS.removeTourniquet(g, U.pid); U.toast(r.msg, 'warn'); return U.renderSheet(false); }
    if (ds.hint) { const p = g.patients[+ds.hint]; if (p && p.crisis) U.toast('Hint: ' + HS.CRISES[p.crisis.type].hint, 'good'); return; }
    if (ds.dispo) return U.dispo(ds.dispo);
    if (ds.surg) return HS.openSurgery(U.pid, ds.surg);
  });
  document.addEventListener('change', (e) => {
    if (e.target.id === 'dxsel' && U.pid) HS.setDx(U.g, U.pid, e.target.value || null);
  });

  U.dispo = function (kind) {
    const g = U.g, p = g.patients[U.pid];
    if (!p) return;
    if (kind === 'declare') { HS.die(g, p, 'Resuscitation stopped — declared dead', false); U.closeSheet(); return; }
    if (kind === 'er') { const r = HS.place(g, p.id, 'er'); U.toast(r.msg, r.ok ? '' : 'warn'); return U.refresh(); }
    if (kind === 'home') {
      const s = HS.shown(p);
      const bad = p.arrest || (s && (s.sbp < 90 || s.spo2 < 92 || s.hr > 130));
      const go = () => {
        const r = HS.discharge(g, p.id);
        U.closeModal(); U.toast(r.msg, r.outcome === 'good' ? 'good' : r.outcome === 'meh' ? 'warn' : 'crit');
        U.closeSheet();
      };
      U.dischargeGo = go;
      U.modal(`<h3>Discharge ${esc(p.name)} home?</h3><div class="sub">${bad ? '⚠ Vitals are currently abnormal. ' : ''}Prescriptions given so far will go with the patient. Make sure they are safe to leave.</div>
        <div class="btnrow"><button class="btn danger grow" data-confirm="1">Discharge</button><button class="btn grow" data-closemodal="1">Cancel</button></div>`);
      return;
    }
    const r = HS.admit(g, p.id, kind);
    U.toast(r.msg, r.ok ? 'good' : 'warn');
    if (r.ok) U.closeSheet(); else U.refresh();
  };
  document.addEventListener('click', (e) => { if (e.target.closest('[data-confirm]') && U.dischargeGo) { const f = U.dischargeGo; U.dischargeGo = null; f(); } });
})(typeof globalThis !== 'undefined' ? globalThis : window);
