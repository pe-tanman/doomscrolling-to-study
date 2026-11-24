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
    paste_fx(frame, text_img(l1, F_RND8, size1, c1), W / 2, y, t, t0)
    paste_fx(frame, text_img(l2, F_RND9, size2, c2), W / 2, y + size1 * 0.6 + size2 * 0.62, t, t0 + 0.15)


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


def draw_phone(frame, scr, cx, cy):
    shell, pad = phone_shell()
    ph = shell.copy()
    ph.paste(scr, (pad + BEZEL, pad + BEZEL), rounded_mask(scr.size, R_SCR))
    d = ImageDraw.Draw(ph)
    iw = 190
    d.rounded_rectangle((pad + BEZEL + SCR_W / 2 - iw / 2, pad + BEZEL + 22, pad + BEZEL + SCR_W / 2 + iw / 2, pad + BEZEL + 78), 28, fill=(8, 8, 12))
    frame.alpha_composite(ph, (int(cx - ph.width / 2), int(cy - ph.height / 2)))


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


def render(out_video, scale=1.0):
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
    note, npad = shadow_box((880, 170), 44, fill=(255, 255, 255, 235))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle((npad + 30, npad + 35, npad + 130, npad + 135), 26, fill=(165, 164, 255))
    note.alpha_composite(icon("bell", 60), (npad + 50, npad + 55))
    nd.text((npad + 160, npad + 36), "Daily lesson", font=font(F_RND9, 38), fill=INK)
    nd.text((npad + 160, npad + 90), "Just 5 minutes today?", font=font(F_RND8, 34), fill=INK2)
    nd.text((npad + 770, npad + 40), "now", font=font(F_RND8, 26), fill=(150, 150, 170))

    ow, oh = int(W * scale) // 2 * 2, int(H * scale) // 2 * 2
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-vf", f"scale={ow}:{oh}",
                           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", str(out_video)],
                          stdin=subprocess.PIPE)
    PH_CY = 1190  # phone centre in the phone scenes
    for i in range(round(total * FPS)):
        t = i / FPS
        scene = next(k for k, (a, b) in S.items() if a <= t < b)
        a, b = S[scene]
        lt = t - a
        fr = (dark if scene == "reveal" else sky).get(t / total)
        continuous = scene in ("card", "swipe")  # these continue the same phone shot

        if scene == "hook":
            headline(fr, t, a + 0.15, "You can't do", "5 minutes of Duolingo…", y=250, size2=84)
            swipe_p = ease_in_out((lt - 1.75) / 0.4)
            paste_fx(fr, note, W / 2 + swipe_p * 1100, 640, t, a + 0.45, rise=-60)
            mascot(fr, "sleepy", W / 2, 1320, 540, t, a + 0.6, move="breathe")
            for k in range(3):  # floating z's
                if lt > 1.0 + k * 0.45:
                    zt = (lt - 1.0 - k * 0.45) % 1.6
                    lay = with_alpha(text_img("z", F_RND9, 46 + k * 10, INDIGO), clamp(1 - zt / 1.6))
                    fr.alpha_composite(lay, (int(W / 2 + 150 + zt * 60), int(1110 - zt * 160)))
        elif scene == "doom":
            headline(fr, t, a + 0.1, "…but you doomscroll", "for hours.", y=210, size2=104)
            order = ["dog", "skate", "bowl", "train"]
            pos = (lt * 0.9 + 1.6 * lt ** 2) * SCR_H * 0.55  # the feed speeds up
            scr = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 255))
            k0 = int(pos // SCR_H)
            for k in (k0, k0 + 1):
                scr.alpha_composite(short_frame(order[k % len(order)], lt), (0, int(k * SCR_H - pos)))
            speed = 0.9 + 3.2 * lt
            if speed > 1.5:  # vertical motion blur
                scr = scr.resize((SCR_W, max(8, int(SCR_H / min(12, speed)))), Image.BILINEAR).resize((SCR_W, SCR_H), Image.BILINEAR)
            draw_phone(fr, scr, W / 2, PH_CY)
            mins = int(12 + (192 - 12) * ease_out((lt - 0.2) / 2.2))
            chip, pad = shadow_box((420, 96), 48)
            cd = ImageDraw.Draw(chip)
            cd.text((pad + 34, pad + 20), "Screen time", font=font(F_RND8, 34), fill=INK2)
            cd.text((pad + 250, pad + 18), f"{mins // 60}h {mins % 60:02d}m", font=font(F_RND9, 40), fill=SAKURA)
            paste_fx(fr, chip, W / 2, 1810, t, a + 0.2, scale_from=0.7)
        elif scene == "reveal":
            paste_fx(fr, text_img("Meet", F_RND8, 64, (220, 220, 255)), W / 2, 330, t, a + 0.15)
            paste_fx(fr, text_img("Upscroll", F_RND9, 190, WHITE), W / 2, 480, t, a + 0.3, dur=0.5, scale_from=0.8)
            t1 = a + 1.4  # Your Shorts -> Japanese lessons
            p1, pad1 = shadow_box((380, 104), 52, fill=(255, 255, 255, 40), shadow=(0, 0, 0, 0))
            d1 = ImageDraw.Draw(p1)
            d1.text((pad1 + 190 - d1.textlength("Your Shorts", font=font(F_RND9, 46)) / 2, pad1 + 18), "Your Shorts", font=font(F_RND9, 46), fill=WHITE)
            p2, pad2 = shadow_box((480, 104), 52, fill=(*GOLD, 255), shadow=(0, 0, 0, 0))
            d2 = ImageDraw.Draw(p2)
            d2.text((pad2 + 240 - d2.textlength("Japanese lessons", font=font(F_RND9, 46)) / 2, pad2 + 18), "Japanese lessons", font=font(F_RND9, 46), fill=(0, 0, 0))
            paste_fx(fr, p1, W / 2, 720, t, t1)
            arrow = Image.new("RGBA", (90, 90), (0, 0, 0, 0))
            ImageDraw.Draw(arrow).line([(18, 30), (45, 60), (72, 30)], fill=GOLD, width=12, joint="curve")
            paste_fx(fr, arrow, W / 2, 832, t, t1 + 0.5)
            paste_fx(fr, p2, W / 2, 945, t, t1 + 0.9, scale_from=0.6)
            mascot(fr, "idea", W / 2, 1430, 520, t, a + 0.9, move="bob")
        elif scene in ("short", "card", "swipe"):
            st = S["short"][0]
            if scene == "short":
                headline(fr, t, a + 0.1, "Watch your Shorts.", "Learn the words.", y=200, size2=90)
            elif scene == "card":
                headline(fr, t, a + 0.1, "A quick card", "makes it stick.", y=200, size2=90)
            else:
                headline(fr, t, a + 0.1, "Then just", "keep scrolling.", y=200, size2=90)
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
            draw_phone(fr, scr, W / 2, PH_CY)
            if scene == "card" and t >= tap_t:  # the cat cheers the right answer
                mascot(fr, "cheer", 900, 610, 300, t, tap_t + 0.05, move="cheer", ground=False)
            if scene == "swipe" and t > a + 0.2:
                plus, pp = shadow_box((330, 92), 46, fill=(*GOLD, 255))
                ImageDraw.Draw(plus).text((pp + 34, pp + 14), "+1 word", font=font(F_RND9, 46), fill=(0, 0, 0))
                fly = ease_out((t - a - 0.2) / 1.2)
                fr.alpha_composite(with_alpha(plus, clamp(1.6 - fly * 1.2)), (int(W / 2 - plus.width / 2), int(1560 - fly * 260)))
        elif scene == "journey":
            headline(fr, t, a + 0.1, "Every Short is", "a step through Japan.", y=200, size2=84)
            paste_fx(fr, jcard, W / 2, 1150, t, a + 0.05, dur=0.45, scale_from=0.85)
            pts = [(-210, 470), (-120, 360), (20, 300), (120, 200), (60, 90)]  # along the path
            u = ease_in_out((lt - 0.4) / 2.4) * (len(pts) - 1)
            k = min(int(u), len(pts) - 2)
            f = u - k
            mx = pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f
            my = pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f
            mascot(fr, "map", W / 2 + mx, 1150 + my, 280, t, a + 0.3, move="walk", flip=pts[k + 1][0] < pts[k][0])
        elif scene == "end":
            paste_fx(fr, text_img("Upscroll", F_RND9, 170, INK), W / 2, 470, t, a + 0.1, dur=0.5, scale_from=0.8)
            paste_fx(fr, text_img("Learn Japanese while you scroll", F_RND8, 50, INDIGO_D), W / 2, 625, t, a + 0.35)
            if lt >= 0.8:  # Apple badge: unmodified, no motion
                fr.alpha_composite(badge, (int(W / 2 - badge.width / 2), 760))
            mascot(fr, "wave", W / 2, 1330, 560, t, a + 0.3, move="wave")

        if lt < 0.2 and not continuous and i > 0:  # cut: quick blur-in
            r = int((1 - lt / 0.2) * 14)
            if r:
                fr = fr.resize((W // 3, H // 3), Image.BILINEAR).filter(ImageFilter.GaussianBlur(r / 3)).resize((W, H), Image.BILINEAR)
        ff.stdin.write(fr.convert("RGB").tobytes())
    ff.stdin.close()
    ff.wait()
    return S, VO, total


def mix_audio(S, VO, total, out):
    s = lambda k: S[k][0]
    cues = [(k, v, -6 if k == "short_en" else 0) for k, v in VO.items()]
    cues += [
        ("sfx_pop", s("hook") + 0.45, -10), ("sfx_swipe", s("hook") + 1.75, -4),
        ("sfx_swipe", s("doom") - 0.1, -6), ("sfx_scrollloop", s("doom"), -10),
        ("sfx_riser", s("reveal") - 1.9, -14), ("sfx_thud", s("reveal"), -4),
        ("sfx_pop", s("reveal") + 1.4, -10), ("sfx_pop", s("reveal") + 2.3, -8),
        ("sfx_swipe", s("short") - 0.1, -6), ("sfx_pop", s("short") + 1.85, -2),
        ("sfx_click", s("card") + 0.2, -8), ("sfx_click", s("card") + 2.7, -6), ("sfx_chime", s("card") + 2.75, -6),
        ("sfx_click", s("card") + 3.7, -6), ("sfx_swipe", s("swipe") + 0.35, -4), ("sfx_record", s("swipe") + 0.25, -10),
        ("sfx_swipe", s("journey") - 0.1, -6), ("sfx_swipe", s("end") - 0.1, -6), ("sfx_chime", s("end") + 0.3, -8),
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
