// UI primitives: element builder, icons, toasts, modals, confirmations, markdown, formatting.
export function h(tag, attrs = {}, ...children) {
  const [name, ...cls] = tag.split('.');
  const el = name === 'svg' || attrs.__svg ? document.createElementNS('http://www.w3.org/2000/svg', name) : document.createElement(name || 'div');
  if (cls.length) el.setAttribute('class', cls.join(' '));
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false || k === '__svg') continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'class') el.setAttribute('class', [el.getAttribute('class'), v].filter(Boolean).join(' '));
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k === 'html') el.innerHTML = v;
    else if (k in el && !(el instanceof SVGElement) && typeof v !== 'string') el[k] = v;
    else if (k === 'value' || k === 'checked') el[k] = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  // Text inside controls goes in a .lbl span, which the stylesheet trims to cap height and
  // baseline so labels are optically centred whatever the font's ascent/descent (see viper.css).
  const control = el.tagName === 'BUTTON' || /(^|\s)(btn|tag|nav-item)(\s|$)/.test(el.getAttribute('class') || '');
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    if (c instanceof Node) el.append(c);
    else if (control && String(c).trim()) el.append(Object.assign(document.createElement('span'), { className: 'lbl', textContent: String(c) }));
    else el.append(document.createTextNode(String(c)));
  }
  return el;
}
export const $ = (s, r = document) => r.querySelector(s);
export const $$ = (s, r = document) => [...r.querySelectorAll(s)];
export function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }

// Line icons (24x24, stroke). Original set drawn for VIPER.
const P = {
  home: 'M4 11 12 4l8 7M6 9.5V20h12V9.5',
  chat: 'M4 5h16v11H9l-5 4z',
  voice: 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5 11a7 7 0 0 0 14 0M12 18v3',
  image: 'M3 5h18v14H3zM3 16l5-5 4 4 3-3 6 6M15.5 9.5h.01',
  code: 'M8 7l-5 5 5 5M16 7l5 5-5 5M13.5 5l-3 14',
  vision: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  research: 'M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13zM15.5 15.5 21 21',
  automation: 'M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z',
  control: 'M3 4h18v12H3zM8 20h8M12 16v4',
  files: 'M6 3h8l4 4v14H6zM14 3v4h4M9 12h6M9 16h6',
  memory: 'M7 4h10v16H7zM4 8h3M4 12h3M4 16h3M17 8h3M17 12h3M17 16h3M10 8h4v8h-4z',
  comms: 'M3 6h18v12H3zM3 6l9 7 9-7',
  system: 'M3 12h4l3-7 4 14 3-7h4',
  plugins: 'M9 3v4M15 3v4M6 7h12v5a6 6 0 0 1-12 0zM12 18v3',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z',
  models: 'M12 3 3 7.5l9 4.5 9-4.5zM3 12l9 4.5 9-4.5M3 16.5 12 21l9-4.5',
  send: 'M4 12 20 4l-6 16-3-7z',
  stop: 'M7 7h10v10H7z',
  plus: 'M12 5v14M5 12h14', x: 'M6 6l12 12M18 6 6 18', check: 'M5 12.5 10 17l9-10',
  pin: 'M9 4h6l-1 5 3 3H7l3-3zM12 12v8', trash: 'M5 7h14M9 7V4h6v3M7 7l1 13h8l1-13', edit: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4',
  download: 'M12 4v11M7 10l5 5 5-5M5 20h14', upload: 'M12 20V9M7 14l5-5 5 5M5 4h14', paperclip: 'M20 11.5 12 19.5a5 5 0 0 1-7-7L13 4.5a3.3 3.3 0 0 1 4.7 4.7L10 17a1.7 1.7 0 0 1-2.3-2.3L15 7.5',
  play: 'M7 5v14l12-7z', pause: 'M8 5v14M16 5v14', refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7', mic: 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5 11a7 7 0 0 0 14 0M12 18v3', micoff: 'M3 3l18 18M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V6a3 3 0 0 0-5.9-.7M5 11a7 7 0 0 0 11.9 5M19 11a7 7 0 0 1-.4 2.3M12 18v3',
  phone: 'M8 2h8a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM11 18h2', bell: 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0', wifi: 'M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0M12 19.5h.01',
  hud: 'M4 4h6v6H4zM14 14h6v6h-6zM14 4h6v6h-6z', panelL: 'M3 4h18v16H3zM9 4v16', panelR: 'M3 4h18v16H3zM15 4v16', copy: 'M8 8h12v12H8zM4 16V4h12',
  min: 'M5 12h14', max: 'M5 5h14v14H5z', camera: 'M3 7h4l2-3h6l2 3h4v13H3zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z', screen: 'M3 4h18v12H3zM8 20h8M12 16v4M7 8h4v4H7z',
  folder: 'M3 6h6l2 2h10v11H3z', file: 'M6 3h8l4 4v14H6zM14 3v4h4', git: 'M6 3v12M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 9a9 9 0 0 1-9 9',
  terminal: 'M3 4h18v16H3zM7 9l3 3-3 3M12 15h5', shield: 'M12 3 4 6v6c0 4.5 3.4 8.3 8 9 4.6-.7 8-4.5 8-9V6z', key: 'M14 10a4 4 0 1 0-4 4l1 1h2v2h2v2h3v-3l-4-4', external: 'M14 4h6v6M20 4l-9 9M18 14v6H4V6h6',
  sparkle: 'M12 3v6M12 15v6M3 12h6M15 12h6', grid: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z', link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
};
export function icon(name, cls = '') {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '16'); svg.setAttribute('height', '16'); svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '1.5'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round'); svg.setAttribute('aria-hidden', 'true');
  if (cls) svg.setAttribute('class', cls);
  const p = document.createElementNS('http://www.w3.org/2000/svg', 'path'); p.setAttribute('d', P[name] || P.sparkle); svg.append(p);
  return svg;
}
export const btn = (label, onClick, { cls = '', ico, title, disabled, type = 'button' } = {}) =>
  h(`button.btn${cls ? '.' + cls.split(' ').join('.') : ''}`, { type, onclick: onClick, title: title || (typeof label === 'string' ? undefined : title), 'aria-label': title || (typeof label === 'string' ? label : undefined), disabled }, ico ? icon(ico) : null, label);
export async function busy(button, fn) {
  button?.classList.add('busy');
  try { return await fn(); } finally { button?.classList.remove('busy'); }
}

// ---------- toasts ----------
export function toast(title, body = '', kind = 'info', ms = 4200) {
  const host = $('#toasts');
  const t = h(`div.toast.${kind}`, { role: kind === 'error' ? 'alert' : 'status' }, h('b', {}, title), body ? h('span', {}, body) : null);
  host.append(t);
  setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 320); }, ms);
  return t;
}
export const toastError = (e, title = 'Something went wrong') => toast(title, e?.message || String(e), 'error', 6500);

// ---------- modal ----------
export function modal({ title, body, actions = [], wide = false, cls = '', onClose, dismissable = true }) {
  const close = () => { scrim.remove(); document.removeEventListener('keydown', onKey); onClose?.(); };
  const onKey = (e) => { if (e.key === 'Escape' && dismissable) close(); };
  const m = h(`div.modal${wide ? '.wide' : ''}${cls ? '.' + cls : ''}`, { role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
    title ? h('h2', {}, title) : null, body,
    actions.length ? h('div.foot', {}, actions.map((a) => btn(a.label, async (ev) => { const r = await busy(ev.currentTarget, () => a.onClick?.()); if (r !== false) close(); }, { cls: a.cls || '' }))) : null);
  const scrim = h('div.scrim', { onclick: (e) => { if (e.target === scrim && dismissable) close(); } }, m);
  document.body.append(scrim);
  document.addEventListener('keydown', onKey);
  setTimeout(() => m.querySelector('input, textarea, select, .btn.primary')?.focus(), 50);
  return { close, el: m };
}
export function ask(title, message, { confirmLabel = 'Confirm', danger = false } = {}) {
  return new Promise((resolve) => {
    modal({ title, body: h('p', { class: 'ink2' }, message), onClose: () => resolve(false), actions: [
      { label: 'Cancel', cls: 'ghost', onClick: () => resolve(false) },
      { label: confirmLabel, cls: danger ? 'danger' : 'primary', onClick: () => resolve(true) },
    ] });
  });
}
export function prompt(title, { label = '', value = '', placeholder = '', multiline = false } = {}) {
  return new Promise((resolve) => {
    const inp = multiline ? h('textarea.input', { rows: 5, placeholder }, value) : h('input.input', { value, placeholder });
    let done = false;
    modal({ title, body: h('label.field', {}, label, inp), onClose: () => { if (!done) resolve(null); }, actions: [
      { label: 'Cancel', cls: 'ghost' }, { label: 'Save', cls: 'primary', onClick: () => { done = true; resolve(inp.value); } },
    ] });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !multiline) { done = true; resolve(inp.value); inp.closest('.scrim').remove(); } });
  });
}

// ---------- form helpers ----------
export function field(label, input, hint) { return h('label.field', {}, h('span', {}, label), input, hint ? h('span.hint', {}, hint) : null); }
export function toggle(checked, onChange, labelText) {
  const inp = h('input', { type: 'checkbox', checked: !!checked, onchange: (e) => onChange(e.target.checked), 'aria-label': labelText || 'toggle' });
  return h('span.switch', {}, inp, h('i'));
}
export function select(options, value, onChange) {
  const s = h('select.input', { onchange: (e) => onChange(e.target.value) }, options.map((o) => { const [v, l] = Array.isArray(o) ? o : [o, o]; return h('option', { value: v, selected: v === value }, l); }));
  return s;
}
export function seg(options, value, onChange) {
  const wrap = h('div.seg', { role: 'group' });
  for (const [v, l] of options) wrap.append(h(`button${v === value ? '.on' : ''}`, { type: 'button', onclick: (ev) => { wrap.querySelectorAll('button').forEach((b) => b.classList.remove('on')); ev.currentTarget.classList.add('on'); onChange(v); } }, l));
  return wrap;
}
export function progress(frac) { return h('div.progress' + (frac == null ? '.indet' : ''), {}, h('i', { style: { width: `${Math.round((frac || 0) * 100)}%` } })); }
export function meter(pct, hot) { return h(`div.meter${hot ? '.hot' : ''}`, {}, h('i', { style: { width: `${Math.max(0, Math.min(100, pct || 0))}%` } })); }

// ---------- formatting ----------
export function bytes(n) { if (n == null || isNaN(n)) return '—'; const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0; while (n >= 1024 && i < 4) { n /= 1024; i++; } return `${n.toFixed(n >= 10 || i === 0 ? 0 : 1)} ${u[i]}`; }
export function ago(ts) { if (!ts) return 'never'; const s = Math.round((Date.now() - ts) / 1000); if (s < 0) return `in ${dur(-s)}`; if (s < 45) return 'just now'; return `${dur(s)} ago`; }
export function dur(s) { if (s < 90) return `${s}s`; if (s < 5400) return `${Math.round(s / 60)} min`; if (s < 129600) return `${Math.round(s / 3600)} h`; return `${Math.round(s / 86400)} d`; }
export function when(ts) { return ts ? new Date(ts).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'; }
export function download(name, text, type = 'text/plain') { const a = h('a', { href: URL.createObjectURL(new Blob([text], { type })), download: name }); document.body.append(a); a.click(); a.remove(); }
export function readFileAs(file, as = 'dataURL') { return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; as === 'text' ? r.readAsText(file) : as === 'buffer' ? r.readAsArrayBuffer(file) : r.readAsDataURL(file); }); }

// ---------- markdown (escape-first, safe) ----------
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const KW = /\b(function|return|const|let|var|if|else|for|while|class|import|from|export|def|async|await|new|try|catch|except|finally|with|as|public|private|static|void|int|string|bool|true|false|null|None|True|False|self|this|lambda|yield|struct|fn|pub|use|match|switch|case|break|continue|package|interface|extends|implements|func|local|then|end|elif|in|not|and|or|using|namespace|template|typename|signal|extends|onready|var)\b/g;
function highlight(code) {
  // tokens: comments, strings, numbers, keywords — applied on escaped text with placeholders
  const store = []; const keep = (cls, s) => { store.push(`<span class="hl-${cls}">${s}</span>`); return `\u0000${store.length - 1}\u0000`; };
  let s = esc(code);
  s = s.replace(/(\/\*[\s\S]*?\*\/|\/\/[^\n]*|#[^\n]*|--[^\n]*)/g, (m) => keep('c', m));
  s = s.replace(/(&quot;(?:[^&]|&(?!quot;))*?&quot;|'(?:[^'\\\n]|\\.)*'|`[^`]*`)/g, (m) => keep('s', m));
  s = s.replace(/\b(\d+(?:\.\d+)?)\b/g, (m) => keep('n', m));
  s = s.replace(KW, (m) => keep('k', m));
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => store[+i]);
}
function inline(s) {
  const codes = [];
  s = s.replace(/`([^`\n]+)`/g, (_, c) => { codes.push(`<code>${esc(c)}</code>`); return `\u0001${codes.length - 1}\u0001`; });
  s = esc(s);
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>').replace(/~~([^~]+)~~/g, '<del>$1</del>');
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, (_, t, u) => `<a href="${u}" data-ext="1" rel="noopener noreferrer">${t}</a>`);
  s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, (_, p, u) => `${p}<a href="${u}" data-ext="1" rel="noopener noreferrer">${u}</a>`);
  return s.replace(/\u0001(\d+)\u0001/g, (_, i) => codes[+i]);
}
export function markdown(src) {
  const lines = String(src || '').replace(/\r/g, '').split('\n');
  let out = ''; let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    const fence = l.match(/^\s*```\s*([\w+#.-]*)/);
    if (fence) {
      const buf = []; i++;
      while (i < lines.length && !/^\s*```/.test(lines[i])) buf.push(lines[i++]);
      i++;
      out += `<pre><span class="lang">${esc(fence[1] || 'code')}<button data-copy="1">copy</button></span><code>${highlight(buf.join('\n'))}</code></pre>`;
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(l) && /^\s*\|?\s*:?-+/.test(lines[i + 1] || '')) {
      const row = (r) => r.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
      out += '<table><thead><tr>' + row(l).map((c) => `<th>${inline(c)}</th>`).join('') + '</tr></thead><tbody>';
      i += 2;
      while (i < lines.length && /^\s*\|/.test(lines[i])) out += '<tr>' + row(lines[i++]).map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>';
      out += '</tbody></table>'; continue;
    }
    const hm = l.match(/^(#{1,4})\s+(.*)/);
    if (hm) { out += `<h${hm[1].length}>${inline(hm[2])}</h${hm[1].length}>`; i++; continue; }
    if (/^\s*([-*_])\s*\1\s*\1\s*$/.test(l)) { out += '<hr>'; i++; continue; }
    if (/^\s*>\s?/.test(l)) { const b = []; while (i < lines.length && /^\s*>\s?/.test(lines[i])) b.push(lines[i++].replace(/^\s*>\s?/, '')); out += `<blockquote>${inline(b.join(' '))}</blockquote>`; continue; }
    if (/^\s*([-*+]|\d+[.)])\s+/.test(l)) {
      const ordered = /^\s*\d/.test(l); const items = [];
      while (i < lines.length && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) { let it = lines[i++].replace(/^\s*([-*+]|\d+[.)])\s+/, ''); while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) it += ' ' + lines[i++].trim(); items.push(it); }
      out += `<${ordered ? 'ol' : 'ul'}>${items.map((x) => `<li>${inline(x)}</li>`).join('')}</${ordered ? 'ol' : 'ul'}>`; continue;
    }
    if (!l.trim()) { i++; continue; }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^\s*(```|#{1,4}\s|>|([-*+]|\d+[.)])\s+|\|)/.test(lines[i])) para.push(lines[i++]);
    if (!para.length) { para.push(lines[i++]); }
    out += `<p>${inline(para.join('\n')).replace(/\n/g, '<br>')}</p>`;
  }
  return out;
}
export function mdEl(src, cls = '') {
  const el = h(`div.md${cls ? '.' + cls : ''}`, { html: markdown(src) });
  el.addEventListener('click', (e) => {
    const c = e.target.closest('button[data-copy]');
    if (c) { navigator.clipboard?.writeText(c.closest('pre').querySelector('code').innerText); c.textContent = 'copied'; setTimeout(() => { c.textContent = 'copy'; }, 1200); }
    const a = e.target.closest('a[data-ext]');
    if (a) { e.preventDefault(); window.viperNative?.openExternal ? window.viperNative.openExternal(a.href) : window.open(a.href, '_blank', 'noopener'); }
  });
  return el;
}
