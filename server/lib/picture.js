// "Picture question" for Shorts with no talking, built from a screenshot of the video frame.
//
// Jev never writes the question. Code supplies the word candidates; Jev judges them against the frame:
//   pass 1 (one request, parallel):  present_i  Noul   — is this thing clearly visible in the frame?
//   pass 2 (one request, parallel):  where_k    Box    — where is each of the top visible things?
//                                    color_k    Choice — its main color, from the Japanese color words we teach
// The app turns this into "What's this?" (outlined), "What color is it?" and "Which one can you see?".
// Images and Box are a TypeSafe preview ("Dreamer-ready"): sent with the TypeSafe-Danger-Zone-Images header.
import { callJev, MODEL } from './lesson.js';

export const PRESENT_MIN = 0.8;     // "clearly visible": below this we don't ask about it
export const ABSENT_MAX = 0.03;     // "clearly not there": safe for a "No" answer
export const COLOR_MIN = 0.6;       // Choice confidence needed to ask the color
const MAX_CANDIDATES = 60;
const MAX_IMAGE_BYTES = 2_000_000;

export function parsePictureInput(body) {
  if (!body || typeof body !== 'object') throw new Error('body must be an object');
  const { videoId, image, candidates } = body;
  if (typeof videoId !== 'string' || !videoId) throw new Error('videoId required');
  if (!image || typeof image.data_base64 !== 'string' || !['jpg', 'jpeg', 'png'].includes(image.format)) {
    throw new Error('image {format: jpg|png, data_base64} required');
  }
  if (image.data_base64.length * 0.75 > MAX_IMAGE_BYTES) throw Object.assign(new Error('image too large'), { status: 413 });
  if (!Array.isArray(candidates) || candidates.length === 0) throw new Error('candidates required');
  const clean = (c) => ({
    entryId: String(c.entryId),
    en: String(c.en || '').slice(0, 40),
    status: ['new', 'learning', 'due', 'known'].includes(c.status) ? c.status : 'new',
  });
  return {
    videoId,
    title: typeof body.title === 'string' ? body.title.slice(0, 200) : '',
    image: { format: image.format === 'jpeg' ? 'jpg' : image.format, data_base64: image.data_base64 },
    candidates: candidates.slice(0, MAX_CANDIDATES).map(clean).filter((c) => c.en),
    colors: Array.isArray(body.colors) ? body.colors.slice(0, 12).map(clean).filter((c) => c.en) : [],
    // Words the app asked about recently: not chosen for the outline/color pass unless nothing else is visible.
    avoid: Array.isArray(body.avoid) ? body.avoid.slice(0, 30).map(String) : [],
  };
}

const FRAME_REF = 'frame-7f3a9c21';   // long, unique reference string (matched as plain text in the request)

const withFrame = (input, questions) => ({
  model: MODEL,
  state: { frame: FRAME_REF, video_title: input.title || undefined },
  assets: { [FRAME_REF]: { type: 'image', format: input.image.format, data_base64: input.image.data_base64 } },
  questions,
});

const VIDEO_ONLY = 'Judge only the video picture itself: ignore app buttons, captions, on-screen text, logos and stickers.';

export function buildPresenceRequest(input) {
  const questions = {};
  input.candidates.forEach((c, n) => {
    questions[`present_${n}`] = {
      type: 'noul',
      instructions: {
        question: `Is there clearly a ${c.en} visible in \`frame\` (a frame from a short video)?`,
        say_yes_when: `a beginner looking at the picture would agree it shows a ${c.en}, without needing to search for it.`,
        say_no_when: `the ${c.en} is absent, tiny, hidden, ambiguous, or only appears as written text. ${VIDEO_ONLY}`,
      },
    };
  });
  return withFrame(input, questions);
}

export function buildDetailRequest(input, things) {
  const criteria = Object.fromEntries(input.colors.map((c) => [c.entryId, `Mostly ${c.en}.`]));
  criteria.other = 'Another color, or several colors with no main one.';
  const questions = {};
  things.forEach((t, k) => {
    questions[`where_${k}`] = {
      type: 'box',
      // Tight: only the object itself, not the person wearing/holding it or nearby things (a hat, not the head).
      instructions: `a tight box around only the most prominent ${t.en} in \`frame\`: just that object, excluding the person wearing or holding it and anything next to it`,
    };
    if (input.colors.length) {
      questions[`color_${k}`] = {
        type: 'choice',
        instructions: `What is the main color of the most prominent ${t.en} in \`frame\`? ${VIDEO_ONLY}`,
        criteria,
      };
    }
  });
  return withFrame(input, questions);
}

/** Policy: which visible thing to ask about. Learner words first, then new ones; never known words if avoidable. */
export function chooseTarget(input, answers) {
  const bonus = { due: 0.1, learning: 0.06, new: 0.03, known: -0.2 };
  const judged = input.candidates.map((c, n) => ({ ...c, p: answers?.[`present_${n}`]?.noul ?? null }));
  const visible = judged.filter((c) => c.p !== null && c.p >= PRESENT_MIN)
    .sort((a, b) => (b.p + bonus[b.status]) - (a.p + bonus[a.status]));
  const absent = judged.filter((c) => c.p !== null && c.p <= ABSENT_MAX).map((c) => c.entryId);
  return { judged, visible, absent };
}

/** In almost every frame (people, background). The app never asks about them, so don't spend outlines on them. */
export const COMMON = new Set(['person', 'man', 'woman', 'boy', 'girl', 'child', 'baby', 'sky', 'tree', 'shirt']);

/**
 * Which visible things get the detail pass (box + color): a weighted random draw, not always the top 3,
 * so the same few words (a person, the sky) don't come up in every Short.
 */
export function pickForDetail(visible, avoid, n = 3, random = Math.random) {
  const useful = visible.filter((c) => !COMMON.has(c.entryId));
  const fresh = useful.filter((c) => !avoid.includes(c.entryId));
  const pool = (fresh.length ? fresh : useful).map((c) => ({ c, w: c.p }));
  const out = [];
  while (out.length < n && pool.length) {
    let r = random() * pool.reduce((s, x) => s + x.w, 0);
    const i = Math.max(0, pool.findIndex((x) => (r -= x.w) <= 0));
    out.push(pool.splice(i, 1)[0].c);
  }
  return out;
}

const cache = new Map();

export async function picture(rawBody, opts = {}) {
  const input = parsePictureInput(rawBody);
  const key = `${input.videoId}:${input.image.data_base64.length}:${input.candidates.map((c) => c.entryId + c.status).join(',')}:${input.avoid.join(',')}`;
  if (cache.has(key)) return { ...cache.get(key), cached: true };

  const jevOpts = { ...opts, headers: { 'TypeSafe-Danger-Zone-Images': 'true' }, timeoutMs: opts.timeoutMs ?? 15000 };
  const started = Date.now();
  const first = await callJev(buildPresenceRequest(input), jevOpts);
  const { judged, visible, absent } = chooseTarget(input, first.answers);

  // Details for 3 visible things drawn at random (one request; the app picks which to ask about).
  const top = pickForDetail(visible, input.avoid, 3, opts.random);
  let things = [];
  if (top.length) {
    const second = await callJev(buildDetailRequest(input, top), jevOpts);
    things = top.map((t, k) => {
      const b = second.answers?.[`where_${k}`];
      const c = second.answers?.[`color_${k}`];
      const color = c?.choice && c.choice !== 'other' && (c.confidence ?? 0) >= COLOR_MIN
        ? { entryId: c.choice, confidence: c.confidence } : null;
      return { entryId: t.entryId, p: t.p, box: b?.box ? { ...b.box, confidence: b.confidence ?? 0 } : null, color };
    });
  }

  const result = {
    videoId: input.videoId,
    things,
    visible: visible.map((c) => c.entryId),
    absent,
    judged: judged.map(({ entryId, p }) => ({ entryId, p })),
    model: first.model ?? MODEL,
    ms: Date.now() - started,
  };
  cache.set(key, result);
  if (cache.size > 500) cache.delete(cache.keys().next().value);
  return result;
}
