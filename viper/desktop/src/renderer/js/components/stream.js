// Renders a streaming VIPER reply (tokens + tool cards) into an element.
import { h, icon, mdEl, clear } from '../ui.js';

export function followRequest(app, requestId, target, { onDone, onError, scroller } = {}) {
  const body = h('div.body'); const tools = h('div'); const text = h('div.cursor');
  clear(target).append(tools, body); body.append(text);
  let buf = ''; let raf = 0;
  const flush = () => { raf = 0; const md = mdEl(buf); md.classList.add('cursor'); body.replaceChildren(md); if (scroller) scroller.scrollTop = scroller.scrollHeight; };
  const handlers = {};
  const on = (type, fn) => { handlers[type] = fn; return app.api.on(type, fn); };
  const offs = [
    on('chat.token', (d) => { if (d.requestId !== requestId) return; buf += d.text; if (!raf) raf = requestAnimationFrame(flush); }),
    on('chat.tool', (d) => {
      if (d.requestId !== requestId) return;
      let card = tools.querySelector(`[data-tool="${d.name}"].running`);
      if (d.state === 'running') { card = h('span.toolcard.running', { 'data-tool': d.name }, h('span.dot'), d.name.replace(/_/g, ' ')); tools.append(card); }
      else if (card) { card.className = `toolcard ${d.state === 'done' ? '' : 'failed'}`; card.replaceChildren(icon(d.state === 'done' ? 'check' : 'x'), `${d.name.replace(/_/g, ' ')} — ${d.summary || d.state}`); }
    }),
    on('chat.done', (d) => { if (d.requestId !== requestId) return; stop(); if (!d.silent) body.replaceChildren(mdEl(d.message?.content || '')); onDone?.(d); }),
    on('chat.error', (d) => { if (d.requestId !== requestId) return; stop(); body.replaceChildren(h('div.toolcard.failed', {}, icon('x'), d.error)); onError?.(d); }),
    on('chat.cancelled', (d) => { if (d.requestId !== requestId) return; stop(); body.replaceChildren(buf ? mdEl(buf + '\n\n_(stopped)_') : h('span.mist', {}, 'Stopped.')); onDone?.(d); }),
  ];
  for (const e of app.api.replay(requestId)) handlers[e.type]?.(e.data);
  function stop() { offs.forEach((o) => o()); if (raf) cancelAnimationFrame(raf); }
  return stop;
}
