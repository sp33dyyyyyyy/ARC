/* Mercy General ER — simulation engine (no DOM). One game minute per tick. */
(function (G) {
  const HS = G.HS;
  const { rand, ri, rf, pick, chance, clamp } = HS;
  const PAY = 0.3; // reimbursement scale (keeps money meaningful)
  const OVERHEAD_PER_MIN = 4.2; // staff + running costs

  // ---------------------------------------------------------------- new game
  HS.newGame = function (opts = {}) {
    const diff = opts.diff || 1;
    const g = {
      v: 2, t: HS.DAY0_START, diff, patients: {}, nextId: 1, inbound: [], events: [], log: [],
      funds: 25000, rep: 70, supplies: {}, lastCrisis: -999, lastMci: 0,
      stats: { seen: 0, home: 0, admitted: 0, surgeries: 0, surgOk: 0, saved: 0, died: 0, crises: 0, crisesOk: 0, lwbs: 0, sued: 0, dxOk: 0, dxN: 0, earned: 0, spent: 0 },
      beds: { er: [], ward: [], icu: [], or: [] }, over: false,
    };
    ['R1', 'R2'].forEach((id) => g.beds.er.push({ id, resus: true, pid: null }));
    ['B1', 'B2', 'B3', 'B4', 'B5', 'B6'].forEach((id) => g.beds.er.push({ id, pid: null }));
    for (let i = 1; i <= 10; i++) g.beds.ward.push({ id: 'W' + i, pid: null });
    for (let i = 1; i <= 3; i++) g.beds.icu.push({ id: 'ICU' + i, pid: null });
    g.beds.or.push({ id: 'OR1', pid: null }, { id: 'OR2', pid: null }, { id: 'CATH', pid: null, cath: true });
    for (const k in HS.SUPPLIES) g.supplies[k] = HS.SUPPLIES[k].start;
    log(g, 'Shift started. Welcome to Mercy General.');
    // opening patients so the board is not empty
    spawn(g, { amb: false, quiet: true });
    spawn(g, { amb: false, quiet: true });
    return g;
  };

  function log(g, text, lvl = '') { g.log.unshift({ t: g.t, text, lvl }); if (g.log.length > 300) g.log.length = 300; }
  HS.log = log;
  function ev(g, k, text, pid, lvl) { g.events.push({ k, text, pid, lvl: lvl || '', t: g.t }); }
  const P = (g, id) => g.patients[id];
  HS.P = P;

  // ---------------------------------------------------------------- patients
  function bedOf(g, p) {
    for (const kind of ['er', 'ward', 'icu', 'or']) for (const b of g.beds[kind]) if (b.pid === p.id) return { kind, bed: b };
    return null;
  }
  HS.bedOf = bedOf;

  function pickCond(g, amb) {
    const h = HS.hourOf(g.t);
    const night = h >= 20 || h < 4;
    const pool = Object.values(HS.CONDS).filter((c) => (amb ? c.arr !== 'walk' : c.arr !== 'amb'));
    return HS.wpick(pool, (c) => {
      let w = c.w;
      if (c.cat === 'Trauma' && night) w *= 1.5;
      if (c.id === 'agitation' && night) w *= 2;
      return w;
    });
  }

  function spawn(g, o = {}) {
    const amb = o.amb !== undefined ? o.amb : chance(0.34);
    const cond = o.cond ? HS.CONDS[o.cond] : pickCond(g, amb);
    const p = makePatient(g, cond, amb);
    if (o.sevAdd) p.sev = clamp(p.sev + o.sevAdd, 1, 96);
    if (o.bounce) { p.bounce = true; p.name = o.bounce.name; p.age = o.bounce.age; p.sex = o.bounce.sex; p.allergies = o.bounce.allergies; }
    g.patients[p.id] = p;
    if (amb && !o.quiet) {
      p.loc = 'inbound';
      p.eta = ri(3, 6);
      g.inbound.push(p.id);
      ev(g, 'inbound', `AMBULANCE inbound: ${handover(p)} ETA ${p.eta} min`, p.id, p.crit ? 'crit' : 'warn');
    } else {
      p.loc = 'waiting';
      p.t0 = g.t;
      ev(g, 'walkin', `${p.name} (${p.age}${p.sex}) walks in: "${p.cc}"`, p.id, '');
    }
    return p;
  }
  HS.spawn = spawn;

  function handover(p) {
    const c = p.condDef;
    let s = `${p.age}${p.sex} — ${p.cc}.`;
    const sc = [];
    if (p.dev.tourniquet) sc.push('tourniquet applied');
    if (p.iv) sc.push('IV in situ');
    if (p.o2) sc.push('on O2');
    if (p.dev.collar) sc.push('C-spine immobilised');
    if (p.dev.chestseal) sc.push('chest seal on');
    if (p.arrest) sc.push('CPR in progress');
    s += ' Pre-hospital vitals HR ' + Math.round(p.v.hr) + ', BP ' + Math.round(p.v.sbp) + '/' + Math.round(p.v.dbp) + ', SpO2 ' + Math.round(p.v.spo2) + '%, GCS ' + Math.round(p.v.gcs) + '.';
    if (sc.length) s += ' Medics: ' + sc.join(', ') + '.';
    return s;
  }
  HS.handover = handover;

  function makePatient(g, c, amb) {
    const sex = c.sex === 'any' ? (chance(0.5) ? 'M' : 'F') : c.sex;
    let age = ri(c.age[0], c.age[1]);
    const peds = age < 16;
    const wt = peds ? Math.round(age * 3 + 8) : Math.round(sex === 'M' ? rf(68, 105, 0) : rf(52, 88, 0));
    const p = {
      id: g.nextId++, cond: c.id, condDef: null, name: HS.makeName(sex), age, sex, wt, amb,
      peds, allergies: [], pmh: [], loc: 'waiting', t0: g.t, sev: ri(c.sev[0], c.sev[1]), floorOn: false,
      base: {
        hr: peds ? ri(85, 115) : ri(60, 84), sbp: peds ? ri(92, 108) : ri(108, 132) + (age > 60 ? 8 : 0), dbp: ri(64, 82), rr: peds ? ri(20, 26) : ri(13, 17),
        spo2: ri(96, 99), temp: rf(36.5, 37.1), gcs: 15,
      },
      v: {}, seen: null, onMonitor: false, iv: false, io: false, o2: false, tags: {}, given: [], pending: [], orders: {}, exam: {}, hx: 0, notes: [], dev: {},
      pain: c.pain, agit: c.agit || 0, sedUntil: 0, restrainedAt: null, tq: null, bleed: null, blood: 0, restored: 0, fluidFx: [], fluidsMl: 0, bloodUnits: 0, bleedMul: 1, bleedMulUntil: 0,
      crisis: null, arrest: null, dead: false, cured: false, recov: 0, dx: null, esi: 3, tensionPtx: !!c.tensionPtx, unconscious: !!c.unconscious,
      cc: pick(c.cc), cost: 0, doneAt: null, crit: !!c.crit, preventable: false, stats: { minWaiting: 0 }, airwayClear: true,
    };
    p.condDef = c;
    if (c.id === 'choking') p.airwayClear = false;
    p.volume = (peds ? 80 : 70) * wt;
    // allergies / history
    if (chance(0.22)) p.allergies.push(pick(['penicillin', 'opioid', 'nsaid', 'sulfa']));
    if (c.id === 'copd' || c.id === 'sepsis') { if (!p.allergies.includes('penicillin') && chance(0.7)) p.allergies = ['penicillin']; }
    if (c.id === 'dka') p.allergies = ['sulfa'];
    if (c.id === 'asthma') p.pmh.push('asthma');
    if (c.id === 'copd') p.pmh.push('copd');
    if (c.id === 'dka' || c.id === 'hypoglyc' || c.id === 'sepsis') p.pmh.push('diabetes');
    if (chance(0.12) && !p.pmh.includes('diabetes')) p.pmh.push('diabetes');
    p.hxLines = buildHistory(p);
    // bleeding
    if (c.bleed) {
      let site = 'torso';
      const k = c.bleed.kind;
      if (k === 'limb') site = pick(['left arm', 'right arm', 'left thigh', 'right thigh']);
      if (k === 'scalp') site = 'right palm';
      if (k === 'pelvis') site = 'pelvis';
      if (k === 'internal_thigh') site = 'right thigh';
      p.bleed = { kind: k, site, rate0: rf(c.bleed.rate[0], c.bleed.rate[1]), stopped: false, minor: !!c.bleed.minor };
    }
    // results pre-rolled
    p.results = {};
    for (const id in HS.TESTS) {
      const T = HS.TESTS[id];
      const ct = c.tests[id];
      let text = T.norm, abn = 0;
      if (ct) {
        const raw = typeof ct[0] === 'function' ? ct[0]() : ct[0];
        if (raw && raw !== 'n/a') { text = raw; abn = ct[1]; }
      }
      if (id === 'hcg' && sex === 'M') text = 'N/A (male)';
      p.results[id] = { text, abn };
    }
    // pre-roll: first troponin can be falsely negative in early MI
    if (c.id === 'mi' && chance(0.3)) p.results.troponin = { text: '0.02 ng/mL (borderline) — consider repeating in 3 h', abn: 0, early: true };
    // initial physiology
    computeVitals(g, p);
    // paramedic interventions
    if (amb && c.scene) {
      const s = c.scene;
      if (s.tourniquet && p.bleed && p.bleed.kind === 'limb' && chance(s.tourniquet)) applyTourniquet(g, p, p.bleed.site, true);
      if (s.iv && chance(s.iv)) p.iv = true;
      if (s.o2 && chance(s.o2)) p.o2 = true;
      if (s.collar && chance(s.collar)) p.dev.collar = true;
      if (s.chestseal && chance(s.chestseal) && c.id === 'gsw_chest') p.dev.chestseal = true;
    }
    if (c.arrestOnArrival) { startArrest(g, p, c.arrestOnArrival, 'cardiac'); p.arrest.cpr = true; p.arrest.t0 = g.t - 4; p.onMonitor = true; p.arrest.ongoingCpr = true; }
    computeVitals(g, p);
    p.seen = Object.assign({ t: g.t }, p.v);
    p.esi = triage(p);
    return p;
  }

  function buildHistory(p) {
    const c = p.condDef;
    const lines = [];
    lines.push(c.hx[0] || 'No detailed history.');
    const pm = (c.hx[1] || '').replace(/Allergic to [^.]*\.?/i, '').trim();
    lines.push((pm || 'No significant past history.') + (p.pmh.length ? ' (PMH also: ' + p.pmh.join(', ') + '.)' : ''));
    lines.push(p.allergies.length ? 'Allergies: ' + p.allergies.join(', ').toUpperCase() + '.' : 'No known drug allergies.');
    return lines;
  }

  function triage(p) {
    const s = p.sev;
    let e = p.arrest || p.crit && s >= 55 || s >= 78 ? 1 : s >= 50 ? 2 : s >= 30 ? 3 : s >= 15 ? 4 : 5;
    if (chance(0.15)) e = clamp(e + pick([-1, 1]), 1, 5);
    return e;
  }

  // ---------------------------------------------------------------- needs & severity
  const has = (p, tag) => !!p.tags[tag];
  function tagSat(p, tag) {
    const T = p.tags;
    switch (tag) {
      case 'analgesia': return !!T.analgesia;
      case 'analgesia_mild': return !!(T.analgesia_mild || T.analgesia);
      case 'iv_access': return p.iv || p.io;
      case 'o2': return p.o2 || !!T.airway || p.v.spo2 >= 95 || (p.cond === 'burn' && p.o2);
      case 'fluids': return p.fluidsMl >= 500 || p.bloodUnits >= 2;
      case 'blood': return effLossFrac(p) < 0.12;
      case 'bleed_control': return !p.bleed || p.bleed.stopped || bleedRate(p) < p.bleed.rate0 * 0.15 || p.cured;
      case 'epi': return !!T.epi;
      case 'abx': return !!(T.abx || T.abx_broad);
      case 'abx_anaer': return !!(T.abx_anaer || T.abx_broad);
      case 'decompress': return !!(T.decompress);
      case 'svt_fix': return !!(T.adenosine && p.condDef.id === 'svt' && T._svtOk) || !!T.cardiovert_ok;
      case 'rosc': return !!T.rosc;
      case 'clear_airway': return p.airwayClear;
      case 'bvm_or_o2': return !!(T.bvm || T.airway);
      case 'pressor_if_low': return !!(T.pressor || p.v.sbp >= 100);
      case 'restraint': return !!(p.tags.restraint || p.tags.sedation);
      case 'sedation': return !!p.tags.sedation;
      case 'cool': return !!T.cool;
      case 'warm': return !!T.warm;
      case 'thrombolytic': return !!T.thrombolytic && p.cond === 'stroke';
      case 'collar': return !!p.dev.collar;
      case 'binder': return !!p.dev.binder;
      case 'splint': return !!p.dev.splint;
      case 'chestseal': return !!p.dev.chestseal || !!T.chesttube;
      case 'chesttube': return !!T.chesttube;
      case 'ngt': return !!T.ngt;
      case 'sutured': return !!T.sutured;
      case 'reduced': return !!T.reduced;
      case 'pressure': return !!(p.dev.pressure || T.sutured);
      case 'txa': return !!T.txa;
      case 'abx_mrsa': return !!T.abx_mrsa;
      default: return !!T[tag];
    }
  }
  HS.tagSat = tagSat;
  function needsMet(p) {
    const n = p.condDef.need;
    if (!n.length) return 1;
    let ok = 0;
    for (const t of n) if (tagSat(p, t)) ok++;
    return ok / n.length;
  }
  HS.needsMet = needsMet;

  function effLossFrac(p) {
    let fx = 0;
    for (const f of p.fluidFx) fx += f.amt;
    return Math.max(0, p.blood - p.restored - fx) / p.volume;
  }
  function bleedRate(p) {
    const b = p.bleed;
    if (!b || b.stopped || p.cured) return 0;
    let ctl = 0;
    const d = p.dev, T = p.tags;
    if (b.kind === 'limb') {
      if (p.tq && sameLimb(p.tq.site, b.site)) ctl = 0.97;
      ctl = Math.max(ctl, d.pressure ? 0.5 : 0, d.packing ? 0.78 : 0);
    } else if (b.kind === 'scalp') ctl = Math.max(d.pressure ? 0.9 : 0, T.sutured ? 1 : 0);
    else if (b.kind === 'pelvis') ctl = Math.max(d.binder ? 0.55 : 0, d.packing ? 0.1 : 0);
    else if (b.kind === 'internal_thigh') ctl = d.splint ? 0.55 : 0;
    else if (b.kind === 'torso') ctl = T.chesttube && p.cond === 'gsw_chest' ? 0.3 : 0;
    if (T.txa) ctl = ctl + (1 - ctl) * 0.25;
    let r = b.rate0 * (1 - ctl) * (g_mulNow(p));
    // clotting / low-pressure slows flow
    r *= clamp((p.v.sbp || 100) / 105, 0.35, 1);
    if (p.loc === 'or') r *= 0.3;
    return r;
  }
  function g_mulNow(p) { return p.bleedMulUntil > (HS._now || 0) ? p.bleedMul : 1; }
  const sameLimb = (a, b) => {
    const side = (s) => (s.includes('left') ? 'L' : 'R');
    const part = (s) => (s.includes('arm') ? 'arm' : 'leg');
    const pa = a.includes('thigh') || a.includes('leg') ? 'leg' : 'arm';
    const pb = b.includes('thigh') || b.includes('leg') ? 'leg' : 'arm';
    return side(a) === side(b) && pa === pb;
  };
  HS.bleedRate = bleedRate;
  HS.effLossFrac = effLossFrac;

  function sevEff(p) { return Math.max(p.sev, effLossFrac(p) * 215); }
  HS.sevEff = sevEff;

  // ---------------------------------------------------------------- vitals
  function computeVitals(g, p) {
    const c = p.condDef, b = p.base, pr = c.vit || {};
    const s = clamp(p.sev, 0, 100) / 100;
    const f = effLossFrac(p);
    const v = {
      hr: b.hr + (pr.hr || 0) * s, sbp: b.sbp + (pr.sbp || 0) * s, rr: b.rr + (pr.rr || 0) * s,
      spo2: b.spo2 + (pr.spo2 || 0) * s, temp: b.temp + (pr.temp || 0) * s, gcs: b.gcs + (pr.gcs || 0) * s,
    };
    if (p.cured) { v.hr = b.hr + (v.hr - b.hr) * 0.6; }
    // hemorrhage
    v.hr += 260 * f; v.sbp -= 360 * Math.max(0, f - 0.07); v.rr += 70 * f; v.gcs -= 28 * Math.max(0, f - 0.25);
    // pain
    v.hr += p.pain * 1.4;
    if (p.agit > 40 && !(p.sedUntil > 0)) { v.hr += 20; v.sbp += 15; }
    // tension pneumothorax
    if (p.tensionPtx) { v.spo2 -= 15; v.sbp -= 30; v.hr += 25; v.rr += 10; }
    // oxygen / airway support
    if (p.o2 && v.spo2 < 99) v.spo2 = Math.min(99, v.spo2 + (c.id === 'copd' ? 3 : 6));
    if (p.tags.airway && v.spo2 < 98) v.spo2 = Math.min(98, v.spo2 + 8);
    if (!p.airwayClear) { v.spo2 -= 30; v.gcs -= 3; }
    // sedation/opioid
    if (p.sedUntil > 0) { v.rr -= 3; v.gcs = Math.min(v.gcs, 13); }
    if (p.respDep > 0) { v.rr -= p.respDep; v.spo2 -= p.respDep * 1.2; }
    // fluids and pressors
    if (p.tags.pressor && p.tags.pressor.t > g.t - 180) v.sbp += 22;
    // crisis
    if (p.crisis) {
      const cr = HS.CRISES[p.crisis.type];
      const prog = clamp((g.t - p.crisis.t0) / cr.deadline, 0, 1.2);
      for (const k in cr.vit) v[k] = (v[k] || 0) + cr.vit[k] * (0.4 + 0.6 * prog);
    }
    // arrest
    if (p.arrest) {
      const a = p.arrest;
      if (a.rhythm === 'VF') { v.hr = 0; v.sbp = 0; v.dbp = 0; v.spo2 = Math.min(v.spo2, 62); v.rr = 0; }
      else { v.hr = a.rhythm === 'PEA' ? 40 : 0; v.sbp = 0; v.dbp = 0; v.spo2 = Math.min(v.spo2, 55); v.rr = 0; }
      v.gcs = 3;
    }
    v.dbp = Math.max(0, v.sbp * 0.62);
    v.hr = clamp(v.hr + (p.arrest ? 0 : rf(-2, 2)), 0, 220);
    v.sbp = clamp(v.sbp + (p.arrest ? 0 : rf(-2, 2)), 0, 250);
    v.dbp = clamp(v.dbp, 0, 150);
    v.rr = clamp(v.rr, 0, 50);
    v.spo2 = clamp(v.spo2 + rf(-0.6, 0.6), 30, 100);
    v.temp = clamp(v.temp, 28, 42.5);
    v.gcs = clamp(Math.round(v.gcs), 3, 15);
    if (p.unconscious && !p.arrest) v.gcs = Math.min(v.gcs, 9);
    p.v = v;
  }
  HS.computeVitals = computeVitals;

  HS.shown = function (p) {
    return p.onMonitor ? Object.assign({ t: null }, p.v) : p.seen;
  };
  HS.vitalFlag = function (v) {
    const f = {};
    f.hr = v.hr < 50 || v.hr > 120 ? 2 : v.hr > 100 || v.hr < 55 ? 1 : 0;
    f.sbp = v.sbp < 90 || v.sbp > 190 ? 2 : v.sbp < 100 || v.sbp > 160 ? 1 : 0;
    f.spo2 = v.spo2 < 90 ? 2 : v.spo2 < 94 ? 1 : 0;
    f.rr = v.rr < 8 || v.rr > 28 ? 2 : v.rr > 20 || v.rr < 11 ? 1 : 0;
    f.temp = v.temp > 39.5 || v.temp < 34.5 ? 2 : v.temp > 38 || v.temp < 36 ? 1 : 0;
    f.gcs = v.gcs <= 8 ? 2 : v.gcs < 15 ? 1 : 0;
    return f;
  };

  // ---------------------------------------------------------------- crises
  HS.CRISES = {
    anaphylaxis: { label: 'ANAPHYLAXIS', msg: 'sudden hives, lip swelling, wheeze and collapsing BP', deadline: 12, groups: [['epi']], vit: { sbp: -55, spo2: -14, hr: 45, rr: 14 },
      w: (p) => (p.allergies.length ? 3 : 0.6), hint: 'Epinephrine IM, then fluids + O2' },
    seizure: { label: 'SEIZURE', msg: 'is having a generalised tonic-clonic seizure', deadline: 14, groups: [['anticonvulsant']], vit: { hr: 30, spo2: -12, gcs: -8 },
      w: (p) => (p.cond === 'seizure' || p.cond === 'eclampsia' ? 4 : 0.7), hint: 'Lorazepam / midazolam; protect airway' },
    airway: { label: 'AIRWAY OBSTRUCTION', msg: 'is vomiting and the airway is blocked, SpO2 falling', deadline: 7, groups: [['suction', 'jaw', 'bvm', 'airway']], vit: { spo2: -32, hr: 30, gcs: -4 },
      w: (p) => (p.unconscious || p.sedUntil > 0 || p.condDef.id === 'stroke' || p.condDef.id === 'hem_stroke' ? 3 : 0.5), hint: 'Suction, jaw thrust, BVM or intubate' },
    tension: { label: 'TENSION PNEUMOTHORAX', msg: 'suddenly short of breath, trachea shifting, BP falling', deadline: 9, groups: [['decompress']], vit: { spo2: -22, sbp: -40, hr: 35, rr: 14 }, setFlag: 'tensionPtx',
      w: (p) => (p.cond === 'ptx' || p.cond === 'open_chest' ? 3 : p.tags.airway ? 1.2 : 0), hint: 'Needle decompression NOW' },
    hemorrhage: { label: 'RE-BLEED', msg: 'is bleeding heavily again — dressing soaked through', deadline: 15, groups: [['tourniquet', 'pressure', 'packing', 'binder', 'surgery'], ['blood', 'fluids']], vit: { sbp: -35, hr: 40 },
      w: (p) => (p.bleed && !p.bleed.stopped && p.bleed.kind !== 'scalp' ? 3.5 : 0), setBleed: true, hint: 'Control the bleed, then volume' },
    hypoglycemia: { label: 'HYPOGLYCEMIA', msg: 'is sweaty and unrousable — glucose very low', deadline: 20, groups: [['dextrose']], vit: { hr: 30, gcs: -8 },
      w: (p) => (p.pmh.includes('diabetes') ? 3 : 0), hint: 'IV dextrose' },
    violence: { label: 'VIOLENT PATIENT', msg: 'is lashing out at staff and tearing at lines', deadline: 10, groups: [['restraint'], ['sedation']], vit: { hr: 30, sbp: 25 },
      w: (p) => (p.cond === 'agitation' || p.cond === 'hypoglyc' || p.cond === 'seizure' ? 4 : 0.2), hint: 'Restraints + sedation (midazolam / haloperidol)' },
    septic_crash: { label: 'SEPTIC SHOCK', msg: 'BP crashing, mottled and confused', deadline: 28, groups: [['fluids'], ['pressor', 'abx']], vit: { sbp: -45, hr: 40, gcs: -4 },
      w: (p) => (['sepsis', 'pneumonia', 'pyelo', 'septic_joint', 'abscess'].includes(p.cond) ? 3 : 0), hint: 'Fluids, antibiotics, then norepinephrine' },
  };

  function crisisSatisfied(g, p) {
    const cr = p.crisis;
    return HS.CRISES[cr.type].groups.every((grp) => grp.some((tag) => {
      if (tag === 'surgery') return p.cured;
      const t = p.tags[tag];
      return t && t.t >= cr.t0;
    }));
  }

  function startCrisis(g, p, type, force) {
    const def = HS.CRISES[type];
    p.crisis = { type, t0: g.t };
    if (def.setFlag) p[def.setFlag] = true;
    if (type === 'airway') p.airwayClear = false;
    if (def.setBleed && p.bleed) { p.bleed.stopped = false; p.bleedMul = 2; p.bleedMulUntil = g.t + 20; if (p.bleed.rate0 < 40) p.bleed.rate0 = 50; }
    g.lastCrisis = g.t;
    g.stats.crises++;
    p.onMonitor = true;
    ev(g, 'crisis', `CODE — ${def.label}: ${p.name} ${def.msg}`, p.id, 'crit');
    log(g, `${def.label}: ${p.name}`, 'crit');
  }
  HS.startCrisis = startCrisis;

  function rollRandomCrisis(g) {
    if (g.t - g.lastCrisis < 200) return;
    const prob = 0.09 * g.diff;
    if (!chance(prob)) return;
    // pick a patient in-department and a crisis type that fits
    const cand = [];
    for (const id in g.patients) {
      const p = g.patients[id];
      if (p.dead || p.crisis || p.arrest || p.loc === 'gone' || p.loc === 'inbound' || p.loc === 'or') continue;
      if (p.loc === 'waiting' && chance(0.7)) continue;
      for (const type in HS.CRISES) {
        const w = HS.CRISES[type].w(p);
        if (w > 0) cand.push({ p, type, w });
      }
    }
    if (!cand.length) return;
    const pickd = HS.wpick(cand, (c) => c.w);
    startCrisis(g, pickd.p, pickd.type);
  }

  // ---------------------------------------------------------------- arrest
  const CAUSE_FIX = { hypovolemia: ['blood', 'fluids', 'tourniquet', 'pressure', 'packing'], tension: ['decompress'], hypoxia: ['airway', 'bvm'], opioid: ['naloxone'], hypoglycemia: ['dextrose'], anaphylaxis: ['epi'], cardiac: [], other: [] };
  function startArrest(g, p, rhythm, cause) {
    if (p.arrest || p.dead) return;
    p.arrest = { rhythm, t0: g.t, cpr: false, noFlow: 0, shocks: 0, epi: 0, amio: 0, cause, causeFixed: false, lastEpi: -99, wrongShocks: 0 };
    p.crisis = null;
    p.onMonitor = true;
    p.unconscious = true;
    computeVitals(g, p);
    ev(g, 'arrest', `CARDIAC ARREST — ${p.name} (${rhythm}). Start CPR!`, p.id, 'crit');
    log(g, `Cardiac arrest: ${p.name} (${rhythm})`, 'crit');
  }
  function arrestRhythmFor(p) {
    const id = p.cond;
    if (['mi', 'arrest_vf', 'chf', 'svt', 'pe_dummy'].includes(id)) return 'VF';
    if (['aaa', 'splenic', 'polytrauma', 'limb_bleed', 'mangled', 'ectopic', 'pph', 'gsw_chest', 'sepsis', 'pe'].includes(id)) return 'PEA';
    return chance(0.5) ? 'PEA' : 'ASYS';
  }
  function arrestCause(p) {
    if (effLossFrac(p) > 0.25) return 'hypovolemia';
    if (p.tensionPtx) return 'tension';
    if (['opioid_od'].includes(p.cond)) return 'opioid';
    if (['asthma', 'choking', 'copd', 'anaphylaxis'].includes(p.cond)) return p.cond === 'anaphylaxis' ? 'anaphylaxis' : 'hypoxia';
    if (p.cond === 'hypoglyc') return 'hypoglycemia';
    return 'cardiac';
  }
  function tickArrest(g, p) {
    const a = p.arrest;
    if (a.cpr) a.noFlow = 0; else a.noFlow++;
    const dur = g.t - a.t0;
    if (!a.causeFixed) {
      const fixes = CAUSE_FIX[a.cause] || [];
      if (fixes.some((tg) => p.tags[tg] && p.tags[tg].t >= a.t0)) a.causeFixed = true;
    }
    if (a.noFlow >= 5) return die(g, p, 'Cardiac arrest — no compressions', true);
    if (dur > 40) return die(g, p, 'Cardiac arrest — resuscitation unsuccessful', false);
    if (a.rhythm === 'VF' && dur > 12 && !a.cpr) a.rhythm = 'ASYS';
    // epinephrine / cause-driven ROSC chance for non-shockable
    if (a.cpr) {
      let pr = 0.012;
      if (a.rhythm !== 'VF') {
        if (a.epi > 0 && g.t - a.lastEpi < 6) pr += 0.02;
        if (a.causeFixed) pr += 0.09;
        if (p.tags.airway || p.tags.bvm) pr += 0.01;
      } else {
        if (a.causeFixed) pr += 0.02;
        pr = 0.004;
      }
      if (chance(pr)) return rosc(g, p);
    }
  }
  function rosc(g, p) {
    p.arrest = null;
    p.tags.rosc = { t: g.t };
    p.sev = clamp(Math.max(55, Math.min(p.sev, 80)), 50, 80);
    p.postRosc = true;
    p.crisis = null;
    computeVitals(g, p);
    ev(g, 'rosc', `ROSC! ${p.name} has a pulse again — transfer to ICU`, p.id, 'good');
    log(g, `ROSC: ${p.name}`, 'good');
    g.stats.saved++;
    g.rep = clamp(g.rep + 2, 0, 100);
  }
  function shock(g, p) {
    const a = p.arrest;
    if (!a) {
      p.sev = clamp(p.sev + 25, 0, 100);
      p.harm = (p.harm || 0) + 1;
      return { ok: false, msg: 'You shocked a patient with a pulse — dangerous arrhythmia triggered.', bad: true };
    }
    if (a.rhythm !== 'VF') { a.wrongShocks++; return { ok: false, msg: 'Not a shockable rhythm (PEA / asystole)! Continue CPR + epinephrine and treat the cause.', bad: true }; }
    a.shocks++;
    let pr = 0.28 + (a.cpr ? 0.12 : -0.15) + (a.epi ? 0.06 : 0) + (a.amio ? 0.08 : 0) + (a.causeFixed ? 0.1 : 0) + (a.shocks > 1 ? 0.04 : 0);
    if (chance(clamp(pr, 0.05, 0.85))) { rosc(g, p); return { ok: true, msg: 'Shock delivered — ROSC!' }; }
    if (chance(0.2)) a.rhythm = 'PEA';
    return { ok: true, msg: `Shock ${a.shocks} delivered. Resume CPR immediately.` };
  }

  // ---------------------------------------------------------------- death
  function die(g, p, cause, preventable) {
    if (p.dead) return;
    p.dead = true; p.arrest = null; p.crisis = null; p.cause = cause; p.doneAt = g.t;
    const loc = bedOf(g, p);
    if (loc) loc.bed.pid = null;
    const wasLoc = p.loc;
    p.loc = 'gone';
    g.stats.died++;
    g.rep = clamp(g.rep - (preventable ? 4 : 2), 0, 100);
    ev(g, 'death', `${p.name} (${p.age}${p.sex}) has died. ${cause}.`, p.id, 'crit');
    log(g, `DEATH: ${p.name} — ${cause}`, 'crit');
    if (wasLoc === 'waiting') log(g, `${p.name} died in the waiting room.`, 'crit');
    if (g.rep <= 0) g.over = true;
  }
  HS.die = die;

  // ---------------------------------------------------------------- placement
  HS.freeBed = function (g, kind, resusFirst) {
    const beds = g.beds[kind];
    const free = beds.filter((b) => !b.pid);
    if (resusFirst) return free.find((b) => b.resus) || free[0] || null;
    return free.find((b) => !b.resus) || free[0] || null;
  };
  HS.place = function (g, pid, kind, bedId) {
    const p = P(g, pid);
    if (!p || p.dead) return { ok: false, msg: 'No such patient' };
    const bed = bedId ? g.beds[kind].find((b) => b.id === bedId) : HS.freeBed(g, kind, p.sev >= 55 || p.crit);
    if (!bed || (bed.pid && bed.pid !== p.id)) return { ok: false, msg: 'No free ' + kind.toUpperCase() + ' bed.' };
    const old = bedOf(g, p);
    if (old) old.bed.pid = null;
    bed.pid = p.id;
    const wasInbound = p.loc === 'inbound';
    p.loc = kind;
    p.bedId = bed.id;
    if (wasInbound) g.inbound = g.inbound.filter((x) => x !== p.id);
    if (kind === 'er' || kind === 'icu') p.onMonitor = p.onMonitor || p.sev >= 50 || kind === 'icu';
    if (kind === 'icu') p.onMonitor = true;
    if (!p.t0 || wasInbound) p.t0 = g.t;
    if (kind === 'er' && !p.seenByDoc) { p.seenByDoc = g.t; g.stats.seen++; }
    return { ok: true, msg: `${p.name} → ${bed.id}` };
  };

  // ---------------------------------------------------------------- the tick
  HS.tick = function (g) {
    g.t += 1;
    HS._now = g.t;
    g.funds -= OVERHEAD_PER_MIN; g.stats.spent += OVERHEAD_PER_MIN;
    if (g.funds < 0 && g.t % 60 === 0) { g.rep = clamp(g.rep - 0.6, 0, 100); if (!g.redWarned || g.t - g.redWarned > 480) { g.redWarned = g.t; ev(g, 'broke', 'The hospital is in the red — reputation is slipping. Treat paying cases and avoid over-ordering.', null, 'warn'); } }
    // arrivals
    arrivals(g);
    // inbound ambulances
    for (const id of g.inbound.slice()) {
      const p = P(g, id);
      p.eta--;
      if (p.eta <= 0) {
        g.inbound = g.inbound.filter((x) => x !== id);
        p.loc = 'waiting'; p.t0 = g.t;
        const bed = HS.freeBed(g, 'er', p.crit || p.sev >= 55);
        if (bed && !p.reserved) { HS.place(g, id, 'er', bed.id); ev(g, 'arrived', `Ambulance arrived: ${p.name} → ${bed.id}. ${p.arrest ? 'CPR IN PROGRESS' : ''}`, id, p.crit ? 'crit' : 'warn'); }
        else if (p.reserved) { HS.place(g, id, 'er', p.reserved); p.readyUntil = g.t + 6; ev(g, 'arrived', `Ambulance arrived: ${p.name} → ${p.reserved} (prepped)`, id, 'warn'); }
        else ev(g, 'arrived', `Ambulance arrived but ER is FULL — ${p.name} is on a trolley in the corridor!`, id, 'crit');
      }
    }
    // pending orders / actions
    for (const id in g.patients) {
      const p = g.patients[id];
      if (p.dead || p.loc === 'gone' || p.loc === 'inbound') continue;
      stepPatient(g, p);
    }
    if (g.t % 30 === 0) rollRandomCrisis(g);
    if (g.t % 360 === 0) mciRoll(g);
    // cleanup
    if (g.t % 120 === 0) for (const id in g.patients) { const p = g.patients[id]; if (p.loc === 'gone' && p.doneAt && g.t - p.doneAt > 600) delete g.patients[id]; }
  };

  HS.advance = function (g, minutes) { for (let i = 0; i < minutes; i++) { HS.tick(g); if (g.over) break; } };

  function arrivals(g) {
    const h = HS.hourOf(g.t);
    const f = h >= 17 && h < 23 ? 1.4 : h >= 7 && h < 17 ? 1.0 : h >= 23 || h < 2 ? 0.8 : 0.5;
    const lam = (1 / 40) * f * g.diff;
    if (chance(lam)) spawn(g, {});
  }
  function mciRoll(g) {
    if (g.t - g.lastMci < 1500 || !chance(0.12 * g.diff)) return;
    g.lastMci = g.t;
    ev(g, 'mci', 'MASS-CASUALTY ALERT: multi-vehicle pile-up on the highway — 3 ambulances inbound!', null, 'crit');
    log(g, 'MASS CASUALTY: 3 trauma ambulances inbound', 'crit');
    const pool = ['splenic', 'polytrauma', 'femur_fx', 'limb_bleed', 'gsw_chest', 'epidural', 'mangled'];
    for (let i = 0; i < 3; i++) spawn(g, { amb: true, cond: pick(pool) });
  }

  function stepPatient(g, p) {
    const c = p.condDef;
    // sedation/respiratory depression timers
    if (p.sedUntil > 0) { p.sedUntil--; if (p.sedUntil === 0 && p.agit) p.agit = Math.max(p.agit, 30); }
    if (p.respDep > 0 && g.t % 5 === 0) p.respDep = Math.max(0, p.respDep - 1);
    p.fluidFx = p.fluidFx.filter((f) => f.until > g.t);
    // pending actions
    if (p.pending.length) {
      const due = p.pending.filter((x) => x.due <= g.t);
      if (due.length) { p.pending = p.pending.filter((x) => x.due > g.t); for (const d of due) finishAction(g, p, d); }
    }
    // test results
    for (const id in p.orders) {
      const o = p.orders[id];
      if (!o.done && o.due <= g.t) {
        o.done = true; o.text = resultFor(g, p, id); const rr = p.results[id];
        o.abn = rr.abn;
        ev(g, 'result', `${p.name}: ${HS.TESTS[id].n} ready${rr.abn ? ' — ABNORMAL' : ''}`, p.id, rr.abn ? 'warn' : '');
      }
    }
    if (p.arrest) { tickArrest(g, p); if (p.dead) return; computeVitals(g, p); if (g.t % 3 === 0) p.seen = Object.assign({ t: g.t }, p.v); return; }
    // bleeding
    const br = bleedRate(p);
    if (br > 0) {
      if (p.bleed.minor) p.blood += br / 5; else p.blood += br;
    }
    // tourniquet clock
    if (p.tq) {
      const tmin = g.t - p.tq.t;
      if (tmin === 120) { p.limbDamage = true; ev(g, 'tq', `${p.name}: tourniquet on >2 h — limb at risk`, p.id, 'warn'); }
      if (tmin === 300) { p.limbLost = true; }
    }
    // restraint monitoring
    if (p.restrainedAt) {
      const rm = g.t - p.restrainedAt;
      if (rm === 45 && !(p.sedUntil > 0)) { p.sev = clamp(p.sev + 8, 0, 100); ev(g, 'restraint', `${p.name}: still agitated in restraints — exhausted, overheating, check on them`, p.id, 'warn'); }
      if (rm > 90 && p.agit < 30) { /* calm */ }
    }
    if (c.agit && p.agit > 50 && !p.restrainedAt && !(p.sedUntil > 0) && !p.crisis && p.loc !== 'waiting' && chance(0.012)) {
      startCrisis(g, p, 'violence');
    }
    // severity dynamics
    const base = c.grow / 60;
    const nm = needsMet(p);
    let ds;
    if (p.cured) ds = -0.45;
    else if (nm >= 0.999) {
      ds = -Math.max(0.12, base * 0.5);
      const fl = c.floor || 0;
      if (fl && p.sev + ds < fl && !p.cured) ds = Math.min(0, fl - p.sev);
    } else ds = base * (1 - 0.8 * nm);
    if (p.loc === 'waiting') ds *= 0.6;
    if (p.loc === 'ward' && c.dispo === 'icu') ds *= 1.25;
    if (p.loc === 'icu') ds *= 0.85;
    if (!p.airwayClear && p.cond === 'choking') ds = 2.0;
    p.sev = clamp(p.sev + ds, 0, 100);
    // chronic onset limits for time-critical therapy
    // crisis resolution
    if (p.crisis) {
      const cr = HS.CRISES[p.crisis.type];
      if (crisisSatisfied(g, p)) {
        const fixed = p.crisis.type;
        if (fixed === 'tension') p.tensionPtx = false;
        if (fixed === 'airway') p.airwayClear = true;
        p.crisis = null; g.stats.crisesOk++;
        p.sev = clamp(p.sev + 4, 0, 100);
        ev(g, 'crisis_ok', `${p.name}: ${cr.label} resolved. Well done.`, p.id, 'good');
        g.rep = clamp(g.rep + 1, 0, 100);
        log(g, `Crisis resolved: ${cr.label} (${p.name})`, 'good');
      } else if (g.t - p.crisis.t0 > cr.deadline) {
        const type = p.crisis.type;
        p.crisis = null;
        if (['anaphylaxis', 'airway', 'tension', 'seizure'].includes(type) && chance(0.7)) startArrest(g, p, type === 'seizure' ? 'ASYS' : 'PEA', type === 'anaphylaxis' ? 'anaphylaxis' : type === 'tension' ? 'tension' : 'hypoxia');
        else { p.sev = clamp(p.sev + 25, 0, 100); ev(g, 'crisis_bad', `${p.name}: ${cr.label} not controlled in time — severely deteriorated`, p.id, 'crit'); }
        p.preventable = true;
      }
    }
    // computing vitals
    computeVitals(g, p);
    const se = sevEff(p);
    if (!p.dead && !p.arrest) {
      if (se >= 98 || p.v.sbp <= 25 && p.v.sbp > 0 && p.loc !== 'waiting' && se > 80) {
        if (p.cond === 'choking') startArrest(g, p, 'ASYS', 'hypoxia');
        else startArrest(g, p, arrestRhythmFor(p), arrestCause(p));
      }
    }
    // monitors & intermittent checks
    if (p.onMonitor) p.seen = Object.assign({ t: g.t }, p.v);
    else if (g.t % 25 === 0 && p.loc !== 'waiting') p.seen = Object.assign({ t: g.t }, p.v);
    else if (g.t % 60 === 0) p.seen = Object.assign({ t: g.t }, p.v);
    // warnings
    if (p.onMonitor && !p.warned && (p.v.spo2 < 88 || p.v.sbp < 80)) { p.warned = g.t; ev(g, 'alarm', `ALARM: ${p.name} — ${p.v.spo2 < 88 ? 'SpO2 ' + Math.round(p.v.spo2) + '%' : 'BP ' + Math.round(p.v.sbp)}`, p.id, 'crit'); }
    if (p.warned && g.t - p.warned > 15) p.warned = null;
    // waiting-room attrition
    if (p.loc === 'waiting') {
      p.stats.minWaiting++;
      if (p.sev < 25 && p.stats.minWaiting > 200 && chance(0.02)) {
        p.dead = false; p.loc = 'gone'; p.doneAt = g.t; g.stats.lwbs++; g.rep = clamp(g.rep - 1, 0, 100);
        ev(g, 'lwbs', `${p.name} got tired of waiting and left without being seen.`, p.id, 'warn');
        return;
      }
    }
    // admitted patients: recovery & automatic discharge
    if ((p.loc === 'ward' || p.loc === 'icu') && !p.dead) {
      const target = c.dispo;
      const stable = (p.cured || nm >= 0.999) && p.sev <= 18 && !p.crisis;
      const isSurgNotDone = c.dispo.startsWith('surg:') && !p.cured;
      if (stable && !isSurgNotDone) { p.recov++; if (p.recov >= Math.max(90, (c.stay || 360) * 0.4)) recovered(g, p); }
      else p.recov = Math.max(0, p.recov - 1);
    }
    // dying
    if (!p.dead && !p.arrest && effLossFrac(p) >= 0.5) die(g, p, 'Exsanguination', true);
  }

  function resultFor(g, p, id) {
    const T = HS.TESTS[id], r = p.results[id];
    let txt = r.text;
    if (id === 'glucose' && p.tags.dextrose && p.cond === 'hypoglyc') txt = '124 mg/dL (after dextrose)';
    if (id === 'troponin' && r.early && g.t - p.t0 > 180) txt = '3.9 ng/mL (HIGH) — repeat troponin now positive';
    if (id === 'bcx') txt = 'No growth yet (final in 24-48h)';
    if (T.ct && sevEff(p) > 75 && chance(0.4)) { p.sev = clamp(p.sev + 10, 0, 100); ev(g, 'ctcrash', `${p.name} crashed in the CT scanner!`, p.id, 'crit'); }
    return txt;
  }

  function recovered(g, p) {
    const c = p.condDef;
    const loc = bedOf(g, p); if (loc) loc.bed.pid = null;
    p.loc = 'gone'; p.doneAt = g.t;
    let pay = (c.pay || 1500) * PAY * (1 - Math.min(0.5, p.cost / 8000));
    pay *= clamp(0.7 + (p.dx === p.cond ? 0.3 : 0), 0.7, 1);
    pay += p.cost * 0.6;
    g.funds += pay; g.stats.earned += pay; g.stats.saved++;
    g.rep = clamp(g.rep + 1.5, 0, 100);
    ev(g, 'recovered', `${p.name} recovered and was discharged from ${p.bedId}. +${HS.money(pay)}`, p.id, 'good');
    log(g, `Discharged recovered: ${p.name} (+${HS.money(pay)})`, 'good');
  }

  // ---------------------------------------------------------------- history / exam / tests
  HS.askHistory = function (g, pid, i) {
    const p = P(g, pid);
    if (!p || p.dead) return { ok: false };
    if (p.arrest) return { ok: false, msg: 'Patient is in cardiac arrest.' };
    p.hxAsked = p.hxAsked || [];
    if (p.hxAsked[i]) return { ok: false, msg: 'Already asked.' };
    p.hxAsked[i] = true;
    p.pending.push({ due: g.t + 2, kind: 'hx', i });
    return { ok: true, msg: 'Taking history…' };
  };
  function histLine(p, i) {
    const unresponsive = p.v.gcs <= 8 || p.unconscious;
    if (unresponsive) {
      if (i === 0) return `(From medics/bystanders) ${p.hxLines[0]}`;
      if (i === 1) return 'Cannot obtain — patient unresponsive and no medical records available.';
      return 'Allergies UNKNOWN — patient unresponsive. (No medical ID bracelet found.) Choose drugs carefully.';
    }
    return p.hxLines[i];
  }

  HS.examine = function (g, pid, sys) {
    const p = P(g, pid);
    if (!p || p.dead) return { ok: false };
    if (p.exam[sys] && p.exam[sys].text) return { ok: true, msg: 'Already examined' };
    p.pending.push({ due: g.t + 2, kind: 'exam', sys });
    p.exam[sys] = { pending: true };
    return { ok: true, msg: 'Examining…' };
  };
  const EXAM_DEFAULT = {
    general: 'Comfortable, alert, no acute distress.',
    chest: 'Clear to auscultation bilaterally, equal air entry.',
    heart: 'Regular rate and rhythm, normal heart sounds, no murmurs.',
    abdomen: 'Soft, non-tender, no guarding, bowel sounds normal.',
    neuro: 'GCS 15, pupils equal and reactive, moves all limbs, no focal deficit.',
    extremities: 'No deformity, pulses intact, warm and well perfused.',
  };
  HS.EXAM_SYSTEMS = [['general', 'General / ABCs'], ['chest', 'Chest / lungs'], ['heart', 'Heart'], ['abdomen', 'Abdomen'], ['neuro', 'Neuro'], ['extremities', 'Limbs / skin']];
  function examText(g, p, sys) {
    const c = p.condDef;
    let t = c.exam[sys] || EXAM_DEFAULT[sys];
    if (t.includes('__BLEED__')) {
      const b = p.bleed;
      const live = b && !b.stopped && bleedRate(p) > 0;
      let s;
      if (p.tq && b && sameLimb(p.tq.site, b.site)) s = `Tourniquet on the ${p.tq.site} (applied ${g.t - p.tq.t} min ago) — bleeding controlled.`;
      else if (b && b.stopped) s = 'Wound repaired.';
      else s = `Active ${p.cond === 'limb_bleed' ? 'pulsatile arterial ' : ''}bleeding from the ${b.site}${live ? ` (~${Math.round(bleedRate(p))} mL/min)` : ''}.`;
      t = t.replace('__BLEED__', s);
    }
    if (sys === 'chest' && p.tensionPtx) t += ' Trachea deviating, absent breath sounds on one side, distended neck veins — TENSION PNEUMOTHORAX.';
    if (sys === 'chest' && p.crisis && p.crisis.type === 'anaphylaxis') t = 'Diffuse wheeze and stridor.';
    if (sys === 'general' && p.crisis) t += ' ** ' + HS.CRISES[p.crisis.type].label + ' in progress **';
    if (sys === 'general' && p.arrest) t = 'Unresponsive. No pulse. ' + (p.arrest.cpr ? 'CPR in progress.' : 'NOT being compressed!');
    if (sys === 'general' && p.restrainedAt) t += ' In soft restraints.';
    if (sys === 'general' && !p.airwayClear) t += ' Airway obstructed — gurgling, no air movement.';
    if (sys === 'general') t += ` Pain ${Math.round(p.pain)}/10.`;
    return t;
  }

  HS.orderTest = function (g, pid, tid) {
    const p = P(g, pid), T = HS.TESTS[tid];
    if (!p || p.dead || !T) return { ok: false };
    if (p.orders[tid] && !p.orders[tid].done) return { ok: false, msg: 'Already ordered.' };
    p.orders[tid] = { due: g.t + T.min, done: false, t: g.t };
    g.funds -= T.cost; g.stats.spent += T.cost; p.cost += T.cost;
    return { ok: true, msg: `${T.n} ordered (ready ~${HS.fmtDur(T.min)})` };
  };

  // ---------------------------------------------------------------- actions
  function dosesFor(p, a) {
    if (!a.doses) return null;
    const k = p.peds ? clamp(p.wt / 70, 0.1, 1) : 1;
    const fmt = (x) => (x >= 10 ? Math.round(x) : +x.toFixed(2));
    if (a.perKg) return [0.5, 1, 2].map((m) => fmt(Math.min(a.perKg * p.wt, 0.5) * m));
    if (a.unit === 'mL' || a.unit === 'g') return a.doses.slice();
    return a.doses.map((d) => fmt(d * k));
  }
  HS.dosesFor = dosesFor;

  function stockOk(g, a) { return !a.stock || g.supplies[a.stock] > 0; }

  HS.act = function (g, pid, aid, opts = {}) {
    const p = P(g, pid), a = HS.ACTIONS[aid];
    if (!p || !a) return { ok: false, msg: 'Invalid action' };
    if (p.dead) return { ok: false, msg: 'Patient has died.' };
    if (p.loc === 'inbound') return { ok: false, msg: 'Patient has not arrived yet.' };
    if (aid === 'cpr') {
      if (!p.arrest) { p.sev = clamp(p.sev + 8, 0, 100); return { ok: false, msg: 'Patient has a pulse — chest compressions caused injury.', bad: true }; }
      p.arrest.cpr = !p.arrest.cpr;
      return { ok: true, msg: p.arrest.cpr ? 'Compressions started (100–120/min).' : 'Compressions paused.' };
    }
    if (aid === 'defib') {
      const r = shock(g, p);
      return r;
    }
    if (!stockOk(g, a)) return { ok: false, msg: `Out of ${HS.SUPPLIES[a.stock].n}! Order more in Supplies.` };
    if (a.group === 'drug' && a.route === 'iv' && !(p.iv || p.io || p.pending.some((x) => x.id === 'iv' || x.id === 'io'))) return { ok: false, msg: 'Needs IV/IO access first.' };
    if (aid === 'prbc' && !(p.iv || p.io || p.pending.some((x) => x.id === 'iv' || x.id === 'io'))) return { ok: false, msg: 'Needs IV/IO access first.' };
    if (aid === 'iv' && (p.iv)) return { ok: false, msg: 'Already has IV access.' };
    if (aid === 'io' && p.io) return { ok: false, msg: 'Already has IO access.' };
    if (a.surgery && opts.score === undefined && !opts.auto) return { ok: true, minigame: a.surgery, msg: 'Starting procedure…' };
    // consume stock now so queue cannot overspend
    if (a.stock) g.supplies[a.stock]--;
    g.funds -= a.cost; g.stats.spent += a.cost; p.cost += a.cost;
    const quick = p.arrest || p.crisis || a.min <= 1;
    const instant = p.readyUntil && g.t <= p.readyUntil;
    const delay = instant ? 0 : p.arrest ? Math.min(a.min, 1) : a.min;
    p.pending.push({ due: g.t + (quick ? Math.min(delay, 1) : delay), id: aid, opts, queued: g.t });
    // zero-minute (instant) execution for emergencies already at the bedside
    if (delay <= 0) { const q = p.pending.pop(); return finishAction(g, p, q); }
    return { ok: true, msg: `${a.name} — in progress (${delay} min)`, pending: true };
  };

  function reaction(g, p, a) {
    if (a.allergy && p.allergies.includes(a.allergy) && !(a.allergyMild && chance(0.85))) {
      p.allergicTo = a.id;
      if (chance(0.7)) {
        if (!p.crisis) startCrisis(g, p, 'anaphylaxis');
        return `ALLERGIC REACTION to ${a.name}! (${a.allergy.toUpperCase()} allergy)`;
      }
      p.sev = clamp(p.sev + 6, 0, 100);
      return `Rash and itching — mild allergic reaction to ${a.name}.`;
    }
    return null;
  }

  function finishAction(g, p, d) {
    if (d.kind === 'hx') {
      p.hxDone = p.hxDone || [];
      p.hxDone[d.i] = histLine(p, d.i);
      return { ok: true };
    }
    if (d.kind === 'exam') { p.exam[d.sys] = { text: examText(g, p, d.sys), t: g.t }; return { ok: true }; }
    const a = HS.ACTIONS[d.id];
    const o = d.opts || {};
    const msgs = [];
    let bad = false;
    const say = (m, b) => { msgs.push(m); if (b) bad = true; };
    const tagIt = (str = 1) => a.tags.forEach((t) => { p.tags[t] = { t: g.t, str }; });
    p.given.push({ id: a.id, n: a.name, t: g.t, dose: o.dose });
    const id = a.id;

    // --- access & monitoring
    if (id === 'iv') {
      if (p.v.sbp < 80 && chance(0.4)) { say('IV attempt failed — veins collapsed. Use an IO drill.', true); g.supplies.iv = Math.max(0, g.supplies.iv); }
      else { p.iv = true; tagIt(); say('IV access established.'); }
    } else if (id === 'io') { p.io = true; p.iv = true; tagIt(); say('IO access in the proximal tibia — drugs/fluids/blood can run.'); }
    else if (id === 'monitor') { p.onMonitor = true; say('Cardiac monitor on — continuous vitals.'); }
    else if (id === 'recheck') { p.seen = Object.assign({ t: g.t }, p.v); say('Vitals updated.'); }
    // --- airway
    else if (id === 'o2') { p.o2 = !p.o2; say(p.o2 ? 'Oxygen on.' : 'Oxygen off.'); if (p.o2) p.tags.o2 = { t: g.t, str: 1 }; }
    else if (id === 'suction' || id === 'jaw' || id === 'heimlich' || id === 'bvm') {
      tagIt();
      if (!p.airwayClear && (id !== 'bvm' || chance(0.5))) {
        if (p.cond === 'choking' ? (id === 'heimlich' || id === 'suction') && chance(0.8) : true) { p.airwayClear = true; say('Airway cleared.'); }
        else say('Not cleared yet — try another manoeuvre (abdominal thrusts / suction / cricothyrotomy).');
      } else say(id === 'bvm' ? 'Bagging the patient with 100% O2.' : 'Done.');
      if (id === 'bvm') p.tags.bvm = { t: g.t, str: 1 };
    } else if (id === 'intubate') {
      const induced = p.tags.induction && g.t - p.tags.induction.t < 12;
      if (p.v.gcs >= 9 && !induced && !p.arrest) { p.sev = clamp(p.sev + 6, 0, 100); p.airwayClear = true; say('Awake intubation — patient fought and vomited. Give an induction agent (ketamine) first next time.', true); if (chance(0.6)) { tagIt(); p.airway = true; } }
      else { tagIt(); p.airwayClear = true; p.airway = true; p.onMonitor = true; say('Intubated and ventilated. ETT confirmed with capnography.'); }
    } else if (id === 'cric') { tagIt(); p.airwayClear = true; p.airway = true; say('Surgical airway secured through the cricothyroid membrane.'); }
    // --- bleeding control & equipment
    else if (id === 'tourniquet') {
      const r = applyTourniquet(g, p, o.site || 'right thigh');
      say(r.msg, r.bad);
    } else if (id === 'pressure') { p.dev.pressure = true; tagIt(); say(p.bleed && p.bleed.kind === 'limb' ? 'Pressure dressing on — still oozing. A tourniquet may be needed for arterial bleeding.' : 'Pressure dressing applied.'); }
    else if (id === 'hemogauze') { p.dev.packing = true; tagIt(); say('Wound packed with hemostatic gauze and held under pressure.'); }
    else if (id === 'binder') { p.dev.binder = true; tagIt(); say(p.cond === 'polytrauma' ? 'Pelvic binder applied at the greater trochanters — pelvic volume reduced.' : 'Pelvic binder applied (no obvious pelvic injury).'); }
    else if (id === 'collar') { p.dev.collar = true; tagIt(); say('C-collar fitted, log-rolled onto a spinal board.'); }
    else if (id === 'splint') { p.dev.splint = true; tagIt(); p.pain = Math.max(0, p.pain - 2); say('Limb splinted; distal pulse rechecked.'); }
    else if (id === 'chestseal') { p.dev.chestseal = true; tagIt(); say(p.cond === 'open_chest' ? 'Vented chest seal applied.' : 'Chest seal applied.'); if (p.cond === 'open_chest') p.sev = clamp(p.sev - 5, 0, 100); }
    else if (id === 'needle') {
      if (p.tensionPtx) { p.tensionPtx = false; tagIt(); p.sev = clamp(p.sev - 8, 0, 100); say('Needle decompression — rush of air, BP and SpO2 improving. Needs a chest tube.'); }
      else { p.sev = clamp(p.sev + 8, 0, 100); say('No tension pneumothorax — you have caused one. Needs a chest tube.', true); p.postNeedle = true; }
    } else if (id === 'restraints') { p.restrainedAt = g.t; tagIt(); say('Soft restraints applied. Monitor circulation — and sedate if still violent.'); }
    else if (id === 'unrestrain') { p.restrainedAt = null; say('Restraints removed.'); }
    else if (id === 'warm') { tagIt(); p.base.temp += 0; say('Active warming started.'); }
    else if (id === 'cool') { tagIt(); say('Active cooling started.'); }
    else if (id === 'ngt') { tagIt(); say('NG tube placed — bilious output.'); }
    else if (id === 'foley') { tagIt(); say('Catheter placed.'); }
    else if (id === 'cardiovert') {
      if (p.cond === 'svt' && p.v.hr > 140) {
        tagIt(); p.tags._svtOk = { t: g.t }; p.tags.cardiovert_ok = { t: g.t }; p.pain = 6;
        say(p.sedUntil > 0 ? 'Sinus rhythm restored.' : 'Converted — but you shocked an awake patient without sedation!', p.sedUntil <= 0);
        if (p.sedUntil <= 0) p.sev = clamp(p.sev + 4, 0, 100);
      } else { p.sev = clamp(p.sev + 14, 0, 100); say('Not an unstable tachyarrhythmia — cardioversion was inappropriate.', true); }
    }
    // --- bedside procedures (mini-game)
    else if (a.surgery) {
      const sc = o.score !== undefined ? o.score : 80;
      if (sc >= 40) { tagIt(); say(`${a.name} done (quality ${Math.round(sc)}%).`); if (id === 'chesttube') { p.tensionPtx = false; p.sev = clamp(p.sev - 10, 0, 100); } if (id === 'suturelac' && p.bleed) p.bleed.stopped = true; if (id === 'reduce') p.pain = 2; }
      else { p.sev = clamp(p.sev + 6, 0, 100); say('Procedure went badly — poor technique.', true); }
    }
    // --- drugs
    else if (a.group === 'drug') bad = giveDrug(g, p, a, o, say) || bad;
    else { tagIt(); say(a.name + ' done.'); }

    if (a.group === 'drug' || a.group === 'equip' || a.group === 'airway' || a.group === 'proc') p.lastAction = g.t;
    const msg = msgs.join(' ');
    ev(g, bad ? 'bad' : 'act', `${p.name}: ${msg}`, p.id, bad ? 'crit' : '');
    p.notes.unshift({ t: g.t, text: `${a.name}${o.dose ? ' ' + o.dose : ''}: ${msg}`, bad });
    return { ok: true, msg, bad };
  }

  function applyTourniquet(g, p, site, scene) {
    const b = p.bleed;
    if (p.tq) return { ok: true, msg: 'A tourniquet is already on — check the time.' };
    p.tq = { site, t: g.t, scene: !!scene };
    p.tags.tourniquet = { t: g.t, str: 1 };
    p.pain = Math.min(10, p.pain + 1);
    if (b && b.kind === 'limb') {
      if (sameLimb(site, b.site)) return { ok: true, msg: `Tourniquet applied high and tight on the ${site} — bleeding stopped. Time noted ${HS.fmtTime(g.t)}.` };
      return { ok: true, bad: true, msg: `Tourniquet on the ${site} — WRONG limb! The ${b.site} is still bleeding.` };
    }
    return { ok: true, bad: true, msg: `Tourniquet on the ${site} for no reason — painful and risks limb ischaemia. Remove it.` };
  }
  HS.removeTourniquet = function (g, pid) {
    const p = P(g, pid); if (!p || !p.tq) return { ok: false };
    const mins = g.t - p.tq.t; p.tq = null; delete p.tags.tourniquet;
    return { ok: true, msg: `Tourniquet released after ${mins} min` + (p.bleed && p.bleed.kind === 'limb' && !p.bleed.stopped ? ' — bleeding resumes!' : '.') };
  };

  const BLEED_CONDS = ['hem_stroke', 'epidural', 'aaa', 'ectopic', 'limb_bleed', 'mangled', 'gsw_chest', 'splenic', 'polytrauma', 'femur_fx', 'perf_ulcer', 'pph', 'lac'];
  function giveDrug(g, p, a, o, say) {
    let bad = false;
    const idx = o.idx !== undefined ? o.idx : a.stdIdx;
    const dose = o.dose;
    const std = idx === a.stdIdx;
    const low = idx < a.stdIdx, high = idx > a.stdIdx;
    const rx = reaction(g, p, a);
    if (rx) { say(rx, true); bad = true; if (!p.crisis) {} }
    // effect strength
    let said = false;
    const _say = say; say = (m, b) => { said = true; _say(m, b); };
    // --- fluids
    if (a.id === 'fluids') {
      const ml = a.doses[idx];
      p.fluidsMl += ml; p.fluidFx.push({ amt: ml * 0.3, until: g.t + 120 });
      p.tags.fluids = { t: g.t, str: 1 };
      if ((p.cond === 'chf') && p.fluidsMl > 600) { p.sev = clamp(p.sev + 14, 0, 100); say('Fluids in heart failure — pulmonary edema worsening!', true); bad = true; }
      else if (p.cond === 'burn' || p.cond === 'dka' || p.cond === 'sepsis' || p.cond === 'gastro') say(`${ml} mL crystalloid running.`);
      else say(`${ml} mL crystalloid bolus given.`);
      return bad;
    }
    if (a.id === 'prbc') {
      p.bloodUnits++; p.restored += 320; p.tags.blood = { t: g.t, str: 1 };
      say('1 unit O-neg blood transfused.');
      if (chance(0.01)) { say('Transfusion reaction — febrile, chills.', true); p.sev = clamp(p.sev + 8, 0, 100); bad = true; }
      return bad;
    }
    // --- contraindications
    if (a.hypo && p.v.sbp < a.hypo) { p.sev = clamp(p.sev + 10, 0, 100); say(`${a.name} with BP ${Math.round(p.v.sbp)} — profound hypotension!`, true); bad = true; }
    const cd = a.contra && a.contra[p.cond];
    if (cd) { p.sev = clamp(p.sev + cd[0], 0, 100); say(cd[1] + ' — made things worse.', true); bad = true; }
    if (a.bleedRisk && (p.bleed && !p.bleed.stopped || BLEED_CONDS.includes(p.cond))) {
      p.bleedMul = 1.7; p.bleedMulUntil = g.t + 180; p.sev = clamp(p.sev + 6, 0, 100);
      say(`${a.name} in an actively bleeding patient — bleeding worse!`, true); bad = true;
    }
    if (a.hypovol && (p.bleed || ['sepsis', 'gastro', 'dka', 'perf_ulcer'].includes(p.cond)) && p.cond !== 'chf') { p.sev = clamp(p.sev + 9, 0, 100); say('Diuretic in a volume-depleted patient — BP dropping.', true); bad = true; }
    if (a.hypoglyc && p.cond === 'hypoglyc') { p.sev = clamp(p.sev + 25, 0, 100); say('Insulin to a hypoglycaemic patient! Glucose crashing further.', true); bad = true; }
    if (a.resp && (high || p.cond === 'opioid_od' || p.v.rr < 10 || p.v.gcs <= 8) ) { p.respDep = (p.respDep || 0) + (high ? 7 : 4); say(`${a.name}: respiratory depression — watch SpO2/RR.`, true); bad = true; }
    if (a.id === 'alteplase') {
      const ow = (p.cond === 'stroke') ? (p.condDef.onset + (g.t - p.t0)) : 9999;
      if (p.cond === 'stroke' && ow <= 270) { p.tags.thrombolytic = { t: g.t, str: 1 }; say('Alteplase given within the window — fingers crossed.'); if (chance(0.05)) { p.sev = clamp(p.sev + 20, 0, 100); say('Symptomatic hemorrhagic conversion.', true); bad = true; } }
      else if (p.cond === 'stroke') { p.sev = clamp(p.sev + 18, 0, 100); say('Outside the 4.5 h window — high bleeding risk.', true); bad = true; }
      else if (BLEED_CONDS.includes(p.cond)) { p.bleedMul = 3; p.bleedMulUntil = g.t + 240; p.sev = clamp(p.sev + 30, 0, 100); say('THROMBOLYTIC GIVEN TO A BLEEDING PATIENT — catastrophic!', true); bad = true; }
      else { p.sev = clamp(p.sev + 14, 0, 100); say('Thrombolytic given with no indication.', true); bad = true; }
      return bad;
    }
    // --- specific therapeutic effects
    if (a.id === 'epi_iv') {
      if (p.arrest) { p.arrest.epi++; p.arrest.lastEpi = g.t; say('Epinephrine 1 mg IV given. Repeat every 3–5 min.'); }
      else { p.sev = clamp(p.sev + 8, 0, 100); say('Epinephrine IV push in a patient with a pulse — severe tachycardia/hypertension.', true); bad = true; }
      return bad;
    }
    if (a.id === 'amio') { if (p.arrest) { p.arrest.amio++; say('Amiodarone given.'); } else say('Amiodarone given.'); a.tags.forEach((t) => (p.tags[t] = { t: g.t, str: 1 })); return bad; }
    if (a.id === 'epi_im') {
      p.tags.epi = { t: g.t, str: 1 };
      if (p.cond === 'mi' || p.cond === 'chf') { p.sev = clamp(p.sev + 10, 0, 100); say('Epinephrine in a cardiac patient — dangerous tachyarrhythmia risk.', true); bad = true; }
      else if (low && p.cond === 'anaphylaxis') { say('Underdosed — repeat the dose.'); delete p.tags.epi; }
      else say(p.crisis && p.crisis.type === 'anaphylaxis' || p.cond === 'anaphylaxis' ? 'IM epinephrine given — wheeze and BP improving.' : 'Epinephrine IM given.');
      return bad;
    }
    if (a.id === 'adenosine') {
      if (p.cond === 'svt' && !low) { p.tags.adenosine = { t: g.t, str: 1 }; p.tags._svtOk = { t: g.t }; say('Rapid push followed by flush: brief pause then sinus rhythm restored.'); }
      else if (p.cond === 'svt') say('6 mg did not convert — try 12 mg.');
      else { say('Adenosine given — brief asystole, no effect on this rhythm.'); }
      return bad;
    }
    if (a.id === 'naloxone') {
      p.tags.naloxone = { t: g.t, str: 1 };
      if (p.cond === 'opioid_od') { say(low ? 'Partial response, still sedated.' : 'Naloxone: patient starts to breathe and wakes up (may be agitated).'); if (!low) { p.respDep = 0; p.unconscious = false; } }
      else if (p.respDep > 0) { p.respDep = 0; say('Opioid sedation reversed.'); }
      else say('Naloxone given — no effect.');
      if (high) { say('Large dose — acute opioid withdrawal & vomiting.', true); bad = true; }
      return bad;
    }
    if (a.id === 'dextrose') {
      p.tags.dextrose = { t: g.t, str: 1 };
      if (p.cond === 'hypoglyc') { say('Dextrose: patient wakes up and starts talking!'); p.sev = clamp(p.sev - 20, 0, 100); p.unconscious = false; p.base.gcs = 15; }
      else say('Dextrose given.');
      if (p.crisis && p.crisis.type === 'hypoglycemia') {}
      return bad;
    }
    if (a.id === 'nitro' && p.v.sbp >= a.hypo && p.cond === 'mi') { p.pain = Math.max(0, p.pain - 2); }
    if (a.id === 'furosemide' && p.cond === 'chf') { say('Furosemide: strong urine output, breathing easier.'); }
    if (a.id === 'insulin' && p.cond === 'dka') { say('Insulin infusion started (with potassium monitoring).'); }
    // analgesia / sedation
    if (a.tags.includes('analgesia')) { p.pain = Math.max(0, p.pain - (low ? 2 : 5)); }
    if (a.tags.includes('analgesia_mild')) p.pain = Math.max(0, p.pain - (low ? 1 : 3));
    if (a.tags.includes('sedation')) {
      if (!low) { p.sedUntil = Math.max(p.sedUntil, 90); p.agit = Math.min(p.agit, 15); if (p.unconscious === false && p.crisis && p.crisis.type === 'violence') {} }
      if (a.tags.includes('induction')) p.tags.induction = { t: g.t, str: 1 };
    }
    if (a.tags.includes('anticonvulsant') && p.crisis && p.crisis.type === 'seizure') say('Seizure terminating.');
    if (high && !a.resp && !a.bleedRisk) { say(`High dose of ${a.name} — risk of toxicity.`); p.sev = clamp(p.sev + 4, 0, 100); bad = true; }
    if (low) {
      say(`${a.name}: low dose — sub-therapeutic, little effect.`);
      return bad;
    }
    a.tags.forEach((t) => { p.tags[t] = { t: g.t, str: 1 }; });
    if (!bad && !said) say(`${a.name} ${dose || ''} given.`);
    return bad;
  }

  // ---------------------------------------------------------------- diagnosis & disposition
  HS.setDx = function (g, pid, condId) { const p = P(g, pid); if (p) p.dx = condId; };

  function canGoHome(p) {
    const c = p.condDef;
    return c.dispo === 'home' || (c.homeIfSev && p.sev <= c.homeIfSev);
  }
  // simple serializable "later" queue (kind + data)
  function later(g, delay, kind, data) { g.later = g.later || []; g.later.push({ at: g.t + delay, kind, data }); }
  const _origTick = HS.tick;
  HS.tick = function (g) {
    _origTick(g);
    if (g.later && g.later.length) {
      const due = g.later.filter((x) => x.at <= g.t);
      if (due.length) {
        g.later = g.later.filter((x) => x.at > g.t);
        for (const d of due) laterFire(g, d);
      }
    }
  };
  function laterFire(g, d) {
    const x = d.data;
    if (d.kind === 'bounce') {
      const p = spawn(g, { amb: x.amb, cond: x.cond, sevAdd: x.sevAdd, bounce: x.id });
      p.loc = x.amb ? p.loc : 'waiting';
      ev(g, 'bounce', `RETURN VISIT: ${x.id.name} is back — ${x.why}`, p.id, 'crit');
      log(g, `Bounce-back: ${x.id.name}`, 'crit');
    } else if (d.kind === 'death_home') {
      g.stats.sued++;
      g.rep = clamp(g.rep - 12, 0, 100); g.funds -= 25000;
      ev(g, 'sued', `${x.name} died at home after discharge. Family files a malpractice suit (-$25,000).`, null, 'crit');
      log(g, `Died at home after premature discharge: ${x.name}. LAWSUIT.`, 'crit');
      if (g.rep <= 0) g.over = true;
    }
  }

  HS.discharge = function (g, pid) {
    const p = P(g, pid), c = p && p.condDef;
    if (!p || p.dead) return { ok: false, msg: 'No patient.' };
    if (p.arrest) return { ok: false, msg: 'Patient is in arrest!' };
    const nm = needsMet(p);
    const ok = canGoHome(p);
    const id = { name: p.name, age: p.age, sex: p.sex, allergies: p.allergies };
    const loc = bedOf(g, p); if (loc) loc.bed.pid = null;
    p.loc = 'gone'; p.doneAt = g.t;
    g.stats.home++;
    if (p.dx) { g.stats.dxN++; if (p.dx === p.cond) g.stats.dxOk++; }
    let res = { ok: true, outcome: 'good', msg: '' };
    if (p.sev > 45 || p.v.sbp < 90 || p.v.spo2 < 90) {
      // clearly unwell patients cannot be discharged safely
      res.outcome = 'bad';
    }
    if (ok && nm >= 0.99 && res.outcome === 'good') {
      let pay = (c.pay || 400) * PAY; if (p.dx === p.cond) pay *= 1.15; pay += p.cost * 0.6;
      g.funds += pay; g.stats.earned += pay; g.stats.saved++; g.rep = clamp(g.rep + (p.dx === p.cond ? 2 : 1.2), 0, 100);
      res.msg = `${p.name} discharged home, well. +${HS.money(pay)}` + (p.dx === p.cond ? ' (correct diagnosis bonus)' : '');
      res.outcome = 'good';
    } else if (ok && res.outcome === 'good') {
      res.outcome = 'meh';
      g.rep = clamp(g.rep - 1, 0, 100);
      res.msg = `${p.name} sent home with incomplete treatment — may return.`;
      if (chance(0.55)) later(g, ri(240, 720), 'bounce', { id, cond: p.cond, amb: false, sevAdd: 12, why: 'symptoms returned after incomplete treatment' });
      g.funds += (c.pay || 400) * PAY * 0.4;
    } else {
      res.outcome = 'bad';
      res.msg = `${p.name} was discharged but was NOT fit for home. ` + (c.dispo.startsWith('surg') ? 'This needed surgery.' : 'This needed admission.');
      g.rep = clamp(g.rep - 3, 0, 100);
      if (chance(0.45)) later(g, ri(180, 600), 'death_home', { name: p.name });
      else later(g, ri(120, 480), 'bounce', { id, cond: p.cond, amb: true, sevAdd: 25, why: 'collapsed at home after being discharged' });
    }
    log(g, res.msg, res.outcome === 'good' ? 'good' : 'crit');
    return res;
  };

  HS.admit = function (g, pid, kind) {
    const p = P(g, pid);
    if (!p || p.dead) return { ok: false, msg: 'No patient.' };
    if (p.arrest) return { ok: false, msg: 'Patient is in arrest!' };
    const r = HS.place(g, pid, kind);
    if (!r.ok) return r;
    g.stats.admitted++;
    if (p.dx) { g.stats.dxN++; if (p.dx === p.cond) { g.stats.dxOk++; } }
    p.dxCounted = true;
    p.admitted = g.t;
    let msg = `${p.name} admitted to ${kind.toUpperCase()} ${p.bedId}.`;
    const c = p.condDef;
    const need = c.dispo === 'icu' ? 'icu' : c.dispo === 'ward' ? 'ward' : c.dispo.startsWith('surg') ? 'surg' : 'home';
    if (kind === 'ward' && need === 'icu') msg += ' (Ward may be too low-acuity.)';
    log(g, msg);
    return { ok: true, msg };
  };

  // ---------------------------------------------------------------- surgery outcome
  HS.surgeryMatches = function (p, sid) { return p.condDef.dispo === 'surg:' + sid; };
  HS.finishSurgery = function (g, pid, r) {
    // r: { sid, score(0..100), blood(ml), prep(0..1), anaes(0..1), mins }
    const p = P(g, pid), c = p.condDef;
    const match = HS.surgeryMatches(p, r.sid);
    p.blood += r.blood || 0;
    g.stats.surgeries++;
    const preSev = p.sevAtOp || p.sev;
    let psucc = 0.38 + 0.55 * (r.score / 100) - 0.3 * (preSev / 100) + 0.1 * (r.prep || 0) + 0.05 * (r.anaes || 0) - Math.max(0, effLossFrac(p) - 0.2) * 1.2;
    if (p.limbDamage && (r.sid === 'vascular')) psucc -= 0.3;
    if (!match) psucc = 0;
    const roll = rand();
    let outcome, msg;
    p.sedUntil = 0;
    if (effLossFrac(p) >= 0.5) { die(g, p, 'Died on the table — hemorrhage', true); return { outcome: 'death', msg: `${p.name} died on the operating table (blood loss).` }; }
    if (!match) {
      p.sev = clamp(p.sev + 12, 0, 100);
      msg = `Operation (${HS.SURGERIES[r.sid].name}) was not the right procedure for the underlying problem. The real condition remains untreated.`;
      outcome = 'wrong';
      g.rep = clamp(g.rep - 4, 0, 100);
    } else if (roll < psucc) {
      p.cured = true; p.bleed && (p.bleed.stopped = true); p.tensionPtx = false; if (p.tq) { p.tq = null; delete p.tags.tourniquet; }
      p.sev = Math.min(p.sev, 30);
      outcome = 'success'; msg = `${HS.SURGERIES[r.sid].name} successful.`;
      g.stats.surgOk++;
      g.rep = clamp(g.rep + 3, 0, 100);
      let pay = (c.pay || 8000) * PAY; pay *= clamp(0.6 + r.score / 160, 0.6, 1.2); pay += p.cost * 0.6;
      g.funds += pay; g.stats.earned += pay; p.pay = pay;
    } else if (roll < psucc + 0.28) {
      p.cured = true; p.bleed && (p.bleed.stopped = true); p.tensionPtx = false;
      p.sev = 58;
      outcome = 'complication'; msg = `${HS.SURGERIES[r.sid].name} completed but with complications — needs ICU care.`;
      g.rep = clamp(g.rep + 1, 0, 100);
      const pay = (c.pay || 8000) * PAY * 0.7 + p.cost * 0.6; g.funds += pay; g.stats.earned += pay;
    } else {
      die(g, p, `Died during ${HS.SURGERIES[r.sid].name}`, r.score < 60);
      return { outcome: 'death', msg: `${p.name} died during the operation.` };
    }
    if (p.dead) return { outcome, msg };
    // move to recovery bed
    const old = bedOf(g, p); if (old) old.bed.pid = null;
    const kind = p.sev > 45 ? 'icu' : 'ward';
    let moved = HS.place(g, pid, kind);
    if (!moved.ok) moved = HS.place(g, pid, kind === 'icu' ? 'ward' : 'icu');
    if (!moved.ok) moved = HS.place(g, pid, 'er');
    p.onMonitor = true;
    p.recov = 0;
    log(g, msg, outcome === 'success' ? 'good' : 'crit');
    ev(g, 'surg', `${p.name}: ${msg}`, pid, outcome === 'success' ? 'good' : 'warn');
    return { outcome, msg };
  };

  // ---------------------------------------------------------------- supplies
  HS.restock = function (g, key, n = 1) {
    const S = HS.SUPPLIES[key];
    n = Math.min(n, S.max - g.supplies[key]);
    if (n <= 0) return { ok: false, msg: 'Fully stocked.' };
    const cost = n * S.cost;
    if (g.funds < cost) return { ok: false, msg: 'Not enough funds.' };
    g.funds -= cost; g.stats.spent += cost; g.supplies[key] += n;
    return { ok: true, msg: `Ordered ${n} × ${S.n} for ${HS.money(cost)}` };
  };
  HS.reserveBed = function (g, pid, bedId) {
    const p = P(g, pid); if (!p || p.loc !== 'inbound') return { ok: false };
    const bed = g.beds.er.find((b) => b.id === bedId && !b.pid);
    if (!bed) return { ok: false, msg: 'Bed not free.' };
    p.reserved = bedId; bed.pid = pid;
    return { ok: true, msg: `${bedId} held for ${p.name}` };
  };

  HS.summary = function (g) {
    const alive = Object.values(g.patients).filter((p) => !p.dead && p.loc !== 'gone');
    return { patients: alive.length, waiting: alive.filter((p) => p.loc === 'waiting').length, inbound: g.inbound.length };
  };

  // ---------------------------------------------------------------- operating room
  HS.toOR = function (g, pid, sid) {
    const p = P(g, pid), S = HS.SURGERIES[sid];
    if (!p || p.dead || !S) return { ok: false, msg: 'Invalid.' };
    if (p.arrest) return { ok: false, msg: 'Patient is in arrest!' };
    const bed = g.beds.or.find((b) => !b.pid && !!b.cath === !!S.cath);
    if (!bed) return { ok: false, msg: S.cath ? 'Cath lab is busy.' : 'Both operating rooms are busy.' };
    p.sevAtOp = p.sev;
    const r = HS.place(g, pid, 'or', bed.id);
    if (!r.ok) return r;
    p.onMonitor = true;
    return { ok: true, msg: `${p.name} → ${bed.id}`, bed: bed.id };
  };

  // ---------------------------------------------------------------- save / load
  HS.serialize = (g) => JSON.stringify(g, (k, v) => (k === 'condDef' ? undefined : v));
  HS.deserialize = (txt) => {
    const g = JSON.parse(txt);
    for (const id in g.patients) g.patients[id].condDef = HS.CONDS[g.patients[id].cond];
    g.events = [];
    return g;
  };

})(typeof globalThis !== 'undefined' ? globalThis : window);
