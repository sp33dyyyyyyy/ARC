'use strict';
// Installs a local AI engine when the user presses Install in VIPER's AI setup prompt.
// Ollama (Windows): downloads the official installer from Ollama's GitHub releases, runs it
// silently for the current user (no admin rights), then resumes VIPER's AI start-up.
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { downloadFile } = require('../download');

const OLLAMA_SETUP = 'https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe';

class EngineInstaller {
  constructor(svc) { this.svc = svc; this.log = svc.logger.scope('install'); this.job = null; }

  status() { return this.job; }

  publish() {
    const j = this.job;
    this.svc.bus.publish('engine.install', j);
    this.svc.bus.publish('task.update', { id: `install:${j.engine}`, label: j.label, kind: 'install', state: j.state === 'running' ? 'running' : j.state === 'done' ? 'done' : 'failed', progress: j.total ? j.received / j.total : null, error: j.error });
  }

  installOllama() {
    if (this.job?.state === 'running') return this.job;
    if (process.platform !== 'win32') throw Object.assign(new Error('Automatic installation is available on Windows. Install Ollama from ollama.com.'), { status: 400 });
    const dir = path.join(this.svc.paths.data, 'downloads'); fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'OllamaSetup.exe');
    this.job = { engine: 'ollama', state: 'running', stage: 'download', received: 0, total: 0, label: 'Downloading Ollama' };
    this.publish();
    (async () => {
      let last = 0;
      await downloadFile(OLLAMA_SETUP, file, { onProgress: (rec, total) => { Object.assign(this.job, { received: rec, total }); if (Date.now() - last > 400) { last = Date.now(); this.publish(); } } });
      Object.assign(this.job, { stage: 'install', label: 'Installing Ollama' }); this.publish();
      await new Promise((resolve, reject) => {
        // Wait for the installer process itself: it starts Ollama's tray app, which keeps running.
        const p = spawn(file, ['/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES'], { windowsHide: true, stdio: 'ignore' });
        const t = setTimeout(() => reject(new Error('The Ollama installer did not finish within 10 minutes.')), 600000);
        p.on('error', (e) => { clearTimeout(t); reject(e); });
        p.on('exit', (code) => { clearTimeout(t); code === 0 ? resolve() : reject(new Error(`The Ollama installer exited with code ${code}.`)); });
      });
      fs.rmSync(file, { force: true });
      Object.assign(this.job, { state: 'done', stage: 'done', label: 'Ollama installed' }); this.publish();
      this.log.info('Ollama installed');
      this.svc.scheduleStartup?.('engine installed', 1000);
    })().catch((e) => { Object.assign(this.job, { state: 'failed', error: e.message, label: 'Ollama installation failed' }); this.publish(); this.log.warn('Ollama install failed', e); });
    return this.job;
  }
}

module.exports = { EngineInstaller };
