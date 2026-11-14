// Only the Upscroll app may call the lesson API.
// The app signs each request: HMAC-SHA256(DS_APP_SECRET, `${ts}\n${nonce}\n${body}`), hex.
// Headers: x-ds-ts (unix seconds), x-ds-nonce (random, single use), x-ds-sig.
// Stale (> 5 min) or replayed requests are rejected. Fails closed in production when the secret is missing.
import { createHmac, timingSafeEqual } from 'node:crypto';

const WINDOW_S = 300;
const seenNonces = new Map();   // nonce → expiry (ms). Per instance; the timestamp window bounds replays elsewhere.

export function sign(secret, ts, nonce, body) {
  return createHmac('sha256', secret).update(`${ts}\n${nonce}\n${body}`).digest('hex');
}

/** Returns null when allowed, or { status, error } when rejected. */
export function verify(headers, body, { secret = process.env.DS_APP_SECRET, now = Date.now(), production = Boolean(process.env.VERCEL) } = {}) {
  if (!secret) {
    return production ? { status: 503, error: 'server not configured' } : null;   // local dev without a secret
  }
  const get = (k) => (typeof headers.get === 'function' ? headers.get(k) : headers[k]);
  const ts = Number(get('x-ds-ts'));
  const nonce = get('x-ds-nonce');
  const sig = get('x-ds-sig');
  if (!ts || !nonce || !sig || !/^[0-9a-f]{64}$/.test(sig) || nonce.length > 64) return { status: 401, error: 'unauthorized' };
  if (Math.abs(now / 1000 - ts) > WINDOW_S) return { status: 401, error: 'unauthorized' };

  const expected = Buffer.from(sign(secret, ts, nonce, body), 'hex');
  if (!timingSafeEqual(expected, Buffer.from(sig, 'hex'))) return { status: 401, error: 'unauthorized' };

  for (const [n, exp] of seenNonces) { if (exp < now) seenNonces.delete(n); else break; }
  if (seenNonces.has(nonce)) return { status: 401, error: 'unauthorized' };
  seenNonces.set(nonce, now + WINDOW_S * 1000);
  return null;
}
