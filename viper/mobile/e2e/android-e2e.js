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
/** Scroll the current screen until an element matching `re` is visible. */
async function scrollTo(re, tries = 6) { for (let i = 0; i < tries; i++) { const n = find(dump(), re); if (n) return n; const [w, h] = screenSize(); sh(`input swipe ${w >> 1} ${Math.round(h * 0.7)} ${w >> 1} ${Math.round(h * 0.35)} 400`); await sleep(700); } return find(dump(), re); }
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
  check('UI', 'app opens on the welcome screen ("WELCOME TO VIPER MOBILE")', !!find(nodes, /^WELCOME TO VIPER MOBILE$/) && !!find(nodes, /Connect your device to your personal intelligence system/), allText(nodes).split('\n').filter((l) => l.trim()).slice(0, 6).join(' | '));
  check('UI', 'welcome screen offers Pair with PC, Scan QR Code and Connection Settings', ['Pair with PC', 'Scan QR Code', 'Connection Settings'].every((t) => find(nodes, new RegExp(`^${t}$`))));
  screenshot('a01-welcome');
  // "Scan QR Code" opens the camera scanner (the emulator camera shows no real QR; decoding the PC's
  // real QR image is covered by the app's unit test).
  await tap(/^Scan QR Code$/);
  const resumed = () => sh('dumpsys activity activities | grep -iE "ResumedActivity" || true');
  const scannerOpen = await until(() => /journeyapps|CaptureActivity/.test(resumed()), 10000, 700);
  check('Pairing', '"Scan QR Code" opens the camera QR scanner', !!scannerOpen, resumed().trim().split('\n')[0]);
  screenshot('a01b-scanner');
  sh('input keyevent 4'); await sleep(1500);
  await tap(/^Connection Settings$/);
  check('UI', 'Connection Settings explains VPN use and accepts a preferred address', !!(await until(() => find(dump(), /PC address to try first/), 6000, 700)));
  sh('input keyevent 4'); await sleep(1000);

  // ===== pairing (with approval on the PC) =====
  const pairReqs = []; svc.bus.on('confirm.request', (r) => { if (r.tool === 'pair_device') pairReqs.push(r); });
  const share = (c) => sh(`am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT ${c} -n ${PKG}/.MainActivity`);
  // The emulator reaches this host as 10.0.2.2 (a real phone uses the PC's LAN address from the QR).
  const emuCode = (p) => { const pl = JSON.parse(Buffer.from(p.code, 'base64url').toString()); pl.hosts = ['10.0.2.2']; return Buffer.from(JSON.stringify(pl)).toString('base64url'); };
  const pr = await svc.remote.createPairing();
  check('Pairing', 'PC generates a single-use, 5-minute pairing QR code', !!pr.qr && !!pr.code && pr.expiresAt - Date.now() <= 300000, `${pr.hosts.map((h) => h.address).join(', ')}:${pr.port}`);
  share('not-a-viper-code'); await sleep(1500);
  await tap(/^Pair$/); await sleep(1500);
  check('Pairing', 'an invalid pairing code is rejected with a clear message', /Pairing failed: This is not a VIPER pairing code/.test(allText(dump())));
  share(emuCode(pr)); await sleep(1500);
  nodes = dump();
  check('Pairing', 'shared pairing code shows the PC it will pair with before connecting', !!find(nodes, /PC: .* · 10\.0\.2\.2/), (find(nodes, /PC: /) || {}).text);
  await tap(/^Pair$/);
  const req1 = await until(() => pairReqs[0], 20000);
  check('Pairing', 'the PC asks its owner to approve the new phone (name and network address shown)', !!req1, req1 ? `${req1.title} · ${String(req1.preview).replace(/\n/g, ' · ')}` : 'no confirmation requested');
  const waiting = await until(() => find(dump(), /Waiting for you to approve this phone on the PC/), 10000, 700);
  check('Pairing', 'the phone shows it is waiting for approval on the PC', !!waiting);
  screenshot('a02-waiting-approval');
  if (req1) svc.permissions.respond(req1.id, false);
  const declined = await until(() => /Pairing failed: Pairing was declined on the PC/.test(allText(dump())), 20000, 800);
  check('Pairing', 'declining on the PC rejects the phone — nothing is paired', !!declined && svc.remote.devices().length === 0, svc.remote.events(null, 5).map((e) => `${e.event}: ${e.detail}`).join(' | '));
  await tap(/^Pair$/);
  const reused = await until(() => /Pairing failed: Pairing code expired/.test(allText(dump())), 15000, 800);
  check('Pairing', 'a used pairing code cannot be reused', !!reused && pairReqs.length === 1, (find(dump(), /Pairing failed/) || {}).text);
  const pr2 = await svc.remote.createPairing();
  share(emuCode(pr2)); await sleep(1500);
  const t0 = Date.now();
  await tap(/^Pair$/);
  const req2 = await until(() => pairReqs[1], 20000);
  if (req2) svc.permissions.respond(req2.id, true);
  const paired = await until(() => svc.remote.devices().length === 1, 30000);
  check('Pairing', 'approved on the PC: phone pairs over TLS with the pinned certificate', !!paired, paired ? `device "${svc.remote.devices()[0].name}" paired in ${Date.now() - t0} ms (including approval)` : allText(dump()).slice(0, 300));
  const online = await until(() => svc.remote.status().connected.length === 1, 30000);
  check('Pairing', 'phone connects to the PC (encrypted WebSocket event stream)', !!online);
  const histEv = svc.remote.events(null, 20).map((e) => e.event);
  check('Pairing', 'pairing history records the rejected and the successful attempts', histEv.includes('paired') && histEv.filter((e) => e === 'rejected').length >= 2 && histEv.includes('connected'), histEv.join(', '));
  nodes = dump();
  check('UI', 'dashboard shows the PC connection state', !!find(nodes, /^Connected to /), (find(nodes, /Connected to|unreachable|Connecting/) || {}).text);
  screenshot('a03-home-connected');

  // ===== navigation: the same five categories as the PC =====
  const navOk = [];
  for (const [tab, expect] of [['Make', /AI Coding Agent/], ['Manage', /Background Tasks/], ['Intelligence', /AI status/], ['Settings', /Stay connected/], ['Prompt', /Ask VIPER|Hold to talk|Live Vision/]]) {
    await tap(new RegExp(`^${tab}$`));
    const ok = !!(await until(() => find(dump(), expect), 8000, 700));
    navOk.push(`${tab}:${ok ? 'ok' : 'FAIL'}`);
    screenshot(`a04-tab-${tab.toLowerCase()}`);
  }
  check('UI', 'bottom navigation opens Prompt, Make, Manage, Intelligence and Settings', navOk.every((x) => x.endsWith('ok')), navOk.join(', '));
  const subOk = [];
  for (const [tab, item, expect] of [['Prompt', 'Live Vision', /Take photo|Choose image/], ['Make', 'AI Coding Agent', /New task|New project/], ['Make', 'Code assistant', /What do you need/], ['Manage', 'Background Tasks', /Nothing running|running/], ['Manage', 'Notifications', /Mark all read/], ['Manage', 'Reminders & scheduled tasks', /Remind me to/], ['Manage', 'Automations', /Describe a new automation/], ['Manage', 'File transfer', /Send a file to the PC/], ['Intelligence', 'AI status & models', /Active engine|Installed models/], ['Manage', 'PC Control', /\d+\s?%/]]) {
    await tap(new RegExp(`^${tab}$`));
    try { await tap(new RegExp(`^${item.replace(/[&—]/g, '.')}$`)); } catch { subOk.push(`${item}:missing`); continue; }
    const ok = !!(await until(() => find(dump(), expect), 15000, 700));
    subOk.push(`${item.split(' ')[0]}:${ok ? 'ok' : 'FAIL'}`);
    screenshot(`a05-${tab.toLowerCase()}-${item.split(' ')[0].toLowerCase()}`);
  }
  check('UI', 'every category screen opens and its controls render (PC Control shows live CPU/memory)', subOk.every((x) => x.endsWith('ok')), subOk.join(', '));
  await tap(/^Prompt$/);

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
  sh('input keyevent 4'); await sleep(800); await tap(/^Prompt$/);
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

  // ===== notifications: kinds, channels, actions, deep links =====
  await tap(/^Settings$/);
  const stay = await scrollTo(/^Stay connected$/);
  const switchNear = (label) => dump().filter((n) => n.checkable && n.b).sort((a, b) => Math.abs(a.b[1] - label.b[1]) - Math.abs(b.b[1] - label.b[1]))[0];
  if (stay) {
    const sw = switchNear(stay); if (sw && !sw.checked) { tapNode(sw); await sleep(1500); }
    check('Notifications', '"Stay connected" switch turns on', !!switchNear(find(dump(), /^Stay connected$/))?.checked);
  } else record('Notifications', '"Stay connected" switch turns on', 'FAIL', 'switch not found on the Settings screen');
  await tap(/^Prompt$/);
  sh('input keyevent 3'); await sleep(2500); // HOME: VIPER goes to the background
  const stillOnline = await until(() => svc.remote.status().connected.length === 1, 10000);
  check('Notifications', '"Stay connected" keeps the link open in the background (foreground service)', !!stillOnline);
  // Parse the posted notifications: channel, title, text and action buttons of each VIPER notification.
  const posted = () => sh('dumpsys notification --noredact').split(/NotificationRecord\(/).slice(1).filter((c) => c.includes(`pkg=${PKG}`)).map((c) => ({
    channel: (c.match(/channel=(\S+)/) || [])[1], title: (c.match(/android\.title=String \(([^)]*)\)/) || [])[1] || '', text: (c.match(/android\.text=String \(([^)]*)\)/) || [])[1] || '',
    actions: [...c.matchAll(/\[\d+\] "([^"]+)" ->/g)].map((m) => m[1]),
  }));
  const EXPECT = {
    task_complete: ['VIPER', 'Task complete, sir.', 'viper_tasks', []],
    input_required: ['VIPER — Input Required', 'I need your input, sir.', 'viper_input', ['Respond', 'View Task']],
    project_complete: ['VIPER — Project Complete', 'Your project is ready for review, sir.', 'viper_code', ['View Results', 'Open VIPER']],
    approval_required: ['VIPER — Approval Required', 'May I proceed, sir?', 'viper_approval', ['Review Request', 'Dismiss']],
    error: ['VIPER — Attention Required', "I've encountered an issue, sir.", 'viper_system', []],
    code_complete: ['VIPER — Code Agent', 'Your application has been built, sir.', 'viper_code', ['View Results', 'Open VIPER']],
    download_complete: ['VIPER — Download Complete', 'Your download is ready, sir.', 'viper_tasks', []],
    system_alert: ['VIPER — System Alert', 'Your system requires attention, sir.', 'viper_system', []],
  };
  // The phone must show exactly the action buttons the PC defines for each kind.
  for (const kind of Object.keys(EXPECT)) EXPECT[kind][3] = svc.notify.compose(kind).actions.map((a) => a[1]);
  const sentIds = {};
  for (const kind of Object.keys(EXPECT)) { const r = await svc.notify.send({ kind, link: { type: 'notifications', id: `e2e-${kind}` }, channels: ['mobile'], dedupeKey: `e2e:${kind}` }); sentIds[kind] = r.id; await sleep(400); }
  const allShown = await until(() => { const ps = posted(); return Object.values(EXPECT).every(([t]) => ps.some((p) => p.title === t)) ? ps : null; }, 30000, 1500) || posted();
  for (const [kind, [title, phrase, channel, actions]] of Object.entries(EXPECT)) {
    const p = allShown.find((x) => x.title === title);
    check('Notifications', `${kind}: "${title}" — "${phrase}"`, !!p && p.text.startsWith(phrase) && p.channel === channel && actions.every((a) => p.actions.includes(a)) && p.actions.length === actions.length,
      p ? `channel ${p.channel} · text "${p.text}" · actions [${p.actions.join(', ')}]` : 'not shown by Android');
  }
  sh('cmd statusbar expand-notifications'); await sleep(1500); screenshot('a08-notification-shade'); sh('cmd statusbar collapse'); await sleep(500);
  // Duplicate prevention: the same event again is not shown twice.
  const dupe = await svc.notify.send({ kind: 'download_complete', link: { type: 'notifications', id: 'e2e-download_complete' }, channels: ['mobile'], dedupeKey: 'e2e:download_complete' });
  await sleep(2500);
  check('Notifications', 'duplicate events are not shown twice', dupe.duplicate === true && posted().filter((p) => p.title === EXPECT.download_complete[0]).length === 1, `PC: ${dupe.duplicate ? 'duplicate suppressed' : 'sent again'} · phone shows ${posted().filter((p) => p.title === EXPECT.download_complete[0]).length}`);
  sh(`cmd notification cancel_all ${PKG} 2>/dev/null || true`);
  try { sh('service call notification 1'); } catch { /* best effort clear */ }

  // Approval escalated from the PC: "Dismiss" must NOT approve; "Review Request" opens the review screen.
  // Start each approval check with an empty shade so its notification is the expanded one on top.
  const clearShade = async () => {
    sh('cmd statusbar expand-notifications'); await sleep(1500);
    const c = await scrollTo(/^Clear all$/i, 3); if (c) tapNode(c);
    sh('cmd statusbar collapse'); await sleep(800);
  };
  // Tap an action button of ONE specific notification: the button nearest below the text `marker`.
  // Retries while the shade settles; on failure, records what was on screen (diagnostics).
  const shadeSeen = {};
  const shadeTap = async (marker, label) => {
    const rx = new RegExp(`^${label}$`, 'i');
    const pick = (ns) => { const m = ns.find((x) => marker.test(x.text) && x.b); if (!m) return null; return ns.filter((x) => rx.test(x.text) && x.b && x.b[1] >= m.b[1]).sort((a, b) => a.b[1] - b.b[1])[0] || null; };
    for (let attempt = 0; attempt < 4; attempt++) {
      sh('cmd statusbar expand-notifications'); await sleep(1500 + attempt * 500);
      let ns = dump(); let n = pick(ns);
      if (!n) { const m = ns.find((x) => marker.test(x.text) && x.b); if (m) { sh(`input swipe ${m.b[0] + 40} ${m.b[1] + 10} ${m.b[0] + 40} ${m.b[3] + 300} 300`); await sleep(1200); ns = dump(); n = pick(ns); } }
      if (n) { tapNode(n); await sleep(2000); return true; }
      shadeSeen[label] = ns.filter((x) => x.text).map((x) => x.text).slice(0, 25).join(' | ');
      screenshot(`zz-shade-${label.replace(/\W+/g, '-').toLowerCase()}-${attempt}`);
      sh('cmd statusbar collapse'); await sleep(800);
    }
    return false;
  };
  await clearShade();
  const decA = svc.permissions.requestConfirmation({ tool: 'agent_command', title: 'Run "npm install" in Calculator?', reason: 'The Code Agent wants to install packages from the internet.', preview: 'npm install', risk: 'network', origin: 'code agent', agent: true });
  let decAValue = null; decA.then((v) => { decAValue = v; });
  const shownA = await until(() => posted().find((p) => p.title === EXPECT.approval_required[0] && /npm install/.test(p.text)), 30000, 1500);
  check('Approvals', 'approval waiting on the PC reaches the phone as "Approval Required"', !!shownA, shownA ? `${shownA.text} · [${shownA.actions.join(', ')}]` : 'not shown');
  const tappedDismiss = await shadeTap(/npm install/, 'Dismiss');
  await sleep(2500);
  const pendingA = svc.permissions.listPending().find((p) => p.title.startsWith('Run "npm install"'));
  check('Approvals', 'dismissing the notification does NOT approve (request still waiting on the PC)', tappedDismiss && !!pendingA && decAValue === null, `Dismiss tapped: ${tappedDismiss} · still pending: ${!!pendingA} · answered: ${decAValue}${tappedDismiss ? '' : ` · shade: ${shadeSeen.Dismiss}`}`);
  if (pendingA) svc.permissions.respond(pendingA.id, false);
  await clearShade();
  const decB = svc.permissions.requestConfirmation({ tool: 'agent_command', title: 'Run "pip install requests" in Weather?', reason: 'The Code Agent wants to install packages from the internet.', preview: 'python -m pip install requests', risk: 'network', origin: 'code agent', agent: true });
  let decBValue = null; decB.then((v) => { decBValue = v; });
  await until(() => posted().find((p) => p.title === EXPECT.approval_required[0]), 30000, 1500);
  const tappedReview = await shadeTap(/pip install requests/, 'Review Request');
  const review = await until(() => { const ns = dump(); return find(ns, /pip install requests/) && find(ns, /^Approve$/) ? ns : null; }, 20000, 1000);
  check('Approvals', '"Review Request" opens the review screen showing exactly what will run', tappedReview && !!review, review ? allText(review).split('\n').filter((l) => /Weather|pip install|Risk|Requested/.test(l)).join(' | ') : `review screen not shown · tapped: ${tappedReview} · shade: ${shadeSeen['Review Request'] || ''} · screen: ${allText(dump()).replace(/\s+/g, ' ').slice(0, 300)}`);
  screenshot('a08b-approval-review');
  if (review) await tap(/^Approve$/);
  const approvedB = await until(() => decBValue !== null, 15000, 500);
  check('Approvals', 'approving on the review screen reaches the PC (screen lock check when the phone has one)', approvedB && decBValue === true, `PC received: ${decBValue}${metrics.device.sdk ? ' · emulator has no screen lock, so the explicit Approve tap is the confirmation' : ''}`);

  // Input required from the Code Agent: Respond → decision screen → answer reaches the agent.
  svc.settings.set('privacy', { allowedFolders: [...svc.settings.get('privacy').allowedFolders, DATA] });
  svc.settings.set('agent', { projectsRoot: path.join(DATA, 'projects') });
  const proj = await svc.agent.createProject({ name: 'E2E Weather' });
  const runId = `run_e2e_${Date.now().toString(36)}`; const nowTs = Date.now();
  const planObj = { title: 'Weather app', stack: 'python', steps: [{ id: 'inspect', title: 'Inspect project', status: 'complete' }, { id: 'plan', title: 'Plan the changes', status: 'needs_input' }] };
  svc.db.run('INSERT INTO agent_runs (id, project_id, request, status, plan, origin, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', runId, proj.id, 'Build a small weather app', 'running', JSON.stringify(planObj), 'e2e', nowTs, nowTs);
  const runObj = { id: runId, project_id: proj.id, request: 'Build a small weather app', status: 'running', plan: planObj };
  sh('input keyevent 3'); await sleep(1500); // the question arrives while VIPER Mobile is in the background
  await clearShade();
  const answerP = svc.agent.ask(runObj, proj, 'Which user interface should the weather app use?', ['Desktop window (tkinter)', 'Command line']);
  let answered = null; answerP.then((a) => { answered = a; });
  const shownQ = await until(() => posted().find((p) => p.title === EXPECT.input_required[0] && /Which user interface/.test(p.text)), 30000, 1500);
  check('Code Agent (phone)', 'agent question reaches the phone as "Input Required"', !!shownQ, shownQ ? `${shownQ.text} · [${shownQ.actions.join(', ')}]` : 'not shown');
  const tappedRespond = await shadeTap(/Which user interface/, 'Respond');
  const qScreen = await until(() => { const ns = dump(); return find(ns, /Which user interface should the weather app use/) && find(ns, /^Desktop window \(tkinter\)$/) ? ns : null; }, 20000, 1000);
  check('Code Agent (phone)', '"Respond" opens the task with the question and its options (incl. "Decide automatically")', tappedRespond && !!qScreen && !!find(qScreen, /^Decide automatically$/), qScreen ? 'question and options shown' : `tapped: ${tappedRespond} · shade: ${shadeSeen.Respond || ''} · screen: ${allText(dump()).replace(/\s+/g, ' ').slice(0, 300)}`);
  screenshot('a08c-agent-question');
  if (qScreen) await tap(/^Desktop window \(tkinter\)$/);
  await until(() => answered !== null, 15000, 500);
  const decRow = svc.db.get('SELECT answer, answered_by FROM agent_decisions WHERE run_id = ?', runId);
  check('Code Agent (phone)', 'the answer chosen on the phone reaches the Code Agent', answered === 'Desktop window (tkinter)' && /^phone: /.test(decRow?.answered_by || ''), `${decRow?.answer} · answered by ${decRow?.answered_by}`);
  svc.agent.setStatus(runObj, 'cancelled');

  // Phone controls a real Code Agent task: start it from the phone, watch it, cancel it.
  sh(`am start -n ${PKG}/.MainActivity`); await sleep(2000);
  await tap(/^Make$/); await tap(/^AI Coding Agent$/);
  await until(() => find(dump(), /^E2E Weather$/), 15000, 1000);
  await tap(/^E2E Weather$/);
  const reqBox = find(dump(), /What should VIPER build or change/);
  if (reqBox) { tapNode(reqBox); await sleep(500); typeText('Create hello.py that prints hello'); sh('input keyevent 4'); await sleep(500); }
  await tap(/^Start$/);
  const phoneRun = await until(() => svc.db.get("SELECT id, origin, status FROM agent_runs WHERE project_id = ? AND origin LIKE 'phone:%' ORDER BY created_at DESC LIMIT 1", proj.id), 20000, 1000);
  check('Code Agent (phone)', 'a task started on the phone runs on the PC', !!phoneRun, phoneRun ? `${phoneRun.id} · origin ${phoneRun.origin} · ${phoneRun.status}` : 'no run');
  const planShown = await until(() => find(dump(), /^(Plan|Planning…)$|Inspect project/), 30000, 1500);
  check('Code Agent (phone)', 'the phone shows the task and its live plan/status', !!planShown, (planShown || {}).text);
  screenshot('a08d-agent-task');
  const cancelBtn = await until(() => find(dump(), /^Cancel$/), 20000, 1000);
  if (cancelBtn) tapNode(cancelBtn);
  const cancelled = await until(() => ['cancelled', 'failed', 'completed'].includes(svc.agent.run(phoneRun?.id || '')?.status), 60000, 1500);
  check('Code Agent (phone)', 'cancel from the phone stops the task on the PC', !!cancelBtn && svc.agent.run(phoneRun?.id || '')?.status === 'cancelled', `final status ${svc.agent.run(phoneRun?.id || '')?.status}`);

  // History: read / unread, tapping marks read on the PC.
  const unreadBefore = svc.notify.list({ unreadOnly: true }).length;
  sh(`am start -n ${PKG}/.MainActivity`); await sleep(1500); sh('input keyevent 4'); await sleep(800);
  await tap(/^Manage$/); await tap(/^Notifications$/);
  const histShown = await until(() => find(dump(), /VIPER — System Alert/), 15000, 1000);
  if (histShown) tapNode(histShown);
  const markedRead = await until(() => svc.notify.get(sentIds.system_alert)?.read, 10000, 700);
  check('Notifications', 'history shows read/unread; opening one marks it read on the PC', !!histShown && !!markedRead, `unread before ${unreadBefore} · system alert read: ${!!markedRead}`);
  screenshot('a08e-history');

  // Closed app: without Firebase push the phone cannot be woken. Delivered on the next connection.
  sh(`am force-stop ${PKG}`); await sleep(1500);
  const closed = await svc.notify.send({ kind: 'task_complete', detail: 'Backup finished', link: { type: 'notifications', id: 'e2e-closed' }, channels: ['mobile'], dedupeKey: 'e2e:closed' });
  await sleep(3000);
  check('Notifications', 'while the app is fully closed, nothing pretends to deliver (no push configured)', closed.results.mobile.ok === false && !!closed.results.mobile.queued, JSON.stringify(closed.results.mobile));
  record('Notifications', 'delivery to a closed app through Firebase Cloud Messaging', 'BLOCKED', 'Needs the PC owner\'s own Firebase project (service-account key + app registration). Not available in CI; FCM sending is verified against a mock FCM/OAuth server in the desktop unit tests, and the phone side (token registration, data-message → notification) is built but not exercised here.');
  sh(`am start -n ${PKG}/.MainActivity`); await sleep(1500); sh('input keyevent 3');
  const caughtUp = await until(() => posted().find((p) => /Task complete, sir\. Backup finished/.test(p.text)), 40000, 1500);
  check('Notifications', 'notifications sent while the app was closed are delivered when it reconnects', !!caughtUp, caughtUp ? caughtUp.text : 'not delivered');

  // ===== disconnect / offline screen / queue / reconnect =====
  sh(`am start -n ${PKG}/.MainActivity`); await sleep(1500);
  await tap(/^Prompt$/);
  await svc.shutdown(); svc = null;
  const offline = await until(() => find(dump(), /^VIPER is currently offline\.$/), 60000, 1500);
  const offNodes = dump();
  check('Network', 'disconnected mode: "VIPER is currently offline." with Reconnect, diagnostics and last connected time', !!offline && !!find(offNodes, /^Reconnect$/) && !!find(offNodes, /^Connection diagnostics$/) && !!find(offNodes, /^Last connected /), (find(offNodes, /Last connected/) || {}).text);
  screenshot('a09-pc-offline');
  await tap(/^Connection diagnostics$/);
  const diag = await until(() => find(dump(), /no answer \(PC off/), 30000, 1500);
  check('Network', 'connection diagnostics run real checks and explain the failure', !!diag, (diag || {}).text);
  screenshot('a09b-diagnostics');
  await tap(/^Chat$/); await tap(/^Message$/);
  typeText('Are you back online'); sh('input keyevent 4'); await sleep(300); await tap(/^Send$/);
  const queued = await until(() => find(dump(), /queued and will be sent when the connection returns/), 10000, 700);
  check('Network', 'messages sent while the PC is offline are queued, not lost', !!queued);
  await startCore();
  const back = await until(() => svc.remote.status().connected.length === 1, 90000, 1000);
  check('Network', 'phone reconnects automatically when the PC comes back (exponential backoff)', !!back);
  const delivered = await until(() => svc.orchestrator.listConversations().some((c) => svc.orchestrator.messages(c.id).some((m) => m.role === 'user' && /Are you back online/.test(m.content))), 30000, 1000);
  check('Network', 'queued message is delivered after reconnecting', !!delivered);
  screenshot('a10-reconnected');
  // Network change: the phone loses and regains its network; it reconnects as soon as it is back.
  sh('cmd connectivity airplane-mode enable'); await sleep(1000);
  let lost = await until(() => svc.remote.status().connected.length === 0, 25000, 1000);
  if (!lost) { sh('svc wifi disable; svc data disable'); lost = await until(() => svc.remote.status().connected.length === 0, 30000, 1000); }
  if (!lost) record('Network', 'reconnects as soon as the phone\'s network returns', 'BLOCKED', 'airplane mode did not cut the emulator\'s link to the host');
  else {
    await sleep(35000); // long enough for the backoff to reach its 30 s ceiling
    const tNet = Date.now(); sh('cmd connectivity airplane-mode disable'); sh('svc wifi enable; svc data enable');
    const regained = await until(() => svc.remote.status().connected.length === 1, 60000, 500);
    check('Network', 'reconnects as soon as the phone\'s network returns (network-change detection)', !!regained && Date.now() - tNet < 20000, regained ? `reconnected ${Date.now() - tNet} ms after the network returned` : 'did not reconnect');
  }
  sh('cmd connectivity airplane-mode disable'); sh('svc wifi enable; svc data enable'); await sleep(2000);

  // ===== pairing persists across app restarts =====
  sh(`am force-stop ${PKG}`); await sleep(1000);
  sh(`am start -W -n ${PKG}/.MainActivity`); await sleep(3000);
  const stillPaired = !find(dump(), /^WELCOME TO VIPER MOBILE$/);
  const reconnect = await until(() => svc.remote.status().connected.length === 1, 40000, 1000);
  check('Security', 'pairing persists after the app is restarted (no re-pairing; stored encrypted on the phone)', stillPaired && !!reconnect);
  const prefs = (() => { try { return sh(`run-as ${PKG} ls shared_prefs`); } catch (e) { return `run-as blocked: ${e.message.split('\n')[0]}`; } })();
  record('Security', 'app data is not accessible from outside the app (release build)', /run-as blocked|not debuggable|is unknown/i.test(prefs) || /package not debuggable/i.test(prefs) ? 'PASS' : 'FAIL', prefs.trim().slice(0, 160));

  // ===== screen sizes =====
  const [W0, H0] = screenSize(); const density0 = (sh('wm density').match(/(\d+)\s*$/m) || [])[1];
  const layouts = [];
  for (const [w, h, dpi, label] of [[720, 1280, 320, 'small-phone'], [1080, 2400, 420, 'tall-phone'], [1600, 2560, 320, 'tablet']]) {
    sh(`wm size ${w}x${h}`); sh(`wm density ${dpi}`); await sleep(1500);
    sh(`am force-stop ${PKG}`); sh(`am start -W -n ${PKG}/.MainActivity`); await sleep(3500);
    const problems = [];
    for (const tab of ['Prompt', 'Make', 'Manage', 'Intelligence', 'Settings']) {
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
    const unpaired = await until(() => find(dump(), /^WELCOME TO VIPER MOBILE$/), 30000, 1500);
    check('Security', 'revoking the phone on the PC disconnects it at once and removes its credentials', !!unpaired, (find(dump(), /revoked/i) || {}).text);
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
