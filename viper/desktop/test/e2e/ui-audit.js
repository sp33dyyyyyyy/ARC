// Pixel-level UI audit of the real VIPER window. For every visible button-like control it
// captures the rendered pixels and measures where the label's ink actually sits relative to
// the control's centre (catches labels that render above/below centre because of font
// metrics), and checks for text overflowing its control, overlapping controls, and
// content that does not fit the window. Used by viper-e2e.js and runnable on its own:
//   xvfb-run node test/e2e/ui-audit.js     (source tree, development)
'use strict';
const path = require('node:path');
const fs = require('node:fs');

const CONTROLS = 'button, .btn, .nav-item, .tag, [role="tab"], .suggest button';

/** Collect geometry of visible controls in the renderer. */
const collect = (win) => win.evaluate((sel) => {
  const out = []; const vw = innerWidth; const vh = innerHeight;
  for (const el of document.querySelectorAll(sel)) {
    if (el.closest('.wizard') && !document.querySelector('.wizard')) continue;
    const r = el.getBoundingClientRect(); const cs = getComputedStyle(el);
    if (r.width < 10 || r.height < 10 || cs.visibility === 'hidden' || +cs.opacity < 0.5 || r.bottom <= 0 || r.top >= vh || r.right <= 0 || r.left >= vw) continue;
    if (el.classList.contains('busy') || el.disabled) continue;
    const cx = r.left + r.width / 2; const cy = r.top + r.height / 2;
    const top = document.elementFromPoint(Math.min(vw - 1, Math.max(0, cx)), Math.min(vh - 1, Math.max(0, cy)));
    if (!top || !(el === top || el.contains(top))) continue; // covered by something else
    if (r.top < 0 || r.bottom > vh) continue; // partly scrolled out of view
    const text = (el.innerText || '').trim().replace(/\s+/g, ' ');
    // label overflow: any text-bearing child extends beyond the control
    let overflow = el.scrollWidth > el.clientWidth + 1 && cs.overflowX !== 'visible';
    for (const c of el.querySelectorAll('*')) { const cr = c.getBoundingClientRect(); if (cr.width && (cr.right > r.right + 1 || cr.left < r.left - 1) && (c.innerText || '').trim()) overflow = true; }
    // Regression guard: text placed straight into a control (not via the .lbl wrapper) is not optically centred.
    const bare = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    const ta = cs.textAlign; const jc = cs.justifyContent;
    const centeredH = el.matches('.btn, .tag, .seg button, .suggest button') || ((ta === 'center' || jc === 'center') && !el.matches('.nav-item'));
    const lb = el.querySelector(':scope > .lbl')?.getBoundingClientRect();
    const ic = el.querySelector(':scope > svg')?.getBoundingClientRect(); const gap = parseFloat(cs.columnGap) || 0;
    out.push({ bare, iconW: ic && ic.width && lb ? -(ic.width + gap) : 0, lx0: lb && lb.width ? lb.left : null, lx1: lb && lb.width ? lb.right : null, text: text.slice(0, 40), cls: (el.className && typeof el.className === 'string' ? el.className : el.tagName).slice(0, 40), x: r.left, y: r.top, w: r.width, h: r.height, overflow, centeredH, hasText: !!text });
  }
  // Collapsed controls: switches, inputs and selects squeezed below a usable size.
  const collapsed = [];
  for (const el of document.querySelectorAll('.switch, input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=range]), select, textarea')) {
    // display:none / hidden ancestors produce no client rects; a 0×0 box that is still rendered is collapsed.
    const r = el.getBoundingClientRect(); if (!el.getClientRects().length || getComputedStyle(el).visibility === 'hidden' || el.closest('[hidden], .hidden')) continue;
    if (r.bottom <= 0 || r.top >= vh) continue;
    const minW = el.matches('.switch') ? 30 : 40;
    if (r.width < minW || r.height < 14) collapsed.push(`${el.matches('.switch') ? 'switch' : el.tagName.toLowerCase()} ${Math.round(r.width)}×${Math.round(r.height)} px near "${(el.closest('.li, .field, label, .panel')?.innerText || '').trim().split('\n')[0].slice(0, 40)}"`);
  }
  // Visible placeholder leaks such as "null", "undefined" or "NaN" in rendered text.
  const leaks = []; const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = tw.nextNode(); n; n = tw.nextNode()) { const t = n.textContent; if (/\b(null|undefined|NaN)\b|\[object Object\]/.test(t) && n.parentElement?.getClientRects().length && !n.parentElement.closest('textarea, pre, code, .mono, .md')) leaks.push(t.trim().slice(0, 60)); }
  return { collapsed, leaks, controls: out, docOverflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1, viewOverflowX: (() => { const v = document.querySelector('#view'); return v ? v.scrollWidth > v.clientWidth + 1 : false; })(), vw, vh, dpr: devicePixelRatio };
}, CONTROLS);

/** Measure ink position of each control from a real capture of the window (main process). */
async function measure(app, controls, dpr) {
  return app.evaluate(async ({ BrowserWindow }, { controls, dpr }) => {
    const w = global.viperDiagnostics?.mainWindow?.() || BrowserWindow.getAllWindows()[0];
    const img = await w.webContents.capturePage();
    const { width, height } = img.getSize(); const bmp = img.toBitmap(); // BGRA
    const sx = width / (w.getContentBounds().width || width);
    const px = (x, y) => { const i = (y * width + x) * 4; return [bmp[i + 2], bmp[i + 1], bmp[i]]; };
    const res = [];
    for (const c of controls) {
      const x0 = Math.round(c.x * sx); const y0 = Math.round(c.y * sx); const W = Math.round(c.w * sx); const H = Math.round(c.h * sx);
      const inset = Math.max(2, Math.round(2 * sx));
      if (x0 < 0 || y0 < 0 || x0 + W > width || y0 + H > height || W < inset * 4 || H < inset * 4) continue;
      // background = most common colour along the inner edge
      const counts = new Map();
      for (let x = x0 + inset; x < x0 + W - inset; x += 2) for (const y of [y0 + inset, y0 + H - inset - 1]) { const k = px(x, y).join(','); counts.set(k, (counts.get(k) || 0) + 1); }
      const bg = [...counts.entries()].sort((a, b) => b[1] - a[1])[0][0].split(',').map(Number);
      // Ink per row. The label's vertical extent is its main ink band: rows with at least 20% of
      // the densest row's ink. That excludes sparse descender tails (g, p, y), which optical
      // centring (cap height to baseline) deliberately ignores, as type designers do.
      const rows = []; let left = -1; let right = -1;
      // Measure the label's own pixels (its horizontal span) against the control's vertical centre.
      const xa = c.lx0 != null ? Math.max(x0 + inset, Math.floor(c.lx0 * sx)) : x0 + inset;
      const xb = c.lx1 != null ? Math.min(x0 + W - inset, Math.ceil(c.lx1 * sx)) : x0 + W - inset;
      for (let y = y0 + inset; y < y0 + H - inset; y++) {
        let n = 0;
        for (let x = xa; x < xb; x++) {
          const p = px(x, y); if (Math.abs(p[0] - bg[0]) + Math.abs(p[1] - bg[1]) + Math.abs(p[2] - bg[2]) < 120) continue;
          n++; if (left < 0 || x < left) left = x; if (x > right) right = x;
        }
        rows.push([y, n]);
      }
      const peak = Math.max(0, ...rows.map((r) => r[1]));
      if (!peak) continue;
      // Cap top = first row with ink; baseline = last row of the dense band (excludes descenders).
      const band = rows.filter((r) => r[1] >= peak * 0.2);
      const top = rows.find((r) => r[1] > 0)[0]; const bottom = band[band.length - 1][0];
      const dy = ((top + bottom) / 2 - (y0 + (H - 1) / 2)) / sx;
      const dx = c.lx0 != null ? (((c.lx0 + c.lx1) / 2) - (c.x + c.w / 2)) + (c.iconW || 0) / 2 : ((left + right) / 2 - (x0 + (W - 1) / 2)) / sx;
      res.push({ ...c, dy: Math.round(dy * 10) / 10, dx: Math.round(dx * 10) / 10, inkH: Math.round((bottom - top + 1) / sx) });
    }
    return res;
  }, { controls, dpr });
}

/** Overlap between distinct, non-nested controls. */
function overlaps(list) {
  const out = [];
  for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
    const a = list[i]; const b = list[j];
    const ix = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x); const iy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
    const nested = (a.x <= b.x && a.y <= b.y && a.x + a.w >= b.x + b.w && a.y + a.h >= b.y + b.h) || (b.x <= a.x && b.y <= a.y && b.x + b.w >= a.x + a.w && b.y + b.h >= a.y + a.h);
    if (ix > 2 && iy > 2 && !nested) out.push(`"${a.text || a.cls}" overlaps "${b.text || b.cls}"`);
  }
  return out;
}

/**
 * Audit every page at several window sizes. Returns { issues, checked, worst, sizes }.
 * TOL: a label whose ink centre is more than 1.5 px from the control's centre is reported.
 */
async function auditApp(app, win, { pages, sizes = [[1440, 900], [1100, 720], [920, 600]], outDir, tol = 1.5 } = {}) {
  const issues = []; let checked = 0; const offsets = [];
  const setSize = (w, h) => app.evaluate(({ BrowserWindow }, [w, h]) => { const x = global.viperDiagnostics?.mainWindow?.() || BrowserWindow.getAllWindows()[0]; if (x.isMaximized()) x.unmaximize(); x.setContentSize(w, h); }, [w, h]);
  for (const [w, h] of sizes) {
    await setSize(w, h); await win.waitForTimeout(700);
    for (const page of pages) {
      await win.evaluate((m) => window.viperApp.go(m), page); await win.waitForTimeout(900);
      const g = await collect(win);
      if (g.docOverflowX) issues.push({ size: `${w}x${h}`, page, kind: 'layout', msg: 'window scrolls horizontally (content wider than the window)' });
      if (g.viewOverflowX) issues.push({ size: `${w}x${h}`, page, kind: 'layout', msg: 'page content wider than its panel (horizontal scrollbar)' });
      for (const c of g.collapsed) issues.push({ size: `${w}x${h}`, page, kind: 'collapsed', msg: `control squeezed too small: ${c}` });
      for (const l of g.leaks) issues.push({ size: `${w}x${h}`, page, kind: 'text', msg: `placeholder text shown to the user: "${l}"` });
      for (const c of g.controls) if (c.bare) issues.push({ size: `${w}x${h}`, page, kind: 'vertical', msg: `"${c.text}" label is not wrapped for optical centring (built without ui.js h())` });
      for (const c of g.controls) if (c.overflow) issues.push({ size: `${w}x${h}`, page, kind: 'overflow', msg: `label overflows its control: "${c.text}"` });
      for (const o of overlaps(g.controls)) issues.push({ size: `${w}x${h}`, page, kind: 'overlap', msg: o });
      const m = await measure(app, g.controls.filter((c) => c.hasText || /icon/.test(c.cls)), g.dpr);
      for (const c of m) {
        checked++; offsets.push(Math.abs(c.dy));
        if (Math.abs(c.dy) > tol) issues.push({ size: `${w}x${h}`, page, kind: 'vertical', msg: `"${c.text || c.cls}" label ${c.dy < 0 ? 'above' : 'below'} centre by ${Math.abs(c.dy)} px` });
        if (c.centeredH && Math.abs(c.dx) > tol + 0.5) issues.push({ size: `${w}x${h}`, page, kind: 'horizontal', msg: `"${c.text || c.cls}" label off-centre horizontally by ${c.dx} px` });
      }
      if (outDir && (w === sizes[sizes.length - 1][0])) await win.screenshot({ path: path.join(outDir, `ui-${page}-${w}x${h}.png`) });
    }
  }
  await app.evaluate(({ BrowserWindow }) => { const x = global.viperDiagnostics?.mainWindow?.() || BrowserWindow.getAllWindows()[0]; x.setContentSize(1440, 900); });
  // de-duplicate identical findings across pages/sizes
  const seen = new Map();
  for (const i of issues) { const k = `${i.kind}|${i.msg}`; if (!seen.has(k)) seen.set(k, { ...i, where: [] }); seen.get(k).where.push(`${i.page}@${i.size}`); }
  offsets.sort((a, b) => a - b);
  return { issues: [...seen.values()], raw: issues.length, checked, medianOffset: offsets[Math.floor(offsets.length / 2)] || 0, p95Offset: offsets[Math.floor(offsets.length * 0.95)] || 0, maxOffset: offsets[offsets.length - 1] || 0 };
}

module.exports = { auditApp };

// ---------- standalone (development) ----------
if (require.main === module) {
  let pw; try { pw = require('playwright'); } catch { pw = require('playwright-core'); }
  const os = require('node:os');
  (async () => {
    const out = process.env.AUDIT_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'viper-ui-'));
    fs.mkdirSync(out, { recursive: true });
    const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'viper-ui-data-'));
    const app = await pw._electron.launch({ executablePath: require('electron'), args: [path.join(__dirname, '..', '..'), '--no-sandbox'], env: { ...process.env, VIPER_DATA_DIR: dataDir, NODE_OPTIONS: '' } });
    const win = await app.firstWindow();
    win.on('console', (m) => { if (m.type() === 'error') console.log('CONSOLE ERROR', m.text(), m.location()?.url); });
    win.on('pageerror', (e) => console.log('PAGE ERROR', e.message));
    await win.waitForFunction(() => window.viperNative?.token && document.querySelector('.nav-item'), null, { timeout: 60000 });
    await win.evaluate(async () => { await fetch('/api/v1/setup/complete', { method: 'POST', headers: { Authorization: `Bearer ${window.viperNative.token}`, 'Content-Type': 'application/json' }, body: '{}' }); });
    await win.reload(); await win.waitForFunction(() => document.querySelector('canvas.core'), null, { timeout: 30000 });
    const pages = await win.evaluate(() => [...document.querySelectorAll('.nav-item[data-mode]')].map((b) => b.dataset.mode));
    const r = await auditApp(app, win, { pages, outDir: out });
    fs.writeFileSync(path.join(out, 'ui-audit.json'), JSON.stringify(r, null, 2));
    console.log(`checked ${r.checked} control renders · median |dy| ${r.medianOffset}px · p95 ${r.p95Offset}px · max ${r.maxOffset}px · ${r.issues.length} distinct issues (${r.raw} total)`);
    const byKind = {}; for (const i of r.issues) byKind[i.kind] = (byKind[i.kind] || 0) + 1; console.log(byKind);
    for (const i of r.issues.slice(0, 60)) console.log(`${i.kind.padEnd(10)} ${i.msg}  [${i.where.slice(0, 3).join(', ')}${i.where.length > 3 ? ` +${i.where.length - 3}` : ''}]`);
    console.log('out', out);
    await app.close();
  })().catch((e) => { console.error(e); process.exit(1); });
}
