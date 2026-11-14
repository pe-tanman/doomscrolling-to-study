// Upscroll — YouTube Shorts bridge (Phase 0 spike).
// Injected at document-start into m.youtube.com. Reports to native via
// window.webkit.messageHandlers.ds:
//   video    — metadata + caption track list for each Short we see
//   captions — parsed cues for a video (English source and Japanese, translated or native)
//   tick     — active video id + currentTime (~4 Hz)
//   log      — diagnostics
(() => {
  // Only run on YouTube itself. Never touch Google sign-in pages (accounts.google.com etc.):
  // hooking fetch there is a privacy problem and makes Google flag the browser as unsafe.
  if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;
  if (window.__dsBridge) return;
  window.__dsBridge = true;

  const post = (type, payload) => {
    try {
      window.webkit.messageHandlers.ds.postMessage({ type, payload: JSON.stringify(payload) });
    } catch (_) { /* not in WKWebView */ }
  };
  const log = (msg, extra) => post('log', Object.assign({ msg }, extra || {}));
  log('bridge start', { ua: navigator.userAgent });

  // ---------- State ----------
  const tracksByVideo = new Map();     // videoId -> [{baseUrl, languageCode, kind, isTranslatable}]
  const potByVideo = new Map();        // videoId -> URLSearchParams from the player's own timedtext request
  const captionState = new Map();      // videoId -> 'pending' | 'done' | 'failed'
  const reported = new Set();

  // ---------- Player-response discovery ----------
  function findPlayerResponses(obj, out, depth) {
    if (!obj || typeof obj !== 'object' || depth > 6) return;
    if (obj.videoDetails && obj.videoDetails.videoId && ('captions' in obj || 'playabilityStatus' in obj)) {
      out.push(obj);
      return;
    }
    for (const k in obj) {
      const v = obj[k];
      if (v && typeof v === 'object') findPlayerResponses(v, out, depth + 1);
    }
  }

  function trackName(t) {
    if (!t.name) return '';
    if (t.name.simpleText) return t.name.simpleText;
    if (t.name.runs) return t.name.runs.map(r => r.text).join('');
    return '';
  }

  function handlePlayerResponse(pr, source) {
    const d = pr.videoDetails;
    const vid = d.videoId;
    if (reported.has(vid)) return;
    reported.add(vid);
    const raw = (pr.captions && pr.captions.playerCaptionsTracklistRenderer &&
      pr.captions.playerCaptionsTracklistRenderer.captionTracks) || [];
    const tracks = raw.map(t => ({
      baseUrl: t.baseUrl,
      languageCode: t.languageCode,
      kind: t.kind || '',
      name: trackName(t),
      isTranslatable: !!t.isTranslatable,
    }));
    tracksByVideo.set(vid, tracks);
    post('video', {
      videoId: vid,
      title: d.title || '',
      author: d.author || '',
      lengthSeconds: Number(d.lengthSeconds || 0),
      description: (d.shortDescription || '').slice(0, 500),
      tracks: tracks.map(t => ({ languageCode: t.languageCode, kind: t.kind, name: t.name, isTranslatable: t.isTranslatable })),
      source,
    });
    fetchCaptions(vid);
  }

  function scanJSON(json, source) {
    const found = [];
    findPlayerResponses(json, found, 0);
    found.forEach(pr => handlePlayerResponse(pr, source));
  }

  // ---------- Caption fetching ----------
  function pickSourceTrack(tracks) {
    const en = tracks.filter(t => t.languageCode && t.languageCode.startsWith('en'));
    return en.find(t => t.kind !== 'asr') || en[0] || tracks.find(t => t.isTranslatable) || null;
  }

  function parseJson3(json) {
    const cues = [];
    (json.events || []).forEach(ev => {
      if (!ev.segs) return;
      const text = ev.segs.map(s => s.utf8 || '').join('').replace(/\s+/g, ' ').trim();
      if (!text) return;
      const start = (ev.tStartMs || 0) / 1000;
      const end = start + (ev.dDurationMs || 2000) / 1000;
      cues.push({ start, end, text });
    });
    return cues;
  }

  // Build a timedtext URL for `track`. If we've seen the player's own (token-bearing) request
  // for this video, use it as the template and only change language/format; otherwise use baseUrl.
  function buildUrl(track, extra, videoId) {
    const tmpl = potByVideo.get(videoId);
    let u;
    if (tmpl) {
      u = new URL(tmpl.href);
      ['tlang', 'fmt', 'kind', 'name', 'lang'].forEach(k => u.searchParams.delete(k));
      u.searchParams.set('lang', track.languageCode);
      if (track.kind) u.searchParams.set('kind', track.kind);
    } else {
      u = new URL(track.baseUrl, location.origin);
    }
    u.searchParams.set('fmt', 'json3');
    Object.keys(extra).forEach(k => u.searchParams.set(k, extra[k]));
    return u.toString();
  }

  async function getCues(url) {
    const res = await origFetch(url, { credentials: 'include' });
    const text = await res.text();
    if (!text || !text.trim()) return { cues: [], status: res.status, empty: true };
    try {
      return { cues: parseJson3(JSON.parse(text)), status: res.status, empty: false };
    } catch (e) {
      return { cues: [], status: res.status, empty: false, parseError: String(e) };
    }
  }

  async function fetchCaptions(videoId) {
    const state = captionState.get(videoId);
    if (state === 'pending' || state === 'done') return;
    const tracks = tracksByVideo.get(videoId) || [];
    const src = pickSourceTrack(tracks);
    // Only a human-made Japanese track counts as "native"; ja(asr) on non-Japanese videos is noise.
    const nativeJa = tracks.find(t => t.languageCode === 'ja' && t.kind !== 'asr');
    if (!src && !nativeJa) {
      captionState.set(videoId, 'failed');
      post('captions', { videoId, role: 'none', cues: [], note: 'no caption tracks' });
      return;
    }
    captionState.set(videoId, 'pending');
    const usedPot = potByVideo.has(videoId);
    try {
      let ok = false;
      if (src) {
        const r = await getCues(buildUrl(src, {}, videoId));
        post('captions', { videoId, role: 'source', languageCode: src.languageCode, kind: src.kind,
          cues: r.cues, status: r.status, empty: r.empty, usedPot });
        ok = r.cues.length > 0;
        if (ok && !src.languageCode.startsWith('ja')) {
          const j = await getCues(buildUrl(src, { tlang: 'ja' }, videoId));
          post('captions', { videoId, role: 'japanese', languageCode: 'ja', kind: 'translated',
            cues: j.cues, status: j.status, empty: j.empty, usedPot });
        }
      }
      if (nativeJa) {
        const j = await getCues(buildUrl(nativeJa, {}, videoId));
        post('captions', { videoId, role: 'japanese', languageCode: 'ja', kind: nativeJa.kind || 'native',
          cues: j.cues, status: j.status, empty: j.empty, usedPot });
        ok = ok || j.cues.length > 0;
      }
      if (ok) {
        captionState.set(videoId, 'done');
      } else {
        captionState.set(videoId, 'failed');
        if (!usedPot && potByVideo.has(videoId)) {
          // The player's token arrived while we were fetching: retry once with it.
          captionState.delete(videoId);
          fetchCaptions(videoId);
        } else if (!usedPot) {
          // Ask the player to load captions; its own request is intercepted and triggers a retry.
          enablePlayerCaptions();
        }
      }
    } catch (e) {
      captionState.set(videoId, 'failed');
      log('caption fetch error', { videoId, error: String(e) });
    }
  }

  function enablePlayerCaptions() {
    const p = document.getElementById('movie_player');
    if (!p) return;
    try {
      if (p.loadModule) p.loadModule('captions');
      if (p.setOption) p.setOption('captions', 'track', { languageCode: 'en' });
    } catch (e) {
      log('enablePlayerCaptions failed', { error: String(e) });
    }
  }

  function onTimedTextRequest(url) {
    try {
      const u = new URL(url, location.origin);
      const vid = u.searchParams.get('v');
      if (!vid || !u.searchParams.has('pot')) return;
      const first = !potByVideo.has(vid);
      potByVideo.set(vid, u);
      if (first) {
        log('captured timedtext pot', { videoId: vid, lang: u.searchParams.get('lang'),
          kind: u.searchParams.get('kind'), fmt: u.searchParams.get('fmt'), tlang: u.searchParams.get('tlang'),
          state: captionState.get(vid) || 'none' });
        if (captionState.get(vid) === 'failed') {
          captionState.delete(vid);
          fetchCaptions(vid);
        }
      }
    } catch (_) { /* ignore */ }
  }

  // ---------- Network hooks ----------
  const origFetch = window.fetch.bind(window);
  window.fetch = async function (input, init) {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    if (url.includes('/api/timedtext')) onTimedTextRequest(url);
    const res = await origFetch(input, init);
    if (url.includes('/youtubei/v1/player') || url.includes('/youtubei/v1/reel/')) {
      res.clone().json().then(j => scanJSON(j, 'fetch')).catch(() => {});
    }
    return res;
  };

  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__dsUrl = String(url || '');
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    const url = this.__dsUrl || '';
    if (url.includes('/api/timedtext')) onTimedTextRequest(url);
    if (url.includes('/youtubei/v1/player') || url.includes('/youtubei/v1/reel/')) {
      this.addEventListener('load', () => {
        try { scanJSON(JSON.parse(this.responseText), 'xhr'); } catch (_) { /* ignore */ }
      });
    }
    return origSend.apply(this, arguments);
  };

  // ---------- Initial page data + player API fallback ----------
  function scanGlobals() {
    if (window.ytInitialPlayerResponse) scanJSON(window.ytInitialPlayerResponse, 'initial');
    const p = document.getElementById('movie_player');
    if (p && typeof p.getPlayerResponse === 'function') {
      try { const pr = p.getPlayerResponse(); if (pr) scanJSON(pr, 'playerApi'); } catch (_) { /* ignore */ }
    }
  }

  // ---------- Active video tracking ----------
  function currentVideoId() {
    const m = location.pathname.match(/\/shorts\/([A-Za-z0-9_-]{6,})/);
    return m ? m[1] : null;
  }

  function activeVideoElement() {
    const vids = Array.from(document.querySelectorAll('video'));
    let best = null, bestArea = 0;
    const vh = window.innerHeight, vw = window.innerWidth;
    vids.forEach(v => {
      const r = v.getBoundingClientRect();
      const w = Math.max(0, Math.min(r.right, vw) - Math.max(r.left, 0));
      const h = Math.max(0, Math.min(r.bottom, vh) - Math.max(r.top, 0));
      const area = w * h;
      if (area > bestArea) { best = v; bestArea = area; }
    });
    return best;
  }

  // Native controls for pause-and-learn moments.
  window.__dsPause = () => {
    const v = activeVideoElement();
    if (v && !v.paused) v.pause();
    return !!v;
  };
  window.__dsPlay = () => {
    const v = activeVideoElement();
    if (v && v.paused) { const p = v.play(); if (p && p.catch) p.catch(() => {}); }
    return !!v;
  };

  // Sponsored Shorts: look for the ad badge / "Sponsored" label near the active player (cached per video id).
  const adById = new Map();
  const dubById = new Map();
  // Positive results are cached; negatives are re-checked for the first ~6 s, because YouTube draws the
  // "Sponsored / スポンサー" label after the video starts (the first check used to miss it and stick).
  const adFirstSeen = new Map();
  function isAd(id, v) {
    if (adById.get(id) === true) return true;
    const now = Date.now();
    if (!adFirstSeen.has(id)) adFirstSeen.set(id, now);
    if (adById.has(id) && now - adFirstSeen.get(id) > 6000) return false;
    let el = v;
    for (let i = 0; i < 7 && el && el.parentElement; i++) el = el.parentElement;   // the reel, not the whole feed
    const root = el || document;
    const badge = root.querySelector && root.querySelector('[class*="ad-badge"], [class*="ad-avatar"], ytm-promoted-sparkles-web-renderer, [class*="sponsor"], [class*="ad-showing"], [aria-label*="Sponsored"], [aria-label*="スポンサー"], [aria-label*="広告"]');
    const text = (root.innerText || '').slice(0, 6000);
    const ad = !!badge || /(^|[\s·•|])(Sponsored|スポンサー|広告)([\s·•|]|$)/.test(text);
    if (/オートダビング|Auto-dubbed|自動吹き替え/.test(text)) dubById.set(id, true);
    adById.set(id, ad);
    if (ad) log('sponsored short', { id });
    return ad;
  }

  let lastId = null, lastTime = -1, lastPaused = null;
  // Which media each Short started with: a different source under the same URL means the feed
  // moved to another Short before the URL caught up, so the old subtitles must not stay up.
  const srcById = new Map();
  let lastUrlId = null;
  let lastPost = 0;
  setInterval(() => {
    scanGlobals();
    const id = currentVideoId();
    const v = activeVideoElement();
    if (!id) return;
    if (!v) {
      // URL moved to a new Short but its player isn't ready: tell the app now so it clears the overlay.
      if (id !== lastId) {
        lastId = id; lastTime = 0; lastPaused = true;
        post('tick', { videoId: id, currentTime: 0, duration: 0, paused: true });
      }
      return;
    }
    const src = v.currentSrc || v.src || '';
    if (id !== lastUrlId) { lastUrlId = id; srcById.delete(id); }   // (re)entering a Short: take its media fresh
    if (src && !srcById.has(id)) srcById.set(id, src);
    const mismatch = !!src && srcById.get(id) !== src;
    const shownId = mismatch ? '' : id;   // '' = "some other Short, not known yet"
    const t = v.currentTime || 0;
    // Heartbeat at least once a second, so the app can tell a live feed from a stalled bridge.
    if (shownId !== lastId || Math.abs(t - lastTime) > 0.15 || v.paused !== lastPaused || Date.now() - lastPost > 1000) {
      lastId = shownId; lastTime = t; lastPaused = v.paused; lastPost = Date.now();
      post('tick', { videoId: shownId, currentTime: t, duration: v.duration || 0, paused: v.paused, ad: shownId ? isAd(shownId, v) : false, dub: shownId ? dubById.get(shownId) === true : false });
    }
    if (mismatch) return;
    if (!tracksByVideo.has(id) && !reported.has(id)) {
      // Seen in the URL but no player data captured yet.
      const p = document.getElementById('movie_player');
      if (p && typeof p.getPlayerResponse === 'function') {
        try { const pr = p.getPlayerResponse(); if (pr) scanJSON(pr, 'playerApi'); } catch (_) { /* ignore */ }
      }
    }
  }, 250);

  // ---------- Cosmetics: hide native captions and app-install nags ----------
  const css = `
    .ytp-caption-window-container, .caption-window, .ytm-caption-window { display: none !important; }
    ytm-mealbar-promo-renderer, .mealbar-promo-renderer, ytm-open-app-promo, .open-app-promo,
    ytm-upsell-dialog-renderer, ytm-statement-banner-renderer { display: none !important; }
  `;
  function injectCSS() {
    if (document.getElementById('ds-style')) return;
    const s = document.createElement('style');
    s.id = 'ds-style';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { injectCSS(); scanGlobals(); });
  } else {
    injectCSS(); scanGlobals();
  }

  log('bridge installed', { href: location.href });
})();
