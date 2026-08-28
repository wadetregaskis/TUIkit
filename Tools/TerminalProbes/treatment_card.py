#!/usr/bin/env python3
"""The treatment card: every shipped Apple Terminal emission, as expect/actual
row pairs a human (or a screenshot analyser) can verify at a glance.

This is the instrument that settled the 2026-08-27 treatments — four
generations of it ran during that session — committed in its final form: it
shows the emissions the walk actually ships, so a regression or a new
terminal's divergence is one run away from visible.

Page 1 (pairs, blue background): each ACTUAL row must line up with the ASCII
`expect` row above it — `ab` starts where the claim ends, `X` (an absolute
CHA to column 60) sits under the expect row's X — with no non-blue cell
inside the payload span, and the glyph looking as the `note` says.

Page 2 (row edges): each emission ends a full-width blue row at the last
column. Any non-blue cell (especially at the right edge) or a wrap is a fail;
wrap detection is DSR-automatic.

The DSR half needs no eyes at all: every row's cursor arithmetic is recorded
to PROBE_OUT (JSON), and any `net != claim`, `ab_end != claim + 2`,
`cha != 60`, or `wrapped` is a failure regardless of pixels.

The emissions here mirror `String.withTerminalAppCursorCompensation()` under
Apple Terminal's width traits, and the Swift side pins the same literals in
`TerminalWidthTraitsTests` — if the walk changes, change both or the card
lies.

Usage (in the terminal under test):
    PROBE_OUT=/tmp/treatment.json python3 treatment_card.py
Keys: space = page 2, b = back, q = quit.
"""
import json
import os
import termios
import tty

E = "\x1b"
ZWNJ = "‌"
BLUE = f"{E}[44;97m"
OFF = f"{E}[0m"
LABEL = 20
XCOL = 60
WIDTH = 100

def cub(n): return f"{E}[{n}D"
def cuf(n): return f"{E}[{n}C"
def ech(n): return f"{E}[{n}X"
def dch(n): return f"{E}[{n}P"

SURGERY = cub(1) + dch(1) + cuf(1)
TAG_SCOTLAND = "\U0001F3F4\U000E0067\U000E0062\U000E0073\U000E0063\U000E0074\U000E007F"

# label, claim, emission, what page 1 should show
TESTS = [
    ("ascii control", 3, "xyz", "plain text"),
    ("plain wide emoji", 2, "\U0001F600", "composed, both cells blue"),
    ("tone separated", 5, "\U0001F919" + ZWNJ + "\U0001F3FD",
     "call-me hand, one blank cell, tone swatch"),
    ("tone sep BMP base", 5, "✊" + ZWNJ + "\U0001F3FF",
     "fist, one blank cell, tone swatch"),
    ("tone sep promoted", 5,
     ech(5) + "☝\uFE0F" + ZWNJ + "\U0001F3FB" + cuf(1),
     "emoji point-up and swatch ADJACENT, one trailing blank"),
    ("zwj family", 8, "\U0001F468\U0001F469\U0001F467\U0001F466",
     "four separate people"),
    ("zwj heartfire", 4, ech(2) + "❤️" + cuf(1) + "\U0001F525",
     "heart then fire, separate"),
    ("zwj astronaut", 7,
     "\U0001F469" + ZWNJ + "\U0001F3FD\U0001F680",
     "woman, blank, swatch, rocket"),
    ("flag surgery", 2, "\U0001F1FA\U0001F1F8" + SURGERY, "composed US flag"),
    ("keycap surgery", 2, "1️⃣" + SURGERY, "composed keycap 1"),
    ("tag flag pullback", 2, TAG_SCOTLAND + cub(6),
     "black flag (composition lost on this host)"),
    ("vs16 ech", 2, ech(2) + "\U0001F5A5️" + cuf(1), "computer emoji"),
    ("lone RI ech", 2, ech(2) + "\U0001F1E6" + cuf(1), "boxed letter A"),
]

fd = os.open("/dev/tty", os.O_RDWR)
saved = termios.tcgetattr(fd)
tty.setraw(fd)


def write(text):
    os.write(fd, text.encode())


def report():
    os.write(fd, b"\x1b[6n")
    buffer = b""
    while not buffer.endswith(b"R"):
        buffer += os.read(fd, 1)
    row, column = buffer.split(b"[")[1][:-1].split(b";")
    return int(row), int(column)


out = {"pairs": [], "edges": []}


def dump():
    if "PROBE_OUT" in os.environ:
        with open(os.environ["PROBE_OUT"], "w") as f:
            json.dump(out, f, indent=1)


def page1():
    write(f"{E}[?1049h{OFF}{E}[2J{E}[H")
    write("Treatment card p1 - per pair: ab under ab? X under X? non-blue cells? glyph?\r\n")
    write("space = edge page, q = quit\r\n")
    row = 4
    done = len(out["pairs"]) > 0
    for label, claim, emission, note in TESTS:
        write(f"{E}[{row};1H{E}[K{'expect':>{LABEL}}|")
        write(f"{E}[{row};{LABEL + 2}H{BLUE}{' ' * claim}ab{OFF}")
        write(f"{E}[{row};{XCOL}HX  {note}")
        write(f"{E}[{row + 1};1H{E}[K{label:>{LABEL}}|")
        _, start = report()
        write(BLUE + emission + "ab" + OFF)
        _, after = report()
        write(f"{E}[{XCOL}G")
        _, landed = report()
        write("X")
        if not done:
            out["pairs"].append({
                "row": label, "claim": claim,
                "net": after - start - 2, "ab_end": after - start,
                "cha": landed,
                "ok": after - start == claim + 2 and landed == XCOL,
            })
        row += 3


def page2():
    write(f"{E}[?1049h{OFF}{E}[2J{E}[H")
    write("Treatment card p2 - every row ends blue at the last column.\r\n")
    write("Any non-blue cell (especially the right edge) is a fail.  b = back, q = quit\r\n")
    row = 4
    done = len(out["edges"]) > 0
    for label, claim, emission, _ in TESTS:
        write(f"{E}[{row};1H{E}[K")
        write(BLUE + f"{label:>{LABEL}}|" + " " * (WIDTH - claim - LABEL - 1))
        row_before, _ = report()
        write(emission + OFF)
        row_after, column_after = report()
        if not done:
            out["edges"].append({
                "row": label, "claim": claim,
                "wrapped": row_after != row_before,
                "final_col": column_after,
                "ok": row_after == row_before and column_after == WIDTH,
            })
        row += 2


try:
    write(f"{E}[8;44;{WIDTH}t{E}[?25l")
    # The CSI 8 resize is a request, not a guarantee (Ghostty ignores it, a
    # tmux pane cannot honour it). Measure the width that actually took and
    # follow it — the full-width edge rows and the DSR wrap detection are
    # meaningless against an assumed width.
    write(f"{E}[999G")
    os.write(fd, b"\x1b[6n")
    reply = b""
    while not reply.endswith(b"R"):
        reply += os.read(fd, 1)
    actual = int(reply[reply.rfind(b"\x1b[") + 2:-1].split(b";")[1])
    if actual != WIDTH:
        WIDTH = actual
        XCOL = min(XCOL, WIDTH - 30)
    page = 1
    page1()
    dump()
    while True:
        key = os.read(fd, 1)
        if key in (b"q", b"\x03"):
            break
        if key == b" " and page == 1:
            page = 2
            page2()
            dump()
        elif key == b"b" and page == 2:
            page = 1
            page1()
    write(f"{E}[?25h{E}[?1049l")
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    os.close(fd)
