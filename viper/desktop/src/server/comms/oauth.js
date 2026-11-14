'use strict';
// OAuth 2.0 Authorization Code + PKCE with a loopback redirect (RFC 8252),
// the official method for desktop apps with Google and Microsoft accounts.
// The user supplies their own OAuth client ID; nothing is hardcoded.
const http = require('node:http');
const crypto = require('node:crypto');

const PROVIDERS = {
  google: {
    auth: 'https://accounts.google.com/o/oauth2/v2/auth', token: 'https://oauth2.googleapis.com/token',
    scope: 'https://mail.google.com/ openid email', extra: { access_type: 'offline', prompt: 'consent' },
  },
  microsoft: {
    auth: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize', token: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    scope: 'offline_access openid email https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send', extra: {},
  },
};

function b64url(buf) { return buf.toString('base64url'); }

/** Runs the interactive browser sign-in. Resolves with { access_token, refresh_token, expires_at, email? }. */
function authorize({ provider, clientId, clientSecret, openExternal, timeoutMs = 300000 }) {
  const p = PROVIDERS[provider];
  if (!p) throw new Error('Unknown OAuth provider');
  if (!clientId) throw new Error('An OAuth client ID is required. Create one in the Google Cloud Console or Microsoft Entra admin center (see docs/COMMUNICATIONS.md).');
  const verifier = b64url(crypto.randomBytes(48));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const state = b64url(crypto.randomBytes(16));
  return new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, 'http://127.0.0.1');
      if (url.pathname !== '/callback') { res.writeHead(404); return res.end(); }
      const done = (msg) => { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(`<html><body style="background:#000;color:#fff;font-family:Segoe UI,sans-serif;padding:40px"><h2>VIPER</h2><p>${msg}</p><p>You can close this window.</p></body></html>`); };
      try {
        if (url.searchParams.get('state') !== state) throw new Error('State mismatch');
        if (url.searchParams.get('error')) throw new Error(url.searchParams.get('error_description') || url.searchParams.get('error'));
        const code = url.searchParams.get('code');
        const tok = await exchange(p, { grant_type: 'authorization_code', code, redirect_uri: redirect, client_id: clientId, code_verifier: verifier, ...(clientSecret ? { client_secret: clientSecret } : {}) });
        done('Signed in. VIPER can now use this mailbox.');
        cleanup(); resolve(tok);
      } catch (e) { done(`Sign-in failed: ${String(e.message).replace(/</g, '&lt;')}`); cleanup(); reject(e); }
    });
    let redirect = '';
    const timer = setTimeout(() => { cleanup(); reject(new Error('Sign-in timed out')); }, timeoutMs);
    const cleanup = () => { clearTimeout(timer); server.close(); };
    server.listen(0, '127.0.0.1', () => {
      redirect = `http://127.0.0.1:${server.address().port}/callback`;
      const q = new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: redirect, scope: p.scope, state, code_challenge: challenge, code_challenge_method: 'S256', ...p.extra });
      openExternal(`${p.auth}?${q}`);
    });
  });
}

async function exchange(p, params) {
  const r = await fetch(p.token, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(params) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error_description || j.error || `Token endpoint ${r.status}`);
  let email = null;
  if (j.id_token) { try { email = JSON.parse(Buffer.from(j.id_token.split('.')[1], 'base64url').toString()).email || null; } catch { /* ignore */ } }
  return { access_token: j.access_token, refresh_token: j.refresh_token || params.refresh_token, expires_at: Date.now() + (j.expires_in || 3600) * 1000 - 60000, email };
}

async function refresh({ provider, clientId, clientSecret, refreshToken }) {
  return exchange(PROVIDERS[provider], { grant_type: 'refresh_token', refresh_token: refreshToken, client_id: clientId, ...(clientSecret ? { client_secret: clientSecret } : {}), ...(provider === 'microsoft' ? { scope: PROVIDERS.microsoft.scope } : {}) });
}

module.exports = { authorize, refresh, PROVIDERS };
