'use strict';
// Computer-control tools. Every tool here performs a real operation and
// reports what was actually verified.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { runPowerShell, run, VOLUME_PS, WINDOW_PS, LIST_WINDOWS_PS, EVENTLOG_PS } = require('./winshell');
const { formatBytes, sleep } = require('../util');
const { norm } = require('../system/apps');

const PROTECTED = new Set(['system', 'idle', 'csrss.exe', 'wininit.exe', 'winlogon.exe', 'lsass.exe', 'services.exe', 'smss.exe', 'svchost.exe', 'dwm.exe', 'explorer.exe', 'registry', 'memory compression', 'fontdrvhost.exe', 'viper.exe', 'systemd', 'init', 'kthreadd', 'launchd', 'kernel_task', 'windowserver']);

function knownFolder(name) {
  const h = os.homedir();
  const map = { home: h, downloads: path.join(h, 'Downloads'), documents: path.join(h, 'Documents'), desktop: path.join(h, 'Desktop'), pictures: path.join(h, 'Pictures'), music: path.join(h, 'Music'), videos: path.join(h, 'Videos') };
  return map[String(name || '').toLowerCase().replace(/^my\s+/, '').replace(/\s+folder$/, '').trim()] || null;
}

function parseWhen(s) {
  if (!s) return null;
  const t = String(s).toLowerCase().trim();
  const now = new Date();
  if (/^yesterday/.test(t)) { const d = new Date(now); d.setDate(d.getDate() - 1); d.setHours(0, 0, 0, 0); return d.getTime(); }
  if (/^today/.test(t)) { const d = new Date(now); d.setHours(0, 0, 0, 0); return d.getTime(); }
  const m = t.match(/(\d+)\s*(minute|hour|day|week)s?/);
  if (m) return Date.now() - parseInt(m[1], 10) * { minute: 60000, hour: 3600000, day: 86400000, week: 604800000 }[m[2]];
  const d = Date.parse(s);
  return Number.isNaN(d) ? null : d;
}

async function searchFiles(roots, { query, ext, since, until, limit = 40, maxScan = 60000, timeMs = 5000 }) {
  const terms = norm(query || '').split(' ').filter(Boolean);
  const exts = (ext || '').split(',').map((e) => e.trim().replace(/^\./, '').toLowerCase()).filter(Boolean);
  const results = []; let scanned = 0; const deadline = Date.now() + timeMs;
  const skip = new Set(['node_modules', '.git', '$recycle.bin', 'appdata', '.cache', '__pycache__', 'venv', '.venv']);
  const stack = roots.map((r) => ({ dir: r, depth: 0 }));
  while (stack.length && scanned < maxScan && Date.now() < deadline) {
    const { dir, depth } = stack.pop();
    let entries; try { entries = await fsp.readdir(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      scanned++;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (!skip.has(e.name.toLowerCase()) && !e.name.startsWith('.') && depth < 8) stack.push({ dir: p, depth: depth + 1 });
      }
      const n = norm(e.name);
      if (terms.length && !terms.every((t) => n.includes(t) || norm(path.relative(roots[0], dir)).includes(t))) continue;
      if (exts.length && !exts.includes(path.extname(e.name).slice(1).toLowerCase())) continue;
      let st; try { st = await fsp.stat(p); } catch { continue; }
      if (since && st.mtimeMs < since) continue;
      if (until && st.mtimeMs > until) continue;
      results.push({ path: p, name: e.name, dir: e.isDirectory(), size: st.size, modified: st.mtimeMs });
    }
  }
  results.sort((a, b) => b.modified - a.modified);
  return { results: results.slice(0, limit), scanned, truncated: scanned >= maxScan || Date.now() >= deadline };
}

function register(reg, svc) {
  const { settings, permissions, monitor, apps, bridge } = svc;

  reg.register({
    name: 'system_status', label: 'System status', category: 'system.read', risk: 'read',
    description: 'Get current CPU, memory, disk, network, GPU, battery and temperature readings for this PC.',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const s = await monitor.snapshot();
      return {
        ok: true,
        result: {
          cpuPercent: s.cpu?.pct ?? null, memoryPercent: s.mem?.pct ?? null, memoryUsed: formatBytes(s.mem?.used), memoryTotal: formatBytes(s.mem?.total),
          disks: s.disks.map((d) => ({ drive: d.mount, usedPercent: d.pct, free: formatBytes(d.size - d.used) })),
          gpu: s.gpu ? { model: s.gpu.model, utilisationPercent: s.gpu.pct, temperatureC: s.gpu.temp } : 'not reported',
          cpuTemperatureC: s.temp?.cpu ?? 'not available on this system', battery: s.battery || 'no battery', internet: s.online ? 'connected' : 'offline',
          uptimeHours: Math.round(s.uptime / 360) / 10, host: s.static.hostname, os: s.static.platform,
        },
        summary: `CPU ${s.cpu?.pct ?? '?'}%, RAM ${s.mem?.pct ?? '?'}%`,
      };
    },
  });

  reg.register({
    name: 'cpu_temperature', label: 'CPU temperature', category: 'system.read', risk: 'read',
    description: 'Read the CPU temperature sensor, if this PC exposes one.',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const s = await monitor.snapshot();
      if (!s.temp?.cpu) return { ok: true, result: { available: false, note: 'This PC does not expose a CPU temperature sensor to applications (common on Windows without vendor drivers). No value can be reported.' } };
      return { ok: true, result: { available: true, cpuC: s.temp.cpu, maxC: s.temp.max } };
    },
  });

  reg.register({
    name: 'list_processes', label: 'Running processes', category: 'system.read', risk: 'read',
    description: 'List the top running processes by CPU and memory use.',
    parameters: { type: 'object', properties: { limit: { type: 'integer', minimum: 1, maximum: 50, default: 15 } } },
    handler: async ({ limit }) => ({ ok: true, result: (await monitor.processes(limit)).map((p) => ({ ...p, mem: formatBytes(p.memBytes) })) }),
  });

  reg.register({
    name: 'disk_space', label: 'Disk space', category: 'system.read', risk: 'read',
    description: 'Report free and used space on each drive.',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const s = await monitor.snapshot();
      let disks = s.disks;
      if (!disks.length) {
        const st = await fsp.statfs(os.homedir());
        disks = [{ mount: os.homedir(), size: st.blocks * st.bsize, used: (st.blocks - st.bfree) * st.bsize, pct: Math.round((1 - st.bfree / st.blocks) * 1000) / 10 }];
      }
      return { ok: true, result: disks.map((d) => ({ drive: d.mount, total: formatBytes(d.size), free: formatBytes(d.size - d.used), usedPercent: d.pct })) };
    },
  });

  reg.register({
    name: 'run_diagnostics', label: 'System diagnostic', category: 'system.read', risk: 'read',
    description: 'Run a full system diagnostic: resource usage, storage capacity, heaviest processes and recent Windows system errors.',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const s = await monitor.snapshot();
      const procs = await monitor.processes(8);
      const warnings = [];
      if (s.mem?.pct > 85) warnings.push(`Memory usage is high (${s.mem.pct}%).`);
      if (s.cpu?.pct > 85) warnings.push(`CPU is heavily loaded (${s.cpu.pct}%).`);
      for (const d of s.disks) if (d.pct > 90) warnings.push(`Drive ${d.mount} is ${d.pct}% full.`);
      if (s.temp?.cpu > 85) warnings.push(`CPU temperature is ${s.temp.cpu}°C.`);
      let events = [];
      if (process.platform === 'win32') {
        const r = await runPowerShell(EVENTLOG_PS, {}, 30000);
        try { events = JSON.parse(r.stdout || '[]'); if (!Array.isArray(events)) events = [events]; } catch { events = []; }
      }
      return {
        ok: true,
        result: {
          cpuPercent: s.cpu?.pct, memoryPercent: s.mem?.pct, disks: s.disks.map((d) => `${d.mount}: ${d.pct}% used, ${formatBytes(d.size - d.used)} free`),
          topProcesses: procs.map((p) => `${p.name} (cpu ${p.cpu}%, ${formatBytes(p.memBytes)})`),
          systemErrorsLast24h: process.platform === 'win32' ? events.length : 'event log only available on Windows',
          recentErrors: events.slice(0, 5).map((e) => `${e.ProviderName}: ${e.Message}`),
          warnings: warnings.length ? warnings : ['No warnings detected.'],
          cpuTemperatureC: s.temp?.cpu ?? 'not available',
        },
      };
    },
  });

  reg.register({
    name: 'open_app', label: 'Open application', category: 'apps.launch', risk: 'write',
    description: 'Open an installed application by name (e.g. "Spotify", "Notepad", "Chrome").',
    parameters: { type: 'object', properties: { name: { type: 'string', description: 'Application name' } }, required: ['name'] },
    handler: async ({ name }) => {
      const matches = await apps.find(name);
      if (!matches.length) return { ok: false, error: `No installed application matching "${name}" was found.` };
      const app = matches[0];
      if (matches.length > 1 && matches[0].score < 70 && matches[1].score === matches[0].score) {
        return { ok: false, error: `Ambiguous application name. Did you mean: ${matches.slice(0, 4).map((m) => m.name).join(', ')}?` };
      }
      const before = new Set((await monitor.allProcesses().catch(() => [])).map((p) => p.pid));
      const r = await apps.launch(app);
      if (!r.ok) return { ok: false, error: `Launch failed: ${r.error}` };
      // Verify: look for a new process whose name resembles the app.
      const key = norm(app.name).split(' ')[0];
      let verified = false;
      for (let i = 0; i < 8 && !verified; i++) {
        await sleep(750);
        const procs = await monitor.allProcesses().catch(() => []);
        verified = procs.some((p) => (!before.has(p.pid) || i > 0) && norm(p.name).includes(key));
      }
      return { ok: true, result: { app: app.name, launched: true, verifiedRunning: verified, note: verified ? 'Process confirmed running.' : 'Launch command was accepted, but a matching process could not be confirmed yet.' }, summary: `${app.name}${verified ? ' running' : ' launch requested'}` };
    },
  });

  reg.register({
    name: 'list_apps', label: 'Installed apps', category: 'system.read', risk: 'read',
    description: 'Search the list of installed applications VIPER can open.',
    parameters: { type: 'object', properties: { query: { type: 'string' } } },
    handler: async ({ query }) => ({ ok: true, result: (query ? await apps.find(query) : (await apps.list()).slice(0, 60)).map((a) => a.name) }),
  });

  reg.register({
    name: 'close_app', label: 'Close application', category: 'apps.close', risk: 'destructive',
    description: 'Close a running application by name. Unsaved work in that app may be lost; the user is always asked to confirm.',
    parameters: { type: 'object', properties: { name: { type: 'string' }, force: { type: 'boolean', default: false } }, required: ['name'] },
    confirmTitle: (a) => `Close "${a.name}"${a.force ? ' (force)' : ''}?`,
    preview: (a) => `VIPER will ask every process matching "${a.name}" to exit.${a.force ? '\nForce mode terminates immediately — unsaved work will be lost.' : '\nThe application may prompt to save work.'}`,
    handler: async ({ name, force }) => {
      const key = norm(name);
      const procs = (await monitor.allProcesses()).filter((p) => norm(p.name).replace(/ exe$/, '').includes(key));
      const targets = procs.filter((p) => !PROTECTED.has(p.name.toLowerCase()) && p.pid !== process.pid);
      if (!targets.length) return { ok: false, error: procs.length ? 'Only protected system processes matched; refusing to close them.' : `No running process matches "${name}".` };
      const pids = targets.map((p) => p.pid);
      if (process.platform === 'win32') {
        const args = ['/T', ...(force ? ['/F'] : []), ...pids.flatMap((p) => ['/PID', String(p)])];
        await run('taskkill', args);
      } else for (const pid of pids) { try { process.kill(pid, force ? 'SIGKILL' : 'SIGTERM'); } catch { /* gone */ } }
      await sleep(1500);
      const still = (await monitor.allProcesses()).filter((p) => pids.includes(p.pid));
      return { ok: still.length === 0, result: { closed: pids.length - still.length, stillRunning: still.length, note: still.length ? 'Some processes did not exit (they may be showing a save prompt). Use force to terminate.' : 'All matching processes exited.' }, error: still.length ? 'Some processes are still running' : undefined };
    },
  });

  reg.register({
    name: 'set_volume', label: 'System volume', category: 'system.volume', risk: 'write',
    description: 'Get or change the system master volume (0-100) or mute/unmute.',
    parameters: { type: 'object', properties: { action: { type: 'string', enum: ['get', 'set', 'up', 'down', 'mute', 'unmute'] }, level: { type: 'integer', minimum: 0, maximum: 100 } }, required: ['action'] },
    handler: async ({ action, level }) => {
      if (process.platform === 'win32') {
        let op = action; let target = level;
        if (action === 'up' || action === 'down') {
          const cur = JSON.parse((await runPowerShell(VOLUME_PS, { op: 'get' })).stdout || '{}');
          target = Math.max(0, Math.min(100, (cur.level || 0) + (action === 'up' ? 10 : -10))); op = 'set';
        }
        if (op === 'set' && (target == null)) return { ok: false, error: 'A level between 0 and 100 is required.' };
        const r = await runPowerShell(VOLUME_PS, { op, level: target });
        if (!r.ok) return { ok: false, error: r.stderr || r.error };
        const state = JSON.parse(r.stdout.split('\n').pop());
        return { ok: true, result: { verifiedLevel: state.level, muted: state.muted } };
      }
      if (process.platform === 'linux') {
        const map = { get: [], set: ['set', 'Master', `${level}%`], up: ['set', 'Master', '10%+'], down: ['set', 'Master', '10%-'], mute: ['set', 'Master', 'mute'], unmute: ['set', 'Master', 'unmute'] };
        const r = await run('amixer', map[action].length ? map[action] : ['get', 'Master']);
        if (!r.ok) return { ok: false, error: 'Volume control unavailable (amixer not found).' };
        const m = r.stdout.match(/\[(\d+)%\].*\[(on|off)\]/);
        return { ok: true, result: { verifiedLevel: m ? parseInt(m[1], 10) : null, muted: m ? m[2] === 'off' : null } };
      }
      return { ok: false, error: 'Volume control is not supported on this platform.' };
    },
  });

  reg.register({
    name: 'manage_window', label: 'Manage window', category: 'windows.manage', risk: 'write',
    description: 'Focus, minimise, maximise or restore an application window by app name or window title; or list open windows.',
    parameters: { type: 'object', properties: { action: { type: 'string', enum: ['list', 'focus', 'minimize', 'maximize', 'restore'] }, name: { type: 'string' } }, required: ['action'] },
    handler: async ({ action, name }) => {
      if (process.platform !== 'win32') return { ok: false, error: 'Window management is implemented for Windows only.' };
      if (action === 'list') {
        const r = await runPowerShell(LIST_WINDOWS_PS);
        let list = []; try { list = JSON.parse(r.stdout || '[]'); if (!Array.isArray(list)) list = [list]; } catch { /* empty */ }
        return { ok: true, result: list.map((w) => ({ app: w.ProcessName, title: w.MainWindowTitle })) };
      }
      if (!name) return { ok: false, error: 'Window name required' };
      const r = await runPowerShell(WINDOW_PS, { name, action });
      const j = JSON.parse(r.stdout || '{"ok":false,"error":"PowerShell failed"}');
      return j.ok ? { ok: true, result: { window: j.title, app: j.process, action } } : { ok: false, error: j.error };
    },
  });

  reg.register({
    name: 'open_folder', label: 'Open folder', category: 'files.search', risk: 'write',
    description: 'Open a folder in File Explorer. Accepts a known folder name (downloads, documents, desktop, pictures, music, videos, home) or a path inside the allowed folders.',
    parameters: { type: 'object', properties: { folder: { type: 'string' } }, required: ['folder'] },
    handler: async ({ folder }) => {
      const p = knownFolder(folder) || folder;
      if (!knownFolder(folder) && !permissions.isPathAllowed(p)) return { ok: false, error: `"${p}" is outside VIPER's allowed folders (Settings → Privacy).` };
      if (!fs.existsSync(p)) return { ok: false, error: `Folder does not exist: ${p}` };
      const r = await bridge.openPath(p);
      return r?.ok === false ? { ok: false, error: r.error } : { ok: true, result: { opened: p } };
    },
  });

  reg.register({
    name: 'search_files', label: 'Search files', category: 'files.search', risk: 'read',
    description: 'Search file and folder names inside the allowed folders. Supports time filters like since="yesterday" or "3 days".',
    parameters: { type: 'object', properties: { query: { type: 'string', description: 'Words in the file name (may be empty when filtering by time)' }, extension: { type: 'string', description: 'Comma-separated extensions, e.g. "pdf,docx"' }, since: { type: 'string' }, until: { type: 'string' }, folder: { type: 'string' } } },
    handler: async ({ query, extension, since, until, folder }) => {
      let roots = settings.get('privacy').allowedFolders.filter((r) => fs.existsSync(r));
      if (folder) {
        const f = knownFolder(folder) || folder;
        if (!permissions.isPathAllowed(f)) return { ok: false, error: 'Folder is outside the allowed folders.' };
        roots = [f];
      }
      if (!roots.length) return { ok: false, error: 'No allowed folders are configured.' };
      const s = since ? parseWhen(since) : null;
      let u = until ? parseWhen(until) : null;
      if (since && /^yesterday/i.test(since) && !until) { u = s + 86400000; }
      const r = await searchFiles(roots, { query, ext: extension, since: s, until: u });
      return { ok: true, result: { matches: r.results.map((x) => ({ ...x, size: formatBytes(x.size), modified: new Date(x.modified).toLocaleString() })), scanned: r.scanned, truncated: r.truncated }, summary: `${r.results.length} matches` };
    },
  });

  reg.register({
    name: 'create_file', label: 'Create file/folder', category: 'files.write', risk: 'write',
    description: 'Create a new text file (with content) or a folder inside the allowed folders. Will not overwrite existing files.',
    parameters: { type: 'object', properties: { path: { type: 'string' }, content: { type: 'string', default: '' }, folder: { type: 'boolean', default: false } }, required: ['path'] },
    confirmTitle: (a) => `Create ${a.folder ? 'folder' : 'file'} ${a.path}?`,
    preview: (a) => a.folder ? `New folder: ${a.path}` : `New file: ${a.path}\n\n${(a.content || '').slice(0, 1500)}`,
    handler: async ({ path: p, content, folder }) => {
      const target = path.resolve(knownFolder(p.split(/[\\/]/)[0]) ? path.join(knownFolder(p.split(/[\\/]/)[0]), ...p.split(/[\\/]/).slice(1)) : p);
      if (!permissions.isPathAllowed(target)) return { ok: false, error: `${target} is outside the allowed folders.` };
      if (fs.existsSync(target)) return { ok: false, error: 'A file or folder already exists at that path; VIPER will not overwrite it.' };
      if (folder) await fsp.mkdir(target, { recursive: true });
      else { await fsp.mkdir(path.dirname(target), { recursive: true }); await fsp.writeFile(target, content || '', { flag: 'wx' }); }
      return { ok: fs.existsSync(target), result: { created: target } };
    },
  });

  reg.register({
    name: 'move_file', label: 'Move/rename file', category: 'files.write', risk: 'write',
    description: 'Move or rename a file or folder within the allowed folders. Never overwrites.',
    parameters: { type: 'object', properties: { from: { type: 'string' }, to: { type: 'string' } }, required: ['from', 'to'] },
    confirmTitle: () => 'Move file?', preview: (a) => `${a.from}\n→ ${a.to}`,
    handler: async ({ from, to }) => {
      if (!permissions.isPathAllowed(from) || !permissions.isPathAllowed(to)) return { ok: false, error: 'Both paths must be inside the allowed folders.' };
      if (!fs.existsSync(from)) return { ok: false, error: 'Source does not exist.' };
      if (fs.existsSync(to)) return { ok: false, error: 'Destination already exists.' };
      await fsp.mkdir(path.dirname(to), { recursive: true });
      await fsp.rename(from, to);
      return { ok: fs.existsSync(to), result: { moved: to } };
    },
  });

  reg.register({
    name: 'delete_file', label: 'Delete file', category: 'files.delete', risk: 'destructive',
    description: 'Send a file or folder inside the allowed folders to the Recycle Bin. Always requires confirmation.',
    parameters: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
    confirmTitle: (a) => `Send to Recycle Bin: ${path.basename(a.path)}?`, preview: (a) => `Path: ${a.path}\nThis can be restored from the Recycle Bin.`,
    handler: async ({ path: p }) => {
      if (!permissions.isPathAllowed(p)) return { ok: false, error: 'Path is outside the allowed folders.' };
      if (!fs.existsSync(p)) return { ok: false, error: 'File does not exist.' };
      const r = await bridge.trash(p);
      if (r?.ok === false) return { ok: false, error: r.error };
      return { ok: !fs.existsSync(p), result: { recycled: p } };
    },
  });

  reg.register({
    name: 'open_url', label: 'Open website', category: 'browser.open', risk: 'write',
    description: 'Open a website in the default browser. Only http/https URLs.',
    parameters: { type: 'object', properties: { url: { type: 'string' } }, required: ['url'] },
    handler: async ({ url }) => {
      let u = url.trim(); if (!/^https?:\/\//i.test(u)) u = `https://${u}`;
      let parsed; try { parsed = new URL(u); } catch { return { ok: false, error: 'Invalid URL' }; }
      if (!['http:', 'https:'].includes(parsed.protocol)) return { ok: false, error: 'Only http(s) URLs can be opened.' };
      const r = await bridge.openExternal(parsed.toString());
      return r?.ok === false ? { ok: false, error: r.error } : { ok: true, result: { opened: parsed.toString() } };
    },
  });

  reg.register({
    name: 'read_clipboard', label: 'Read clipboard', category: 'clipboard.read', risk: 'read',
    description: 'Read the text currently on the clipboard (requires permission).',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const t = await bridge.readClipboard();
      if (t == null) return { ok: false, error: 'Clipboard access is not available in this mode.' };
      return { ok: true, result: { text: t.slice(0, 8000), length: t.length }, untrusted: true };
    },
  });
  // Clipboard can contain anything — mark as read-but-sensitive so 'ask' applies.

  reg.register({
    name: 'take_screenshot', label: 'Screenshot', category: 'screen.capture', risk: 'read',
    description: 'Capture a screenshot of the primary display and save it. Use describe_screen to analyse what is on screen.',
    parameters: { type: 'object', properties: {} },
    handler: async () => {
      const r = await bridge.captureScreen();
      if (!r?.path) return { ok: false, error: r?.error || 'Screen capture is not available in this mode.' };
      return { ok: true, result: { saved: r.path, width: r.width, height: r.height } };
    },
  });

  reg.register({
    name: 'run_approved_script', label: 'Run approved script', category: 'scripts.run', risk: 'write',
    description: 'Run one of the scripts the user has pre-approved in Settings → Computer Control. Arbitrary commands are not allowed.',
    parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
    preview: (a) => { const s = settings.get('approvedScripts').find((x) => norm(x.name) === norm(a.name)); return s ? `${s.name}\n${s.path} ${(s.args || []).join(' ')}` : a.name; },
    handler: async ({ name }) => {
      const list = settings.get('approvedScripts');
      const s = list.find((x) => norm(x.name) === norm(name));
      if (!s) return { ok: false, error: `No approved script named "${name}". Approved: ${list.map((x) => x.name).join(', ') || 'none'}` };
      if (!fs.existsSync(s.path)) return { ok: false, error: 'Script file no longer exists.' };
      const ext = path.extname(s.path).toLowerCase();
      const cmd = { '.ps1': ['powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', s.path]], '.bat': ['cmd.exe', ['/d', '/c', s.path]], '.cmd': ['cmd.exe', ['/d', '/c', s.path]], '.py': ['python', [s.path]], '.js': [process.execPath, [s.path]], '.sh': ['bash', [s.path]] }[ext];
      if (!cmd) return { ok: false, error: `Unsupported script type ${ext}` };
      const env = ext === '.js' ? { ...process.env, ELECTRON_RUN_AS_NODE: '1' } : process.env;
      return await new Promise((resolve) => {
        const p = spawn(cmd[0], [...cmd[1], ...(s.args || [])], { cwd: path.dirname(s.path), windowsHide: true, env });
        let out = ''; const t = setTimeout(() => p.kill(), 120000);
        p.stdout.on('data', (d) => { out += d; }); p.stderr.on('data', (d) => { out += d; });
        p.on('error', (e) => { clearTimeout(t); resolve({ ok: false, error: e.message }); });
        p.on('close', (code) => { clearTimeout(t); resolve({ ok: code === 0, result: { exitCode: code, output: out.slice(-4000) }, error: code === 0 ? undefined : `Exited with code ${code}` }); });
      });
    },
  });
}

module.exports = { register, searchFiles, knownFolder, parseWhen };
