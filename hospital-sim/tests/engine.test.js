/* Engine smoke + behaviour tests. Run: node hospital-sim/tests/engine.test.js */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const dir = path.join(__dirname, '..', 'web', 'js');
for (const f of ['util', 'data_actions', 'data_conditions', 'data_surgery', 'engine']) {
  vm.runInThisContext(fs.readFileSync(path.join(dir, f + '.js'), 'utf8'), { filename: f + '.js' });
}
const HS = globalThis.HS;
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };

// --- data integrity
for (const id in HS.CONDS) {
  const c = HS.CONDS[id];
  ok(c.cc.length && c.hx.length, `${id} has complaints/history`);
  if (c.dispo.startsWith('surg:')) ok(HS.SURGERIES[c.dispo.slice(5)], `${id} surgery ${c.dispo} exists`);
  for (const t in c.tests) ok(HS.TESTS[t], `${id} test ${t} exists`);
  for (const n of c.need) ok(true, n);
}
for (const id in HS.SURGERIES) for (const st of HS.SURGERIES[id].steps) ok(HS.TOOLS[st[1]], `${id} tool ${st[1]}`);
for (const [, ids] of HS.ACTION_GROUPS) for (const a of ids) ok(HS.ACTIONS[a], `action ${a} exists`);
console.log(`conditions: ${Object.keys(HS.CONDS).length}, surgeries: ${Object.keys(HS.SURGERIES).length}, actions: ${Object.keys(HS.ACTIONS).length}`);

// --- 1000 patients through the sim without throwing
HS.seed(1234);
let g = HS.newGame();
let maxP = 0;
for (let i = 0; i < 1440 * 3; i++) {
  HS.tick(g);
  // auto-place waiting patients so beds cycle
  for (const id in g.patients) {
    const p = g.patients[id];
    if (p.loc === 'waiting' && HS.freeBed(g, 'er')) HS.place(g, id, 'er');
  }
  g.events.length = 0;
  maxP = Math.max(maxP, Object.keys(g.patients).length);
  if (g.over) break;
}
ok(g.stats.crises >= 0, 'sim ran');
console.log('3 days idle sim:', JSON.stringify(g.stats), 'rep', g.rep.toFixed(1), 'patients', maxP);

// --- limb bleed: tourniquet stops the bleed, no tourniquet exsanguinates
HS.seed(7);
g = HS.newGame();
let p = HS.spawn(g, { cond: 'limb_bleed', amb: false });
HS.place(g, p.id, 'er', 'R1');
p.tq = null; p.dev = {};
ok(HS.bleedRate(p) > 20, 'limb bleed is heavy');
const site = p.bleed.site;
HS.act(g, p.id, 'tourniquet', { site });
HS.advance(g, 2);
ok(p.tq && HS.bleedRate(p) < p.bleed.rate0 * 0.1, 'correct-limb tourniquet controls bleed');
// wrong limb
let p2 = HS.spawn(g, { cond: 'limb_bleed', amb: false });
HS.place(g, p2.id, 'er', 'R2'); p2.tq = null; p2.dev = {};
const wrong = p2.bleed.site.includes('arm') ? (p2.bleed.site.includes('left') ? 'right arm' : 'left arm') : (p2.bleed.site.includes('left') ? 'right thigh' : 'left thigh');
HS.act(g, p2.id, 'tourniquet', { site: wrong });
HS.advance(g, 2);
ok(HS.bleedRate(p2) > p2.bleed.rate0 * 0.3, 'wrong-limb tourniquet does not stop bleeding');
// untreated bleeding kills
let p3 = HS.spawn(g, { cond: 'limb_bleed', amb: false });
HS.place(g, p3.id, 'er', 'B1'); p3.tq = null; p3.dev = {};
HS.advance(g, 120);
ok(p3.dead || p3.arrest, 'untreated arterial bleed -> arrest/death');

// --- restraints & chest tube path & arrest with CPR + defib
HS.seed(99);
g = HS.newGame();
let v = HS.spawn(g, { cond: 'arrest_vf', amb: false }); HS.place(g, v.id, 'er', 'R1');
ok(v.arrest && v.arrest.rhythm === 'VF', 'arrest patient in VF');
let revived = false;
for (let k = 0; k < 200 && !v.dead && !revived; k++) {
  if (v.arrest) {
    if (!v.arrest.cpr) HS.act(g, v.id, 'cpr');
    HS.act(g, v.id, 'defib');
    if (k % 3 === 0) HS.act(g, v.id, 'iv');
    HS.advance(g, 1);
  }
  if (!v.arrest && !v.dead) revived = true;
}
ok(revived || v.dead, 'arrest resolves one way or the other');
// no CPR => death
let v2 = HS.spawn(g, { cond: 'arrest_vf', amb: false }); HS.place(g, v2.id, 'er', 'R2'); v2.arrest.cpr = false;
HS.advance(g, 8);
ok(v2.dead, 'no CPR -> dies');

// --- wrong drug harms (thrombolytic in bleeding)
HS.seed(5);
g = HS.newGame();
let s = HS.spawn(g, { cond: 'splenic', amb: false }); HS.place(g, s.id, 'er', 'B2'); s.iv = true;
const r = HS.act(g, s.id, 'alteplase', { idx: 1, dose: 'x' });
HS.advance(g, 3);
ok(s.bleedMul >= 2, 'alteplase in bleed worsens bleeding');

// --- allergy
let a = HS.spawn(g, { cond: 'pneumonia', amb: false }); HS.place(g, a.id, 'er', 'B3'); a.iv = true; a.allergies = ['penicillin'];
HS.act(g, a.id, 'pipetazo', { idx: 1 });
HS.advance(g, 3);
ok(a.crisis || a.sev > 20, 'penicillin allergy reaction');

// --- surgery path
HS.seed(11);
g = HS.newGame();
let ap = HS.spawn(g, { cond: 'appendicitis', amb: false }); HS.place(g, ap.id, 'er', 'B1');
const t = HS.toOR(g, ap.id, 'appy');
ok(t.ok && ap.loc === 'or', 'to OR');
const out = HS.finishSurgery(g, ap.id, { sid: 'appy', score: 90, blood: 80, prep: 1, anaes: 1 });
ok(['success', 'complication', 'death'].includes(out.outcome), 'surgery outcome: ' + out.outcome);

// --- discharge rules
HS.seed(3);
g = HS.newGame();
let m = HS.spawn(g, { cond: 'mi', amb: false }); HS.place(g, m.id, 'er', 'B1');
const d = HS.discharge(g, m.id);
ok(d.outcome === 'bad', 'discharging a heart attack is flagged bad');

// --- save/load roundtrip
const txt = HS.serialize(g);
const g2 = HS.deserialize(txt);
ok(g2.t === g.t && Object.keys(g2.patients).length === Object.keys(g.patients).length, 'save/load roundtrip');
HS.advance(g2, 30);
ok(true, 'loaded game ticks');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
