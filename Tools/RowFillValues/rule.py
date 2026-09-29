#!/usr/bin/env python3
"""The row fills for a palette that arrives at RUNTIME -- a custom palette, LiveTerminalPalette's report, a
`.tint` subtree -- and the reference `RowFillRule.swift` must match (generate.py --goldens).

The sixteen shipped palettes never run it: they read the constants in values.json. This is the design's
v5c rule (2026-09-29), with its colour maths replaced by TUIkitStyling's own so the two agree to the bit:
WCAG luminance and contrast, `Color.perceivedLightness` (CIE L* of that luminance), `Color.lerp`'s
rounding, `Color.lighter(by:)` / `darker(by:)` (HSL), `Color.oklab`, `nearestPalette256Index` and
`Color.cubeRamp(from:to:)`.

The design's notes, kept with the rule they explain:
No CIEDE2000, no colour-vision model, no criteria, no scoring. Every end is placed by a walk (truecolour: along a
path; 256: first fit along a ladder sorted by distance to a target lift), and each depth checks its own hard
invariants (the rule's estimates: `sure` for ΔE00 floors) and retries on a wider ladder / a lower floor.

WHAT CHANGED FROM v5b's SIMPLE RULE (rule_simple.py), and why (v5b verifier: flat truecolour B on Zenburn, Tango,
Solarized and mid-grey pages; F on S's entry at 256; invariants failing outright):
  truecolour  The path is page -> A, where A is the accent pushed toward the text in its own hue (HSL lighter/darker,
              which Color has) until it sits 45 L* off the page or the text would fall under 2:1. Zenburn's blue is
              13 L* up: the old ray ended there, so S, F's top and B sat within 0.3 L* of each other. An accent on the
              page's far side (mid-grey pages) crosses the page the same way. The path's top is the text's 2:1 (and
              the secondary text's 1.5:1, and 5.5 OKLab under the ●). S starts at today's 25% of the accent.
              Every end is a walk on the path, then one short walk per hard invariant. rule_true() then tries, in
              order, until a look holds H0-H5 with both breaths >= 12: S a step lower / higher (every other index,
              up to 24 either way; the text 3:1 on S first, then 2:1); F's dim end on the page's own line toward the
              text (it clears S by chroma); the secondary text's cap dropped; the ●'s margin dropped; the accent at
              full HSL saturation, with F's dim end also allowed on the complementary hue; then the same without the
              breath target. Else the look that holds the invariants and breathes most.
  256         S is chosen where B can still breathe 12 above it; B is placed before F; every end is a FIRST FIT over a
              ladder sorted by distance to its target, filtered by the hard invariants (F never on S's entry at any
              frame, never on the page's, B never on S's, F and B never one entry on one frame, B's peak a different
              entry >= 2 L* higher); soft wishes (breath 12, B's peak 8 over F's, "a little brighter") are dropped in
              tiers. Ladders: in-hue (30°), 60°, every entry; the secondary text >= 1.5:1, then not. Where none gives
              both breaths 12, every S on the whole-cube ladder is tried (lowest first). Where no entry between the
              page and the text keeps the text 2:1 at all (the listed exception), entries PAST the text that do.
              No more 'none' fallback (it quantised the truecolour ends and inverted dgreen-lowtext-sat0).
  16          'pairs' (five distinct legible fills), 'reversed' (reverse video in anti-phase), 'shared' (one fill for
              both breaths, anti-phase): all keep every state distinguishable, and are tried at each secondary floor
              before it drops, the ● kept off B first; weak pairs only after those. A pick is taken only if its own
              frames hold H0-H5. Fewer than two legible fills: the listed text exception.
LiveTerminalPalette's page and text are SGR 49 / 39 at every depth: they are its reported colours, never quantised.
"""
import functools
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import cube_rgb, linear, lightness as Ls, oklab as _oklab, cube_ramp as _cube_ramp  # noqa: E402

FRAMES = 16
XTERM16 = [(0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205),
           (229, 229, 229), (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255),
           (255, 0, 255), (0, 255, 255), (255, 255, 255)]
ANSI_NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white', 'brightBlack',
              'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightMagenta', 'brightCyan',
              'brightWhite']
oklab = functools.lru_cache(maxsize=1 << 16)(lambda c: _oklab(tuple(c)))


def rnd(x):
    """Swift `Double.rounded()`: to nearest, ties away from zero."""
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def clamped_byte(v):
    return int(max(0, min(255, rnd(v)))) if math.isfinite(v) else 0


def lum(c):
    return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])


def cr(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def lerp(a, b, t):
    """Color.lerp: per channel in encoded sRGB, rounded."""
    t = min(1.0, max(0.0, t))
    return tuple(int(min(255, max(0, rnd(x + (y - x) * t)))) for x, y in zip(a, b))


def over(c, op, surf):
    """`c.opacity(op, over: surf)` for an opaque `c`."""
    return lerp(c, surf, 1 - min(1.0, max(0.0, op)))


def hsl(h, s, l):
    """Color.hsl."""
    h = h % 360
    nh, ns, nl = h / 360, s / 100, l / 100
    if ns <= 0:
        g = clamped_byte(nl * 255)
        return (g, g, g)
    c = nl * (1 + ns) if nl < 0.5 else nl + ns - nl * ns
    lu = 2 * nl - c

    def h2(lu, ch, hc):
        if hc < 0:
            hc += 1
        if hc > 1:
            hc -= 1
        if hc < 1 / 6:
            return lu + (ch - lu) * 6 * hc
        if hc < 1 / 2:
            return ch
        if hc < 2 / 3:
            return lu + (ch - lu) * (2 / 3 - hc) * 6
        return lu
    return (clamped_byte(h2(lu, c, nh + 1 / 3) * 255), clamped_byte(h2(lu, c, nh) * 255),
            clamped_byte(h2(lu, c, nh - 1 / 3) * 255))


def rgb_to_hsl(rgb):
    """Color.rgbToHSL."""
    r, g, b = [x / 255 for x in rgb]
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    l = (mx + mn) / 2
    if d <= 0:
        return (0, 0, l * 100)
    s = d / (mx + mn) if l < 0.5 else d / (2 - mx - mn)
    if mx == r:
        seg = (g - b) / d
        h = 60 * (seg + 6 if seg < 0 else seg)
    elif mx == g:
        h = 60 * ((b - r) / d + 2)
    else:
        h = 60 * ((r - g) / d + 4)
    return (h, s * 100, l * 100)


def p256rgb(i):
    return XTERM16[i] if i < 16 else cube_rgb(i)


_CUBE_LAB = [(i, oklab(cube_rgb(i))) for i in range(16, 256)]
_INDEX = {cube_rgb(i): i for i in range(16, 256)}


@functools.lru_cache(maxsize=1 << 16)
def q256(rgb):
    """`Color.nearestPalette256Index`: the cube entry a truecolour RGB draws as (the lower 16 never)."""
    L, A, B = oklab(rgb)
    C = math.hypot(A, B)
    must = C >= 0.01
    best, bd = 16, float('inf')
    for i, (l2, a2, b2) in _CUBE_LAB:
        c2 = math.hypot(a2, b2)
        if must and not (cube_rgb(i) == (0, 0, 0) or c2 >= 0.01):
            continue
        dl, dc, da, db = L - l2, C - c2, A - a2, B - b2
        dh2 = max(0, da * da + db * db - dc * dc)
        d = dl * dl + (4.0 if dc > 0 else 1.0) * dc * dc + 4 * dh2
        if d < bd:
            bd, best = d, i
    return best


def at(c, depth):
    return tuple(c) if depth == 'true' else p256rgb(q256(tuple(c)))


def phase_at(frame):
    """CursorTimer.pulsePhase(atFrame:of: 16)."""
    return (math.cos(frame % FRAMES / FRAMES * 2 * math.pi) + 1) / 2


def step_frames(steps):
    """The 16 frames of an explicit breath: SelectionEmphasis.pulsed's equal-time steps."""
    n = len(steps)
    out = []
    for f in range(FRAMES):
        t = math.acos(max(-1.0, min(1.0, 1 - 2 * phase_at(f)))) / math.pi
        out.append(tuple(steps[min(n - 1, max(0, int(math.floor(t * n + 1e-9))))]))
    return out


def cube_ramp(a, b):
    """Color.cubeRamp(from:to:) on RGB ends."""
    return [cube_rgb(i) for i in _cube_ramp(_INDEX[tuple(a)], _INDEX[tuple(b)])]


def sec_of(p):
    return tuple(p['sec'])


class R4:
    """The 16-colour table helpers the rule reads (v4's rules module)."""
    XTERM = XTERM16

    @staticmethod
    def nearest(c, tbl):
        return min(range(16), key=lambda i: (sum((x - y) ** 2 for x, y in zip(c, tbl[i])), i))


N = 128
_ramps = {}


def ramp(a, b):
    """Color.pulseRamp for two .palette256 ends (v5 plan commit 2 = lib5.cube_ramp), memoised as pulseRamp's own cache
    is (Color+PulseRamp.swift:121-127)."""
    k = (tuple(a), tuple(b))
    if k not in _ramps:
        r = cube_ramp(a, b)
        _ramps[k] = (r, step_frames(r))
    return _ramps[k][0]


def frames256(a, b):
    """The 16 frames of a 256 breath (step_frames over the ramp): the ramp's steps at their time positions."""
    ramp(a, b)
    return _ramps[(tuple(a), tuple(b))][1]


def SL(L):
    return 1 + 0.015 * (L - 50) ** 2 / math.sqrt(20 + (L - 50) ** 2)


def step(a, b):
    la, lb = Ls(a), Ls(b)
    return abs(la - lb) / SL((la + lb) / 2)


def apart(a, b, k, m=0.0):
    """hypot(step, k x OKLab a-b distance x 100 / (1 + m x mean OKLab chroma x 100)): ΔE00's lightness term plus a
    chroma-plane term compressed with chroma, as ΔE00's SC / SH compress it."""
    A, B = oklab(a), oklab(b)
    cm = (math.hypot(A[1], A[2]) + math.hypot(B[1], B[2])) / 2
    return math.hypot(step(a, b), k * 100 * math.hypot(A[1] - B[1], A[2] - B[2]) / (1 + m * 100 * cm))


near = lambda a, b: apart(a, b, 1.4)          # placement (~ΔE00 at the median)
# floors: calibrate.py on 88,108 pairs the rule compares (paths, page lines, cube entries; 1-16 ΔE00 apart):
# <= ΔE00 on 97.7%, over 1.1x ΔE00 on 0.06%; its 5th percentile is 0.61 x ΔE00 (v5b's k=0.8 form: 0.37)
sure = lambda a, b: apart(a, b, 2.8, 0.2)
F4 = 4.4                                      # the invariants' 4 ΔE00, with a 10% margin for the estimate


def hue_chroma(c):
    _, a, b = oklab(c)
    return math.degrees(math.atan2(b, a)) % 360, math.hypot(a, b)


def hue_gap(a, b):
    g = abs(a - b) % 360
    return min(g, 360 - g)


def walk(i, cond, d, lim):
    while (i < lim if d > 0 else i > lim) and cond(i):
        i += d
    return i


def push(c, k, d):
    """Color.lighter(by: k) (d > 0) / darker(by: k): HSL lightness toward white / black, hue and saturation kept."""
    h, s, l = rgb_to_hsl(c)
    return hsl(h, s, l + (100 - l) * k if d > 0 else l * (1 - k))


class Pal:
    def __init__(self, p):
        self.page, self.text, self.acc, self.sec = tuple(p['bg']), tuple(p['fg']), tuple(p['accent']), sec_of(p)
        self.Lp = Ls(self.page)
        # LiveTerminalPalette's page and text are the terminal's own (SGR 49 / 39) at EVERY depth: never quantised
        self.live = p.get('kind') == 'live'
        self.page256 = self.page if self.live else at(self.page, '256')
        self.text256 = self.text if self.live else at(self.text, '256')
        self.d = 1 if Ls(self.text) >= self.Lp else -1
        # A: the accent, pushed toward the text in its own hue (HSL lightness) while it sits under 45 L* off the page
        # (S ~12, + 22 for the two peaks, + the ●'s margin) and the text still reads 2:1 on the next step
        k = walk(0, lambda k: self.lift(push(self.acc, k / N, self.d)) < 45
                 and cr(self.text, push(self.acc, (k + 1) / N, self.d)) >= 2, 1, N)
        self.A = push(self.acc, k / N, self.d)

    def lift(self, c, base=None):
        return (Ls(c) - (self.Lp if base is None else Ls(base))) * self.d

    def R(self, i):
        return lerp(self.page, self.A, i / N)


# ------------------------------------------------------------------ truecolour

def tframes(a, b):
    return [lerp(a, b, phase_at(f)) for f in range(16)]


def hard_true(c, S, F, B):
    """The rule's own check of H0-H5 (estimates); H6 holds by the path's cap. F's transit past S's lightness is a
    preference (the JND walks in place_true), not a gate: v5's approved looks pass within 1 ΔE00 of S on 5 palettes."""
    Ff, Bf, lift = tframes(*F), tframes(*B), c.lift
    off = lambda x, b: sure(x, b) >= F4 and lift(x, b) >= 2
    return (off(S, c.page) and all(off(x, c.page) for x in Ff) and all(off(x, S) for x in Bf)
            and min(sure(Ff[f], S) for f in (15, 0, 1, 7, 8, 9)) >= F4
            and min(sure(a, b) for a, b in zip(Ff, Bf)) >= F4 and sure(B[1], F[1]) >= F4 and lift(B[1], F[1]) >= 2)


def place_true(c, sec_floor, iS=None, fd_line='path', dot=True, need=12.0):
    """One look at truecolour. S and every peak ride the path R; F's dim end rides R too, or -- fd_line 'text', the
    fallback where the room is short -- the page's own line toward the text (the page, a little brighter: it clears S
    by chroma where there is no lightness to spare), or -- 'complement', the last resort -- a line toward the accent's
    opposite hue, which clears S by hue and lets S sit a few L* off the page."""
    R, lift, text = c.R, c.lift, c.text
    if fd_line == 'path':
        D = R
    elif fd_line == 'text':
        D = lambda i: lerp(c.page, text, i / N)
    else:                     # 'complement': toward the accent's opposite hue, full HSL saturation, at A's lightness
        h, _, l = rgb_to_hsl(c.A)
        Ac = hsl(h + 180, 100, l)
        D = lambda i: lerp(c.page, Ac, i / N)
    # up from the page to the last point before the text's 2:1 (the secondary's floor); past the text's own
    # lightness the ratio climbs again, so the walk never looks beyond the first failure
    top = walk(1, lambda i: cr(text, R(i + 1)) >= 2 and cr(c.sec, R(i + 1)) >= sec_floor, 1, N)
    # and below the ● (the accent itself): B's peak must not swallow it
    top = walk(top, lambda i: dot and 100 * math.dist(oklab(c.acc), oklab(R(i))) < 5.5, -1, 1)
    room = lift(R(top))
    if iS is None:
        # today's S (the accent at 25%) where the accent faces the text, else 25% of the pushed accent
        s0 = lift(lerp(c.page, c.acc, 0.25)) if lift(c.acc) > 0 else lift(R(32))
        iS = walk(1, lambda i: lift(R(i)) < s0, 1, top)
        iS = walk(iS, lambda i: cr(text, R(i)) < 3, -1, 1)
        iS = walk(iS, lambda i: (near(R(i), c.page) < 12 or lift(R(i)) < 6) and cr(text, R(i + 1)) >= 3, 1, top)
        # S moves DOWN (to 8 L*, 10 ΔE00 est. off the page) while the room above it cannot give F's top 8 over S and
        # B's peak 10 over F's
        iS = walk(iS, lambda i: room - lift(R(i)) < 18 and near(R(i - 1), c.page) >= 10 and lift(R(i - 1)) >= 8, -1, 1)
    S, Sl = R(iS), lift(R(iS))
    free = max(0.0, room - Sl)
    g, h = (10.0, 12.0) if free >= 22 else (free / 2 - 1, free / 2 + 1) if free >= 18 else (8 * free / 18, 10 * free / 18)
    iFt = walk(iS, lambda i: lift(R(i)) < Sl + g, 1, top)
    iBt = walk(iFt, lambda i: lift(R(i)) < Sl + g + h, 1, top)
    rise = lift(R(iBt), S)
    iBd = walk(iS + 1, lambda i: lift(R(i + 1), S) <= 0.5 * rise and (lift(R(i), S) < max(3.0, 0.2 * rise)
                                                                    or near(R(i), S) < 4), 1, iBt)
    cap = min(0.6 * Sl, Sl - 2.0)
    iFd = walk(1, lambda i: lift(D(i + 1)) <= cap and (lift(D(i)) < max(3.5, 0.35 * Sl) or near(D(i), c.page) < 5), 1, N)
    iFd = walk(iFd, lambda i: near(D(i), S) < 6 and near(D(i - 1), c.page) >= 5, -1, 1)
    # the hard invariants, one short walk each (H3, P2 for B, H5, H2 at F's top, P2 for F, H1, H2 at F's dim end)
    iBd = walk(iBd, lambda i: sure(R(i), S) < F4 or lift(R(i), S) < 2, 1, iBt - 1)
    iBt = walk(iBt, lambda i: lift(R(i), R(iBd)) < need, 1, top)
    iFt = walk(iFt, lambda i: sure(R(iBt), R(i)) < F4, -1, iS + 1)
    iFt = walk(iFt, lambda i: (sure(R(i), S) < F4 or lift(R(i), D(iFd)) < need) and sure(R(iBt), R(i + 1)) >= F4, 1, iBt - 1)
    iFd = walk(iFd, lambda i: sure(D(i), c.page) < F4 or lift(D(i)) < 2, 1, N)
    iFd = walk(iFd, lambda i: sure(D(i), S) < F4 and sure(D(i - 1), c.page) >= F4 and lift(D(i - 1)) >= 2, -1, 1)
    # a preference, not a gate: no F frame within one JND of S -- F's dim end steps toward the page (still 5 off it
    # and 6 off S, est.), else F's top up (leaving B's peak room for 10 over it), else down (still 8 L* past S)
    jnd = lambda a, b: min(near(x, S) for x in tframes(a, b)) < 1.2
    iFd = walk(iFd, lambda i: jnd(D(i), R(iFt)) and near(D(i - 1), c.page) >= 5 and sure(D(i - 1), c.page) >= F4
               and near(D(i - 1), S) >= 6 and lift(D(i - 1)) >= 2, -1, 1)
    iF0 = iFt
    iFt = walk(iFt, lambda i: jnd(D(iFd), R(i)) and room - lift(R(i + 1)) >= 10 and sure(R(iBt), R(i + 1)) >= F4, 1, iBt - 1)
    if jnd(D(iFd), R(iFt)):
        iFt = walk(iF0, lambda i: jnd(D(iFd), R(i)) and lift(R(i - 1), D(iFd)) >= need and lift(R(i - 1), S) >= 8
                   and sure(R(i - 1), S) >= F4, -1, iS + 1)
    # B's peak keeps 10 L* over F's where the room allows (the walks above can lift F's top)
    iBt = walk(iBt, lambda i: lift(R(i), R(iFt)) < 10, 1, top)
    look = dict(S=S, F=(D(iFd), R(iFt)), B=(R(iBd), R(iBt)), iS=iS, sec_floor=sec_floor, fd_line=fd_line)
    look['ok'] = hard_true(c, S, look['F'], look['B'])
    look['breath'] = min(lift(R(iFt), D(iFd)), lift(R(iBt), R(iBd)))
    return look


def rule_true(p):
    """The first look that holds H0-H5 with both breaths >= 12. Variants, in order: the secondary text's 1.5:1 cap,
    then none; then the ●'s margin under the path's top dropped; then the accent at full HSL saturation (same hue:
    a near-grey accent has no chroma to separate four ends by). In each, F's dim end on the path, then on the page's
    own line; and S where place_true puts it, then a step down, a step up, two down, ... (S >= 5 ΔE00 est. and 3 L*
    off the page, the text >= 3:1 on it, then >= 2:1; every other step, at most 24 either way). Else the look that
    holds the invariants and breathes most."""
    c = Pal(p)
    best = None
    A0 = c.A
    for need, sf, dot, vivid in ((12, 1.5, True, False), (12, 0.0, True, False), (12, 0.0, False, False),
                                 (12, 0.0, False, True), (0, 1.5, True, False), (0, 0.0, False, True)):
        h, sat, l = rgb_to_hsl(A0)
        c.A = hsl(h, 100 if vivid else sat, l)
        S_ok = lambda i, t: 2 <= i < N and sure(c.R(i), c.page) >= 5 and c.lift(c.R(i)) >= 3 and cr(c.text, c.R(i)) >= t
        for fl in (('path', 'text', 'complement') if vivid else ('path', 'text')):
            i0 = place_true(c, sf, None, fl, dot, need)['iS']
            for t in (3.0, 2.0):             # the text at 3:1 on S at rest where it can be, else the hard 2:1
                for k in range(0, 25):
                    i = i0 + 2 * ((k + 1) // 2) * (1 if k % 2 else -1)
                    if (k or t < 3) and (not S_ok(i, t) or (t < 3 and S_ok(i, 3.0))):
                        continue
                    lk = place_true(c, sf, i, fl, dot, need)
                    lk['variant'] = dict(need=need, sec_floor=sf, dot=dot, vivid=vivid, fd_line=fl)
                    if lk['ok'] and lk['breath'] >= 12:
                        return lk
                    if best is None or (lk['ok'], min(lk['breath'], 12.0)) > (best['ok'], min(best['breath'], 12.0)):
                        best = lk
    return best


# ------------------------------------------------------------------ 256

CUBE_E = [p256rgb(i) for i in range(16, 256)]


def ladder(c, deg, sec_floor, legible=True, text_floor=2.0):
    """Cube entries between the page and the text, text >= 2:1 and secondary >= sec_floor on them, never the page's
    entry, sorted by lift -> (E, G). E: within `deg` degrees (OKLab hue) of the accent's tints at 25/50/75/100%
    (greys where the accent is grey); every entry where deg is None. G: the greys a grey page may lift F's dim end
    to ("the page, a little brighter"), empty on a tinted page. legible=False
    (the listed exception, where no entry between the page and the text keeps the text at 2:1): entries toward the
    text and PAST it with the text >= 2:1 (the fill lighter than the text on a dark page), else any toward the text."""
    page, text, sec = c.page256, c.text256, at(c.sec, '256')
    A = [h for h, ch in (hue_chroma(lerp(c.page, c.acc, k)) for k in (0.25, 0.5, 0.75, 1.0)) if ch >= 0.03]
    page_grey = hue_chroma(page)[1] < 0.03
    lo, hi = sorted((lum(page), lum(text)))
    E, G = [], []
    for e in CUBE_E:
        if e == page or (legible and (not (lo <= lum(e) <= hi) or cr(text, e) < 2 or cr(sec, e) < sec_floor)) \
                or (not legible and (c.lift(e, page) <= 0 or cr(text, e) < text_floor)):
            continue
        h, ch = hue_chroma(e)
        if deg is None or (ch < 0.03 and not A) or (ch >= 0.03 and A and min(hue_gap(h, x) for x in A) <= deg):
            E.append(e)
        elif ch < 0.03 and page_grey:
            G.append(e)
    key = lambda e: (c.lift(e), e)
    return sorted(E, key=key), sorted(G, key=key)


def first(cands, *tiers):
    """The first candidate meeting every test of the first tier any candidate meets; a tier is (sort key, tests)."""
    for key, tests in tiers:
        for e in sorted(cands, key=key):
            if all(t(e) for t in tests):
                return e
    return None


def hard_256(c, page, S, F, B):
    Ff, Bf = frames256(*F), frames256(*B)
    off = lambda x, b: x != b and sure(x, b) >= F4 and c.lift(x, b) >= 2
    return (off(S, page) and all(off(x, page) for x in Ff) and S not in Ff and all(off(x, S) for x in Bf)
            and not any(a == b for a, b in zip(Ff, Bf)) and B[1] != F[1] and c.lift(B[1], F[1]) >= 2
            and len(set(Ff)) > 1 and len(set(Bf)) > 1)


def place_256(c, EG, tc, S_at=None):
    E, G = EG
    if len(E) < 3:
        return None
    page = c.page256
    lift = lambda e, b=None: c.lift(e, b)
    off = lambda x, b: x != b and sure(x, b) >= F4 and lift(x, b) >= 2
    fr = frames256
    to = lambda target: (lambda e: (abs(lift(e) - target), e))
    low, high = (lambda e: (lift(e), e)), (lambda e: (-lift(e), e))
    Bd_of = lambda S: first([e for e in E if off(e, S)], (low, []))
    Broom = lambda S: Bd_of(S) is not None and lift(E[-1], Bd_of(S)) >= 12
    Fd_ok = lambda S: any(off(e, page) and e != S and lift(S, e) >= 2 for e in E + G)
    # S: nearest the truecolour S, >= 8 (est.) off the page, B able to breathe 12 above it, an F dim end below it;
    # where B cannot breathe 12 above any S, the lowest S (B's most room)
    tS = to(c.lift(tc['S']))
    S = S_at or first(E[:-2], (tS, [lambda e: sure(e, page) >= 8, lambda e: lift(e) > 0, Broom, Fd_ok]),
              (tS, [lambda e: off(e, page), Broom, Fd_ok]), (tS, [lambda e: off(e, page), Broom]),
              (low, [lambda e: off(e, page), Fd_ok]), (low, [lambda e: off(e, page)]))
    if S is None:
        return None
    Bd = Bd_of(S)
    if Bd is None:
        return None
    # B first: its peak nearest the truecolour peak, breathing 12, else the highest; then F under it
    Bt = first([e for e in E if lift(e, Bd) > 0], (to(max(c.lift(tc['B'][1]), lift(Bd) + 12)),
               [lambda e: lift(e, Bd) >= 12, lambda e: S not in fr(Bd, e)]), (high, [lambda e: S not in fr(Bd, e)]))
    if Bt is None:
        return None
    Bf = fr(Bd, Bt)
    fd_base = [lambda e: off(e, page), lambda e: e != S]
    Fd = first(E + G, (low, fd_base + [lambda e: lift(S, e) >= 2, lambda e: lift(e) <= 0.6 * lift(S)]),
               (low, fd_base + [lambda e: lift(S, e) >= 2]), (low, fd_base))
    if Fd is None:
        return None
    Fok = lambda e: (lift(Bt, e) >= 2 and e != Bt and S not in fr(Fd, e) and page not in fr(Fd, e)
                     and all(off(x, page) for x in fr(Fd, e)) and not any(a == b for a, b in zip(fr(Fd, e), Bf)))
    tF = to(min(c.lift(tc['F'][1]), lift(Bt) - 8))
    Ft = first([e for e in E if lift(e, Fd) > 0],
               (tF, [Fok, lambda e: lift(e, Fd) >= 12, lambda e: lift(Bt, e) >= 8, lambda e: lift(e, S) >= 4]),
               (tF, [Fok, lambda e: lift(e, Fd) >= 12, lambda e: lift(e, S) >= 4]), (tF, [Fok, lambda e: lift(e, Fd) >= 12]),
               (high, [Fok]))
    if Ft is None:
        return None
    # B's peak 8 L* over F's where the ladder has an entry for it (F may have had to pass S's entry to breathe)
    if lift(Bt, Ft) < 8:
        Ff = fr(Fd, Ft)
        Bt = first([e for e in E if lift(e, Ft) >= 8], (low, [lambda e: S not in fr(Bd, e),
                   lambda e: not any(a == b for a, b in zip(Ff, fr(Bd, e)))])) or Bt
    look = dict(S=S, F=(Fd, Ft), B=(Bd, Bt))
    look['ok'] = hard_256(c, page, S, look['F'], look['B'])
    look['breath'] = min(lift(Ft, Fd), lift(Bt, Bd))
    return look


def rule_256(p, tc):
    c = Pal(p)
    best = None
    for sf in (1.5, 0.0):
        for deg in (30.0, 60.0, None):
            lk = place_256(c, ladder(c, deg, sf), tc)
            if lk is None:
                continue
            lk['ladder'], lk['sec_floor'] = deg, sf
            if lk['ok'] and lk['breath'] >= 12:
                return lk
            if best is None or (lk['ok'], min(lk['breath'], 12.0)) > (best['ok'], min(best['breath'], 12.0)):
                best = lk
    if best is not None and not (best['ok'] and best['breath'] >= 12):
        # no ladder gives both breaths 12 from the S the tiers chose: every S on the whole cube's ladder, lowest first
        # (B's most room), keeping the look that holds the invariants and breathes most
        for sf in (1.5, 0.0):
            EG = ladder(c, None, sf)
            for S in EG[0][:-2]:
                lk = place_256(c, EG, tc, S)
                if lk and (lk['ok'], min(lk['breath'], 12.0)) > (best['ok'], min(best['breath'], 12.0)):
                    best = dict(lk, ladder='S-sweep', sec_floor=sf)
    if best is None:     # no three entries keep the text 2:1 (the listed exception): H0-H5 on any entry toward the text
        best = place_256(c, ladder(c, None, 0.0, False), tc) or place_256(c, ladder(c, None, 0.0, False, 0.0), tc)
        if best is not None:
            best.update(ladder='past-the-text', sec_floor=0.0)
    if best is None:
        best = dict(S=at(tc['S'], '256'), F=tuple(at(x, '256') for x in tc['F']), B=tuple(at(x, '256') for x in tc['B']),
                    ladder='none', ok=False, breath=0.0)
    return best


# ------------------------------------------------------------------ 16

STRONG = 18.0   # OKLab x100 (v5b calibrate16.py: no slot pair of the 18 tables at >= 18 is under 15 ΔE00)


def rule_16(p, tc, tbl):
    """Against the REPORTED table, by colour. page / text / secondary text are the slots nearest the palette's
    (LiveTerminalPalette's page and text are its own reported colours); the page and text are never fills, the
    secondary text's slot only at the last floor; a fill keeps the text >= 2:1. Modes: 'pairs' -- S, Fd, Ft, Bd, Bt five different fills, each the
    unused fill nearest (RGB) its truecolour end, each breath's two >= STRONG apart; 'reversed' -- S a fill,
    F = (a fill, reverse video), B = (reverse video, another fill), in anti-phase; 'shared' -- the same with ONE fill
    for both breaths (F = (b, rev), B = (rev, b): never the same colour on a frame). All three keep every state
    distinguishable, so they are tried in turn at each secondary floor (1.5, 1.25, 1.1, none) before the floor drops,
    first keeping the ● off B (and the faded ● off S), then not; pairs whose breaths are weaker than STRONG (a visible
    change, priority 2) come only after all of those. A pick is taken only if its own frames hold H0-H5. Last resort (fewer than two legible fills): the most legible OTHER colour joins, S keeps
    the legible fill, and F = (rev, x), B = (x, rev) -- x's frames are the listed text exception."""
    tbl = [tuple(x) for x in tbl]
    nearest = lambda x: tbl[R4.nearest(x, tbl)]
    live = p.get('kind') == 'live'
    page, text, sec = (tuple(p['bg']) if live else nearest(p['bg'])), (tuple(p['fg']) if live else nearest(p['fg'])), nearest(sec_of(p))
    dot, fdot = nearest(p['accent']), nearest(over(p['accent'], 0.6, p['bg']))
    others = sorted((x for x in dict.fromkeys(tbl) if x not in (page, text)), key=lambda x: (-cr(text, x), x))
    # the secondary text's own slot is a fill only at the last floor (it reads 1:1 there; v5b's fix), before the
    # primary text's 2:1 ever gives way
    cols = [x for x in others if cr(text, x) >= 2]
    d2 = lambda a, b: sum((x - y) ** 2 for x, y in zip(a, b))
    strong = lambda a, b: 100 * math.dist(oklab(a), oklab(b)) >= STRONG
    REV = text          # stands for reverse video (the text's colour under the page's ink)

    def ok(pk, keep_dot):
        F, B = step_frames([pk['Fd'], pk['Ft']]), step_frames([pk['Bd'], pk['Bt']])
        return (pk['S'] != page and page not in F + B and pk['S'] not in F + B and F[0] != B[0]
                and not any(a == b for a, b in zip(F, B)) and len(set(F)) > 1 and len(set(B)) > 1
                and (not keep_dot or (dot not in B and pk['S'] != fdot)))   # the ● visible on B, the faded ● on S

    def picks(use, mode, keep_dot):
        taken = []

        def pick(target, t=lambda x: True):
            x = min((x for x in use if x not in taken and t(x)), key=lambda x: (d2(target, x), x), default=None)
            taken.append(x)
            return x
        S = pick(tc['S'], lambda x: x != fdot)
        if mode in ('pairs', 'pairs-weak'):
            w = mode == 'pairs'
            Fd = pick(tc['F'][0])
            Ft = pick(tc['F'][1], lambda x: Fd is not None and (not w or strong(x, Fd)))
            Bd = pick(tc['B'][0], lambda x: x != dot)
            Bt = pick(tc['B'][1], lambda x: x != dot and Bd is not None and (not w or strong(x, Bd)))
            pk = dict(S=S, Fd=Fd, Ft=Ft, Bd=Bd, Bt=Bt)
        elif mode == 'reversed':
            a, b = pick(tc['F'][0]), pick(tc['B'][1], lambda x: x != dot)
            pk = dict(S=S, Fd=a, Ft=REV, Bd=REV, Bt=b)
        else:
            b = pick(tc['F'][0], lambda x: x != dot)
            pk = dict(S=S, Fd=b, Ft=REV, Bd=REV, Bt=b)
        return pk if None not in pk.values() and ok(pk, keep_dot) else None
    pk = how = None
    for modes, keep_dot in ((('pairs', 'reversed', 'shared'), True), (('pairs', 'reversed', 'shared'), False),
                            (('pairs-weak',), False)):
        for floor in (1.5, 1.25, 1.1, 0.0):
            for mode in modes:
                pk = picks([x for x in cols if cr(sec, x) >= floor], mode, keep_dot)
                if pk:
                    how = mode
                    break
            if pk:
                break
        if pk:
            break
    if pk is None:
        a = cols[0] if cols else (others[0] if others else page)
        x = next((y for y in others if y != a), a)
        pk, how = dict(S=a, Fd=REV, Ft=x, Bd=x, Bt=REV), 'last-resort'
    cyc = lambda a, b: step_frames([a, b])
    return dict(S=pk['S'], F=cyc(pk['Fd'], pk['Ft']), B=cyc(pk['Bd'], pk['Bt']), pick=pk, how=how,
                reversed=[REV] if REV in pk.values() else [], dot=dot, faded_dot=fdot, page=page, text=text, sec=sec,
                slots={k: ([ANSI_NAMES[i] for i in range(16) if tbl[i] == v] if v != REV else ['reverse'])
                       for k, v in pk.items()})


def rule(p, tbl=None):
    lk = rule_true(p)
    return dict(true=lk, q=rule_256(p, lk), s16=rule_16(p, lk, [tuple(x) for x in (tbl or p.get('table', R4.XTERM))]))
