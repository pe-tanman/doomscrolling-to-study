import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parsePictureInput, buildPresenceRequest, buildDetailRequest, chooseTarget, picture, pickForDetail } from '../lib/picture.js';

const img = { format: 'jpg', data_base64: Buffer.from('fake').toString('base64') };
const body = (extra = {}) => ({
  videoId: 'v1', image: img,
  candidates: [{ entryId: 'dog', en: 'dog', status: 'new' }, { entryId: 'cat', en: 'cat', status: 'learning' }, { entryId: 'car', en: 'car' }],
  colors: [{ entryId: 'white', en: 'white' }, { entryId: 'black', en: 'black' }],
  ...extra,
});

test('rejects missing image and oversized image', () => {
  assert.throws(() => parsePictureInput({ ...body(), image: undefined }), /image/);
  assert.throws(() => parsePictureInput(body({ image: { format: 'jpg', data_base64: 'A'.repeat(3_000_000) } })), /too large/);
});

test('presence request: one Noul per candidate, frame sent once as an asset', () => {
  const input = parsePictureInput(body());
  const req = buildPresenceRequest(input);
  assert.equal(Object.keys(req.questions).length, 3);
  assert.equal(Object.keys(req.assets).length, 1);
  assert.equal(req.state.frame, Object.keys(req.assets)[0]);
  assert.match(req.questions.present_0.instructions.question, /dog/);
  const detail = buildDetailRequest(input, [input.candidates[0]]);
  assert.equal(detail.questions.where_0.type, 'box');
  assert.deepEqual(Object.keys(detail.questions.color_0.criteria), ['white', 'black', 'other']);
});

test('policy: visible ≥ 0.8 (learner words first), absent ≤ 0.03', () => {
  const input = parsePictureInput(body());
  const r = chooseTarget(input, { present_0: { noul: 0.9 }, present_1: { noul: 0.88 }, present_2: { noul: 0.01 } });
  assert.deepEqual(r.visible.map((c) => c.entryId), ['cat', 'dog']);   // 0.88 + learning beats 0.9 + new
  assert.deepEqual(r.absent, ['car']);
});

test('pipeline: sends the images header, keeps confident colors only', async () => {
  const seen = [];
  const fetchImpl = async (_url, init) => {
    seen.push(init.headers);
    const q = JSON.parse(init.body).questions;
    const answers = q.present_0
      ? { present_0: { noul: 0.97 }, present_1: { noul: 0.02 }, present_2: { noul: 0.01 } }
      : { where_0: { box: { top: 0.1, bottom: 0.9, left: 0.2, right: 0.8 }, confidence: 0.8 },
          color_0: { choice: 'white', confidence: 0.4 } };
    return new Response(JSON.stringify({ model: 'jev-test', answers }));
  };
  const r = await picture(body({ videoId: 'v-pipe' }), { apiKey: 'k', fetchImpl });
  assert.equal(seen.length, 2);
  assert.ok(seen.every((h) => h['TypeSafe-Danger-Zone-Images'] === 'true'));
  assert.equal(r.things[0].entryId, 'dog');
  assert.equal(r.things[0].box.confidence, 0.8);
  assert.equal(r.things[0].color, null);          // 0.4 < COLOR_MIN
  assert.deepEqual(r.absent.sort(), ['car', 'cat']);
});

test('detail pick: random over visible things, skips recent words, never people/background', () => {
  const visible = ['person', 'dog', 'car', 'sky', 'ball'].map((entryId) => ({ entryId, p: 0.95 }));
  const counts = {};
  for (let k = 0; k < 2000; k++) {
    for (const c of pickForDetail(visible, ['dog'], 1)) counts[c.entryId] = (counts[c.entryId] || 0) + 1;
  }
  assert.equal(counts.dog, undefined);                 // recently asked → skipped
  assert.ok(counts.car > 500 && counts.ball > 500);    // spread across the others
  assert.equal(counts.person, undefined);              // people / background never get outlined
  assert.equal(counts.sky, undefined);
  // Everything recent → still picks something rather than nothing (but never people).
  assert.deepEqual(pickForDetail(visible, visible.map((c) => c.entryId), 5).map((c) => c.entryId).sort(), ['ball', 'car', 'dog']);
  // Only people in the frame → nothing to outline.
  assert.equal(pickForDetail([{ entryId: 'person', p: 0.99 }, { entryId: 'man', p: 0.9 }], []).length, 0);
});
