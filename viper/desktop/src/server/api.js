'use strict';
// Core REST API (versioned under /api/v1). Feature modules add their own routes.
const { HttpError } = require('./http');
const { detectHardware } = require('./hardware');
const { CATEGORY_INFO } = require('./permissions');
const { parseDue, parseSchedule } = require('./timeparse');

function coreRoutes(r, svc) {
  const P = '/api/v1';
  r.get(`${P}/status`, async () => ({
    name: 'VIPER', version: svc.version, setupComplete: svc.settings.get('app').setupComplete, platform: process.platform,
    bridge: svc.bridge.kind, vault: svc.vault.kind, health: svc.models.health, activeBackend: svc.settings.get('backend').active,
    remote: svc.remote ? svc.remote.status() : null, uptimeSec: Math.round(process.uptime()),
  }), { scope: 'read' });

  // Settings
  r.get(`${P}/settings`, async () => svc.settings.all());
  r.get(`${P}/settings/:section`, async ({ params }) => svc.settings.get(params.section));
  r.patch(`${P}/settings/:section`, async ({ params, body }) => {
    if (params.section === 'permissions') for (const [k, v] of Object.entries(body)) if (!['allow', 'ask', 'deny'].includes(v)) throw new HttpError(400, `Invalid permission mode for ${k}`);
    const out = svc.settings.set(params.section, body, { replace: Array.isArray(body) });
    svc.events.onSettingsChanged?.(params.section);
    return out;
  });
  r.post(`${P}/settings/:section/reset`, async ({ params }) => { svc.settings.reset(params.section); return svc.settings.get(params.section); });
  r.get(`${P}/permissions/info`, async () => CATEGORY_INFO);
  r.post(`${P}/setup/complete`, async () => svc.settings.set('app', { setupComplete: true, firstRunAt: Date.now() }));

  // Hardware + recommendations
  r.get(`${P}/hardware`, async ({ query }) => detectHardware(query.refresh === '1'));
  r.get(`${P}/recommendation`, async () => svc.models.recommendation(await detectHardware()));
  r.get(`${P}/performance`, async () => svc.performance.status());
  r.post(`${P}/performance/preset`, async ({ body }) => {
    if (!['auto', 'eco', 'balanced', 'performance'].includes(body.preset)) throw new HttpError(400, 'preset must be auto, eco, balanced or performance');
    const st = svc.performance.apply(body.preset);
    svc.scheduleWarmup?.('preset changed', 500);
    return st;
  });
  r.get(`${P}/ai/startup`, async () => svc.aiStartup.status(), { scope: 'read' });
  r.get(`${P}/ai/engines`, async () => { const [o, f] = await Promise.all([svc.aiStartup.engineInstalled('ollama'), svc.aiStartup.engineInstalled('foundry').catch(() => ({ ok: false }))]); return { ollama: { installed: o.ok, path: o.path }, foundry: { installed: f.ok } }; });
  r.get(`${P}/ai/engine-install`, async () => svc.engineInstaller.status());
  r.post(`${P}/ai/startup/retry`, async () => { svc.aiStartup.recoveries = []; return svc.aiStartup.run('retry'); });
  r.post(`${P}/models/warmup`, async () => (await svc.orchestrator.warmup('manual')) || { skipped: true, reason: 'No chat model available or engine offline' });

  // Models / backends
  r.post(`${P}/models/health`, async () => svc.models.checkHealth(), { scope: 'read' });
  r.get(`${P}/models`, async ({ query }) => svc.models.listInstalled(query.refresh === '1'), { scope: 'read' });
  r.get(`${P}/models/status`, async () => svc.models.status(), { scope: 'read' });
  r.get(`${P}/models/catalog`, async ({ query }) => svc.models.catalog(query.backend || svc.settings.get('backend').active));
  r.get(`${P}/models/loaded`, async () => svc.models.loadedModels());
  r.get(`${P}/models/perf`, async () => svc.models.perfSummary());
  r.get(`${P}/models/downloads`, async () => svc.models.listDownloads());
  r.post(`${P}/models/pull`, async ({ body }) => svc.models.startDownload(body.backend, body.model));
  r.post(`${P}/models/cancel`, async ({ body }) => { svc.models.cancelDownload(body.id); });
  r.post(`${P}/models/remove`, async ({ body }) => { await svc.models.backend(body.backend).remove(body.model); svc.models.modelCache.at = 0; });
  r.post(`${P}/models/load`, async ({ body }) => { await svc.models.backend(body.backend).load(body.model); });
  r.post(`${P}/models/unload`, async ({ body }) => { await svc.models.backend(body.backend).unload(body.model); });
  r.post(`${P}/models/benchmark`, async ({ body }) => svc.models.benchmark(body.backend, body.model));
  r.post(`${P}/models/role`, async ({ body }) => {
    const valid = ['chat', 'code', 'vision', 'embeddings', 'image', 'stt', 'tts'];
    if (!valid.includes(body.role)) throw new HttpError(400, 'Unknown role');
    return svc.settings.set('models', { [body.role]: { backend: body.backend || '', model: body.model || '' } });
  }, { scope: 'models' });
  r.post(`${P}/backend/active`, async ({ body }) => {
    if (!svc.models.backends[body.backend]) throw new HttpError(400, 'Unknown backend');
    svc.settings.set('backend', { active: body.backend });
    svc.models.modelCache.at = 0;
    return svc.models.checkHealth();
  });
  r.post(`${P}/backend/test`, async ({ body }) => {
    const b = svc.models.backend(body.backend);
    const h = await b.health();
    if (!h.ok) return { ok: false, stage: 'connect', ...h };
    const target = await svc.models.resolve('chat');
    const model = body.model || (target.backend === body.backend ? target.model : null) || (await b.listModels().catch(() => []))[0]?.id;
    if (!model) return { ok: false, stage: 'model', error: 'Connected, but no model is installed yet.' };
    const t0 = Date.now();
    const out = await svc.models.complete({ backend: body.backend, model, messages: [{ role: 'user', content: 'Reply with exactly: VIPER online.' }], options: { maxTokens: 20, temperature: 0 } });
    return { ok: true, model, reply: out.text.trim(), ms: Date.now() - t0, perf: out.perf };
  });
  r.post(`${P}/backend/foundry/start`, async () => ({ endpoint: await svc.models.backends.foundry.startService() }));
  r.get(`${P}/backend/foundry/cli`, async () => svc.models.backends.foundry.cliInstalled());
  // Engine installers: Foundry Local via winget (official package), Ollama via its download page.
  r.post(`${P}/backend/:id/install`, async ({ params }) => {
    if (params.id === 'foundry') {
      if (process.platform !== 'win32') { await svc.bridge.openExternal('https://learn.microsoft.com/azure/foundry-local/get-started'); return { started: false, message: 'Foundry Local installs via winget on Windows; opened the documentation.' }; }
      const ok = await svc.permissions.requestConfirmation({ tool: 'install_foundry', title: 'Install Microsoft Foundry Local?', preview: 'winget install Microsoft.FoundryLocal --accept-source-agreements --accept-package-agreements', risk: 'write', category: 'scripts.run', reason: 'Runs the official Windows Package Manager installer for Foundry Local.', origin: 'desktop' });
      if (!ok) throw new HttpError(403, 'Installation declined');
      const { spawn } = require('node:child_process');
      const p = spawn('winget', ['install', '--id', 'Microsoft.FoundryLocal', '-e', '--accept-source-agreements', '--accept-package-agreements'], { windowsHide: false, detached: true, stdio: 'ignore' });
      p.on('error', () => svc.bus.publish('notification', { title: 'winget not available', body: 'Install Foundry Local manually from Microsoft Learn.' }));
      p.unref();
      return { started: true, message: 'The Windows installer is running. Return here and press Refresh when it finishes.' };
    }
    if (params.id === 'ollama') {
      if (process.platform !== 'win32') { await svc.bridge.openExternal('https://ollama.com/download'); return { started: false, message: 'Install Ollama from ollama.com, then press Retry.' }; }
      return svc.engineInstaller.installOllama();
    }
    throw new HttpError(400, 'Unknown engine');
  });

  // Chat
  r.get(`${P}/conversations`, async ({ query }) => svc.orchestrator.listConversations({ q: query.q, mode: query.mode }), { scope: 'chat' });
  r.post(`${P}/conversations`, async ({ body }) => svc.orchestrator.createConversation(body), { scope: 'chat' });
  r.patch(`${P}/conversations/:id`, async ({ params, body }) => svc.orchestrator.updateConversation(params.id, body), { scope: 'chat' });
  r.delete(`${P}/conversations/:id`, async ({ params }) => svc.orchestrator.deleteConversation(params.id), { scope: 'chat' });
  r.get(`${P}/conversations/:id/messages`, async ({ params }) => svc.orchestrator.messages(params.id).map(({ meta, ...m }) => ({ ...m, meta: { ...meta, images: undefined, docContext: undefined, hasImages: !!meta?.images?.length } })), { scope: 'chat' });
  r.get(`${P}/conversations/:id/export`, async ({ params, query }) => {
    const fmt = query.format === 'json' ? 'json' : 'markdown';
    return { __raw: Buffer.from(svc.orchestrator.exportConversation(params.id, fmt)), type: fmt === 'json' ? 'application/json' : 'text/markdown', filename: `viper-conversation.${fmt === 'json' ? 'json' : 'md'}` };
  }, { scope: 'chat' });
  r.post(`${P}/chat`, async ({ body, auth }) => {
    if (!body.text && !body.attachments?.length) throw new HttpError(400, 'Message is empty');
    const { requestId, conversationId } = svc.orchestrator.handle({ ...body, device: auth.device || null });
    return { requestId, conversationId };
  }, { scope: 'chat' });
  r.post(`${P}/chat/cancel`, async ({ body }) => ({ cancelled: body.requestId ? svc.orchestrator.cancel(body.requestId) : (svc.orchestrator.cancelAll(), true) }), { scope: 'chat' });

  // Confirmations (permission prompts)
  r.get(`${P}/confirm/pending`, async () => svc.permissions.listPending(), { scope: 'chat' });
  r.post(`${P}/confirm/:id`, async ({ params, body, auth }) => {
    const pending = svc.permissions.listPending().find((p) => p.id === params.id);
    // A phone may only approve prompts that its own request created.
    if (auth.device && pending && pending.origin !== `phone: ${auth.device.name}`) throw new HttpError(403, 'This prompt must be answered on the desktop');
    return { ok: svc.permissions.respond(params.id, !!body.approved) };
  }, { scope: 'chat' });

  // Tools (direct execution from UI buttons; permissions still enforced)
  r.get(`${P}/tools`, async () => svc.tools.list().map((t) => ({ name: t.name, label: t.label, description: t.description, category: t.category, risk: t.risk, parameters: t.parameters, plugin: t.plugin || null })));
  r.post(`${P}/tools/:name`, async ({ params, body, auth }) => svc.tools.execute(params.name, body.args || {}, { actor: auth.device ? `device:${auth.device.name}` : 'user', device: auth.device || null, origin: auth.device ? 'phone' : 'desktop', userInitiated: true }), { scope: 'control' });
  r.get(`${P}/approved-scripts`, async () => svc.settings.get('approvedScripts').map((s) => ({ name: s.name })), { scope: 'control' });
  r.get(`${P}/apps`, async ({ query }) => (query.q ? svc.apps.find(query.q) : svc.apps.list()), { scope: 'read' });
  r.post(`${P}/apps/refresh`, async () => (await svc.apps.refresh()).length);

  // Vision
  r.post(`${P}/vision/analyze`, async ({ body, auth }) => {
    if (!body.image) throw new HttpError(400, 'Image required');
    const image = String(body.image).replace(/^data:[^,]*,/, '');
    return svc.orchestrator.analyzeImage({ prompt: String(body.prompt || 'Describe this image.').slice(0, 4000), image, requestId: body.requestId });
  }, { scope: 'chat' });
  r.post(`${P}/vision/capture`, async ({ auth }) => {
    const shot = await svc.tools.execute('take_screenshot', {}, { actor: auth.device ? `device:${auth.device.name}` : 'user', device: auth.device || null, origin: auth.device ? 'phone' : 'desktop' });
    if (!shot.ok) throw new HttpError(shot.denied ? 403 : 503, shot.error);
    return { dataUrl: `data:image/png;base64,${require('node:fs').readFileSync(shot.result.saved).toString('base64')}`, path: shot.result.saved };
  }, { scope: 'control' });

  // Memory
  r.get(`${P}/memory`, async ({ query }) => (query.q ? svc.memory.search(query.q, 100) : svc.memory.list({ category: query.category })), { scope: 'chat' });
  r.post(`${P}/memory`, async ({ body }) => svc.memory.add({ content: body.content, category: body.category, source: 'user' }));
  r.patch(`${P}/memory/:id`, async ({ params, body }) => svc.memory.update(params.id, body));
  r.delete(`${P}/memory/:id`, async ({ params }) => ({ deleted: svc.memory.delete(params.id) }));
  r.post(`${P}/memory/clear`, async ({ body }) => { if (body.confirm !== 'DELETE ALL') throw new HttpError(400, 'Confirmation text required'); svc.memory.clear(); });
  r.get(`${P}/memory/export`, async () => ({ __raw: Buffer.from(JSON.stringify(svc.memory.export(), null, 2)), type: 'application/json', filename: 'viper-memory.json' }));
  r.post(`${P}/memory/import`, async ({ body }) => svc.memory.import(body));

  // Reminders
  r.get(`${P}/reminders`, async () => svc.reminders.list(), { scope: 'read' });
  r.post(`${P}/reminders`, async ({ body }) => {
    const due = body.dueAt || parseDue(body.when);
    if (!due) throw new HttpError(400, `Could not understand time "${body.when}"`);
    return svc.reminders.add({ text: body.text, dueAt: due, channels: body.channels });
  }, { scope: 'reminders' });
  r.patch(`${P}/reminders/:id`, async ({ params, body }) => svc.reminders.update(params.id, body), { scope: 'reminders' });
  r.delete(`${P}/reminders/:id`, async ({ params }) => svc.reminders.delete(params.id), { scope: 'reminders' });

  // Automations
  r.get(`${P}/automations`, async () => svc.automation.list(), { scope: 'read' });
  r.post(`${P}/automations`, async ({ body }) => svc.automation.create(body), { scope: 'automation' });
  r.post(`${P}/automations/parse-schedule`, async ({ body }) => ({ trigger: parseSchedule(body.text) || (parseDue(body.text) ? { type: 'once', at: parseDue(body.text) } : null) }));
  r.post(`${P}/automations/from-text`, async ({ body, auth }) => {
    // Natural language → automation using the create_automation tool via the LLM.
    const { requestId, conversationId, done } = svc.orchestrator.handle({ text: `Create an automation: ${body.text}`, mode: 'automation', device: auth.device || null, private: true });
    const res = await done;
    svc.orchestrator.deleteConversation(conversationId); // throwaway private conversation
    return { requestId, conversationId, reply: res?.message?.content, error: res?.error };
  }, { scope: 'automation' });
  r.get(`${P}/automations/history`, async () => svc.automation.history(null, 100), { scope: 'read' });
  r.patch(`${P}/automations/:id`, async ({ params, body }) => svc.automation.update(params.id, body), { scope: 'automation' });
  r.delete(`${P}/automations/:id`, async ({ params }) => svc.automation.delete(params.id), { scope: 'automation' });
  r.post(`${P}/automations/:id/run`, async ({ params }) => svc.automation.run(params.id, { trigger: 'manual' }), { scope: 'automation' });
  r.get(`${P}/automations/:id/history`, async ({ params }) => svc.automation.history(params.id), { scope: 'read' });

  // Notifications
  r.get(`${P}/notifications`, async ({ query }) => svc.notify.list({ unreadOnly: query.unread === '1' }), { scope: 'read' });
  r.get(`${P}/notifications/channels`, async () => svc.notify.channelList());
  r.post(`${P}/notifications/test`, async ({ body }) => svc.notify.send({ title: body.title || 'Test notification', body: body.body || 'This is a test from VIPER.', channels: body.channels, priority: body.priority || 'normal', category: 'general' }));
  r.post(`${P}/notifications/:id/read`, async ({ params }) => svc.notify.markRead(params.id), { scope: 'read' });
  r.post(`${P}/notifications/:id/retry`, async ({ params }) => svc.notify.retry(params.id));
  r.post(`${P}/notifications/clear`, async () => svc.notify.clear());

  // System
  r.get(`${P}/system/snapshot`, async () => svc.monitor.snapshot(), { scope: 'read' });
  r.get(`${P}/system/history`, async ({ query }) => (query.range === 'day' ? svc.monitor.minuteHistory : svc.monitor.history), { scope: 'read' });
  r.get(`${P}/system/processes`, async ({ query }) => svc.monitor.processes(Number(query.limit) || 30), { scope: 'read' });
  r.post(`${P}/system/visibility`, async ({ body }) => svc.monitor.setVisible(body.visible));
  r.get(`${P}/tasks`, async () => ({ tasks: svc.taskWatch.list(), ai: [...svc.models.active.values()] }), { scope: 'read' });
  r.get(`${P}/activity`, async ({ query }) => svc.db.all('SELECT * FROM activity ORDER BY ts DESC LIMIT ?', Number(query.limit) || 200));
  r.post(`${P}/activity/clear`, async () => { svc.db.run('DELETE FROM activity'); });
  r.get(`${P}/logs/recent`, async () => svc.logger.recent.slice(-200));
  r.get(`${P}/transcripts`, async () => svc.db.all('SELECT * FROM transcripts ORDER BY ts DESC LIMIT 200'));
  r.post(`${P}/transcripts/clear`, async () => { svc.db.run('DELETE FROM transcripts'); });
  r.get(`${P}/briefing`, async ({ query }) => svc.briefing.build(query.kind || 'morning'), { scope: 'read' });
  r.post(`${P}/data/delete-all`, async ({ body }) => {
    if (body.confirm !== 'DELETE EVERYTHING') throw new HttpError(400, 'Confirmation text required');
    for (const t of ['messages_fts', 'messages', 'conversations', 'memories_fts', 'memories', 'reminders', 'automation_runs', 'automations', 'deliveries', 'notifications', 'activity', 'transcripts', 'research', 'images', 'chunks_fts', 'chunks', 'documents', 'model_perf']) svc.db.run(`DELETE FROM ${t}`);
    svc.automation.stop();
    svc.bus.publish('data.deleted', {});
  });
}

module.exports = { coreRoutes };
