'use strict';
// Firebase Cloud Messaging (HTTP v1) sender, used to reach VIPER Mobile when the app is closed.
// Uses YOUR Firebase project: a service-account key (stored encrypted in VIPER's vault) is
// exchanged for a short-lived OAuth token, then data-only messages are sent to the phone's
// registration token. Payloads carry only a title, a short phrase and identifiers — never task
// contents — because they pass through Google's servers.
const crypto = require('node:crypto');
const { fetchWithTimeout } = require('./util');

const b64url = (b) => Buffer.from(b).toString('base64url');

class FcmSender {
  constructor({ getServiceAccount, tokenUrl = 'https://oauth2.googleapis.com/token', apiBase = 'https://fcm.googleapis.com' } = {}) {
    this.getServiceAccount = getServiceAccount; this.tokenUrl = tokenUrl; this.apiBase = apiBase;
    this.cached = null;
  }

  configured() { const sa = this.serviceAccount(); return !!(sa?.client_email && sa?.private_key && sa?.project_id); }
  serviceAccount() { try { const raw = this.getServiceAccount(); return raw ? (typeof raw === 'string' ? JSON.parse(raw) : raw) : null; } catch { return null; } }

  /** Signed JWT assertion for Google's OAuth token endpoint (RS256). */
  assertion(sa, nowSec = Math.floor(Date.now() / 1000)) {
    const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: sa.token_uri || this.tokenUrl, iat: nowSec, exp: nowSec + 3600 }));
    const sig = crypto.createSign('RSA-SHA256').update(`${header}.${claims}`).sign(sa.private_key);
    return `${header}.${claims}.${b64url(sig)}`;
  }

  async accessToken() {
    if (this.cached && this.cached.exp > Date.now() + 60000) return this.cached.token;
    const sa = this.serviceAccount();
    if (!sa) throw new Error('Firebase service account not configured');
    const r = await fetchWithTimeout(sa.token_uri || this.tokenUrl, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: this.assertion(sa) }).toString() }, 15000);
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.access_token) throw new Error(`Google OAuth failed (${r.status}): ${j.error_description || j.error || ''}`.trim());
    this.cached = { token: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 };
    return this.cached.token;
  }

  /** Send a data-only, high-priority message so the phone app builds its own notification. */
  async send(registrationToken, data) {
    const sa = this.serviceAccount();
    const token = await this.accessToken();
    const message = { message: { token: registrationToken, data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, typeof v === 'string' ? v : JSON.stringify(v)])), android: { priority: 'high', ttl: '86400s' } } };
    const r = await fetchWithTimeout(`${this.apiBase}/v1/projects/${encodeURIComponent(sa.project_id)}/messages:send`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(message) }, 15000);
    const j = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, status: r.status, error: j.error?.message || `FCM HTTP ${r.status}`, unregistered: j.error?.details?.some?.((d) => d.errorCode === 'UNREGISTERED') || r.status === 404 };
    return { ok: true, id: j.name };
  }
}

module.exports = { FcmSender };
