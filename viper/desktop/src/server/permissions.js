'use strict';
// Permission engine. Every tool declares a category and a risk level.
//  - category mode comes from settings.permissions: allow | ask | deny
//  - risk 'destructive' ALWAYS requires explicit confirmation
//  - when the current turn contains untrusted external content (web pages,
//    emails, documents) any non-read action requires confirmation, so text
//    inside that content cannot silently trigger actions.
//  - requests arriving from a paired phone use the device's own grants.
const path = require('node:path');
const { uid } = require('./util');

const CATEGORY_INFO = {
  'system.read': 'Read CPU, memory, disk, network and process information.',
  'apps.launch': 'Open installed applications.',
  'apps.close': 'Close running applications (unsaved work could be lost).',
  'system.volume': 'Change system volume and mute state.',
  'windows.manage': 'Focus, minimise or maximise application windows.',
  'browser.open': 'Open websites in your default browser.',
  'files.search': 'Search file names inside your allowed folders.',
  'files.read': 'Read file contents inside your allowed folders.',
  'files.write': 'Create, move or rename files inside your allowed folders.',
  'files.delete': 'Delete files (moved to the VIPER recycle folder).',
  'clipboard.read': 'Read the text currently on your clipboard.',
  'screen.capture': 'Take screenshots of your screen.',
  'camera': 'Use the webcam for vision analysis.',
  'web.access': 'Search the web and download pages (requires Web Access opt-in).',
  'scripts.run': 'Run scripts you have explicitly approved in Settings.',
  'shell.workspace': 'Run commands inside a Code Studio workspace.',
  'email.read': 'Read and search connected mailboxes.',
  'email.send': 'Send email from connected accounts.',
  'sms.send': 'Send SMS through your configured provider or phone.',
  'notify.send': 'Send notifications to your configured channels.',
  'memory.write': 'Save long-term memories.',
  'automation.manage': 'Create, change or delete automations.',
  'ui.control': 'Switch VIPER modes, open the HUD, stop speech.',
  'reminders': 'Create and manage reminders.',
  'plugin.tools': 'Run tools provided by installed plugins (each plugin is sandboxed).',
};

class Permissions {
  constructor({ settings, bus, db, log }) {
    this.settings = settings; this.bus = bus; this.db = db; this.log = log;
    this.pending = new Map();
  }
  mode(category) { return this.settings.get('permissions')[category] || 'ask'; }

  audit(actor, action, detail, risk, outcome) {
    try {
      this.db.run('INSERT INTO activity (ts, actor, action, detail, risk, outcome) VALUES (?, ?, ?, ?, ?, ?)',
        Date.now(), actor, action, typeof detail === 'string' ? detail : JSON.stringify(detail).slice(0, 2000), risk || 'low', outcome || '');
    } catch (e) { this.log?.warn('audit failed', e); }
  }

  // Folder sandboxing for file tools.
  isPathAllowed(p, extra = []) {
    if (!p) return false;
    const target = path.resolve(p);
    const roots = [...this.settings.get('privacy').allowedFolders, ...extra].map((r) => path.resolve(r));
    return roots.some((r) => {
      const rel = path.relative(r, target);
      return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
    });
  }

  /**
   * Decide whether a tool call may run.
   * @returns {Promise<{allowed: boolean, reason?: string}>}
   */
  async check({ tool, args, ctx = {} }) {
    const category = tool.category;
    let mode = this.mode(category);
    if (ctx.device) {
      const grants = ctx.device.permissions || {};
      if (grants[category] === 'deny' || (grants[category] == null && tool.risk !== 'read')) {
        if (grants[category] === 'deny') return { allowed: false, reason: `Paired device "${ctx.device.name}" is not permitted to use ${category}.` };
        mode = mode === 'deny' ? 'deny' : 'ask';
      }
    }
    if (mode === 'deny') return { allowed: false, reason: `Permission "${category}" is disabled in Settings → Privacy & Permissions.` };
    let needConfirm = mode === 'ask' || tool.risk === 'destructive';
    let reason = CATEGORY_INFO[category] || category;
    if (ctx.tainted && tool.risk !== 'read') {
      needConfirm = true;
      reason = 'This request follows external content (web page, email or document). Confirm that YOU want this action.';
    }
    if (ctx.autoApprove && !needConfirm) return { allowed: true };
    if (!needConfirm) return { allowed: true };
    if (ctx.noInteractive) return { allowed: false, reason: 'Action requires confirmation but no one is available to approve it.' };
    const approved = await this.requestConfirmation({
      tool: tool.name, title: tool.confirmTitle ? tool.confirmTitle(args) : `Allow ${tool.label || tool.name}?`,
      preview: tool.preview ? tool.preview(args) : JSON.stringify(args, null, 2), risk: tool.risk, category, reason,
      origin: ctx.device ? `phone: ${ctx.device.name}` : (ctx.origin || 'desktop'),
    });
    return approved ? { allowed: true } : { allowed: false, reason: 'You declined this action.' };
  }

  requestConfirmation(req, timeoutMs = 120000) {
    const id = uid('cf_');
    return new Promise((resolve) => {
      const timer = setTimeout(() => { this.pending.delete(id); this.bus.publish('confirm.closed', { id, approved: false, timeout: true }); resolve(false); }, timeoutMs);
      this.pending.set(id, { resolve, timer, req });
      this.bus.publish('confirm.request', { id, ...req, expiresAt: Date.now() + timeoutMs });
    });
  }
  respond(id, approved) {
    const p = this.pending.get(id);
    if (!p) return false;
    clearTimeout(p.timer); this.pending.delete(id);
    this.bus.publish('confirm.closed', { id, approved: !!approved });
    p.resolve(!!approved);
    return true;
  }
  listPending() { return [...this.pending.entries()].map(([id, p]) => ({ id, ...p.req })); }
}

module.exports = { Permissions, CATEGORY_INFO };
