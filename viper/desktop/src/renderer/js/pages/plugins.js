import { h, clear, icon, btn, busy, toast, toastError, ask, prompt, modal, toggle, when } from '../ui.js';

export async function render(view, { app, api }) {
  const list = h('div'); const ex = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Plugins'), h('div.sub', {}, 'Extend VIPER with tools, automation actions, notification channels, widgets and pages. Plugins run in an isolated sandbox and can only use the permissions you grant.')),
    h('div.actions', {}, btn('Install from folder or .zip', install, { cls: 'primary', ico: 'plus' }))), list, ex);
  async function install(src) {
    const source = typeof src === 'string' ? src : (window.viperNative?.pickFile ? await window.viperNative.pickFile([{ name: 'VIPER plugin', extensions: ['zip', 'json'] }]) : await prompt('Install plugin', { label: 'Path to a plugin folder or .zip' }));
    if (!source) return;
    try {
      const info = await api.post('/plugins/inspect', { source: source.replace(/[\\/]plugin\.json$/i, '') });
      const grant = new Set();
      modal({ title: `Install ${info.manifest.name} ${info.manifest.version}?`, body: h('div', {}, h('p.ink2', {}, info.manifest.description || ''),
        h('h3', { style: { marginTop: '10px' } }, 'Requested permissions'),
        info.permissions.length ? h('div.list', {}, info.permissions.map((p) => h('div.li', {}, h('div.t', {}, h('b', {}, p.id), h('small', {}, p.info)), toggle(false, (v) => (v ? grant.add(p.id) : grant.delete(p.id)), p.id)))) : h('p.small.mist', {}, 'None — this plugin cannot access the network, notifications, AI or storage.'),
        h('p.small.mist', { style: { marginTop: '8px' } }, `Contributes: ${Object.entries(info.manifest.contributes).map(([k, v]) => `${v.length} ${k}`).join(', ') || 'nothing'}. Plugins never get direct file, process or system access.`)),
      actions: [{ label: 'Cancel', cls: 'ghost' }, { label: 'Install', cls: 'primary', onClick: async () => { try { await api.post('/plugins/install', { source: info.folder, grant: [...grant] }); toast('Plugin installed', 'Enable it to start using it.'); load(); } catch (e) { toastError(e); return false; } } }] });
    } catch (e) { toastError(e, 'Not a valid plugin'); }
  }
  async function load() {
    const items = await api.get('/plugins').catch(() => []);
    clear(list).append(items.length ? h('div.grid.g2', {}, items.map((p) => h('div.panel', {},
      h('h3', {}, icon('plugins'), `${p.name}`, h('small.mist', {}, p.version), h('span.r', {}, toggle(p.enabled, async (v) => { try { await api.post(`/plugins/${p.id}/${v ? 'enable' : 'disable'}`); } catch (e) { toastError(e, 'Plugin failed to start'); } load(); }, `Enable ${p.name}`))),
      h('p.small.mist', {}, p.manifest.description || ''), p.error ? h('p.small', {}, h('span.badge-inv', {}, 'Error'), ` ${p.error}`) : null,
      h('div.list', {}, p.permissionInfo.map((x) => h('div.li', {}, h('div.t', {}, h('b', {}, x.id), h('small', {}, x.info)), toggle(p.granted.includes(x.id), async (v) => { await api.post(`/plugins/${p.id}/grants`, { granted: v ? [...p.granted, x.id] : p.granted.filter((g) => g !== x.id) }); load(); }, x.id)))),
      h('p.small.mist', {}, `Installed ${when(p.installed_at)} · ${Object.entries(p.manifest.contributes || {}).map(([k, v]) => `${v.length} ${k}`).join(', ')}`),
      btn('Uninstall', async () => { if (await ask(`Uninstall ${p.name}?`, 'Its files and stored data are removed.', { danger: true, confirmLabel: 'Uninstall' })) { await api.del(`/plugins/${p.id}`); load(); } }, { cls: 'sm ghost' })))) : h('div.empty', {}, h('b', {}, 'No plugins installed'), 'Install the example below to see how plugins work.'));
    const examples = await api.get('/plugins/examples').catch(() => []);
    clear(ex).append(examples.length ? h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Bundled examples'), h('div.list', {}, examples.map((e) => h('div.li', {}, h('div.t', {}, h('b', {}, e.name), h('small', {}, e.description)), items.some((i) => i.id === e.id) ? h('span.tag.on', {}, 'Installed') : btn('Install', () => install(e.folder), { cls: 'sm' }))))) : null,
      h('div.panel', { style: { marginTop: '14px' } }, h('h3', {}, 'Writing a plugin'), h('p.small.mist', {}, 'A plugin is a folder with plugin.json (id, name, version, permissions, contributes) and a main.js that fills in plugin.tools, plugin.actions, plugin.widgets, plugin.pages, plugin.notify or plugin.readers. See docs/PLUGINS.md.')));
  }
  load();
}
