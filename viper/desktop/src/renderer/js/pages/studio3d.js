import { h, icon, btn, busy, toast, toastError, select, field } from '../ui.js';
import { startAgentProject } from './builder.js';

// MAKE → 3D Studio: describe a 3D object or scene and the Code Agent builds it as code you can
// open and edit — an interactive WebGL scene (plain JavaScript, no downloads) or an OpenSCAD
// model for 3D printing when OpenSCAD is installed.
export async function render(view, { app, api }) {
  const kind = select([['scene', 'Interactive 3D scene (WebGL, opens in a browser)'], ['scad', 'Printable model (OpenSCAD .scad)']], 'scene', () => {});
  const name = h('input.input', { placeholder: 'e.g. Solar system' });
  const desc = h('textarea.input', { rows: 5, placeholder: 'Describe the object or scene: shapes, sizes, colours, animation, camera controls…' });
  view.append(h('div.view-head', {}, h('div', {}, h('h1', {}, '3D Studio'), h('div.sub', {}, 'Generated as real, editable code by the Code Agent.'))),
    h('div.panel', { style: { maxWidth: '760px' } }, h('h3', {}, icon('cube'), 'New 3D project'), h('div.col', {}, field('Output', kind), field('Name', name), desc,
      h('div.row', {}, btn('Create', async (e) => busy(e.currentTarget, async () => {
        if (!desc.value.trim()) return toast('Describe the object first', '', 'warn');
        const d = desc.value.trim();
        const request = kind.value === 'scad'
          ? `Create an OpenSCAD model (model.scad) for 3D printing: ${d}. Use named parameters at the top for the key dimensions in millimetres. Add a check script check.py (Python, standard library only) that verifies the .scad file exists, defines the parameters and has balanced braces; use "python check.py" as the test command. If the openscad command is available, the build command is "openscad -o model.stl model.scad".`
          : `Create an interactive 3D scene that runs in a web browser with plain WebGL and JavaScript (no libraries, no CDN, no build step): ${d}. Files: index.html, scene.js, math3d.js (matrix/vector helpers). Add mouse-drag orbit and wheel zoom. Write unit tests for math3d.js with node:test (math3d.test.js) and use "node --test" as the test command.`;
        try { await startAgentProject(api, app, name.value.trim() || '3D project', request); } catch (err) { toastError(err); }
      }), { cls: 'primary', ico: 'play' })),
      h('p.small.mist', {}, 'The agent writes the files, runs the checks and reports honestly. A WebGL scene opens in any browser by double-clicking index.html; an STL is produced only if OpenSCAD is installed.'))));
}
