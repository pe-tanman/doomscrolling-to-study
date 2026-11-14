import test from 'node:test';
import assert from 'node:assert/strict';
import { reactionQuiz, buildReactionRequest, parseReactionInput, reaction, REACTIONS } from '../lib/reaction.js';

test('quiz: top choice is the answer, the two least likely are distractors', () => {
  const probabilities = { cute: 0.7, amazing: 0.1, crazy: 0.05, funny: 0.08, scary: 0.01, pretty: 0.03, looks_tasty: 0.005, cool: 0.03, sad: 0.005 };
  const q = reactionQuiz({ choice: 'cute', confidence: 0.6, probabilities });
  assert.equal(q.answerId, 'cute');
  assert.equal(q.options.length, 3);
  for (const d of q.options.slice(1)) assert.ok(probabilities[d] < 0.05, `${d} should be clearly wrong`);
  assert.equal(q.confident, true);
  assert.equal(reactionQuiz({ choice: 'cute', confidence: 0.16, probabilities }).confident, false);
});

test('request: one Choice over all reactions; empty fields omitted', () => {
  const req = buildReactionRequest(parseReactionInput({ videoId: 'v', title: 'puppy sees snow', visualLabels: ['dog', 'snow'] }));
  assert.deepEqual(Object.keys(req.questions), ['reaction']);
  assert.equal(Object.keys(req.questions.reaction.criteria).length, Object.keys(REACTIONS).length);
  assert.deepEqual(req.state.video.what_is_visible, ['dog', 'snow']);
  assert.equal(req.state.video.description, undefined);
});

test('reaction(): single TypeSafe call, cached', async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return new Response(JSON.stringify({ model: 'jev-1.14.0', answers: { reaction: { type: 'choice', choice: 'looks_tasty', confidence: 0.8, probabilities: { looks_tasty: 0.9, sad: 0.01, scary: 0.02 } } } }));
  };
  const a = await reaction({ videoId: 'food1', title: 'Best ramen in Tokyo' }, { apiKey: 'k', fetchImpl });
  const b = await reaction({ videoId: 'food1', title: 'Best ramen in Tokyo' }, { apiKey: 'k', fetchImpl });
  assert.equal(a.answerId, 'looks_tasty');
  assert.equal(a.options.length, 3);
  assert.equal(calls, 1);
  assert.equal(b.cached, true);
});
