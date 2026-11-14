// Message composer: auto-growing textarea, attachments, push-to-talk mic, send/stop.
import { h, icon, toast, readFileAs } from '../ui.js';

const TEXT_EXT = /\.(txt|md|csv|json|js|ts|tsx|jsx|py|cs|java|cpp|c|h|hpp|go|rs|rb|php|html|css|xml|yaml|yml|ini|log|gd|lua|sql|sh|ps1|bat)$/i;

export function composer({ app, onSend, placeholder = 'Message VIPER…', allowAttach = true, onStop }) {
  const attachments = [];
  const list = h('div.attach-list');
  const ta = h('textarea', { rows: 1, placeholder, 'aria-label': 'Message' });
  const grow = () => { ta.style.height = 'auto'; ta.style.height = `${Math.min(180, ta.scrollHeight)}px`; };
  ta.addEventListener('input', grow);
  let busyReq = null;
  const sendBtn = h('button.btn.primary.icon', { type: 'button', title: 'Send (Enter)', 'aria-label': 'Send' }, icon('send'));
  const setBusy = (reqId) => { busyReq = reqId; sendBtn.replaceChildren(icon(reqId ? 'stop' : 'send')); sendBtn.title = reqId ? 'Stop generating' : 'Send (Enter)'; };
  const submit = async () => {
    if (busyReq) { await app.api.post('/chat/cancel', { requestId: busyReq }).catch(() => {}); onStop?.(); setBusy(null); return; }
    const text = ta.value.trim();
    if (!text && !attachments.length) return;
    const atts = attachments.splice(0); list.replaceChildren();
    ta.value = ''; grow();
    await onSend(text, atts, setBusy);
  };
  sendBtn.addEventListener('click', submit);
  ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); submit(); } });

  const fileInput = h('input', { type: 'file', multiple: true, style: { display: 'none' }, onchange: async (e) => { for (const f of e.target.files) await addFile(f); e.target.value = ''; } });
  async function addFile(f) {
    if (f.size > 25 * 1024 * 1024) { toast('File too large', `${f.name} exceeds 25 MB.`, 'warn'); return; }
    let att;
    if (f.type.startsWith('image/')) att = { type: 'image', name: f.name, data: await readFileAs(f) };
    else if (TEXT_EXT.test(f.name)) att = { type: 'document', name: f.name, text: await readFileAs(f, 'text') };
    else {
      // PDFs, Word, spreadsheets: extracted locally by the File Intelligence service.
      try {
        const b64 = await readFileAs(f);
        const r = await app.api.post('/files/extract', { name: f.name, data: b64 });
        att = { type: 'document', name: f.name, text: r.text };
      } catch (e) { toast(`Can't read ${f.name}`, e.message, 'warn'); return; }
    }
    attachments.push(att);
    list.append(h('span.tag', {}, icon(att.type === 'image' ? 'image' : 'file'), f.name, h('button.btn.sm.ghost.icon', { 'aria-label': `Remove ${f.name}`, onclick: (e) => { attachments.splice(attachments.indexOf(att), 1); e.currentTarget.parentElement.remove(); } }, icon('x'))));
  }
  const mic = h('button.btn.icon.mic-btn', { type: 'button', title: 'Hold to talk (or Ctrl+Space)', 'aria-label': 'Hold to talk' }, icon('mic'));
  const down = async (e) => { e.preventDefault(); if (await app.voice.pttStart().catch((err) => { toast('Microphone', err.message, 'warn'); return false; })) mic.classList.add('live'); };
  const up = () => { if (mic.classList.contains('live')) { mic.classList.remove('live'); app.voice.pttStop(); } };
  mic.addEventListener('pointerdown', down); mic.addEventListener('pointerup', up); mic.addEventListener('pointerleave', up);
  const el = h('div', {},
    h('div.composer', {}, allowAttach ? h('button.btn.ghost.icon', { type: 'button', title: 'Attach files', 'aria-label': 'Attach files', onclick: () => fileInput.click() }, icon('paperclip')) : null, ta, mic, sendBtn),
    list, fileInput);
  el.addEventListener('dragover', (e) => e.preventDefault());
  el.addEventListener('drop', async (e) => { e.preventDefault(); for (const f of e.dataTransfer.files) await addFile(f); });
  return { el, focus: () => ta.focus(), setBusy, set value(v) { ta.value = v; grow(); }, addFile };
}
