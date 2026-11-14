// Vercel Function: GET /api/feed?lang=en|ja&goal=travel&q=…&page=… → { items: [{youtubeId, title, author, cues?}], next }
// Public and read-only. Cached at the edge per URL, so YouTube API quota is spent once per query/page an hour.
import { feed } from '../lib/feed.js';

export async function GET(request) {
  const u = new URL(request.url);
  const params = {
    lang: u.searchParams.get('lang') === 'ja' ? 'ja' : 'en',
    goal: (u.searchParams.get('goal') || '').slice(0, 20),
    q: (u.searchParams.get('q') || '').slice(0, 120),
    page: (u.searchParams.get('page') || '').slice(0, 100),
  };
  const body = await feed(params, { apiKey: process.env.YOUTUBE_API_KEY });
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=600, s-maxage=3600' },
  });
}
