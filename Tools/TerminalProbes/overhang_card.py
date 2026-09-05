#!/usr/bin/env python3
"""Prints a card for chrome glyphs whose INK spills out of their cell.

`advance_probe.py` settled the cursor question for the framework's own chrome
on 2026-09-04: all 29 rows (`chrome_key`, `chrome_glyph`) advance exactly one
cell on Ghostty, iTerm2, Apple Terminal and Warp. The claim is right and no row
shifts. What it could not settle is the PAINT — `↵` (U+21B5) was reported in
Ghostty to swallow the space the status bar puts between a shortcut and its
label, so `↵ activate` reads as `↵activate`. A cursor report cannot see that,
because nothing moved: the grid is intact and only the ink is over the line.

`landing_probe.py` is the machine version of this question and it needs
screenshots, which need a Screen Recording grant this project does not have. So
this card hands the reading to a pair of eyes, and makes it a reading that does
not need judgement.

## The measurement

Each glyph is drawn in ONE cell of the terminal's own background, flanked left
and right by two cells of solid magenta:

    ██<glyph>██

A glyph that stays inside its cell leaves both flanks flat. A glyph that
overhangs puts ink ON a flank — dark marks on magenta, at the very edge — and
which flank says which way it spills. That is the whole test; the flanks are
background-only, so anything non-magenta inside one came from the glyph.

The calibration rows come first and they are not optional: `█` FULL BLOCK must
meet both flanks with no seam and no bleed, and `a` must sit clear of both. If
those two do not read as described, this terminal is compositing the card in
some way that invalidates every row under them (a translucent window, a
background image, a font substituted at a different size) and nothing below can
be trusted.

The second block asks the same question the report was about, in the shape the
report was about: the status bar's `<glyph> <label>` beside `<glyph>  <label>`,
which is what a two-cell claim would produce. It settles whether the remedy
reads correctly, which the flanks cannot.

## What to do with the answer

**Overhang is a FONT property at least as much as a host one**, so record the
font and its size next to the host and version — a reading with no font named
is not reproducible. Put the reading in
`Documentation/Terminal-compatibility.md`, and add one row per overhanging
codepoint to `chromeOverhangCodepoints` in
`Sources/TUIkitCore/Extensions/ChromeOverhang.swift`, which widens the claim to
two cells and lets the existing ECH+CUF walk keep the grid where it is.

Box Drawing and Block Elements (`─ │ █ ▌ ▐ ▒`) are shown here too, and they are
the one group that must NOT be added to that table: a two-cell border is not a
fix but a second defect. If one of those overhangs, the answer is a different
glyph. See the file's own notes.

Run INSIDE the terminal under test and record what you saw in
Documentation/Terminal-compatibility.md.
"""
import os
import sys

from landing_probe import load_corpus  # the corpus loader, not a second copy

CSI = "\x1b["
RESET = CSI + "0m"

# 256-palette rather than truecolor, for the reason `landing_probe.py` gives:
# Apple Terminal has no 24-bit colour, and a flank it renders approximately is
# a flank whose edge cannot be read. 201 is a pure corner of the 6x6x6 cube.
FLANK = CSI + "48;5;201m" + "  " + RESET
CHROME_CLASSES = ("chrome_key", "chrome_glyph")

# Not part of the corpus: the rows that say whether this card is legible at all
# on this host. `pad` is EXTRA cells after the cluster, and it is 0 everywhere:
# a glyph is given exactly the cells it claims, so the flanks sit against it.
# The CJK control is the reason this is not a "cells" count — 漢 claims two on
# its own, and padding it to two put a stray third cell inside the slot and made
# the one row whose job is to be trusted the one row drawn differently.
CALIBRATION = [
    ("full block", "█", 0, "must MEET both flanks — no seam, no gap"),
    ("ascii a", "a", 0, "must sit clear of both flanks"),
    ("cjk", "漢", 0, "claims two cells — flanks stay flat against them"),
]

# The glyphs the report is about, in the shape the report is about.
SPACING_SAMPLE = "activate"


def slot(cluster, pad):
    """`cluster` plus `pad` blank cells of default background, between flanks."""
    return FLANK + cluster + " " * pad + FLANK


def flank_rows(rows):
    for index, (name, cluster, pad, note) in enumerate(rows, start=1):
        codepoints = " ".join("U+%04X" % ord(character) for character in cluster)
        print(("  %2d  %s  %-22s %-8s %s"
               % (index, slot(cluster, pad), name, codepoints, note)).rstrip())


def spacing_rows(rows):
    for name, cluster, _, _ in rows:
        print("      %-22s  %-20s   %s"
              % (name, cluster + " " + SPACING_SAMPLE, cluster + "  " + SPACING_SAMPLE))


def main():
    clusters = [entry for entry in load_corpus() if entry["class"] in CHROME_CLASSES]
    if len(clusters) != 29:
        print("WARNING: %d chrome rows in the corpus, expected 29" % len(clusters),
              file=sys.stderr)

    keys = [(e["id"], e["text"], 0, "") for e in clusters if e["class"] == "chrome_key"]
    glyphs = [(e["id"], e["text"], 0, "") for e in clusters if e["class"] == "chrome_glyph"]

    print()
    print("CHROME OVERHANG CARD — does a glyph's ink stay inside its cell?")
    print("Each glyph sits in ONE cell between two magenta flanks. Ink ON a")
    print("flank means the glyph overhangs, and which flank says which way.")
    print()
    print("0. CALIBRATION — if these do not read as described, stop here.")
    flank_rows(CALIBRATION)
    print()
    print("1. KEYBOARD SYMBOLS (chrome_key) — the status bar draws these.")
    flank_rows(keys)
    print()
    print("2. DRAWING GLYPHS (chrome_glyph) — borders, tracks, radios, arrows.")
    print("   The last six are Box Drawing and Block Elements: if one of THOSE")
    print("   overhangs the remedy is a different glyph, never a wider claim.")
    flank_rows(glyphs)
    print()
    print("3. THE REPORTED SHAPE — one space between glyph and label, then two.")
    print("   Two spaces is what a two-cell claim produces. Which reads right?")
    print()
    print("      %-22s  %-20s   %s" % ("", "one space", "two spaces"))
    spacing_rows(keys)
    print()
    print("READING IT")
    print("  * both flanks flat            -> the glyph fits; nothing to do.")
    print("  * ink on the RIGHT flank      -> it overhangs right, which is the")
    print("                                   reported `↵ activate` defect.")
    print("  * ink on the LEFT flank       -> it overhangs left; the claim")
    print("                                   cannot fix that, so record it and")
    print("                                   treat it as a glyph choice.")
    print("  * a flank looks NARROWER      -> the glyph is being drawn over it,")
    print("                                   which is the same answer as ink.")
    print()
    print("RECORDING IT")
    print("  Host + version, FONT + SIZE (overhang is a font property at least")
    print("  as much as a host one, and a reading with no font named is not")
    print("  reproducible), then one line per overhanging row:")
    print()
    print("      <id>  <U+XXXX>  left | right | none")
    print()
    print("  Into Documentation/Terminal-compatibility.md, and one entry per")
    print("  right-overhanging codepoint into `chromeOverhangCodepoints` in")
    print("  Sources/TUIkitCore/Extensions/ChromeOverhang.swift — never from a")
    print("  report, only from this card.")
    print()
    print("  This terminal says: TERM=%s TERM_PROGRAM=%s %s"
          % (os.environ.get("TERM", "?"),
             os.environ.get("TERM_PROGRAM", "?"),
             os.environ.get("TERM_PROGRAM_VERSION", "")))
    print("  (`probe_stamp.py` is the full provenance; that is what a recorded")
    print("   measurement carries, and this line is only a reminder.)")
    print()


main()
