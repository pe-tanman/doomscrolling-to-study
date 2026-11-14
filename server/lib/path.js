// A personal curriculum: Jev decides the learner's direction from their goal, interests and results.
//
// One request, three kinds of judgment:
//   next_place: Choice over the places not finished yet: which to study next for THIS learner?
//   focus:      Choice over the four skills: which one to push in the feed right now?
//   fit_n:      Noul per candidate phrase: how useful is it for this learner's goal and interests?
// Code turns the probabilities into a path: every place ordered (Jev's pick first, then by probability),
// a focus skill, and phrases in priority order. Jev only judges options that code supplied.
import { MODEL, callJev } from './lesson.js';
import { GOALS } from './phrase.js';

export const SKILLS = {
  reading: 'reading: recognising written Japanese (kana, words, short lines)',
  listening: 'listening: understanding spoken Japanese at natural speed',
  writing: 'writing: building Japanese sentences in the right order',
  speaking: 'speaking: saying phrases out loud with good pronunciation',
};
const MAX_PHRASES = 20;

export function parsePathInput(body) {
  if (!body || typeof body !== 'object') throw new Error('body must be an object');
  const clip = (s, n) => (typeof s === 'string' ? s.slice(0, n) : '');
  const places = Array.isArray(body.places) ? body.places : [];
  if (places.length === 0) throw new Error('places required');
  const skill = (s) => ({ right: Math.max(0, Number(s?.right) || 0), wrong: Math.max(0, Number(s?.wrong) || 0), dots: Math.max(0, Number(s?.dots) || 0) });
  return {
    goal: GOALS[body.goal] ? body.goal : 'culture',
    level: clip(body.level, 20),
    wordsLearned: Math.max(0, Number(body.wordsLearned) || 0),
    interests: (Array.isArray(body.interests) ? body.interests : []).slice(0, 12).map((t) => clip(String(t), 100)).filter(Boolean),
    skills: Object.fromEntries(Object.keys(SKILLS).map((k) => [k, skill(body.skills?.[k])])),
    speakingOff: Boolean(body.speakingOff),
    stage: clip(body.stage, 20),
    grammarKnown: (Array.isArray(body.grammarKnown) ? body.grammarKnown : []).slice(0, 30).map((g) => clip(String(g), 80)),
    places: places.slice(0, 20).map((p) => ({
      id: clip(String(p.id), 40),
      name: clip(p.name, 60),
      summary: clip(p.summary, 200),
      canDos: (Array.isArray(p.canDos) ? p.canDos : []).slice(0, 8).map((c) => clip(String(c), 60)),
      done: Math.max(0, Number(p.done) || 0),
      total: Math.max(1, Number(p.total) || 1),
    })).filter((p) => p.id),
    phrases: (Array.isArray(body.phrases) ? body.phrases : []).slice(0, MAX_PHRASES).map((p) => ({
      id: clip(String(p.id), 40), place: clip(String(p.place), 40), meaning: clip(p.meaning, 100), example: clip(p.example, 100),
    })).filter((p) => p.id),
  };
}

/** Jev chooses among the next few unfinished places (in curriculum order), so nobody skips the basics. */
export const LOOKAHEAD = 3;
const openPlaces = (input) => input.places.filter((p) => p.done < p.total);

export function buildPathRequest(input) {
  const open = openPlaces(input).slice(0, LOOKAHEAD);
  const questions = {};
  if (open.length > 1) {
    questions.next_place = {
      type: 'choice',
      instructions: 'Which place should this learner study next so they reach their own goal fastest and stay motivated? Prefer places that match their goal and the videos they watch; a beginner still needs the basics before advanced places, and a place whose grammar is far beyond `learner.grammar_known` is a leap, not a next step.',
      criteria: Object.fromEntries(open.map((p) => [p.id, `${p.name}: ${p.summary} Can do: ${p.canDos.join(', ')}. ${p.done}/${p.total} phrases done.`])),
    };
  }
  const skills = input.speakingOff ? Object.fromEntries(Object.entries(SKILLS).filter(([k]) => k !== 'speaking')) : SKILLS;
  questions.focus = {
    type: 'choice',
    instructions: 'Which skill should short practice cards in the video feed focus on next for this learner? Weigh their weakest skill (most wrong answers, fewest dots) against what their goal needs most.',
    criteria: skills,
  };
  input.phrases.forEach((p, n) => {
    questions[`fit_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is the Japanese phrase "${p.example}" ("${p.meaning}") especially useful for this learner right now, given their goal and the videos they like?`,
        good_when: 'they would likely need to say or understand it soon for their goal or interests.',
        bad_when: 'it rarely comes up for this goal, or it is too advanced for their level.',
      },
    };
  });
  return {
    model: MODEL,
    state: {
      learner: {
        goal: GOALS[input.goal],
        level: input.level || undefined,
        words_learned: input.wordsLearned,
        recent_video_titles: input.interests.length ? input.interests : undefined,
        skill_results: input.skills,
        question_stage: input.stage || undefined,
        grammar_known: input.grammarKnown.length ? input.grammarKnown : undefined,
      },
    },
    questions,
  };
}

/** Probabilities → path. Missing answers fall back to the given order (never an empty path). */
export function buildPath(input, answers) {
  const allOpen = openPlaces(input);
  const open = allOpen.slice(0, LOOKAHEAD);
  const probs = answers?.next_place?.probabilities ?? {};
  const pick = answers?.next_place?.choice;
  const first = open.find((p) => p.id === pick) ?? open[0];
  const restOpen = open.filter((p) => p !== first)
    .map((p, idx) => ({ p, s: (probs[p.id] ?? 0) - idx * 0.001 }))   // stable: ties keep the given order
    .sort((a, b) => b.s - a.s).map((x) => x.p)
    .concat(allOpen.slice(LOOKAHEAD));
  const done = input.places.filter((p) => p.done >= p.total);
  const order = [...done, ...(first ? [first] : []), ...restOpen].map((p) => p.id);

  const skillKeys = Object.keys(SKILLS).filter((k) => !(input.speakingOff && k === 'speaking'));
  const focus = skillKeys.includes(answers?.focus?.choice) ? answers.focus.choice : null;

  const fit = input.phrases.map((p, n) => ({ id: p.id, fit: typeof answers?.[`fit_${n}`]?.noul === 'number' ? answers[`fit_${n}`].noul : null }));
  const phrasePriority = fit.filter((f) => f.fit !== null).sort((a, b) => b.fit - a.fit).map((f) => f.id);
  return {
    order,
    next: first?.id ?? null,
    nextConfidence: answers?.next_place?.confidence ?? null,
    focus,
    focusProbabilities: answers?.focus?.probabilities ?? {},
    phrasePriority,
    fit,
  };
}

const cache = new Map();

export async function path(rawBody, opts = {}) {
  const input = parsePathInput(rawBody);
  const key = JSON.stringify(input);
  if (cache.has(key)) return { ...cache.get(key), cached: true };
  const started = Date.now();
  const response = await callJev(buildPathRequest(input), opts);
  const result = { ...buildPath(input, response.answers), goal: input.goal, model: response.model ?? null, ms: Date.now() - started };
  cache.set(key, result);
  if (cache.size > 500) cache.delete(cache.keys().next().value);
  return result;
}
