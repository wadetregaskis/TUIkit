#!/usr/bin/env python3
"""Prints a card for how this terminal paints TUIkit's reversing row breaths.

On a 16-colour terminal a palette sometimes has too few slots to keep the
selected row, the cursor row and the selected cursor row apart, and one end of
a cursor row's breath is then reverse video: the whole row the text's colour,
everything on it in the page's. Without colour at all, a cursor row is reversed
on every frame and breathes by its weight, bold on the bright frames. The frames
are checked byte for byte by the test suite; what a host PAINTS for them is what
this card asks (Terminal-compatibility.md, "Reverse video (SGR 7)").

The rows are the bytes TUIkit emits (captured 2026-09-30 from the framework:
Red Sands on xterm's sixteen, and the default palette without colour), so this
card needs nothing built. Each breath shows its two frames, then the references.

**Read, for each 16-colour breath:** frame 0 and frame 8 are both legible; the
reversed frame is ONE colour across the whole row with every glyph (the ●, the
secondary text) in one other — no cell keeps its own colour; the two frames
differ plainly.

**Read, without colour:** the bold+reversed frame and the reversed frame are
told apart at a glance (a heavier or brighter glyph — either is fine), and both
say "this row" against the plain row beside them.

    python3 Tools/TerminalProbes/breath_card.py            # the card
    python3 Tools/TerminalProbes/breath_card.py --animate  # each breath at its cadence, 10 s
    python3 Tools/TerminalProbes/breath_card.py --host ghostty   # Ghostty's own sixteen

**Which sixteen.** The 16-colour rows are placed against xterm's sixteen, which
is what a terminal that does not report its own is assumed to paint. A host that
reports them (OSC 4) gets fills placed against ITS table, and replaying xterm's
picks there says nothing about what TUIkit draws: on a default-config Ghostty
(Tomorrow Night) xterm's blue fill is a pale steel blue and the text on it all
but vanishes. `--host ghostty` shows the frames for Ghostty's default table
instead — rule.py's picks for Red Sands there (`rule_16`), spelled as the
framework spells the xterm rows above; derived, not captured.
"""
import sys
import time

E = "\033["
FRAMES = {
    "16 colours · selected cursor row (B)": (
        f"{E}44m{E}33m●{E}0m{E}44m{E}37mrow 0{E}0m{E}44m {E}90mdim{E}0m{E}44m                  {E}0m",
        f"{E}7;37;41m●{E}0m{E}7;37;41mrow 0{E}0m{E}7;37;41m dim{E}0m{E}7;37;41m                  {E}0m",
    ),
    "16 colours · unselected cursor row (F)": (
        f"{E}7;37;41m row 0{E}0m{E}7;37;41m dim{E}0m{E}7;37;41m                  {E}0m",
        f"{E}44m {E}37mrow 0{E}0m{E}44m {E}90mdim{E}0m{E}44m                  {E}0m",
    ),
    "16 colours · menu bar (B)": (
        f"{E}44m{E}37mOpen{E}0m{E}44m {E}90m⌘O{E}0m{E}44m{E}0m",
        f"{E}7;37;41mOpen{E}0m{E}7;37;41m ⌘O{E}0m{E}7;37;41m{E}0m",
    ),
    "no colour · cursor row": (
        f"{E}1;7m row 0 dim                  {E}0m",
        f"{E}7m row 0 dim                  {E}0m",
    ),
    "no colour · menu bar": (
        f"{E}1;7mOpen ⌘O{E}0m",
        f"{E}7mOpen ⌘O{E}0m",
    ),
}
# Red Sands against a default-config Ghostty's sixteen (`ghostty +show-config
# --default`, 1.3.1): rule_16 picks page = bright red (101), text = white (37),
# secondary = green (32), ● = bright yellow (93); F = (bright black, reverse),
# B = (reverse, black) — blue is not used at all. Frame 0 is each breath's top.
GHOSTTY_FRAMES = {
    "16 colours on Ghostty · selected cursor row (B)": (
        f"{E}40m{E}93m●{E}0m{E}40m{E}37mrow 0{E}0m{E}40m {E}32mdim{E}0m{E}40m                  {E}0m",
        f"{E}7;37;101m●{E}0m{E}7;37;101mrow 0{E}0m{E}7;37;101m dim{E}0m{E}7;37;101m                  {E}0m",
    ),
    "16 colours on Ghostty · unselected cursor row (F)": (
        f"{E}7;37;101m row 0{E}0m{E}7;37;101m dim{E}0m{E}7;37;101m                  {E}0m",
        f"{E}100m {E}37mrow 0{E}0m{E}100m {E}32mdim{E}0m{E}100m                  {E}0m",
    ),
    "16 colours on Ghostty · menu bar (B)": (
        f"{E}40m{E}37mOpen{E}0m{E}40m {E}32m⌘O{E}0m{E}40m{E}0m",
        f"{E}7;37;101mOpen{E}0m{E}7;37;101m ⌘O{E}0m{E}7;37;101m{E}0m",
    ),
}
HOSTS = {"ghostty": GHOSTTY_FRAMES}

# Which frames of the 16 show frame 0's end (the bright end): SelectionEmphasis's
# equal-time two-step walk.
BRIGHT = {0, 1, 2, 3, 4, 12, 13, 14, 15}


def frames():
    """The card's rows: xterm's sixteen, or `--host NAME`'s, then the no-colour rows."""
    host = sys.argv[sys.argv.index("--host") + 1] if "--host" in sys.argv else None
    if host is None:
        return FRAMES
    rows = dict(HOSTS[host])
    rows.update((label, pair) for label, pair in FRAMES.items() if label.startswith("no colour"))
    return rows


def card():
    print(f"{E}2J{E}H", end="")
    print("TUIkit reversing breath card\n")
    for label, (bright, dim) in frames().items():
        print(label)
        print(f"  frame 0:  {bright}")
        print(f"  frame 8:  {dim}")
        print(f"  plain:     row 1 dim\n")
    print("References: plain, reverse video alone, bold alone, bold + reverse")
    print(f"  plain  {E}7m reversed {E}0m  {E}1m bold {E}0m  {E}1;7m bold reversed {E}0m")


def animate(seconds=10.0, frame_seconds=0.05):
    print(f"{E}2J{E}H", end="")
    print("TUIkit reversing breath card — animated\n")
    rows = frames()
    labels = list(rows)
    end = time.time() + seconds
    frame = 0
    while time.time() < end:
        print(f"{E}3;1H", end="")
        for label in labels:
            bright, dim = rows[label]
            print(f"{E}2K{label}\n{E}2K  {bright if frame % 16 in BRIGHT else dim}\n")
        sys.stdout.flush()
        time.sleep(frame_seconds)
        frame += 1


if __name__ == "__main__":
    animate() if "--animate" in sys.argv else card()
