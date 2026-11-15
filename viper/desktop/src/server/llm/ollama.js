'use strict';
// Native Ollama backend (https://github.com/ollama/ollama/blob/main/docs/api.md)
const { readNDJSON } = require('./stream');
const { fetchWithTimeout } = require('../util');
const { guessCapabilities } = require('./openai');

/**
 * Threads for CPU inference. llama.cpp is fastest with one thread per *performance* core;
 * hyper-threads and Intel E-cores slow it down. A configurable number of cores is left free
 * so VIPER's interface and Windows stay responsive while a reply is generated.
 */
function inferenceThreads(l, cpu) {
  if (l.numThreads > 0) return l.numThreads;
  if (l.reserveUiCore === false) return 0; // let the engine decide
  const os = require('node:os');
  const physical = cpu?.physicalCores || Math.max(1, Math.floor(os.cpus().length / 2));
  const fast = cpu?.performanceCores || physical;
  const reserve = Number.isFinite(l.reserveCores) ? l.reserveCores : 1;
  // On hybrid CPUs the E-cores absorb the UI, so all P-cores can be used.
  const n = cpu?.performanceCores ? fast : fast - reserve;
  return physical >= 4 ? Math.max(2, n) : 0;
}

class OllamaBackend {
  constructor({ getUrl, getLimits, log }) {
    this.id = 'ollama'; this.label = 'Ollama'; this.getUrl = getUrl; this.getLimits = getLimits; this.log = log;
    this._caps = new Map();
  }
  base() { return (this.getUrl() || 'http://127.0.0.1:11434').replace(/\/+$/, ''); }
  async health() {
    try {
      const r = await fetchWithTimeout(`${this.base()}/api/version`, {}, 3000);
      if (!r.ok) return { ok: false, status: r.status, url: this.base() };
      const j = await r.json();
      return { ok: true, version: j.version, url: this.base() };
    } catch (e) { return { ok: false, error: e.message, url: this.base() }; }
  }
  async capabilities(name) {
    if (this._caps.has(name)) return this._caps.get(name);
    let caps = null;
    try {
      const r = await fetchWithTimeout(`${this.base()}/api/show`, { method: 'POST', body: JSON.stringify({ model: name }) }, 8000);
      if (r.ok) {
        const j = await r.json();
        if (Array.isArray(j.capabilities)) {
          caps = j.capabilities.map((c) => (c === 'completion' ? 'chat' : c === 'embedding' ? 'embeddings' : c));
          if (caps.includes('embeddings')) caps = caps.filter((c) => c !== 'chat');
          if (/coder|code/.test(name)) caps.push('code');
        }
      }
    } catch { /* fall through to heuristic */ }
    caps = caps || guessCapabilities(name);
    this._caps.set(name, caps);
    return caps;
  }
  async listModels() {
    const r = await fetchWithTimeout(`${this.base()}/api/tags`, {}, 8000);
    if (!r.ok) throw new Error(`Ollama /api/tags failed (${r.status})`);
    const j = await r.json();
    const loaded = await this.loaded().catch(() => []);
    const out = [];
    for (const m of j.models || []) {
      out.push({
        id: m.name, name: m.name, backend: 'ollama', installed: true,
        family: m.details?.family, parameterSize: m.details?.parameter_size, quantization: m.details?.quantization_level,
        sizeBytes: m.size, capabilities: await this.capabilities(m.name),
        loaded: loaded.some((l) => l.name === m.name),
      });
    }
    return out;
  }
  async loaded() {
    const r = await fetchWithTimeout(`${this.base()}/api/ps`, {}, 5000);
    if (!r.ok) return [];
    const j = await r.json();
    return (j.models || []).map((m) => ({ name: m.name, sizeBytes: m.size, vramBytes: m.size_vram, expiresAt: m.expires_at }));
  }
  async pull(model, onProgress, signal) {
    const r = await fetch(`${this.base()}/api/pull`, { method: 'POST', body: JSON.stringify({ model, stream: true }), signal });
    if (!r.ok) throw new Error(`Pull failed (${r.status}): ${(await r.text()).slice(0, 200)}`);
    let last = null;
    for await (const ev of readNDJSON(r.body, signal)) {
      if (ev.error) throw new Error(ev.error);
      last = ev;
      onProgress?.({ status: ev.status, completed: ev.completed || 0, total: ev.total || 0 });
    }
    if (!last || last.status !== 'success') throw new Error('Download did not complete');
    this._caps.delete(model);
    return true;
  }
  async remove(model) {
    const r = await fetchWithTimeout(`${this.base()}/api/delete`, { method: 'DELETE', body: JSON.stringify({ model }) }, 30000);
    if (!r.ok) throw new Error(`Delete failed (${r.status})`);
  }
  async load(model) {
    const r = await fetchWithTimeout(`${this.base()}/api/generate`, { method: 'POST', body: JSON.stringify({ model, prompt: '', keep_alive: this.getLimits().keepAlive || '5m' }) }, 300000);
    if (!r.ok) throw new Error(`Load failed (${r.status}): ${(await r.text()).slice(0, 200)}`);
    await r.text();
  }
  async unload(model) {
    const r = await fetchWithTimeout(`${this.base()}/api/generate`, { method: 'POST', body: JSON.stringify({ model, keep_alive: 0 }) }, 30000);
    await r.text().catch(() => '');
  }
  options(extra = {}) {
    const l = this.getLimits();
    const o = { temperature: extra.temperature ?? l.temperature ?? 0.6 };
    if (l.numCtx) o.num_ctx = l.numCtx;
    const t = inferenceThreads(l, this.cpu);
    if (t) o.num_thread = t;
    if (l.gpuLayers >= 0) o.num_gpu = l.gpuLayers;
    if (extra.maxTokens) o.num_predict = extra.maxTokens;
    return o;
  }
  async *chat({ model, messages, tools, options = {}, signal }) {
    const body = {
      model, stream: true, keep_alive: this.getLimits().keepAlive || '5m', options: this.options(options),
      messages: messages.map((m) => {
        const o = { role: m.role, content: m.content || '' };
        if (m.images?.length) o.images = m.images.map((b) => b.replace(/^data:[^;]+;base64,/, ''));
        if (m.tool_calls?.length) o.tool_calls = m.tool_calls.map((c) => ({ function: { name: c.name, arguments: c.arguments || {} } }));
        if (m.role === 'tool' && m.name) o.tool_name = m.name;
        return o;
      }),
    };
    if (tools?.length) body.tools = tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description, parameters: t.parameters } }));
    if (options.json) body.format = 'json'; // constrained JSON output (Code Agent plans and decisions)
    const r = await fetch(`${this.base()}/api/chat`, { method: 'POST', body: JSON.stringify(body), signal });
    if (!r.ok) {
      const text = await r.text().catch(() => '');
      const err = new Error(`Ollama returned ${r.status}: ${text.slice(0, 300)}`);
      err.status = r.status;
      if (/does not support tools/i.test(text)) err.code = 'NO_TOOLS';
      throw err;
    }
    const calls = [];
    let final = null;
    for await (const ev of readNDJSON(r.body, signal)) {
      if (ev.error) throw new Error(ev.error);
      const msg = ev.message || {};
      if (msg.thinking) yield { type: 'reasoning', text: msg.thinking };
      if (msg.content) yield { type: 'token', text: msg.content };
      for (const tc of msg.tool_calls || []) {
        calls.push({ id: `call_${calls.length}`, name: tc.function?.name, arguments: tc.function?.arguments || {} });
      }
      if (ev.done) final = ev;
    }
    if (calls.length) yield { type: 'tool_calls', calls };
    yield {
      type: 'done',
      usage: final ? { prompt_tokens: final.prompt_eval_count, completion_tokens: final.eval_count } : null,
      stats: final ? { evalCount: final.eval_count, evalDurationNs: final.eval_duration, loadDurationNs: final.load_duration, promptDurationNs: final.prompt_eval_duration } : null,
    };
  }
  async embed({ model, input }) {
    const r = await fetchWithTimeout(`${this.base()}/api/embed`, { method: 'POST', body: JSON.stringify({ model, input }) }, 300000);
    if (!r.ok) throw new Error(`Embeddings failed (${r.status}): ${(await r.text()).slice(0, 200)}`);
    const j = await r.json();
    return j.embeddings;
  }
}

module.exports = { OllamaBackend, inferenceThreads };
