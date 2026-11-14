'use strict';
// OpenAI-compatible chat backend. Used directly for Foundry Local's
// /v1/chat/completions endpoint and for any other local OpenAI-compatible
// server (llama.cpp llama-server, LM Studio, vLLM...).
const { readSSE } = require('./stream');
const { fetchWithTimeout } = require('../util');

function toOpenAIMessages(messages) {
  return messages.map((m) => {
    if (m.role === 'tool') return { role: 'tool', tool_call_id: m.tool_call_id || m.name || 'call', content: m.content };
    if (m.role === 'assistant' && m.tool_calls?.length) {
      return {
        role: 'assistant', content: m.content || '',
        tool_calls: m.tool_calls.map((c) => ({ id: c.id, type: 'function', function: { name: c.name, arguments: JSON.stringify(c.arguments || {}) } })),
      };
    }
    if (m.images?.length) {
      return {
        role: m.role,
        content: [{ type: 'text', text: m.content || '' }, ...m.images.map((b64) => ({ type: 'image_url', image_url: { url: b64.startsWith('data:') ? b64 : `data:image/png;base64,${b64}` } }))],
      };
    }
    return { role: m.role, content: m.content };
  });
}

class OpenAICompatBackend {
  constructor({ id = 'openai', label = 'OpenAI-compatible', getBaseUrl, getApiKey = () => null, log }) {
    this.id = id; this.label = label; this.getBaseUrl = getBaseUrl; this.getApiKey = getApiKey; this.log = log;
  }
  async base() {
    const b = await this.getBaseUrl();
    if (!b) throw Object.assign(new Error(`${this.label} endpoint is not configured or not running.`), { code: 'ENDPOINT' });
    return b.replace(/\/+$/, '');
  }
  headers() {
    const h = { 'Content-Type': 'application/json' };
    const k = this.getApiKey();
    if (k) h.Authorization = `Bearer ${k}`;
    return h;
  }
  async health() {
    try {
      const base = await this.base();
      const r = await fetchWithTimeout(`${base}/models`, { headers: this.headers() }, 4000);
      return { ok: r.ok, url: base, status: r.status };
    } catch (e) { return { ok: false, error: e.message }; }
  }
  async listModels() {
    const base = await this.base();
    const r = await fetchWithTimeout(`${base}/models`, { headers: this.headers() }, 8000);
    if (!r.ok) throw new Error(`Model list failed (${r.status})`);
    const j = await r.json();
    const arr = Array.isArray(j) ? j : (j.data || j.models || []);
    return arr.map((m) => {
      const id = typeof m === 'string' ? m : (m.id || m.name);
      return { id, name: id, backend: this.id, installed: true, capabilities: guessCapabilities(id) };
    });
  }

  /** Streams a chat completion. Yields {type:'token'|'tool_calls'|'done'} events. */
  async *chat({ model, messages, tools, options = {}, signal }) {
    const base = await this.base();
    const body = {
      model, messages: toOpenAIMessages(messages), stream: true,
      temperature: options.temperature ?? 0.6,
    };
    if (options.maxTokens) body.max_tokens = options.maxTokens;
    if (tools?.length) body.tools = tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
    const r = await fetch(`${base}/chat/completions`, { method: 'POST', headers: this.headers(), body: JSON.stringify(body), signal });
    if (!r.ok) {
      const text = await r.text().catch(() => '');
      const err = new Error(`${this.label} returned ${r.status}: ${text.slice(0, 300)}`);
      err.status = r.status;
      throw err;
    }
    const calls = new Map();
    let usage = null; let finish = null;
    for await (const chunk of readSSE(r.body, signal)) {
      if (chunk.error) throw new Error(chunk.error.message || JSON.stringify(chunk.error));
      if (chunk.usage) usage = chunk.usage;
      const ch = chunk.choices?.[0];
      if (!ch) continue;
      const d = ch.delta || ch.message || {};
      if (d.content) yield { type: 'token', text: d.content };
      if (d.reasoning_content) yield { type: 'reasoning', text: d.reasoning_content };
      for (const tc of d.tool_calls || []) {
        const idx = tc.index ?? calls.size;
        const cur = calls.get(idx) || { id: tc.id || `call_${idx}`, name: '', args: '' };
        if (tc.id) cur.id = tc.id;
        if (tc.function?.name) cur.name += tc.function.name;
        if (tc.function?.arguments) cur.args += typeof tc.function.arguments === 'string' ? tc.function.arguments : JSON.stringify(tc.function.arguments);
        calls.set(idx, cur);
      }
      if (ch.finish_reason) finish = ch.finish_reason;
    }
    if (calls.size) {
      yield { type: 'tool_calls', calls: [...calls.values()].map((c) => ({ id: c.id, name: c.name, arguments: parseArgs(c.args) })) };
    }
    yield { type: 'done', usage, finish };
  }

  async embed({ model, input }) {
    const base = await this.base();
    const r = await fetchWithTimeout(`${base}/embeddings`, { method: 'POST', headers: this.headers(), body: JSON.stringify({ model, input }) }, 120000);
    if (!r.ok) throw new Error(`Embeddings failed (${r.status})`);
    const j = await r.json();
    return j.data.map((d) => d.embedding);
  }
}

function parseArgs(s) {
  if (!s) return {};
  if (typeof s === 'object') return s;
  try { return JSON.parse(s); } catch { return { _raw: s }; }
}

function guessCapabilities(id = '') {
  const s = id.toLowerCase();
  const caps = ['chat'];
  if (/embed|minilm|bge|e5-|gte/.test(s)) return ['embeddings'];
  if (/whisper/.test(s)) return ['speech'];
  if (/vision|llava|vl\b|vl-|-vl|moondream|gemma3|llama3\.2-vision|minicpm-v|qwen2\.5vl|qwen2-vl|phi-3\.5-vision|phi-4-multimodal/.test(s)) caps.push('vision');
  if (/coder|code|deepseek-coder|starcoder|codellama/.test(s)) caps.push('code');
  if (/qwen|llama3\.[123]|llama-3\.[123]|phi-4|mistral|hermes|granite|command-r|gpt-oss|smollm2/.test(s)) caps.push('tools');
  return caps;
}

module.exports = { OpenAICompatBackend, toOpenAIMessages, guessCapabilities, parseArgs };
