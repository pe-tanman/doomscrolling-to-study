// Server-side daily usage limits, per device and per IP, for every endpoint that costs money.
// Counters live in Supabase (private.usage_counters) behind public.bump_usage(), which only answers
// when given USAGE_TOKEN (its hash is in private.config). The app's own Plan limits are lower; these
// are the hard ceiling a modified app, a reinstall or someone with the extracted signing secret can't pass.
//
// If the counter store can't be reached, a smaller per-instance in-memory limit applies (fail safe,
// but the app keeps working).

export const DEVICE_LIMITS = {   // per device per day (UTC)
  tts: 600,       // matches Plan premium "natural voice"
  lesson: 400,    // "smart picks"
  picture: 200,   // "picture questions"
  phrase: 400,
  grammar: 400,
  path: 100,
  reaction: 400,
  search: 60,     // YouTube searches that miss the CDN cache (100 quota units each)
};
const IP_FACTOR = 4;   // several learners can share one IP (school, café, carrier NAT)
const MEMORY_FACTOR = 0.25;

const memory = new Map();   // fallback: `${subject}|${feature}|${day}` → count

export function clientIp(headers) {
  const get = (k) => (typeof headers.get === 'function' ? headers.get(k) : headers[k]);
  const fwd = get('x-forwarded-for') || '';
  return (get('x-real-ip') || fwd.split(',')[0] || '').trim().slice(0, 64) || 'unknown';
}

/** A device id the app keeps in its Keychain (random UUID). Anything else is ignored. */
export function deviceId(headers) {
  const get = (k) => (typeof headers.get === 'function' ? headers.get(k) : headers[k]);
  const d = String(get('x-ds-device') || '');
  return /^[0-9A-Fa-f-]{36}$/.test(d) ? d.toLowerCase() : null;
}

async function bump(subject, feature, limit, { url, anonKey, token, fetchImpl }) {
  const r = await fetchImpl(`${url}/rest/v1/rpc/bump_usage`, {
    method: 'POST',
    headers: { apikey: anonKey, authorization: `Bearer ${anonKey}`, 'content-type': 'application/json' },
    body: JSON.stringify({ p_token: token, p_subject: subject, p_feature: feature, p_limit: limit }),
    signal: AbortSignal.timeout(2500),
  });
  if (!r.ok) throw new Error(`usage store ${r.status}`);
  const n = await r.json();
  if (n === -2) throw new Error('usage store rejected the token');
  return n;
}

function bumpMemory(subject, feature, limit, now) {
  const day = new Date(now).toISOString().slice(0, 10);
  const k = `${subject}|${feature}|${day}`;
  const n = memory.get(k) || 0;
  if (n >= limit) return -1;
  memory.set(k, n + 1);
  if (memory.size > 50_000) memory.clear();
  return n + 1;
}

/**
 * Counts one use of `feature`. Returns null when allowed, or { status: 429, error } when a daily limit is reached.
 * `env` and `fetchImpl` are injectable for tests.
 */
export async function checkUsage(headers, feature, {
  env = process.env, fetchImpl = fetch, now = Date.now(), production = Boolean(process.env.VERCEL),
} = {}) {
  const base = DEVICE_LIMITS[feature];
  if (!base) throw new Error(`unknown feature ${feature}`);
  const subjects = [[`ip:${clientIp(headers)}`, base * IP_FACTOR]];
  const dev = deviceId(headers);
  if (dev) subjects.unshift([`d:${dev}`, base]);

  const store = env.SUPABASE_URL && env.SUPABASE_ANON_KEY && env.USAGE_TOKEN
    ? { url: env.SUPABASE_URL.replace(/\/$/, ''), anonKey: env.SUPABASE_ANON_KEY, token: env.USAGE_TOKEN, fetchImpl }
    : null;
  if (!store && !production) return null;   // local dev without the store: no limits

  for (const [subject, limit] of subjects) {
    let n;
    try {
      if (!store) throw new Error('usage store not configured');
      n = await bump(subject, feature, limit, store);
    } catch (e) {
      console.error(`usage: ${e.message}; using in-memory limit`);
      n = bumpMemory(subject, feature, Math.max(1, Math.floor(limit * MEMORY_FACTOR)), now);
    }
    if (n < 0) return { status: 429, error: 'daily limit reached' };
  }
  return null;
}
