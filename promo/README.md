# Upscroll promo video

Short vertical (9:16) promo. Story: you skip a 5-minute lesson but doomscroll for hours,
then Upscroll turns those Shorts into Japanese lessons. A Short plays, a subtitle word
swaps into Japanese, the video pauses for a practice card, you answer and keep scrolling.
It ends on the journey map and an App Store end card.

The phone and every piece of app UI are drawn in `build_mock1.py`, modelled on the app's
SwiftUI views (`Theme.swift`, `SubtitleOverlay.swift`, `LearningCard.swift`). The cat
uses the app's own mascot art from `ios/Upscroll/Assets.xcassets`.

## Pipeline
1. **Mock 1** (`mock1/upscroll_mock1.mp4`): stills + voice + SFX + music, no AI video.
2. **Mock 2**: each shot animated at the lowest resolution (480p).
3. **Final**: the same shots at full resolution.

## Sources
- Backgrounds are drawn in code (clean gradients). `img/shorts/`: frames used as the Shorts in the feed; `ramen_vlog.jpg` is the main Short. Other `img/` files are from earlier revisions., generated on fal.ai (Nano Banana 2.1), using the app's mascot and journey map as references.
- `audio/`: ElevenLabs voice (Jessica for English, Will for 「はぁ… つかれた。」), sound effects and music bed. Lines in use are listed in `script_lines.tsv`.
- `brand/`: Apple's official "Download on the App Store" badge (SVG from developer.apple.com, PNG rendered from it). Use it unmodified and don't animate it.
- Music: `music_intro.mp3` (tense, 120 bpm) plays under the problem, and `music_main_a.mp3` drops at the reveal. Both come from the ElevenLabs Sound Effects endpoint, since the Music API needs a paid plan.
- Fonts: Inter Display / Inter from the system (close to SF Pro) and `fonts/noto-sans-jp-*` (SIL Open Font License). Older font files in `fonts/` are from earlier revisions.

## Build
```bash
python3 build_mock1.py            # writes mock1/upscroll_mock1.mp4 (1080x1920, 30 fps)
```
Needs Python 3 with Pillow, plus ffmpeg.
