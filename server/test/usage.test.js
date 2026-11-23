import test from 'node:test';
import assert from 'node:assert/strict';
import { checkUsage, clientIp, deviceId, DEVICE_LIMITS } from '../lib/usage.js';

const DEV = '0F8A2C1E-3B4D-4E5F-8A9B-0C1D2E3F4A5B';
const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', USAGE_TOKEN: 'tok' };

// A fake bump_usage: counts per subject/feature and enforces p_limit like the SQL function.
function fakeStore() {
  const counts = new Map(); const calls = [];
  const fetchImpl = async (_url, init) => {
    const b = JSON.parse(init.body); calls.push(b);
    if (b.p_token !== 'tok') return new Response('-2');
    const k = `${b.p_subject}|${b.p_feature}`; const n = counts.get(k) || 0;
    if (n >= b.p_limit) return new Response('-1');
    counts.set(k, n + 1); return new Response(String(n + 1));
  };
  return { fetchImpl, calls };
}

test('device and IP are both counted, device first', async () => {
  const s = fakeStore();
  assert.equal(await checkUsage({ 'x-ds-device': DEV, 'x-forwarded-for': '1.2.3.4, 9.9.9.9' }, 'tts', { env, fetchImpl: s.fetchImpl }), null);
  assert.deepEqual(s.calls.map((c) => [c.p_subject, c.p_limit]),
    [[`d:${DEV.toLowerCase()}`, DEVICE_LIMITS.tts], ['ip:1.2.3.4', DEVICE_LIMITS.tts * 4]]);
});

test('over the device limit → 429', async () => {
  const s = fakeStore();
  const h = { 'x-ds-device': DEV, 'x-real-ip': '5.5.5.5' };
  for (let i = 0; i < DEVICE_LIMITS.path; i++) assert.equal(await checkUsage(h, 'path', { env, fetchImpl: s.fetchImpl }), null);
  assert.deepEqual(await checkUsage(h, 'path', { env, fetchImpl: s.fetchImpl }), { status: 429, error: 'daily limit reached' });
});

test('rotating device ids still hits the IP limit', async () => {
  const s = fakeStore();
  let blocked = 0;
  for (let i = 0; i < DEVICE_LIMITS.path * 4 + 5; i++) {
    const id = `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`;
    if (await checkUsage({ 'x-ds-device': id, 'x-real-ip': '7.7.7.7' }, 'path', { env, fetchImpl: s.fetchImpl })) blocked++;
  }
  assert.equal(blocked, 5);
});

test('store down or wrong token → smaller in-memory limit, still enforced', async () => {
  const down = async () => { throw new Error('offline'); };
  const h = { 'x-real-ip': '8.8.8.8' };
  let ok = 0;
  for (let i = 0; i < DEVICE_LIMITS.path * 4; i++) if (!(await checkUsage(h, 'path', { env, fetchImpl: down }))) ok++;
  assert.equal(ok, DEVICE_LIMITS.path);   // 25% of the IP limit
  const wrong = fakeStore();
  const r = await checkUsage({ 'x-real-ip': '6.6.6.6' }, 'tts', { env: { ...env, USAGE_TOKEN: 'nope' }, fetchImpl: wrong.fetchImpl });
  assert.equal(r, null);   // falls back to memory (first use is allowed)
});

test('production without a store still limits; local dev does not', async () => {
  assert.equal(await checkUsage({}, 'tts', { env: {}, production: false }), null);
  const h = { 'x-real-ip': '4.4.4.4' };
  let ok = 0;
  for (let i = 0; i < 1000; i++) if (!(await checkUsage(h, 'search', { env: {}, production: true }))) ok++;
  assert.equal(ok, DEVICE_LIMITS.search);
});

test('header parsing ignores junk', () => {
  assert.equal(deviceId({ 'x-ds-device': 'not-a-uuid' }), null);
  assert.equal(deviceId({ 'x-ds-device': DEV }), DEV.toLowerCase());
  assert.equal(clientIp({}), 'unknown');
  assert.equal(clientIp({ 'x-forwarded-for': ' 1.1.1.1 , 2.2.2.2' }), '1.1.1.1');
});
