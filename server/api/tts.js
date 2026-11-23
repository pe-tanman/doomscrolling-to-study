// Vercel Function: POST /api/tts { text } → audio/wav (Gemini 3.8 Flash TTS, Japanese). Signed like the other endpoints.
import { tts } from '../lib/tts.js';
import { verify } from '../lib/auth.js';
import { checkUsage } from '../lib/usage.js';

const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export async function POST(request) {
  const body = await request.text();
  if (body.length > 2_000) return json(413, { error: 'body too large' });
  const denied = verify(request.headers, body);
  if (denied) return json(denied.status, { error: denied.error });
  const limited = await checkUsage(request.headers, 'tts');
  if (limited) return json(limited.status, { error: limited.error });
  try {
    const { audio, cached, shared, provider } = await tts(JSON.parse(body));
    return new Response(audio, { status: 200, headers: { 'content-type': 'audio/wav', 'x-ds-cached': String(cached), 'x-ds-shared': String(Boolean(shared)), 'x-ds-voice': provider } });
  } catch (e) {
    return json(e.status || 400, { error: String(e.message || e) });
  }
}

export function GET() {
  return json(405, { error: 'POST only' });
}
