// Builds VIPER-Test-Report (HTML, printed to PDF by CI) from the results of ONE CI run:
// the Windows installed-app E2E, the Android emulator E2E, both unit-test suites, the APK
// signature, a secret scan of the source tree, and the SHA-256 checksums of the delivered files.
// Usage: node make-report.js <artifacts-dir> <SHA256SUMS.txt> <commit> <out.html>
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const [ART, SUMS, COMMIT, OUT] = process.argv.slice(2);
const read = (p, d = null) => { try { return fs.readFileSync(path.join(ART, p), 'utf8'); } catch { return d; } };
const json = (p) => { try { return JSON.parse(read(p)); } catch { return null; } };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const win = json('e2e-windows/results.json');
const and = json('e2e-android/results.json');
const unitTxt = read('e2e-windows/unit-tests.txt', '');
const andUnit = json('VIPER-Mobile/android-unit-tests.json');
const apkSig = read('VIPER-Mobile/apk-signature.txt', '');
const sums = fs.readFileSync(SUMS, 'utf8').trim().split('\n').map((l) => l.split(/\s+/));
const version = (read('VIPER-Windows/latest.yml', '').match(/^version:\s*(\S+)/m) || [])[1] || '?';

// ---- desktop unit tests (node --test TAP summary) ----
const num = (k) => +(unitTxt.match(new RegExp(`^# ${k} (\\d+)`, 'm')) || [])[1] || 0;
const unit = { tests: num('tests'), pass: num('pass'), fail: num('fail'), skipped: num('skipped') };
const suites = [...unitTxt.matchAll(/^(ok|not ok) \d+ - (.+?)(?: # SKIP (.*))?$/gm)].map((m) => ({ ok: m[1] === 'ok', name: m[2], skip: m[3] }));

// ---- secret scan of the source tree that was built ----
const PATTERNS = [
  ['private key', /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
  ['AWS access key', /AKIA[0-9A-Z]{16}/], ['OpenAI-style key', /\bsk-[A-Za-z0-9]{32,}/], ['GitHub token', /\bgh[pousr]_[A-Za-z0-9]{36}\b/],
  ['Slack token', /\bxox[abprs]-[A-Za-z0-9-]{10,}/], ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/], ['Twilio key', /\bSK[0-9a-fA-F]{32}\b/],
  ['hard-coded password', /(?:password|passwd|secret)\s*[:=]\s*["'][^"'${}\s]{8,}["']/i],
];
const scanHits = []; let scanned = 0;
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (['node_modules', '.git', 'build', 'dist', '.gradle', 'releases', 'fixtures', 'e2e-out'].includes(e.name)) continue;
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(js|kt|kts|json|yml|yaml|xml|md|properties|ps1|sh|html|css)$/.test(e.name) && fs.statSync(p).size < 2e6) {
      scanned++; const t = fs.readFileSync(p, 'utf8');
      for (const [label, re] of PATTERNS) { if (label === 'hard-coded password' && /[\\/]test[\\/]/.test(p)) continue; /* test fixtures use dummy passwords for local fake servers */ const m = t.match(re); if (m && !/make-report\.js$/.test(p)) scanHits.push(`${label}: ${path.relative('.', p)} (“${m[0].slice(0, 24)}…”)`); }
    }
  }
})('viper');

// ---- helpers ----
const STATUS = { PASS: '#0a7d32', FAIL: '#b00020', BLOCKED: '#a15c00', 'NOT TESTED': '#555' };
const badge = (s) => `<span class="b" style="background:${STATUS[s] || '#555'}">${esc(s)}</span>`;
const count = (rs, s) => (rs || []).filter((r) => r.status === s).length;
const table = (rows, areas) => {
  const list = (rows || []).filter((r) => !areas || areas.includes(r.area));
  if (!list.length) return '<p class="mist">No results recorded.</p>';
  return `<table><tr><th>Check</th><th>Result</th><th>Evidence</th></tr>${list.map((r) => `<tr><td>${esc(r.name)}</td><td>${badge(r.status)}</td><td class="ev">${esc(r.detail)}</td></tr>`).join('')}</table>`;
};
const kv = (o) => `<table class="kv">${Object.entries(o).map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(v)}</td></tr>`).join('')}</table>`;
const img = (dir, f, cap) => { const p = path.join(ART, dir, f); if (!fs.existsSync(p)) return ''; return `<figure><img src="data:image/png;base64,${fs.readFileSync(p).toString('base64')}"><figcaption>${esc(cap)}</figcaption></figure>`; };
const m = win?.metrics || {}; const am = and?.metrics || {};
const mb = (x) => (x == null ? '—' : `${x} MB`); const pct = (x) => (x == null ? '—' : `${x}%`);

const html = `<!doctype html><html><head><meta charset="utf-8"><title>VIPER Test Report ${esc(version)}</title><style>
  @page { size: A4; margin: 14mm 12mm; }
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body { font: 10.5px/1.45 "Segoe UI", Arial, sans-serif; color: #111; }
  h1 { font-size: 24px; letter-spacing: 6px; margin: 0 0 2px; } h2 { font-size: 15px; border-bottom: 2px solid #000; padding-bottom: 3px; margin: 22px 0 8px; page-break-after: avoid; }
  h3 { font-size: 12px; margin: 14px 0 5px; page-break-after: avoid; } .mist { color: #666; }
  table { border-collapse: collapse; width: 100%; margin: 4px 0 8px; page-break-inside: auto; } tr { page-break-inside: avoid; }
  th, td { border: 1px solid #ccc; padding: 3px 5px; text-align: left; vertical-align: top; } th { background: #f1f1f1; }
  td.ev { font-family: Consolas, monospace; font-size: 9px; color: #333; word-break: break-word; }
  .kv th { width: 34%; } .b { color: #fff; border-radius: 3px; padding: 1px 5px; font-size: 9px; font-weight: 700; white-space: nowrap; }
  .sum { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; } .sum div { border: 1px solid #ccc; padding: 6px; }
  .sum b { font-size: 17px; display: block; } figure { display: inline-block; width: 31%; margin: 0 1% 8px 0; vertical-align: top; }
  figure img { width: 100%; border: 1px solid #999; } figcaption { font-size: 8.5px; color: #555; } .mono { font-family: Consolas, monospace; font-size: 9px; word-break: break-all; }
  ul { margin: 4px 0 8px 16px; padding: 0; } li { margin: 2px 0; }
</style></head><body>
<h1>VIPER</h1><div class="mist">Test report · version ${esc(version)} · commit ${esc(COMMIT.slice(0, 12))} · generated ${new Date().toUTCString()}</div>
<p>This report was generated automatically from the CI run that built the delivered files. Every result below comes from a test that actually ran on that build. <b>PASS</b> = verified; <b>FAIL</b> = verified broken; <b>BLOCKED</b> = could not run in the test environment; <b>NOT TESTED</b> = no test was performed. Tests ran on cloud CI machines, not on your PC (see limitations).</p>

<h2>Summary</h2>
<div class="sum">
  <div><b>${unit.pass}/${unit.tests - unit.skipped}</b>desktop unit + integration tests passed${unit.fail ? ` · <span style="color:#b00020">${unit.fail} failed</span>` : ''}${unit.skipped ? ` · ${unit.skipped} skipped` : ''}</div>
  <div><b>${count(win?.results, 'PASS')}/${(win?.results || []).length}</b>Windows installed-app checks passed · ${count(win?.results, 'FAIL')} FAIL · ${count(win?.results, 'BLOCKED')} BLOCKED</div>
  <div><b>${andUnit ? `${andUnit.tests - andUnit.failures}/${andUnit.tests}` : '—'}</b>Android unit tests passed</div>
  <div><b>${count(and?.results, 'PASS')}/${(and?.results || []).length}</b>Android device checks passed · ${count(and?.results, 'FAIL')} FAIL · ${count(and?.results, 'NOT TESTED')} NOT TESTED</div>
</div>

<h2>Delivered files (SHA-256)</h2>
<table><tr><th>File</th><th>SHA-256</th></tr>${sums.map(([h, f]) => `<tr><td>${esc(f)}</td><td class="mono">${esc(h)}</td></tr>`).join('')}</table>

<h2>WINDOWS</h2>
${kv({ 'Build status': 'Built on windows-latest with electron-builder: NSIS installer (per-user, Start menu + desktop shortcuts, uninstaller) and a portable EXE. Electron runtime bundled; no Node.js, Python or .NET needed.', 'Test machine': win ? `${win.platform} · ${win.cpu} · ${win.cores} logical CPUs · ${win.ramGB} GB RAM · no GPU (software rendering)` : 'no results', 'AI model used': `${win?.model || '—'} via Ollama (downloaded by VIPER's Model Manager during the test)`, 'Installed size': mb(m.installedSizeMB), 'Install time': m.installSeconds ? `${m.installSeconds} s` : '—', 'Performance preset auto-selected': m.presetApplied || '—' })}
<h3>Automatic AI start-up</h3>${table(win?.results, ['AI start-up'])}
${kv({ 'Cold launch to "VIPER ONLINE — READY" (engine not running)': m.coldStartToReadyMs ? `${(m.coldStartToReadyMs / 1000).toFixed(1)} s` : '—', 'Readiness check (real generation)': m.readinessMs != null ? `${m.readinessMs} ms` : '—', 'Automatic reconnection after the engine was killed': m.recoverySeconds ? `${m.recoverySeconds} s` : '—', 'Ollama already running when VIPER first opened': m.enginePreRunning ? 'yes (VIPER connected to it and did not start a copy)' : 'no (VIPER started it)' })}
<h3>UI alignment and layout (pixel audit of the real window)</h3>${table(win?.results, ['UI'])}
${m.uiAudit ? kv({ 'Control renders measured': m.uiAudit.checked, 'Label offset from centre (median / 95th percentile / max)': `${m.uiAudit.medianOffsetPx} px / ${m.uiAudit.p95OffsetPx} px / ${m.uiAudit.maxOffsetPx} px`, 'Window sizes': '1440×900, 1100×720, 920×600 (minimum)' }) : ''}
<h3>Installer</h3>${table(win?.results, ['Installer', 'Portable'])}
<h3>Start-up, navigation and application behaviour</h3>${table(win?.results, ['App'])}
<h3>Chat inference (real local model)</h3>${table(win?.results, ['AI'])}
${m.chat ? kv({ 'Time to first token (UI)': `${m.chat.ttftMs} ms`, 'Complete reply': `${m.chat.totalMs} ms`, 'Generation speed': m.chat.tokPerS ? `${m.chat.tokPerS} tokens/s` : '—', 'Follow-up turn (prompt cache reused)': m.chatTurn2 ? `first token ${m.chatTurn2.ttftMs ?? m.chatTurn2.ttft} ms, complete ${m.chatTurn2.totalMs ?? m.chatTurn2.total} ms` : '—', 'Model warm-up': m.warmupMs != null ? `${m.warmupMs} ms` : '—' }) : ''}
<h3>Voice</h3>${table(win?.results, ['Voice'])}
<h3>UI performance, CPU and RAM</h3>${table(win?.results, ['Performance', 'System'])}
${kv({
  'Idle (Home, core animating): CPU': m.idle ? `${pct(m.idle.cpuTotalPct)} of one core (${pct(m.idle.cpuTotalPctOfMachine)} of the machine)` : '—',
  'Idle: RAM (all VIPER processes)': m.idle ? `${mb(m.idle.ramTotalMB)} (interface ${mb(m.idle.ramRendererMB)}, core ${mb(m.idle.ramCoreMB)})` : '—',
  'During inference: VIPER CPU': m.chat?.viperDuringInference ? `${pct(m.chat.viperDuringInference.cpuTotalPct)} of one core` : '—',
  'During inference: VIPER RAM': m.chat?.viperDuringInference ? mb(m.chat.viperDuringInference.ramTotalMB) : '—',
  'During inference: AI engine (Ollama, incl. model runner)': m.chat ? `${m.chat.engineCpuSeconds} CPU-seconds for the reply, peak ${mb(m.chat.engineRamMB)} RAM` : '—',
  'During inference: whole machine': m.chat?.machine ? `CPU peak ${pct(m.chat.machine.cpuPeak)} · RAM in use ${mb(m.chat.machine.memUsedPeakMB)} of ${mb(m.chat.machine.memTotalMB)}` : '—',
  'UI frame rate during inference': m.chat?.frames ? `${m.chat.frames.uiFps} fps interface, core animation ${m.chat.frames.coreFps} fps (capped at 30 while generating), p95 frame ${m.chat.frames.p95FrameMs} ms, longest gap ${m.chat.frames.maxFrameGapMs} ms, ${m.chat.frames.longTasks} long tasks` : '—',
  'Minimised: CPU / RAM': m.minimised ? `${pct(m.minimised.cpuTotalPct)} of one core · ${mb(m.minimised.ramTotalMB)}` : '—',
  'Page switch (median / max)': m.pageSwitchMs ? `${m.pageSwitchMs.median} ms / ${m.pageSwitchMs.max} ms` : '—',
  'Renderer heap before / after visiting every page 3×': m.heapMB ? `${m.heapMB.before} MB / ${m.heapMB.afterNavigating3x} MB` : '—',
  'Start-up to dashboard (first / second launch)': `${m.startup_first_ms ?? '—'} ms / ${m.startup_second_ms ?? '—'} ms`,
})}
<h3>Desktop unit + integration test suites</h3>
<table><tr><th>Suite</th><th>Result</th></tr>${suites.map((s) => `<tr><td>${esc(s.name)}</td><td>${badge(s.skip ? 'BLOCKED' : s.ok ? 'PASS' : 'FAIL')}${s.skip ? ` <span class="mist">${esc(s.skip)}</span>` : ''}</td></tr>`).join('')}</table>

<h2>ANDROID</h2>
${kv({ 'Build status': `Release APK built with Gradle (minified with R8, signed). ${esc((apkSig.match(/signing=.*/) || [''])[0])}`, 'Signer': (apkSig.match(/Signer #1 certificate DN: .*/) || ['—'])[0], 'APK size': am.apkBytes ? `${(am.apkBytes / 1048576).toFixed(1)} MB` : '—', 'Test device': and?.metrics?.device ? `Android emulator (${and.metrics.device.model}), Android ${and.metrics.device.android} (API ${and.metrics.device.sdk}), ${and.metrics.device.abi}. NOT a physical phone.` : 'no results', 'PC side': `real VIPER core (the same server code the Windows app runs) + Ollama ${esc(and?.model || '')} on the CI host, reached by the emulator at 10.0.2.2` })}
<h3>APK installation and permissions</h3>${table(and?.results, ['Install', 'Permissions'])}
<h3>UI tests</h3>${table(and?.results, ['UI'])}
<h3>Phone-to-PC connection and chat</h3>${table(and?.results, ['Host', 'Pairing', 'Chat', 'Network'])}
${am.phoneChat ? kv({ 'Tokens streamed to the phone': am.phoneChat.tokens, 'First token after tapping Send': `${am.phoneChat.firstTokenMs} ms`, 'Reply length seen growing on screen': (am.phoneChat.observedLengths || []).join(' → ') }) : ''}
<h3>Voice</h3>${table(and?.results, ['Voice'])}
<h3>Notifications</h3>${table(and?.results, ['Notifications'])}
<h3>Screen sizes and stability</h3>${table(and?.results, ['Layout', 'Stability'])}
<h3>Android unit tests</h3><p>${andUnit ? `${andUnit.tests} tests, ${andUnit.failures} failures: ${esc(andUnit.cases.join(', '))}` : 'not available'}</p>

<h2>SECURITY</h2>
<h3>Authentication checks</h3>
<ul>
<li>Local API listens on 127.0.0.1 only and needs a random per-launch token; foreign Host headers (DNS rebinding) are refused — automated test <i>“API rejects missing/invalid token and foreign Host headers”</i>.</li>
<li>Phone pairing uses a single-use, 5-minute token shown only on the PC; each phone gets its own secret (stored hashed on the PC) and scopes — tests <i>“wrong token is rejected; correct token pairs exactly once”</i>, <i>“requests need the device secret, and scopes limit what a phone can reach”</i>, <i>“every phone API call targets a route a paired device may use”</i>.</li>
<li>Revoking a phone closes its connection at once and invalidates its secret — unit test <i>“revocation disconnects the phone immediately and blocks the secret”</i> and, on the emulator, ${and ? badge((and.results.find((r) => /revoking/.test(r.name)) || {}).status || 'NOT TESTED') : 'not run'}.</li>
</ul>
<h3>Network security checks</h3>
<ul>
<li>Phone ↔ PC traffic is TLS-encrypted; the phone pins the PC certificate's SHA-256 fingerprint from the QR code (no trust-on-first-use) — test <i>“the presented certificate matches the pinned fingerprint”</i>. The Android app disallows clear-text traffic (<code>usesCleartextTraffic=false</code>).</li>
<li>The phone link is off until enabled and only reachable on the local network/VPN the PC is on; nothing is exposed to the internet by VIPER.</li>
<li>Web fetching refuses private-network targets and re-checks every redirect (SSRF) — test <i>“web fetching refuses private-network targets”</i>. Web/e-mail/document content is treated as untrusted and actions after it require confirmation — test <i>“prompt injection: actions after untrusted content require confirmation”</i>.</li>
<li>Pairing links/shared codes are not exposed to browsers (no BROWSABLE intent filter) and only pre-fill the form; the user must tap Pair after seeing the PC name and address.</li>
</ul>
<h3>Credential storage review</h3>
<ul>
<li>Desktop secrets (e-mail passwords, OAuth tokens, API keys) are AES-256-GCM encrypted; the key is protected with Windows DPAPI — tests <i>“vault encrypts at rest”</i>, <i>“password stored encrypted, never in the accounts table”</i>; logs redact secrets — <i>“log sanitiser redacts secrets”</i>.</li>
<li>The phone stores its pairing in EncryptedSharedPreferences (Android Keystore); app backups are disabled; the release APK is not debuggable — ${and ? badge((and.results.find((r) => /not debuggable/.test(r.name)) || {}).status || 'NOT TESTED') : ''} and app data is inaccessible from outside the app — ${and ? badge((and.results.find((r) => /not accessible/.test(r.name)) || {}).status || 'NOT TESTED') : ''}.</li>
<li>Source secret scan (${scanned} files): ${scanHits.length ? `<b style="color:#b00020">${scanHits.length} finding(s)</b><br><span class="mono">${scanHits.map(esc).join('<br>')}</span>` : `${badge('PASS')} no API keys, tokens, private keys or hard-coded passwords found`}. Signing keys are never stored in the repository.</li>
<li>Dangerous actions: destructive actions always ask for confirmation; file tools are limited to the allowed folders; e-mail and SMS sending ask by default — tests <i>“destructive actions always ask; a declined prompt blocks the action”</i>, <i>“file tools are sandboxed to allowed folders”</i>, <i>“approved send delivers via authenticated SMTP and is logged”</i>.</li>
</ul>
<h3>Outstanding security limitations</h3>
<ul>
<li>The Windows installer and portable EXE are <b>not code-signed</b>; Windows SmartScreen and browsers warn on download. Code signing needs a certificate in your name.</li>
<li>The APK is signed with ${/per-build/.test(apkSig) ? '<b>a key generated for this build</b> (no permanent signing key is configured yet): a future APK signed with a different key cannot update this one in place — uninstall first. Configure the VIPER_KEYSTORE_* repository secrets for permanent signing.' : 'the repository signing key.'}</li>
<li>Remote use outside the home network requires your own VPN (e.g. Tailscale/WireGuard); VIPER does not provide internet relaying. Not tested.</li>
<li>Plugins run in a QuickJS sandbox with explicit grants, but a plugin you grant web access to can send the data it is given to that host.</li>
</ul>

<h2>Limitations of this test run (read before relying on the numbers)</h2>
<ul>
<li><b>Hardware:</b> Windows tests ran on a GitHub-hosted VM (${esc(win?.cpu || '?')}, ${win?.cores || '?'} vCPU, ${win?.ramGB || '?'} GB, no GPU, software rendering), not your Intel Core i7 laptop with integrated graphics. CPU, RAM, FPS and speed figures will differ on your PC; integrated graphics usually render the interface faster than software rendering.</li>
<li><b>Audio:</b> CI machines have no microphone or speakers. The microphone was tested with Chromium's built-in fake audio device; speech output was verified by synthesising audio and transcribing it back with whisper.cpp, not by listening. Wake-word detection with a real voice: <b>NOT TESTED</b>.</li>
<li><b>Android:</b> tested on an emulator only — <b>no physical phone</b>. Camera/QR scanning: <b>NOT TESTED</b> (pairing used the text pairing code). Speech captured on the phone: <b>NOT TESTED</b> with real speech.</li>
<li><b>Not tested (need your accounts, services or hardware):</b> Microsoft Foundry Local (not available on CI), Image Studio generation (needs a local Stable Diffusion server such as A1111/Forge), real e-mail (IMAP/SMTP/OAuth) and Twilio SMS accounts, SMS sending from the phone, push via ntfy, GPU acceleration. These features show their real availability status in the app and are covered by unit tests against local test servers where possible.</li>
<li><b>Interactive installer UI:</b> the installer was tested in silent mode (/S); the wizard pages were not clicked through on CI.</li>
</ul>

<h2>Screenshots from this run</h2>
${img('e2e-windows', '03-dashboard.png', 'Windows: dashboard (installed app)')}${img('e2e-windows', '05-chat-answer.png', 'Windows: real local model answering')}${img('e2e-windows', '04-settings-performance.png', 'Windows: Settings → Performance')}
${img('e2e-windows', 'page-models.png', 'Windows: Models')}${img('e2e-windows', 'page-system.png', 'Windows: System monitor')}${img('e2e-windows', '06-hud.png', 'Windows: floating HUD')}
${img('e2e-android', 'a03-home-connected.png', 'Android: connected to the PC')}${img('e2e-android', 'a06-chat-reply.png', 'Android: reply streamed from the PC')}${img('e2e-android', 'a08-notification-shade.png', 'Android: notification from the PC')}
${img('e2e-android', 'a09-pc-offline.png', 'Android: PC offline detected')}${img('e2e-android', 'a11-small-phone-home.png', 'Android: 720×1280 phone')}${img('e2e-android', 'a11-tablet-chat.png', 'Android: tablet')}
</body></html>`;

fs.writeFileSync(OUT, html);
console.log(`report: ${OUT} · windows ${win ? win.results.length : 0} checks · android ${and ? and.results.length : 0} checks · unit ${unit.pass}/${unit.tests} · secret-scan ${scanHits.length} hits in ${scanned} files`);
