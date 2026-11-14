// Picks which caption words to teach in one Short, using TypeSafe Jev judgments.
//
// Division of labor:
//   app (on-device)  → finds candidate swaps: English word in a caption line ↔ bundled N5 entry
//   Jev (this file)  → two judgments per candidate, all in ONE request, answered in parallel:
//                        sense:  is the word used with this meaning here? ("bank" of a river ≠ 銀行)
//                        useful: is it a good word to teach a beginner at this moment of this video?
//   code (this file) → policy: thresholds, learner state, earliest-word-first, spacing, count.
// Jev never generates text; it only judges candidates code supplied.

export const TYPESAFE_URL = 'https://api.typesafe.ai/v1/systemone';
export const MODEL = process.env.TYPESAFE_MODEL || 'jev-latest';

export const MAX_CANDIDATES = 30;     // keeps each request small and fast (many-meaning words send one per sense)
export const SENSE_MIN = 0.6;         // below this, the swap would teach a wrong meaning
// A word with several Japanese senses ("poor": へた / まずしい / かわいそう) must have one sense clearly confirmed:
// teaching まずしい for "poor baby" is worse than teaching nothing on that line.
export const MULTI_SENSE_MIN = 0.75;
// Right meaning is not enough: Japanese must really say it with this word here (no idioms, no word-for-word).
export const FITS_MIN = 0.55;
const senseKey = (c) => `${c.cue}|${c.word.toLowerCase()}`;
const EARLY_WINDOW = 6;               // seconds: people swipe fast, first word must come early
const MIN_GAP = 2.5;                  // seconds between pauses

/** Validate and normalize the app's request. Throws on bad input. */
export function parseInput(body) {
  if (!body || typeof body !== 'object') throw new Error('body must be an object');
  const { videoId, cues, candidates } = body;
  if (typeof videoId !== 'string' || !videoId) throw new Error('videoId required');
  if (!Array.isArray(cues) || !Array.isArray(candidates)) throw new Error('cues and candidates must be arrays');
  return {
    videoId,
    title: typeof body.title === 'string' ? body.title.slice(0, 200) : '',
    wordsPerVideo: Math.min(3, Math.max(1, Number(body.wordsPerVideo) || 2)),
    playedTo: Math.max(0, Number(body.playedTo) || 0),
    cues: cues.slice(0, 200).map((c, i) => ({
      i: Number.isInteger(c.i) ? c.i : i,
      start: Number(c.start) || 0,
      end: Number(c.end) || 0,
      text: String(c.text || '').slice(0, 300),
      ja: c.ja ? String(c.ja).slice(0, 300) : undefined,
    })),
    candidates: candidates.map((c) => ({
      cue: Number(c.cue),
      entryId: String(c.entryId),
      word: String(c.word || ''),
      kana: String(c.kana || ''),
      meaning: String(c.meaning || ''),
      status: ['new', 'learning', 'due', 'known'].includes(c.status) ? c.status : 'new',
    })).filter((c) => Number.isInteger(c.cue)),
  };
}

/** Which candidates are worth asking Jev about: still ahead in the video, not known, early first. */
export function shortlist(input) {
  const byCue = new Map(input.cues.map((c) => [c.i, c]));
  const seen = new Set();
  return input.candidates
    .filter((c) => {
      const cue = byCue.get(c.cue);
      if (!cue || cue.end <= input.playedTo + 0.4) return false;
      const key = `${c.cue}:${c.entryId}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((a, b) => (a.status === 'known') - (b.status === 'known') || a.cue - b.cue)
    .slice(0, MAX_CANDIDATES);
}

/** One Jev request: state = the video's captions; two Nouls per candidate. */
export function buildRequest(input, list) {
  const questions = {};
  const groups = new Map();
  for (const c of list) groups.set(senseKey(c), [...(groups.get(senseKey(c)) ?? []), c]);
  list.forEach((c, n) => {
    const where = `\`captions[${c.cue}]\``;
    const others = (groups.get(senseKey(c)) ?? []).filter((o) => o !== c);
    questions[`sense_${n}`] = {
      type: 'noul',
      instructions: {
        question: `In ${where}, is the English word "${c.word}" used with the meaning "${c.meaning}", so that it could be replaced by the Japanese word ${c.kana}?`,
        ...(others.length ? {
          contrast: `"${c.word}" has other Japanese words for other meanings: ${others.map((o) => `${o.kana} ("${o.meaning}")`).join(', ')}. Say yes only if ${c.kana} is the one that fits this line (for example "poor baby" is かわいそう "pitiable", not まずしい "needy" or へた "unskillful").`,
        } : {}),
        evidence: `${where}.en is the English caption; ${where}.ja, when present, is a machine translation of the same line.`,
        say_yes_when: 'the word carries this meaning in the line. A question word that starts a direct question counts, even without a question mark (for example "What is that supposed to be?", "why did you do that").',
        say_no_when: [
          'the word is part of a fixed phrase, a name, or has a different meaning here (for example "like" as in "looks like", "bank" of a river).',
          'a question word (what, who, where, why, when, how, which) is not asking a question: relative or embedded uses such as "look what I built", "I know what you mean", "the guy who won", "when I was young" are NO, because Japanese does not use the question word there.',
        ],
      },
    };
    questions[`fits_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Would a Japanese speaker really use ${c.kana} ("${c.meaning}") to say what "${c.word}" says in ${where}, so that learning ${c.kana} from this line teaches correct Japanese?`,
        say_yes_when: 'Japanese expresses this idea with this word too (maybe with different grammar around it).',
        say_no_when: [
          'the English word is part of an idiom or set phrase that Japanese says completely differently ("good morning" is おはよう, not いい; "make sense", "my bad", "break a leg", "kind of", "hang out").',
          'it is a word-for-word translation that sounds wrong in Japanese, or Japanese would leave the word out or use a different word in this situation ("I\'m good" meaning "no thanks" is not いい; "poor baby" as pity is かわいそう, not まずしい).',
        ],
      },
    };
    questions[`useful_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is "${c.word}" (Japanese ${c.kana}, "${c.meaning}") in ${where} a good word to teach a complete beginner of Japanese while they watch this short video?`,
        good_when: 'the word carries the meaning of the line, is clearly spoken, and is common in everyday conversation.',
        bad_when: 'the word is filler, a tiny function word that adds little, or the line is noise like lyrics fragments or [Music].',
      },
    };
  });
  return {
    model: MODEL,
    state: {
      video_title: input.title,
      captions: Object.fromEntries(
        input.cues.map((c) => [c.i, c.ja ? { en: c.text, ja: c.ja } : { en: c.text }]),
      ),
    },
    questions,
  };
}

/** Policy: combine Jev probabilities with the learner state and timing rules. */
export function pickTargets(input, list, answers) {
  const byCue = new Map(input.cues.map((c) => [c.i, c]));
  const learnerBonus = { new: 0.25, due: 0.35, learning: 0.05, known: -1 };
  const scored = list.map((c, n) => {
    const sense = answers?.[`sense_${n}`]?.noul;
    const useful = answers?.[`useful_${n}`]?.noul;
    const fits = answers?.[`fits_${n}`]?.noul;
    return {
      ...c,
      start: byCue.get(c.cue)?.start ?? 0,
      sense: typeof sense === 'number' ? sense : null,
      useful: typeof useful === 'number' ? useful : null,
      fits: typeof fits === 'number' ? fits : null,
      value: (typeof useful === 'number' ? useful : 0) + (learnerBonus[c.status] ?? 0),
    };
  });
  // Many-meaning words: only the best-fitting sense on each line survives, and only when clearly confirmed.
  const best = new Map();
  for (const s of scored) {
    const k = senseKey(s), b = best.get(k);
    if (s.sense !== null && (!b || s.sense > b.sense)) best.set(k, s);
  }
  const groupSize = new Map();
  for (const s of scored) groupSize.set(senseKey(s), (groupSize.get(senseKey(s)) ?? 0) + 1);
  const ok = scored.filter((s) => s.sense !== null && s.status !== 'known' && (s.fits === null || s.fits >= FITS_MIN)
    && (groupSize.get(senseKey(s)) > 1 ? best.get(senseKey(s)) === s && s.sense >= MULTI_SENSE_MIN : s.sense >= SENSE_MIN));

  const picked = [];
  const clashes = (c) => picked.some((p) => p.cue === c.cue || p.entryId === c.entryId || Math.abs(p.start - c.start) < MIN_GAP);
  // 1) First word: the most valuable one inside the early window; else the earliest acceptable one.
  const early = ok.filter((c) => c.start - input.playedTo <= EARLY_WINDOW).sort((a, b) => b.value - a.value);
  const first = early[0] ?? [...ok].sort((a, b) => a.start - b.start)[0];
  if (first) picked.push(first);
  // 2) The rest by value, spaced out.
  for (const c of [...ok].sort((a, b) => b.value - a.value)) {
    if (picked.length >= input.wordsPerVideo) break;
    if (!clashes(c)) picked.push(c);
  }
  return {
    targets: picked.sort((a, b) => a.start - b.start).map((c) => ({ entryId: c.entryId, cue: c.cue })),
    judged: scored.map(({ cue, entryId, word, sense, useful, fits }) => ({ cue, entryId, word, sense, useful, fits })),
  };
}

/** Call TypeSafe. API key stays on the server. */
export async function callJev(body, { apiKey = process.env.TYPESAFE_API_KEY, fetchImpl = fetch, timeoutMs = 8000, headers = {} } = {}) {
  if (!apiKey) throw Object.assign(new Error('TYPESAFE_API_KEY is not set'), { status: 503 });
  for (let attempt = 0; ; attempt++) {
    const res = await fetchImpl(TYPESAFE_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${apiKey}`, ...headers },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if ((res.status === 429 || res.status === 529) && attempt < 2) {
      const wait = Number(res.headers.get('retry-after')) * 1000 || 300 * 2 ** attempt;
      await new Promise((r) => setTimeout(r, Math.min(wait, 2000)));
      continue;
    }
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw Object.assign(new Error(`TypeSafe ${res.status}: ${text.slice(0, 300)}`), { status: 502 });
    }
    return res.json();
  }
}

const cache = new Map();   // videoId + learner-relevant input → result (per server instance)

/** Full pipeline for one video. */
export async function lesson(rawBody, opts = {}) {
  const input = parseInput(rawBody);
  const list = shortlist(input);
  if (list.length === 0) return { videoId: input.videoId, targets: [], judged: [], pickedBy: 'jev', model: null };

  const key = JSON.stringify([input.videoId, input.wordsPerVideo, Math.floor(input.playedTo), list.map((c) => [c.cue, c.entryId, c.status])]);
  if (cache.has(key)) return { ...cache.get(key), cached: true };

  const started = Date.now();
  const response = await callJev(buildRequest(input, list), opts);
  const result = {
    videoId: input.videoId,
    ...pickTargets(input, list, response.answers),
    pickedBy: 'jev',
    model: response.model ?? null,
    usage: response.usage ?? null,
    ms: Date.now() - started,
  };
  cache.set(key, result);
  if (cache.size > 2000) cache.delete(cache.keys().next().value);
  return result;
}
