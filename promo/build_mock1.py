"""Upscroll promo, Mock 1: animatic built from stills + ElevenLabs audio.

Story: a lock screen fills with "5 minutes of Japanese" reminders you swipe away, then
you doomscroll for hours -> "Meet... Upscroll": your Shorts become Japanese lessons ->
a food vlog plays, "good" swaps to おいしい in the subtitles -> a practice card slides
over the Short -> keep scrolling -> journey map -> App Store end card.

All UI is drawn here: the phone, a realistic short-video screen, iOS Liquid Glass
notifications and chips, and Upscroll's own learning layer modelled on the app's
SwiftUI views (Theme.swift, SubtitleOverlay.swift, LearningCard.swift). The mascot
uses the app's own art. Every frame is drawn in Python and piped to ffmpeg.

Usage: python3 build_mock1.py [--out mock1/upscroll_mock1.mp4] [--scale 1.0]
"""
import argparse
import json
import math
import random
import subprocess
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).parent
IMG, AUD, FONTS = ROOT / "img", ROOT / "audio", ROOT / "fonts"
ASSETS = ROOT.parent / "ios/Upscroll/Assets.xcassets"
W, H, FPS = 1080, 1920, 30

# Fonts: Inter Display / Inter (close to Apple's SF Pro Display / Text) and Noto Sans JP.
INTER = "/usr/share/fonts/opentype/inter/"
F_BOLD = INTER + "InterDisplay-Bold.otf"
F_SEMI = INTER + "InterDisplay-SemiBold.otf"
F_MED = INTER + "InterDisplay-Medium.otf"
F_TXT_SB = INTER + "Inter-SemiBold.otf"     # UI text inside the phone
F_TXT = INTER + "Inter-Medium.otf"
F_JP = str(FONTS / "noto-sans-jp-japanese-700-normal.woff")
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
DUO_GREEN = (88, 204, 2)     # Duolingo's green (#58CC02), used only as the reminder icon colour

GLASS_LIGHT = (255, 255, 255, 70)
GLASS_DARK = (0, 0, 0, 95)


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
def text_img(txt, path, size, fill):
    f = font(path, size)
    l, t, r, b = f.getbbox(txt)
    pad = 24
    im = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad - l, pad - t), txt, font=f, fill=fill)
    return im


@lru_cache(None)
def word_img(txt, path, size, fill):
    """Text on a fixed-height box (ascent+descent), so words in a line share a baseline."""
    f = font(path, size)
    asc, desc = f.getmetrics()
    pad = 24
    im = Image.new("RGBA", (int(f.getlength(txt)) + 2 + pad * 2, asc + desc + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad, pad), txt, font=f, fill=fill)
    return im


def with_alpha(img, a):
    if a >= 1:
        return img
    img = img.copy()
    img.putalpha(img.getchannel("A").point(lambda v: int(v * a)))
    return img


def composite(dst, img, x, y):
    """alpha_composite that tolerates images hanging off the edges."""
    x, y = int(x), int(y)
    sx, sy = max(0, -x), max(0, -y)
    w, h = min(img.width - sx, dst.width - x - sx), min(img.height - sy, dst.height - y - sy)
    if w <= 0 or h <= 0:
        return
    dst.alpha_composite(img, (x + sx, y + sy), (sx, sy, sx + w, sy + h))


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
    composite(frame, img, cx - img.width / 2, cy - img.height / 2 + dy)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def cover(img, size):
    return ImageOps.fit(img, size, Image.LANCZOS)


# ---------- AI video clips (Mock 2 / final) ----------
CLIP_DIR = None   # set by --clips: a folder of <name>/frame_00001.jpg|png sequences at FPS
CLIP_FPS = FPS
MASCOT_BOX = (84, 110, 600)  # where the mascot sits in the 768px green-screen source: x, y, size


@lru_cache(None)
def clip_len(name):
    if CLIP_DIR is None or not (CLIP_DIR / name).is_dir():
        return 0
    return len(list((CLIP_DIR / name).glob("frame_*")))


@lru_cache(maxsize=64)
def _clip_img(name, idx):
    f = next((CLIP_DIR / name).glob(f"frame_{idx + 1:05d}.*"))
    return Image.open(f).convert("RGBA")


def clip_frame(name, lt, mode="clamp"):
    """Frame of an AI clip at local time lt (None when there is no clip)."""
    n = clip_len(name)
    if not n:
        return None
    i = int(max(0.0, lt) * CLIP_FPS)
    if mode == "loop":
        i %= n
    elif mode == "pingpong":
        i %= max(1, 2 * n - 2)
        i = i if i < n else 2 * n - 2 - i
    return _clip_img(name, min(i, n - 1))


# ---------- iOS Liquid Glass ----------
@lru_cache(None)
def _vgrad(h, top, bottom, cut=1.0):
    """Vertical alpha ramp: top -> bottom, reaching `bottom` at `cut` of the height."""
    g = Image.new("L", (1, h))
    for y in range(h):
        p = min(1.0, y / max(1, h * cut))
        g.putpixel((0, y), int(top + (bottom - top) * p))
    return g


@lru_cache(None)
def _ring(w, h, radius, inset):
    outer = rounded_mask((w, h), radius)
    inset = min(inset, (min(w, h) - 2) // 2)  # tiny panels (pins popping in)
    inner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(inner).rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset), max(1, radius - inset), fill=255)
    return ImageChops.subtract(outer, inner)


def glass(base, box, radius, tint=GLASS_DARK, blur=24, light=False, alpha=1.0, shadow=None):
    """Liquid Glass: blurred, saturated backdrop with lensing at the rim, a tint,
    a top sheen and a specular edge that is bright at the top and fades downwards."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    w, h = x1 - x0, y1 - y0
    if w < 8 or h < 8 or alpha <= 0.01:
        return
    radius = int(min(radius, w / 2, h / 2))
    if shadow is None:
        shadow = light
    if shadow:
        pad = 40
        sh = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 14, pad + w, pad + h + 14), radius, fill=(41, 40, 80, int(55 * alpha)))
        composite(base, sh.filter(ImageFilter.GaussianBlur(22)), x0 - pad, y0 - pad)
    reg = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(base.width, x1), min(base.height, y1)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    reg.paste(base.crop((cx0, cy0, cx1, cy1)), (cx0 - x0, cy0 - y0))
    back = reg.convert("RGB").filter(ImageFilter.GaussianBlur(blur))
    back = ImageEnhance.Color(back).enhance(1.4)
    if light:
        back = ImageEnhance.Brightness(back).enhance(1.06)
    m = max(4, int(min(w, h) * 0.05))  # lensing: a magnified copy near the rim
    mag = back.resize((w + 2 * m, h + 2 * m), Image.BILINEAR).crop((m, m, m + w, m + h))
    back = Image.composite(mag, back, _ring(w, h, radius, 14).filter(ImageFilter.GaussianBlur(5))).convert("RGBA")
    back.alpha_composite(Image.new("RGBA", (w, h), tint))
    sheen = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    sheen.putalpha(_vgrad(h, 70 if light else 34, 0, 0.5).resize((w, h)))
    back.alpha_composite(sheen)
    rim = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    rim.putalpha(ImageChops.multiply(_ring(w, h, radius, 2), _vgrad(h, 235 if light else 170, 55 if light else 40).resize((w, h))))
    back.alpha_composite(rim)
    mask = rounded_mask((w, h), radius)
    if alpha < 1:
        mask = mask.point(lambda v: int(v * alpha))
    base.paste(back, (x0, y0), mask)


def glass_layer(frame, content, cx, cy, radius, t, t0, dur=0.45, light=True, tint=GLASS_LIGHT,
                from_scale=0.86, dx=0.0, t_out=None, scale=1.0, alpha=1.0, blur=26):
    """A glass panel with content on it, springing in (scale + fade); dx slides it sideways."""
    if t < t0:
        return
    p = ease_back((t - t0) / dur, 1.3)
    a = clamp((t - t0) / (dur * 0.6)) * alpha
    if t_out is not None and t > t_out:
        a *= clamp(1 - (t - t_out) / 0.25)
    if a <= 0.01:
        return
    s = (from_scale + (1 - from_scale) * p) * scale
    w, h = max(8, int(content.width * s)), max(8, int(content.height * s))
    bx, by = cx - w / 2 + dx, cy - h / 2
    glass(frame, (bx, by, bx + w, by + h), radius * s, tint=tint, light=light, alpha=a, blur=blur)
    c = content if abs(s - 1) < 0.01 else content.resize((w, h), Image.BILINEAR)
    composite(frame, with_alpha(c, a), bx, by)


# ---------- mascot (the app's own art) ----------
@lru_cache(None)
def mascot_img(name, size):
    im = Image.open(ASSETS / f"mascot_{name}.imageset/mascot_{name}.png").convert("RGBA")
    return im.resize((size, size), Image.LANCZOS)


def mascot(frame, name, cx, cy, size, t, t0, move="bob", flip=False, ground=True):
    """Hop in, then keep moving: bob, breathe (sleepy), wave, cheer or walk."""
    if t < t0:
        return
    lt = t - t0
    clip = clip_frame(f"mascot_{name}", lt, "pingpong")
    if clip is not None:  # AI character animation: scale so the cat matches the still's size
        bx, by, bs = MASCOT_BOX
        k = clip.width / 768
        full = int(size * 768 / bs)
        im = clip.resize((full, full), Image.BILINEAR)
        cy = cy - (by + bs / 2 - 384) * full / 768
        move = "clip"
    else:
        im = mascot_img(name, size)
    if flip:
        im = ImageOps.mirror(im)
    sx = sy = 1.0
    ang = dy = 0.0
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
        dy -= abs(math.sin(lt * 2 * math.pi * 1.6)) * 10
    elif move == "cheer":
        jump = abs(math.sin(lt * 2 * math.pi * 1.4))
        dy -= jump * 40
        sy *= 1 + 0.05 * jump
    elif move == "walk":
        dy -= abs(math.sin(lt * 2 * math.pi * 2.6)) * 14
        ang = math.sin(lt * 2 * math.pi * 2.6) * 5
    im = im.resize((int(im.width * sx), int(im.height * sy)), Image.BILINEAR)
    if abs(ang) > 0.2:
        im = im.rotate(ang, resample=Image.BICUBIC, expand=True)
    if ground:
        sh = Image.new("RGBA", (int(size * 0.6), 40), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((0, 0, sh.width - 1, 39), fill=(41, 40, 80, 50))
        composite(frame, with_alpha(sh.filter(ImageFilter.GaussianBlur(8)), clamp(lt / 0.3)), cx - sh.width / 2, cy + size * 0.44)
    composite(frame, im, cx - im.width / 2, cy - im.height / 2 + dy)


# ---------- backgrounds (clean gradients, no texture) ----------
@lru_cache(None)
def soft_glow(color, alpha, r):
    """A blurred disc of radius r on a canvas wide enough that the blur never reaches the edge."""
    n = r // 4  # work at quarter size
    c = n * 6
    im = Image.new("RGBA", (c, c), (*color, 0))
    ImageDraw.Draw(im).ellipse((c / 2 - n, c / 2 - n, c / 2 + n, c / 2 + n), fill=(*color, alpha))
    im = im.filter(ImageFilter.GaussianBlur(n * 0.55))
    return im.resize((c * 4, c * 4), Image.BICUBIC)


class Gradient:
    """A smooth vertical gradient with two soft glows; drifts slowly."""

    def __init__(self, stops, glows):
        bw, bh = int(W * 1.12), int(H * 1.12)
        col = Image.new("RGB", (1, 256))
        for y in range(256):
            p = y / 255
            for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
                if p0 <= p <= p1:
                    f = (p - p0) / (p1 - p0)
                    col.putpixel((0, y), tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3)))
        img = col.resize((bw, bh), Image.BICUBIC).convert("RGBA")
        for (gx, gy, r, c, a) in glows:
            g = soft_glow(c, a, r)
            composite(img, g, gx * bw - g.width / 2, gy * bh - g.height / 2)
        # 1-level dither so the gradient doesn't band after encoding
        rnd = Image.effect_noise((bw, bh), 6).convert("L").point(lambda v: 0 if v < 128 else 1)
        self.src = ImageChops.add(img.convert("RGB"), Image.merge("RGB", (rnd, rnd, rnd))).convert("RGBA")

    def get(self, u):
        ox = (self.src.width - W) * (0.5 + 0.35 * math.sin(u * math.pi))
        oy = (self.src.height - H) * (0.3 + 0.4 * u)
        return self.src.crop((int(ox), int(oy), int(ox) + W, int(oy) + H))


LIGHT_BG = Gradient([(0, (236, 234, 252)), (0.55, (222, 219, 249)), (1, (248, 233, 228))],
                    [(0.15, 0.12, 520, (196, 192, 255), 150), (0.9, 0.55, 480, (250, 205, 222), 120), (0.4, 0.95, 560, (255, 224, 190), 120)])
DARK_BG = Gradient([(0, (10, 9, 28)), (0.6, (20, 17, 52)), (1, (38, 30, 96))],
                   [(0.5, 1.0, 700, (97, 90, 207), 170), (0.2, 0.85, 420, (176, 65, 108), 90)])


@lru_cache(None)
def aura_blob(color, r):
    return soft_glow(color, 150, r)


def aura(frame, t, cx, cy, strength=1.0):
    """Soft colour blobs drifting behind the phone (the blurred blobs in the references)."""
    for col, r, fx, fy, ph in [((165, 164, 255), 260, 0.31, 0.23, 0.0), ((250, 177, 201), 230, 0.27, 0.35, 2.1),
                               ((246, 191, 81), 190, 0.38, 0.29, 4.0)]:
        b = aura_blob(col, r)
        if strength < 1:
            b = with_alpha(b, strength)
        x = cx + math.sin(t * fx * 2 * math.pi + ph) * 260
        y = cy + math.cos(t * fy * 2 * math.pi + ph) * 380
        composite(frame, b, x - b.width / 2, y - b.height / 2)


# ---------- typography ----------
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


def headline(frame, t, t0, l1, l2, y=200, dark=False, size1=56, size2=92):
    c1 = (215, 214, 245) if dark else INK2
    c2 = WHITE if dark else INK
    t1 = kinetic(frame, t, t0, l1, F_SEMI, size1, c1, y)
    kinetic(frame, t, t1 + 0.05, l2, F_BOLD, size2, c2, y + size1 * 0.62 + size2 * 0.6)


# ---------- 3D and motion helpers ----------
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
    size = (int(max(p[0] for p in pts) - minx) + 1, int(max(p[1] for p in pts) - miny) + 1)
    dst = [(px - minx, py - miny) for px, py in pts]
    return img.transform(size, Image.PERSPECTIVE, find_coeffs(dst, [(0, 0), (w, 0), (w, h), (0, h)]), Image.BICUBIC)


def whip(fr, lt, direction, dur=0.28):
    """Whip-pan into a cut: the new frame slides in with horizontal motion blur."""
    p = ease_out(lt / dur)
    if p >= 0.98:
        return fr
    k = 1 - p
    blurred = fr.resize((max(16, int(W / (1 + 30 * k))), H), Image.BILINEAR).resize((W, H), Image.BILINEAR)
    return ImageChops.offset(blurred, int(direction * k * 380), 0)


def zoom_through(fr, p, cx, cy):
    """Push into a point (the phone screen) to carry into the next scene."""
    if p <= 0:
        return fr
    z = 1 + 2.4 * p * p
    cw, ch = W / z, H / z
    cx = min(max(cx, cw / 2), W - cw / 2)
    cy = min(max(cy, ch / 2), H - ch / 2)
    out = fr.resize((W, H), Image.BILINEAR, box=(cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2))
    if p * 10 >= 1:
        out = out.resize((W // 3, H // 3), Image.BILINEAR).filter(ImageFilter.GaussianBlur(p * 10 / 3)).resize((W, H), Image.BILINEAR)
    return out


# ---------- icons ----------
@lru_cache(None)
def icon(kind, size=56, color=WHITE):
    """Simple UI glyphs (no platform branding)."""
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    lw = int(s * .085)
    if kind == "heart":
        pts = []
        for i in range(120):
            a = i / 120 * 2 * math.pi
            x = 16 * math.sin(a) ** 3
            y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
            pts.append((s / 2 + x * s / 36, s / 2 + y * s / 36 - s * 0.02))
        d.polygon(pts, fill=color)
    elif kind == "comment":
        d.rounded_rectangle((s * .1, s * .14, s * .9, s * .74), s * .26, fill=color)
        d.polygon([(s * .26, s * .68), (s * .22, s * .92), (s * .48, s * .72)], fill=color)
    elif kind == "share":
        d.polygon([(s * .55, s * .12), (s * .92, s * .45), (s * .55, s * .78), (s * .55, s * .6),
                   (s * .12, s * .62), (s * .22, s * .3), (s * .55, s * .3)], fill=color)
    elif kind == "bookmark":
        d.polygon([(s * .26, s * .1), (s * .74, s * .1), (s * .74, s * .9), (s * .5, s * .7), (s * .26, s * .9)], fill=color)
    elif kind == "search":
        d.ellipse((s * .12, s * .12, s * .68, s * .68), outline=color, width=lw)
        d.line([(s * .6, s * .6), (s * .88, s * .88)], fill=color, width=lw)
    elif kind == "dots":
        for i in range(3):
            d.ellipse((s * .42, s * (.14 + i * .28), s * .58, s * (.3 + i * .28)), fill=color)
    elif kind == "note":
        d.ellipse((s * .14, s * .62, s * .44, s * .88), fill=color)
        d.rectangle((s * .36, s * .14, s * .44, s * .76), fill=color)
        d.polygon([(s * .44, s * .14), (s * .82, s * .06), (s * .82, s * .26), (s * .44, s * .34)], fill=color)
    elif kind == "speaker":
        d.polygon([(s * .12, s * .38), (s * .32, s * .38), (s * .56, s * .16), (s * .56, s * .84), (s * .32, s * .62), (s * .12, s * .62)], fill=color)
        d.arc((s * .5, s * .28, s * .78, s * .72), -55, 55, fill=color, width=int(s * .07))
        d.arc((s * .5, s * .12, s * .95, s * .88), -55, 55, fill=color, width=int(s * .07))
    elif kind == "check":
        d.ellipse((0, 0, s - 1, s - 1), fill=RIGHT)
        d.line([(s * .27, s * .52), (s * .44, s * .68), (s * .74, s * .34)], fill=(20, 60, 30), width=int(s * .11), joint="curve")
    elif kind == "pause":
        d.rounded_rectangle((s * .28, s * .2, s * .43, s * .8), s * .05, fill=color)
        d.rounded_rectangle((s * .57, s * .2, s * .72, s * .8), s * .05, fill=color)
    elif kind == "book":
        d.rounded_rectangle((s * .16, s * .2, s * .48, s * .8), s * .05, fill=color)
        d.rounded_rectangle((s * .52, s * .2, s * .84, s * .8), s * .05, fill=color)
    elif kind == "hand":
        d.rounded_rectangle((s * .38, s * .08, s * .54, s * .6), s * .08, fill=color)
        d.rounded_rectangle((s * .24, s * .44, s * .8, s * .92), s * .18, fill=color)
    elif kind == "flash":
        d.polygon([(s * .56, s * .08), (s * .26, s * .56), (s * .48, s * .56), (s * .4, s * .92), (s * .74, s * .42), (s * .52, s * .42)], fill=color)
    elif kind == "camera":
        d.rounded_rectangle((s * .1, s * .28, s * .9, s * .82), s * .1, fill=color)
        d.rounded_rectangle((s * .34, s * .18, s * .66, s * .32), s * .04, fill=color)
        d.ellipse((s * .34, s * .38, s * .66, s * .7), fill=(0, 0, 0, 0))
    return im.resize((size, size), Image.LANCZOS)


# ---------- the phone ----------
SCR_W, SCR_H = 640, 1386       # iPhone-like 19.5:9 screen
BEZEL, R_OUT, R_SCR = 20, 100, 82
PH_CY = 1190                   # phone centre in the phone scenes


def status_bar(scr, clock="1:47"):
    d = ImageDraw.Draw(scr)
    d.text((70, 30), clock, font=font(F_TXT_SB, 28), fill=WHITE)
    x = SCR_W - 74  # battery
    d.rounded_rectangle((x, 36, x + 44, 58), 7, outline=(255, 255, 255, 200), width=2)
    d.rounded_rectangle((x + 4, 40, x + 34, 54), 4, fill=WHITE)
    d.rectangle((x + 46, 43, x + 49, 51), fill=(255, 255, 255, 200))
    for k in range(4):  # signal
        d.rounded_rectangle((SCR_W - 160 + k * 9, 54 - (k + 1) * 4.5, SCR_W - 154 + k * 9, 56), 2, fill=WHITE)
    for k, r in enumerate((18, 12, 6)):  # wifi
        d.arc((SCR_W - 108 - r, 52 - r, SCR_W - 108 + r, 52 + r), 225, 315, fill=WHITE, width=4)


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
    d.rounded_rectangle((pad + 3, pad + 3, pad + w - 3, pad + h - 3), R_OUT - 3, outline=(120, 118, 140), width=3)
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
    composite(frame, with_alpha(ph, alpha), cx - ph.width / 2, cy - ph.height / 2)


# ---------- lock screen (hook) ----------
@lru_cache(None)
def lock_wallpaper():
    g = Gradient([(0, (120, 112, 230)), (0.5, (200, 150, 220)), (1, (250, 190, 170))],
                 [(0.2, 0.3, 300, (90, 80, 210), 200), (0.85, 0.6, 320, (250, 150, 190), 180), (0.4, 0.9, 260, (255, 210, 140), 160)])
    return g.src.resize((SCR_W, SCR_H), Image.BILINEAR)


NOTES = [("Japanese lesson", "Just 5 minutes today?"), ("Your streak is at risk", "Don't lose your 12-day streak."),
         ("Still there?", "It only takes 5 minutes a day.")]
NOTE_W, NOTE_H = 600, 132


@lru_cache(None)
def note_content(title, body):
    im = Image.new("RGBA", (NOTE_W, NOTE_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ic = Image.new("RGBA", (76, 76), (0, 0, 0, 0))
    ImageDraw.Draw(ic).rounded_rectangle((0, 0, 75, 75), 18, fill=DUO_GREEN)  # colour only, no logo
    ic.alpha_composite(icon("book", 44), (16, 16))
    im.alpha_composite(ic, (24, 28))
    d.text((120, 26), title, font=font(F_TXT_SB, 27), fill=(25, 24, 40))
    d.text((120, 66), body, font=font(F_TXT, 25), fill=(60, 60, 80))
    d.text((NOTE_W - 72, 28), "now", font=font(F_TXT, 22), fill=(90, 90, 110))
    return im


def lock_screen(t, t0, swipe_t):
    scr = lock_wallpaper().copy()
    status_bar(scr)
    d = ImageDraw.Draw(scr)
    for txt, f, y in [("Monday, November 24", font(F_SEMI, 30), 120), ("1:47", font(F_SEMI, 180), 140)]:
        tw = d.textlength(txt, font=f)
        d.text((SCR_W / 2 - tw / 2, y), txt, font=f, fill=(255, 255, 255, 235))
    for k, (ti, bo) in enumerate(NOTES):  # reminders stack up, then get swiped away together
        sp = ease_in_out((t - swipe_t - k * 0.06) / 0.35)
        glass_layer(scr, note_content(ti, bo), SCR_W / 2, 540 + k * 150, 40, t, t0 + k * 0.35, light=True,
                    tint=(255, 255, 255, 120), dx=sp * 700, blur=20)
    for x in (90, SCR_W - 90):  # flashlight / camera buttons
        glass(scr, (x - 42, SCR_H - 150, x + 42, SCR_H - 66), 42, tint=(255, 255, 255, 50), light=True, shadow=False, blur=14)
        scr.alpha_composite(icon("flash" if x < SCR_W / 2 else "camera", 40), (x - 20, SCR_H - 128))
    d.rounded_rectangle((SCR_W / 2 - 90, SCR_H - 22, SCR_W / 2 + 90, SCR_H - 14), 4, fill=WHITE)
    return scr


# ---------- the short-video feed ----------
SHORTS = {  # image, handle, caption, likes, comments
    "vlog": ("shorts/ramen_vlog.jpg", "@mika.eats", "This ramen changed my life", "128K", "2,341"),
    "cat": ("shorts/street_cat.jpg", "@tokyo.strays", "he guards this staircase", "56K", "890"),
    "dog": ("shorts/dog.jpg", "@goldenhours", "he heard the treat bag", "48K", "512"),
    "skate": ("shorts/skate.jpg", "@street.kick", "first clean kickflip!!", "12K", "301"),
    "bowl": ("shorts/bowl.jpg", "@morning.bowls", "5-minute breakfast", "9.1K", "88"),
    "train": ("shorts/train.jpg", "@tokyo.daily", "morning commute in Tokyo", "22K", "640"),
}


@lru_cache(None)
def short_still(name):
    return cover(Image.open(IMG / SHORTS[name][0]).convert("RGB"), (int(SCR_W * 1.08), int(SCR_H * 1.08))).convert("RGBA")


@lru_cache(None)
def avatar(name, size=56):
    im = cover(Image.open(IMG / SHORTS[name][0]).convert("RGB"), (size * 3, size * 3)).resize((size, size), Image.LANCZOS).convert("RGBA")
    im.putalpha(rounded_mask((size, size), size // 2))
    return im


@lru_cache(None)
def chrome_layer(name):
    """Static parts of a realistic short-video screen."""
    _, handle, caption, likes, comments = SHORTS[name]
    lay = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 0))
    top = Image.new("RGBA", (SCR_W, 200), (0, 0, 0, 0))
    top.putalpha(_vgrad(200, 110, 0).resize((SCR_W, 200)))
    lay.alpha_composite(top)
    bot = Image.new("RGBA", (SCR_W, 560), (0, 0, 0, 0))
    bot.putalpha(_vgrad(560, 0, 170).resize((SCR_W, 560)))
    lay.alpha_composite(bot, (0, SCR_H - 560))
    status_bar(lay)
    d = ImageDraw.Draw(lay)
    lay.alpha_composite(icon("search", 40), (SCR_W - 134, 104))
    lay.alpha_composite(icon("dots", 40), (SCR_W - 70, 104))
    x = SCR_W - 64
    for k, (kind, label) in enumerate([("heart", likes), ("comment", comments), ("bookmark", "Save"), ("share", "Share")]):
        y = 690 + k * 122
        lay.alpha_composite(icon(kind, 54), (x - 27, y))
        f = font(F_TXT_SB, 21)
        d.text((x - d.textlength(label, font=f) / 2, y + 60), label, font=f, fill=WHITE)
    lay.alpha_composite(avatar(name, 54), (28, SCR_H - 232))
    d.text((94, SCR_H - 222), handle, font=font(F_TXT_SB, 27), fill=WHITE)
    fx = 94 + d.textlength(handle, font=font(F_TXT_SB, 27)) + 18
    d.rounded_rectangle((fx, SCR_H - 226, fx + 102, SCR_H - 186), 20, fill=WHITE)
    d.text((fx + 16, SCR_H - 220), "Follow", font=font(F_TXT_SB, 22), fill=(15, 15, 20))
    d.text((30, SCR_H - 166), caption, font=font(F_TXT, 26), fill=(245, 245, 250))
    lay.alpha_composite(icon("note", 26), (30, SCR_H - 110))
    d.text((64, SCR_H - 114), f"original sound · {handle}", font=font(F_TXT, 22), fill=(235, 235, 240))
    return lay


@lru_cache(maxsize=32)
def _clip_cover(name, idx):
    return cover(_clip_img(name, idx).convert("RGB"), (int(SCR_W * 1.08), int(SCR_H * 1.08))).convert("RGBA")


def short_frame(name, lt, chrome=True, dim=0.0, blur=0):
    """One Short at local time lt: its AI clip if there is one, else the still with a handheld drift."""
    n = clip_len(name)
    if n:
        i = min(int(max(0.0, lt) * CLIP_FPS), n - 1) if name == "vlog" else int(max(0.0, lt) * CLIP_FPS) % n
        src = _clip_cover(name, i)
        lt = lt * 0.3  # the clip has its own camera motion; keep only a hint of drift
    else:
        src = short_still(name)
    z = 1 + 0.02 * math.sin(lt * 0.9)
    big = src.resize((int(src.width * z), int(src.height * z)), Image.BILINEAR)
    ox = (big.width - SCR_W) / 2 + math.sin(lt * 1.7) * 8 + math.sin(lt * 4.1) * 2
    oy = (big.height - SCR_H) / 2 + math.cos(lt * 1.3) * 8 + math.cos(lt * 3.7) * 2
    scr = big.crop((int(ox), int(oy), int(ox) + SCR_W, int(oy) + SCR_H))
    if blur:
        scr = scr.filter(ImageFilter.GaussianBlur(blur))
    if chrome:
        scr.alpha_composite(chrome_layer(name))
        d = ImageDraw.Draw(scr)  # spinning sound disc + progress
        disc = avatar(name, 50).rotate(-lt * 120, resample=Image.BICUBIC)
        d.ellipse((SCR_W - 92, SCR_H - 126, SCR_W - 36, SCR_H - 70), fill=(30, 30, 30))
        scr.alpha_composite(disc, (SCR_W - 89, SCR_H - 123))
        prog = Image.new("RGBA", (SCR_W, 5), (255, 255, 255, 80))
        ImageDraw.Draw(prog).rectangle((0, 0, int(SCR_W * ((lt % 9) / 9)), 5), fill=WHITE)
        scr.alpha_composite(prog, (0, SCR_H - 5))
    if dim:
        scr.alpha_composite(Image.new("RGBA", scr.size, (10, 8, 30, int(170 * dim))))
    return scr


# ---------- Upscroll's learning layer (as in SubtitleOverlay.swift / LearningCard.swift) ----------
SUB_Y = 1000
WORD, ROMAJI, MEANING = "おいしい", "oishii", "delicious"


def subtitle_layer(scr, t, t_in, t_swap):
    """Glass caption over the Short; one word swaps into Japanese in gold, with the word chip above."""
    if t < t_in:
        return
    fe, fj = font(F_TXT_SB, 42), font(F_JP, 44)
    d = ImageDraw.Draw(scr)
    swapped = t >= t_swap
    parts = [("this is SO", fe), (WORD + "!" if swapped else "good!", fj if swapped else fe)]
    widths = [d.textlength(p, font=f) for p, f in parts]
    total = sum(widths) + 14
    x0, y0 = (SCR_W - total) / 2, SUB_Y
    glass(scr, (x0 - 28, y0 - 18, x0 + total + 28, y0 + 74), 30, tint=GLASS_DARK, blur=18)
    d = ImageDraw.Draw(scr)
    x = x0
    for (p, f), w in zip(parts, widths):
        if swapped and f is fj:
            pop = ease_back((t - t_swap) / 0.35, 2.5)
            lay = text_img(p, F_JP, max(8, int(44 * (0.6 + 0.4 * pop))), GOLD)
            composite(scr, lay, x + w / 2 - lay.width / 2, y0 + 27 - lay.height / 2)
        else:
            d.text((x, y0 + 2), p, font=f, fill=WHITE)
        x += w + 14
    if swapped:  # word chip: kana (gold) + romaji + tap hand, on glass
        a = ease_out((t - t_swap - 0.15) / 0.3)
        if a > 0:
            fk, fr_ = font(F_JP, 34), font(F_TXT_SB, 28)
            kw, rw = d.textlength(WORD, font=fk), d.textlength(ROMAJI, font=fr_)
            cw = int(kw + rw + 110)
            cx0, cy0 = (SCR_W - cw) / 2, y0 - 104 + (1 - a) * 20
            glass(scr, (cx0, cy0, cx0 + cw, cy0 + 64), 32, tint=GLASS_DARK, blur=16, alpha=a)
            lay = Image.new("RGBA", (cw, 64), (0, 0, 0, 0))
            ld = ImageDraw.Draw(lay)
            ld.text((22, 6), WORD, font=fk, fill=GOLD)
            ld.text((22 + kw + 14, 14), ROMAJI, font=fr_, fill=WHITE)
            lay.alpha_composite(icon("hand", 32), (cw - 50, 16))
            composite(scr, with_alpha(lay, a), cx0, cy0)


CARD_W, CARD_H, CARD_BOTTOM = 588, 760, 70
OPTIONS = ["spicy", "delicious", "expensive"]


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
    glass(scr, (x0, y0, x0 + cw, y0 + ch), 56, tint=(10, 8, 30, 140), blur=28)
    ov = Image.new("RGBA", scr.size, (0, 0, 0, 0))  # translucent fills must blend, not replace
    d = ImageDraw.Draw(ov)
    d.rounded_rectangle((x0 + 30, y0 + 30, x0 + 124, y0 + 72), 21, fill=PINK)
    d.text((x0 + 46, y0 + 34), "NEW", font=font(F_TXT_SB, 26), fill=(0, 0, 0))
    d.text((x0 + cw - 80, y0 + 36), "1/2", font=font(F_TXT_SB, 24), fill=(220, 220, 235))
    jw = d.textlength(WORD, font=font(F_JP, 92))
    d.text((x0 + 32, y0 + 92), WORD, font=font(F_JP, 92), fill=GOLD)
    d.text((x0 + 36, y0 + 226), ROMAJI, font=font(F_TXT_SB, 34), fill=WHITE)
    pulse = 1 + 0.12 * max(0.0, math.sin((t - t0 - 0.3) * 12)) if t0 + 0.3 < t < t0 + 1.3 else 1
    sp = icon("speaker", int(60 * pulse), GOLD)
    ov.alpha_composite(sp, (int(x0 + 32 + jw + 28 + (60 - sp.width) / 2), int(y0 + 132 + (60 - sp.height) / 2)))
    d.text((x0 + 34, y0 + 300), "What does it mean?", font=font(F_TXT_SB, 34), fill=WHITE)
    for k, opt in enumerate(OPTIONS):
        oy = y0 + 366 + k * 96
        right = opt == MEANING and t >= t_tap
        fill = (134, 240, 159, 75) if right else (255, 255, 255, 30)
        d.rounded_rectangle((x0 + 30, oy, x0 + cw - 30, oy + 78), 39, fill=fill,
                            outline=(134, 240, 159, 220) if right else (255, 255, 255, 60), width=2)
        d.text((x0 + 62, oy + 19), opt, font=font(F_TXT_SB, 34), fill=WHITE)
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
        tw = d.textlength("Continue", font=font(F_TXT_SB, 34))
        d.text((x0 + cw / 2 - tw / 2, by + bh / 2 - 21), "Continue", font=font(F_TXT_SB, 34), fill=(0, 0, 0, int(255 * a)))
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


# ---------- other reference-style moves ----------
@lru_cache(None)
def float_card(name, z):
    """A Short as a floating card; far cards are smaller and blurred."""
    w, h = int(200 * z), int(356 * z)
    im = cover(Image.open(IMG / SHORTS[name][0]).convert("RGB"), (w, h)).convert("RGBA")
    pad = 36
    card = Image.new("RGBA", (w + pad * 2, h + pad * 2 + 10), (0, 0, 0, 0))
    sh = Image.new("RGBA", card.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 10, pad + w, pad + h + 10), int(24 * z), fill=(41, 40, 80, 70))
    card.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)))
    card.paste(im, (pad, pad), rounded_mask((w, h), int(24 * z)))
    if z < 0.85:
        card = with_alpha(card.filter(ImageFilter.GaussianBlur((0.85 - z) * 14)), 0.55 + 0.45 * z)
    return card


FLOATERS = [  # (short, x, y0, depth, speed, phase)
    ("skate", 120, 620, 0.6, 1.0, 0.0), ("bowl", 960, 860, 0.65, 1.2, 1.0), ("train", 70, 1420, 0.7, 0.9, 2.0),
    ("dog", 1000, 1600, 0.62, 1.1, 3.0), ("cat", 140, 1080, 1.08, 1.6, 0.5), ("skate", 940, 1280, 1.12, 1.7, 1.5),
    ("train", 980, 520, 1.0, 1.5, 2.5),
]


def floaters(frame, t, lt, front):
    for name, x, y0, z, sp, ph in FLOATERS:
        if (z >= 1.0) != front:
            continue
        y = (y0 - lt * sp * 260 * (1 + lt * 0.6)) % (H + 600) - 300  # drifting up, speeding up
        a = clamp(lt / 0.4) * clamp((y - 420) / 220)  # fade out before the headline
        if a <= 0:
            continue
        img = float_card(name, z).rotate(math.sin(t * 1.3 + ph) * 6, resample=Image.BICUBIC, expand=True)
        composite(frame, with_alpha(img, a), x - img.width / 2, y - img.height / 2)


def rolling_digits(img, x, y, value, period, f, color):
    """Odometer digit: value is a float; the digit rolls up as it moves to the next."""
    v = value % period
    d0 = int(v)
    frac = v - d0
    asc, desc = f.getmetrics()
    h = asc + desc
    box = Image.new("RGBA", (int(f.getlength("0")) + 4, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(box)
    bd.text((0, -frac * h), str(d0 % 10), font=f, fill=color)
    bd.text((0, (1 - frac) * h), str((d0 + 1) % period % 10), font=f, fill=color)
    img.alpha_composite(box, (int(x), int(y)))
    return box.width


def screen_time_content(minutes):
    im = Image.new("RGBA", (460, 100), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((36, 30), "Screen time", font=font(F_SEMI, 34), fill=INK2)
    f = font(F_BOLD, 42)
    ones = minutes % 10
    carry = max(0.0, ones - 9)
    tens = (minutes // 10) % 6 + carry
    hours = minutes // 60 + (carry if (minutes // 10) % 6 == 5 else 0)
    x, y = 262, 22
    x += rolling_digits(im, x, y, hours, 10, f, SAKURA)
    d.text((x, y), "h", font=f, fill=SAKURA)
    x += f.getlength("h ")
    x += rolling_digits(im, x, y, tens, 6, f, SAKURA)
    x += rolling_digits(im, x, y, ones, 10, f, SAKURA)
    d.text((x, y), "m", font=f, fill=SAKURA)
    return im


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
        lay = word_img(it, F_BOLD, int(74 * s), WHITE if abs(dist) < 0.5 else (200, 200, 235))
        r = int(abs(dist) * 7)
        if r:
            lay = lay.filter(ImageFilter.GaussianBlur(r))
        composite(frame, with_alpha(lay, a_in * clamp(1 - abs(dist) * 0.6)), W / 2 - lay.width / 2, cy + dist * 96 - lay.height / 2)


@lru_cache(None)
def petal_img(c, s):
    im = Image.new("RGBA", (s * 4, s * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, s * 4 - 1, s * 3 - 1), fill=c)
    d.ellipse((s, s * 0.8, s * 2.6, s * 2), fill=(255, 235, 242))
    return im.resize((s * 2, int(s * 1.4)), Image.LANCZOS)


def petal_burst(frame, t, t0, ox, oy, n=18, seed=7):
    """Sakura confetti on a right answer (the app's confetti colour)."""
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
        composite(frame, with_alpha(im, clamp(1.3 - dt) if dt > 0.3 else 1), x, y)


ORBIT = [("おいしい", "tasty"), ("つかれた", "tired"), ("かわいい", "cute"), ("ありがとう", "thanks"), ("すごい", "amazing")]


@lru_cache(None)
def orbit_content(kana, meaning):
    fk, fm = font(F_JP, 46), font(F_SEMI, 34)
    w = int(fk.getlength(kana) + fm.getlength(meaning)) + 76
    im = Image.new("RGBA", (w, 88), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((28, 10), kana, font=fk, fill=INDIGO_D)
    d.text((28 + fk.getlength(kana) + 20, 22), meaning, font=fm, fill=INK2)
    return im


def orbit_chips(frame, t, t0, cx, cy, front):
    """Glass word chips orbiting the mascot with depth (the icons orbiting Audixa's search bar)."""
    if t < t0:
        return
    lt = t - t0
    for k, (kana, mean) in enumerate(ORBIT):
        th = 2 * math.pi * k / len(ORBIT) + lt * 0.75
        depth = math.sin(th)
        if (depth > 0) != front:
            continue
        pop = ease_back((lt - k * 0.08) / 0.4, 2)
        if pop <= 0.05:
            continue
        s = (0.72 + 0.28 * (depth + 1) / 2) * pop
        c = orbit_content(kana, mean)
        x, y = cx + math.cos(th) * 300, cy + depth * 190
        glass_layer(frame, c, x, y, 44, t, -1, scale=s, from_scale=1.0, alpha=0.75 if depth < -0.2 else 1.0,
                    tint=(255, 255, 255, 110))


def pin(frame, n, x, y, t, t0):
    if t < t0:
        return
    s = ease_back((t - t0) / 0.35, 2.4)
    r = int(36 * s)
    if r < 3:
        return
    glass(frame, (x - r, y - r, x + r, y + r), r, tint=(255, 255, 255, 170), light=True, blur=10)
    lay = word_img(str(n), F_BOLD, max(8, int(38 * s)), INDIGO)
    composite(frame, lay, x - lay.width / 2, y - lay.height / 2)


# ---------- timeline ----------
def build_timeline():
    S, t = {}, 0.0
    for name, d in [("hook", 3.5), ("doom", 2.6), ("reveal", 5.9), ("short", 5.3), ("card", 4.5),
                    ("swipe", 2.0), ("journey", 3.0), ("end", 4.4)]:
        S[name] = (t, t + d)
        t += d
    s = lambda k: S[k][0]
    vo = {  # audio file -> absolute start
        "hook1": s("hook") + 0.3, "hook2": s("doom") + 0.1,
        "meet": s("reveal") + 0.15, "upscroll": s("reveal") + 1.1, "how1": s("reveal") + 2.3,
        "short_en": s("short") + 0.25, "how2": s("short") + 2.45, "word_jp": s("card") + 0.45, "how3": s("card") + 1.3,
        "swipe": s("swipe") + 0.2, "journey": s("journey") + 0.15, "endline": s("end") + 0.45,
    }
    return S, vo, t


def render(out_video, scale=1.0, only=None):
    """only: list of times to save as JPEG stills next to out_video (quick checks); no video then."""
    S, VO, total = build_timeline()
    badge = Image.open(BADGE).convert("RGBA")
    badge = badge.resize((430, round(430 * badge.height / badge.width)), Image.LANCZOS)
    journey = Image.open(ASSETS / "journey_map_tall.imageset/journey_map_tall.jpg").convert("RGBA")
    map_w = 700
    journey = journey.resize((map_w, int(journey.height * map_w / journey.width)), Image.LANCZOS)
    map_h = min(journey.height, 1180)
    journey = journey.crop((0, journey.height - map_h, map_w, journey.height))
    jpad = 50
    jcard = Image.new("RGBA", (map_w + jpad * 2, map_h + jpad * 2 + 14), (0, 0, 0, 0))
    jsh = Image.new("RGBA", jcard.size, (0, 0, 0, 0))
    ImageDraw.Draw(jsh).rounded_rectangle((jpad, jpad + 14, jpad + map_w, jpad + map_h + 14), 56, fill=(41, 40, 80, 70))
    jcard.alpha_composite(jsh.filter(ImageFilter.GaussianBlur(24)))
    jcard.paste(journey, (jpad, jpad), rounded_mask(journey.size, 56))
    jmask = rounded_mask(journey.size, 56)

    def journey_card(lt):
        fr_ = clip_frame("journey", lt, "clamp")
        if fr_ is None:
            return jcard
        c = jcard.copy()
        c.paste(cover(fr_.convert("RGB"), journey.size), (jpad, jpad), jmask)
        return c
    how1 = word_times("how1", VO["how1"])
    t_shorts = next(st for w, st in how1 if w.lower().startswith("shorts"))
    t_japanese = next(st for w, st in how1 if w.lower().startswith("japanese"))
    t_swap = next(st for w, st in word_times("short_en", VO["short_en"]) if w.lower().startswith("good"))
    scene_index = {k: i for i, k in enumerate(S)}

    ow, oh = int(W * scale) // 2 * 2, int(H * scale) // 2 * 2
    ff = None if only else subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
         "-i", "-", "-vf", f"scale={ow}:{oh}", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
         str(out_video)], stdin=subprocess.PIPE)
    wanted = {round(x * FPS) for x in only} if only else None
    scr_x0, scr_y0 = W / 2 - SCR_W / 2, PH_CY - SCR_H / 2  # screen origin in frame coords
    for i in range(round(total * FPS)):
        if wanted is not None and i not in wanted:
            continue
        t = i / FPS
        scene = next(k for k, (a, b) in S.items() if a <= t < b)
        a, b = S[scene]
        lt = t - a
        fr = (DARK_BG if scene == "reveal" else LIGHT_BG).get(t / total).copy()
        continuous = scene in ("doom", "card", "swipe", "journey")  # same phone shot, or zoomed into

        if scene in ("hook", "doom"):
            aura(fr, t, W / 2, PH_CY)
            if scene == "doom":
                floaters(fr, t, lt, front=False)
            unlock = ease_in_out((t - S["doom"][0]) / 0.45)  # lock screen slides up into the feed
            if unlock < 1:
                scr = lock_screen(t, S["hook"][0] + 0.55, S["hook"][0] + 2.55)
            if unlock > 0:
                feed_t = t - S["doom"][0]
                order = ["dog", "skate", "bowl", "train", "cat"]
                pos = (feed_t * 0.9 + 1.6 * feed_t ** 2) * SCR_H * 0.55  # the feed speeds up
                feed = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 255))
                k0 = int(pos // SCR_H)
                for k in (k0, k0 + 1):
                    feed.alpha_composite(short_frame(order[k % len(order)], feed_t), (0, int(k * SCR_H - pos)))
                speed = 0.9 + 3.2 * feed_t
                if speed > 1.5:  # vertical motion blur
                    feed = feed.resize((SCR_W, max(8, int(SCR_H / min(12, speed)))), Image.BILINEAR).resize((SCR_W, SCR_H), Image.BILINEAR)
                if unlock < 1:
                    feed.alpha_composite(scr, (0, int(-unlock * SCR_H)))
                scr = feed
            enter = ease_out((t - S["hook"][0]) / 0.6)
            draw_phone(fr, scr, W / 2, PH_CY + (1 - enter) * 500, ang=(1 - enter) * 30)
            if scene == "hook":
                headline(fr, t, a + 0.2, "You can't do 5 minutes of", "Japanese on Duolingo…", y=230, size1=54, size2=80)
                mascot(fr, "sleepy", 880, 1690, 300, t, a + 1.0, move="breathe")
                for k in range(3):  # floating z's
                    if lt > 1.4 + k * 0.45:
                        zt = (lt - 1.4 - k * 0.45) % 1.6
                        lay = with_alpha(text_img("z", F_BOLD, 40 + k * 10, INDIGO), clamp(1 - zt / 1.6))
                        composite(fr, lay, 960 + zt * 50, 1560 - zt * 140)
            else:
                floaters(fr, t, lt, front=True)
                headline(fr, t, a + 0.1, "…but you doomscroll", "for hours.", y=230, size2=100)
                mins = 12 + (192 - 12) * ease_in_out((lt - 0.2) / 2.3)
                glass_layer(fr, screen_time_content(mins), W / 2, 1810, 50, t, a + 0.2, tint=(255, 255, 255, 120))
        elif scene == "reveal":
            aura(fr, t, W / 2, 1500, strength=0.5)
            paste_fx(fr, text_img("Meet", F_SEMI, 72, (215, 214, 245)), W / 2, 300, t, a + 0.15, blur=16)
            f = font(F_BOLD, 196)  # ...beat... then the wordmark lands on the drop
            x = W / 2 - f.getlength("Upscroll") / 2
            for k, ch in enumerate("Upscroll"):
                cw = f.getlength(ch)
                paste_fx(fr, word_img(ch, F_BOLD, 196, WHITE), x + cw / 2, 470, t, a + 1.05 + k * 0.04, dur=0.45, scale_from=0.3, blur=16)
                x += cw
            paste_fx(fr, word_img("turns your", F_SEMI, 52, (215, 214, 245)), W / 2, 660, t, a + 2.2)
            wheel(fr, t, a + 2.25, t_shorts + 0.05, ["cat videos", "cooking clips", "travel vlogs", "memes", "Shorts"], 772)
            arrow = Image.new("RGBA", (90, 90), (0, 0, 0, 0))
            ImageDraw.Draw(arrow).line([(18, 30), (45, 60), (72, 30)], fill=GOLD, width=12, joint="curve")
            paste_fx(fr, arrow, W / 2, 880, t, t_shorts + 0.15)
            pill = Image.new("RGBA", (520, 112), (0, 0, 0, 0))
            pd = ImageDraw.Draw(pill)
            pd.rounded_rectangle((0, 0, 519, 111), 56, fill=GOLD)
            pd.text((260 - pd.textlength("Japanese lessons", font=font(F_BOLD, 50)) / 2, 22), "Japanese lessons", font=font(F_BOLD, 50), fill=(20, 18, 40))
            paste_fx(fr, pill, W / 2, 992, t, t_japanese - 0.05, dur=0.45, scale_from=0.4)
            mascot(fr, "idea", W / 2, 1450, 480, t, a + 1.6, move="bob")
        elif scene in ("short", "card", "swipe"):
            st = S["short"][0]
            aura(fr, t, W / 2, PH_CY)
            card_t0 = S["card"][0] + 0.2
            tap_t, cont_t = S["card"][0] + 2.7, S["card"][0] + 3.7
            out_t = S["swipe"][0] + 0.05
            paused = card_t0 <= t < out_t + 0.3
            dim = ease_out((t - card_t0) / 0.3) if paused else 0
            vid_t = min(t, card_t0) - st  # the Short freezes while the card is up
            base = short_frame("vlog", vid_t, dim=dim * 0.8, blur=int(dim * 6))
            subtitle_layer(base, t, st + 0.3, t_swap)
            if paused and t < card_t0 + 0.6:  # pause glyph flash
                composite(base, with_alpha(icon("pause", 120), clamp(1 - (t - card_t0) / 0.6)), SCR_W // 2 - 60, 420)
            practice_card(base, t, card_t0, tap_t, cont_t, out_t)
            card_y = SCR_H - CARD_H - CARD_BOTTOM
            tap_ripple(base, SCR_W - 150, card_y + 366 + 96 + 39, t, tap_t)
            tap_ripple(base, SCR_W // 2, card_y + CARD_H - 74, t, cont_t)
            scr = base
            if scene == "swipe":  # swipe up to the next Short
                sp = ease_in_out((t - (S["swipe"][0] + 0.35)) / 0.5)
                if sp > 0:
                    nxt = short_frame("cat", max(0.0, t - S["swipe"][0] - 0.35))
                    scr = Image.new("RGBA", (SCR_W, SCR_H), (0, 0, 0, 255))
                    scr.alpha_composite(base, (0, int(-sp * SCR_H)))
                    scr.alpha_composite(nxt, (0, int((1 - sp) * SCR_H)))
            enter = ease_out((t - st) / 0.6) if scene == "short" else 1.0  # 3D tilt-in
            draw_phone(fr, scr, W / 2, PH_CY + (1 - enter) * 380, ang=(1 - enter) * 38, scale=0.9 + 0.1 * enter)
            if scene == "short":
                headline(fr, t, a + 0.15, "Watch your Shorts.", "Learn the words.", y=210, size2=88)
            elif scene == "card":
                headline(fr, t, a + 0.1, "A quick card", "makes it stick.", y=210, size2=88)
                check = (scr_x0 + (SCR_W - CARD_W) / 2 + CARD_W - 70, scr_y0 + card_y + 366 + 96 + 39)
                petal_burst(fr, t, tap_t + 0.05, *check)
                if t >= tap_t:  # the cat cheers the right answer
                    mascot(fr, "cheer", 900, 620, 290, t, tap_t + 0.05, move="cheer", ground=False)
            else:
                headline(fr, t, a + 0.1, "Then just", "keep scrolling.", y=210, size2=88)
                if t > a + 0.2:
                    plus = Image.new("RGBA", (300, 92), (0, 0, 0, 0))
                    ImageDraw.Draw(plus).text((48, 18), "+1 word", font=font(F_BOLD, 46), fill=(30, 25, 10))
                    fly = ease_out((t - a - 0.2) / 1.2)
                    glass_layer(fr, plus, W / 2, 1600 - fly * 260, 46, t, a + 0.2, tint=(255, 209, 90, 170),
                                alpha=clamp(1.6 - fly * 1.2))
                fr = zoom_through(fr, ease_in_out((t - (b - 0.4)) / 0.4), W / 2, PH_CY)  # push into the screen
        elif scene == "journey":
            aura(fr, t, W / 2, 1150, strength=0.7)
            pts = [(-210, 470), (-120, 360), (20, 300), (120, 200), (60, 90)]  # along the path
            u = ease_in_out((lt - 0.5) / 2.3) * (len(pts) - 1)
            p = ease_out(lt / 0.7)  # the map swings up in 3D, settling from the zoom
            card = tilt(journey_card(lt), (1 - p) * 42)
            sc = 1.35 - 0.35 * p
            card = card.resize((int(card.width * sc), int(card.height * sc)), Image.BILINEAR)
            composite(fr, with_alpha(card, clamp(lt / 0.25)), W / 2 - card.width / 2, 1150 - card.height / 2 + (1 - p) * 120)
            if p > 0.95:
                for k in range(1, len(pts)):  # stop pins pop as the cat reaches them
                    pin(fr, k + 2, W / 2 + pts[k][0] + 50, 1150 + pts[k][1] - 70, t, a + 0.5 + (k - 0.2) * 2.3 / (len(pts) - 1))
                k = min(int(u), len(pts) - 2)
                f = u - k
                mx = pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f
                my = pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f
                mascot(fr, "map", W / 2 + mx, 1150 + my, 280, t, a + 0.6, move="walk", flip=pts[k + 1][0] < pts[k][0])
                # (with clips, the mascot_map clip walks in place while this moves it along the path)
            headline(fr, t, a + 0.2, "Every Short is", "a step through Japan.", y=210, size2=82)
        elif scene == "end":
            aura(fr, t, W / 2, 1380, strength=0.8)
            f = font(F_BOLD, 180)
            x = W / 2 - f.getlength("Upscroll") / 2
            for k, ch in enumerate("Upscroll"):
                cw = f.getlength(ch)
                paste_fx(fr, word_img(ch, F_BOLD, 180, INK), x + cw / 2, 460, t, a + 0.1 + k * 0.04, dur=0.45, scale_from=0.3, blur=14)
                x += cw
            kinetic(fr, t, a + 0.5, "Learn Japanese while you scroll", F_SEMI, 50, INDIGO_D, 620, stagger=0.06)
            if lt >= 0.9:  # Apple badge: unmodified, no motion
                fr.alpha_composite(badge, (int(W / 2 - badge.width / 2), 760))
            orbit_chips(fr, t, a + 0.7, W / 2, 1380, front=False)
            mascot(fr, "wave", W / 2, 1380, 500, t, a + 0.3, move="wave")
            orbit_chips(fr, t, a + 0.7, W / 2, 1380, front=True)

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
    cues = [(k, v, -5 if k == "short_en" else 0) for k, v in VO.items()]
    drop = VO["upscroll"]
    cues += [
        ("sfx_pop", s("hook") + 0.55, -10), ("sfx_pop", s("hook") + 0.9, -11), ("sfx_pop", s("hook") + 1.25, -12),
        ("sfx_swipe", s("hook") + 2.55, -4),
        ("sfx_swipe", s("doom") - 0.05, -6), ("sfx_scrollloop", s("doom") + 0.2, -10),
        ("sfx_riser", drop - 2.0, -13), ("sfx_thud", drop, -3),
        ("sfx_typing", s("reveal") + 2.25, -12), ("sfx_pop", s("reveal") + 3.9, -8),
        ("sfx_swipe", s("short") - 0.1, -6), ("sfx_pop", s("short") + 2.0, -2),
        ("sfx_click", s("card") + 0.2, -8), ("sfx_click", s("card") + 2.7, -6), ("sfx_chime", s("card") + 2.75, -6),
        ("sfx_pop", s("card") + 2.8, -10),
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
    # then the main track drops exactly on "Upscroll" (after the "Meet..." pause)
    md = int(drop * 1000)
    inputs += ["-stream_loop", "1", "-i", str(AUD / "music_intro.mp3"), "-stream_loop", "1", "-i", str(AUD / "music_main_a.mp3")]
    chain.append(f"[{m}:a]aresample=48000,atrim=0:{drop},volume='if(gt(t,{drop - 0.9}),0.25,0.6)':eval=frame,"
                 f"afade=t=in:d=0.2,afade=t=out:st={drop - 0.08}:d=0.08[intro]")
    chain.append(f"[{m + 1}:a]aresample=48000,atrim=0:{total - drop},volume=0.5,afade=t=out:st={total - drop - 1.2}:d=1.2,"
                 f"adelay={md}|{md}[main]")
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
    ap.add_argument("--clips", help="folder of AI clip frame sequences (Mock 2 / final)")
    a = ap.parse_args()
    global CLIP_DIR
    CLIP_DIR = Path(a.clips) if a.clips else None
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
