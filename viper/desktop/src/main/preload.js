'use strict';
// Narrow, explicit bridge between VIPER pages and the desktop shell.
const { contextBridge, ipcRenderer } = require('electron');

const token = ipcRenderer.sendSync('viper:token');
let pttHandler = null; let pttDown = false;
ipcRenderer.on('viper:ptt-toggle', () => { pttDown = !pttDown; pttHandler?.(pttDown); });

contextBridge.exposeInMainWorld('viperNative', {
  token,
  platform: process.platform,
  window: (action) => ipcRenderer.invoke('viper:window', action),
  toggleHud: (show) => ipcRenderer.invoke('viper:hud', show),
  hudSize: (compact) => ipcRenderer.invoke('viper:hud-size', compact),
  showMain: (mode) => ipcRenderer.invoke('viper:show-main', mode),
  openExternal: (url) => ipcRenderer.invoke('viper:open-external', url),
  pickFolder: () => ipcRenderer.invoke('viper:pick-folder'),
  pickFile: (filters) => ipcRenderer.invoke('viper:pick-file', filters),
  checkUpdates: () => ipcRenderer.invoke('viper:check-updates'),
  installUpdate: () => ipcRenderer.invoke('viper:install-update'),
  openDataDir: () => ipcRenderer.invoke('viper:open-data'),
  flash: () => ipcRenderer.invoke('viper:flash'),
  wake: () => ipcRenderer.invoke('viper:wake'),
  onPtt: (fn) => { pttHandler = fn; },
});
