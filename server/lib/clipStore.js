// Shared voice-clip storage: a clip is generated once and then reused by every user.
// Backed by Vercel Blob (BLOB_READ_WRITE_TOKEN, set automatically when a Blob store is connected to the project).
// Clips are stored at a fixed path from a fingerprint of provider + voice + model + text, so the same words always
// map to the same file. Without a token the store is a no-op and the server just generates as before.
import { createHash } from 'node:crypto';
import { put, head, BlobNotFoundError } from '@vercel/blob';

export function clipPath({ provider, voice, model, text }) {
  const hash = createHash('sha256').update(`${provider}|${model}|${voice}|${text}`).digest('hex').slice(0, 32);
  return `tts/${provider}/${voice}/${hash}.wav`;
}

/** Vercel Blob store. `get` → bytes or null; `put` saves (never overwrites an existing clip). */
export function blobStore({ token = process.env.BLOB_READ_WRITE_TOKEN, fetchImpl = fetch, timeoutMs = 2500 } = {}) {
  if (!token) return null;
  return {
    async get(path) {
      try {
        const meta = await head(path, { token });
        const res = await fetchImpl(meta.url, { signal: AbortSignal.timeout(timeoutMs) });
        if (!res.ok) return null;
        const bytes = Buffer.from(await res.arrayBuffer());
        return bytes.length > 44 ? bytes : null;
      } catch (e) {
        if (!(e instanceof BlobNotFoundError)) console.warn(`clip store get ${path}: ${e.message ?? e}`);
        return null;
      }
    },
    async put(path, bytes) {
      try {
        await put(path, Buffer.from(bytes), {
          token, access: 'public', contentType: 'audio/wav',
          addRandomSuffix: false, allowOverwrite: false, cacheControlMaxAge: 31536000,
        });
      } catch (e) {
        // Two users asking for a new word at the same moment: the second save is refused; the clip is there.
        if (!/already exists/i.test(String(e.message))) console.warn(`clip store put ${path}: ${e.message ?? e}`);
      }
    },
  };
}
