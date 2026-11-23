"""Upscroll promo, Mock 1: animatic from generated stills + ElevenLabs audio.

Style taken from the reference reels: warm off-white canvas, two-line headlines
(plain sans + italic serif accent), chapter pills, word-by-word karaoke captions,
blur-in reveals, a dark product-reveal frame, a list carousel, a typing search pill.

Every frame is drawn in Python and piped to ffmpeg. Plates are stills here;
Mock 2 / final swap them for generated video clips (see Plate).
Usage: python3 build_mock1.py [--scale 1.0] [--out mock1/upscroll_mock1.mp4]
"""
import argparse
import json
import subprocess
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).parent
IMG, AUD = ROOT / "img", ROOT / "audio"
W, H, FPS = 1080, 1920, 30

F_SANS_B = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
F_SANS_SB = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"
F_SANS_M = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"
F_SERIF_I = str(ROOT / "fonts/instrument-serif-latin-400-italic.woff")
F_JP = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"

BG = (242, 241, 238)
INK = (27, 26, 46)
ACCENT = (97, 90, 207)       # indigo 600
ACCENT_LT = (194, 194, 255)  # indigo 300, for the dark frame
MUTED = (178, 176, 192)
SAKURA = (216, 106, 146)
WHITE = (255, 255, 255)


# ---------- helpers ----------
@lru_cache(None)
def font(path, size):
    return ImageFont.truetype(path, size)


def ease_out(p):
    p = max(0.0, min(1.0, p))
    return 1 - (1 - p) ** 3


def ease_back(p, s=1.7):
    p = max(0.0, min(1.0, p))
    p -= 1
    return 1 + (s + 1) * p ** 3 + s * p ** 2


def text_img(txt, fnt, fill, stroke=0):
    """Render text tightly into an RGBA image (cached by args)."""
    return _text_img(txt, fnt.path, fnt.size, fill, stroke)


@lru_cache(None)
def _text_img(txt, path, size, fill, stroke):
    f = font(path, size)
    l, t, r, b = f.getbbox(txt, stroke_width=stroke)
    pad = 30
    im = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad - l, pad - t), txt, font=f, fill=fill, stroke_width=stroke, stroke_fill=fill)
    return im


def paste_fx(frame, layer, cx, cy, t, t0, dur=0.4, rise=36, blur=10, scale_from=None, t_out=None):
    """Blur-in + rise (or pop) entrance, optional fade out. cx,cy = center."""
    if t < t0:
        return
    p = ease_out((t - t0) / dur)
    a = p
    if t_out is not None and t > t_out:
        a *= max(0.0, 1 - (t - t_out) / 0.2)
    if a <= 0:
        return
    img = layer
    if scale_from is not None:
        s = scale_from + (1 - scale_from) * ease_back((t - t0) / dur)
        if abs(s - 1) > 0.01:
            img = img.resize((max(1, int(img.width * s)), max(1, int(img.height * s))), Image.BILINEAR)
    r = round((1 - p) * blur)
    if r >= 1:
        img = img.filter(ImageFilter.GaussianBlur(r))
    if a < 1:
        img = img.copy()
        img.putalpha(img.getchannel("A").point(lambda v: int(v * a)))
    dy = 0 if scale_from is not None else (1 - p) * rise
    frame.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2 + dy)))


def shadow_box(size, radius, fill=(255, 255, 255, 245), shadow=(40, 30, 80, 60), blur=24, offset=12):
    w, h = size
    pad = blur * 2
    im = Image.new("RGBA", (w + pad * 2, h + pad * 2 + offset), (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + offset, pad + w, pad + h + offset), radius, fill=shadow)
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))
    ImageDraw.Draw(im).rounded_rectangle((pad, pad, pad + w, pad + h), radius, fill=fill)
    return im, pad


# ---------- plates ----------
class Plate:
    """Background for a scene: a still with a slow push-in (Mock 1)."""

    def __init__(self, path, z0=1.0, z1=1.06, shrink=None, cy=0.5):
        src = Image.open(path).convert("RGB")
        s = W * 1.1 / src.width
        src = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
        if shrink:  # place smaller on a matching background (for the map card)
            bg = Image.new("RGB", src.size, src.getpixel((src.width // 2, 12)))
            small = src.resize((int(src.width * shrink), int(src.height * shrink)), Image.LANCZOS)
            feather = Image.new("L", small.size, 0)
            ImageDraw.Draw(feather).rectangle((60, 60, small.width - 60, small.height - 60), fill=255)
            feather = feather.filter(ImageFilter.GaussianBlur(30))
            bg.paste(small, ((src.width - small.width) // 2, int((src.height - small.height) * 0.47)), feather)
            src = bg
        self.src, self.z0, self.z1, self.cy = src, z0, z1, cy

    def get(self, u):  # u in [0,1] across the scene
        z = self.z0 + (self.z1 - self.z0) * u
        cw, ch = W / z, H / z  # src is 1.1x wide, so z=1 already leaves some margin
        cx, cy = self.src.width / 2, self.src.height * self.cy
        box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
        return self.src.resize((W, H), Image.BILINEAR, box=box).convert("RGBA")


# ---------- typography components ----------
def headline(frame, t, t0, l1, l2, y=330, dark=False, size2=108, gap=92):
    c1 = WHITE if dark else INK
    c2 = ACCENT_LT if dark else ACCENT
    a = text_img(l1, font(F_SANS_M, 66), c1)
    b = text_img(l2, font(F_SERIF_I, size2), c2)
    paste_fx(frame, a, W / 2, y, t, t0)
    paste_fx(frame, b, W / 2, y + gap, t, t0 + 0.18)


CHAPTERS = ["RIP", "THE PROBLEM", "HOW IT WORKS", "THE WIN"]


def chapter_pills(frame, t, t0, active, dark=False):
    d = ImageDraw.Draw(frame)
    f = font(F_SANS_SB, 24)
    items = []
    for i in range(4):
        label = f"0{i + 1}" + (f"  ·  {CHAPTERS[i]}" if i == active else "")
        items.append((label, d.textlength(label, font=f) + 36))
    total = sum(w for _, w in items) + 12 * 3
    x = (W - total) / 2
    a = ease_out((t - t0) / 0.3)
    if a <= 0:
        return
    for i, (label, w) in enumerate(items):
        on = i == active
        fill = (*INK, int(235 * a)) if on else (*((60, 58, 90) if dark else (226, 224, 234)), int(255 * a))
        tc = (*WHITE, int(255 * a)) if on else (*MUTED, int(255 * a))
        d.rounded_rectangle((x, 118, x + w, 162), 22, fill=fill)
        d.text((x + 18, 126), label, font=f, fill=tc)
        x += w + 12


class Captions:
    """Word-by-word karaoke caption from ElevenLabs character alignment."""

    def __init__(self, name, start):
        a = json.loads((AUD / f"{name}.align.json").read_text())
        words, cur, ws = [], "", None
        for ch, st in zip(a["chars"], a["start"]):
            if ch == " ":
                if cur:
                    words.append((cur, ws + start))
                cur, ws = "", None
            else:
                if ws is None:
                    ws = st
                cur += ch
        if cur:
            words.append((cur, ws + start))
        self.words, self.start, self.end = words, start, start + a["end"][-1]

    def draw(self, frame, t, dark=False):
        if not (self.start - 0.1 <= t <= self.end + 0.35):
            return
        d = ImageDraw.Draw(frame)
        f = font(F_SANS_SB, 52)
        sp = d.textlength(" ", font=f)
        lines, line, lw = [], [], 0
        for w, st in self.words:
            ww = d.textlength(w, font=f)
            if line and lw + sp + ww > 900:
                lines.append((line, lw)); line, lw = [], 0
            line.append((w, st, ww)); lw += (sp if lw else 0) + ww
        lines.append((line, lw))
        y = 1640 - (len(lines) - 1) * 36
        fade = min(1.0, (t - self.start + 0.1) / 0.15, (self.end + 0.35 - t) / 0.2)
        cur_idx = max([i for i, (_, st) in enumerate(self.words) if st <= t] or [-1])
        k = 0
        for line, lw in lines:
            x = (W - lw) / 2
            for w, st, ww in line:
                if k == cur_idx:
                    col = ACCENT_LT if dark else ACCENT
                elif k < cur_idx:
                    col = WHITE if dark else INK
                else:
                    col = (110, 108, 140) if dark else MUTED
                d.text((x, y), w, font=f, fill=(*col, int(255 * fade)))
                x += ww + sp
                k += 1
            y += 72


# ---------- the cut ----------
def build_timeline():
    S = {}
    t = 0.0
    for name, dur in [("s1", 2.8), ("s2", 3.6), ("s3", 1.8), ("s4", 4.0), ("s5", 3.2), ("s6", 2.8), ("s7", 3.4), ("s8", 3.6)]:
        S[name] = (t, t + dur)
        t += dur
    vo = {  # VO file -> absolute start
        "vo1": S["s1"][0] + 0.3, "vo2": S["s2"][0] + 0.15, "vo3": S["s3"][0] + 0.2, "vo4": S["s4"][0] + 0.15,
        "jp1": S["s5"][0] + 0.15, "vo5": S["s5"][0] + 1.4, "vo6": S["s6"][0] + 0.15, "vo7": S["s7"][0] + 0.15,
        "vo8": S["s8"][0] + 1.15,
    }
    return S, vo, t


def render(out_video, plates_override=None, scale=1.0):
    S, VO, total = build_timeline()
    plates = {
        "s1": Plate(IMG / "p1.jpg", 1.0, 1.05), "s2": Plate(IMG / "p2.jpg", 1.04, 1.0),
        "s3": Plate(IMG / "p3.jpg", 1.0, 1.08), "s4": Plate(IMG / "p4.jpg", 1.0, 1.04),
        "s5": Plate(IMG / "p5.jpg", 1.0, 1.1), "s6": Plate(IMG / "p6.jpg", 1.0, 1.04, shrink=0.66),
        "s7": Plate(IMG / "p7.jpg", 1.0, 1.05), "s8": Plate(IMG / "p8.jpg", 1.0, 1.03),
    }
    if plates_override:
        plates.update(plates_override)
    caps = {k: Captions(k, v) for k, v in VO.items() if k.startswith("vo") and k not in ("vo1", "vo3", "vo5", "vo7", "vo8")}
    vo5 = Captions("vo5", VO["vo5"])

    ow, oh = int(W * scale) // 2 * 2, int(H * scale) // 2 * 2
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-vf", f"scale={ow}:{oh}",
                           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", str(out_video)],
                          stdin=subprocess.PIPE)
    n = round(total * FPS)
    for i in range(n):
        t = i / FPS
        scene = next(k for k, (a, b) in S.items() if a <= t < b)
        a, b = S[scene]
        lt = t - a
        fr = plates[scene].get(lt / (b - a))
        # cut transition: blur-in of the plate
        if lt < 0.22:
            r = int((1 - lt / 0.22) * 16)
            if r:
                fr = fr.resize((W // 4, H // 4)).filter(ImageFilter.GaussianBlur(r / 4)).resize((W, H))

        if scene == "s1":
            chapter_pills(fr, t, a + 0.1, 0)
            headline(fr, t, a + 0.25, "Say goodbye to", "doomscrolling.")
        elif scene == "s2":
            chapter_pills(fr, t, a, 1)
            headline(fr, t, a + 0.15, "Hours of scrolling,", "nothing to show.")
            # screen-time chip counting up
            if t > a + 0.5:
                mins = int(47 + (192 - 47) * ease_out((t - a - 0.5) / 2.6))
                chip, pad = shadow_box((450, 96), 48)
                d = ImageDraw.Draw(chip)
                d.text((pad + 34, pad + 26), "Screen time", font=font(F_SANS_M, 34), fill=MUTED)
                d.text((pad + 258, pad + 22), f"{mins // 60}h {mins % 60:02d}m", font=font(F_SANS_B, 38), fill=SAKURA)
                paste_fx(fr, chip, W / 2, 1470, t, a + 0.5, scale_from=0.7)
        elif scene == "s3":
            headline(fr, t, a + 0.15, "Meet", "Upscroll.", y=790, dark=True, size2=210, gap=150)
        elif scene == "s4":
            chapter_pills(fr, t, a, 2)
            headline(fr, t, a + 0.15, "Your feed,", "now in Japanese.", y=250)
            swap = a + 1.75
            fe, fj = font(F_SANS_B, 46), font(F_JP, 50)
            if t < swap:
                pill, pad = shadow_box((470, 92), 26, fill=(20, 18, 50, 200), shadow=(0, 0, 0, 0))
                d = ImageDraw.Draw(pill)
                d.text((pad + 470 / 2 - d.textlength("I'm so tired.", font=fe) / 2, pad + 18), "I'm so tired.", font=fe, fill=WHITE)
                paste_fx(fr, pill, 539, 1300, t, a + 0.5, t_out=swap - 0.05)
            else:
                pill, pad = shadow_box((500, 104), 28, fill=(20, 18, 50, 210), shadow=(0, 0, 0, 0))
                d = ImageDraw.Draw(pill)
                x0 = pad + 40
                d.text((x0, pad + 24), "I'm so", font=fe, fill=WHITE)
                jx = x0 + d.textlength("I'm so ", font=fe) + 10
                jw = d.textlength("つかれた", font=fj)
                d.rounded_rectangle((jx - 14, pad + 14, jx + jw + 14, pad + 90), 20, fill=SAKURA)
                d.text((jx, pad + 22), "つかれた", font=fj, fill=WHITE, stroke_width=1, stroke_fill=WHITE)
                paste_fx(fr, pill, 539, 1300, t, swap, dur=0.35, scale_from=0.75)
        elif scene == "s5":
            chapter_pills(fr, t, a, 2)
            card, pad = shadow_box((740, 330), 48)
            d = ImageDraw.Draw(card)
            jt = text_img("つかれた", font(F_JP, 132), INK, stroke=3)
            card.alpha_composite(jt, (int(pad + 370 - jt.width / 2), pad + 20))
            sub = "tsukareta  ·  tired"
            d.text((pad + 370 - d.textlength(sub, font=font(F_SANS_M, 44)) / 2, pad + 218), sub, font=font(F_SANS_M, 44), fill=(110, 108, 140))
            paste_fx(fr, card, W / 2, 620, t, a + 0.1, dur=0.45, scale_from=0.6)
            # list carousel synced to "Hear it. Say it. Keep it."
            starts = [st for w, st in vo5.words if w.lower().startswith(("hear", "say", "keep"))]
            for k, word in enumerate(["Hear it.", "Say it.", "Keep it."]):
                on = k < len(starts) and t >= starts[k] and (k + 1 >= len(starts) or t < starts[k + 1])
                done = k < len(starts) and t >= starts[k]
                col = INK if on else ((150, 148, 170) if done else MUTED)
                lay = text_img(word, font(F_SANS_B, 92), col)
                y = 1150 + k * 130
                paste_fx(fr, lay, W / 2 + 20, y, t, a + 1.1 + k * 0.08)
                if on:
                    ImageDraw.Draw(fr).ellipse((W / 2 - lay.width / 2 - 18, y - 12, W / 2 - lay.width / 2 + 6, y + 12), fill=ACCENT)
        elif scene == "s6":
            chapter_pills(fr, t, a, 3)
            headline(fr, t, a + 0.15, "Every scroll,", "a step through Japan.", y=255)
        elif scene == "s7":
            chapter_pills(fr, t, a, 3)
            headline(fr, t, a + 0.15, "Scrolling isn't dead.", "Mindless scrolling is.")
        elif scene == "s8":
            word = "Upscroll"
            t_type0, t_click = a + 0.2, a + 1.05
            if t < t_click + 0.15:
                pill, pad = shadow_box((640, 112), 56)
                d = ImageDraw.Draw(pill)
                d.ellipse((pad + 40, pad + 34, pad + 74, pad + 68), outline=MUTED, width=5)
                d.line((pad + 70, pad + 64, pad + 84, pad + 78), fill=MUTED, width=5)
                nch = max(0, min(len(word), int((t - t_type0) / 0.09)))
                d.text((pad + 110, pad + 26), word[:nch], font=font(F_SANS_M, 52), fill=INK)
                if int(t * 3) % 2 == 0 or nch < len(word):
                    cx = pad + 112 + d.textlength(word[:nch], font=font(F_SANS_M, 52))
                    d.line((cx, pad + 30, cx, pad + 84), fill=ACCENT, width=4)
                d.ellipse((pad + 560, pad + 32, pad + 608, pad + 80), fill=ACCENT if nch == len(word) else (226, 224, 234))
                paste_fx(fr, pill, W / 2, 760, t, a + 0.05, t_out=t_click)
            else:
                paste_fx(fr, text_img("Upscroll", font(F_SANS_B, 150), INK), W / 2, 640, t, t_click + 0.1, dur=0.45, scale_from=0.8)
                paste_fx(fr, text_img("Learn Japanese", font(F_SANS_M, 58), INK), W / 2, 800, t, t_click + 0.35)
                paste_fx(fr, text_img("while you scroll.", font(F_SERIF_I, 92), ACCENT), W / 2, 885, t, t_click + 0.5)

        for c in caps.values():
            c.draw(fr, t, dark=(scene == "s3"))
        ff.stdin.write(fr.convert("RGB").tobytes())
    ff.stdin.close()
    ff.wait()
    return S, VO, total


def mix_audio(S, VO, total, out):
    cues = [(k, v, 0) for k, v in VO.items()]
    s = lambda k: S[k][0]
    cues += [
        ("sfx_scrollloop", 0.0, -12), ("sfx_click", s("s1") + 0.25, -10),
        ("sfx_swipe", s("s2") - 0.12, -6), ("sfx_pop", s("s2") + 0.5, -10),
        ("sfx_riser", s("s3") - 1.9, -12), ("sfx_thud", s("s3"), -4),
        ("sfx_swipe", s("s4") - 0.12, -6), ("sfx_pop", s("s4") + 1.75, -3),
        ("sfx_pop", s("s5") + 0.1, -6), ("sfx_record", s("s5") + 1.4, -12),
        ("sfx_swipe", s("s6") - 0.12, -6), ("sfx_swipe", s("s7") - 0.12, -6),
        ("sfx_typing", s("s8") + 0.2, -8), ("sfx_click", s("s8") + 1.05, -4), ("sfx_chime", s("s8") + 1.1, -6),
    ]
    inputs, chain, labels = [], [], []
    for i, (f, st, g) in enumerate(cues):
        inputs += ["-i", str(AUD / f"{f}.mp3")]
        ms = int(st * 1000)
        chain.append(f"[{i}:a]aresample=48000,volume={g}dB,adelay={ms}|{ms}[a{i}]")
        labels.append(f"[a{i}]")
    m = len(cues)
    inputs += ["-stream_loop", "2", "-i", str(AUD / "music.mp3")]
    s3 = s("s3")
    chain.append(f"[{m}:a]aresample=48000,atrim=0:{total},volume='if(lt(t,{s3}),0.22,if(lt(t,{s3}+0.3),0.05,0.4))':eval=frame,"
                 f"afade=t=in:d=0.6,afade=t=out:st={total - 1.4}:d=1.4[mus]")
    chain.append(f"{''.join(labels)}amix=inputs={m}:normalize=0,asplit=2[fx][side]")
    chain.append("[mus][side]sidechaincompress=threshold=0.05:ratio=4:attack=20:release=300[duck]")
    chain.append(f"[fx][duck]amix=inputs=2:normalize=0,apad,atrim=0:{total},loudnorm=I=-14:TP=-1.5:LRA=11[aout]")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(chain),
                    "-map", "[aout]", "-ar", "48000", "-c:a", "aac", "-b:a", "192k", str(out)], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "mock1/upscroll_mock1.mp4"))
    ap.add_argument("--scale", type=float, default=1.0)
    a = ap.parse_args()
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    silent, mix = out.with_suffix(".silent.mp4"), out.with_suffix(".m4a")
    S, VO, total = render(silent, scale=a.scale)
    mix_audio(S, VO, total, mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(silent), "-i", str(mix), "-c", "copy",
                    "-t", f"{total:.3f}", "-movflags", "+faststart", str(out)], check=True)
    silent.unlink(); mix.unlink()
    print(out, f"{total:.1f}s")


if __name__ == "__main__":
    main()
