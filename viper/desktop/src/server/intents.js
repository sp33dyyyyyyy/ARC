'use strict';
// Deterministic fast-path for common commands. Small local models are not
// always reliable at tool selection, so clear, unambiguous commands are
// routed directly to the real tool handlers here. Anything not matched goes
// to the language model (which can still call tools itself).
const { parseDue } = require('./timeparse');
const { formatBytes } = require('./util');

const MODE_WORDS = [
  [/\b(image|picture|art)\s*(mode|studio)?\b/, 'image'], [/\b(code|coding|programming)\s*(mode|studio)?\b/, 'code'],
  [/\bvision\s*(mode)?\b/, 'vision'], [/\bresearch\s*(mode)?\b/, 'research'], [/\bautomation(s)?\s*(mode)?\b/, 'automation'],
  [/\bmemory\s*(mode|bank)?\b/, 'memory'], [/\b(system monitor|system intelligence|diagnostics? (mode|panel|dashboard))\b/, 'system'],
  [/\bcomputer control\b/, 'control'], [/\bfile intelligence|documents? mode\b/, 'files'], [/\bcommunications?\b|\bemail mode\b/, 'comms'],
  [/\bsettings\b/, 'settings'], [/\bplugins?\b/, 'plugins'], [/\bmodel manager\b|\bmodels\b/, 'models'], [/\bchat\s*mode\b/, 'chat'], [/\bvoice\s*mode\b/, 'voice'], [/\bhome\b|\bdashboard\b/, 'home'],
];

function stripWake(text, wakeWords = ['viper', 'hey viper']) {
  let t = String(text || '').trim();
  const ww = [...wakeWords].sort((a, b) => b.length - a.length);
  for (const w of ww) {
    const re = new RegExp(`^${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[\\s,.!:;-]*`, 'i');
    if (re.test(t)) { t = t.replace(re, ''); break; }
  }
  const tail = new RegExp(`[\\s,]+(${ww.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})[.!?]*$`, 'i');
  return t.replace(tail, '').trim();
}

// "check my downloads" → "check your downloads" when echoing the user's words back.
function yourify(s) { return String(s).replace(/\b(my|mine|myself|me|i'm|i am|i)\b/gi, (w) => ({ my: 'your', mine: 'yours', myself: 'yourself', me: 'you', "i'm": "you're", 'i am': 'you are', i: 'you' })[w.toLowerCase()]); }
const VERB3 = { am: 'is', have: 'has', do: 'does', "don't": "doesn't", 'do not': 'does not', go: 'goes' };
function thirdPerson(fact) {
  let f = fact.trim();
  const m = f.match(/^(i|i'm)\s+(\S+)(.*)$/i);
  if (/^i'm\b/i.test(f)) f = `The user is${f.slice(3)}`;
  else if (m) { const v = m[2].toLowerCase(); const v3 = VERB3[v] || (/(s|sh|ch|x|o)$/.test(v) ? `${v}es` : /[^aeiou]y$/.test(v) ? `${v.slice(0, -1)}ies` : `${v}s`); f = `The user ${v3}${m[3]}`; }
  return f.replace(/\bmy\b/gi, "the user's").replace(/\bme\b/gi, 'the user').replace(/\bI am\b/g, 'the user is');
}
function pick(arr, seed) { return arr[Math.abs(seed) % arr.length]; }

class IntentRouter {
  constructor(svc) { this.svc = svc; this.pending = new Map(); /* conversationId -> slot */ }

  async route(rawText, ctx) {
    const svc = this.svc;
    const text = stripWake(rawText, svc.settings.get('voice').wakeWords);
    const t = text.toLowerCase().replace(/[!?.]+$/, '').trim();
    const seed = Date.now();
    const exec = (name, args) => svc.tools.execute(name, args, ctx);
    const address = svc.settings.get('personality').address;
    const sirSuffix = address && Math.random() < 0.3 ? `, ${address}` : '';

    // Follow-up slot: reminder waiting for a time.
    const slot = this.pending.get(ctx.conversationId);
    if (slot && slot.type === 'reminder_time') {
      const due = parseDue(t);
      if (due) {
        this.pending.delete(ctx.conversationId);
        const r = await exec('set_reminder', { text: slot.text, when: t });
        if (r.ok) return { reply: `Very good. I'll remind you to ${yourify(slot.text)} at ${new Date(due).toLocaleString([], { weekday: 'short', hour: '2-digit', minute: '2-digit' })}.`, tool: { name: 'set_reminder', result: r } };
        return { reply: `I couldn't set that reminder: ${r.error}` };
      }
      if (/^(never ?mind|cancel|forget it)/.test(t)) { this.pending.delete(ctx.conversationId); return { reply: 'Understood. Reminder cancelled.' }; }
      this.pending.delete(ctx.conversationId);
    }

    if (!t) return { reply: pick(['Yes?', 'At your service.', 'Listening.'], seed), wakeOnly: true };

    if (/^(stop|stop (speaking|talking)|be quiet|quiet|shut up|silence|that'?s enough)$/.test(t)) {
      await exec('stop_speaking', {});
      return { reply: '', silent: true, action: 'stop' };
    }
    if (/^(are you (online|there|awake|up|operational)|status report|you there|systems? check)$/.test(t)) {
      const h = await svc.models.checkHealth();
      const be = svc.settings.get('backend').active;
      const r = await svc.models.resolve('chat');
      if (h[be]?.ok && r.model) return { reply: `Online and operational. All local systems are available${sirSuffix}. How may I assist you?` };
      if (h[be]?.ok) return { reply: `I'm online, though no chat model is installed on ${svc.models.backends[be].label} yet. The Model Manager can fix that in a minute.` };
      return { reply: `I'm online, but the ${svc.models.backends[be].label} inference engine isn't responding, so my conversational abilities are limited. System tools and commands still work.` };
    }

    // Mode switching
    let m = t.match(/^(?:please\s+)?(?:switch to|go to|open|launch|show(?: me)?|start|enter)\s+(?:the\s+)?(.+?)(?:\s+mode)?$/);
    if (m && /\b(mode|studio|monitor|manager|settings|dashboard|home|plugins?|memory|automations?|research|vision|communications?|computer control|file intelligence)\b/.test(t)) {
      const target = m[1];
      if (/research session/.test(t) || /new research/.test(t)) { svc.bus.publish('ui.navigate', { mode: 'research', action: 'new' }); return { reply: 'Starting a new research session.', navigate: 'research' }; }
      for (const [re, mode] of MODE_WORDS) if (re.test(target) || re.test(t)) {
        svc.bus.publish('ui.navigate', { mode });
        if (/automations?/.test(t) && /show|scheduled/.test(t)) {
          const list = svc.automation.list();
          return { reply: list.length ? `You have ${list.length} automation${list.length > 1 ? 's' : ''}: ${list.slice(0, 4).map((a) => `${a.name}${a.enabled ? '' : ' (paused)'}`).join(', ')}.` : 'You have no automations yet. Shall I create one?', navigate: mode };
        }
        return { reply: pick([`Switching to ${labelFor(mode)}.`, `${labelFor(mode)}, coming up.`, `Opening ${labelFor(mode)}.`], seed), navigate: mode };
      }
    }
    if (/^(?:start|begin|open)\s+(?:a\s+)?new research( session)?$/.test(t)) { svc.bus.publish('ui.navigate', { mode: 'research', action: 'new' }); return { reply: 'Starting a new research session. What would you like me to investigate?', navigate: 'research' }; }
    if (/^(?:show|list)\s+(?:me\s+)?(?:my\s+)?(?:scheduled\s+)?automations$/.test(t)) {
      svc.bus.publish('ui.navigate', { mode: 'automation' });
      const list = svc.automation.list();
      return { reply: list.length ? `You have ${list.length} automation${list.length > 1 ? 's' : ''}: ${list.slice(0, 5).map((a) => `${a.name}${a.enabled ? '' : ' (paused)'}`).join(', ')}.` : 'There are no automations scheduled at the moment.', navigate: 'automation' };
    }
    if (/(open|show|launch|bring up)\s+(the\s+)?(floating (interface|hud|window)|hud|overlay)/.test(t)) {
      const r = await exec('open_hud', { show: true });
      return { reply: r.ok ? 'Floating interface deployed.' : `I couldn't open the floating interface: ${r.error}` };
    }
    if (/(close|hide)\s+(the\s+)?(floating (interface|hud|window)|hud|overlay)/.test(t)) { await exec('open_hud', { show: false }); return { reply: 'Floating interface closed.' }; }

    // System status
    if (/^(what'?s (happening|going on) with my (computer|pc|system)|how(?:'s| is) my (computer|pc|system)( doing)?|system status|pc status|computer status)$/.test(t)) {
      const s = await svc.monitor.snapshot();
      const issues = svc.briefing.assess(s);
      const memNote = s.mem?.pct > 85 ? `Memory consumption is high at ${s.mem.pct} percent` : s.mem?.pct > 70 ? 'Memory consumption is slightly elevated' : `Memory usage is comfortable at ${Math.round(s.mem?.pct)} percent`;
      const reply = issues.length > 1 || s.mem?.pct > 85 || s.cpu?.pct > 85
        ? `Your system is under some strain. ${memNote}, and the processor is at ${Math.round(s.cpu?.pct ?? 0)} percent. ${issues.filter((i) => !/memory/.test(i)).map((i) => i[0].toUpperCase() + i.slice(1)).join('. ')}`.trim()
        : `Your system is operating normally. ${memNote}${s.mem?.pct > 70 ? ', but nothing appears particularly concerning.' : `, and the processor is at ${Math.round(s.cpu?.pct ?? 0)} percent.`}`;
      return { reply, tool: { name: 'system_status' } };
    }
    if (/\b(cpu|processor)\s+temp(erature)?\b/.test(t)) {
      const r = await exec('cpu_temperature', {});
      if (!r.ok) return { reply: `I couldn't read the temperature: ${r.error}` };
      return { reply: r.result.available ? `Your CPU is currently at ${Math.round(r.result.cpuC)} degrees Celsius${r.result.cpuC > 85 ? ', which is quite warm' : ', which is within a normal range'}.` : 'This PC does not expose a CPU temperature sensor to applications, so I cannot give you a genuine reading. I would rather not guess.', tool: { name: 'cpu_temperature', result: r } };
    }
    if (/^(run|perform|start|initiate)\s+(a\s+)?(full\s+)?(system\s+)?diagnostics?$/.test(t)) {
      const r = await exec('run_diagnostics', {});
      if (!r.ok) return { reply: `Diagnostics could not run: ${r.error}` };
      const d = r.result;
      return { reply: `Initiating diagnostics. I've checked resource usage, storage capacity, active processes and system warnings. CPU is at ${d.cpuPercent ?? '?'} percent and memory at ${d.memoryPercent ?? '?'} percent. ${d.warnings.join(' ')}${typeof d.systemErrorsLast24h === 'number' ? ` The system log shows ${d.systemErrorsLast24h} error${d.systemErrorsLast24h === 1 ? '' : 's'} in the last 24 hours.` : ''}`, tool: { name: 'run_diagnostics', result: r } };
    }
    if (/^(how much )?(free )?(disk|storage) (space|capacity|left)|^check (my )?(disk|storage)/.test(t)) {
      const r = await exec('disk_space', {});
      if (!r.ok) return { reply: r.error };
      return { reply: r.result.map((d) => `${d.drive} has ${d.free} free of ${d.total}`).join('; ') + '.', tool: { name: 'disk_space', result: r } };
    }

    // Briefings
    if (/\b(morning briefing|evening summary|daily summary|brief me|catch me up)\b/.test(t) && !/email|send/.test(t)) {
      const kind = /evening/.test(t) ? 'evening' : /daily|catch me up/.test(t) ? 'daily' : 'morning';
      const b = await svc.briefing.build(kind);
      return { reply: b.text, tool: { name: 'briefing' } };
    }

    // Reminders
    m = t.match(/^remind me (?:to |about |that )?(.+)$/);
    if (m) {
      const body = m[1];
      const due = parseDue(body);
      const what = body.replace(/\b(later|in \d+\s*\w+|in (an?|half an?) \w+|at \d{1,2}(:\d{2})?\s*(am|pm)?|tomorrow( morning| afternoon| evening)?( at [\w: ]+)?|tonight|this (morning|afternoon|evening)|on \w+day( at [\w: ]+)?|next \w+)\b/g, '').replace(/\s+/g, ' ').trim();
      if (!due) {
        this.pending.set(ctx.conversationId, { type: 'reminder_time', text: what || body });
        return { reply: 'Of course. What time would you prefer?' };
      }
      const r = await exec('set_reminder', { text: what || body, when: body });
      if (!r.ok) return { reply: `I couldn't set that reminder: ${r.error}` };
      return { reply: `Certainly. I'll remind you to ${yourify(what || body)} ${humanWhen(due)}.`, tool: { name: 'set_reminder', result: r } };
    }

    // Memory
    m = text.match(/^(?:please\s+)?remember (?:that )?(.+)$/i);
    if (m && !/^(when|what|how|the time)\b/i.test(m[1])) {
      let fact = m[1].trim().replace(/[.]+$/, '');
      const pref = /\b(i prefer|i like|i (don'?t|do not) like|i want|i hate|i love|call me|always|never)\b/i.test(fact);
      fact = thirdPerson(fact);
      const r = await exec('remember', { content: fact[0].toUpperCase() + fact.slice(1), category: pref ? 'preference' : 'fact' });
      if (!r.ok) return { reply: `I couldn't save that: ${r.error}` };
      return { reply: r.result.duplicate ? 'I already have that noted.' : `Noted. I'll remember that${r.result.temporary ? ' for this session only, as temporary memory mode is on' : ''}.`, tool: { name: 'remember', result: r } };
    }

    // Volume
    m = t.match(/^(?:set (?:the )?volume to|volume to|volume)\s*(\d{1,3})\s*(%|percent)?$/);
    if (m) { const r = await exec('set_volume', { action: 'set', level: parseInt(m[1], 10) }); return { reply: r.ok ? `Volume set to ${r.result.verifiedLevel} percent.` : `I couldn't change the volume: ${r.error}` }; }
    if (/^(turn (the )?volume (up|down)|volume (up|down)|(raise|lower|increase|decrease) (the )?volume|mute|unmute)( the (volume|sound|audio))?$/.test(t)) {
      const action = /mute/.test(t) ? (/unmute/.test(t) ? 'unmute' : 'mute') : /(up|raise|increase)/.test(t) ? 'up' : 'down';
      const r = await exec('set_volume', { action });
      return { reply: r.ok ? (action === 'mute' ? 'Audio muted.' : action === 'unmute' ? `Audio restored at ${r.result.verifiedLevel} percent.` : `Volume is now ${r.result.verifiedLevel} percent.`) : `I couldn't change the volume: ${r.error}` };
    }

    // Screenshots / screen analysis
    if (/^(take|grab|capture) (a )?screenshot$/.test(t)) {
      const r = await exec('take_screenshot', {});
      return { reply: r.ok ? `Screenshot captured and saved to ${r.result.saved}.` : `No screenshot taken: ${r.error}` };
    }
    if (/(what'?s|what is|explain|describe|look at|analy[sz]e|read).*\b(on )?(my |the )?screen\b/.test(t)) {
      return { delegate: 'vision.screen', prompt: text };
    }

    // Open folders / apps / websites
    m = t.match(/^(?:please\s+)?(?:open|show|launch|start|run)\s+(?:up\s+)?(?:my\s+|the\s+)?(downloads|documents|desktop|pictures|music|videos|home)(?:\s+folder)?$/);
    if (m) { const r = await exec('open_folder', { folder: m[1] }); return { reply: r.ok ? `Opening your ${m[1]} folder.` : `I couldn't open it: ${r.error}` }; }
    m = t.match(/^(?:please\s+)?(?:open|go to|visit|browse to)\s+((?:https?:\/\/)?[\w-]+(?:\.[\w-]+)+(?:\/\S*)?)$/);
    if (m) { const r = await exec('open_url', { url: m[1] }); return { reply: r.ok ? `Opening ${m[1]}.` : `I couldn't open that site: ${r.error}` }; }
    m = text.match(/^(?:can you |could you |please )?(?:open|launch|start|run|fire up)\s+(?:up\s+)?(?:the\s+)?(?:app\s+)?([\w .+#&'-]{2,40}?)(?:\s+(?:app|application|for me|please|now))*[.!?]*$/i);
    if (m && !/\b(file|folder|document|mode|studio|session|interface|hud|website|page)\b/i.test(m[1])) {
      const name = m[1].trim();
      const matches = await svc.apps.find(name);
      if (matches.length) {
        const r = await exec('open_app', { name });
        if (!r.ok) return { reply: r.denied ? `Understood, I won't open ${name}.` : `I wasn't able to open ${name}: ${r.error}` };
        return { reply: r.result.verifiedRunning ? `Certainly. ${r.result.app} is now open.` : `Certainly. Opening ${r.result.app} now — the launch was accepted, though I can't yet confirm it's running.`, tool: { name: 'open_app', result: r } };
      }
    }
    m = t.match(/^(?:close|quit|exit|kill)\s+(?:the\s+)?([\w .+#&'-]{2,40})$/);
    if (m && !/(hud|floating|overlay|window)/.test(m[1])) {
      const r = await exec('close_app', { name: m[1] });
      if (!r.ok) return { reply: r.denied ? 'Understood. Leaving it open.' : `I couldn't close ${m[1]}: ${r.error}` };
      return { reply: `${m[1][0].toUpperCase() + m[1].slice(1)} has been closed.` };
    }

    // File search
    m = t.match(/^(?:search|look|find)\s+(?:through\s+)?(?:my\s+)?files?\s+(?:for\s+)?(.+)$/) || t.match(/^find (?:the |my )?(.+?) (?:file|document)s?$/);
    if (m) {
      const q = m[1];
      const since = /yesterday/.test(q) ? 'yesterday' : /today/.test(q) ? 'today' : /last week|this week/.test(q) ? '7 days' : undefined;
      const words = q.replace(/\b(the|a|an|i|my|me|that|which|worked|working|on|was|were|yesterday|today|last week|this week|from|for|with|file|files|document|documents)\b/g, ' ').replace(/\s+/g, ' ').trim();
      const r = await exec('search_files', { query: words, since });
      if (!r.ok) return { reply: `File search failed: ${r.error}` };
      const hits = r.result.matches;
      if (!hits.length && words && since) {
        const r2 = await exec('search_files', { query: '', since });
        if (r2.ok && r2.result.matches.length) return { reply: `Nothing named "${words}" turned up, but ${r2.result.matches.length} item${r2.result.matches.length > 1 ? 's were' : ' was'} modified ${since === 'yesterday' ? 'yesterday' : 'recently'}. The most recent: ${r2.result.matches.slice(0, 3).map((x) => x.name).join(', ')}.`, tool: { name: 'search_files', result: r2 }, files: r2.result.matches };
      }
      return { reply: hits.length ? `I found ${hits.length} match${hits.length > 1 ? 'es' : ''}. The most recent ${hits.length > 1 ? 'are' : 'is'}: ${hits.slice(0, 3).map((x) => x.name).join(', ')}.` : `I couldn't find anything matching "${words || q}" in your allowed folders.`, tool: { name: 'search_files', result: r }, files: hits };
    }

    // Email summary to self
    if (/^(send|email) me (an? )?(email )?(summary|report|briefing)|send me a (daily )?summary by email|email me (my |a )?(summary|briefing|status)/.test(t)) {
      const b = await svc.briefing.build('daily');
      const sys = await svc.briefing.systemReport();
      const r = await exec('send_email', { to: 'me', subject: 'VIPER summary', body: `${b.text}\n\n${sys}` });
      return { reply: r.ok ? 'Summary sent to your email.' : r.denied ? 'Understood, no email sent.' : `I couldn't send the email: ${r.error}` };
    }

    // Notify when finished
    if (/notify (my phone|me) when (this|it|that)( task)? (is )?(finishe[sd]|done|complete)/.test(t)) {
      const channels = /phone/.test(t) ? ['mobile'] : ['desktop', 'mobile'];
      const r = await exec('watch_task_completion', { channels });
      return { reply: r.ok ? `Very well. I'll notify ${/phone/.test(t) ? 'your phone' : 'you'} when ${r.result.watching.join(' and ')} finishes.` : 'There is no VIPER task running right now for me to watch.' };
    }
    return null;
  }
}

function labelFor(mode) {
  return { image: 'Image Studio', code: 'Code Studio', vision: 'Vision mode', research: 'Research mode', automation: 'Automation', memory: 'Memory', system: 'System Intelligence', control: 'Computer Control', files: 'File Intelligence', comms: 'Communications', settings: 'Settings', plugins: 'Plugins', models: 'the Model Manager', chat: 'Chat', voice: 'Voice', home: 'the dashboard' }[mode] || mode;
}
function humanWhen(ts) {
  const d = new Date(ts); const diff = ts - Date.now();
  if (diff < 3600000) return `in ${Math.max(1, Math.round(diff / 60000))} minute${Math.round(diff / 60000) === 1 ? '' : 's'}`;
  const sameDay = d.toDateString() === new Date().toDateString();
  const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (sameDay) return `at ${time}`;
  const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1);
  if (d.toDateString() === tomorrow.toDateString()) return `tomorrow at ${time}`;
  return `on ${d.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' })} at ${time}`;
}

module.exports = { IntentRouter, stripWake, humanWhen, formatBytes, thirdPerson, yourify };
