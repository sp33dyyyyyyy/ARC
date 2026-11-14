'use strict';
// Tool registry. A tool = { name, label, description, category, risk, parameters, handler }.
//   risk: 'read' (no side effects) | 'write' (changes state) | 'destructive' (always confirmed)
// Tools run only through ToolRegistry.execute(), which validates arguments
// against the declared schema and enforces the permission engine.

function validate(schema, args) {
  const errors = [];
  if (!schema || schema.type !== 'object') return { ok: true, value: args || {} };
  const value = {};
  const input = args && typeof args === 'object' ? args : {};
  for (const req of schema.required || []) {
    if (input[req] === undefined || input[req] === null || input[req] === '') errors.push(`Missing required argument "${req}"`);
  }
  for (const [k, spec] of Object.entries(schema.properties || {})) {
    let v = input[k];
    if (v === undefined) { if (spec.default !== undefined) value[k] = spec.default; continue; }
    if (spec.type === 'number' || spec.type === 'integer') {
      v = Number(v);
      if (Number.isNaN(v)) { errors.push(`"${k}" must be a number`); continue; }
      if (spec.minimum !== undefined && v < spec.minimum) v = spec.minimum;
      if (spec.maximum !== undefined && v > spec.maximum) v = spec.maximum;
      if (spec.type === 'integer') v = Math.round(v);
    } else if (spec.type === 'boolean') {
      v = v === true || v === 'true' || v === 1;
    } else if (spec.type === 'string') {
      if (typeof v !== 'string') v = String(v);
      if (spec.enum && !spec.enum.includes(v)) { errors.push(`"${k}" must be one of: ${spec.enum.join(', ')}`); continue; }
      if (v.length > (spec.maxLength || 20000)) v = v.slice(0, spec.maxLength || 20000);
    } else if (spec.type === 'array') {
      if (!Array.isArray(v)) v = typeof v === 'string' ? v.split(',').map((s) => s.trim()).filter(Boolean) : [v];
    } else if (spec.type === 'object') {
      if (typeof v === 'string') { try { v = JSON.parse(v); } catch { errors.push(`"${k}" must be an object`); continue; } }
    }
    value[k] = v;
  }
  return errors.length ? { ok: false, errors } : { ok: true, value };
}

class ToolRegistry {
  constructor({ permissions, bus, log }) {
    this.tools = new Map(); this.permissions = permissions; this.bus = bus; this.log = log;
  }
  register(tool) {
    if (!tool.name || !tool.handler) throw new Error('Invalid tool');
    this.tools.set(tool.name, { risk: 'read', category: 'system.read', ...tool });
  }
  unregister(name) { this.tools.delete(name); }
  get(name) { return this.tools.get(name); }
  list() { return [...this.tools.values()]; }
  /** Definitions for the LLM (optionally filtered). */
  definitions(filter) {
    return this.list().filter((t) => !t.hidden && (!filter || filter(t))).map((t) => ({ name: t.name, description: t.description, parameters: t.parameters || { type: 'object', properties: {} } }));
  }

  async execute(name, rawArgs, ctx = {}) {
    const tool = this.tools.get(name);
    if (!tool) return { ok: false, error: `Unknown tool "${name}"` };
    const v = validate(tool.parameters, rawArgs);
    if (!v.ok) return { ok: false, error: v.errors.join('; ') };
    const args = v.value;
    const perm = await this.permissions.check({ tool, args, ctx });
    if (!perm.allowed) {
      this.permissions.audit(ctx.actor || 'viper', name, args, tool.risk, `denied: ${perm.reason}`);
      return { ok: false, denied: true, error: perm.reason };
    }
    const started = Date.now();
    this.bus.publish('tool.start', { name, label: tool.label || name, args: tool.redactArgs ? tool.redactArgs(args) : args, requestId: ctx.requestId });
    try {
      const result = await tool.handler(args, ctx);
      const out = result && typeof result === 'object' && 'ok' in result ? result : { ok: true, result };
      this.permissions.audit(ctx.actor || 'viper', name, tool.redactArgs ? tool.redactArgs(args) : args, tool.risk, out.ok ? 'ok' : `failed: ${out.error}`);
      this.bus.publish('tool.end', { name, ok: out.ok, ms: Date.now() - started, requestId: ctx.requestId, summary: out.summary || null });
      return out;
    } catch (e) {
      this.log.warn(`tool ${name} failed`, e);
      this.permissions.audit(ctx.actor || 'viper', name, args, tool.risk, `error: ${e.message}`);
      this.bus.publish('tool.end', { name, ok: false, ms: Date.now() - started, requestId: ctx.requestId, error: e.message });
      return { ok: false, error: e.message };
    }
  }
}

module.exports = { ToolRegistry, validate };
