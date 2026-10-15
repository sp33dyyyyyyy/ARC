/* Balance check: a competent scripted "doctor" should keep the hospital alive. Run: node hospital-sim/tests/bot.test.js [seed] [diff] */
const fs = require('fs'), path = require('path'), vm = require('vm');
const dir = path.join(__dirname, '..', 'web', 'js');
for (const f of ['util', 'data_actions', 'data_conditions', 'data_surgery', 'engine']) vm.runInThisContext(fs.readFileSync(path.join(dir, f + '.js'), 'utf8'), { filename: f });
const HS = globalThis.HS;
const seed = +process.argv[2] || 42, diff = +process.argv[3] || 1;
HS.seed(seed);
const g = HS.newGame({ diff });
const TAG = { antiplatelet: 'aspirin', analgesia: 'fentanyl', analgesia_mild: 'paracetamol', o2: 'o2', abx: 'ceftriaxone', abx_atyp: 'azithro', abx_anaer: 'metro', abx_mrsa: 'vanco', fluids: 'fluids', anticoag: 'heparin',
  bronchodilator: 'salbutamol', bronchodilator2: 'ipratropium', steroid: 'steroid', diuretic: 'furosemide', nitrate: 'nitro', thrombolytic: 'alteplase', antihypertensive: 'labetalol', anticonvulsant: 'lorazepam',
  antiemetic: 'ondansetron', insulin: 'insulin', dextrose: 'dextrose', epi: 'epi_im', naloxone: 'naloxone', sedation: 'midazolam', restraint: 'restraints', mag: 'magnesium', oxytocin: 'oxytocin', txa: 'txa',
  blood: 'prbc', binder: 'binder', collar: 'collar', splint: 'splint', chestseal: 'chestseal', decompress: 'needle', chesttube: 'chesttube', ngt: 'ngt', cool: 'cool', warm: 'warm', pressure: 'pressure', sutured: 'suturelac', reduced: 'reduce',
  bvm_or_o2: 'bvm', pressor_if_low: 'norepi', svt_fix: 'adenosine' };
const isOk = (p, a) => { const aa = HS.ACTIONS[a]; return true; };
let seenMinute = {};
function doctor(p) {
  const c = p.condDef;
  if (p.arrest) {
    const a = p.arrest;
    if (!a.cpr) HS.act(g, p.id, 'cpr');
    if (!p.iv && !p.io && !p.pending.some((x) => x.id === 'io')) HS.act(g, p.id, 'io');
    if (a.rhythm === 'VF') HS.act(g, p.id, 'defib');
    else if (g.t - a.lastEpi > 4 && p.iv) HS.act(g, p.id, 'epi_iv', { idx: 1 });
    if (a.cause === 'hypovolemia' && p.iv) HS.act(g, p.id, 'prbc');
    if (a.cause === 'tension') HS.act(g, p.id, 'needle');
    return;
  }
  if (!p.onMonitor) HS.act(g, p.id, 'monitor');
  // bleeding first
  if (p.bleed && !p.bleed.stopped && !p.cured) {
    if (p.bleed.kind === 'limb' && !p.tq) HS.act(g, p.id, 'tourniquet', { site: p.bleed.site });
    if (p.bleed.kind === 'pelvis' && !p.dev.binder) HS.act(g, p.id, 'binder');
    if (p.bleed.kind === 'scalp' && !p.dev.pressure) HS.act(g, p.id, 'pressure');
  }
  if (p.crisis) {
    const t = p.crisis.type;
    const m = { anaphylaxis: ['epi_im'], seizure: ['lorazepam'], airway: ['suction', 'jaw'], tension: ['needle'], hemorrhage: ['pressure', 'prbc'], hypoglycemia: ['dextrose'], violence: ['restraints', 'midazolam'], septic_crash: ['fluids', 'norepi'] }[t];
    for (const a of m) { if (HS.ACTIONS[a].group === 'drug' && !p.iv) HS.act(g, p.id, 'iv'); HS.act(g, p.id, a, { idx: HS.ACTIONS[a].stdIdx }); }
    return;
  }
  if (!p.airwayClear) { HS.act(g, p.id, 'heimlich'); HS.act(g, p.id, 'suction'); }
  const sev = HS.sevEff(p);
  if ((sev > 35 || p.bleed) && !p.iv && !p.io && !p.pending.some((x) => x.id === 'iv')) HS.act(g, p.id, sev > 70 ? 'io' : 'iv');
  if (p.cond === 'choking' && !p.airwayClear && g.t - p.t0 > 3) HS.act(g, p.id, 'cric');
  if (p.cond === 'gsw_chest' && p.tensionPtx) HS.act(g, p.id, 'needle');
  // needs
  for (const tag of c.need) {
    if (HS.tagSat(p, tag)) continue;
    let aid = TAG[tag];
    if (!aid) continue;
    if (tag === 'o2' && p.o2) continue;
    if (tag === 'thrombolytic' && p.cond !== 'stroke') continue;
    if (tag === 'fluids' && p.cond === 'chf') continue;
    if (tag === 'blood' && p.pending.some((x) => x.id === 'prbc')) continue;
    if (p.pending.some((x) => x.id === aid)) continue;
    if (tag === 'analgesia' && p.cond === 'aaa') aid = 'fentanyl';
    const A = HS.ACTIONS[aid];
    if (A.group === 'drug' && A.route === 'iv' && !p.iv && !p.io) continue;
    if (A.allergy && p.allergies.includes(A.allergy)) { if (aid === 'ceftriaxone') aid = 'vanco'; else if (aid === 'amoxclav') aid = 'azithro'; else continue; }
    if (p.cond === 'chf' && aid === 'nitro' && p.v.sbp < 100) continue;
    if (A.surgery) { HS.act(g, p.id, aid, { auto: true }); continue; }
    HS.act(g, p.id, aid, { idx: A.stdIdx, site: p.bleed && p.bleed.site });
  }
}
let log = { surg: {}, home: 0, adm: 0 };
function dispose(p) {
  const c = p.condDef;
  if (p.dead || p.arrest || p.loc === 'gone') return;
  const nm = HS.needsMet(p);
  p.dx = p.cond; // assume correct dx
  if (c.dispo.startsWith('surg:') && !p.cured && p.loc !== 'or') {
    if (p.pending.length > 3 || nm < 0.7 && HS.sevEff(p) < 80) { }
    const sid = c.dispo.slice(5);
    const r = HS.toOR(g, p.id, sid);
    if (r.ok) {
      p.iv = true; HS.advance(g, 6);
      const S = HS.SURGERIES[sid]; const sc = 70 + Math.random() * 25;
      for (const st of S.steps) { HS.advance(g, st[2]); p.blood += st[3] * Math.pow(1 - sc / 100, 1.2); }
      const out = HS.finishSurgery(g, p.id, { sid, score: sc, blood: 0, prep: 0.9, anaes: 1 });
      log.surg[out.outcome] = (log.surg[out.outcome] || 0) + 1;
    }
    return;
  }
  if (p.loc === 'er') {
    const ready = (nm >= 0.99 || g.t - (p.seenByDoc || g.t) > 90) && !p.crisis && (g.t - (p.seenByDoc || g.t) > 25) && p.sev < 40;
    if (c.dispo === 'home' || (c.homeIfSev && p.sev <= c.homeIfSev)) { if (ready && p.sev < 30) { HS.discharge(g, p.id); log.home++; } }
    else if (ready || p.cured) {
      const kind = c.dispo === 'icu' || p.cured && p.sev > 45 ? 'icu' : 'ward';
      const r = HS.admit(g, p.id, kind) ; if (!r.ok) HS.admit(g, p.id, kind === 'icu' ? 'ward' : 'icu'); else log.adm++;
    }
  }
}
const end = HS.DAY0_START + 1440 * 3;
while (g.t < end && !g.over) {
  HS.tick(g);
  for (const e of g.events.splice(0)) { /* ignore */ }
  const ps = Object.values(g.patients).filter((p) => !p.dead && p.loc !== 'gone');
  // triage: sickest first into free beds
  const wait = ps.filter((p) => p.loc === 'waiting').sort((a, b) => a.esi - b.esi);
  for (const p of wait) { if (HS.freeBed(g, 'er', p.crit || p.sev >= 55)) HS.place(g, p.id, 'er', HS.freeBed(g, 'er', p.crit || p.sev >= 55).id); }
  // doctor reacts with 1-minute reaction lag, but works on at most ~2 patients per minute (human limits)
  const er = ps.filter((p) => p.loc === 'er' || p.loc === 'ward' || p.loc === 'icu').sort((a, b) => (b.arrest ? 100 : 0) + (b.crisis ? 50 : 0) + HS.sevEff(b) - ((a.arrest ? 100 : 0) + (a.crisis ? 50 : 0) + HS.sevEff(a)));
  for (const p of er.slice(0, 2)) doctor(p);
  if (g.t % 10 === 0) for (const p of er) dispose(p);
  if (g.t % 120 === 0) for (const k of ['tourniquet', 'blood', 'iv', 'dressing', 'needle', 'ett', 'chesttube']) HS.restock(g, k, 3);
}
const s = g.stats;
console.log(`seed ${seed} diff ${diff}: day ${HS.dayOf(g.t)} rep ${g.rep.toFixed(0)} funds ${Math.round(g.funds)} | seen ${s.seen} saved ${s.saved} died ${s.died} crises ${s.crisesOk}/${s.crises} surg ${s.surgOk}/${s.surgeries} sued ${s.sued} lwbs ${s.lwbs} | outcomes ${JSON.stringify(log)}`);
const causes = {};
for (const id in g.patients) { const p = g.patients[id]; if (p.dead) { const k = `${p.cond} @${p.loc === 'gone' ? 'gone' : p.loc} (${p.cause})`; causes[k] = (causes[k] || 0) + 1; } }
if (process.env.CAUSES) console.log(causes);
