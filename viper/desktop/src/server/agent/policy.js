'use strict';
// Command policy for the Code Agent. Every command the agent wants to run is classified:
//   allow    — builds, tests, compilers and read-only git inside the project
//   approve  — needs your explicit OK: installing packages (network), unknown programs,
//              git history rewrites, deletes, anything touching paths outside the project
//   deny     — never run: privilege escalation, disk/system tools, shutdown, registry edits
const path = require('node:path');

const DENY = /^(sudo|su|runas|doas|format|diskpart|bcdedit|reg|regedit|shutdown|restart-computer|stop-computer|takeown|icacls|cacls|net|netsh|sc|schtasks|wmic|vssadmin|cipher|mkfs|fdisk|dd|chown|chmod|rm|del|erase|rd|rmdir|remove-item|curl|wget|invoke-webrequest|iwr|powershell|pwsh)$/i;
const BUILD = /^(python3?|py|node|tsc|dotnet|javac|java|kotlinc|go|cargo|rustc|gcc|g\+\+|clang|clang\+\+|cl|msbuild|cmake|make|ninja|godot|godot4|flutter|dart|gradle|gradlew|mvn|deno|bun)$/i;
const INSTALL = [/^(pip3?|uv)\b.*\binstall\b/i, /^(python3?|py)\s+-m\s+pip\s+install\b/i, /^(npm|pnpm|yarn)\s+(i|install|add|ci)\b/i, /^npx\b/i, /^dotnet\s+(add|tool\s+install|workload)\b/i, /^cargo\s+(add|install)\b/i, /^go\s+(get|install)\b/i, /^(flutter|dart)\s+pub\s+(get|add)\b/i];
const NPM_RUN = /^(npm|pnpm|yarn)\s+(run|test|start|run-script)\b/i;
const GIT_SAFE = /^git\s+(status|diff|log|show|add|commit|init|rev-parse|branch|ls-files)\b/i;
const GIT_RISKY = /^git\s+(reset|clean|checkout|restore|rebase|push|pull|fetch|clone|remote|stash|merge|cherry-pick|rm)\b/i;

/** Split a shell line into simple commands (&&, ||, ;, |). */
function segments(line) { return String(line).split(/&&|\|\||;|\|/).map((s) => s.trim()).filter(Boolean); }
const exe = (seg) => { const m = seg.match(/^"([^"]+)"|^(\S+)/); const raw = (m?.[1] || m?.[2] || '').replace(/\\/g, '/'); return path.posix.basename(raw).replace(/\.(exe|cmd|bat)$/i, ''); };

/** Absolute paths or parent escapes that leave the project root. */
function outsidePaths(line, root) {
  const out = [];
  for (const tok of String(line).match(/"[^"]+"|'[^']+'|\S+/g) || []) {
    const t = tok.replace(/^['"]|['"]$/g, '');
    if (/^[a-z]+:\/\//i.test(t)) continue; // URLs are judged by the network rules
    const abs = /^[a-z]:[\\/]/i.test(t) || t.startsWith('/') || t.startsWith('\\\\');
    const up = /(^|[\\/])\.\.([\\/]|$)/.test(t);
    if (!abs && !up) continue;
    const full = abs ? path.resolve(t) : path.resolve(root, t);
    const rel = path.relative(root, full);
    if (rel.startsWith('..') || path.isAbsolute(rel)) out.push(t);
  }
  return out;
}

/**
 * @returns {{ verdict: 'allow'|'approve'|'deny', reason: string, network?: boolean }}
 */
function classify(line, root, { allowInstall = false, interpreter } = {}) {
  const segs = segments(line);
  if (!segs.length) return { verdict: 'deny', reason: 'Empty command' };
  if (/[`]|\$\(/.test(line)) return { verdict: 'approve', reason: 'Command substitution' };
  const outside = outsidePaths(line, root).filter((p) => !(interpreter && path.resolve(p) === path.resolve(interpreter)));
  let verdict = 'allow'; let reason = 'Build/test command inside the project'; let network = false;
  const raise = (v, r) => { const rank = { allow: 0, approve: 1, deny: 2 }; if (rank[v] > rank[verdict]) { verdict = v; reason = r; } };
  for (const seg of segs) {
    const e = exe(seg);
    if (DENY.test(e)) { raise('deny', `"${e}" is never run by the Code Agent`); continue; }
    if (INSTALL.some((re) => re.test(seg))) { network = true; if (!allowInstall) raise('approve', `Installs packages from the internet: ${seg}`); continue; }
    if (/^git$/i.test(e)) { if (GIT_RISKY.test(seg)) raise('approve', `Git operation that can change or discard history: ${seg}`); else if (!GIT_SAFE.test(seg)) raise('approve', `Git command: ${seg}`); continue; }
    if (/^(npm|pnpm|yarn)$/i.test(e)) { if (!NPM_RUN.test(seg)) raise('approve', `Package-manager command: ${seg}`); continue; }
    if (BUILD.test(e) || (interpreter && seg.startsWith(`"${interpreter}"`))) continue;
    if (/^(echo|cd|type|cat|dir|ls|mkdir|copy|cp|move|mv|where|which)$/i.test(e)) { if (/^(copy|cp|move|mv)$/i.test(e)) raise('approve', `Moves or copies files: ${seg}`); continue; }
    raise('approve', `Program not on the Code Agent's allow-list: ${e}`);
  }
  if (outside.length) raise('approve', `Uses paths outside the project: ${outside.join(', ')}`);
  if (/>\s*\S/.test(line) && outside.length) raise('approve', 'Writes outside the project');
  return { verdict, reason, network };
}

module.exports = { classify, segments, outsidePaths };
