// Phrases from any Short: which caption line is worth learning as a whole phrase?
//
// The app sends up to 12 caption lines that have YouTube's machine-translated Japanese.
// Jev judges each line twice (all in ONE request):
//   learn: is it a short, natural, everyday line this learner would want to say or understand?
//   ja:    is the Japanese a correct, natural rendering of the English (machine translation can be wrong)?
// Code ranks by learn × ja and drops anything below the thresholds. Jev never writes text.
import { MODEL, callJev } from './lesson.js';

export const MAX_LINES = 12;
export const LEARN_MIN = 0.5;
export const JA_MIN = 0.6;

export const GOALS = {
  travel: 'travelling in Japan: shops, food, directions, hotels',
  anime: 'understanding anime, games and Japanese pop culture',
  friends: 'chatting casually with Japanese friends',
  work: 'working or studying with Japanese speakers, politely',
  culture: 'food, culture and everyday life in Japan',
};

export function parsePhraseInput(body) {
  if (!body || typeof body.videoId !== 'string' || !body.videoId) throw new Error('videoId required');
  if (!Array.isArray(body.lines)) throw new Error('lines must be an array');
  const clip = (s, n) => (typeof s === 'string' ? s.slice(0, n) : '');
  return {
    videoId: body.videoId,
    title: clip(body.title, 200),
    goal: GOALS[body.goal] ? body.goal : 'culture',
    // What the learner already knows, so "learnable" means one step up from there (not a leap).
    learner: body.learner && typeof body.learner === 'object' ? {
      wordsLearned: Math.max(0, Number(body.learner.wordsLearned) || 0),
      known: (Array.isArray(body.learner.known) ? body.learner.known : []).slice(0, 30).map((k) => clip(String(k), 60)),
    } : null,
    lines: body.lines
      .map((l) => ({ i: Number(l.i), en: clip(l.en, 200).trim(), ja: clip(l.ja, 120).trim() }))
      .filter((l) => Number.isInteger(l.i) && l.en && l.ja)
      .slice(0, MAX_LINES),
  };
}

export function buildPhraseRequest(input) {
  const questions = {};
  input.lines.forEach((l, n) => {
    const where = `\`lines[${l.i}]\``;
    questions[`learn_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is the line ${where}.en (Japanese ${where}.ja) a good whole phrase for this learner of Japanese to learn next, for someone whose goal is ${GOALS[input.goal]}?`,
        evidence: input.learner ? '`learner` lists the words count and grammar they already know; a good next phrase uses at most one new grammar idea.' : undefined,
        good_when: 'it is short, complete on its own, natural in everyday conversation, and something people often say or react with (greetings, reactions, requests, questions, feelings).',
        bad_when: 'it is a fragment cut mid-sentence, a name or brand, song lyrics, a long explanation, slang that only makes sense in this video, or rude.',
      },
    };
    questions[`ja_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is ${where}.ja a correct and natural Japanese way to say ${where}.en?`,
        evidence: `${where}.ja is a machine translation of the English caption ${where}.en.`,
        say_no_when: 'the meaning changed, words are missing, it is unnatural word-for-word Japanese, or it is not Japanese.',
      },
    };
  });
  return {
    model: MODEL,
    state: {
      video_title: input.title,
      learner_goal: GOALS[input.goal],
      learner: input.learner ? { words_learned: input.learner.wordsLearned, grammar_known: input.learner.known } : undefined,
      lines: Object.fromEntries(input.lines.map((l) => [l.i, { en: l.en, ja: l.ja }])),
    },
    questions,
  };
}

export function rankPhrases(input, answers) {
  const judged = input.lines.map((l, n) => {
    const learn = answers?.[`learn_${n}`]?.noul;
    const ja = answers?.[`ja_${n}`]?.noul;
    return { i: l.i, learn: typeof learn === 'number' ? learn : null, ja: typeof ja === 'number' ? ja : null };
  });
  const picks = judged
    .filter((j) => j.learn !== null && j.ja !== null && j.learn >= LEARN_MIN && j.ja >= JA_MIN)
    .sort((a, b) => b.learn * b.ja - a.learn * a.ja)
    .slice(0, 2);
  return { picks, judged };
}

const cache = new Map();

export async function phrase(rawBody, opts = {}) {
  const input = parsePhraseInput(rawBody);
  if (input.lines.length === 0) return { videoId: input.videoId, picks: [], judged: [], model: null };
  const key = JSON.stringify([input.videoId, input.goal, input.learner?.known?.length ?? -1, input.lines.map((l) => l.i)]);
  if (cache.has(key)) return { ...cache.get(key), cached: true };
  const started = Date.now();
  const response = await callJev(buildPhraseRequest(input), opts);
  const result = { videoId: input.videoId, ...rankPhrases(input, response.answers), model: response.model ?? null, ms: Date.now() - started };
  cache.set(key, result);
  if (cache.size > 2000) cache.delete(cache.keys().next().value);
  return result;
}
