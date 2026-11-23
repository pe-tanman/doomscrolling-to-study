"""Upscroll colour palette (v4): generator + verifier.

Every colour in ios/Upscroll/Views/Theme.swift (the `Palette` ramps and the on-dark / on-indigo accents)
comes out of this file. Change a ramp here, then:

    python3 -I tools/palette/palette.py            # verify (exits 1 on any failure), writes report.txt
    python3 -I tools/palette/palette.py --swift    # print the Swift `Palette` block to paste into Theme.swift

How the ramps are built
  * OKLCH, ten steps (50…900). Lightness is fixed per step, so every hue's 100 or 700 has the same weight.
  * Step 600 is contrast-targeted instead: the lightest shade of the hue that still reads as text on its
    own 100 tint (≥ 4.6:1). That makes one rule hold for every hue:
        600 is text-safe on white, 50 and 100 — and white text on 600 passes AA.
  * Hue drifts a little toward the dark end, as real pigments do (gold warms toward amber, pink toward rose),
    so the dark steps don't turn muddy. Out-of-gamut chroma is reduced, never clipped per channel.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from colorlib import apca, cvd, de, oklch, over, wcag  # noqa: E402

STEPS = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]
L = dict(zip(STEPS, [.975, .945, .895, .835, .755, .665, .545, .465, .385, .30]))
CMUL = dict(zip(STEPS, [.10, .18, .36, .60, .84, .96, 1, .94, .82, .66]))

# name: (hue at the light end, hue at the dark end, peak chroma, role)
RAMPS = {
    'indigo':  (287, 279, .175, '藍 ai — primary; the lavender→periwinkle sky of the art'),
    'neutral': (290, 282, .042, 'indigo-tinted greys; ink is a deep indigo, never flat black'),
    'sakura':  (355, 2, .15,   '桜 sakura — the blossoms; skill: speaking'),
    'gold':    (92, 68, .165,  '山吹 yamabuki — rewards, the next unlock; skill: writing'),
    'sky':     (240, 252, .14, '空 sora — skill: reading'),
    'asagi':   (196, 190, .11, '浅葱 asagi teal — skill: listening'),
    'matcha':  (148, 155, .15, '抹茶 matcha — right, learned, success'),
    'kaki':    (58, 46, .16,   '柿 kaki persimmon — "again", gentle warning'),
    'beni':    (24, 22, .19,   '紅 beni crimson — wrong, destructive'),
    'ice':     (225, 232, .11, '氷 kōri — streak freeze'),
}


def _hue(name, t):
    h0, h1 = RAMPS[name][:2]
    d = h1 - h0 + (360 if h1 - h0 < -180 else 0)
    return (h0 + d * t) % 360


def build():
    P = {}
    for n, (_, _, peak, _) in RAMPS.items():
        P[n] = {s: oklch(L[s], peak * CMUL[s], _hue(n, i / 9)) for i, s in enumerate(STEPS)}
    # Neutral: hand-set so ink reads as deep indigo and ink3 icons clear 3:1 on white and on the page.
    P['neutral'].update({
        50: oklch(.975, .008, 292), 100: oklch(.955, .012, 292), 200: oklch(.915, .016, 292),
        300: oklch(.83, .02, 288), 400: oklch(.73, .026, 286), 500: oklch(.62, .032, 285),
        600: oklch(.545, .04, 284), 700: oklch(.465, .048, 283), 800: oklch(.385, .06, 282),
        900: oklch(.30, .07, 282),
    })
    # 600: contrast-targeted (see module docstring).
    for n, (_, _, peak, _) in RAMPS.items():
        if n == 'neutral':
            continue
        h, l = _hue(n, 6 / 9), .56
        while wcag(oklch(l, peak, h), P[n][100]) < 4.6:
            l -= .002
        P[n][600] = oklch(l, peak, h)
    # Gold 300 is the vivid yamabuki fill (bars, rings, coins): more chroma than the other pastel 300s.
    P['gold'][300] = oklch(.835, .14, 82)
    return P


P = build()

# On the indigo hero cards (gradient indigo 700 → 800).
ON_INDIGO = {
    'gold': oklch(.90, .11, 88),     # "NEXT UNLOCK" labels, progress fill
    'muted': P['indigo'][50],        # secondary text (replaces white at 85–90 % opacity)
}
# Bright accents for the dark glass cards over video (all with black text when used as a capsule fill).
ON_DARK = {
    'gold': oklch(.88, .15, 88),     # the highlight: Japanese word, answer, buttons (replaces iOS system yellow)
    'cyan': oklch(.85, .095, 215),
    'peach': oklch(.84, .095, 55),
    'mint': oklch(.86, .10, 162),
    'violet': oklch(.80, .10, 292),
    'pink': oklch(.82, .10, 355),
    'lime': oklch(.88, .12, 125),
    'gray': oklch(.83, .012, 285),
    'right': oklch(.87, .15, 150),
    'wrong': oklch(.85, .11, 4),     # rose, not red: keeps right/wrong apart for red-green colour blindness
}

W, B = '#FFFFFF', '#000000'


def verify():
    rows, fails = [], []

    def chk(label, fg, bg, need):
        r, a = wcag(fg, bg), abs(apca(fg, bg))
        ok = r >= need
        if not ok:
            fails.append(label)
        rows.append(f'{"ok  " if ok else "FAIL"} {label:46} {fg} on {bg}  {r:5.2f}:1 (≥{need})  APCA Lc {a:5.1f}')

    N, I = P['neutral'], P['indigo']
    rows.append('— Light surfaces (dashboard) —')
    chk('ink (n900) on page (n50)', N[900], N[50], 7)
    chk('ink2 (n700) on page', N[700], N[50], 4.5)
    chk('ink2 on mist (n100)', N[700], N[100], 4.5)
    chk('ink2 on indigo 100', N[700], I[100], 4.5)
    chk('ink3 (n500) icons on white', N[500], W, 3)
    chk('ink3 icons on page', N[500], N[50], 3)
    chk('indigo 700 (accent text) on white', I[700], W, 4.5)
    chk('indigo 700 on indigo 100 (secondary btn)', I[700], I[100], 4.5)
    chk('ink on gold 300', N[900], P['gold'][300], 4.5)
    chk('ink on sakura 300', N[900], P['sakura'][300], 4.5)
    for n in RAMPS:
        if n == 'neutral':
            continue
        rows.append(f'— {n} —')
        chk(f'{n} 600 on white', P[n][600], W, 4.5)
        chk(f'{n} 600 on {n} 50', P[n][600], P[n][50], 4.5)
        chk(f'{n} 600 on {n} 100 (chip, tile)', P[n][600], P[n][100], 4.5)
        chk(f'white on {n} 600', W, P[n][600], 4.5)
        chk(f'{n} 600 bar vs empty track (n200)', P[n][600], N[200], 3)

    rows.append('— Indigo hero card (700 → 800) —')
    for step in (700, 800):
        chk(f'white on indigo {step}', W, I[step], 4.5)
        chk(f'onIndigo.gold on indigo {step}', ON_INDIGO['gold'], I[step], 4.5)
        chk(f'onIndigo.muted on indigo {step}', ON_INDIGO['muted'], I[step], 4.5)
    cell = over(W, .12, I[700])
    chk('onIndigo.muted on kana cell (12 % white)', ON_INDIGO['muted'], cell, 4.5)
    chk('white 70 % lock icon on indigo 700', over(W, .7, I[700]), I[700], 3)
    chk('white on indigo 600 (review card)', W, I[600], 4.5)

    rows.append('— Dark glass over video —')
    worst = over(B, .5, '#E0E0E0')     # a bright frame under the card's 50 % black tint
    typical = over(B, .5, '#9A9A9A')   # an average frame
    chk('white on worst-case glass', W, worst, 4.5)
    for k in ('gold', 'right', 'wrong'):
        chk(f'onDark.{k} on worst-case glass (icon/large)', ON_DARK[k], worst, 3)
        chk(f'onDark.{k} on typical glass (text)', ON_DARK[k], typical, 4.5)
    for k, v in ON_DARK.items():
        chk(f'black on onDark.{k} (capsule)', B, v, 7)

    rows.append('\n— Separation under colour-vision deficiency (min ΔE_OK; ≥ .06 comfortably distinct) —')
    rows.append('  Every one of these sets also carries an icon or a text label, so colour is never the only cue.')

    def sep(title, cols):
        out = []
        for kind in ('normal', 'protan', 'deutan', 'tritan'):
            c = {k: (v if kind == 'normal' else cvd(v, kind)) for k, v in cols.items()}
            ks = list(c)
            m = min((de(c[a], c[b]), a, b) for i, a in enumerate(ks) for b in ks[i + 1:])
            out.append(f'{kind} {m[0]:.3f}')
        rows.append(f'  {title:28} ' + '  '.join(out))

    sep('skills (600)', {'reading': P['sky'][600], 'listening': P['asagi'][600],
                         'writing': P['gold'][600], 'speaking': P['sakura'][600]})
    sep('status (600)', {'success': P['matcha'][600], 'again': P['kaki'][600], 'wrong': P['beni'][600]})
    sep('speaking vs wrong', {'speaking': P['sakura'][600], 'wrong': P['beni'][600]})
    sep('right vs wrong on video', {'right': ON_DARK['right'], 'wrong': ON_DARK['wrong']})
    sep('tag capsules on video', {k: ON_DARK[k] for k in ('cyan', 'peach', 'mint', 'violet', 'pink', 'lime', 'gray')})
    return rows, fails


def swift():
    def hx(h):
        return '0x' + h.lstrip('#')
    lines = ['enum Palette {']
    for n, (_, _, _, role) in RAMPS.items():
        lines.append(f'    /// {role}')
        lines.append(f'    static let {n} = Ramp(' + ', '.join(hx(P[n][s]) for s in STEPS) + ')')
    lines.append('}')
    lines.append('')
    for title, d in (('OnIndigo', ON_INDIGO), ('OnDark', ON_DARK)):
        lines.append(f'// {title}: ' + ', '.join(f'{k}={hx(v)}' for k, v in d.items()))
    return '\n'.join(lines)


if __name__ == '__main__':
    if '--swift' in sys.argv:
        print(swift())
        sys.exit(0)
    rows, fails = verify()
    here = os.path.dirname(os.path.abspath(__file__))
    head = ['Upscroll palette v4 — verification report (generated by palette.py)', '']
    for n in RAMPS:
        head.append(f'{n:8} ' + ' '.join(P[n][s] for s in STEPS))
    head.append('onIndigo ' + ' '.join(f'{k}={v}' for k, v in ON_INDIGO.items()))
    head.append('onDark   ' + ' '.join(f'{k}={v}' for k, v in ON_DARK.items()))
    head.append('')
    report = '\n'.join(head + rows + ['', f'{sum(r.startswith("ok") for r in rows)} pairs pass, {len(fails)} fail'])
    open(os.path.join(here, 'report.txt'), 'w').write(report + '\n')
    json.dump({'ramps': P, 'onIndigo': ON_INDIGO, 'onDark': ON_DARK}, open(os.path.join(here, 'palette.json'), 'w'), indent=1)
    print(report)
    sys.exit(1 if fails else 0)
