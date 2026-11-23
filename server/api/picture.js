// Vercel Function: POST /api/picture → picture question material for a Short with no talking.
// Body: { videoId, title, image: {format, data_base64}, candidates: [{entryId, en, status}], colors: [...] }
import { picture } from '../lib/picture.js';
import { verify } from '../lib/auth.js';
import { checkUsage } from '../lib/usage.js';

const json = (status, obj) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export async function POST(request) {
  const body = await request.text();
  if (body.length > 3_000_000) return json(413, { error: 'body too large' });

  const denied = verify(request.headers, body);
  if (denied) return json(denied.status, { error: denied.error });
  const limited = await checkUsage(request.headers, 'picture');
  if (limited) return json(limited.status, { error: limited.error });

  try {
    return json(200, await picture(JSON.parse(body)));
  } catch (e) {
    return json(e.status || 400, { error: String(e.message || e) });
  }
}

export function GET() {
  return json(405, { error: 'POST only' });
}
