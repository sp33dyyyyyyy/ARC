'use strict';
// Line-oriented readers for SSE (OpenAI-style) and NDJSON (Ollama) streams.
async function* readLines(body, signal) {
  const reader = body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  try {
    while (true) {
      if (signal?.aborted) throw signal.reason || new Error('aborted');
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).replace(/\r$/, '');
        buf = buf.slice(i + 1);
        yield line;
      }
    }
    if (buf.trim()) yield buf;
  } finally {
    try { reader.releaseLock(); } catch { /* noop */ }
  }
}

async function* readSSE(body, signal) {
  for await (const line of readLines(body, signal)) {
    if (!line.startsWith('data:')) continue;
    const data = line.slice(5).trim();
    if (data === '[DONE]') return;
    if (!data) continue;
    try { yield JSON.parse(data); } catch { /* partial / keepalive */ }
  }
}

async function* readNDJSON(body, signal) {
  for await (const line of readLines(body, signal)) {
    const t = line.trim();
    if (!t) continue;
    try { yield JSON.parse(t); } catch { /* ignore malformed */ }
  }
}

module.exports = { readLines, readSSE, readNDJSON };
