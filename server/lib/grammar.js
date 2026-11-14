// Grammar chunks from any Short: the step between a single word and a whole sentence.
//
// The app finds grammar points on-device in YouTube's Japanese line for a caption (を, 〜たい, 〜ている …):
// the piece to blank out, where it sits, and confusable pieces to offer instead. Jev judges, in ONE request:
//   uses_n:  is the piece really this grammar point here? (わかった is not an い-adjective past; の can be many things)
//   ja_l:    is the machine-translated Japanese a correct, natural rendering of the English line? (once per line)
//   fit_n:   is this a clear, typical example of the point for THIS learner right now?
//   alt_n_k: would distractor k ALSO be correct here with the same meaning? (は vs が, から vs ので …)
//            Those are dropped: a cloze question must have exactly one right answer.
// Code ranks (fit × uses × ja + learner bonus) and keeps candidates with ≥ 2 clearly-wrong distractors.
// Jev never writes text; it only judges pieces code found.
import { MODEL, callJev } from './lesson.js';

export const MAX_CANDIDATES = 8;
export const USES_MIN = 0.6;
export const JA_MIN = 0.6;
export const FIT_MIN = 0.45;
export const ALT_MAX = 0.35;     // a distractor with ≥ this chance of also being right is removed
const MIN_DISTRACTORS = 2;

export function parseGrammarInput(body) {
  if (!body || typeof body.videoId !== 'string' || !body.videoId) throw new Error('videoId required');
  if (!Array.isArray(body.lines) || !Array.isArray(body.candidates)) throw new Error('lines and candidates must be arrays');
  const clip = (s, n) => (typeof s === 'string' ? s.slice(0, n) : '');
  const lines = body.lines
    .map((l) => ({
      i: Number(l.i), en: clip(l.en, 200).trim(), ja: clip(l.ja, 120).trim(),
      // The line's other words with meanings; known = the learner answered it right before.
      words: (Array.isArray(l.words) ? l.words : []).slice(0, 12)
        .map((w) => ({ ja: clip(w?.ja, 20), meaning: clip(w?.meaning, 40), known: Boolean(w?.known) }))
        .filter((w) => w.ja),
    }))
    .filter((l) => Number.isInteger(l.i) && l.en && l.ja)
    .slice(0, 16);
  const lineIds = new Set(lines.map((l) => l.i));
  const learner = body.learner && typeof body.learner === 'object' ? body.learner : {};
  return {
    videoId: body.videoId,
    title: clip(body.title, 200),
    learner: {
      stage: clip(learner.stage, 40) || 'chunks',
      wordsLearned: Math.max(0, Number(learner.wordsLearned) || 0),
      known: (Array.isArray(learner.known) ? learner.known : []).slice(0, 30).map((s) => clip(String(s), 60)),
    },
    lines,
    candidates: body.candidates
      .map((c) => ({
        line: Number(c.line),
        point: clip(String(c.point || ''), 40),
        title: clip(c.title, 60),
        meaning: clip(c.meaning, 160),
        piece: clip(c.piece, 12),
        before: clip(c.before, 40),
        after: clip(c.after, 40),
        distractors: (Array.isArray(c.distractors) ? c.distractors : []).slice(0, 4).map((d) => clip(String(d), 12)).filter(Boolean),
        status: ['new', 'learning', 'due', 'known'].includes(c.status) ? c.status : 'new',
      }))
      .filter((c) => lineIds.has(c.line) && c.point && c.piece && c.distractors.length >= MIN_DISTRACTORS)
      .slice(0, MAX_CANDIDATES),
  };
}

export function buildGrammarRequest(input) {
  const questions = {};
  const usedLines = [...new Set(input.candidates.map((c) => c.line))];
  usedLines.forEach((i) => {
    const where = `\`lines[${i}]\``;
    questions[`ja_${i}`] = {
      type: 'noul',
      instructions: {
        question: `Is ${where}.ja a correct and natural Japanese way to say ${where}.en?`,
        evidence: `${where}.ja is a machine translation of the English caption ${where}.en from a short video.`,
        say_no_when: 'the meaning changed, words are missing, it is unnatural word-for-word Japanese, or it is not Japanese.',
      },
    };
  });
  input.candidates.forEach((c, n) => {
    const where = `\`lines[${c.line}]\``;
    const marked = `${c.before}【${c.piece}】${c.after}`;
    questions[`uses_${n}`] = {
      type: 'noul',
      instructions: {
        question: `In ${where}.ja, the marked part in 「${marked}」 is 「${c.piece}」. Is it used here as the grammar point "${c.title}" (${c.meaning})?`,
        say_no_when: [
          'the same characters are part of a different word or a different grammar (for example わかった is the verb わかる, not an い-adjective; から in からだ "body" is not "because").',
          'the line is cut off so the grammar cannot be seen clearly.',
        ],
      },
    };
    questions[`fit_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is ${where} a clear, typical example for teaching "${c.title}" (${c.meaning}) to this learner right now, as a fill-in-the-blank on 「${c.piece}」?`,
        evidence: `\`learner\` describes what they already know; ${where}.words lists the other words in the line with their meanings and whether the learner already knows each one (new ones are translated on the card).`,
        good_when: 'the line is short and everyday, the English makes the right answer clear, and the other words are ones the learner knows, so the only new thing is the grammar.',
        bad_when: 'the line is long, slang-heavy, lyrics, a name, the English does not tell you which piece is right, or understanding it depends on several words the learner does not know.',
      },
    };
    c.distractors.forEach((d, k) => {
      questions[`alt_${n}_${k}`] = {
        type: 'noul',
        instructions: {
          question: `If 「${c.piece}」 in 「${marked}」 were replaced by 「${d}」, would ${where}.ja still be correct, natural Japanese that means the same as ${where}.en?`,
          say_yes_when: 'a Japanese speaker would accept it as an equally good answer for this English line.',
          say_no_when: 'it becomes ungrammatical, unnatural, or changes the meaning (tense, negation, who does what, want vs do).',
        },
      };
    });
  });
  return {
    model: MODEL,
    state: {
      video_title: input.title,
      learner: {
        stage: input.learner.stage,
        words_learned: input.learner.wordsLearned,
        grammar_known: input.learner.known.length ? input.learner.known : undefined,
      },
      lines: Object.fromEntries(input.lines.filter((l) => usedLines.includes(l.i))
        .map((l) => [l.i, l.words.length ? { en: l.en, ja: l.ja, words: l.words } : { en: l.en, ja: l.ja }])),
    },
    questions,
  };
}

/** Probabilities → the best one or two cloze questions, each with only clearly-wrong distractors. */
export function rankGrammar(input, answers) {
  const num = (k) => (typeof answers?.[k]?.noul === 'number' ? answers[k].noul : null);
  const bonus = { due: 0.3, new: 0.15, learning: 0.05, known: -0.4 };
  const judged = input.candidates.map((c, n) => {
    const alts = c.distractors.map((d, k) => ({ d, p: num(`alt_${n}_${k}`) }));
    return {
      line: c.line,
      point: c.point,
      piece: c.piece,
      uses: num(`uses_${n}`),
      ja: num(`ja_${c.line}`),
      fit: num(`fit_${n}`),
      distractors: alts.filter((a) => a.p !== null && a.p < ALT_MAX).map((a) => a.d),
      rejected: alts.filter((a) => a.p === null || a.p >= ALT_MAX).map((a) => a.d),
      status: c.status,
    };
  });
  const ok = judged.filter((j) => j.uses !== null && j.ja !== null && j.fit !== null
    && j.uses >= USES_MIN && j.ja >= JA_MIN && j.fit >= FIT_MIN && j.distractors.length >= MIN_DISTRACTORS);
  const score = (j) => j.fit * j.uses * j.ja + (bonus[j.status] ?? 0);
  const picks = [];
  for (const j of ok.sort((a, b) => score(b) - score(a))) {
    if (picks.length >= 2) break;
    if (picks.some((p) => p.line === j.line || p.point === j.point)) continue;   // one per line, one per point
    picks.push({ line: j.line, point: j.point, piece: j.piece, distractors: j.distractors.slice(0, 3), uses: j.uses, ja: j.ja, fit: j.fit });
  }
  return { picks, judged };
}

const cache = new Map();

export async function grammar(rawBody, opts = {}) {
  const input = parseGrammarInput(rawBody);
  if (input.candidates.length === 0) return { videoId: input.videoId, picks: [], judged: [], model: null };
  const key = JSON.stringify([input.videoId, input.learner.stage, input.candidates.map((c) => [c.line, c.point, c.piece, c.status, c.distractors])]);
  if (cache.has(key)) return { ...cache.get(key), cached: true };
  const started = Date.now();
  const response = await callJev(buildGrammarRequest(input), opts);
  const result = { videoId: input.videoId, ...rankGrammar(input, response.answers), model: response.model ?? null, ms: Date.now() - started };
  cache.set(key, result);
  if (cache.size > 2000) cache.delete(cache.keys().next().value);
  return result;
}
