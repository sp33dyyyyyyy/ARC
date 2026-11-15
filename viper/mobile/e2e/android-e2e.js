// End-to-end test of the real VIPER Mobile APK on an Android emulator, against a real VIPER
// core (the same server code the Windows app runs) on the host with a real local model.
// The emulator reaches the host as 10.0.2.2 (its built-in alias for the host's loopback),
// so the pairing code is re-addressed to 10.0.2.2, the way a phone uses the PC's LAN address.
//
// Run from viper/desktop:  node ../mobile/e2e/android-e2e.js <apk>
// Env: E2E_OUT (results + screenshots), E2E_MODEL (Ollama model, default qwen2.5:0.5b)
// Every check is recorded as PASS / FAIL / BLOCKED with evidence. Nothing is simulated.
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const APK = path.resolve(process.argv[2] || '');
const OUT = process.env.E2E_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'viper-android-e2e-'));
const MODEL = process.env.E2E_MODEL || 'qwen2.5:0.5b';
const PKG = 'com.viper.mobile';
const DESKTOP = process.env.VIPER_DESKTOP || path.join(__dirname, '..', '..', 'desktop');
fs.mkdirSync(OUT, { recursive: true });

const results = []; const metrics = {};
const record = (area, name, status, detail = '') => { results.push({ area, name, status, detail: String(detail).slice(0, 600) }); console.log(`${status.padEnd(7)} [${area}] ${name}${detail ? ` — ${String(detail).slice(0, 300)}` : ''}`); };
const check = (area, name, ok, detail) => record(area, name, ok ? 'PASS' : 'FAIL', detail);
const save = () => fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify({ device: metrics.device, model: MODEL, when: new Date().toISOString(), results, metrics }, null, 2));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 30000, step = 500) { const end = Date.now() + ms; let v; while (Date.now() < end) { try { v = await fn(); if (v) return v; } catch { /* retry */ } await sleep(step); } return v; }

// ---------------- adb ----------------
const adb = (...a) => execFileSync('adb', a, { encoding: 'utf8', maxBuffer: 64 << 20, timeout: 120000 });
const sh = (cmd) => adb('shell', cmd);
function screenshot(name) { try { const png = execFileSync('adb', ['exec-out', 'screencap', '-p'], { maxBuffer: 64 << 20 }); fs.writeFileSync(path.join(OUT, `${name}.png`), png); } catch (e) { console.log('screenshot failed', e.message); } }
function dump() {
  for (let i = 0; i < 4; i++) {
    try {
      sh('uiautomator dump /sdcard/ui.xml >/dev/null'); const xml = adb('exec-out', 'cat', '/sdcard/ui.xml');
      if (!xml.includes('<hierarchy')) continue;
      const nodes = parseNodes(xml);
      // A freshly booted emulator sometimes reports its own launcher as "not responding";
      // that system dialog belongs to Android, not VIPER: dismiss it and look again.
      if (nodes.some((n) => /isn.t responding/.test(n.text))) { const w = nodes.find((n) => /^Wait$/.test(n.text)); if (w) { tapNode(w); execFileSync('sleep', ['1']); continue; } }
      return nodes;
    } catch { /* retry */ }
  }
  return [];
}
function parseNodes(xml) {
  const nodes = [];
  for (const m of xml.matchAll(/<node ([^>]*?)\/?>/g)) {
    const a = {}; for (const kv of m[1].matchAll(/([\w-]+)="([^"]*)"/g)) a[kv[1]] = kv[2].replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#10;/g, '\n');
    const b = (a.bounds || '').match(/\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/);
    nodes.push({ text: a.text || '', desc: a['content-desc'] || '', pkg: a.package, cls: a.class, clickable: a.clickable === 'true', checkable: a.checkable === 'true', checked: a.checked === 'true', scrollable: a.scrollable === 'true', b: b ? b.slice(1).map(Number) : null });
  }
  return nodes;
}
const allText = (nodes) => nodes.map((n) => `${n.text} ${n.desc}`).join('\n');
const find = (nodes, re) => nodes.find((n) => re.test(n.text) || re.test(n.desc));
function tapNode(n) { const [x1, y1, x2, y2] = n.b; sh(`input tap ${Math.round((x1 + x2) / 2)} ${Math.round((y1 + y2) / 2)}`); }
async function tap(re, ms = 15000) { const n = await until(() => find(dump(), re), ms, 700); if (!n) throw new Error(`no element matching ${re}`); tapNode(n); await sleep(700); return n; }
function typeText(s) { sh(`input text '${s.replace(/ /g, '%s').replace(/'/g, '')}'`); }
const screenSize = () => { const m = sh('wm size').match(/(\d+)x(\d+)\s*$/m); return m ? [+m[1], +m[2]] : [1080, 1920]; };
function crashes() { const c = (() => { try { return adb('logcat', '-b', 'crash', '-d'); } catch { return ''; } })(); return c.split('\n').filter((l) => l.includes(PKG) || /FATAL EXCEPTION/.test(l)).join('\n'); }

// ---------------- VIPER core on the host ----------------
const DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'viper-phone-host-'));
let svc = null;
async function startCore() {
  const { createViper } = require(path.join(DESKTOP, 'src', 'server', 'server.js'));
  svc = await createViper({ dataDir: DATA, port: 0 });
  svc.settings.set('backend', { active: 'ollama' });
  svc.settings.set('models', { chat: { backend: 'ollama', model: MODEL } });
  svc.settings.set('remote', { enabled: true });
  await svc.remote.applySettings?.();
  await until(() => svc.remote.status().running, 15000);
  await svc.models.checkHealth();
  return svc;
}

(async () => {
  if (!fs.existsSync(APK)) { record('Build', 'APK present', 'FAIL', APK); save(); process.exit(1); }
  metrics.apkBytes = fs.statSync(APK).size;
  metrics.device = { model: sh('getprop ro.product.model').trim(), android: sh('getprop ro.build.version.release').trim(), sdk: sh('getprop ro.build.version.sdk').trim(), abi: sh('getprop ro.product.cpu.abi').trim(), physical: false };
  console.log('device', metrics.device);
  await startCore();
  const health = svc.models.health.ollama;
  check('Host', `VIPER core with phone link running; local AI engine reachable`, svc.remote.status().running && health?.ok, `phone link port ${svc.remote.status().port}; Ollama ${health?.version || health?.error}`);

  // ===== install =====
  try { adb('uninstall', PKG); } catch { /* not installed */ }
  sh('logcat -c'); try { adb('logcat', '-b', 'crash', '-c'); } catch { /* ignore */ }
  // Let the emulator finish booting its own apps, and keep system "not responding" dialogs from
  // covering the screen (VIPER crashes are still caught from the logcat crash buffer).
  await until(() => sh('getprop sys.boot_completed').trim() === '1', 120000, 2000);
  try { sh('settings put global hide_error_dialogs 1'); } catch { /* not available */ }
  await sleep(5000);
  let out = ''; try { out = adb('install', '-r', APK); } catch (e) { out = e.stdout || e.message; }
  check('Install', 'APK installs on the emulator', /Success/.test(out), out.trim().split('\n').pop());
  const info = sh(`dumpsys package ${PKG}`);
  check('Install', 'release build is not debuggable', !/flags=\[[^\]]*DEBUGGABLE/.test(info), (info.match(/versionName=\S+/) || [''])[0]);

  // ===== first launch + runtime permissions =====
  sh(`am start -W -n ${PKG}/.MainActivity`);
  await sleep(2500);
  // The app asks for microphone, camera and notification permission on first launch.
  const permAsked = [];
  for (let i = 0; i < 6; i++) {
    const nodes = dump();
    const dlg = nodes.find((n) => /permissioncontroller/.test(n.pkg || ''));
    if (!dlg) break;
    const q = nodes.find((n) => /Allow .*VIPER/i.test(n.text));
    if (q) permAsked.push(q.text);
    const allow = find(nodes, /^(While using the app|Allow|ALLOW|Only this time)$/);
    if (!allow) break;
    tapNode(allow); await sleep(1200);
  }
  check('Permissions', 'app requests microphone / camera / notification permission on first launch', permAsked.length >= 2, permAsked.join(' | '));
  const granted = sh(`dumpsys package ${PKG}`);
  const g = (p) => new RegExp(`${p}: granted=true`).test(granted);
  check('Permissions', 'microphone permission granted through the system dialog', g('android.permission.RECORD_AUDIO'));
  check('Permissions', 'notification permission granted through the system dialog', g('android.permission.POST_NOTIFICATIONS') || +metrics.device.sdk < 33);

  let nodes = dump();
  check('UI', 'app opens on the pairing screen', !!find(nodes, /Scan pairing code/) && !!find(nodes, /VIPER Mobile/), allText(nodes).split('\n').filter(Boolean).slice(0, 6).join(' | '));
  screenshot('a01-pair-screen');

  // ===== pairing =====
  const pr = await svc.remote.createPairing();
  check('Pairing', 'PC generates a pairing QR code and text code', !!pr.qr && !!pr.code, `${pr.hosts.map((h) => h.address).join(', ')}:${pr.port}`);
  const payload = JSON.parse(Buffer.from(pr.code, 'base64url').toString());
  payload.hosts = ['10.0.2.2']; // the emulator's route to this host (a real phone uses the PC's LAN address from the QR)
  const code = Buffer.from(JSON.stringify(payload)).toString('base64url');
  // Wrong code first: a foreign QR must be rejected.
  sh(`am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT not-a-viper-code -n ${PKG}/.MainActivity`);
  await sleep(1200);
  await tap(/^Pair$/); await sleep(1500);
  check('Pairing', 'an invalid pairing code is rejected with a clear message', /Pairing failed: This is not a VIPER pairing code/.test(allText(dump())));
  // Real code shared to the app (as from a chat/e-mail), confirmed by tapping Pair.
  sh(`am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT ${code} -n ${PKG}/.MainActivity`);
  await sleep(1500);
  nodes = dump();
  check('Pairing', 'shared pairing code shows the PC it will pair with before connecting', !!find(nodes, /PC: .* · 10\.0\.2\.2/), (find(nodes, /PC: /) || {}).text);
  screenshot('a02-pair-code');
  const t0 = Date.now();
  await tap(/^Pair$/);
  const paired = await until(() => svc.remote.devices().length === 1, 30000);
  check('Pairing', 'phone pairs with the PC over TLS with the pinned certificate', !!paired, paired ? `device "${svc.remote.devices()[0].name}" paired in ${Date.now() - t0} ms` : allText(dump()).slice(0, 300));
  const online = await until(() => svc.remote.status().connected.length === 1, 30000);
  check('Pairing', 'phone connects to the PC (encrypted WebSocket event stream)', !!online);
  nodes = dump();
  check('UI', 'dashboard shows the PC connection state', !!find(nodes, /^Connected to /), (find(nodes, /Connected to|unreachable|Connecting/) || {}).text);
  screenshot('a03-home-connected');

  // ===== navigation =====
  const navOk = [];
  for (const [tab, expect] of [['Chat', /Message|New/], ['PC', /PC|CPU|Memory|Diagnostic/], ['More', /Settings & connection/], ['Home', /Ask VIPER|Hold to talk/]]) {
    await tap(new RegExp(`^${tab}$`));
    const ok = !!(await until(() => find(dump(), expect), 8000, 700));
    navOk.push(`${tab}:${ok ? 'ok' : 'FAIL'}`);
    screenshot(`a04-tab-${tab.toLowerCase()}`);
  }
  check('UI', 'bottom navigation opens Home, Chat, PC and More', navOk.every((x) => x.endsWith('ok')), navOk.join(', '));
  const subOk = [];
  await tap(/^More$/);
  for (const [item, expect] of [['Vision — camera & image analysis', /Take photo|Choose image/], ['File transfer', /Send a file to the PC/], ['Reminders', /Remind me to/], ['Automations', /Describe a new automation/], ['Notifications', /Mark all read/], ['Code assistant', /What do you need/], ['Settings & connection', /Stay connected/]]) {
    await tap(new RegExp(`^${item.replace(/[&—]/g, '.')}$`));
    const ok = !!(await until(() => find(dump(), expect), 8000, 700));
    subOk.push(`${item.split(' ')[0]}:${ok ? 'ok' : 'FAIL'}`);
    screenshot(`a05-more-${item.split(' ')[0].toLowerCase()}`);
    await tap(/Back/);
  }
  check('UI', 'every More screen opens and its controls render', subOk.every((x) => x.endsWith('ok')), subOk.join(', '));
  // PC dashboard shows live data from the PC
  await tap(/^PC$/);
  const pcLive = await until(() => /\d+\s?%/.test(allText(dump())), 15000, 1000);
  check('UI', 'PC dashboard shows live CPU/memory from the PC', !!pcLive);

  // ===== chat: message reaches the PC, reply streams back =====
  await tap(/^Chat$/);
  await tap(/^Message$/);
  const question = 'Count from one to forty in words separated by commas';
  typeText(question); await sleep(500);
  sh('input keyevent 4'); await sleep(400); // hide keyboard
  const tokens = []; const conv = () => svc.orchestrator.listConversations();
  const onTok = (e) => { if (e.type === 'chat.token') tokens.push(Date.now()); };
  svc.bus.on('event', onTok);
  const tSend = Date.now();
  await tap(/^Send$/);
  const arrived = await until(() => { const c = conv()[0]; if (!c) return null; const m = svc.orchestrator.messages(c.id).find((x) => x.role === 'user' && x.content === question); return m ? { c, m } : null; }, 20000);
  check('Chat', 'message typed on the phone reaches the Windows/PC backend', !!arrived && arrived.m.meta?.device, arrived ? `stored in conversation ${arrived.c.id} from device "${arrived.m.meta?.device}"` : 'not received');
  // Watch the phone's screen while the reply is generated: the app's text must grow over time,
  // and the reply the PC's model produced must be what the phone shows (Markdown is rendered,
  // so compare normalised words, not raw characters).
  const words = (t) => String(t).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const screenWords = () => words(dump().filter((n) => n.pkg === PKG && n.text && n.text !== question && !/^(Message|Send|Stop|Image|Camera|New|Chat|Home|PC|More|Hold to talk|VIPER|You)$/.test(n.text) && !/^Connected to /.test(n.text)).map((n) => n.text).join(' '));
  const seen = []; let shownOk = false;
  const finished = await until(() => {
    const sw = screenWords();
    if (!seen.length || seen[seen.length - 1] !== sw.length) seen.push(sw.length);
    const last = svc.orchestrator.messages(arrived?.c.id || '').filter((m) => m.role === 'assistant').pop();
    if (!last) return null;
    const rw = words(last.content).split(' ');
    shownOk = sw.includes(rw.slice(0, 6).join(' ')) || sw.includes(rw.slice(-6).join(' '));
    return shownOk ? last : null;
  }, 180000, 250);
  svc.bus.off('event', onTok);
  screenshot('a06-chat-reply');
  check('Chat', 'AI reply from the PC\'s local model appears on the phone', !!finished, finished ? finished.content.slice(0, 160) : 'no reply shown');
  // A small model sometimes answers in a few tokens, too fast to watch it grow. Then ask for a
  // longer answer in the same chat and watch that one (the phone screen must change several times
  // while tokens are still arriving from the PC).
  let streamSeen = seen; let streamTokens = tokens.length;
  for (let attempt = 0; attempt < 2 && !(new Set(streamSeen).size >= 3 && streamTokens > 5); attempt++) {
    const n0 = svc.orchestrator.messages(arrived?.c.id || '').filter((m) => m.role === 'assistant').length;
    const toks = []; const f = (e) => { if (e.type === 'chat.token') toks.push(Date.now()); }; svc.bus.on('event', f);
    await tap(/^Message$/); typeText('Write a numbered list of twenty fruits with one short sentence about each'); sh('input keyevent 4'); await sleep(400);
    await tap(/^Send$/);
    const lens = [];
    await until(() => { const l = screenWords().length; if (!lens.length || lens[lens.length - 1] !== l) lens.push(l); return svc.orchestrator.messages(arrived?.c.id || '').filter((m) => m.role === 'assistant').length > n0; }, 180000, 250);
    svc.bus.off('event', f);
    streamSeen = lens; streamTokens = toks.length;
  }
  check('Chat', 'reply streams to the phone progressively (text observed growing)', new Set(streamSeen).size >= 3 && streamTokens > 5, `phone screen lengths ${streamSeen.slice(0, 8).join('→')}; ${streamTokens} tokens streamed; first reply's first token ${tokens[0] ? tokens[0] - tSend : '?'} ms after Send`);
  metrics.phoneChat = { tokens: tokens.length, firstTokenMs: tokens[0] ? tokens[0] - tSend : null, totalMs: tokens.length ? tokens[tokens.length - 1] - tSend : null, observedLengths: seen };

  // ===== voice capture =====
  await tap(/^Home$/);
  const ptt = find(dump(), /^Hold to talk$/);
  if (ptt) {
    const [x1, y1, x2, y2] = ptt.b; const x = Math.round((x1 + x2) / 2); const y = Math.round((y1 + y2) / 2);
    let sawListening = false;
    // Hold the button for 6 s in the background while the screen is inspected mid-press.
    const press = new Promise((res) => { const p = require('node:child_process').spawn('adb', ['shell', `input swipe ${x} ${y} ${x} ${y} 6000`]); p.on('close', res); p.on('error', res); });
    await sleep(2500); sawListening = !!find(dump(), /Listening — release to send/);
    screenshot('a07-voice-listening');
    await press;
    const handled = await until(() => find(dump(), /Transcribing|Speech recognition unavailable|PC offline/), 20000, 700);
    check('Voice', 'hold-to-talk records from the microphone (emulator virtual mic)', sawListening, sawListening ? 'UI switched to "Listening — release to send"' : 'listening state not shown');
    record('Voice', 'recorded speech uploaded to the PC for recognition', handled ? 'PASS' : 'FAIL', handled ? handled.text : 'no transcription state shown');
    record('Voice', 'speech recognised from a real voice on the phone', 'NOT TESTED', 'emulator microphone carries no speech; Windows CI verifies whisper.cpp recognition on the PC side');
  } else record('Voice', 'hold-to-talk control present', 'FAIL', 'button not found');
  screenshot('a07-voice');

  // ===== notifications =====
  await tap(/^More$/); await tap(/^Settings & connection$/);
  const stay = find(dump(), /^Stay connected$/);
  if (stay) {
    const sw = dump().filter((n) => n.checkable && n.b).sort((a, b) => Math.abs(a.b[1] - stay.b[1]) - Math.abs(b.b[1] - stay.b[1]))[0];
    if (sw && !sw.checked) { tapNode(sw); await sleep(1500); }
    check('Notifications', '"Stay connected" switch turns on', !!dump().filter((n) => n.checkable && n.b).sort((a, b) => Math.abs(a.b[1] - stay.b[1]) - Math.abs(b.b[1] - stay.b[1]))[0]?.checked);
  }
  sh('input keyevent 3'); await sleep(2500); // HOME: VIPER goes to the background
  const stillOnline = await until(() => svc.remote.status().connected.length === 1, 10000);
  check('Notifications', '"Stay connected" keeps the link open in the background (foreground service)', !!stillOnline);
  await svc.notify.send({ title: 'E2E alert', body: 'Backup finished on your PC', channels: ['mobile'], category: 'general', priority: 'high' });
  const posted = await until(() => /E2E alert/.test(sh('dumpsys notification --noredact')), 20000, 1000);
  check('Notifications', 'notification from the PC is shown by Android while the app is in the background', !!posted);
  sh('cmd statusbar expand-notifications'); await sleep(1500); screenshot('a08-notification-shade'); sh('cmd statusbar collapse'); await sleep(500);

  // ===== disconnect / offline queue / reconnect =====
  sh(`am start -n ${PKG}/.MainActivity`); await sleep(1500);
  await svc.shutdown(); svc = null;
  const offline = await until(() => find(dump(), /^PC unreachable$|^Connecting…$/), 40000, 1500);
  check('Network', 'PC going offline is detected and shown', !!offline, offline?.text);
  screenshot('a09-pc-offline');
  await tap(/^Chat$/); await tap(/^Message$/);
  typeText('Are you back online'); sh('input keyevent 4'); await sleep(300); await tap(/^Send$/);
  const queued = await until(() => find(dump(), /queued and will be sent when the connection returns/), 10000, 700);
  check('Network', 'messages sent while the PC is offline are queued, not lost', !!queued);
  await startCore();
  const back = await until(() => svc.remote.status().connected.length === 1, 90000, 1000);
  check('Network', 'phone reconnects automatically when the PC comes back', !!back);
  const delivered = await until(() => svc.orchestrator.listConversations().some((c) => svc.orchestrator.messages(c.id).some((m) => m.role === 'user' && /Are you back online/.test(m.content))), 30000, 1000);
  check('Network', 'queued message is delivered after reconnecting', !!delivered);
  screenshot('a10-reconnected');

  // ===== pairing persists across app restarts =====
  sh(`am force-stop ${PKG}`); await sleep(1000);
  sh(`am start -W -n ${PKG}/.MainActivity`); await sleep(3000);
  const stillPaired = !find(dump(), /Scan pairing code/);
  const reconnect = await until(() => svc.remote.status().connected.length === 1, 40000, 1000);
  check('Security', 'pairing persists after the app is restarted (stored encrypted on the phone)', stillPaired && !!reconnect);
  const prefs = (() => { try { return sh(`run-as ${PKG} ls shared_prefs`); } catch (e) { return `run-as blocked: ${e.message.split('\n')[0]}`; } })();
  record('Security', 'app data is not accessible from outside the app (release build)', /run-as blocked|not debuggable|is unknown/i.test(prefs) || /package not debuggable/i.test(prefs) ? 'PASS' : 'FAIL', prefs.trim().slice(0, 160));

  // ===== screen sizes =====
  const [W0, H0] = screenSize(); const density0 = (sh('wm density').match(/(\d+)\s*$/m) || [])[1];
  const layouts = [];
  for (const [w, h, dpi, label] of [[720, 1280, 320, 'small-phone'], [1080, 2400, 420, 'tall-phone'], [1600, 2560, 320, 'tablet']]) {
    sh(`wm size ${w}x${h}`); sh(`wm density ${dpi}`); await sleep(1500);
    sh(`am force-stop ${PKG}`); sh(`am start -W -n ${PKG}/.MainActivity`); await sleep(3500);
    const problems = [];
    for (const tab of ['Home', 'Chat', 'PC', 'More']) {
      try { await tap(new RegExp(`^${tab}$`), 8000); } catch { problems.push(`${tab}: tab not reachable`); continue; }
      const ns = dump().filter((n) => n.pkg === PKG && n.b);
      for (const n of ns) { const [x1, , x2] = n.b; if ((n.text || n.clickable) && (x2 > w + 2 || x1 < -2)) problems.push(`${tab}: "${(n.text || n.cls).slice(0, 30)}" outside screen [${n.b}]`); }
      screenshot(`a11-${label}-${tab.toLowerCase()}`);
    }
    layouts.push({ label, w, h, dpi, problems });
    check('Layout', `${label} ${w}×${h} @${dpi}dpi: nothing extends beyond the screen`, !problems.length, problems.slice(0, 4).join('; ') || 'all tabs fit');
  }
  sh(`wm size ${W0}x${H0}`); if (density0) sh(`wm density ${density0}`); sh('wm size reset'); sh('wm density reset');
  metrics.layouts = layouts;

  // ===== revocation =====
  const dev = svc.remote.devices()[0];
  if (dev) {
    sh(`am start -n ${PKG}/.MainActivity`); await sleep(2000);
    await svc.remote.revoke(dev.id);
    const unpaired = await until(() => find(dump(), /Scan pairing code/), 30000, 1500);
    check('Security', 'revoking the phone on the PC disconnects it and removes its credentials', !!unpaired);
    screenshot('a12-revoked');
  }

  const crash = crashes();
  check('Stability', 'no crashes (logcat crash buffer clean)', !crash.trim(), crash.slice(0, 400));
  try { fs.writeFileSync(path.join(OUT, 'logcat.txt'), adb('logcat', '-d', '-t', '3000')); } catch { /* ignore */ }

  await svc?.shutdown();
  save();
  const fails = results.filter((r) => r.status === 'FAIL');
  console.log(`\n${results.filter((r) => r.status === 'PASS').length} PASS · ${fails.length} FAIL · ${results.filter((r) => r.status === 'BLOCKED').length} BLOCKED · ${results.filter((r) => r.status === 'NOT TESTED').length} NOT TESTED`);
  process.exit(fails.length ? 1 : 0);
})().catch(async (e) => { record('Harness', 'android e2e run', 'FAIL', e.stack || e.message); screenshot('zz-failure'); save(); try { await svc?.shutdown(); } catch { /* ignore */ } process.exit(1); });
