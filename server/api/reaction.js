// Vercel Function: POST /api/reaction → { answerId, options[3], confidence, probabilities }
import { reaction } from '../lib/reaction.js';
import { verify } from '../lib/auth.js';
import { checkUsage } from '../lib/usage.js';

const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export async function POST(request) {
  const body = await request.text();
  if (body.length > 50_000) return json(413, { error: 'body too large' });
  const denied = verify(request.headers, body);
  if (denied) return json(denied.status, { error: denied.error });
  const limited = await checkUsage(request.headers, 'reaction');
  if (limited) return json(limited.status, { error: limited.error });
  try {
    return json(200, await reaction(JSON.parse(body)));
  } catch (e) {
    return json(e.status || 400, { error: String(e.message || e) });
  }
}

export function GET() {
  return json(405, { error: 'POST only' });
}
