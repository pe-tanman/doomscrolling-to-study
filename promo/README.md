# Upscroll promo video

Short vertical (9:16) promo, styled after the reference reels: warm off-white canvas,
two-line headlines (sans + italic serif accent), chapter pills, word-by-word captions,
a dark reveal frame, and a "RIP doomscrolling" hook with a callback ending.

## Pipeline
1. **Mock 1** (`mock1/upscroll_mock1.mp4`): stills + voice + SFX + music, no AI video.
2. **Mock 2**: each shot animated at the lowest resolution (480p).
3. **Final**: the same shots at full resolution.

## Sources
- `img/p1.jpg` … `img/p8.jpg`: scene stills, generated on fal.ai (Nano Banana 2.1), using the app's mascot and journey map as references.
- `audio/`: ElevenLabs voice (Jessica for English, Will for 「はぁ… つかれた。」), sound effects and music bed. `script_lines.tsv` is the voiceover script; `vo*.align.json` holds per-character timings for the captions.
- `fonts/`: Instrument Serif (SIL Open Font License). Inter and IPAGothic come from the system.

## Build
```bash
python3 build_mock1.py            # writes mock1/upscroll_mock1.mp4 (1080x1920, 30 fps)
```
Needs Python 3 with Pillow, plus ffmpeg.
