"""Small color toolkit: OKLCH <-> sRGB (with chroma-reduction gamut mapping), WCAG 2 contrast,
APCA (SAPC 0.0.98G-4g), alpha compositing, Machado 2009 CVD simulation, OKLab deltaE."""
import math

def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

def hex2rgb(h):
    h = h if isinstance(h, int) else int(h.lstrip('#'), 16)
    return ((h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255)

def rgb2hex(rgb):
    return '#%02X%02X%02X' % tuple(round(max(0, min(1, c)) * 255) for c in rgb)

def rgb2oklab(rgb):
    r, g, b = (_lin(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

def oklab2linrgb(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)

def oklch2rgb(L, C, H):
    """Gamut-map by reducing chroma (holds L and H), then gamma-encode."""
    lo, hi = 0.0, C
    def lin(c):
        return oklab2linrgb(L, c * math.cos(math.radians(H)), c * math.sin(math.radians(H)))
    if all(-1e-6 <= x <= 1 + 1e-6 for x in lin(C)):
        best = C
    else:
        for _ in range(40):
            mid = (lo + hi) / 2
            if all(-1e-6 <= x <= 1 + 1e-6 for x in lin(mid)):
                lo = mid
            else:
                hi = mid
        best = lo
    return tuple(_gam(max(0, min(1, x))) for x in lin(best))

def oklch(L, C, H):
    return rgb2hex(oklch2rgb(L, C, H))

def to_oklch(h):
    L, a, b = rgb2oklab(hex2rgb(h))
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360

def lum(rgb):
    r, g, b = (_lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def wcag(fg, bg):
    a, b = lum(hex2rgb(fg)), lum(hex2rgb(bg))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)

def apca(fg, bg):
    def y(h):
        r, g, b = hex2rgb(h)
        return 0.2126729 * r ** 2.4 + 0.7151522 * g ** 2.4 + 0.0721750 * b ** 2.4
    yt, yb = y(fg), y(bg)
    clamp = lambda v: v if v > 0.022 else v + (0.022 - v) ** 1.414
    yt, yb = clamp(yt), clamp(yb)
    if abs(yb - yt) < 0.0005:
        return 0.0
    if yb > yt:
        s = (yb ** 0.56 - yt ** 0.57) * 1.14
        out = 0 if s < 0.1 else s - 0.027
    else:
        s = (yb ** 0.65 - yt ** 0.62) * 1.14
        out = 0 if s > -0.1 else s + 0.027
    return out * 100

def over(fg, alpha, bg):
    f, b = hex2rgb(fg), hex2rgb(bg)
    return rgb2hex(tuple(alpha * x + (1 - alpha) * y for x, y in zip(f, b)))

# Machado et al. 2009, severity 1.0
_CVD = {
    'protan': ((0.152286, 1.052583, -0.204868), (0.114503, 0.786281, 0.099216), (-0.003882, -0.048116, 1.051998)),
    'deutan': ((0.367322, 0.860646, -0.227968), (0.280085, 0.672501, 0.047413), (-0.011820, 0.042940, 0.968881)),
    'tritan': ((1.255528, -0.076749, -0.178779), (-0.078411, 0.930809, 0.147602), (0.004733, 0.691367, 0.303900)),
}

def cvd(h, kind):
    r = [_lin(c) for c in hex2rgb(h)]
    m = _CVD[kind]
    out = [sum(m[i][j] * r[j] for j in range(3)) for i in range(3)]
    return rgb2hex(tuple(_gam(max(0, min(1, x))) for x in out))

def de(h1, h2):
    a, b = rgb2oklab(hex2rgb(h1)), rgb2oklab(hex2rgb(h2))
    return math.dist(a, b)
