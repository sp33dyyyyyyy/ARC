'use strict';
const os = require('node:os');
const path = require('node:path');
const { jsonParse } = require('./util');

/**
 * The user's real Documents / Downloads / Desktop. The desktop shell passes the locations Windows
 * reports (they live under OneDrive when folder backup is on); otherwise common locations are probed.
 */
function defaultFolders(home) {
  let known = {}; try { known = JSON.parse(process.env.VIPER_KNOWN_FOLDERS || '{}'); } catch { /* ignore */ }
  const fs = require('node:fs');
  const pick = (key, name) => {
    if (known[key]) return known[key];
    const cands = [path.join(home, name), path.join(home, 'OneDrive', name)];
    return cands.find((c) => { try { return fs.statSync(c).isDirectory(); } catch { return false; } }) || cands[0];
  };
  return [...new Set([pick('documents', 'Documents'), pick('downloads', 'Downloads'), pick('desktop', 'Desktop')])];
}

function defaults() {
  const home = os.homedir();
  return {
    app: { setupComplete: false, setupStep: 0, firstRunAt: null, lastWorkingModel: null, version: require('../../package.json').version },
    backend: {
      active: 'ollama', // 'foundry' | 'ollama' | 'openai'
      foundry: { url: '', cliPath: 'foundry' },
      ollama: { url: 'http://127.0.0.1:11434', path: '' },
      openai: { url: 'http://127.0.0.1:8080/v1', label: 'OpenAI-compatible local server', apiKeySecret: '' },
      autoRecover: true,
      // Start the engine automatically when VIPER opens; stop it on exit only if VIPER started it.
      autoStart: true, stopOwnedOnExit: true,
      requestTimeoutSec: 300,
    },
    // Model per role. backend '' = use the active backend.
    models: {
      chat: { backend: '', model: '' },
      code: { backend: '', model: '' },
      vision: { backend: 'ollama', model: '' },
      embeddings: { backend: 'ollama', model: '' },
      image: { backend: 'a1111', model: '' },
      stt: { backend: 'whisper.cpp', model: 'base.en' },
      tts: { backend: 'piper', model: 'en_GB-alan-medium' },
    },
    limits: { numCtx: 4096, numThreads: 0, reserveUiCore: true, reserveCores: 1, gpuLayers: -1, keepAlive: '10m', maxContextMessages: 40, temperature: 0.6 },
    // Performance profile (see performance.js). 'auto' picks ECO/BALANCED/PERFORMANCE from the hardware.
    performance: { preset: 'auto', applied: '', appliedAt: 0, maxLoadedModels: 1, warmup: true, monitorMs: 2000, adaptiveQuality: true },
    personality: {
      name: 'VIPER', userName: '', address: 'sir', humour: 0.35, formality: 0.7, verbosity: 'concise',
      proactivity: 0.4, customInstructions: '',
    },
    voice: {
      wakeEnabled: false, wakeWords: ['viper', 'hey viper'], continuous: false, pushToTalk: true,
      inputDevice: '', outputDevice: '', sensitivity: 0.5, silenceMs: 900, noiseSuppression: true,
      echoCancellation: true, ttsEngine: 'piper', piperVoice: 'en_GB-alan-medium', systemVoice: '',
      rate: 1.0, speakReplies: true, sttModel: 'base.en', micMuted: false, language: 'en', startupGreeting: false,
    },
    privacy: {
      webAccess: false, // live internet research/fetching (explicit opt-in)
      allowedFolders: defaultFolders(home),
      saveTranscripts: true, temporaryMemory: false, cameraEnabled: false,
    },
    permissions: {
      'system.read': 'allow', 'apps.launch': 'allow', 'apps.close': 'ask', 'system.volume': 'allow',
      'windows.manage': 'allow', 'browser.open': 'allow', 'files.search': 'allow', 'files.read': 'allow',
      'files.write': 'ask', 'files.delete': 'ask', 'clipboard.read': 'ask', 'screen.capture': 'ask',
      'camera': 'ask', 'web.access': 'ask', 'scripts.run': 'ask', 'shell.workspace': 'ask',
      'email.read': 'ask', 'email.send': 'ask', 'sms.send': 'ask', 'notify.send': 'allow',
      'memory.write': 'allow', 'automation.manage': 'ask', 'ui.control': 'allow', 'reminders': 'allow', 'plugin.tools': 'ask',
    },
    approvedScripts: [], // [{ id, name, path, args: [] }]
    ui: {
      animations: 'full', fpsLimit: 60, leftPanel: true, rightPanel: true, compactSidebar: false,
      widgets: ['clock', 'system', 'model', 'network', 'phone', 'tasks', 'notifications', 'plugins'],
      hudShortcut: 'CommandOrControl+Shift+Space', hudOpacity: 0.92, hudCompact: false,
      launchAtStartup: false, startMinimized: false, closeToTray: true, showHudOnStart: false,
    },
    proactive: {
      enabled: false,
      morningBriefing: { enabled: false, time: '08:00', channels: ['desktop'] },
      eveningSummary: { enabled: false, time: '20:00', channels: ['desktop'] },
      lowDisk: { enabled: true, thresholdPct: 10 },
      highMemory: { enabled: true, thresholdPct: 92, sustainSec: 120 },
      highCpuTemp: { enabled: true, thresholdC: 90 },
      failedAutomations: true,
      downloads: { enabled: false, folder: path.join(home, 'Downloads') },
    },
    notifications: {
      quietHours: { enabled: false, start: '22:00', end: '07:00', allowUrgent: true },
      emergencyMute: false, rateLimitPerHour: 30, retryAttempts: 3,
      defaultChannels: ['desktop', 'mobile'],
      categories: { system: true, reminder: true, automation: true, research: true, communication: true, general: true },
      ntfy: { enabled: false, server: 'https://ntfy.sh', topic: '' },
      sms: { provider: 'none', twilio: { accountSid: '', from: '' } },
      emailAccountId: '', selfRecipientId: '',
    },
    remote: { enabled: false, port: 47801, localPort: 47800 },
    image: { backend: 'a1111', a1111Url: 'http://127.0.0.1:7860', defaultSteps: 25, defaultCfg: 7 },
    research: { maxSources: 5, searchEngine: 'duckduckgo' },
    updates: { checkOnStartup: true },
  };
}

function isObj(v) { return v && typeof v === 'object' && !Array.isArray(v); }
function deepMerge(base, patch) {
  if (!isObj(base) || !isObj(patch)) return patch === undefined ? base : patch;
  const out = { ...base };
  for (const [k, v] of Object.entries(patch)) out[k] = isObj(v) && isObj(base[k]) ? deepMerge(base[k], v) : v;
  return out;
}

class Settings {
  constructor(db, bus) {
    this.db = db; this.bus = bus;
    this.cache = defaults();
    for (const row of db.all('SELECT key, value FROM settings')) {
      const v = jsonParse(row.value);
      if (v !== null) this.cache[row.key] = deepMerge(this.cache[row.key] ?? {}, v);
    }
  }
  all() { return JSON.parse(JSON.stringify(this.cache)); }
  get(section) { return JSON.parse(JSON.stringify(this.cache[section])); }
  set(section, patch, { replace = false } = {}) {
    if (!(section in defaults())) throw new Error(`Unknown settings section: ${section}`);
    const next = replace ? patch : deepMerge(this.cache[section], patch);
    this.cache[section] = next;
    this.db.run('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', section, JSON.stringify(next));
    this.bus?.publish('settings.changed', { section, value: next });
    return this.get(section);
  }
  reset(section) {
    this.db.run('DELETE FROM settings WHERE key = ?', section);
    this.cache[section] = defaults()[section];
    this.bus?.publish('settings.changed', { section, value: this.cache[section] });
  }
}

module.exports = { Settings, defaults, deepMerge, defaultFolders };
