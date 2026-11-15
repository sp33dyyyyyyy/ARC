import { h, clear, icon, btn, toast, toastError, toggle } from '../ui.js';

// INTELLIGENCE → Agent Permissions: what VIPER's assistant and Code Agent may do on their own,
// what needs your approval and what is never allowed.
export async function render(view, { app, api }) {
  const body = h('div');
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, 'Agent Permissions'), h('div.sub', {}, 'Control what VIPER can do without asking. Destructive actions always ask.')),
    h('div.actions', {}, btn('Allowed folders & scripts', () => app.go('settings', { tab: 'security' }), { cls: 'sm ghost', ico: 'shield' }))), body);
  const save = async (section, patch) => { try { app.settings[section] = await api.patch(`/settings/${section}`, patch); } catch (e) { toastError(e); } };
  async function draw() {
    const info = await api.get('/permissions/info').catch(() => ({}));
    const perms = app.settings.permissions; const ag = app.settings.agent || {};
    const row = (label, desc, control) => h('div.li', {}, h('div.t', {}, h('b', {}, label), desc ? h('small', { style: { whiteSpace: 'normal' } }, desc) : null), control);
    clear(body).append(h('div.grid.g2', {},
      h('div.panel', { style: { gridColumn: '1 / -1' } }, h('h3', {}, icon('shield'), 'Assistant actions'), h('p.small.mist', {}, 'Ask shows a confirmation for each action. Anything that follows web, email or document content is confirmed regardless of these settings.'),
        h('div.list', {}, Object.entries(info).map(([cat, desc]) => row(cat, desc, h('div.seg', {}, ...['allow', 'ask', 'deny'].map((m) => h(`button${perms[cat] === m ? '.on' : ''}`, { type: 'button', onclick: async () => { await save('permissions', { [cat]: m }); draw(); } }, m === 'allow' ? 'Allow' : m === 'ask' ? 'Ask' : 'Deny'))))))),
      h('div.panel', {}, h('h3', {}, icon('code'), 'Code Agent'), h('div.list', {},
        row('Build, test and compiler commands inside the project', 'python, node, dotnet, cargo, javac, godot… — run without asking, with a timeout.', h('span.tag', {}, 'Allowed')),
        row('Install packages from the internet', 'pip, npm, dotnet add, cargo add…', toggle(!!ag.allowInstall, (v) => save('agent', { allowInstall: v }), 'Install packages without asking')),
        row('Programs not on the allow-list, paths outside the project, git history changes', 'Shown to you with the exact command first.', h('span.tag', {}, 'Ask')),
        row('Privilege escalation, disk and system tools, registry, shutdown, deleting files, downloading with curl/wget/PowerShell', 'Never run by the Code Agent.', h('span.tag', {}, 'Never')),
        row('Git checkpoints before and after each change', 'Every change can be rolled back from the Code Agent’s History tab.', toggle(ag.gitCheckpoints !== false, (v) => save('agent', { gitCheckpoints: v }), 'Git checkpoints')))),
      h('div.panel', {}, h('h3', {}, icon('phone'), 'From your phone'), h('div.list', {},
        row('Approvals from the phone', 'Only phones with the “Approve actions” permission, after a review screen, and never pairing requests. Dismissing a notification is never an approval.', btn('Device permissions', () => app.go('devices'), { cls: 'sm' })),
        row('Unanswered approvals go to the phone after', 'An approval waiting on this PC is offered to your phone so work does not stall while you are away.', h('span.tag', {}, '20 seconds'))))));
  }
  await draw();
}
