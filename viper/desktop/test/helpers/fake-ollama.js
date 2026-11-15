// A small stand-in for `ollama serve` used by the AI start-up tests: a real process with a real
// HTTP server speaking the parts of Ollama's API that VIPER uses. Configured by environment:
//   OLLAMA_HOST    host:port to listen on (as with Ollama)
//   FAKE_MODELS    comma-separated installed models (default qwen2.5:3b)
//   FAKE_EXIT      exit immediately with this code (simulates a broken install)
//   FAKE_DELAY_MS  delay before the server starts listening (simulates a slow start)
'use strict';
const http = require('node:http');
if (process.env.FAKE_EXIT) { console.error('fake engine: failed to start'); process.exit(Number(process.env.FAKE_EXIT)); }
const [host, port] = (process.env.OLLAMA_HOST || '127.0.0.1:11434').split(':');
const models = (process.env.FAKE_MODELS ?? 'qwen2.5:3b').split(',').filter(Boolean);
const loaded = new Set();
const server = http.createServer(async (req, res) => {
  let body = ''; for await (const c of req) body += c;
  const j = body ? JSON.parse(body) : {};
  const json = (o) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); };
  if (req.url === '/api/version') return json({ version: 'fake-0.1' });
  if (req.url === '/api/tags') return json({ models: models.map((m) => ({ name: m, size: 2e9, details: { family: 'qwen', parameter_size: '3B', quantization_level: 'Q4_K_M' } })) });
  if (req.url === '/api/show') return json({ capabilities: ['completion', 'tools'] });
  if (req.url === '/api/ps') return json({ models: [...loaded].map((m) => ({ name: m, size: 2e9, size_vram: 0 })) });
  if (req.url === '/api/generate') { if (j.keep_alive === 0) loaded.delete(j.model); else loaded.add(j.model); return json({ done: true }); }
  if (req.url === '/api/chat') {
    if (!models.includes(j.model)) { res.writeHead(404); return res.end(JSON.stringify({ error: `model "${j.model}" not found` })); }
    loaded.add(j.model);
    res.writeHead(200, { 'Content-Type': 'application/x-ndjson' });
    const last = j.messages[j.messages.length - 1]?.content || '';
    const words = /ready/i.test(last) && j.options?.num_predict <= 8 ? ['Ready'] : `Hello! VIPER here, answering: ${last.slice(-40)}`.split(' ');
    for (const w of words) { res.write(`${JSON.stringify({ message: { role: 'assistant', content: `${w} ` }, done: false })}\n`); await new Promise((r) => setTimeout(r, 5)); }
    res.end(`${JSON.stringify({ message: { role: 'assistant', content: '' }, done: true, eval_count: words.length, eval_duration: 1e8, prompt_eval_count: 10 })}\n`);
    return;
  }
  res.writeHead(404); res.end();
});
setTimeout(() => server.listen(Number(port), host), Number(process.env.FAKE_DELAY_MS || 0));
process.on('SIGTERM', () => process.exit(0));
