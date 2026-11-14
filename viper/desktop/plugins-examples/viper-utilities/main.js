// VIPER Utilities — runs inside VIPER's QuickJS sandbox. Only `viper.*` host APIs are available.
const FACTORS = { km: ['mi', 0.621371], mi: ['km', 1.609344], kg: ['lb', 2.204623], lb: ['kg', 0.453592], m: ['ft', 3.28084], ft: ['m', 0.3048], l: ['gal', 0.264172], gal: ['l', 3.785412] };
const ALIASES = { miles: 'mi', mile: 'mi', kilometres: 'km', kilometers: 'km', kilograms: 'kg', pounds: 'lb', lbs: 'lb', metres: 'm', meters: 'm', feet: 'ft', foot: 'ft', litres: 'l', liters: 'l', gallons: 'gal', c: 'celsius', f: 'fahrenheit' };
const norm = (u) => { const s = String(u).toLowerCase().trim(); return ALIASES[s] || s; };

plugin.tools.convert_units = async ({ value, from, to }) => {
  const a = norm(from); const b = norm(to);
  if (a === 'celsius' && b === 'fahrenheit') return { result: value * 9 / 5 + 32, unit: '°F' };
  if (a === 'fahrenheit' && b === 'celsius') return { result: (value - 32) * 5 / 9, unit: '°C' };
  const f = FACTORS[a];
  if (!f || f[0] !== b) throw new Error(`Cannot convert ${from} to ${to}`);
  return { result: Math.round(value * f[1] * 10000) / 10000, unit: b };
};

plugin.tools.roll_dice = async ({ notation }) => {
  const m = String(notation).replace(/\s+/g, '').match(/^(\d{0,3})d(\d{1,4})([+-]\d+)?$/i);
  if (!m) throw new Error('Use notation like 2d6 or 1d20+3');
  const n = Math.min(100, parseInt(m[1] || '1', 10)); const sides = parseInt(m[2], 10); const mod = parseInt(m[3] || '0', 10);
  const rolls = Array.from({ length: n }, () => 1 + Math.floor(Math.random() * sides));
  return { rolls, modifier: mod, total: rolls.reduce((a, b) => a + b, 0) + mod };
};

plugin.widgets.clocks = async () => {
  const zones = [['London', 0], ['New York', -5], ['Tokyo', 9], ['Sydney', 11]];
  const now = Date.now();
  return { title: 'World clock (standard time)', lines: zones.map(([city, off]) => { const d = new Date(now + off * 3600000); return `${city}: ${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`; }) };
};

plugin.pages.scratchpad = async (input) => {
  const notes = (await viper.storage.get('notes')) || [];
  if (input && input.text) { notes.unshift({ text: String(input.text).slice(0, 500), at: new Date().toISOString() }); await viper.storage.set('notes', notes.slice(0, 50)); }
  if (input && input.clear) { await viper.storage.set('notes', []); return { markdown: '_Scratchpad cleared._', input: { placeholder: 'Write a note…' } }; }
  return { markdown: notes.length ? notes.map((n) => `- ${n.text}  \n  _${n.at.slice(0, 16).replace('T', ' ')}_`).join('\n') : '_No notes yet._', input: { placeholder: 'Write a note…' }, actions: [{ label: 'Clear all', payload: { clear: true } }] };
};

plugin.actions.log_note = async (args) => { const notes = (await viper.storage.get('notes')) || []; notes.unshift({ text: String(args.text || 'Automation ran'), at: new Date().toISOString() }); await viper.storage.set('notes', notes.slice(0, 50)); return { ok: true }; };
