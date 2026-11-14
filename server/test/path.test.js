import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePathInput, buildPathRequest, buildPath, path } from '../lib/path.js';

const places = [
  { id: 'arrival', name: 'Arrival', summary: 'kana', canDos: ['Said hello'], done: 5, total: 5 },
  { id: 'cafe', name: 'Café', summary: 'order', canDos: ['Ordered a drink'], done: 2, total: 6 },
  { id: 'station', name: 'Station', summary: 'directions', canDos: ['Asked the way'], done: 0, total: 6 },
  { id: 'shrine', name: 'Shrine', summary: 'casual', canDos: ['Talked casually'], done: 0, total: 4 },
];
const body = { goal: 'friends', places, phrases: [{ id: 'matte', place: 'shrine', meaning: 'wait', example: 'ちょっと まって' }, { id: 'kippu', place: 'station', meaning: 'ticket', example: 'きっぷ' }], speakingOff: true };

test('request: Choice over open places only, no speaking when off', () => {
  const r = buildPathRequest(parsePathInput(body));
  assert.deepEqual(Object.keys(r.questions.next_place.criteria), ['cafe', 'station', 'shrine']);
  assert.equal(r.questions.focus.criteria.speaking, undefined);
  assert.ok(r.questions.fit_0 && r.questions.fit_1);
});

test('path: done first, then Jev pick, then by probability; phrases by fit', () => {
  const input = parsePathInput(body);
  const out = buildPath(input, {
    next_place: { choice: 'shrine', confidence: 0.6, probabilities: { shrine: 0.6, cafe: 0.1, station: 0.3 } },
    focus: { choice: 'listening' },
    fit_0: { noul: 0.9 }, fit_1: { noul: 0.2 },
  });
  assert.deepEqual(out.order, ['arrival', 'shrine', 'station', 'cafe']);
  assert.equal(out.next, 'shrine');
  assert.equal(out.focus, 'listening');
  assert.deepEqual(out.phrasePriority, ['matte', 'kippu']);
});

test('path: missing answers keep the given order; invalid focus → null', () => {
  const out = buildPath(parsePathInput(body), { focus: { choice: 'speaking' } });
  assert.deepEqual(out.order, ['arrival', 'cafe', 'station', 'shrine']);
  assert.equal(out.focus, null);
});

test('path(): one TypeSafe call, cached', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls++; return new Response(JSON.stringify({ model: 'jev', answers: { next_place: { choice: 'station' }, focus: { choice: 'reading' } } })); };
  const a = await path(body, { apiKey: 'k', fetchImpl });
  const b = await path(body, { apiKey: 'k', fetchImpl });
  assert.equal(a.next, 'station');
  assert.equal(b.cached, true);
  assert.equal(calls, 1);
});

test('lookahead: only the next 3 open places are offered; later ones keep curriculum order', () => {
  const many = [...places, { id: 'ramen', name: 'Ramen', summary: '', canDos: [], done: 0, total: 4 }, { id: 'castle', name: 'Castle', summary: '', canDos: [], done: 0, total: 4 }];
  const input = parsePathInput({ ...body, places: many });
  assert.deepEqual(Object.keys(buildPathRequest(input).questions.next_place.criteria), ['cafe', 'station', 'shrine']);
  const out = buildPath(input, { next_place: { choice: 'castle' } });
  assert.equal(out.next, 'cafe');
  assert.deepEqual(out.order.slice(-2), ['ramen', 'castle']);
});
