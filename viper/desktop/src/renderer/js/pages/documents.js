import { h, clear, icon, btn, busy, toast, toastError, select, field, mdEl, readFileAs } from '../ui.js';

// MAKE → Document Studio: drafts documents with the local chat model, then saves them as
// Markdown, HTML or text in your Documents\VIPER Documents folder. The model is told never to
// invent facts — it leaves [placeholders] for anything you have not provided.
const KINDS = [['report', 'Report'], ['letter', 'Letter'], ['essay', 'Essay'], ['readme', 'README'], ['meeting', 'Meeting notes'], ['plan', 'Project plan'], ['summary', 'Summary of a file']];
export async function render(view, { app, api }) {
  let doc = '';
  const kind = select(KINDS, 'report', (v) => { srcRow.style.display = v === 'summary' ? '' : 'none'; });
  const tone = select([['professional', 'Professional'], ['friendly', 'Friendly'], ['formal', 'Formal'], ['plain', 'Plain English']], 'professional', () => {});
  const length = select([['short', 'Short'], ['medium', 'Medium'], ['long', 'Long']], 'medium', () => {});
  const prompt = h('textarea.input', { rows: 4, placeholder: 'What is the document about? Include the facts it must contain.' });
  let source = ''; const srcName = h('small.mist', {}, 'No file chosen');
  const srcIn = h('input', { type: 'file', style: { display: 'none' }, accept: '.txt,.md,.pdf,.docx,.csv,.json,.html', onchange: async (e) => {
    const f = e.target.files[0]; if (!f) return;
    try { const r = await api.post('/files/extract', { name: f.name, data: await readFileAs(f) }); source = r.text; srcName.textContent = `${f.name} · ${r.text.length.toLocaleString()} characters${r.truncated ? ' (truncated)' : ''}`; } catch (err) { toastError(err); }
  } });
  const srcRow = h('div.row', { style: { display: 'none' } }, btn('Choose a file', () => srcIn.click(), { cls: 'sm', ico: 'upload' }), srcName, srcIn);
  const preview = h('div.doc-preview'); const actions = h('div.row.wrap');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Document Studio'), h('div.sub', {}, 'Draft reports, letters, plans and summaries with your local AI model.'))),
    h('div.split', {},
      h('div.panel', {}, h('h3', {}, icon('doc'), 'Brief'), h('div.col', {}, h('div.row.wrap', {}, field('Type', kind), field('Tone', tone), field('Length', length)), prompt, srcRow,
        h('div.row', {}, btn('Write document', async (e) => busy(e.currentTarget, async () => {
          try {
            const r = await api.post('/studio/document', { kind: kind.value, prompt: prompt.value, source, tone: tone.value, length: length.value });
            doc = r.markdown; drawDoc(r);
          } catch (err) { toastError(err, 'Could not write the document'); }
        }), { cls: 'primary', ico: 'sparkle' })))),
      h('div.panel', {}, h('h3', {}, 'Result', h('span.r', {}, actions)), preview)));
  drawDoc();
  function drawDoc(r) {
    clear(preview).append(doc ? mdEl(doc) : h('div.empty.small', {}, 'Your document appears here.'));
    clear(actions);
    if (!doc) return;
    if (r?.perf) preview.append(h('small.mist', {}, `${r.model || r.perf.model || ''} · ${r.perf.tokens || '?'} tokens${r.perf.tokPerS ? ` at ${r.perf.tokPerS} tok/s` : ''}`));
    const save = (fmt) => async () => {
      const name = (doc.match(/^#\s+(.+)$/m)?.[1] || KINDS.find(([k]) => k === kind.value)[1]).slice(0, 80);
      try { const s = await api.post('/studio/document/save', { name, content: doc, format: fmt }); toast('Saved', s.path); } catch (err) { toastError(err); }
    };
    actions.append(btn('Copy', () => { navigator.clipboard.writeText(doc); toast('Copied'); }, { cls: 'sm ghost', ico: 'copy' }), btn('Save .md', save('md'), { cls: 'sm' }), btn('Save .html', save('html'), { cls: 'sm' }));
  }
}
