import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInput, shortlist, buildRequest, pickTargets, lesson } from '../lib/lesson.js';

const body = {
  videoId: 'abc', title: 'River trip', wordsPerVideo: 2, playedTo: 0,
  cues: [
    { i: 0, start: 0.5, end: 2, text: 'We sat on the bank of the river', ja: '私たちは川の土手に座った' },
    { i: 1, start: 2.2, end: 4, text: 'I like this place so much', ja: 'この場所がとても好き' },
    { i: 2, start: 4.5, end: 6, text: 'Looks like rain, what now?', ja: '雨みたい、どうする？' },
    { i: 3, start: 9, end: 11, text: 'My dog is so tired', ja: '私の犬はとても疲れている' },
  ],
  candidates: [
    { cue: 0, entryId: 'bank', word: 'bank', kana: 'ぎんこう', meaning: 'bank (money)', status: 'new' },
    { cue: 0, entryId: 'river', word: 'river', kana: 'かわ', meaning: 'river', status: 'new' },
    { cue: 1, entryId: 'like', word: 'like', kana: 'すき', meaning: 'to like', status: 'new' },
    { cue: 2, entryId: 'what', word: 'what', kana: 'なに', meaning: 'what', status: 'known' },
    { cue: 3, entryId: 'dog', word: 'dog', kana: 'いぬ', meaning: 'dog', status: 'due' },
    { cue: 3, entryId: 'tired', word: 'tired', kana: 'つかれた', meaning: 'tired', status: 'new' },
  ],
};

test('shortlist drops passed lines and puts known words last', () => {
  const input = parseInput({ ...body, playedTo: 2.5 });
  const list = shortlist(input);
  assert.deepEqual(list.map((c) => c.entryId), ['like', 'dog', 'tired', 'what']);
});

test('request: one state, three Nouls per candidate (sense, fits, useful), no answers leaked in ids', () => {
  const input = parseInput(body);
  const list = shortlist(input);
  const req = buildRequest(input, list);
  assert.equal(Object.keys(req.questions).length, list.length * 3);
  assert.equal(req.state.captions[0].ja, '私たちは川の土手に座った');
  assert.match(req.questions.sense_0.instructions.question, /captions\[0\]/);
});

test('policy: wrong sense is rejected, early valuable word first, due word beats new word on the same line', () => {
  const input = parseInput(body);
  const list = shortlist(input);
  const idx = (id) => list.findIndex((c) => c.entryId === id);
  const answers = {};
  for (const [id, sense, useful] of [['bank', 0.05, 0.9], ['river', 0.95, 0.7], ['like', 0.9, 0.6], ['dog', 0.97, 0.85], ['tired', 0.96, 0.9], ['what', 0.9, 0.9]]) {
    answers[`sense_${idx(id)}`] = { type: 'noul', noul: sense };
    answers[`useful_${idx(id)}`] = { type: 'noul', noul: useful };
  }
  const { targets } = pickTargets(input, list, answers);
  assert.deepEqual(targets, [{ entryId: 'river', cue: 0 }, { entryId: 'dog', cue: 3 }]);
});

test('lesson(): calls TypeSafe once with bearer auth and returns targets', async () => {
  let calls = 0;
  const fetchImpl = async (url, init) => {
    calls++;
    assert.equal(url, 'https://api.typesafe.ai/v1/systemone');
    assert.equal(init.headers.authorization, 'Bearer test-key');
    const q = JSON.parse(init.body).questions;
    const answers = Object.fromEntries(Object.keys(q).map((k) => [k, { type: 'noul', noul: 0.9 }]));
    return new Response(JSON.stringify({ model: 'jev-1.14.0', answers, usage: { input_tokens: 900, output_tokens: 20 } }));
  };
  const out = await lesson({ ...body, videoId: 'xyz' }, { apiKey: 'test-key', fetchImpl });
  assert.equal(calls, 1);
  assert.equal(out.model, 'jev-1.14.0');
  assert.ok(out.targets.length >= 1 && out.targets.length <= 2);
  const again = await lesson({ ...body, videoId: 'xyz' }, { apiKey: 'test-key', fetchImpl });
  assert.equal(calls, 1, 'second call served from cache');
  assert.equal(again.cached, true);
});

test('missing key → 503, so the app keeps its on-device picks', async () => {
  await assert.rejects(lesson({ ...body, videoId: 'nokey' }, { apiKey: '' }), (e) => e.status === 503);
});

test('many-meaning word: senses contrasted; only the clearly-confirmed best sense is taught', async () => {
  const { parseInput, shortlist, buildRequest, pickTargets } = await import('../lib/lesson.js');
  const input = parseInput({
    videoId: 'p1', wordsPerVideo: 2,
    cues: [{ i: 0, start: 0, end: 2, text: 'oh poor baby' }, { i: 1, start: 5, end: 7, text: 'he plays the piano poorly' }],
    candidates: [
      { cue: 0, entryId: 'heta', word: 'poor', kana: 'へた', meaning: 'unskillful, poor' },
      { cue: 0, entryId: 'kawaisou', word: 'poor', kana: 'かわいそう', meaning: 'poor, pitiable' },
      { cue: 0, entryId: 'mazushii', word: 'poor', kana: 'まずしい', meaning: 'poor, needy' },
    ],
  });
  const list = shortlist(input);
  const req = buildRequest(input, list);
  assert.match(req.questions.sense_0.instructions.contrast, /かわいそう/);
  // Two senses look fine to Jev: only the best one (かわいそう) is taught.
  let out = pickTargets(input, list, { sense_0: { noul: 0.3 }, sense_1: { noul: 0.9 }, sense_2: { noul: 0.65 }, useful_1: { noul: 0.8 } });
  assert.deepEqual(out.targets.map((t) => t.entryId), ['kawaisou']);
  // Nothing clearly confirmed: no word on that line at all.
  out = pickTargets(input, list, { sense_0: { noul: 0.5 }, sense_1: { noul: 0.7 }, sense_2: { noul: 0.6 } });
  assert.deepEqual(out.targets, []);
});

test('right sense but not how Japanese says it (idiom / word-for-word) → not taught', async () => {
  const { parseInput, shortlist, buildRequest, pickTargets } = await import('../lib/lesson.js');
  const input = parseInput({
    videoId: 'f1', wordsPerVideo: 2,
    cues: [{ i: 0, start: 0, end: 2, text: 'good morning everyone' }, { i: 1, start: 5, end: 7, text: 'this ramen is good' }],
    candidates: [
      { cue: 0, entryId: 'good', word: 'good', kana: 'いい', meaning: 'good' },
      { cue: 1, entryId: 'good', word: 'good', kana: 'いい', meaning: 'good' },
    ],
  });
  const list = shortlist(input);
  assert.ok(buildRequest(input, list).questions.fits_0);
  const out = pickTargets(input, list, { sense_0: { noul: 0.8 }, fits_0: { noul: 0.1 }, sense_1: { noul: 0.9 }, fits_1: { noul: 0.9 } });
  assert.deepEqual(out.targets.map((t) => t.cue), [1]);
  assert.equal(out.judged[0].fits, 0.1);
});
