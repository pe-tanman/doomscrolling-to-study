// Vercel Function: GET /api/player → the page the app's feed loads.
// It hosts the official YouTube IFrame Player (https://developers.google.com/youtube/iframe_api_reference)
// on our own origin. Nothing is injected into YouTube: the app talks only to this page, and this page
// talks to the player only through the documented API (load, play, pause, getCurrentTime…).
//
// Layout follows the YouTube API policies: the player is never covered. `top` and `bottom` (points)
// reserve bands above and below it for the app's own buttons and subtitles.
//
// App → page:  __dsSetQueue(items, start) · __dsAppend(items) · __dsNext() · __dsPrev()
//              __dsPlayNow(item) · __dsPause() · __dsPlay()      (item = {youtubeId, title, author})
// Page → app:  webkit.messageHandlers.ds.postMessage({type, payload: JSON string})
//              types: video, tick, needMore, log

const PAGE = String.raw`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="referrer" content="strict-origin-when-cross-origin">
<title>Upscroll player</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; overscroll-behavior: none; }
  #box { position: absolute; left: 50%; transform: translateX(-50%); background: #000; }
  #box iframe { display: block; border: 0; }
</style>
</head><body>
<div id="box"><div id="player"></div></div>
<script>
(() => {
  const q = new URLSearchParams(location.search);
  const TOP = Number(q.get('top')) || 0, BOTTOM = Number(q.get('bottom')) || 0;
  const HL = q.get('hl') || 'en';
  const box = document.getElementById('box');

  const post = (type, payload) => {
    try { window.webkit.messageHandlers.ds.postMessage({ type, payload: JSON.stringify(payload) }); } catch (_) {}
  };
  const log = (s) => post('log', 'player: ' + s);

  let queue = [], idx = -1, dir = 1, player = null, ready = false, current = null, asked = -1;

  // Largest 9:16 box that fits between the reserved bands.
  function size() {
    const W = innerWidth, H = Math.max(200, innerHeight - TOP - BOTTOM);
    let w = W, h = Math.round(W * 16 / 9);
    if (h > H) { h = H; w = Math.round(H * 9 / 16); }
    return { w, h };
  }
  function layout() {
    const { w, h } = size();
    box.style.top = TOP + 'px'; box.style.width = w + 'px'; box.style.height = h + 'px';
    if (player && player.setSize) player.setSize(w, h);
  }
  addEventListener('resize', layout);
  layout();

  function show(i) {
    if (!ready || i < 0 || i >= queue.length) return;
    idx = i;
    current = queue[i];
    player.loadVideoById(current.youtubeId);
    post('video', { videoId: current.youtubeId, title: current.title || '', author: current.author || '',
                    lengthSeconds: 0, description: '', tracks: [], source: 'iframe' });
    if (idx >= queue.length - 3 && asked !== queue.length) { asked = queue.length; post('needMore', { have: queue.length }); }
  }

  window.__dsSetQueue = (items, start) => { queue = items || []; asked = -1; dir = 1; show(start || 0); if (!ready) idx = (start || 0) - 1; };
  window.__dsAppend = (items) => {
    const known = new Set(queue.map((x) => x.youtubeId));
    for (const it of items || []) if (!known.has(it.youtubeId)) queue.push(it);
    if (ready && !current && queue.length) show(Math.max(0, idx + 1));
  };
  window.__dsNext = () => { dir = 1; if (idx + 1 < queue.length) show(idx + 1); else post('needMore', { have: queue.length }); };
  window.__dsPrev = () => { dir = -1; if (idx > 0) show(idx - 1); };
  window.__dsPlayNow = (item) => { queue.splice(idx + 1, 0, item); dir = 1; show(idx + 1); };
  window.__dsPause = () => { if (ready) player.pauseVideo(); };
  window.__dsPlay = () => { if (ready) player.playVideo(); };

  window.onYouTubeIframeAPIReady = () => {
    const { w, h } = size();
    player = new YT.Player('player', {
      width: w, height: h,
      host: 'https://www.youtube.com',
      playerVars: { playsinline: 1, controls: 1, rel: 0, iv_load_policy: 3, fs: 0, hl: HL, origin: location.origin },
      events: {
        onReady: () => { ready = true; log('ready'); if (queue.length) show(Math.max(0, idx + 1)); },
        onStateChange: (e) => {
          // Shorts loop: play the same one again (swiping is what moves on).
          if (e.data === YT.PlayerState.ENDED) { player.seekTo(0, true); player.playVideo(); }
        },
        onError: (e) => {
          // 2 bad id · 5 HTML5 error · 100 removed/private · 101/150 owner disallows embedding: skip it.
          log('error ' + e.data + ' on ' + (current && current.youtubeId));
          const bad = idx;
          queue.splice(bad, 1);
          current = null;
          const next = dir < 0 ? bad - 1 : bad;
          if (next >= 0 && next < queue.length) show(next); else post('needMore', { have: queue.length });
        },
      },
    });
  };

  // Heartbeat: which Short is on screen and where it is. An empty id means nothing is playing yet.
  setInterval(() => {
    if (!ready || !current) { post('tick', { videoId: '', currentTime: 0, duration: 0, paused: true }); return; }
    const st = player.getPlayerState();
    post('tick', { videoId: current.youtubeId, currentTime: player.getCurrentTime() || 0,
                   duration: player.getDuration() || 0, paused: st !== YT.PlayerState.PLAYING && st !== YT.PlayerState.BUFFERING });
  }, 500);

  const s = document.createElement('script');
  s.src = 'https://www.youtube.com/iframe_api';
  document.head.appendChild(s);
})();
</script>
</body></html>`;

export function GET() {
  return new Response(PAGE, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=300, s-maxage=3600',
      'referrer-policy': 'strict-origin-when-cross-origin',
    },
  });
}
