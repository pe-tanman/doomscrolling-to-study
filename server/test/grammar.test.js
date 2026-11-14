import test from 'node:test';
import assert from 'node:assert/strict';
import { parseGrammarInput, buildGrammarRequest, rankGrammar, grammar } from '../lib/grammar.js';

const body = {
  videoId: 'g1', title: 'ramen in tokyo',
  learner: { stage: 'chunks', wordsLearned: 20, known: ['を (object)'] },
  lines: [
    { i: 0, en: 'I want to eat ramen', ja: 'ラーメンが食べたい', words: [{ ja: 'ラーメン', meaning: 'ramen', known: true }, { ja: '食べ', meaning: 'to eat', known: false }] },
    { i: 2, en: 'I understood', ja: 'わかった' },
    { i: 4, en: 'no japanese', ja: '' },
  ],
  candidates: [
    { line: 0, point: 'tai', title: '〜たい', meaning: 'want to do', piece: 'たい', before: 'ラーメンが食べ', after: '', distractors: ['ます', 'ました', 'ない'], status: 'new' },
    { line: 0, point: 'ga_like', title: 'が', meaning: 'marks what you want or like', piece: 'が', before: 'ラーメン', after: '食べたい', distractors: ['を', 'に', 'で'], status: 'new' },
    { line: 2, point: 'katta', title: '〜かった', meaning: 'past of an い-adjective', piece: 'かった', before: 'わ', after: '', distractors: ['い', 'くない'], status: 'new' },
    { line: 4, point: 'wo', title: 'を', meaning: 'object', piece: 'を', before: '', after: '', distractors: ['が', 'に'] },
    { line: 0, point: 'x', title: 'x', meaning: 'x', piece: 'x', distractors: ['y'] },
  ],
};

test('parse: drops lines without Japanese and candidates without a line or with < 2 distractors', () => {
  const i = parseGrammarInput(body);
  assert.equal(i.lines.length, 2);
  assert.deepEqual(i.candidates.map((c) => c.point), ['tai', 'ga_like', 'katta']);
});

test('request: ja once per line, uses + fit per candidate, alt per distractor', () => {
  const r = buildGrammarRequest(parseGrammarInput(body));
  const keys = Object.keys(r.questions);
  assert.deepEqual(keys.filter((k) => k.startsWith('ja_')).sort(), ['ja_0', 'ja_2']);
  assert.equal(keys.filter((k) => k.startsWith('uses_')).length, 3);
  assert.equal(keys.filter((k) => k.startsWith('alt_0_')).length, 3);
  assert.match(r.questions.uses_0.instructions.question, /ラーメンが食べ【たい】/);
  assert.deepEqual(r.state.learner.grammar_known, ['を (object)']);
  assert.deepEqual(r.state.lines[0].words.map((w) => w.known), [true, false]);
  assert.equal(r.state.lines[2].words, undefined);
  assert.match(r.questions.fit_0.instructions.evidence, /lines\[0\]`\.words/);
});

test('rank: drops wrong-sense candidates and acceptable distractors; needs 2 clearly-wrong ones', () => {
  const i = parseGrammarInput(body);
  const out = rankGrammar(i, {
    ja_0: { noul: 0.9 }, ja_2: { noul: 0.9 },
    uses_0: { noul: 0.95 }, fit_0: { noul: 0.8 }, alt_0_0: { noul: 0.05 }, alt_0_1: { noul: 0.1 }, alt_0_2: { noul: 0.6 },
    // が vs を: both accepted with 食べたい → only one clearly-wrong distractor left → not asked
    uses_1: { noul: 0.9 }, fit_1: { noul: 0.9 }, alt_1_0: { noul: 0.7 }, alt_1_1: { noul: 0.05 }, alt_1_2: { noul: 0.4 },
    // わかった is not an adjective past
    uses_2: { noul: 0.1 }, fit_2: { noul: 0.9 }, alt_2_0: { noul: 0.1 }, alt_2_1: { noul: 0.1 },
  });
  assert.deepEqual(out.picks.map((p) => p.point), ['tai']);
  assert.deepEqual(out.picks[0].distractors, ['ます', 'ました']);
  assert.deepEqual(out.judged[1].rejected, ['を', 'で']);
});

test('grammar(): one call, cached; no candidates → no call', async () => {
  let calls = 0;
  const fetchImpl = async (_u, init) => {
    calls++;
    const q = JSON.parse(init.body).questions;
    const answers = Object.fromEntries(Object.keys(q).map((k) => [k, { noul: k.startsWith('alt') ? 0.05 : 0.9 }]));
    return new Response(JSON.stringify({ model: 'jev', answers }));
  };
  const a = await grammar(body, { apiKey: 'k', fetchImpl });
  const b = await grammar(body, { apiKey: 'k', fetchImpl });
  assert.equal(a.picks.length, 2);
  assert.notEqual(a.picks[0].line === a.picks[1].line, true);
  assert.equal(b.cached, true);
  assert.equal(calls, 1);
  const c = await grammar({ videoId: 'g2', lines: [], candidates: [] }, { apiKey: 'k', fetchImpl });
  assert.deepEqual(c.picks, []);
  assert.equal(calls, 1);
});
