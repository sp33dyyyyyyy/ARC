import { h, clear, icon, btn, busy, toast, toastError, field } from '../ui.js';

// MAKE → Project Builder: start a Code Agent project from a template. Each template is a real
// request the agent plans, writes, builds and tests — progress is shown in the Code Agent.
export const TEMPLATES = [
  { id: 'desktop', title: 'Windows desktop app', ico: 'screen', needs: 'python', stack: 'Python + tkinter', request: (d) => `Create a Windows desktop application with Python and tkinter: ${d}. Keep the logic in a separate module with unit tests (unittest), and a main.py that opens the window.` },
  { id: 'web', title: 'Web app', ico: 'grid', needs: 'node', stack: 'HTML, CSS and JavaScript', request: (d) => `Create a single-page web app (index.html, styles.css, app.js, no build step and no external CDN): ${d}. Put the logic in a module that can be unit-tested with node:test, and add a test file.` },
  { id: 'cli', title: 'Command-line tool', ico: 'terminal', needs: 'python', stack: 'Python', request: (d) => `Create a Python command-line tool using argparse: ${d}. Include unit tests (unittest) and a README with usage.` },
  { id: 'api', title: 'Local REST API', ico: 'link', needs: 'node', stack: 'Node.js (no dependencies)', request: (d) => `Create a small REST API in Node.js using only the built-in http module (no npm packages): ${d}. Include tests with node:test that start the server on a random port.` },
  { id: 'game', title: '2D game', ico: 'play', needs: 'python', stack: 'Python + tkinter canvas', request: (d) => `Create a simple 2D game with Python and the tkinter canvas (no extra packages): ${d}. Keep game rules in a separate module with unit tests.` },
  { id: 'dotnet', title: '.NET console app', ico: 'code', needs: 'dotnet', stack: 'C# / .NET', request: (d) => `Create a .NET console application in C#: ${d}. Include an xUnit test project only if the dotnet templates are available offline; otherwise put self-checks behind a --test flag.` },
];

export async function startAgentProject(api, app, name, request) {
  const p = await api.post('/agent/projects', { name });
  const r = await api.post(`/agent/projects/${p.id}/runs`, { request });
  toast(r.status === 'queued' ? 'Project queued' : 'Project started', `${name} — follow it in the Code Agent.`);
  app.go('agent', { project: p.id, run: r.id });
}

export async function render(view, { app, api }) {
  const tc = await api.get('/agent/toolchains').catch(() => ({}));
  const grid = h('div.grid.g3');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Project Builder'), h('div.sub', {}, 'Pick a starting point, describe it, and the Code Agent builds it — then runs the build and tests to prove it works.')),
    h('div.actions', {}, btn('Open Code Agent', () => app.go('agent'), { cls: 'sm ghost', ico: 'code' }))), grid);
  for (const t of TEMPLATES) {
    const name = h('input.input', { placeholder: 'Project name', value: '' });
    const desc = h('textarea.input', { rows: 3, placeholder: 'Describe what it should do' });
    const ok = !!tc[t.needs];
    grid.append(h('div.panel.tpl', {}, h('h3', {}, icon(t.ico), t.title), h('small.mist', {}, t.stack),
      ok ? null : h('p.small', {}, `${t.needs === 'dotnet' ? '.NET SDK' : t.needs === 'python' ? 'Python 3' : t.needs} was not found on this PC — the agent can write the code but cannot build or test it, so it will not report success.`),
      h('div.col', { style: { marginTop: '8px' } }, field('Name', name), desc,
        btn('Build it', async (e) => busy(e.currentTarget, async () => {
          if (!desc.value.trim()) return toast('Describe the project first', '', 'warn');
          try { await startAgentProject(api, app, name.value.trim() || t.title, t.request(desc.value.trim())); } catch (err) { toastError(err); }
        }), { cls: ok ? 'primary' : '', ico: 'play' }))));
  }
}
