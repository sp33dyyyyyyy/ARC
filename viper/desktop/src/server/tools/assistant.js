'use strict';
// Assistant-level tools: memory, reminders, automations, notifications, UI control, briefings.
const { parseDue, parseSchedule } = require('../timeparse');
const { knownFolder } = require('./computer');

const MODES = ['home', 'chat', 'voice', 'image', 'code', 'vision', 'research', 'automation', 'control', 'files', 'memory', 'comms', 'system', 'plugins', 'settings', 'models'];

function register(reg, svc) {
  reg.register({
    name: 'remember', label: 'Save memory', category: 'memory.write', risk: 'write', keywords: ['remember', 'prefer', 'note that', 'my name', 'i like', "don't forget"],
    description: 'Save a fact or preference to long-term memory when the user explicitly asks VIPER to remember something.',
    parameters: { type: 'object', properties: { content: { type: 'string', description: 'The fact, phrased in third person e.g. "User prefers short responses"' }, category: { type: 'string', enum: ['preference', 'fact', 'project', 'app', 'workflow', 'person', 'other'] } }, required: ['content'] },
    handler: async ({ content, category }) => {
      const m = svc.memory.add({ content, category: category || 'fact', source: 'assistant' });
      return { ok: true, result: { saved: !m.duplicate, duplicate: !!m.duplicate, temporary: !!m.temporary, id: m.id } };
    },
  });
  reg.register({
    name: 'recall_memory', label: 'Search memory', category: 'system.read', risk: 'read', keywords: ['remember', 'recall', 'what do you know', 'did i tell'],
    description: 'Search long-term memory for saved facts and preferences.',
    parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] },
    handler: async ({ query }) => ({ ok: true, result: svc.memory.search(query, 8).map((m) => ({ id: m.id, category: m.category, content: m.content })) }),
  });
  reg.register({
    name: 'forget_memory', label: 'Delete memory', category: 'memory.write', risk: 'destructive', keywords: ['forget'],
    description: 'Delete a saved memory by id (find ids with recall_memory first).',
    parameters: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    preview: (a) => { const m = svc.memory.get(a.id); return m ? `Forget: "${m.content}"` : a.id; },
    handler: async ({ id }) => ({ ok: svc.memory.delete(id), result: { deleted: id } }),
  });

  reg.register({
    name: 'set_reminder', label: 'Set reminder', category: 'reminders', risk: 'write', keywords: ['remind', 'reminder', 'alert me', "don't let me forget"],
    description: 'Create a reminder. "when" must contain a time, e.g. "in 20 minutes", "at 8pm", "tomorrow at 9". If the user gave no time, ask them instead of calling this.',
    parameters: { type: 'object', properties: { text: { type: 'string' }, when: { type: 'string' }, channels: { type: 'array', items: { type: 'string' } } }, required: ['text', 'when'] },
    handler: async ({ text, when, channels }) => {
      const due = parseDue(when);
      if (!due) return { ok: false, error: `Could not understand the time "${when}". Ask the user for a specific time.` };
      const r = svc.reminders.add({ text, dueAt: due, channels });
      return { ok: true, result: { id: r.id, text, due: new Date(due).toLocaleString() }, summary: `Reminder at ${new Date(due).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` };
    },
  });
  reg.register({
    name: 'list_reminders', label: 'List reminders', category: 'system.read', risk: 'read', keywords: ['reminder', 'reminders', 'scheduled'],
    description: 'List pending reminders.', parameters: { type: 'object', properties: {} },
    handler: async () => ({ ok: true, result: svc.reminders.list('pending').map((r) => ({ text: r.text, due: new Date(r.due_at).toLocaleString() })) }),
  });

  reg.register({
    name: 'create_automation', label: 'Create automation', category: 'automation.manage', risk: 'write', keywords: ['every', 'automat', 'schedule', 'when a', 'notify me when', 'check this folder', 'each morning', 'daily'],
    description: 'Create a recurring/triggered automation. schedule examples: "every morning at 8", "every 30 minutes", "weekdays at 7:30", "at 8pm" (one-off). Or watch a folder for new files / finished downloads. action: notify | system_report | briefing | ai_prompt | open_app.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string' }, schedule: { type: 'string', description: 'Natural-language schedule (omit for folder triggers)' },
        watch_folder: { type: 'string', description: 'Folder to watch for new files (known names like downloads allowed)' },
        watch_kind: { type: 'string', enum: ['new_file', 'download_finished'] },
        action: { type: 'string', enum: ['notify', 'system_report', 'briefing', 'ai_prompt', 'open_app'] },
        message: { type: 'string', description: 'Notification text, AI prompt, or app name depending on action' },
        channels: { type: 'array', items: { type: 'string' }, description: 'desktop, mobile, email, sms, ntfy' },
      },
      required: ['name', 'action'],
    },
    preview: (a) => `${a.name}\nWhen: ${a.schedule || `${a.watch_kind || 'new_file'} in ${a.watch_folder}`}\nDo: ${a.action}${a.message ? ` — ${a.message}` : ''}\nChannels: ${(a.channels || ['default']).join(', ')}`,
    handler: async (a) => {
      let trigger = null;
      if (a.watch_folder) {
        const folder = knownFolder(a.watch_folder) || a.watch_folder;
        trigger = { type: a.watch_kind === 'download_finished' ? 'download' : 'folder', folder };
      } else if (a.schedule) {
        trigger = parseSchedule(a.schedule);
        if (!trigger) { const at = parseDue(a.schedule); if (at) trigger = { type: 'once', at }; }
      }
      if (!trigger) return { ok: false, error: 'Could not determine when this automation should run. Ask the user for a schedule or folder.' };
      const actMap = {
        notify: { type: 'notify', title: a.name, message: a.message || (trigger.type === 'download' ? 'Download finished: {file}' : trigger.type === 'folder' ? 'New file: {file}' : a.name) },
        system_report: { type: 'system_report' }, briefing: { type: 'briefing', kind: 'morning' },
        ai_prompt: { type: 'ai_prompt', prompt: a.message || a.name }, open_app: { type: 'open_app', app: a.message },
      };
      const created = svc.automation.create({ name: a.name, description: a.schedule || '', trigger, actions: [actMap[a.action]], channels: a.channels || [] });
      return { ok: true, result: { id: created.id, name: created.name, trigger: trigger.description || trigger.type, nextRun: svc.automation.list().find((x) => x.id === created.id)?.nextRun } };
    },
  });
  reg.register({
    name: 'list_automations', label: 'List automations', category: 'system.read', risk: 'read', keywords: ['automation', 'scheduled', 'workflows'],
    description: 'List the automations and their status.', parameters: { type: 'object', properties: {} },
    handler: async () => ({ ok: true, result: svc.automation.list().map((a) => ({ name: a.name, enabled: a.enabled, trigger: a.trigger.description || a.trigger.type, lastRun: a.last_run ? new Date(a.last_run).toLocaleString() : 'never', lastStatus: a.last_status, nextRun: a.nextRun ? new Date(a.nextRun).toLocaleString() : null })) }),
  });

  reg.register({
    name: 'notify_me', label: 'Send notification', category: 'notify.send', risk: 'write', keywords: ['notify', 'notification', 'phone', 'ping me', 'alert'],
    description: 'Send the user a notification now via desktop, mobile (paired phone), email, sms or ntfy.',
    parameters: { type: 'object', properties: { title: { type: 'string' }, message: { type: 'string' }, channels: { type: 'array', items: { type: 'string' } }, priority: { type: 'string', enum: ['low', 'normal', 'high', 'urgent'] } }, required: ['title'] },
    handler: async (a) => {
      const r = await svc.notify.send({ title: a.title, body: a.message, channels: a.channels, priority: a.priority, category: 'general' });
      const failed = Object.entries(r.results).filter(([, v]) => !v.ok && !v.queued).map(([k, v]) => `${k}: ${v.error}`);
      return { ok: failed.length === 0, result: { delivered: Object.entries(r.results).filter(([, v]) => v.ok).map(([k]) => k), queued: Object.entries(r.results).filter(([, v]) => v.queued).map(([k]) => k), suppressed: r.suppressed }, error: failed.join('; ') || undefined };
    },
  });

  reg.register({
    name: 'switch_mode', label: 'Switch mode', category: 'ui.control', risk: 'read', keywords: ['mode', 'switch', 'launch', 'studio', 'open'],
    description: `Switch the VIPER interface to a mode: ${MODES.join(', ')}.`,
    parameters: { type: 'object', properties: { mode: { type: 'string', enum: MODES } }, required: ['mode'] },
    handler: async ({ mode }) => { svc.bus.publish('ui.navigate', { mode }); return { ok: true, result: { mode } }; },
  });
  reg.register({
    name: 'open_hud', label: 'Floating HUD', category: 'ui.control', risk: 'read', keywords: ['floating', 'hud', 'overlay'],
    description: 'Open (or close) the floating desktop HUD.',
    parameters: { type: 'object', properties: { show: { type: 'boolean', default: true } } },
    handler: async ({ show }) => { const r = await svc.bridge.toggleHud(show); return r?.ok === false ? { ok: false, error: r.error } : { ok: true, result: { hud: show ? 'open' : 'closed' } }; },
  });
  reg.register({
    name: 'stop_speaking', label: 'Stop speaking', category: 'ui.control', risk: 'read', hidden: true,
    description: 'Stop any speech output immediately.', parameters: { type: 'object', properties: {} },
    handler: async () => { svc.bus.publish('voice.stop', {}); return { ok: true, result: 'stopped' }; },
  });
  reg.register({
    name: 'briefing', label: 'Briefing', category: 'system.read', risk: 'read', keywords: ['briefing', 'summary', 'morning', 'evening', 'catch me up'],
    description: 'Build the morning briefing, evening summary or daily summary from real system, reminder and automation data.',
    parameters: { type: 'object', properties: { kind: { type: 'string', enum: ['morning', 'evening', 'daily'] } } },
    handler: async ({ kind }) => { const b = await svc.briefing.build(kind || 'morning'); return { ok: true, result: b.text }; },
  });
  reg.register({
    name: 'watch_task_completion', label: 'Notify when done', category: 'notify.send', risk: 'write', keywords: ['when this', 'when it finishes', 'when done', 'finished', 'notify my phone'],
    description: 'Notify the user (e.g. on their phone) when the currently running VIPER task (model download, automation, research, image generation) finishes.',
    parameters: { type: 'object', properties: { channels: { type: 'array', items: { type: 'string' } } } },
    handler: async ({ channels }) => {
      const active = svc.taskWatch.activeTasks();
      if (!active.length) return { ok: false, error: 'No VIPER task is currently running to watch.' };
      svc.taskWatch.notifyOnCompletion(active, channels && channels.length ? channels : ['mobile', 'desktop']);
      return { ok: true, result: { watching: active.map((t) => t.label) } };
    },
  });
}

module.exports = { register, MODES };
