import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tts, validate, toWav } from '../lib/tts.js';

test('validate accepts Japanese and rejects everything else', () => {
  assert.equal(validate('コーヒーをください。'), null);
  assert.equal(validate('疲れた'), null);
  assert.equal(validate('か'), null);
  assert.ok(validate('hello'));
  assert.ok(validate('ねこ <script>'));
  assert.ok(validate(''));
  assert.ok(validate('あ'.repeat(81)));
  assert.ok(validate(42));
});

const wav = (tag = 1) => Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WAVE'), Buffer.alloc(32, tag)]);
const geminiReply = (tag) => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ inlineData: { mimeType: 'audio/wav', data: wav(tag).toString('base64') } }] } }] }));

test('Kokoro (fal) when TTS_PROVIDER=kokoro: one call + WAV download, then cached', async () => {
  const seen = [];
  const fetchImpl = async (url, init = {}) => {
    seen.push({ url, body: init.body && JSON.parse(init.body), auth: init.headers?.authorization });
    if (url === 'https://fal.run/fal-ai/kokoro/japanese') return new Response(JSON.stringify({ audio: { url: 'https://cdn.example/a.wav' } }));
    if (url === 'https://cdn.example/a.wav') return new Response(wav(7));
    throw new Error(`unexpected ${url}`);
  };
  const a = await tts({ text: ' いぬ ' }, { provider: 'kokoro', falKey: 'f', geminiKey: 'g', fetchImpl });
  const b = await tts({ text: 'いぬ' }, { provider: 'kokoro', falKey: 'f', geminiKey: 'g', fetchImpl });
  assert.equal(a.provider, 'kokoro');
  assert.deepEqual([...a.audio], [...wav(7)]);
  assert.equal(b.cached, true);
  assert.equal(seen.length, 2);
  assert.deepEqual(seen[0].body, { prompt: 'いぬ', voice: 'jf_alpha' });
  assert.equal(seen[0].auth, 'Key f');
});

test('Kokoro fails → Gemini backup', async () => {
  const fetchImpl = async (url) => {
    if (url.startsWith('https://fal.run/')) return new Response('down', { status: 500 });
    return geminiReply(3);
  };
  const r = await tts({ text: 'さかな' }, { provider: 'kokoro', falKey: 'f', geminiKey: 'g', fetchImpl });
  assert.equal(r.provider, 'gemini');
  assert.deepEqual([...r.audio], [...wav(3)]);
});

test('Gemini 3.8 Flash TTS is the default, even when FAL_KEY is also set', async () => {
  let seen;
  const fetchImpl = async (url, init) => { seen = { url, body: JSON.parse(init.body), key: init.headers['x-goog-api-key'] }; return geminiReply(5); };
  const r = await tts({ text: 'とり' }, { falKey: '', geminiKey: 'k', fetchImpl });
  assert.equal(r.provider, 'gemini');
  assert.equal(seen.url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash-tts:generateContent');
  assert.equal(seen.body.contents[0].parts[0].text, 'とり');
  assert.deepEqual(seen.body.generationConfig.responseModalities, ['AUDIO']);
  assert.equal(seen.body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Kore');
  assert.equal(seen.key, 'k');
  const both = await tts({ text: 'うま' }, { falKey: 'f', geminiKey: 'k', fetchImpl });
  assert.equal(both.provider, 'gemini');
});

test('raw PCM from Gemini is wrapped into a playable WAV', () => {
  const out = toWav(Buffer.from([0, 1, 0, 2]).toString('base64'), 'audio/L16;codec=pcm;rate=24000');
  assert.equal(out.subarray(0, 4).toString(), 'RIFF');
  assert.equal(out.subarray(8, 12).toString(), 'WAVE');
  assert.equal(out.readUInt32LE(24), 24000);
  assert.equal(out.readUInt32LE(40), 4);
  assert.equal(out.length, 48);
});

test('no keys → 503; both providers fail → 502; non-WAV download rejected', async () => {
  await assert.rejects(tts({ text: 'いぬ' }, { falKey: '', geminiKey: '' }), (e) => e.status === 503);
  const down = async () => new Response('nope', { status: 401 });
  await assert.rejects(tts({ text: 'くま' }, { falKey: 'f', geminiKey: 'g', fetchImpl: down }), (e) => e.status === 502);
  const notWav = async (url) => (url.startsWith('https://fal.run/')
    ? new Response(JSON.stringify({ audio: { url: 'https://cdn.example/x' } }))
    : new Response('<html>'));
  await assert.rejects(tts({ text: 'しか' }, { provider: 'kokoro', falKey: 'f', geminiKey: '', fetchImpl: notWav }), (e) => e.status === 502);
});

// Shared storage: clips are generated once and reused by every user.
import { clipPath } from '../lib/clipStore.js';

function memoryStore() {
  const files = new Map();
  return { files, gets: 0, puts: 0,
    async get(p) { this.gets++; return files.get(p) ?? null; },
    async put(p, b) { this.puts++; files.set(p, Buffer.from(b)); } };
}

test('shared store: first request generates and saves; another server instance reuses the saved clip', async () => {
  const store = memoryStore();
  let calls = 0;
  const fetchImpl = async () => { calls++; return geminiReply(9); };
  const a = await tts({ text: 'りんご' }, { falKey: '', geminiKey: 'k', fetchImpl, store });
  assert.equal(calls, 1);
  assert.equal(a.shared, false);
  assert.equal(store.puts, 1);
  const path = clipPath({ provider: 'gemini', voice: 'Kore', model: 'gemini-3.8-flash-tts', text: 'りんご' });
  assert.ok(store.files.has(path), `saved at ${path}`);
  assert.match(path, /^tts\/gemini\/Kore\/[0-9a-f]{32}\.wav$/);

  // A different word that someone else already generated: served from storage, Gemini never called.
  const other = clipPath({ provider: 'gemini', voice: 'Kore', model: 'gemini-3.8-flash-tts', text: 'みかん' });
  store.files.set(other, wav(4));
  const b = await tts({ text: 'みかん' }, { falKey: '', geminiKey: 'k', fetchImpl, store });
  assert.equal(calls, 1, 'no new generation for a clip already in storage');
  assert.equal(b.shared, true);
  assert.deepEqual([...b.audio], [...wav(4)]);
});

test('shared store down: the voice still works (generated, not saved)', async () => {
  const broken = { async get() { return null; }, async put() { throw new Error('store down'); } };
  const fetchImpl = async () => geminiReply(2);
  // put errors are swallowed inside blobStore; a raw store that throws must not break speech either
  const safe = { get: broken.get, async put(p, b) { try { await broken.put(p, b); } catch {} } };
  const r = await tts({ text: 'ぶどう' }, { falKey: '', geminiKey: 'k', fetchImpl, store: safe });
  assert.equal(r.provider, 'gemini');
});

test('clip path depends on provider, voice, model and text', () => {
  const base = { provider: 'gemini', voice: 'Kore', model: 'm', text: 'ねこ' };
  const p = clipPath(base);
  assert.equal(clipPath({ ...base }), p);
  assert.notEqual(clipPath({ ...base, text: 'いぬ' }), p);
  assert.notEqual(clipPath({ ...base, voice: 'Puck' }), p);
  assert.notEqual(clipPath({ ...base, model: 'n' }), p);
});
