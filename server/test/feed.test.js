import test from 'node:test';
import assert from 'node:assert/strict';
import { feed, defaultQuery, searchItems } from '../lib/feed.js';
import { GET as playerGET } from '../api/player.js';

const fakeYT = (calls) => async (url) => {
  calls.push(String(url));
  return new Response(JSON.stringify({
    nextPageToken: 'P2',
    items: [
      { id: { videoId: 'abc123def45' }, snippet: { title: 'Tom &amp; Jerry&#39;s', channelTitle: 'Ch' } },
      { id: { videoId: 'abc123def45' }, snippet: { title: 'dupe', channelTitle: 'Ch' } },
      { id: { channelId: 'x' }, snippet: { title: 'not a video' } },
    ],
  }));
};

test('search asks only for embeddable short safe videos and decodes titles', async () => {
  const calls = [];
  const r = await searchItems({ q: 'x', lang: 'ja', apiKey: 'K', fetchImpl: fakeYT(calls) });
  const u = new URL(calls[0]);
  assert.equal(u.searchParams.get('videoEmbeddable'), 'true');
  assert.equal(u.searchParams.get('videoDuration'), 'short');
  assert.equal(u.searchParams.get('safeSearch'), 'strict');
  assert.equal(u.searchParams.get('regionCode'), 'JP');
  assert.equal(r.items[0].title, "Tom & Jerry's");
  assert.equal(r.next, 'P2');
});

test('feed dedupes and works without an API key', async () => {
  const none = await feed({ lang: 'en' }, {});
  assert.ok(Array.isArray(none.items));
  assert.equal(none.next, null);
  const r = await feed({ lang: 'en', goal: 'travel' }, { apiKey: 'K', fetchImpl: fakeYT([]) });
  assert.equal(r.items.filter((x) => x.youtubeId === 'abc123def45').length, 1);
});

test('goal picks a query, unknown goal falls back', () => {
  assert.match(defaultQuery('ja', 'anime'), /アニメ/);
  assert.equal(defaultQuery('en', 'nope'), defaultQuery('en', ''));
});

test('player page uses the official IFrame API and nothing else from YouTube', async () => {
  const html = await playerGET().text();
  assert.match(html, /youtube\.com\/iframe_api/);
  assert.match(html, /new YT\.Player/);
  assert.doesNotMatch(html, /timedtext|XMLHttpRequest|fetch\(/);
});
