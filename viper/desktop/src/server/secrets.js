'use strict';
// Credential vault. In the desktop app the encryptor is Electron safeStorage
// (Windows DPAPI, tied to the user account). In standalone/headless mode a
// local AES-256-GCM key file is used and the vault reports itself as
// "file-key" so the UI can warn that it is weaker than the OS keystore.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

function fileKeyEncryptor(dir) {
  const keyFile = path.join(dir, 'vault.key');
  let key;
  if (fs.existsSync(keyFile)) key = fs.readFileSync(keyFile);
  else { key = crypto.randomBytes(32); fs.writeFileSync(keyFile, key, { mode: 0o600 }); }
  return {
    kind: 'file-key',
    encrypt(plain) {
      const iv = crypto.randomBytes(12);
      const c = crypto.createCipheriv('aes-256-gcm', key, iv);
      const enc = Buffer.concat([c.update(Buffer.from(plain, 'utf8')), c.final()]);
      return Buffer.concat([iv, c.getAuthTag(), enc]);
    },
    decrypt(buf) {
      const b = Buffer.from(buf);
      const d = crypto.createDecipheriv('aes-256-gcm', key, b.subarray(0, 12));
      d.setAuthTag(b.subarray(12, 28));
      return Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8');
    },
  };
}

class Vault {
  constructor(db, encryptor) { this.db = db; this.enc = encryptor; }
  get kind() { return this.enc.kind; }
  set(name, value) {
    if (value == null || value === '') return this.delete(name);
    const blob = this.enc.encrypt(String(value));
    this.db.run('INSERT INTO secrets (name, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(name) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at', name, blob, Date.now());
  }
  get(name) {
    const row = this.db.get('SELECT value FROM secrets WHERE name = ?', name);
    if (!row) return null;
    try { return this.enc.decrypt(row.value); } catch { return null; }
  }
  has(name) { return !!this.db.get('SELECT 1 AS x FROM secrets WHERE name = ?', name); }
  delete(name) { this.db.run('DELETE FROM secrets WHERE name = ?', name); }
  list() { return this.db.all('SELECT name, updated_at FROM secrets ORDER BY name'); }
}

module.exports = { Vault, fileKeyEncryptor };
