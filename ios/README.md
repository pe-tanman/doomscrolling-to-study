# Upscroll: Phase 0 spike (YouTube Shorts)

This test app answers one question: can we wrap the user's own YouTube Shorts feed and reliably get **English and Japanese caption cues** for each Short? If we can, the word-swap subtitles work.

## Run
1. You need **Xcode 26+**. Xcode 16.0 won't launch on macOS 26.
2. `cd ios && xcodegen generate` (already done once) → open `Upscroll.xcodeproj`.
3. Set your Team under Signing, then run it on a **real iPhone** (the simulator is fine for a first look).
4. Scroll about 50 Shorts. Tap **あ** (top right) to open the spike panel → **Export report JSON**.

## What to check (go / no-go)
| Check | Where |
|---|---|
| Swiping feels like the native app | by hand |
| Google sign-in works inside the app (or the signed-out feed is good enough) | try signing in from the YouTube menu |
| English/source cue hit rate | spike panel, "English/source cues" |
| Japanese cue hit rate (`tlang=ja` translation) | spike panel, "Japanese cues" |
| Empty responses vs "Recovered via player token" | if direct fetch returns empty, the bridge turns on the player's captions and reuses its request token |

**Go** if most Shorts that have speech give both English and Japanese cues.

## How it works
- `Injected/youtube-shorts-bridge.js` hooks the page's fetch/XHR, reads player responses (video ID + caption tracks), downloads caption tracks as `json3` (plus `tlang=ja`), reports which video is active and its currentTime, and hides YouTube's own captions and app-install banners.
- `Bridges/`: `PlatformBridge` is shared by all platforms. Only the YouTube bridge exists so far; TikTok comes later.
- `Model/FeedSession.swift` stores per-video records and stats. It picks one target word per video (loanwords first) from `Resources/mini_vocab.json`.
- `Views/SubtitleOverlay.swift` is the native subtitle bar with the swapped word. Tapping the word plays on-device Japanese TTS and shows its meaning.

Phase 1 replaces the fixed word pick with the `/lesson` backend (TypeSafe Jev word choice, Japanese alignment and sense check).

## Smart word picks (TypeSafe Jev)
The app picks words on the phone instantly, then asks the lesson server, which asks TypeSafe Jev.
Jev's picks replace the words that haven't been shown yet. If the server can't be reached, the on-device picks stay.

```sh
cd server
npm test                                  # policy + request-shape tests (no key needed)
TYPESAFE_API_KEY=... npm run dev          # http://localhost:8787 (simulator default)
node dev.js --mock                        # fake Jev answers, to test the app end to end
```
Production: https://upscroll-lesson.vercel.app (Vercel project `upscroll-lesson`, `TYPESAFE_API_KEY` set as a production env var). The app uses it by default (`LESSON_SERVER_URL` in `project.yml`). Redeploy with `cd server && npx vercel deploy --prod`.

Jev also decides:
- **Phrases from any Short** (`/api/phrase`): of a Short's caption lines that have YouTube's Japanese, which one is worth learning whole (learnable × the translation is right). The card pauses after that line: see it, hear it, build it; it's saved to *My phrases* and comes back as practice. Offline: the shortest line that sounds like speech.
- **The personal path** (`/api/path`): from the goal picked in onboarding, recent Short titles and skill results, the next place (among the next 3 unfinished), the skill the feed focuses on, and which phrases matter most. Home's map draws this route. Offline: the goal's default order (`LearningGoal.defaultOrder`).

## Lesson videos (your own Shorts in the feed)
1. Upload the lesson as a YouTube Short.
2. Add it to `server/lib/lessons.json`: `youtubeId`, `title`, `place` (a curriculum place id or null), `goals` (empty = everyone), and `checkpoints` (`at` seconds → `phrase` with `phraseId` + `skill`, or `word` with `entryId`). Set `enabled: true`.
3. Deploy the server. The app fetches `GET /api/lessons`, so no app update is needed.

Every ~8 swipes the feed plays the best unwatched lesson for the learner's current place and goal. It pauses at each checkpoint for a card. Lessons also show on Home. To try the lesson frame now, use the `-demoLesson` launch argument (debug builds).

### Access control (app only)
- **Request signing:** every request is signed with HMAC-SHA256 over `ts\nnonce\nbody`, sent in the `x-ds-ts`, `x-ds-nonce` and `x-ds-sig` headers. The server rejects unsigned, tampered, stale (more than 5 minutes old) and replayed requests. In production it fails closed if `DS_APP_SECRET` is missing.
- **Where the secret lives:** `DS_APP_SECRET` is in the root `.env`, in `ios/Secrets.xcconfig` (git-ignored, read by `project.yml`) and in Vercel as a production env var. To rotate it, update all three, then redeploy and rebuild the app.
- **Fresh clone:** create `ios/Secrets.xcconfig` with `DS_APP_SECRET = <value from .env>` before running `xcodegen generate`.
- **Rate limit:** a Vercel Firewall rule allows 30 requests per minute per IP on `/api/lesson`; requests over that get 403.
- **Next step: App Attest.** The secret ships inside the app, so a determined person could extract it. Apple App Attest proves a request comes from a genuine copy of this app on a real iPhone. It needs your Apple Team ID and a real device, and the simulator isn't supported.
