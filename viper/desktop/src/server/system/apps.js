'use strict';
// Installed application discovery (Start Menu shortcuts + Store apps on
// Windows; .desktop files on Linux; /Applications on macOS). VIPER can only
// launch entries discovered here — never arbitrary executables.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { runPowerShell, START_APPS_PS } = require('../tools/winshell');

function walk(dir, exts, out, depth = 0) {
  if (depth > 4) return;
  let entries; try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, exts, out, depth + 1);
    else if (exts.some((x) => e.name.toLowerCase().endsWith(x))) out.push(p);
  }
}

const norm = (s) => s.toLowerCase().replace(/\.(lnk|url|desktop|app)$/i, '').replace(/[^a-z0-9+#]+/g, ' ').trim();

class AppCatalog {
  constructor({ log }) { this.log = log; this.apps = []; this.at = 0; }
  async refresh() {
    const apps = [];
    if (process.platform === 'win32') {
      const dirs = [
        path.join(process.env.ProgramData || 'C:\\ProgramData', 'Microsoft', 'Windows', 'Start Menu', 'Programs'),
        path.join(process.env.APPDATA || '', 'Microsoft', 'Windows', 'Start Menu', 'Programs'),
      ];
      const files = []; for (const d of dirs) walk(d, ['.lnk', '.url'], files);
      for (const f of files) {
        const name = path.basename(f).replace(/\.(lnk|url)$/i, '');
        if (/uninstall|readme|help|license|documentation|release notes/i.test(name)) continue;
        apps.push({ name, kind: 'shortcut', target: f });
      }
      const r = await runPowerShell(START_APPS_PS, {}, 20000);
      if (r.ok && r.stdout) {
        try {
          let list = JSON.parse(r.stdout); if (!Array.isArray(list)) list = [list];
          for (const a of list) if (a?.Name && a?.AppID && !apps.some((x) => norm(x.name) === norm(a.Name))) apps.push({ name: a.Name, kind: 'appid', target: a.AppID });
        } catch { /* ignore */ }
      }
    } else if (process.platform === 'darwin') {
      for (const d of ['/Applications', path.join(os.homedir(), 'Applications')]) {
        try { for (const e of fs.readdirSync(d)) if (e.endsWith('.app')) apps.push({ name: e.replace(/\.app$/, ''), kind: 'mac', target: path.join(d, e) }); } catch { /* skip */ }
      }
    } else {
      const files = []; for (const d of ['/usr/share/applications', path.join(os.homedir(), '.local/share/applications')]) walk(d, ['.desktop'], files);
      for (const f of files) {
        try {
          const txt = fs.readFileSync(f, 'utf8');
          if (/^NoDisplay=true/m.test(txt)) continue;
          const name = (txt.match(/^Name=(.+)$/m) || [])[1];
          if (name) apps.push({ name, kind: 'desktop', target: f });
        } catch { /* skip */ }
      }
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    this.apps = apps; this.at = Date.now();
    return apps;
  }
  async list() { if (!this.apps.length || Date.now() - this.at > 300000) await this.refresh(); return this.apps; }

  async find(query) {
    const q = norm(query);
    if (!q) return [];
    const apps = await this.list();
    const scored = apps.map((a) => {
      const n = norm(a.name);
      let score = 0;
      if (n === q) score = 100;
      else if (n.startsWith(q)) score = 80;
      else if (n.split(' ').includes(q)) score = 70;
      else if (n.includes(q)) score = 50;
      else { const qt = q.split(' '); const hits = qt.filter((t) => n.includes(t)).length; score = hits ? 20 + 20 * hits / qt.length : 0; }
      return { ...a, score };
    }).filter((a) => a.score > 0).sort((a, b) => b.score - a.score || a.name.length - b.name.length);
    return scored.slice(0, 8);
  }

  launch(app) {
    return new Promise((resolve) => {
      let p;
      try {
        if (app.kind === 'shortcut') p = spawn('explorer.exe', [app.target], { detached: true, stdio: 'ignore', windowsHide: true });
        else if (app.kind === 'appid') p = spawn('explorer.exe', [`shell:AppsFolder\\${app.target}`], { detached: true, stdio: 'ignore', windowsHide: true });
        else if (app.kind === 'mac') p = spawn('open', ['-a', app.target], { detached: true, stdio: 'ignore' });
        else p = spawn('gtk-launch', [path.basename(app.target, '.desktop')], { detached: true, stdio: 'ignore' });
      } catch (e) { return resolve({ ok: false, error: e.message }); }
      let settled = false;
      p.on('error', (e) => { if (!settled) { settled = true; resolve({ ok: false, error: e.message }); } });
      p.unref();
      // explorer.exe returns quickly; give spawn a moment to surface ENOENT etc.
      setTimeout(() => { if (!settled) { settled = true; resolve({ ok: true }); } }, 400);
    });
  }
}

module.exports = { AppCatalog, norm };
