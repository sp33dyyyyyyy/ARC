'use strict';
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');

function defaultDataDir() {
  if (process.env.VIPER_DATA_DIR) return process.env.VIPER_DATA_DIR;
  if (process.platform === 'win32') {
    return path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'VIPER');
  }
  return path.join(os.homedir(), '.config', 'viper');
}

function makePaths(dataDir = defaultDataDir()) {
  const p = {
    data: dataDir,
    db: path.join(dataDir, 'viper.db'),
    logs: path.join(dataDir, 'logs'),
    images: path.join(dataDir, 'images'),
    uploads: path.join(dataDir, 'uploads'),
    exports: path.join(dataDir, 'exports'),
    research: path.join(dataDir, 'research'),
    components: process.env.VIPER_COMPONENTS_DIR || path.join(dataDir, 'components'), // whisper.cpp, piper, voices
    plugins: path.join(dataDir, 'plugins'),
    certs: path.join(dataDir, 'certs'),
    screenshots: path.join(dataDir, 'screenshots'),
    transfers: path.join(dataDir, 'transfers'),
  };
  for (const k of Object.keys(p)) {
    if (k === 'db') continue;
    fs.mkdirSync(p[k], { recursive: true });
  }
  return p;
}

module.exports = { makePaths, defaultDataDir };
