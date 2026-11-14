'use strict';
// Local text extraction for documents. No external services.
const path = require('node:path');

const TEXT_EXT = new Set(['txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'py', 'cs', 'java', 'cpp', 'cc', 'c', 'h', 'hpp', 'go', 'rs', 'rb', 'php', 'css', 'scss', 'xml', 'yaml', 'yml', 'ini', 'toml', 'cfg', 'conf', 'log', 'gd', 'lua', 'sql', 'sh', 'ps1', 'bat', 'cmd', 'kt', 'swift', 'r', 'm', 'vue', 'svelte', 'tex', 'rst', 'srt', 'vtt', 'gradle', 'properties', 'env']);
const SUPPORTED = new Set([...TEXT_EXT, 'pdf', 'docx', 'xlsx', 'xls', 'ods', 'html', 'htm', 'rtf']);

function ext(name) { return path.extname(name).slice(1).toLowerCase(); }
function isSupported(name) { return SUPPORTED.has(ext(name)); }

function htmlToText(html) {
  return String(html).replace(/<(script|style|noscript|svg|head)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|h[1-6]|li|tr|section|article|header|footer|blockquote|pre)>/gi, '\n')
    .replace(/<li[^>]*>/gi, '• ').replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/[ \t]+/g, ' ').replace(/\n\s*\n\s*\n+/g, '\n\n').trim();
}

let pdfjs = null;
async function pdfText(buf) {
  if (!pdfjs) pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const task = pdfjs.getDocument({ data: new Uint8Array(buf), isEvalSupported: false, useSystemFonts: true, disableFontFace: true, verbosity: 0 });
  const doc = await task.promise;
  const pages = [];
  for (let i = 1; i <= Math.min(doc.numPages, 500); i++) {
    const page = await doc.getPage(i);
    const c = await page.getTextContent();
    let last = null; let line = '';
    const lines = [];
    for (const it of c.items) {
      if (last && Math.abs(it.transform[5] - last) > 2) { lines.push(line); line = ''; }
      line += (line && !line.endsWith(' ') ? ' ' : '') + it.str; last = it.transform[5];
    }
    lines.push(line);
    pages.push(`[Page ${i}]\n${lines.join('\n')}`);
  }
  await task.destroy?.();
  return { text: pages.join('\n\n'), pages: doc.numPages };
}

function sheetSummary(wb, XLSX) {
  const out = []; const sheets = [];
  for (const name of wb.SheetNames.slice(0, 20)) {
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, blankrows: false, defval: '' });
    const header = (rows[0] || []).map(String);
    const stats = header.map((h, ci) => {
      const nums = rows.slice(1).map((r) => r[ci]).filter((v) => typeof v === 'number' || (v !== '' && !isNaN(Number(v)))).map(Number);
      if (nums.length < Math.max(1, (rows.length - 1) * 0.6)) return null;
      const sum = nums.reduce((a, b) => a + b, 0);
      return { column: h || `Column ${ci + 1}`, count: nums.length, min: Math.min(...nums), max: Math.max(...nums), mean: Math.round(sum / nums.length * 1000) / 1000, sum: Math.round(sum * 1000) / 1000 };
    }).filter(Boolean);
    sheets.push({ name, rows: Math.max(0, rows.length - 1), columns: header, numeric: stats });
    out.push(`[Sheet ${name}] ${rows.length - 1} rows · columns: ${header.join(', ')}`);
    for (const s of stats) out.push(`  ${s.column}: n=${s.count} min=${s.min} max=${s.max} mean=${s.mean} sum=${s.sum}`);
    out.push(rows.slice(0, 200).map((r) => r.join('\t')).join('\n'));
  }
  return { text: out.join('\n'), sheets };
}

/** @returns {Promise<{text:string, meta:object}>} */
async function extractText(name, buf) {
  const e = ext(name);
  if (TEXT_EXT.has(e)) return { text: buf.toString('utf8').replace(/^﻿/, ''), meta: { kind: e === 'csv' ? 'table' : 'text' } };
  if (e === 'html' || e === 'htm') return { text: htmlToText(buf.toString('utf8')), meta: { kind: 'html' } };
  if (e === 'pdf') { const r = await pdfText(buf); return { text: r.text, meta: { kind: 'pdf', pages: r.pages } }; }
  if (e === 'docx') { const mammoth = require('mammoth'); const r = await mammoth.extractRawText({ buffer: buf }); return { text: r.value, meta: { kind: 'docx' } }; }
  if (['xlsx', 'xls', 'ods'].includes(e)) { const XLSX = require('xlsx'); const wb = XLSX.read(buf, { type: 'buffer', cellDates: true }); const r = sheetSummary(wb, XLSX); return { text: r.text, meta: { kind: 'spreadsheet', sheets: r.sheets } }; }
  if (e === 'rtf') return { text: buf.toString('latin1').replace(/\\par[d]?/g, '\n').replace(/\{\\\*[^}]*\}|\\[a-z]+-?\d* ?|[{}]/g, '').trim(), meta: { kind: 'rtf' } };
  throw new Error(`Unsupported file type .${e}`);
}

module.exports = { extractText, isSupported, htmlToText, ext, TEXT_EXT };
