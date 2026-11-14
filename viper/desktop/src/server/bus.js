'use strict';
const { EventEmitter } = require('node:events');

// Central event bus. Every event published here is also forwarded to
// connected UI clients (desktop renderer, HUD, paired phones) by the API layer.
class Bus extends EventEmitter {
  constructor() { super(); this.setMaxListeners(100); }
  publish(type, data = {}) {
    const evt = { type, data, ts: Date.now() };
    this.emit('event', evt);
    this.emit(type, data);
    return evt;
  }
}
module.exports = { Bus };
