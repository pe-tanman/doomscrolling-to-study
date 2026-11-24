"""Upscroll promo, Mock 1: animatic built from stills + ElevenLabs audio.

Story: you skip a 5-minute lesson but doomscroll for hours -> Meet Upscroll: your
Shorts become Japanese lessons -> a word swaps into the subtitles -> a practice
card slides over the Short -> keep scrolling -> journey map -> App Store end card.

All UI (phone, Shorts chrome, Upscroll's glass subtitle, word chip, practice card)
is drawn here, modelled on the app's SwiftUI views (Theme.swift, SubtitleOverlay.swift,
LearningCard.swift), so nothing in the UI is AI-generated. The mascot uses the app's
own art. Every frame is drawn in Python and piped to ffmpeg.

Usage: python3 build_mock1.py [--out mock1/upscroll_mock1.mp4] [--scale 1.0]
"""
import argparse
import json
import math
import subprocess
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).parent
IMG, AUD, FONTS = ROOT / "img", ROOT / "audio", ROOT / "fonts"
ASSETS = ROOT.parent / "ios/Upscroll/Assets.xcassets"
W, H, FPS = 1080, 1920, 30

# Fonts: Nunito stands in for SF Rounded (the app's UI font), M PLUS Rounded 1c for
# Hiragino Maru Gothic (the app's Japanese font).
F_RND9 = str(FONTS / "nunito-latin-900-normal.woff")
F_RND8 = str(FONTS / "nunito-latin-800-normal.woff")
F_JP = str(FONTS / "m-plus-rounded-1c-japanese-800-normal.woff")
BADGE = ROOT / "brand/app-store-badge.png"  # Apple's official badge, from brand/download-on-the-app-store.svg

# Brand colours (Theme.swift)
INK = (41, 40, 80)            # neutral 900
INK2 = (85, 86, 116)          # neutral 700
INDIGO = (97, 90, 207)        # indigo 600
INDIGO_D = (77, 70, 177)      # indigo 700
WHITE = (255, 255, 255)
GOLD = (255, 209, 90)         # Brand.OnDark.gold: the Japanese word, the main button
PINK = (248, 169, 199)        # Brand.OnDark.pink: the NEW tag
RIGHT = (134, 240, 159)       # Brand.OnDark.right
SAKURA = (216, 106, 146)


# ---------- helpers ----------
@lru_cache(None)
def font(path, size):
    return ImageFont.truetype(path, size)


def clamp(p):
    return max(0.0, min(1.0, p))


def ease_out(p):
    return 1 - (1 - clamp(p)) ** 3


def ease_in_out(p):
    p = clamp(p)
    return 3 * p * p - 2 * p * p * p


def ease_back(p, s=1.7):
    p = clamp(p) - 1
    return 1 + (s + 1) * p ** 3 + s * p ** 2


@lru_cache(None)
def text_img(txt, path, size, fill, stroke=0):
    f = font(path, size)
    l, t, r, b = f.getbbox(txt, stroke_width=stroke)
    pad = 24
    im = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad - l, pad - t), txt, font=f, fill=fill, stroke_width=stroke, stroke_fill=fill)
    return im


def with_alpha(img, a):
    if a >= 1:
        return img
    img = img.copy()
    img.putalpha(img.getchannel("A").point(lambda v: int(v * a)))
    return img


def paste_fx(frame, layer, cx, cy, t, t0, dur=0.4, rise=36, blur=10, scale_from=None, t_out=None):
    """Blur-in + rise (or pop) entrance and optional fade out; cx, cy = centre."""
    if t < t0:
        return
    p = ease_out((t - t0) / dur)
    a = p
    if t_out is not None and t > t_out:
        a *= clamp(1 - (t - t_out) / 0.2)
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
    img = with_alpha(img, a)
    dy = 0 if scale_from is not None else (1 - p) * rise
    frame.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2 + dy)))


def shadow_box(size, radius, fill=(255, 255, 255, 245), shadow=(41, 40, 80, 60), blur=24, offset=12):
    w, h = size
    pad = blur * 2
    im = Image.new("RGBA", (w + pad * 2, h + pad * 2 + offset), (0, 0, 0, 0))
    if shadow[3]:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((pad, pad + offset, pad + w, pad + h + offset), radius, fill=shadow)
        im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))
    ImageDraw.Draw(im).rounded_rectangle((pad, pad, pad + w, pad + h), radius, fill=fill)
    return im, pad


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def glass(base, box, radius, tint=(0, 0, 0, 120), blur=22):
    """Frosted glass like the app's Liquid Glass cards: blur what's behind, tint, hairline edge."""
    x0, y0, x1, y1 = [int(v) for v in box]
    region = base.crop((x0, y0, x1, y1)).filter(ImageFilter.GaussianBlur(blur))
    region.alpha_composite(Image.new("RGBA", region.size, tint))
    edge = Image.new("RGBA", region.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((0, 0, region.width - 1, region.height - 1), radius, outline=(255, 255, 255, 70), width=2)
    region.alpha_composite(edge)
    base.paste(region, (x0, y0), rounded_mask(region.size, radius))


def cover(img, size):
    return ImageOps.fit(img, size, Image.LANCZOS)


# ---------- mascot (the app's own art) ----------
@lru_cache(None)
def mascot_img(name, size):
    im = Image.open(ASSETS / f"mascot_{name}.imageset/mascot_{name}.png").convert("RGBA")
    return im.resize((size, size), Image.LANCZOS)


def mascot(frame, name, cx, cy, size, t, t0, move="bob", flip=False, ground=True):
    """Hop in, then keep moving: bob, breathe (sleepy), wave (rock side to side), cheer or walk."""
    if t < t0:
        return
    lt = t - t0
    im = mascot_img(name, size)
    if flip:
        im = ImageOps.mirror(im)
    sx = sy = 1.0
    ang = 0.0
    dy = 0.0
    hop = ease_back(lt / 0.45, 2.2)
    if lt < 0.45:  # hop in from below with a squash
        dy = (1 - hop) * 220
        sy = 0.7 + 0.3 * hop
        sx = 1.15 - 0.15 * hop
    if move == "bob":
        dy += math.sin(lt * 2 * math.pi * 1.1) * 12
        ang = math.sin(lt * 2 * math.pi * 0.8) * 3
    elif move == "breathe":
        sy *= 1 + 0.03 * math.sin(lt * 2 * math.pi * 0.7)
        sx *= 1 - 0.015 * math.sin(lt * 2 * math.pi * 0.7)
    elif move == "wave":
        ang = math.sin(lt * 2 * math.pi * 1.6) * 6
        dy += abs(math.sin(lt * 2 * math.pi * 1.6)) * -10
    elif move == "cheer":
        jump = abs(math.sin(lt * 2 * math.pi * 1.4))
        dy -= jump * 40
        sy *= 1 + 0.05 * jump
    elif move == "walk":
        dy += -abs(math.sin(lt * 2 * math.pi * 2.6)) * 14
        ang = math.sin(lt * 2 * math.pi * 2.6) * 5
    w, h = int(size * sx), int(size * sy)
    im = im.resize((w, h), Image.BILINEAR)
    if abs(ang) > 0.2:
        im = im.rotate(ang, resample=Image.BICUBIC, expand=True)
    if ground:  # soft contact shadow
        sh = Image.new("RGBA", (int(size * 0.6), 40), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((0, 0, sh.width - 1, 39), fill=(41, 40, 80, 50))
        sh = sh.filter(ImageFilter.GaussianBlur(8))
        frame.alpha_composite(with_alpha(sh, clamp(lt / 0.3)), (int(cx - sh.width / 2), int(cy + size * 0.44)))
    frame.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2 + dy)))


# ---------- backgrounds ----------
class Plate:
    """A still background with a slow push-in."""

    def __init__(self, path, z0=1.0, z1=1.05):
        src = Image.open(path).convert("RGB")
        s = W * 1.1 / src.width
        self.src = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
        self.z0, self.z1 = z0, z1

    def get(self, u):
        z = self.z0 + (self.z1 - self.z0) * u
        cw, ch = W / z, H / z
        cx, cy = self.src.width / 2, self.src.height / 2
        return self.src.resize((W, H), Image.BILINEAR, box=(cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)).convert("RGBA")


# ---------- typography ----------
def headline(frame, t, t0, l1, l2, y=200, dark=False, size1=60, size2=96):
    c1 = (235, 235, 255) if dark else INK2
    c2 = WHITE if dark else INDIGO_D
    t1 = kinetic(frame, t, t0, l1, F_RND8, size1, c1, y)
    kinetic(frame, t, t1 + 0.05, l2, F_RND9, size2, c2, y + size1 * 0.6 + size2 * 0.62)


# ---------- the phone and the Shorts feed ----------
SCR_W, SCR_H = 640, 1386       # iPhone-like 19.5:9 screen
BEZEL, R_OUT, R_SCR = 20, 100, 82
SHORTS = {
    "dog": ("shorts/dog.jpg", "@goldenhours", "he heard the treat bag", "48K"),
    "skate": ("shorts/skate.jpg", "@street.kick", "first clean kickflip!!", "12K"),
    "bowl": ("shorts/bowl.jpg", "@morning.bowls", "5-minute breakfast", "9.1K"),
    "train": ("shorts/train.jpg", "@tokyo.daily", "morning commute in Tokyo", "22K"),
    "tired": ("shorts/tired.jpg", "@deskdiaries", "me at 4pm every day", "31K"),
    "ramen": ("shorts/ramen_cat.jpg", "@tokyo.eats", "best ramen counter in Tokyo", "64K"),
}


@lru_cache(None)
def short_still(name):
    return cover(Image.open(IMG / SHORTS[name][0]).convert("RGB"), (int(SCR_W * 1.08), int(SCR_H * 1.08))).convert("RGBA")


@lru_cache(None)
def icon(kind, size=56):
    """Generic short-video side icons (no platform branding) and small UI glyphs."""
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "heart":
        pts = []
        for i in range(120):
            a = i / 120 * 2 * math.pi
            x = 16 * math.sin(a) ** 3
            y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
            pts.append((s / 2 + x * s / 36, s / 2 + y * s / 36 - s * 0.02))
        d.polygon(pts, fill=WHITE)
    elif kind == "comment":
        d.rounded_rectangle((s * .1, s * .14, s * .9, s * .74), s * .26, fill=WHITE)
        d.polygon([(s * .26, s * .68), (s * .22, s * .92), (s * .48, s * .72)], fill=WHITE)
    elif kind == "share":
        d.polygon([(s * .55, s * .12), (s * .92, s * .45), (s * .55, s * .78), (s * .55, s * .6),
                   (s * .12, s * .62), (s * .22, s * .3), (s * .55, s * .3)], fill=WHITE)
    elif kind == "dots":
        for i in range(3):
            d.ellipse((s * (.16 + i * .26), s * .4, s * (.32 + i * .26), s * .56), fill=WHITE)
    elif kind == "speaker":
        d.polygon([(s * .12, s * .38), (s * .32, s * .38), (s * .56, s * .16), (s * .56, s * .84), (s * .32, s * .62), (s * .12, s * .62)], fill=GOLD)
        d.arc((s * .5, s * .28, s * .78, s * .72), -55, 55, fill=GOLD, width=int(s * .07))
        d.arc((s * .5, s * .12, s * .95, s * .88), -55, 55, fill=GOLD, width=int(s * .07))
    elif kind == "check":
        d.ellipse((0, 0, s - 1, s - 1), fill=RIGHT)
        d.line([(s * .27, s * .52), (s * .44, s * .68), (s * .74, s * .34)], fill=(20, 60, 30), width=int(s * .11), joint="curve")
    elif kind == "pause":
        d.rounded_rectangle((s * .28, s * .2, s * .43, s * .8), s * .05, fill=WHITE)
        d.rounded_rectangle((s * .57, s * .2, s * .72, s * .8), s * .05, fill=WHITE)
    elif kind == "bell":
        d.pieslice((s * .2, s * .14, s * .8, s * .74), 180, 360, fill=WHITE)
        d.rectangle((s * .2, s * .44, s * .8, s * .66), fill=WHITE)
        d.rounded_rectangle((s * .12, s * .62, s * .88, s * .72), s * .04, fill=WHITE)
        d.ellipse((s * .42, s * .72, s * .58, s * .86), fill=WHITE)
    elif kind == "hand":
        d.rounded_rectangle((s * .38, s * .08, s * .54, s * .6), s * .08, fill=WHITE)
        d.rounded_rectangle((s * .24, s * .44, s * .8, s * .92), s * .18, fill=WHITE)
    return im.resize((size, size), Image.LANCZOS)


def shorts_chrome(scr, name, progress):
    """Side actions, handle, caption and progress bar over a bottom scrim."""
    _, handle, caption, likes = SHORTS[name]
    scrim = Image.new("RGBA", (SCR_W, 520), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    for y in range(520):
        sd.line((0, y, SCR_W, y), fill=(0, 0, 0, int(150 * (y / 520) ** 1.6)))
    scr.alpha_composite(scrim, (0, SCR_H - 520))
    d = ImageDraw.Draw(scr)
    x = SCR_W - 70
    for k, (kind, label) in enumerate([("heart", likes), ("comment", "512"), ("share", "Share"), ("dots", "")]):
        y = 760 + k * 128
        scr.alpha_composite(icon(kind), (x - 28, y))
        if label:
            f = font(F_RND8, 22)
            d.text((x - d.textlength(label, font=f) / 2, y + 62), label, font=f, fill=WHITE)
    d.ellipse((28, SCR_H - 196, 84, SCR_H - 140), fill=(200, 196, 235), outline=WHITE, width=3)
    d.text((98, SCR_H - 190), handle, font=font(F_RND8, 28), fill=WHITE)
    d.text((30, SCR_H - 124), caption, font=font(F_RND8, 26), fill=(240, 240, 248))
    scr.alpha_composite(Image.new("RGBA", (SCR_W, 8), (255, 255, 255, 70)), (0, SCR_H - 8))
    d.rectangle((0, SCR_H - 8, int(SCR_W * clamp(progress)), SCR_H), fill=WHITE)


def short_frame(name, lt, chrome=True, dim=0.0, blur=0):
    """One Short at local time lt, with a slow drift so the 'video' feels alive."""
    src = short_still(name)
    z = 1 + 0.02 * math.sin(lt * 0.9)
    big = src.resize((int(src.width * z), int(src.height * z)), Image.BILINEAR)
    ox = (big.width - SCR_W) / 2 + math.sin(lt * 0.7) * 10
    oy = (big.height - SCR_H) / 2 + math.cos(lt * 0.6) * 10
    scr = big.crop((int(ox), int(oy), int(ox) + SCR_W, int(oy) + SCR_H))
    if blur:
        scr = scr.filter(ImageFilter.GaussianBlur(blur))
    if chrome:
        shorts_chrome(scr, name, (lt % 8) / 8)
    if dim:
        scr.alpha_composite(Image.new("RGBA", scr.size, (10, 8, 30, int(170 * dim))))
    return scr


@lru_cache(None)
def phone_shell():
    w, h = SCR_W + BEZEL * 2, SCR_H + BEZEL * 2
    pad = 60
    im = Image.new("RGBA", (w + pad * 2, h + pad * 2 + 30), (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 30, pad + w, pad + h + 30), R_OUT, fill=(41, 40, 80, 90))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(36)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((pad, pad, pad + w, pad + h), R_OUT, fill=(22, 22, 30))
    d.rounded_rectangle((pad + 3, pad + 3, pad + w - 3, pad + h - 3), R_OUT - 3, outline=(90, 90, 110), width=3)
    return im, pad


def draw_phone(frame, scr, cx, cy, ang=0.0, scale=1.0, alpha=1.0):
    shell, pad = phone_shell()
    ph = shell.copy()
    ph.paste(scr, (pad + BEZEL, pad + BEZEL), rounded_mask(scr.size, R_SCR))
    d = ImageDraw.Draw(ph)
    iw = 190
    d.rounded_rectangle((pad + BEZEL + SCR_W / 2 - iw / 2, pad + BEZEL + 22, pad + BEZEL + SCR_W / 2 + iw / 2, pad + BEZEL + 78), 28, fill=(8, 8, 12))
    if scale != 1:
        ph = ph.resize((int(ph.width * scale), int(ph.height * scale)), Image.BILINEAR)
    ph = tilt(ph, ang)
    frame.alpha_composite(with_alpha(ph, alpha), (int(cx - ph.width / 2), int(cy - ph.height / 2)))


# ---------- Upscroll's learning layer (as in SubtitleOverlay.swift / LearningCard.swift) ----------
SUB_Y = 1010  # subtitle row inside the screen


def subtitle_layer(scr, t, t_in, t_swap):
    """Glass caption over the Short; one word swaps into Japanese in gold, with the word chip above."""
    if t < t_in:
        return
    fe, fj = font(F_RND8, 40), font(F_JP, 44)
    d = ImageDraw.Draw(scr)
    swapped = t >= t_swap
    parts = [("Ugh… I'm so", fe), ("つかれた" if swapped else "tired.", fj if swapped else fe)]
    widths = [d.textlength(p, font=f) for p, f in parts]
    total = sum(widths) + 14
    x0, y0 = (SCR_W - total) / 2, SUB_Y
    glass(scr, (x0 - 26, y0 - 18, x0 + total + 26, y0 + 70), 26, tint=(0, 0, 0, 90))
    d = ImageDraw.Draw(scr)
    x = x0
    for (p, f), w in zip(parts, widths):
        if swapped and f is fj:
            pop = ease_back((t - t_swap) / 0.35, 2.5)
            lay = text_img(p, F_JP, max(8, int(44 * (0.6 + 0.4 * pop))), GOLD, 1)
            scr.alpha_composite(lay, (int(x + w / 2 - lay.width / 2), int(y0 + 26 - lay.height / 2)))
        else:
            d.text((x, y0 + 2), p, font=f, fill=WHITE)
        x += w + 14
    if swapped:  # word chip: kana (gold) + romaji + tap hand on a glass capsule
        a = ease_out((t - t_swap - 0.15) / 0.3)
        if a > 0:
            cd = ImageDraw.Draw(scr)
            kana, rom = "つかれた", "tsukareta"
            kw, rw = cd.textlength(kana, font=font(F_JP, 34)), cd.textlength(rom, font=font(F_RND8, 28))
            cwid = kw + rw + 44 + 60
            cx0 = (SCR_W - cwid) / 2
            box = (int(cx0), y0 - 110, int(cx0 + cwid), y0 - 44)
            sub = scr.crop(box).filter(ImageFilter.GaussianBlur(16))
            sub.alpha_composite(Image.new("RGBA", sub.size, (0, 0, 0, 110)))
            cap = Image.new("RGBA", sub.size, (0, 0, 0, 0))
            cap.paste(sub, (0, 0), rounded_mask(sub.size, sub.height // 2))
            cdd = ImageDraw.Draw(cap)
            cdd.text((22, 10), kana, font=font(F_JP, 34), fill=GOLD)
            cdd.text((22 + kw + 14, 16), rom, font=font(F_RND8, 28), fill=WHITE)
            cap.alpha_composite(icon("hand", 34), (int(cwid - 52), 16))
            scr.alpha_composite(with_alpha(cap, a), (box[0], int(box[1] + (1 - a) * 20)))


CARD_W, CARD_H, CARD_BOTTOM = 588, 760, 70


def practice_card(scr, t, t0, t_tap, t_continue, t_out):
    """The practice card sliding up over the paused Short."""
    if t < t0:
        return
    cw, ch = CARD_W, CARD_H
    p_in = ease_back((t - t0) / 0.5, 1.2)
    p_out = ease_in_out((t - t_out) / 0.35) if t >= t_out else 0
    x0 = (SCR_W - cw) / 2
    y0 = SCR_H - ch - CARD_BOTTOM + (1 - p_in) * (ch + 120) + p_out * (ch + 160)
    if y0 >= SCR_H - 2:
        return
    glass(scr, (x0, y0, x0 + cw, min(SCR_H, y0 + ch)), 56, tint=(10, 8, 30, 150), blur=26)
    ov = Image.new("RGBA", scr.size, (0, 0, 0, 0))  # translucent fills must blend, not replace
    d = ImageDraw.Draw(ov)
    d.rounded_rectangle((x0 + 30, y0 + 30, x0 + 128, y0 + 74), 22, fill=PINK)
    d.text((x0 + 48, y0 + 32), "NEW", font=font(F_RND9, 28), fill=(0, 0, 0))
    d.text((x0 + cw - 82, y0 + 36), "1/2", font=font(F_RND8, 26), fill=(220, 220, 235))
    jw = d.textlength("つかれた", font=font(F_JP, 96))
    d.text((x0 + 34, y0 + 96), "つかれた", font=font(F_JP, 96), fill=GOLD)
    d.text((x0 + 38, y0 + 222), "tsukareta", font=font(F_RND8, 36), fill=WHITE)
    pulse = 1 + 0.12 * max(0.0, math.sin((t - t0 - 0.3) * 12)) if t0 + 0.3 < t < t0 + 1.3 else 1
    sp = icon("speaker", int(64 * pulse))
    ov.alpha_composite(sp, (int(x0 + 34 + jw + 30 + (64 - sp.width) / 2), int(y0 + 130 + (64 - sp.height) / 2)))
    d.text((x0 + 34, y0 + 300), "What does it mean?", font=font(F_RND8, 36), fill=WHITE)
    for k, opt in enumerate(["hungry", "tired", "happy"]):
        oy = y0 + 368 + k * 96
        right = opt == "tired" and t >= t_tap
        fill = (134, 240, 159, 75) if right else (255, 255, 255, 34)
        d.rounded_rectangle((x0 + 30, oy, x0 + cw - 30, oy + 78), 39, fill=fill, outline=(134, 240, 159, 220) if right else None, width=3)
        d.text((x0 + 62, oy + 15), opt, font=font(F_RND8, 36), fill=WHITE)
        if right:
            s = int(46 * ease_back((t - t_tap) / 0.3, 2.5))
            if s > 4:
                ov.alpha_composite(icon("check", s), (int(x0 + cw - 92 + (46 - s) / 2), int(oy + 16 + (46 - s) / 2)))
    if t >= t_tap + 0.2:  # Continue (gold), after the answer
        a = ease_out((t - t_tap - 0.2) / 0.3)
        press = 0.94 if t_continue <= t < t_continue + 0.15 else 1
        bw, bh = (cw - 60) * press, 84 * press
        bx, by = x0 + cw / 2 - bw / 2, y0 + ch - 116 + (84 - bh) / 2
        d.rounded_rectangle((bx, by, bx + bw, by + bh), bh / 2, fill=(*GOLD, int(255 * a)))
        tw = d.textlength("Continue", font=font(F_RND9, 36))
        d.text((x0 + cw / 2 - tw / 2, by + bh / 2 - 26), "Continue", font=font(F_RND9, 36), fill=(0, 0, 0, int(255 * a)))
    scr.alpha_composite(ov)


def tap_ripple(scr, x, y, t, t0):
    if not (t0 - 0.25 <= t <= t0 + 0.5):
        return
    ov = Image.new("RGBA", scr.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    if t < t0:  # finger approaching
        a = (t - t0 + 0.25) / 0.25
        d.ellipse((x - 34, y - 34, x + 34, y + 34), fill=(255, 255, 255, int(120 * a)))
    else:
        p = (t - t0) / 0.5
        r = 34 + 60 * p
        d.ellipse((x - r, y - r, x + r, y + r), outline=(255, 255, 255, int(200 * (1 - p))), width=6)
        d.ellipse((x - 30, y - 30, x + 30, y + 30), fill=(255, 255, 255, int(150 * (1 - p))))
    scr.alpha_composite(ov)


# ---------- motion effects borrowed from the reference reels ----------
@lru_cache(None)
def word_img(txt, path, size, fill):
    """One word on a fixed-height box (ascent+descent), so words in a line share a baseline."""
    f = font(path, size)
    asc, desc = f.getmetrics()
    w = int(f.getlength(txt)) + 2
    pad = 24
    im = Image.new("RGBA", (w + pad * 2, asc + desc + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad, pad), txt, font=f, fill=fill)
    return im


def kinetic(frame, t, t0, text, path, size, color, cy, stagger=0.07):
    """Words build in one by one with a blur-in and a small rise (Holo / Relocate)."""
    f = font(path, size)
    words = text.split(" ")
    sp = f.getlength(" ")
    widths = [f.getlength(w) for w in words]
    x = W / 2 - (sum(widths) + sp * (len(words) - 1)) / 2
    for k, (w, ww) in enumerate(zip(words, widths)):
        paste_fx(frame, word_img(w, path, size, color), x + ww / 2, cy, t, t0 + k * stagger, dur=0.38, rise=30, blur=14)
        x += ww + sp
    return t0 + len(words) * stagger


def find_coeffs(dst, src):
    import numpy as np
    A, B = [], []
    for (x, y), (X, Y) in zip(dst, src):
        A += [[x, y, 1, 0, 0, 0, -X * x, -X * y], [0, 0, 0, x, y, 1, -Y * x, -Y * y]]
        B += [X, Y]
    return np.linalg.solve(np.array(A, float), np.array(B, float)).tolist()


def tilt(img, ang, persp=0.0011):
    """Rotate an image about its horizontal axis (top edge leans back for ang > 0)."""
    if abs(ang) < 0.3:
        return img
    w, h = img.size
    a = math.radians(ang)
    pts = []
    for x, y in [(0, 0), (w, 0), (w, h), (0, h)]:
        xc, yc = x - w / 2, y - h / 2
        f = 1 / (1 + (-yc * math.sin(a)) * persp)
        pts.append((xc * f, yc * math.cos(a) * f))
    minx, miny = min(p[0] for p in pts), min(p[1] for p in pts)
    maxx, maxy = max(p[0] for p in pts), max(p[1] for p in pts)
    dst = [(px - minx, py - miny) for px, py in pts]
    size = (int(maxx - minx) + 1, int(maxy - miny) + 1)
    return img.transform(size, Image.PERSPECTIVE, find_coeffs(dst, [(0, 0), (w, 0), (w, h), (0, h)]), Image.BICUBIC)


@lru_cache(None)
def aura_blob(color, r):
    im = Image.new("RGBA", (r * 4, r * 4), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((r, r, r * 3, r * 3), fill=(*color, 150))
    return im.resize((r, r), Image.BILINEAR).filter(ImageFilter.GaussianBlur(r / 10)).resize((r * 4, r * 4), Image.BILINEAR)


def aura(frame, t, cx, cy):
    """Soft gradient blobs drifting behind the phone (the blurred blobs in the references)."""
    for k, (col, r, fx, fy, ph) in enumerate([((165, 164, 255), 260, 0.31, 0.23, 0.0), ((250, 177, 201), 230, 0.27, 0.35, 2.1),
                                             ((246, 191, 81), 190, 0.38, 0.29, 4.0)]):
        b = aura_blob(col, r)
        x = cx + math.sin(t * fx * 2 * math.pi + ph) * 260
        y = cy + math.cos(t * fy * 2 * math.pi + ph) * 380
        frame.alpha_composite(b, (int(x - b.width / 2), int(y - b.height / 2)))


@lru_cache(None)
def float_card(name, z):
    """A Short as a floating card; far cards are smaller and blurred."""
    w, h = int(200 * z), int(356 * z)
    im = cover(Image.open(IMG / SHORTS[name][0]).convert("RGB"), (w, h)).convert("RGBA")
    card, pad = shadow_box((w + 10, h + 10), int(26 * z), fill=(255, 255, 255, 255), shadow=(41, 40, 80, 70), blur=18, offset=10)
    card.paste(im, (pad + 5, pad + 5), rounded_mask((w, h), int(22 * z)))
    if z < 0.85:
        card = with_alpha(card.filter(ImageFilter.GaussianBlur((0.85 - z) * 14)), 0.55 + 0.45 * z)
    return card


FLOATERS = [  # (short, x, y0, depth, speed, phase)
    ("skate", 120, 520, 0.6, 1.0, 0.0), ("bowl", 960, 760, 0.65, 1.2, 1.0), ("train", 70, 1320, 0.7, 0.9, 2.0),
    ("dog", 1000, 1500, 0.62, 1.1, 3.0), ("bowl", 140, 980, 1.08, 1.6, 0.5), ("skate", 940, 1180, 1.12, 1.7, 1.5),
    ("train", 980, 420, 1.0, 1.5, 2.5),
]


def floaters(frame, t, lt, front):
    for name, x, y0, z, sp, ph in FLOATERS:
        if (z >= 1.0) != front:
            continue
        card = float_card(name, z)
        y = (y0 - lt * sp * 260 * (1 + lt * 0.6)) % (H + 600) - 300  # drifting up, speeding up
        ang = math.sin(t * 1.3 + ph) * 6
        img = card.rotate(ang, resample=Image.BICUBIC, expand=True)
        a = clamp(lt / 0.4) * clamp((y - 420) / 220)  # fade out before reaching the headline
        if a <= 0:
            continue
        frame.alpha_composite(with_alpha(img, a), (int(x - img.width / 2), int(y - img.height / 2)))


def rolling_digits(chip, x, y, value, period, f, color):
    """Odometer digit: value is a float; the digit rolls up as it moves to the next."""
    v = value % period
    d0 = int(v)
    frac = v - d0
    h = f.getmetrics()[0] + f.getmetrics()[1]
    box = Image.new("RGBA", (int(f.getlength("0")) + 4, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    bd.text((0, -frac * h), str(d0 % period % 10), font=f, fill=color)
    bd.text((0, (1 - frac) * h), str((d0 + 1) % period % 10), font=f, fill=color)
    chip.alpha_composite(box, (int(x), int(y)))
    return box.width


def screen_time_chip(minutes):
    chip, pad = shadow_box((440, 96), 48)
    cd = ImageDraw.Draw(chip)
    cd.text((pad + 34, pad + 22), "Screen time", font=font(F_RND8, 34), fill=INK2)
    f = font(F_RND9, 40)
    ones = minutes % 10
    carry = max(0.0, ones - 9)  # tens roll only during the last tenth of the ones roll
    tens = (minutes // 10) % 6 + carry
    hours = minutes // 60 + (carry if (minutes // 10) % 6 == 5 else 0)
    x, y = pad + 258, pad + 18
    x += rolling_digits(chip, x, y, hours, 10, f, SAKURA)
    cd.text((x, y), "h", font=f, fill=SAKURA)
    x += f.getlength("h ")
    x += rolling_digits(chip, x, y, tens, 6, f, SAKURA)
    x += rolling_digits(chip, x, y, ones, 10, f, SAKURA)
    cd.text((x, y), "m", font=f, fill=SAKURA)
    return chip


def word_times(name, start):
    a = json.loads((AUD / f"{name}.align.json").read_text())
    out, cur, ws = [], "", None
    for ch, st in zip(a["chars"], a["start"]):
        if ch == " ":
            if cur:
                out.append((cur, ws + start))
            cur, ws = "", None
        else:
            ws = st if ws is None else ws
            cur += ch
    if cur:
        out.append((cur, ws + start))
    return out


def wheel(frame, t, t0, t_land, items, cy):
    """A vertical word wheel that spins and lands on the last item (Holo's list carousel)."""
    p = (len(items) - 1) * ease_out((t - t0) / max(0.1, t_land - t0)) if t >= t0 else 0
    a_in = ease_out((t - t0 + 0.3) / 0.3)
    for k, it in enumerate(items):
        dist = k - p
        if abs(dist) > 1.6:
            continue
        s = 1 - 0.3 * min(1, abs(dist))
        lay = word_img(it, F_RND9, int(70 * s), WHITE if abs(dist) < 0.5 else (200, 200, 235))
        r = int(abs(dist) * 7)
        if r:
            lay = lay.filter(ImageFilter.GaussianBlur(r))
        lay = with_alpha(lay, a_in * clamp(1 - abs(dist) * 0.6))
        frame.alpha_composite(lay, (int(W / 2 - lay.width / 2), int(cy + dist * 92 - lay.height / 2)))


@lru_cache(None)
def petal_img(c, s):
    im = Image.new("RGBA", (s * 4, s * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, s * 4 - 1, s * 3 - 1), fill=c)
    d.ellipse((s, s * 0.8, s * 2.6, s * 2), fill=(255, 235, 242))
    return im.resize((s * 2, int(s * 1.4)), Image.LANCZOS)


def petal_burst(frame, t, t0, ox, oy, n=18, seed=7):
    """Sakura confetti on a right answer (the app's confetti colour)."""
    import random
    if not (t0 <= t <= t0 + 1.3):
        return
    rnd = random.Random(seed)
    dt = t - t0
    for _ in range(n):
        ang = rnd.uniform(-math.pi, 0)
        v = rnd.uniform(380, 820)
        col = rnd.choice([(250, 177, 201), (239, 140, 175), (253, 230, 237), (255, 209, 90)])
        s = rnd.randint(9, 15)
        spin = rnd.uniform(-400, 400)
        x = ox + math.cos(ang) * v * dt
        y = oy + math.sin(ang) * v * dt + 900 * dt * dt
        im = petal_img(col, s).rotate(spin * dt, expand=True)
        frame.alpha_composite(with_alpha(im, clamp(1.3 - dt) / 1.0 if dt > 0.3 else 1), (int(x), int(y)))


@lru_cache(None)
def word_chip(kana, meaning):
    fk, fm = font(F_JP, 52), font(F_RND8, 38)
    w = int(fk.getlength(kana) + fm.getlength(meaning)) + 80
    chip, pad = shadow_box((w, 94), 47, fill=(41, 40, 80, 235), shadow=(41, 40, 80, 70))
    d = ImageDraw.Draw(chip)
    d.text((pad + 28, pad + 10), kana, font=fk, fill=GOLD)
    d.text((pad + 28 + fk.getlength(kana) + 22, pad + 20), meaning, font=fm, fill=WHITE)
    return chip


ORBIT = [("つかれた", "tired"), ("おいしい", "tasty"), ("かわいい", "cute"), ("ありがとう", "thanks"), ("すごい", "amazing")]


def orbit_chips(frame, t, t0, cx, cy, front):
    """Japanese word chips orbiting the mascot with depth (the icons orbiting Audixa's search bar)."""
    if t < t0:
        return
    lt = t - t0
    for k, (kana, mean) in enumerate(ORBIT):
        th = 2 * math.pi * k / len(ORBIT) + lt * 0.75
        depth = math.sin(th)
        if (depth > 0) != front:
            continue
        chip = word_chip(kana, mean)
        s = (0.72 + 0.28 * (depth + 1) / 2) * ease_back((lt - k * 0.08) / 0.4, 2)
        if s <= 0.05:
            continue
        img = chip.resize((int(chip.width * s), int(chip.height * s)), Image.BILINEAR)
        if depth < -0.2:
            img = with_alpha(img.filter(ImageFilter.GaussianBlur((-depth) * 4)), 0.75)
        x = cx + math.cos(th) * 300
        y = cy + depth * 190
        frame.alpha_composite(img, (int(x - img.width / 2), int(y - img.height / 2)))


def pin(frame, n, x, y, t, t0):
    if t < t0:
        return
    s = ease_back((t - t0) / 0.35, 2.4)
    r = int(36 * s)
    if r < 3:
        return
    im = Image.new("RGBA", (r * 2 + 30, r * 2 + 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((15, 20, 15 + r * 2, 20 + r * 2), fill=(41, 40, 80, 60))
    d.ellipse((15, 15, 15 + r * 2, 15 + r * 2), fill=WHITE)
    lay = word_img(str(n), F_RND9, max(8, int(40 * s)), INDIGO)
    im.alpha_composite(lay, (int(15 + r - lay.width / 2), int(15 + r - lay.height / 2)))
    frame.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))


def whip(fr, lt, direction, dur=0.28):
    """Whip-pan into a cut: the new frame slides in with horizontal motion blur."""
    p = ease_out(lt / dur)
    if p >= 0.98:
        return fr
    from PIL import ImageChops
    k = 1 - p
    blurred = fr.resize((max(16, int(W / (1 + 30 * k))), H), Image.BILINEAR).resize((W, H), Image.BILINEAR)
    return ImageChops.offset(blurred, int(direction * k * 380), 0)


def zoom_through(fr, p, cx, cy):
    """Push into a point (the phone screen) to carry into the next scene."""
    if p <= 0:
        return fr
    z = 1 + 2.4 * p * p
    cw, ch = W / z, H / z
    cx = min(max(cx, cw / 2), W - cw / 2)  # keep the crop inside the frame
    cy = min(max(cy, ch / 2), H - ch / 2)
    out = fr.resize((W, H), Image.BILINEAR, box=(cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2))
    r = p * 10
    if r >= 1:
        out = out.resize((W // 3, H // 3), Image.BILINEAR).filter(ImageFilter.GaussianBlur(r / 3)).resize((W, H), Image.BILINEAR)
    return out


# ---------- timeline ----------
def build_timeline():
    S, t = {}, 0.0
    for name, d in [("hook", 2.7), ("doom", 2.6), ("reveal", 4.9), ("short", 4.7), ("card", 4.5),
                    ("swipe", 2.0), ("journey", 3.0), ("end", 4.4)]:
        S[name] = (t, t + d)
        t += d
    s = lambda k: S[k][0]
    vo = {  # audio file -> absolute start
        "hook1": s("hook") + 0.25, "hook2": s("doom") + 0.1, "reveal": s("reveal") + 0.25, "how1": s("reveal") + 1.4,
        "short_en": s("short") + 0.25, "how2": s("short") + 1.9, "word_jp": s("card") + 0.45, "how3": s("card") + 1.3,
        "swipe": s("swipe") + 0.2, "journey": s("journey") + 0.15, "endline": s("end") + 0.45,
    }
    return S, vo, t


NOTES = [("Daily lesson", "Just 5 minutes today?"), ("Your streak", "Don't break your 12-day streak!"),
         ("Still there?", "It only takes 5 minutes.")]


@lru_cache(None)
def notification(title, body):
    note, npad = shadow_box((880, 150), 40, fill=(255, 255, 255, 238))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle((npad + 28, npad + 28, npad + 122, npad + 122), 24, fill=(165, 164, 255))
    note.alpha_composite(icon("bell", 58), (npad + 46, npad + 46))
    nd.text((npad + 150, npad + 26), title, font=font(F_RND9, 36), fill=INK)
    nd.text((npad + 150, npad + 78), body, font=font(F_RND8, 32), fill=INK2)
    nd.text((npad + 780, npad + 30), "now", font=font(F_RND8, 26), fill=(150, 150, 170))
    return note


def render(out_video, scale=1.0, only=None):
    """only: list of times to save as PNG stills next to out_video (quick checks); no video then."""
    S, VO, total = build_timeline()
    sky = Plate(IMG / "bg_sky.jpg", 1.0, 1.04)
    dark = Plate(IMG / "p3.jpg", 1.0, 1.06)
    badge = Image.open(BADGE).convert("RGBA")
    badge = badge.resize((430, round(430 * badge.height / badge.width)), Image.LANCZOS)
    journey = Image.open(ASSETS / "journey_map_tall.imageset/journey_map_tall.jpg").convert("RGBA")
    map_w = 700
    journey = journey.resize((map_w, int(journey.height * map_w / journey.width)), Image.LANCZOS)
    map_h = min(journey.height, 1180)
    journey = journey.crop((0, journey.height - map_h, map_w, journey.height))
    jcard, jpad = shadow_box((map_w, map_h), 56, fill=(255, 255, 255, 255))
    jcard.paste(journey, (jpad, jpad), rounded_mask(journey.size, 56))
    how1 = word_times("how1", VO["how1"])
    t_shorts = next(st for w, st in how1 if w.lower().startswith("shorts"))
    t_japanese = next(st for w, st in how1 if w.lower().startswith("japanese"))
    scene_index = {k: i for i, k in enumerate(S)}

    ow, oh = int(W * scale) // 2 * 2, int(H * scale) // 2 * 2
    ff = None if only else subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-vf", f"scale={ow}:{oh}",
                           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", str(out_video)],
                          stdin=subprocess.PIPE)
    wanted = {round(x * FPS) for x in only} if only else None
    PH_CY = 1190  # phone centre in the phone scenes
    scr_x0, scr_y0 = W / 2 - SCR_W / 2, PH_CY - SCR_H / 2  # screen origin in frame coords
    for i in range(round(total * FPS)):
        if wanted is not None and i not in wanted:
            continue
        t = i / FPS
        scene = next(k for k, (a, b) in S.items() if a <= t < b)
        a, b = S[scene]
        lt = t - a
        fr = (dark if scene == "reveal" else sky).get(t / total)
        continuous = scene in ("card", "swipe", "journey")  # no whip: same phone shot, or zoomed into

        if scene == "hook":
            headline(fr, t, a + 0.15, "You can't do", "5 minutes of Duolingo…", y=250, size2=84)
            for k, (ti, bo) in enumerate(NOTES):  # reminders stack up, then get swiped away together
                t_k = a + 0.45 + k * 0.32
                swipe_p = ease_in_out((lt - 1.85 - k * 0.05) / 0.35)
                paste_fx(fr, notification(ti, bo), W / 2 + swipe_p * 1150, 560 + k * 176, t, t_k, dur=0.35, scale_from=0.6)
            mascot(fr, "sleepy", W / 2, 1400, 500, t, a + 0.6, move="breathe")
            for k in range(3):  # floating z's
                if lt > 1.0 + k * 0.45:
                    zt = (lt - 1.0 - k * 0.45) % 1.6
                    lay = with_alpha(text_img("z", F_RND9, 46 + k * 10, INDIGO), clamp(1 - zt / 1.6))
                    fr.alpha_composite(lay, (int(W / 2 + 140 + zt * 60), int(1200 - zt * 160)))
        elif scene == "doom":
            aura(fr, t, W / 2, PH_CY)
            floaters(fr, t, lt, front=False)
            order = ["dog", "skate", "bowl", "train"]
            pos = (lt * 0.9 + 1.6 * lt ** 2) * SCR_H * 0.55  # the feed speeds up
            scr = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 255))
            k0 = int(pos // SCR_H)
            for k in (k0, k0 + 1):
                scr.alpha_composite(short_frame(order[k % len(order)], lt), (0, int(k * SCR_H - pos)))
            speed = 0.9 + 3.2 * lt
            if speed > 1.5:  # vertical motion blur
                scr = scr.resize((SCR_W, max(8, int(SCR_H / min(12, speed)))), Image.BILINEAR).resize((SCR_W, SCR_H), Image.BILINEAR)
            enter = ease_out(lt / 0.5)
            draw_phone(fr, scr, W / 2, PH_CY + (1 - enter) * 500, ang=(1 - enter) * 30)
            floaters(fr, t, lt, front=True)
            headline(fr, t, a + 0.1, "…but you doomscroll", "for hours.", y=210, size2=104)
            mins = 12 + (192 - 12) * ease_in_out((lt - 0.2) / 2.3)
            paste_fx(fr, screen_time_chip(mins), W / 2, 1810, t, a + 0.2, scale_from=0.7)
        elif scene == "reveal":
            # wordmark springs in letter by letter
            paste_fx(fr, text_img("Meet", F_RND8, 64, (220, 220, 255)), W / 2, 300, t, a + 0.15)
            f = font(F_RND9, 190)
            word = "Upscroll"
            x = W / 2 - f.getlength(word) / 2
            for k, ch in enumerate(word):
                cw = f.getlength(ch)
                paste_fx(fr, word_img(ch, F_RND9, 190, WHITE), x + cw / 2, 470, t, a + 0.3 + k * 0.045, dur=0.45, scale_from=0.3, blur=16)
                x += cw
            # "turns your [cat videos / cooking clips / travel vlogs / memes / Shorts] -> Japanese lessons"
            paste_fx(fr, word_img("turns your", F_RND8, 52, (220, 220, 255)), W / 2, 660, t, a + 1.3)
            wheel(fr, t, a + 1.35, t_shorts + 0.05, ["cat videos", "cooking clips", "travel vlogs", "memes", "Shorts"], 770)
            arrow = Image.new("RGBA", (90, 90), (0, 0, 0, 0))
            ImageDraw.Draw(arrow).line([(18, 30), (45, 60), (72, 30)], fill=GOLD, width=12, joint="curve")
            paste_fx(fr, arrow, W / 2, 875, t, t_shorts + 0.15)
            p2, pad2 = shadow_box((500, 108), 54, fill=(*GOLD, 255), shadow=(0, 0, 0, 0))
            d2 = ImageDraw.Draw(p2)
            d2.text((pad2 + 250 - d2.textlength("Japanese lessons", font=font(F_RND9, 50)) / 2, pad2 + 18), "Japanese lessons", font=font(F_RND9, 50), fill=(0, 0, 0))
            paste_fx(fr, p2, W / 2, 985, t, t_japanese - 0.05, dur=0.45, scale_from=0.4)
            mascot(fr, "idea", W / 2, 1440, 500, t, a + 0.9, move="bob")
        elif scene in ("short", "card", "swipe"):
            st = S["short"][0]
            aura(fr, t, W / 2, PH_CY)
            card_t0 = S["card"][0] + 0.2
            tap_t, cont_t = S["card"][0] + 2.7, S["card"][0] + 3.7
            out_t = S["swipe"][0] + 0.05
            paused = card_t0 <= t < out_t + 0.3
            dim = ease_out((t - card_t0) / 0.3) if paused else 0
            vid_t = min(t, card_t0) - st  # the Short freezes while the card is up
            base = short_frame("tired", vid_t, dim=dim * 0.8, blur=int(dim * 6))
            subtitle_layer(base, t, st + 0.35, st + 1.85)
            if paused and t < card_t0 + 0.6:  # pause glyph flash
                base.alpha_composite(with_alpha(icon("pause", 120), clamp(1 - (t - card_t0) / 0.6)), (SCR_W // 2 - 60, 420))
            practice_card(base, t, card_t0, tap_t, cont_t, out_t)
            card_y = SCR_H - CARD_H - CARD_BOTTOM
            tap_ripple(base, SCR_W - 150, card_y + 368 + 96 + 39, t, tap_t)
            tap_ripple(base, SCR_W // 2, card_y + CARD_H - 74, t, cont_t)
            scr = base
            if scene == "swipe":  # swipe up to the next Short
                sp = ease_in_out((t - (S["swipe"][0] + 0.35)) / 0.5)
                if sp > 0:
                    nxt = short_frame("ramen", max(0.0, t - S["swipe"][0] - 0.35))
                    scr = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 255))
                    scr.alpha_composite(base, (0, int(-sp * SCR_H)))
                    scr.alpha_composite(nxt, (0, int((1 - sp) * SCR_H)))
            plt = t - st
            enter = ease_out(plt / 0.6) if scene == "short" else 1.0  # 3D tilt-in
            draw_phone(fr, scr, W / 2, PH_CY + (1 - enter) * 380, ang=(1 - enter) * 38, scale=0.9 + 0.1 * enter)
            if scene == "short":
                headline(fr, t, a + 0.15, "Watch your Shorts.", "Learn the words.", y=200, size2=90)
            elif scene == "card":
                headline(fr, t, a + 0.1, "A quick card", "makes it stick.", y=200, size2=90)
                check = (scr_x0 + (SCR_W - CARD_W) / 2 + CARD_W - 70, scr_y0 + card_y + 368 + 96 + 39)
                petal_burst(fr, t, tap_t + 0.05, *check)
                if t >= tap_t:  # the cat cheers the right answer
                    mascot(fr, "cheer", 900, 610, 300, t, tap_t + 0.05, move="cheer", ground=False)
            else:
                headline(fr, t, a + 0.1, "Then just", "keep scrolling.", y=200, size2=90)
                if t > a + 0.2:
                    plus, pp = shadow_box((330, 92), 46, fill=(*GOLD, 255))
                    ImageDraw.Draw(plus).text((pp + 34, pp + 14), "+1 word", font=font(F_RND9, 46), fill=(0, 0, 0))
                    fly = ease_out((t - a - 0.2) / 1.2)
                    fr.alpha_composite(with_alpha(plus, clamp(1.6 - fly * 1.2)), (int(W / 2 - plus.width / 2), int(1560 - fly * 260)))
                # push into the phone screen to carry into the map
                fr = zoom_through(fr, ease_in_out((t - (b - 0.4)) / 0.4), W / 2, PH_CY)
        elif scene == "journey":
            pts = [(-210, 470), (-120, 360), (20, 300), (120, 200), (60, 90)]  # along the path
            u = ease_in_out((lt - 0.5) / 2.3) * (len(pts) - 1)
            p = ease_out(lt / 0.7)  # the map swings up in 3D, settling from the zoom
            card = tilt(jcard, (1 - p) * 42)
            sc = 1.35 - 0.35 * p
            card = card.resize((int(card.width * sc), int(card.height * sc)), Image.BILINEAR)
            fr.alpha_composite(with_alpha(card, clamp(lt / 0.25)), (int(W / 2 - card.width / 2), int(1150 - card.height / 2 + (1 - p) * 120)))
            if p > 0.95:
                for k in range(1, len(pts)):  # stop pins pop as the cat reaches them
                    pin(fr, k + 2, W / 2 + pts[k][0] + 50, 1150 + pts[k][1] - 70, t, a + 0.5 + (k - 0.2) * 2.3 / (len(pts) - 1))
                k = min(int(u), len(pts) - 2)
                f = u - k
                mx = pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f
                my = pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f
                mascot(fr, "map", W / 2 + mx, 1150 + my, 280, t, a + 0.6, move="walk", flip=pts[k + 1][0] < pts[k][0])
            headline(fr, t, a + 0.2, "Every Short is", "a step through Japan.", y=200, size2=84)
        elif scene == "end":
            f = font(F_RND9, 170)
            x = W / 2 - f.getlength("Upscroll") / 2
            for k, ch in enumerate("Upscroll"):
                cw = f.getlength(ch)
                paste_fx(fr, word_img(ch, F_RND9, 170, INK), x + cw / 2, 470, t, a + 0.1 + k * 0.04, dur=0.45, scale_from=0.3, blur=14)
                x += cw
            kinetic(fr, t, a + 0.5, "Learn Japanese while you scroll", F_RND8, 50, INDIGO_D, 625, stagger=0.06)
            if lt >= 0.9:  # Apple badge: unmodified, no motion
                fr.alpha_composite(badge, (int(W / 2 - badge.width / 2), 760))
            orbit_chips(fr, t, a + 0.7, W / 2, 1360, front=False)
            mascot(fr, "wave", W / 2, 1360, 520, t, a + 0.3, move="wave")
            orbit_chips(fr, t, a + 0.7, W / 2, 1360, front=True)

        if lt < 0.28 and not continuous and i > 0:  # whip-pan into the cut
            fr = whip(fr, lt, 1 if scene_index[scene] % 2 else -1)
        if ff is None:
            fr.convert("RGB").save(Path(out_video).with_name(f"still_{t:05.2f}.jpg"), quality=88)
            continue
        ff.stdin.write(fr.convert("RGB").tobytes())
    if ff is None:
        return S, VO, total
    ff.stdin.close()
    ff.wait()
    return S, VO, total


def mix_audio(S, VO, total, out):
    s = lambda k: S[k][0]
    cues = [(k, v, -6 if k == "short_en" else 0) for k, v in VO.items()]
    cues += [
        ("sfx_pop", s("hook") + 0.45, -10), ("sfx_pop", s("hook") + 0.77, -11), ("sfx_pop", s("hook") + 1.09, -12),
        ("sfx_swipe", s("hook") + 1.85, -4),
        ("sfx_swipe", s("doom") - 0.1, -6), ("sfx_scrollloop", s("doom"), -10),
        ("sfx_riser", s("reveal") - 1.9, -14), ("sfx_thud", s("reveal"), -4),
        ("sfx_typing", s("reveal") + 1.4, -12), ("sfx_pop", s("reveal") + 3.2, -8),
        ("sfx_swipe", s("short") - 0.1, -6), ("sfx_pop", s("short") + 1.85, -2),
        ("sfx_click", s("card") + 0.2, -8), ("sfx_click", s("card") + 2.7, -6), ("sfx_chime", s("card") + 2.75, -6), ("sfx_pop", s("card") + 2.8, -10),
        ("sfx_click", s("card") + 3.7, -6), ("sfx_swipe", s("swipe") + 0.35, -4), ("sfx_record", s("swipe") + 0.25, -10),
        ("sfx_riser", s("journey") - 1.6, -16), ("sfx_thud", s("journey"), -12), ("sfx_pop", s("journey") + 1.1, -12),
        ("sfx_pop", s("journey") + 1.7, -12), ("sfx_pop", s("journey") + 2.3, -12),
        ("sfx_swipe", s("end") - 0.1, -6), ("sfx_chime", s("end") + 0.3, -8), ("sfx_pop", s("end") + 0.8, -12),
    ]
    inputs, chain, labels = [], [], []
    for i, (f, st, g) in enumerate(cues):
        inputs += ["-i", str(AUD / f"{f}.mp3")]
        ms = int(st * 1000)
        chain.append(f"[{i}:a]aresample=48000,volume={g}dB,adelay={ms}|{ms}[a{i}]")
        labels.append(f"[a{i}]")
    m = len(cues)
    # music in two parts, as in the references: a tense 120 bpm intro under the problem,
    # then the main track drops on the reveal ("Meet Upscroll")
    s3 = s("reveal")
    ms3 = int(s3 * 1000)
    inputs += ["-i", str(AUD / "music_intro.mp3"), "-stream_loop", "1", "-i", str(AUD / "music_main_a.mp3")]
    chain.append(f"[{m}:a]aresample=48000,atrim=0:{s3},volume=0.6,afade=t=in:d=0.2,afade=t=out:st={s3 - 0.08}:d=0.08[intro]")
    chain.append(f"[{m + 1}:a]aresample=48000,atrim=0:{total - s3},volume=0.5,afade=t=out:st={total - s3 - 1.2}:d=1.2,"
                 f"adelay={ms3}|{ms3}[main]")
    chain.append("[intro][main]amix=inputs=2:normalize=0[mus]")
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
