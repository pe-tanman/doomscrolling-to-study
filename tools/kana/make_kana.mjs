// Bundled kana sound clips → ios/Upscroll/Resources/Kana/kana_<hex>.m4a (hex = the hiragana's UTF-16 code units).
//
// Why: every TTS mangles a lone kana (か → "K", ふ → a laugh, は → "wa", を → "a"). So each kana is spoken at the end
// of a short frame (「つぎは、ふ。」), where it's pronounced properly; the last spoken segment is cut out, faded,
// and laid out as  [pad] kana [gap] kana [pad]  at a steady loudness. Each clip is then checked by transcribing it
// (ElevenLabs Scribe); a mismatch retries with a different frame.
//
// Usage: GEMINI_API_KEY in the repo .env, ELEVENLABS_API_KEY in .env.local, ffmpeg on PATH.
//   cd tools/kana && npm install && npm run make            (skips clips that already exist)
//   npm run make -- ふ を                                   (remake only these)
import { ElevenLabsClient } from '@elevenlabs/elevenlabs-js';
import { writeFile, mkdir, access, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../ios/Upscroll/Resources/Kana');
const TMP = path.join(process.env.CLAUDE_JOB_DIR ? path.join(process.env.CLAUDE_JOB_DIR, 'tmp') : os.tmpdir(), 'kana-make');
const VOICE = 'Kore';
// Same Kore voice on each; when one model's daily quota runs out, the next one takes over.
const MODELS = ['gemini-3.8-flash-tts', 'gemini-2.5-pro-preview-tts', 'gemini-3.1-flash-tts-preview'];   // not 2.5-flash-preview: it refuses one-kana text
// A full stop gives a longer pause than a comma, so a vowel kana (い) can't merge with the frame's last sound (はい).
const FRAMES = [k => `つぎは、${k}。`, k => `つぎ。${k}。`, k => `では。${k}。`];

const basic = [...'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん'];
const voiced = [...'がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ'];
const yoon = ['き', 'し', 'ち', 'に', 'ひ', 'み', 'り', 'ぎ', 'じ', 'び', 'ぴ'].flatMap(c => ['ゃ', 'ゅ', 'ょ'].map(s => c + s));
export const KANA = [...basic, ...voiced, ...yoon];

export const fileName = k => `kana_${[...k].map(c => c.charCodeAt(0).toString(16)).join('_')}.m4a`;

// Same sound, different spelling: what the transcriber may write back.
const SAME = { ぢ: 'じ', づ: 'ず', を: 'お', ぢゃ: 'じゃ', ぢゅ: 'じゅ', ぢょ: 'じょ' };
const ROMAJI = Object.fromEntries(Object.entries({
  a:'あ',i:'い',u:'う',e:'え',o:'お',ka:'か',ki:'き',ku:'く',ke:'け',ko:'こ',sa:'さ',shi:'し',su:'す',se:'せ',so:'そ',
  ta:'た',chi:'ち',tsu:'つ',te:'て',to:'と',na:'な',ni:'に',nu:'ぬ',ne:'ね',no:'の',ha:'は',hi:'ひ',fu:'ふ',he:'へ',ho:'ほ',
  ma:'ま',mi:'み',mu:'む',me:'め',mo:'も',ya:'や',yu:'ゆ',yo:'よ',ra:'ら',ri:'り',ru:'る',re:'れ',ro:'ろ',wa:'わ',n:'ん',
  ga:'が',gi:'ぎ',gu:'ぐ',ge:'げ',go:'ご',za:'ざ',ji:'じ',zu:'ず',ze:'ぜ',zo:'ぞ',da:'だ',de:'で',do:'ど',
  ba:'ば',bi:'び',bu:'ぶ',be:'べ',bo:'ぼ',pa:'ぱ',pi:'ぴ',pu:'ぷ',pe:'ぺ',po:'ぽ',
}).map(([r, k]) => [k, r]));
const toHira = s => s.replace(/[ァ-ヶ]/g, c => String.fromCharCode(c.charCodeAt(0) - 0x60));
function heard(k, text) {
  // Drop punctuation only: a kanji or letter left over (次、さ) means the frame leaked into the cut.
  let t = toHira(text).replace(/[\s、。，．,.!?！？「」『』…〜・\-]/g, '');
  const want = SAME[k] ?? k;
  if (/^[a-z ,.!?'-]+$/i.test(text.trim())) {               // transcribed in letters (の → "No, no")
    const words = text.toLowerCase().match(/[a-z]+/g) ?? [];
    return words.length >= 1 && words.length <= 2 && words.every(w => w === ROMAJI[k]);
  }
  t = t.replace(/っ/g, '');                                   // a clipped ending is written ほっ
  const n = (t.match(new RegExp(want, 'g')) ?? []).length;
  if (k === 'ん') return /ん/.test(t);           // a lone ん is often written うん
  const rest = t.replaceAll(want, '');
  return n >= 1 && rest.length <= 1 && /^[ぁ-ゖ]*$/.test(rest);   // the kana, at most one stray kana, no kanji/letters
}

function wav(pcm, rate = 24000) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function speak(text) {
  for (let i = 0; i < 12 && MODELS.length; i++) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODELS[0]}:generateContent`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': process.env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ parts: [{ text }] }],
        generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICE } } } },
      }),
    });
    if (r.status === 429) {
      const body = await r.text();
      if (/PerDay/.test(body)) { console.log(`  (${MODELS.shift()} is out of today's quota)`); continue; }
      await sleep(20000); continue;
    }
    if (r.status >= 500) { await sleep(20000); continue; }
    const j = await r.json();
    const p = j.candidates?.[0]?.content?.parts?.[0]?.inlineData;
    if (!p) throw new Error(JSON.stringify(j).slice(0, 200));
    return wav(Buffer.from(p.data, 'base64'));
  }
  throw new Error(MODELS.length ? 'Gemini kept rate-limiting' : 'every Gemini TTS model is out of today\'s quota');
}

/** The last spoken segment (the kana after the frame's pause), as [start, end] seconds. */
function lastSegment(file) {
  let log = '';
  try {
    log = execFileSync('ffmpeg', ['-hide_banner', '-i', file, '-af', 'silencedetect=noise=-38dB:d=0.12', '-f', 'null', '-'],
      { stdio: ['ignore', 'ignore', 'pipe'] }).toString();
  } catch (e) { log = String(e.stderr ?? ''); }
  if (!log) log = execFileSync('sh', ['-c', `ffmpeg -hide_banner -i "${file}" -af silencedetect=noise=-38dB:d=0.12 -f null - 2>&1`]).toString();
  const ends = [...log.matchAll(/silence_end: ([\d.]+)/g)].map(m => +m[1]);
  const starts = [...log.matchAll(/silence_start: ([\d.]+)/g)].map(m => +m[1]);
  if (ends.length < 2) return null;
  const s = ends[ends.length - 2];
  const after = starts.filter(x => x > s);
  const e = after.length ? after[0] : null;
  if (e == null || e - s < 0.08 || e - s > 1.2) return null;
  return [Math.max(0, s - 0.04), e + 0.10];
}

function compose(raw, [s, e], out) {
  const d = e - s;
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-filter_complex',
    `[0]atrim=${s}:${e},asetpts=N/SR/TB,afade=t=in:d=0.01,afade=t=out:st=${Math.max(0, d - 0.05)}:d=0.05,asplit[a][b];` +
    `aevalsrc=0:d=0.15:s=24000[p0];aevalsrc=0:d=0.45:s=24000[p1];aevalsrc=0:d=0.25:s=24000[p2];` +
    `[p0][a][p1][b][p2]concat=n=5:v=0:a=1,loudnorm=I=-16:TP=-1.5`,
    '-ar', '44100', '-ac', '1', '-c:a', 'aac', '-b:a', '64k', out]);
}

if (!process.env.GEMINI_API_KEY || !process.env.ELEVENLABS_API_KEY) {
  console.error('Needs GEMINI_API_KEY (.env) and ELEVENLABS_API_KEY (.env.local).');
  process.exit(1);
}
const el = new ElevenLabsClient();
await mkdir(OUT, { recursive: true });
await mkdir(TMP, { recursive: true });
const only = process.argv.slice(2);
const todo = only.length ? KANA.filter(k => only.includes(k)) : KANA;
const failed = [];

for (const k of todo) {
  const out = path.join(OUT, fileName(k));
  if (!only.length && await access(out).then(() => true, () => false)) continue;
  let ok = false, last = '';
  for (let attempt = 0; attempt < FRAMES.length * 2 && !ok; attempt++) {
    try {
      const raw = path.join(TMP, `raw.wav`);
      await writeFile(raw, await speak(FRAMES[attempt % FRAMES.length](k)));
      const seg = lastSegment(raw);
      if (!seg) { last = 'no clean cut'; await sleep(6500); continue; }
      const tmpOut = path.join(TMP, `try.m4a`);
      compose(raw, seg, tmpOut);
      const { readFile } = await import('node:fs/promises');
      const tr = await el.speechToText.convert({ file: new Blob([await readFile(tmpOut)]), modelId: 'scribe_v1', languageCode: 'ja' });
      last = tr.text;
      if (heard(k, tr.text)) {
        await writeFile(out, await readFile(tmpOut));
        ok = true;
        console.log(`✓ ${k}  ${fileName(k)}  heard ${JSON.stringify(tr.text)}`);
      }
    } catch (e) { last = String(e.message ?? e).slice(0, 120); }
    await sleep(6500);   // Gemini free tier: ~10 requests a minute
  }
  if (!ok) { failed.push(k); console.log(`✗ ${k}  last heard ${JSON.stringify(last)}`); }
}
await rm(TMP, { recursive: true, force: true });
console.log(failed.length ? `\nNot verified: ${failed.join(' ')}` : '\nAll verified.');
