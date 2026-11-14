'use strict';
// Research: live web research (explicit opt-in), local document research,
// cited reports, fact checking and comparison tables. Citations can only
// reference sources that were actually fetched; invalid markers are removed.
const fs = require('node:fs');
const path = require('node:path');
const { uid, now, fetchWithTimeout, jsonParse } = require('./util');
const { htmlToText } = require('./files/extract');
const { wrapUntrusted } = require('./orchestrator');
const { HttpError } = require('./http');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 VIPER-Research';

function decodeEntities(s) { return String(s).replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#x27;|&#39;/g, "'").replace(/<[^>]+>/g, ''); }

async function ddgSearch(query, limit = 8) {
  const r = await fetchWithTimeout(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, { headers: { 'User-Agent': UA, Accept: 'text/html' } }, 15000);
  if (!r.ok && r.status !== 202) throw new Error(`Search failed (${r.status})`);
  const html = await r.text();
  const out = [];
  const re = /<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?(?:<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>)?/g;
  let m;
  while ((m = re.exec(html)) && out.length < limit) {
    let url = decodeEntities(m[1]);
    const u = url.match(/[?&]uddg=([^&]+)/); if (u) url = decodeURIComponent(u[1]);
    if (url.startsWith('//')) url = `https:${url}`;
    if (!/^https?:\/\//.test(url) || /duckduckgo\.com\/y\.js|\/\/duckduckgo\.com\/l\//.test(url)) continue;
    out.push({ url, title: decodeEntities(m[2]).trim(), snippet: decodeEntities(m[3] || '').trim() });
  }
  return out;
}

function isPrivateIp(ip) {
  const v = ip.replace(/^::ffff:/, '');
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)/.test(v) || /^172\.(1[6-9]|2\d|3[01])\./.test(v)) return true;
  return v === '::1' || v === '::' || /^f[cd]/i.test(v) || /^fe80/i.test(v);
}
/** Refuse loopback/LAN/link-local targets, including hostnames that resolve to them. */
async function assertPublicUrl(u) {
  if (!['http:', 'https:'].includes(u.protocol)) throw new Error('Only http(s) URLs');
  const host = u.hostname.replace(/^\[|\]$/g, '');
  if (/^localhost$/i.test(host) || host.endsWith('.local') || host.endsWith('.internal')) throw new Error('Refusing to fetch a private-network address');
  const addrs = await require('node:dns').promises.lookup(host, { all: true }).catch(() => []);
  if (!addrs.length) throw new Error(`Cannot resolve ${host}`);
  if (addrs.some((a) => isPrivateIp(a.address))) throw new Error('Refusing to fetch a private-network address');
}

async function fetchPage(url) {
  let u = new URL(url);
  let r;
  // Follow redirects manually so every hop is checked (a public page must not bounce us to the LAN).
  for (let hop = 0; ; hop++) {
    await assertPublicUrl(u);
    r = await fetchWithTimeout(u.toString(), { headers: { 'User-Agent': UA, Accept: 'text/html,text/plain,application/xhtml+xml' }, redirect: 'manual' }, 15000);
    if (r.status >= 300 && r.status < 400 && r.headers.get('location')) {
      if (hop >= 5) throw new Error('Too many redirects');
      u = new URL(r.headers.get('location'), u);
      continue;
    }
    break;
  }
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const ct = r.headers.get('content-type') || '';
  if (!/text\/|html|xml|json/.test(ct)) throw new Error(`Unsupported content type ${ct}`);
  const raw = (await r.text()).slice(0, 2_000_000);
  const title = (raw.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1]?.trim();
  const main = raw.match(/<(article|main)[^>]*>([\s\S]*?)<\/\1>/i);
  const text = /html/.test(ct) ? htmlToText(main && main[2].length > 1500 ? main[2] : raw) : raw;
  return { url: u.toString(), title: decodeEntities(title || u.hostname), text: text.slice(0, 60000), fetchedAt: now() };
}

function relevantPassages(text, query, max = 2400) {
  const terms = query.toLowerCase().split(/\W+/).filter((t) => t.length > 3);
  const paras = text.split(/\n+/).map((p) => p.trim()).filter((p) => p.length > 60);
  const scored = paras.map((p, i) => ({ p, i, s: terms.reduce((a, t) => a + (p.toLowerCase().includes(t) ? 1 : 0), 0) + (i < 3 ? 0.5 : 0) }));
  scored.sort((a, b) => b.s - a.s);
  const pick = []; let len = 0;
  for (const x of scored) { if (len + x.p.length > max) continue; pick.push(x); len += x.p.length; }
  return pick.sort((a, b) => a.i - b.i).map((x) => x.p).join('\n');
}

function validateCitations(text, n) {
  let invalid = 0;
  const cleaned = text.replace(/\[(\d+(?:\s*,\s*\d+)*)\]/g, (m, inner) => {
    const nums = inner.split(',').map((x) => parseInt(x.trim(), 10)).filter((x) => x >= 1 && x <= n);
    if (!nums.length) { invalid++; return ''; }
    return `[${nums.join(', ')}]`;
  });
  return { text: cleaned, invalid };
}

class Research {
  constructor(svc) { this.svc = svc; this.db = svc.db; this.log = svc.logger.scope('research'); }
  webAllowed() { return !!this.svc.settings.get('privacy').webAccess; }

  async run({ query, web = true, local = true, format = 'report', actor = 'user', requestId }) {
    if (!query?.trim()) throw new HttpError(400, 'Query required');
    const id = uid('rs_');
    const taskId = `research:${id}`;
    const pub = (label, progress) => this.svc.bus.publish('task.update', { id: taskId, label, kind: 'research', state: 'running', progress });
    const useWeb = web && this.webAllowed();
    const sources = [];
    const notes = [];
    try {
      if (web && !useWeb) notes.push('Web access is turned off (Settings → Privacy), so no live internet sources were used.');
      if (useWeb) {
        pub('Searching the web', 0.1);
        const ok = await this.svc.permissions.check({ tool: { name: 'web_research', category: 'web.access', risk: 'read', label: 'Web research' }, args: { query }, ctx: { actor, origin: actor === 'automation' ? 'automation' : 'desktop', noInteractive: actor === 'automation' } });
        if (!ok.allowed) { notes.push(`Web research not permitted: ${ok.reason}`); }
        else {
          let results = [];
          try { results = await ddgSearch(query, 8); } catch (e) { notes.push(`Web search failed: ${e.message}`); }
          const max = this.svc.settings.get('research').maxSources || 5;
          let i = 0;
          for (const res of results) {
            if (sources.length >= max) break;
            pub(`Reading ${new URL(res.url).hostname}`, 0.2 + 0.5 * (++i / Math.min(results.length, max + 2)));
            try {
              const page = await fetchPage(res.url);
              if (page.text.length < 300) continue;
              sources.push({ kind: 'web', title: page.title || res.title, url: page.url, fetchedAt: page.fetchedAt, excerpt: relevantPassages(page.text, query), full: page.text });
            } catch (e) { this.log.debug('fetch failed', res.url, e.message); }
          }
          if (!sources.length && results.length) notes.push('Search returned results but none of the pages could be read.');
        }
      }
      if (local && this.svc.files) {
        pub('Searching local documents', 0.75);
        const r = await this.svc.files.search(query, { limit: 4 }).catch(() => ({ results: [] }));
        for (const c of r.results.filter((x) => x.score > 0.2)) sources.push({ kind: 'local', title: c.name, path: c.path, excerpt: c.text });
      }
      pub('Writing the report', 0.85);
      const instr = {
        report: 'Write a well-structured research report in Markdown: a short summary, key findings with [n] citations, and open questions.',
        table: 'Produce a Markdown comparison table of the options discussed, with a short conclusion. Cite sources with [n].',
        factcheck: 'Fact-check the claim. Give a verdict (Supported / Contradicted / Unclear) and explain with [n] citations.',
        brief: 'Answer briefly in 3-5 sentences with [n] citations.',
      }[format] || '';
      const sourceBlock = sources.map((s, i) => wrapUntrusted(`[${i + 1}] ${s.title}${s.url ? ` — ${s.url}` : ` — local file ${s.path}`}`, s.excerpt)).join('\n\n');
      const sys = `${this.svc.orchestrator.systemPrompt({ mode: 'research' })}\n${sources.length ? 'Use ONLY the numbered sources for factual claims and cite them as [n]. Never cite a number that is not listed. If sources disagree, say so.' : 'NO SOURCES ARE AVAILABLE. Begin your answer with: "Offline answer from model knowledge — not verified against live sources." Do not include citations or URLs.'}`;
      const r = await this.svc.models.complete({ role: 'chat', requestId, label: 'Research', messages: [{ role: 'system', content: sys }, { role: 'user', content: `${sourceBlock}\n\n${format === 'factcheck' ? 'Claim' : 'Research question'}: ${query}\n\n${instr}` }], options: { temperature: 0.3, maxTokens: 1400 } });
      let report = r.text.trim();
      const v = validateCitations(report, sources.length);
      report = v.text;
      if (v.invalid) notes.push(`${v.invalid} citation marker(s) that did not match a real source were removed.`);
      if (!sources.length && !/^offline answer/i.test(report)) report = `**Offline answer from model knowledge — not verified against live sources.**\n\n${report}`;
      const title = query.length > 70 ? `${query.slice(0, 67)}…` : query;
      const mode = sources.some((s) => s.kind === 'web') ? 'web' : sources.length ? 'local' : 'offline';
      const stored = sources.map(({ full, ...s }) => s);
      this.db.run('INSERT INTO research (id, title, query, mode, report, sources, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', id, title, query, mode, report, JSON.stringify({ sources: stored, notes, format }), 'done', now());
      // keep downloaded references for offline reading
      for (const s of sources.filter((x) => x.kind === 'web')) {
        try { fs.writeFileSync(path.join(this.svc.paths.research, `${id}-${sources.indexOf(s) + 1}.txt`), `${s.title}\n${s.url}\nFetched ${new Date(s.fetchedAt).toISOString()}\n\n${s.full}`); } catch { /* disk */ }
      }
      this.svc.bus.publish('task.update', { id: taskId, label: `Research: ${title}`, kind: 'research', state: 'done' });
      return { id, title, mode, report, sources: stored, notes };
    } catch (e) {
      this.svc.bus.publish('task.update', { id: taskId, label: 'Research', kind: 'research', state: 'failed', error: e.message });
      throw e;
    }
  }
  list() { return this.db.all('SELECT id, title, query, mode, created_at FROM research ORDER BY created_at DESC LIMIT 200'); }
  get(id) { const r = this.db.get('SELECT * FROM research WHERE id = ?', id); if (!r) return null; const x = jsonParse(r.sources, {}); return { ...r, sources: x.sources || [], notes: x.notes || [], format: x.format }; }
  delete(id) { this.db.run('DELETE FROM research WHERE id = ?', id); for (const f of fs.readdirSync(this.svc.paths.research)) if (f.startsWith(id)) fs.rmSync(path.join(this.svc.paths.research, f), { force: true }); }
  references() {
    return fs.readdirSync(this.svc.paths.research).filter((f) => f.endsWith('.txt')).map((f) => { const head = fs.readFileSync(path.join(this.svc.paths.research, f), 'utf8').split('\n', 3); return { file: f, title: head[0], url: head[1], fetched: head[2] }; });
  }
  exportMarkdown(id) {
    const r = this.get(id); if (!r) throw new HttpError(404, 'Not found');
    return `# ${r.title}\n\n_${r.mode === 'web' ? 'Live web research' : r.mode === 'local' ? 'Local document research' : 'Offline model knowledge'} · ${new Date(r.created_at).toLocaleString()}_\n\n${r.report}\n\n## Sources\n\n${r.sources.map((s, i) => `${i + 1}. ${s.title} — ${s.url || s.path}${s.fetchedAt ? ` (retrieved ${new Date(s.fetchedAt).toLocaleDateString()})` : ''}`).join('\n') || 'None — offline answer.'}\n${r.notes.length ? `\n## Notes\n\n${r.notes.map((n) => `- ${n}`).join('\n')}\n` : ''}`;
  }
}

module.exports = {
  name: 'research',
  init: (svc) => {
    const rs = new Research(svc);
    svc.tools.register({
      name: 'web_search', label: 'Web search', category: 'web.access', risk: 'read', keywords: ['search the web', 'look up', 'google', 'latest', 'news', 'online', 'internet', 'current'],
      description: 'Search the live web (only when the user enabled Web Access). Returns titles, URLs and snippets.',
      parameters: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] },
      handler: async ({ query }) => { if (!rs.webAllowed()) return { ok: false, error: 'Web access is turned off in Settings → Privacy.' }; return { ok: true, result: await ddgSearch(query, 6), untrusted: true }; },
    });
    svc.tools.register({
      name: 'fetch_page', label: 'Read web page', category: 'web.access', risk: 'read', keywords: ['http', 'www', 'website', 'page', 'article'],
      description: 'Download a web page and return its readable text (only when Web Access is enabled).',
      parameters: { type: 'object', properties: { url: { type: 'string' } }, required: ['url'] },
      handler: async ({ url }) => { if (!rs.webAllowed()) return { ok: false, error: 'Web access is turned off in Settings → Privacy.' }; const p = await fetchPage(url); return { ok: true, result: { title: p.title, url: p.url, text: p.text.slice(0, 12000) }, untrusted: true }; },
    });
    return rs;
  },
  routes(r, svc) {
    const P = '/api/v1/research';
    r.post(`${P}`, async ({ body }) => svc.research.run({ query: body.query, web: body.web !== false, local: body.local !== false, format: body.format }), { scope: 'research' });
    r.get(`${P}`, async () => svc.research.list(), { scope: 'research' });
    r.get(`${P}/references`, async () => svc.research.references());
    r.get(`${P}/:id`, async ({ params }) => svc.research.get(params.id) || (() => { throw new HttpError(404, 'Not found'); })(), { scope: 'research' });
    r.get(`${P}/:id/export`, async ({ params }) => ({ __raw: Buffer.from(svc.research.exportMarkdown(params.id)), type: 'text/markdown', filename: 'viper-research.md' }));
    r.delete(`${P}/:id`, async ({ params }) => svc.research.delete(params.id));
  },
  ddgSearch, fetchPage, validateCitations, relevantPassages, isPrivateIp, assertPublicUrl,
};
