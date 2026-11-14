'use strict';
// Microsoft Foundry Local integration.
// Docs: https://learn.microsoft.com/azure/foundry-local/reference/reference-rest
//  - Inference: OpenAI-compatible POST {endpoint}/v1/chat/completions
//  - Management: GET /foundry/list (catalog), GET /openai/models (cached),
//    POST /openai/download (streamed progress), GET /openai/load/{name},
//    GET /openai/unload/{name}, GET /openai/loadedmodels, GET /openai/status
// The service port is dynamic, so the endpoint is discovered with
// `foundry service status` unless the user configured a URL explicitly.
const { execFile, spawn } = require('node:child_process');
const { OpenAICompatBackend, guessCapabilities } = require('./openai');
const { readLines } = require('./stream');
const { fetchWithTimeout } = require('../util');

function runCli(cli, args, timeout = 20000) {
  return new Promise((resolve) => {
    execFile(cli, args, { timeout, windowsHide: true }, (err, stdout, stderr) => {
      resolve({ ok: !err, code: err?.code, stdout: String(stdout || ''), stderr: String(stderr || ''), error: err });
    });
  });
}

function parseEndpoint(text) {
  const m = String(text).match(/https?:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):\d+/i);
  return m ? m[0].replace('localhost', '127.0.0.1') : null;
}

class FoundryBackend extends OpenAICompatBackend {
  constructor({ getConfig, log }) {
    super({ id: 'foundry', label: 'Foundry Local', getBaseUrl: async () => { const e = await this.endpoint(); return e ? `${e}/v1` : null; }, log });
    this.getConfig = getConfig;
    this._endpoint = null; this._checkedAt = 0;
    this._catalog = null;
  }
  cli() { return this.getConfig().cliPath || 'foundry'; }

  async cliInstalled() {
    const r = await runCli(this.cli(), ['--version'], 10000);
    return { installed: r.ok, version: r.stdout.trim() || null };
  }

  async endpoint(force = false) {
    const cfg = this.getConfig();
    if (cfg.url) return cfg.url.replace(/\/+$/, '').replace(/\/v1$/, '');
    if (!force && this._endpoint && Date.now() - this._checkedAt < 60000) return this._endpoint;
    const r = await runCli(this.cli(), ['service', 'status'], 15000);
    this._checkedAt = Date.now();
    this._endpoint = parseEndpoint(r.stdout + '\n' + r.stderr);
    return this._endpoint;
  }

  async startService() {
    const r = await runCli(this.cli(), ['service', 'start'], 60000);
    const ep = parseEndpoint(r.stdout + r.stderr) || await this.endpoint(true);
    if (!ep) throw new Error(`Could not start Foundry Local service: ${(r.stderr || r.stdout || r.error?.message || '').slice(0, 300)}`);
    this._endpoint = ep;
    return ep;
  }

  async health() {
    try {
      const ep = await this.endpoint();
      if (!ep) {
        const cli = await this.cliInstalled();
        return { ok: false, error: cli.installed ? 'Foundry Local service is not running' : 'Foundry Local CLI not found (install with: winget install Microsoft.FoundryLocal)', cliInstalled: cli.installed };
      }
      const r = await fetchWithTimeout(`${ep}/openai/status`, {}, 4000);
      if (!r.ok) return { ok: false, url: ep, status: r.status };
      const j = await r.json().catch(() => ({}));
      return { ok: true, url: ep, modelDir: j.ModelDirPath };
    } catch (e) { this._endpoint = null; return { ok: false, error: e.message }; }
  }

  async catalogRaw() {
    const ep = await this.endpoint();
    if (!ep) throw new Error('Foundry Local service is not running');
    const r = await fetchWithTimeout(`${ep}/foundry/list`, {}, 30000);
    if (!r.ok) throw new Error(`Catalog request failed (${r.status})`);
    const j = await r.json();
    this._catalog = Array.isArray(j) ? j : (j.models || []);
    return this._catalog;
  }

  async catalog() {
    const raw = await this.catalogRaw();
    const cached = new Set(await this.cachedNames().catch(() => []));
    return raw.map((m) => ({
      id: m.name, name: m.name, alias: m.alias, displayName: m.displayName || m.alias || m.name, backend: 'foundry',
      publisher: m.publisher, task: m.task, device: m.runtime?.deviceType, executionProvider: m.runtime?.executionProvider,
      sizeBytes: m.fileSizeMb ? m.fileSizeMb * 1024 * 1024 : null, supportsTools: !!m.supportsToolCalling,
      license: m.license, uri: m.uri, providerType: m.providerType, version: m.version, promptTemplate: m.promptTemplate,
      installed: cached.has(m.name) || [...cached].some((c) => c.split(':')[0] === m.name),
      capabilities: [...guessCapabilities(m.name), ...(m.supportsToolCalling ? ['tools'] : [])].filter((v, i, a) => a.indexOf(v) === i),
    }));
  }

  async cachedNames() {
    const ep = await this.endpoint();
    if (!ep) return [];
    const r = await fetchWithTimeout(`${ep}/openai/models`, {}, 8000);
    if (!r.ok) return [];
    const j = await r.json();
    return (Array.isArray(j) ? j : (j.data || [])).map((m) => (typeof m === 'string' ? m : m.id));
  }

  async listModels() {
    const names = await this.cachedNames();
    const loaded = new Set(await this.loadedNames().catch(() => []));
    let cat = this._catalog;
    if (!cat) cat = await this.catalogRaw().catch(() => []);
    return names.map((n) => {
      const meta = cat.find((c) => c.name === n || n.startsWith(c.name)) || {};
      const caps = guessCapabilities(n);
      if (meta.supportsToolCalling && !caps.includes('tools')) caps.push('tools');
      if (meta.supportsToolCalling === false) caps.splice(caps.indexOf('tools') >>> 0, caps.includes('tools') ? 1 : 0);
      return {
        id: n, name: n, alias: meta.alias, backend: 'foundry', installed: true, loaded: loaded.has(n),
        sizeBytes: meta.fileSizeMb ? meta.fileSizeMb * 1048576 : null, device: meta.runtime?.deviceType, capabilities: caps,
      };
    });
  }

  async loadedNames() {
    const ep = await this.endpoint();
    if (!ep) return [];
    const r = await fetchWithTimeout(`${ep}/openai/loadedmodels`, {}, 5000);
    if (!r.ok) return [];
    return await r.json();
  }
  async loaded() { return (await this.loadedNames()).map((name) => ({ name })); }

  /** Download via REST with streamed progress; falls back to the CLI. */
  async pull(name, onProgress, signal) {
    const ep = await this.endpoint();
    if (!ep) throw new Error('Foundry Local service is not running');
    const cat = this._catalog || await this.catalogRaw();
    const m = cat.find((c) => c.name === name || c.alias === name);
    if (!m) {
      // Alias not in catalog JSON: let the CLI resolve it (it picks the best variant for this hardware).
      return this.pullViaCli(name, onProgress, signal);
    }
    const body = {
      model: { Uri: m.uri, Name: m.version ? `${m.name}:${m.version}` : m.name, ProviderType: m.providerType, Publisher: m.publisher || '', PromptTemplate: m.promptTemplate || undefined },
      ignorePipeReport: true,
    };
    const r = await fetch(`${ep}/openai/download`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal });
    if (!r.ok) throw new Error(`Download failed (${r.status})`);
    let result = null;
    for await (const line of readLines(r.body, signal)) {
      const pm = line.match(/\(\s*"([^"]*)"\s*,\s*([\d.]+)\s*\)/);
      if (pm) { onProgress?.({ status: pm[1] || 'downloading', completed: Math.round(parseFloat(pm[2]) * 1000), total: 1000 }); continue; }
      const jm = line.match(/\{.*"Success".*\}/i);
      if (jm) { try { result = JSON.parse(jm[0]); } catch { /* ignore */ } }
    }
    if (result && result.Success === false) throw new Error(result.ErrorMessage || 'Download failed');
    onProgress?.({ status: 'success', completed: 1000, total: 1000 });
    return true;
  }

  pullViaCli(alias, onProgress, signal) {
    return new Promise((resolve, reject) => {
      const p = spawn(this.cli(), ['model', 'download', alias], { windowsHide: true });
      signal?.addEventListener('abort', () => p.kill(), { once: true });
      const onData = (d) => {
        const s = String(d);
        const m = s.match(/(\d{1,3}(?:\.\d+)?)\s*%/g);
        if (m) onProgress?.({ status: 'downloading', completed: Math.round(parseFloat(m[m.length - 1]) * 10), total: 1000 });
      };
      p.stdout.on('data', onData); p.stderr.on('data', onData);
      p.on('error', reject);
      p.on('close', (code) => (code === 0 ? resolve(true) : reject(new Error(`foundry model download exited with ${code}`))));
    });
  }

  async load(name) {
    const ep = await this.endpoint();
    const r = await fetchWithTimeout(`${ep}/openai/load/${encodeURIComponent(name)}?ttl=1800`, {}, 600000);
    if (!r.ok) throw new Error(`Load failed (${r.status})`);
  }
  async unload(name) {
    const ep = await this.endpoint();
    await fetchWithTimeout(`${ep}/openai/unload/${encodeURIComponent(name)}?force=true`, {}, 60000);
  }
  async remove(name) {
    const r = await runCli(this.cli(), ['cache', 'remove', name, '--yes'], 60000);
    if (!r.ok) throw new Error(`Remove failed: ${(r.stderr || r.stdout).slice(0, 200)}`);
  }
  async embed() { throw new Error('Foundry Local does not provide an embeddings endpoint; select an Ollama embeddings model.'); }
}

module.exports = { FoundryBackend, parseEndpoint };
