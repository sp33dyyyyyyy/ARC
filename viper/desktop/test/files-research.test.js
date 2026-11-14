'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { fakeLLM, startViper, waitFor } = require('./helpers/env');
const { extractText } = require('../src/server/files/extract');
const { validateCitations } = require('../src/server/research');

const FIX = path.join(__dirname, 'fixtures');

test('document extraction (PDF, Word, Excel, CSV, Markdown)', async () => {
  assert.match((await extractText('sample.pdf', fs.readFileSync(path.join(FIX, 'sample.pdf')))).text, /reactor runs at 3 gigawatts/);
  assert.match((await extractText('sample.docx', fs.readFileSync(path.join(FIX, 'sample.docx')))).text, /launch date is 14 March/);
  const x = await extractText('sample.xlsx', fs.readFileSync(path.join(FIX, 'sample.xlsx')));
  assert.equal(x.meta.sheets[0].numeric.find((n) => n.column === 'qty').sum, 35);
  assert.match((await extractText('data.csv', fs.readFileSync(path.join(FIX, 'data.csv')))).text, /Feb,150,55/);
  await assert.rejects(extractText('x.exe', Buffer.from('MZ')), /Unsupported/);
});

test('file intelligence index, hybrid search and cited Q&A; research labelling', async (t) => {
  const llm = await fakeLLM(async (msgs) => {
    const u = msgs[msgs.length - 1].content;
    if (/Question:/.test(u)) return { content: 'The launch is on 14 March [1]. Budget is 42,000 [9].' };
    if (/Research question/.test(u)) return { content: 'Some general knowledge answer [2].' };
    return { content: 'Summary.' };
  });
  const svc = await startViper('files');
  t.after(async () => { await svc.shutdown(); await llm.close(); });
  svc.settings.set('backend', { active: 'openai', openai: { url: llm.url } });
  svc.settings.set('models', { embeddings: { backend: 'openai', model: 'fake-embed' } });
  const docs = path.join(svc.dataDir, 'docs'); fs.mkdirSync(docs);
  for (const f of fs.readdirSync(FIX)) fs.copyFileSync(path.join(FIX, f), path.join(docs, f));
  svc.settings.set('privacy', { allowedFolders: [docs] });
  await svc.models.checkHealth();

  await t.test('indexing a folder with embeddings', async () => {
    const done = waitFor(svc, (e) => e.type === 'files.indexed', 30000);
    const r = await svc.files.index(docs);
    assert.ok(r.files >= 5);
    const ev = await done; assert.equal(ev.data.errors, 0);
    assert.ok(svc.files.list().every((d) => d.embedded === 1));
  });
  await t.test('hybrid search finds the right document', async () => {
    const r = await svc.files.search('database migration PostgreSQL');
    assert.equal(r.semantic, true); assert.equal(r.results[0].name, 'notes.md');
  });
  await t.test('Q&A cites sources; citations pointing to nothing are removed by research', async () => {
    const a = await svc.files.ask('When is the Falcon launch?');
    assert.ok(a.sources.length >= 1); assert.match(a.answer, /\[1\]/);
    assert.deepEqual(validateCitations('A [1] B [9]', 2), { text: 'A [1] B ', invalid: 1 });
  });
  await t.test('reading outside allowed folders is refused', async () => {
    await assert.rejects(svc.files.extractPath('/etc/hostname'), /outside your allowed folders/);
  });
  await t.test('research with web access off is labelled as offline knowledge and has no fake citations', async () => {
    svc.settings.set('privacy', { webAccess: false });
    const r = await svc.research.run({ query: 'history of the transistor', local: false });
    assert.equal(r.mode, 'offline'); assert.equal(r.sources.length, 0);
    assert.match(r.report, /Offline answer from model knowledge/);
    assert.ok(!/\[2\]/.test(r.report), 'invalid citation removed');
    assert.ok(r.notes.some((n) => /Web access is turned off/.test(n)));
  });
});
