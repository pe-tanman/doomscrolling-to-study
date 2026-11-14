// Vercel Function: POST /api/phrase (signed). See lib/phrase.js.
import { phrase } from '../lib/phrase.js';
import { verify } from '../lib/auth.js';

const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export async function POST(request) {
  const body = await request.text();
  if (body.length > 60_000) return json(413, { error: 'body too large' });
  const denied = verify(request.headers, body);
  if (denied) return json(denied.status, { error: denied.error });
  try {
    return json(200, await phrase(JSON.parse(body)));
  } catch (e) {
    return json(e.status || 400, { error: String(e.message || e) });
  }
}

export function GET() {
  return json(405, { error: 'POST only' });
}
