# Upscroll promo video

Short vertical (9:16) promo, styled after the reference reels: warm off-white canvas,
two-line headlines (sans + italic serif accent), chapter pills, word-by-word captions,
a dark reveal frame where the music drops, and an App Store end card.

Hook: "You can't do 5 minutes of Duolingo… but you'll doomscroll for hours."

## Pipeline
1. **Mock 1** (`mock1/upscroll_mock1.mp4`): stills + voice + SFX + music, no AI video.
2. **Mock 2**: each shot animated at the lowest resolution (480p).
3. **Final**: the same shots at full resolution.

## Sources
- `img/p1.jpg` … `img/p8.jpg` (no p7): scene stills; `img/v2/` holds retired versions, generated on fal.ai (Nano Banana 2.1), using the app's mascot and journey map as references.
- `audio/`: ElevenLabs voice (Jessica for English, Will for 「はぁ… つかれた。」), sound effects and music bed. `script_lines.tsv` is the voiceover script; `vo*.align.json` holds per-character timings for the captions.
- `brand/`: Apple's official "Download on the App Store" badge (SVG from developer.apple.com, PNG rendered from it). Use it unmodified and don't animate it.
- Music: `music_intro.mp3` (tense, 120 bpm) plays under the problem, and `music_main_a.mp3` drops at the reveal. Both come from the ElevenLabs Sound Effects endpoint, since the Music API needs a paid plan.
- `fonts/`: Instrument Serif (SIL Open Font License). Inter and IPAGothic come from the system.

## Build
```bash
python3 build_mock1.py            # writes mock1/upscroll_mock1.mp4 (1080x1920, 30 fps)
```
Needs Python 3 with Pillow, plus ffmpeg.
