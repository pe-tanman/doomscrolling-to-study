// The feed: which Shorts the app's IFrame player plays.
// 1) Curated items (lib/feed.json) and enabled lesson videos, which may carry cues we are allowed to use.
// 2) YouTube Data API v3 search (embeddable short videos only) when YOUTUBE_API_KEY is set.
import curated from './feed.json' with { type: 'json' };
import lessons from './lessons.json' with { type: 'json' };

const GOAL_QUERY = {
  ja: {
    travel: '日本 旅行 やさしい日本語 shorts',
    anime: 'アニメ 日本語 勉強 shorts',
    friends: '日本語 会話 やさしい日本語 shorts',
    work: 'ビジネス日本語 shorts',
    culture: '日本 文化 やさしい日本語 shorts',
    '': 'やさしい日本語 shorts',
  },
  en: {
    travel: 'learn Japanese travel phrases shorts',
    anime: 'learn Japanese anime phrases shorts',
    friends: 'learn Japanese conversation shorts',
    work: 'business Japanese phrases shorts',
    culture: 'Japanese culture explained shorts',
    '': 'learn Japanese shorts',
  },
};

export function defaultQuery(lang, goal) {
  const table = GOAL_QUERY[lang === 'ja' ? 'ja' : 'en'];
  return table[goal] || table[''];
}

const ENTITIES = { '&amp;': '&', '&quot;': '"', '&#39;': "'", '&lt;': '<', '&gt;': '>' };
const unescape = (s) => String(s || '').replace(/&(amp|quot|#39|lt|gt);/g, (m) => ENTITIES[m]);

/** Curated + lesson items for this learner (first page only). */
export function curatedItems({ lang, goal }) {
  const suits = (x) => (!x.goals || x.goals.length === 0 || x.goals.includes(goal));
  const fromLessons = lessons.lessons
    .filter((l) => l.enabled && l.youtubeId && !l.youtubeId.startsWith('REPLACE') && suits(l))
    .map((l) => ({ youtubeId: l.youtubeId, title: l.title, author: 'Upscroll', ...(l.cues ? { cues: l.cues } : {}) }));
  const fromFeed = curated.items
    .filter((x) => x.youtubeId && suits(x) && (!lang || !x.lang || x.lang === lang))
    .map(({ youtubeId, title, author, cues }) => ({ youtubeId, title: title || '', author: author || '', ...(cues ? { cues } : {}) }));
  return [...fromFeed, ...fromLessons];
}

/** YouTube Data API search: embeddable, short, safe-search strict. */
export async function searchItems({ q, lang, pageToken, apiKey, fetchImpl = fetch }) {
  const p = new URLSearchParams({
    part: 'snippet', type: 'video', videoDuration: 'short', videoEmbeddable: 'true', videoSyndicated: 'true',
    safeSearch: 'strict', maxResults: '25', q, relevanceLanguage: lang === 'ja' ? 'ja' : 'en', key: apiKey,
  });
  if (lang === 'ja') p.set('regionCode', 'JP');
  if (pageToken) p.set('pageToken', pageToken);
  const r = await fetchImpl(`https://www.googleapis.com/youtube/v3/search?${p}`);
  if (!r.ok) throw new Error(`youtube search ${r.status}`);
  const j = await r.json();
  const items = (j.items || [])
    .filter((it) => it.id && it.id.videoId)
    .map((it) => ({ youtubeId: it.id.videoId, title: unescape(it.snippet?.title), author: unescape(it.snippet?.channelTitle) }));
  return { items, next: j.nextPageToken || null };
}

export async function feed({ lang = 'en', goal = '', q = '', page = '' } = {}, { apiKey, fetchImpl } = {}) {
  const items = page || q ? [] : curatedItems({ lang, goal });
  let next = null;
  if (apiKey) {
    try {
      const s = await searchItems({ q: q || defaultQuery(lang, goal), lang, pageToken: page, apiKey, fetchImpl });
      items.push(...s.items);
      next = s.next;
    } catch (e) {
      console.error(e.message);
    }
  }
  const seen = new Set();
  return { items: items.filter((x) => !seen.has(x.youtubeId) && seen.add(x.youtubeId)), next };
}
