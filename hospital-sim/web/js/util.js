/* Mercy General ER — shared helpers. Everything hangs off globalThis.HS so the engine runs in a browser, WebView or node. */
(function (G) {
  const HS = (G.HS = G.HS || {});

  // ---- seedable RNG (mulberry32) ----
  let _s = (Date.now() ^ 0x9e3779b9) >>> 0;
  HS.seed = (s) => { _s = s >>> 0; };
  HS.rand = () => {
    _s = (_s + 0x6d2b79f5) >>> 0;
    let t = _s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  HS.ri = (a, b) => a + Math.floor(HS.rand() * (b - a + 1));
  HS.rf = (a, b, d = 1) => +(a + HS.rand() * (b - a)).toFixed(d);
  HS.pick = (arr) => arr[Math.floor(HS.rand() * arr.length)];
  HS.chance = (p) => HS.rand() < p;
  HS.clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  HS.shuffle = (arr) => {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(HS.rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  };
  HS.wpick = (items, wf) => {
    let tot = 0;
    for (const it of items) tot += wf(it);
    if (tot <= 0) return null;
    let r = HS.rand() * tot;
    for (const it of items) { r -= wf(it); if (r <= 0) return it; }
    return items[items.length - 1];
  };

  // ---- clock ----
  HS.DAY0_START = 7 * 60; // game starts 07:00
  HS.hourOf = (t) => Math.floor(((t % 1440) + 1440) % 1440 / 60);
  HS.fmtTime = (t) => {
    const m = ((t % 1440) + 1440) % 1440;
    return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(Math.floor(m % 60)).padStart(2, '0');
  };
  HS.dayOf = (t) => Math.floor(t / 1440) + 1;
  HS.fmtDur = (m) => {
    m = Math.max(0, Math.round(m));
    if (m < 60) return m + ' min';
    return Math.floor(m / 60) + 'h ' + String(m % 60).padStart(2, '0') + 'm';
  };
  HS.money = (v) => (v < 0 ? '-$' : '$') + Math.abs(Math.round(v)).toLocaleString('en-US');

  // ---- names ----
  const FIRST_M = ['James','Robert','Michael','David','Carlos','Daniel','Marcus','Tyrone','Wei','Ahmed','Luca','Samuel','Peter','Jamal','Kevin','Miguel','Henry','Oscar','Raj','Tom','Andre','Victor','Ethan','Noah','Liam','Mateo'];
  const FIRST_F = ['Mary','Linda','Sarah','Jessica','Maria','Aisha','Emily','Priya','Grace','Hannah','Olivia','Chloe','Fatima','Rosa','Nina','Dana','Keisha','Yuki','Ella','Sofia','Ruth','Amara','Julia','Mia','Ava'];
  const LAST = ['Smith','Johnson','Garcia','Nguyen','Patel','Brown','Davis','Martinez','Kim','Okafor','Rossi','Cohen','Walker','Lopez','Hughes','Baker','Singh','Ortiz','Reyes','Murphy','Foster','Young','Bell','Cruz','Hayes','Dunn'];
  HS.makeName = (sex) => HS.pick(sex === 'F' ? FIRST_F : FIRST_M) + ' ' + HS.pick(LAST);
})(typeof globalThis !== 'undefined' ? globalThis : window);
