#!/usr/bin/env python3
"""Prints a card for whether this terminal lets SGR 1 change a COLOUR.

Bold is not only a weight. xterm and most of its descendants implement "bold
means bright": with SGR 1 in force, a foreground named as one of the standard
eight (SGR 30-37) is painted in its BRIGHT twin instead. Terminals disagree,
and each spells the choice differently — iTerm2's "Use Bright Bold" (on by
default), Warp's own bold handling, Ghostty's weight-only bold, Terminal.app's
"Use bright colors for bold text" — so a sequence that is a pure weight change
on one host is a colour change on the next.

That mattered to TUIkit because `ASCIIConverter+HalfBlocks` used to embolden
every `▄` of a 16-colour image, to close a rasterisation gap under SF Mono in
Terminal.app. In true colour the foreground is an explicit RGB triple and bold
cannot touch it. In ``ASCIIColorMode/ansi16`` it is SGR 30-37, so on a host
that brightens bold EVERY cell's lower half came out as the bright twin of the
colour asked for while its upper half (the background, which bold never
touches) stayed correct — horizontal stripes at cell pitch across the whole
picture. Measured on the Example's demo photograph: 5724 cells, all bold.

One question, answered by eye: each row shows one colour drawn three ways —
PLAIN, BOLD, and the explicit BRIGHT twin. If the middle swatch matches the
right one rather than the left, this host brightens bold. The second block
then shows what that does to an image cell, which is the defect itself at two
lines instead of five thousand.

`palette_probe.py` is the companion for the other half of a 16-colour image:
which colours this host actually has.

Run INSIDE the terminal under test and record what you saw in
Documentation/Terminal-compatibility.md.
"""

CSI = "\x1b["
RESET = CSI + "0m"
BAR = "█" * 12          # FULL BLOCK, so the swatch is pure colour
HALF = "▄" * 24    # LOWER HALF BLOCK — every cell of a 16-colour image

NAMES = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

def bold_row(index):
    """One colour: plain, bold, and its bright twin, with a gap between."""
    plain = f"{CSI}{30 + index}m{BAR}{RESET}"
    bold = f"{CSI}1m{CSI}{30 + index}m{BAR}{RESET}"
    bright = f"{CSI}{90 + index}m{BAR}{RESET}"
    return f"  {NAMES[index]:8s} {plain}  {bold}  {bright}"


def card():
    print("1. Does SGR 1 change a COLOUR here, or only a weight?\n")
    print("           %-12s  %-12s  %s" % ("plain", "BOLD", "bright twin"))
    for index in range(8):
        print(bold_row(index))
    print()
    print("  Middle matches RIGHT  -> this host brightens bold.")
    print("  Middle matches LEFT   -> bold is a weight here, nothing more.")
    print()
    print("2. The defect it made, drawn twice: a 16-colour image cell is")
    print("   U+2584 with foreground == background, so it must be FLAT.")
    print()
    print("   plain " + f"{CSI}30m{CSI}40m{HALF}{RESET}" + "  <- correct: one dark bar")
    print("   bold  " + f"{CSI}1m{CSI}30m{CSI}40m{HALF}{RESET}"
          + "  <- striped wherever bold brightens")
    print()


def main():
    card()
    print("The other half of a 16-colour image is WHICH colours this host has:")
    print("`palette_probe.py` asks it over OSC 4 and writes the answer as JSON.")
    print("A host whose slot 0 is not #000000 draws a near-black photograph")
    print("lighter than it is, and nothing TUIkit chooses can change that —")
    print("16-colour means THIS HOST'S sixteen.")


main()
