import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePhraseInput, buildPhraseRequest, rankPhrases, phrase } from '../lib/phrase.js';

const body = {
  videoId: 'v1', title: 'cat reacts', goal: 'travel',
  lines: [
    { i: 0, en: 'oh my god this is so cute', ja: 'なんてかわいいの' },
    { i: 3, en: 'and then he', ja: 'そして彼は' },
    { i: 5, en: 'thank you so much', ja: '本当にありがとう' },
    { i: 7, en: 'no japanese here', ja: '' },
  ],
};

test('parse: drops lines without Japanese, unknown goal → culture', () => {
  const i = parsePhraseInput(body);
  assert.equal(i.lines.length, 3);
  assert.equal(parsePhraseInput({ ...body, goal: 'x' }).goal, 'culture');
});

test('request: two Nouls per line, lines in state', () => {
  const r = buildPhraseRequest(parsePhraseInput(body));
  assert.equal(Object.keys(r.questions).length, 6);
  assert.equal(r.state.lines[5].ja, '本当にありがとう');
});

test('rank: learn × ja, thresholds, top 2', () => {
  const i = parsePhraseInput(body);
  const out = rankPhrases(i, {
    learn_0: { noul: 0.8 }, ja_0: { noul: 0.7 },
    learn_1: { noul: 0.1 }, ja_1: { noul: 0.9 },
    learn_2: { noul: 0.9 }, ja_2: { noul: 0.95 },
  });
  assert.deepEqual(out.picks.map((p) => p.i), [5, 0]);
  assert.equal(out.judged.length, 3);
});

test('phrase(): one call, cached; empty → no call', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls++; return new Response(JSON.stringify({ model: 'jev', answers: { learn_0: { noul: 0.9 }, ja_0: { noul: 0.9 } } })); };
  const a = await phrase({ videoId: 'v2', lines: [{ i: 1, en: 'hello', ja: 'こんにちは' }] }, { apiKey: 'k', fetchImpl });
  const b = await phrase({ videoId: 'v2', lines: [{ i: 1, en: 'hello', ja: 'こんにちは' }] }, { apiKey: 'k', fetchImpl });
  assert.deepEqual(a.picks.map((p) => p.i), [1]);
  assert.equal(b.cached, true);
  assert.equal(calls, 1);
  const c = await phrase({ videoId: 'v3', lines: [] }, { apiKey: 'k', fetchImpl });
  assert.deepEqual(c.picks, []);
  assert.equal(calls, 1);
});
