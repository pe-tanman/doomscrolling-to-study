// Nonverbal Shorts (music, gameplay, pets, food…): no speech to learn from, so teach the
// reaction word a Japanese viewer would say. Jev picks it with ONE Choice over a fixed list,
// from the title/description and on-device visual labels. Code builds a fair quiz from the
// probabilities: answer = top choice, distractors = the least likely reactions.
import { MODEL, callJev } from './lesson.js';

// ids match the app's vocab.json entries.
export const REACTIONS = {
  cute:        'かわいい (kawaii) — cute, adorable: animals, babies, small sweet things',
  amazing:     'すごい (sugoi) — amazing, impressive: skill, talent, big achievements',
  crazy:       'やばい (yabai) — insane, wild, "no way!": shocking, extreme, risky moments',
  funny:       'おもしろい (omoshiroi) — funny, entertaining: jokes, pranks, fails, comedy',
  scary:       'こわい (kowai) — scary, frightening: horror, danger, heights, jump scares',
  pretty:      'きれい (kirei) — beautiful, pretty: scenery, art, makeup, clean aesthetic',
  looks_tasty: 'おいしそう (oishisō) — looks delicious: cooking, food, eating',
  cool:        'かっこいい (kakkoii) — cool, stylish: cars, sports moves, fashion, tricks',
  sad:         'かなしい (kanashii) — sad: emotional, touching or heartbreaking moments',
};

export function parseReactionInput(body) {
  if (!body || typeof body.videoId !== 'string' || !body.videoId) throw new Error('videoId required');
  const clip = (s, n) => (typeof s === 'string' ? s.slice(0, n) : '');
  return {
    videoId: body.videoId,
    title: clip(body.title, 200),
    description: clip(body.description, 400),
    visualLabels: Array.isArray(body.visualLabels) ? body.visualLabels.slice(0, 10).map((l) => clip(String(l), 40)) : [],
    captions: Array.isArray(body.captions) ? body.captions.slice(0, 10).map((c) => clip(String(c), 120)) : [],
  };
}

export function buildReactionRequest(input) {
  return {
    model: MODEL,
    state: {
      video: {
        title: input.title,
        description: input.description || undefined,
        what_is_visible: input.visualLabels.length ? input.visualLabels : undefined,
        non_speech_captions: input.captions.length ? input.captions : undefined,
      },
    },
    questions: {
      reaction: {
        type: 'choice',
        instructions: 'A viewer just watched this short video, which has no spoken words. Which Japanese reaction word would they most naturally say about it?',
        criteria: REACTIONS,
      },
    },
  };
}

/** Quiz from the distribution: answer = top, 2 distractors = least likely (clearly wrong). */
export function reactionQuiz(answer) {
  const probs = answer?.probabilities ?? {};
  const ranked = Object.keys(REACTIONS).sort((a, b) => (probs[b] ?? 0) - (probs[a] ?? 0));
  const best = answer?.choice && REACTIONS[answer.choice] ? answer.choice : ranked[0];
  // Vary the wrong options: any reaction Jev considers clearly wrong (< 5%), at random;
  // fill from the least likely if there aren't two such.
  const clearlyWrong = ranked.filter((id) => id !== best && (probs[id] ?? 0) < 0.05).sort(() => Math.random() - 0.5);
  const fallback = ranked.filter((id) => id !== best && !clearlyWrong.includes(id)).reverse();
  const distractors = [...clearlyWrong, ...fallback].slice(0, 2);
  const confidence = answer?.confidence ?? null;
  return {
    answerId: best,
    options: [best, ...distractors],
    confidence,
    // Without any signal (no title, nothing recognized) Jev's pick is a guess: the app skips the quiz.
    confident: confidence !== null && confidence >= 0.3,
    probabilities: probs,
  };
}

const cache = new Map();

export async function reaction(rawBody, opts = {}) {
  const input = parseReactionInput(rawBody);
  const key = JSON.stringify([input.videoId, input.visualLabels]);
  if (cache.has(key)) return { ...cache.get(key), cached: true };
  const started = Date.now();
  const response = await callJev(buildReactionRequest(input), opts);
  const result = { videoId: input.videoId, ...reactionQuiz(response.answers?.reaction), model: response.model ?? null, ms: Date.now() - started };
  cache.set(key, result);
  if (cache.size > 2000) cache.delete(cache.keys().next().value);
  return result;
}
