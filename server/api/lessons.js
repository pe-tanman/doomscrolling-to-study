// Vercel Function: GET /api/lessons → the special lesson video catalog (lib/lessons.json).
// Public and read-only: adding a lesson is a JSON edit + deploy, no app update needed.
import catalog from '../lib/lessons.json' with { type: 'json' };

export function GET() {
  const lessons = catalog.lessons.filter((l) => l.enabled && l.youtubeId && !l.youtubeId.startsWith('REPLACE'));
  return new Response(JSON.stringify({ version: catalog.version, lessons }), {
    status: 200,
    headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=300, s-maxage=300' },
  });
}
