'use strict';
// Download + extract helper for user-initiated component installs (voice engines, voices).
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFile } = require('node:child_process');
const { Readable } = require('node:stream');

async function downloadFile(url, dest, { onProgress, signal } = {}) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const r = await fetch(url, { signal, redirect: 'follow' });
  if (!r.ok) throw new Error(`Download failed (${r.status}) for ${url}`);
  const total = Number(r.headers.get('content-length')) || 0;
  const tmp = `${dest}.part`;
  const out = fs.createWriteStream(tmp);
  const hash = crypto.createHash('sha256');
  let done = 0; let last = 0;
  await new Promise((resolve, reject) => {
    const src = Readable.fromWeb(r.body);
    src.on('data', (c) => { done += c.length; hash.update(c); if (Date.now() - last > 200) { last = Date.now(); onProgress?.(done, total); } });
    src.on('error', reject); out.on('error', reject); out.on('finish', resolve);
    src.pipe(out);
  });
  if (total && done !== total) throw new Error('Download incomplete');
  fs.renameSync(tmp, dest);
  onProgress?.(done, total || done);
  return { path: dest, bytes: done, sha256: hash.digest('hex') };
}

function extract(archive, dir) {
  fs.mkdirSync(dir, { recursive: true });
  return new Promise((resolve, reject) => {
    // bsdtar (Windows 10+ tar.exe) and GNU tar both handle .tar.gz; bsdtar also handles .zip.
    const isZip = archive.toLowerCase().endsWith('.zip');
    const [cmd, args] = isZip && process.platform !== 'win32' ? ['unzip', ['-o', '-q', archive, '-d', dir]] : ['tar', ['-xf', archive, '-C', dir]];
    execFile(cmd, args, { windowsHide: true, timeout: 300000 }, (err, _o, stderr) => (err ? reject(new Error(`Extract failed: ${stderr || err.message}`)) : resolve(dir)));
  });
}

function findFile(dir, names, depth = 0) {
  if (depth > 5 || !fs.existsSync(dir)) return null;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isFile() && names.includes(e.name.toLowerCase())) return p;
  }
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) if (e.isDirectory()) { const f = findFile(path.join(dir, e.name), names, depth + 1); if (f) return f; }
  return null;
}

module.exports = { downloadFile, extract, findFile };
