// Japanese speech for the app: Google Gemini 3.8 Flash TTS (key GEMINI_API_KEY), returned as WAV (the iPhone plays it natively).
// Optional alternative, off unless TTS_PROVIDER=kokoro: fal.ai Kokoro TTS (Japanese), key FAL_KEY.
// If the chosen provider fails, the other one is tried when its key is set.
// Keys stay on the server; the app caches every clip on the device.
// Every clip is also saved in shared storage (see clipStore.js): generated once, then reused by every user.
import { blobStore, clipPath } from './clipStore.js';

const GEMINI_API = 'https://generativelanguage.googleapis.com/v1beta/models';
const FAL_API = 'https://fal.run';
export const DEFAULTS = {
  gemini: { model: 'gemini-3.8-flash-tts', voice: 'Kore' },
  kokoro: { model: 'fal-ai/kokoro/japanese', voice: 'jf_alpha' },   // voices: jf_alpha, jf_gongitsune, jf_nezumi, jf_tebukuro, jm_kumo
};
const MAX_CHARS = 80;
// Kana, kanji, Japanese punctuation, full-width forms, plus spaces and basic punctuation.
const ALLOWED = /^[　-ヿ㐀-䶿一-鿿＀-￯\s!?.,ー〜…]+$/u;
const JAPANESE = /[぀-ヿ㐀-䶿一-鿿]/u;

const cache = new Map();   // per instance: provider|voice|text → Uint8Array (WAV)
const CACHE_MAX = 300;

export function validate(text) {
  if (typeof text !== 'string') return 'text required';
  const t = text.trim();
  if (!t || t.length > MAX_CHARS) return `text must be 1–${MAX_CHARS} characters`;
  if (!JAPANESE.test(t) || !ALLOWED.test(t)) return 'Japanese text only';
  return null;
}

/** Raw 16-bit little-endian mono PCM → a WAV file. */
export function pcmToWav(pcm, sampleRate = 24000, channels = 1) {
  const header = Buffer.alloc(44);
  const byteRate = sampleRate * channels * 2;
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);          // fmt chunk size
  header.writeUInt16LE(1, 20);           // PCM
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(channels * 2, 32);
  header.writeUInt16LE(16, 34);          // bits per sample
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, Buffer.from(pcm)]);
}

/** Gemini's inline audio → WAV bytes (passes WAV through, wraps PCM like "audio/L16;codec=pcm;rate=24000"). */
export function toWav(base64, mimeType = '') {
  const bytes = Buffer.from(base64, 'base64');
  if (bytes.subarray(0, 4).toString() === 'RIFF') return bytes;
  const rate = Number(/rate=(\d+)/.exec(mimeType)?.[1]) || 24000;
  return pcmToWav(bytes, rate);
}

const fail = (msg, status) => Object.assign(new Error(msg), { status });

async function geminiSpeech(text, { apiKey, voice, model, fetchImpl, timeoutMs }) {
  const res = await fetchImpl(`${GEMINI_API}/${encodeURIComponent(model)}:generateContent`, {
    method: 'POST',
    headers: { 'x-goog-api-key': apiKey, 'content-type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text }] }],
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
      },
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw fail(`gemini tts ${res.status}: ${(await res.text()).slice(0, 200)}`, res.status === 429 ? 429 : 502);
  const data = await res.json().catch(() => null);
  const inline = data?.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data)?.inlineData;
  if (!inline) throw fail('gemini tts: no audio in reply', 502);
  return toWav(inline.data, inline.mimeType);
}

/** fal.ai Kokoro: a synchronous call returns a URL to the WAV, which is then downloaded. */
async function kokoroSpeech(text, { apiKey, voice, model, fetchImpl, timeoutMs }) {
  const res = await fetchImpl(`${FAL_API}/${model}`, {
    method: 'POST',
    headers: { authorization: `Key ${apiKey}`, 'content-type': 'application/json' },
    body: JSON.stringify({ prompt: text, voice }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw fail(`kokoro tts ${res.status}: ${(await res.text()).slice(0, 200)}`, res.status === 429 ? 429 : 502);
  const url = (await res.json().catch(() => null))?.audio?.url;
  if (!url) throw fail('kokoro tts: no audio in reply', 502);
  const file = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) });
  if (!file.ok) throw fail(`kokoro tts: audio download ${file.status}`, 502);
  const bytes = Buffer.from(await file.arrayBuffer());
  if (bytes.length < 44 || bytes.subarray(0, 4).toString() !== 'RIFF') throw fail('kokoro tts: not a WAV file', 502);
  return bytes;
}

const PROVIDERS = { gemini: geminiSpeech, kokoro: kokoroSpeech };

export async function tts({ text }, {
  provider = process.env.TTS_PROVIDER,
  falKey = process.env.FAL_KEY,
  geminiKey = process.env.GEMINI_API_KEY,
  kokoroVoice = process.env.KOKORO_VOICE || DEFAULTS.kokoro.voice,
  geminiVoice = process.env.GEMINI_TTS_VOICE || DEFAULTS.gemini.voice,
  geminiModel = process.env.GEMINI_TTS_MODEL || DEFAULTS.gemini.model,
  fetchImpl = fetch,
  timeoutMs = 8000,
  store = blobStore(),
} = {}) {
  const bad = validate(text);
  if (bad) throw fail(bad, 400);
  const t = text.trim();
  const configs = {
    kokoro: falKey && { apiKey: falKey, voice: kokoroVoice, model: DEFAULTS.kokoro.model },
    gemini: geminiKey && { apiKey: geminiKey, voice: geminiVoice, model: geminiModel },
  };
  const first = PROVIDERS[provider] ? provider : 'gemini';
  const order = [first, first === 'kokoro' ? 'gemini' : 'kokoro'].filter((p) => configs[p]);
  if (order.length === 0) throw fail('speech not configured', 503);

  const remember = (key, audio) => {
    if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
    cache.set(key, audio);
  };

  let lastError;
  for (const p of order) {
    const key = `${p}|${configs[p].voice}|${t}`;
    if (cache.has(key)) return { audio: cache.get(key), cached: true, shared: false, provider: p };
    // Shared storage: someone already asked for these words → reuse their clip (no new generation).
    const path = clipPath({ provider: p, voice: configs[p].voice, model: configs[p].model, text: t });
    const saved = store ? await store.get(path) : null;
    if (saved) {
      const audio = new Uint8Array(saved);
      remember(key, audio);
      return { audio, cached: true, shared: true, provider: p };
    }
    try {
      const audio = new Uint8Array(await PROVIDERS[p](t, { ...configs[p], fetchImpl, timeoutMs }));
      remember(key, audio);
      if (store) await store.put(path, audio);   // first time anyone asked: save it for everyone
      return { audio, cached: false, shared: false, provider: p };
    } catch (e) {
      lastError = e;   // try the other provider
    }
  }
  throw lastError;
}
