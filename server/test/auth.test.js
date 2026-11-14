import test from 'node:test';
import assert from 'node:assert/strict';
import { sign, verify } from '../lib/auth.js';
import { POST } from '../api/lesson.js';

const secret = 'test-secret';
const body = '{"videoId":"a","cues":[],"candidates":[]}';
const now = 1_800_000_000_000;
const ts = now / 1000;
const h = (o) => o;

test('valid signature passes, once', () => {
  const headers = h({ 'x-ds-ts': String(ts), 'x-ds-nonce': 'n1', 'x-ds-sig': sign(secret, ts, 'n1', body) });
  assert.equal(verify(headers, body, { secret, now, production: true }), null);
  assert.equal(verify(headers, body, { secret, now, production: true })?.status, 401, 'replay rejected');
});

test('tampered body, wrong secret, stale time and missing headers are rejected', () => {
  const sig = sign(secret, ts, 'n2', body);
  assert.equal(verify({ 'x-ds-ts': String(ts), 'x-ds-nonce': 'n2', 'x-ds-sig': sig }, body + ' ', { secret, now })?.status, 401);
  assert.equal(verify({ 'x-ds-ts': String(ts), 'x-ds-nonce': 'n3', 'x-ds-sig': sign('other', ts, 'n3', body) }, body, { secret, now })?.status, 401);
  assert.equal(verify({ 'x-ds-ts': String(ts - 600), 'x-ds-nonce': 'n4', 'x-ds-sig': sign(secret, ts - 600, 'n4', body) }, body, { secret, now })?.status, 401);
  assert.equal(verify({}, body, { secret, now })?.status, 401);
});

test('production without a secret fails closed', () => {
  assert.equal(verify({}, body, { secret: '', production: true })?.status, 503);
  assert.equal(verify({}, body, { secret: '', production: false }), null);
});

test('POST handler rejects unsigned requests when a secret is set', async () => {
  process.env.DS_APP_SECRET = secret;
  const res = await POST(new Request('http://x/api/lesson', { method: 'POST', body }));
  assert.equal(res.status, 401);
  delete process.env.DS_APP_SECRET;
});
