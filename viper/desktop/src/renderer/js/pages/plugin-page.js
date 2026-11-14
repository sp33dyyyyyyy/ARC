import { h, clear, btn, busy, mdEl, toastError } from '../ui.js';

export async function render(view, { app, api, mode }) {
  const [pluginId, pageId] = mode.slice('plugin:'.length).split('/');
  const page = app.pluginPages.find((p) => p.id === `${pluginId}/${pageId}`);
  const out = h('div.panel'); const input = h('textarea.input', { rows: 3 });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, page?.title || pageId), h('div.sub', {}, `Provided by the ${page?.plugin || pluginId} plugin (sandboxed).`))), out);
  async function call(payload) {
    try {
      const r = await api.post(`/plugins/${pluginId}/page/${pageId}`, payload || {});
      clear(out).append(mdEl(r.markdown || ''),
        r.input ? h('div.col', { style: { marginTop: '12px' } }, Object.assign(input, { placeholder: r.input.placeholder || '' }), h('div.row', {}, btn('Submit', (e) => busy(e.currentTarget, () => call({ text: input.value }).then(() => { input.value = ''; })), { cls: 'primary sm' }), ...(r.actions || []).map((a) => btn(a.label, () => call(a.payload), { cls: 'sm' })))) : null);
    } catch (e) { toastError(e); clear(out).append(h('p', {}, e.message)); }
  }
  call({});
}
