// Vercel Function: GET /api/feed?lang=en|ja&goal=travel&q=…&page=… → { items: [{youtubeId, title, author, cues?}], next }
// Public and read-only. Cached at the edge per URL, so YouTube API quota is spent once per query/page an hour.
// Cache misses that would search YouTube count against a per-IP daily limit (lib/usage.js). Over the limit,
// the curated list is returned uncached, so one client can't exhaust the quota or poison the cache.
import { feed } from '../lib/feed.js';
import { checkUsage } from '../lib/usage.js';

export async function GET(request) {
  const u = new URL(request.url);
  const params = {
    lang: u.searchParams.get('lang') === 'ja' ? 'ja' : 'en',
    goal: (u.searchParams.get('goal') || '').slice(0, 20),
    q: (u.searchParams.get('q') || '').slice(0, 120),
    page: (u.searchParams.get('page') || '').slice(0, 100),
  };
  let apiKey = process.env.YOUTUBE_API_KEY;
  let cache = 'public, max-age=600, s-maxage=3600';
  if (apiKey && (await checkUsage(request.headers, 'search'))) {
    apiKey = undefined;
    cache = 'no-store';
  }
  const body = await feed(params, { apiKey });
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json', 'cache-control': cache },
  });
}
