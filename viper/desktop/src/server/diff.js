'use strict';
// Line diff (LCS) for code comparison and AI edit previews.
function diffLines(a, b) {
  const A = String(a).split('\n'); const B = String(b).split('\n');
  if (A.length * B.length > 4e6) return [{ op: 'del', lines: A }, { op: 'add', lines: B }].map((x) => x.lines.map((l) => ({ op: x.op, line: l }))).flat();
  const n = A.length; const m = B.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = A[i] === B[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out = []; let i = 0; let j = 0;
  while (i < n && j < m) {
    if (A[i] === B[j]) { out.push({ op: 'eq', line: A[i] }); i++; j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ op: 'del', line: A[i++] });
    else out.push({ op: 'add', line: B[j++] });
  }
  while (i < n) out.push({ op: 'del', line: A[i++] });
  while (j < m) out.push({ op: 'add', line: B[j++] });
  return out;
}
function unified(a, b, name = 'file', ctx = 3) {
  const d = diffLines(a, b);
  const keep = d.map((x, i) => x.op !== 'eq' || d.slice(Math.max(0, i - ctx), i + ctx + 1).some((y) => y.op !== 'eq'));
  const lines = [`--- a/${name}`, `+++ b/${name}`];
  let skipping = false;
  d.forEach((x, i) => {
    if (!keep[i]) { if (!skipping) { lines.push('@@ … @@'); skipping = true; } return; }
    skipping = false;
    lines.push(`${x.op === 'add' ? '+' : x.op === 'del' ? '-' : ' '}${x.line}`);
  });
  return { text: lines.join('\n'), added: d.filter((x) => x.op === 'add').length, removed: d.filter((x) => x.op === 'del').length };
}
module.exports = { diffLines, unified };
