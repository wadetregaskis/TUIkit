#!/usr/bin/env python3
"""Prints a static alignment card for RIGHT-TO-LEFT text.

TUIkit lays cells out in logical order and assumes the terminal paints them
that way. A terminal that implements the Unicode bidirectional algorithm does
not: a Hebrew or Arabic letter reorders the run around it, so what TUIkit
thinks is in column 7 is painted somewhere else and every column after it
shears. Nothing in `Documentation/Terminal-compatibility.md` records which
hosts do this, because it has never been measured.

This card measures it. Every row is  |<sample>|X  and there are two answers
in it, one mechanical and one that needs a pair of eyes:

  * The X column tests ADVANCE. A row whose X moves is being painted at a
    different width than TUIkit counted, and every column after it shears.
  * The `digits_after_rtl` row tests ORDER, which the X cannot: each row here
    begins with ASCII, so the paragraph is left-to-right and a terminal
    applying the bidirectional algorithm reverses an RTL run *inside the
    columns it already occupies*, moving nothing. In that row the algorithm
    also drags the digits across, so it displays as `123 בא ab` — digits hard
    against the opening `|` instead of in the middle. Look for that.

  * `plain`     — the sample as TUIkit would emit it today.
  * `forced`    — the same sample with each RTL run wrapped in
                  U+202D LEFT-TO-RIGHT OVERRIDE … U+202C POP DIRECTIONAL
                  FORMATTING, which is the standard way to ask for logical
                  order. If `plain` shears and `forced` does not, the wrap is
                  the fix. If `forced` shows visible boxes or shifts the X
                  column itself, this terminal prints the controls instead of
                  obeying them and the wrap would be a regression there.

Run INSIDE the terminal under test and look at the X column, then record what
you saw in Documentation/Terminal-compatibility.md.
"""
import sys

LRO, PDF = "‭", "‬"

# Each sample is nine cells wide by TUIkit's count, so every X should land in
# the same column whatever the row.
SAMPLES = [
    ("ascii", "abcdefghi"),
    ("hebrew_alone", "אבגדהוזחט"),
    ("hebrew_in_ascii", "abcאבגdef"),
    ("hebrew_one", "abcdאdefg"),
    ("arabic_in_ascii", "abcابتdef"),
    ("digits_after_rtl", "אב 123 ab"),
]


def forced(text):
    """Every run of strong-RTL scalars wrapped in LRO … PDF."""
    def is_rtl(ch):
        cp = ord(ch)
        return (0x0590 <= cp <= 0x05FF or 0x0600 <= cp <= 0x06FF
                or 0x0700 <= cp <= 0x074F or 0x0780 <= cp <= 0x07BF
                or 0x08A0 <= cp <= 0x08FF or 0xFB1D <= cp <= 0xFDFF
                or 0xFE70 <= cp <= 0xFEFF)
    out, run = "", ""
    for ch in text:
        if is_rtl(ch):
            run += ch
        else:
            if run:
                out += LRO + run + PDF
                run = ""
            out += ch
    return out + (LRO + run + PDF if run else "")


def main():
    print("Every X should be in the same column. Ruler:")
    print("        |123456789|X")
    for name, sample in SAMPLES:
        print("%-16s|%s|X   (plain)" % (name, sample))
    print()
    for name, sample in SAMPLES:
        print("%-16s|%s|X   (forced)" % (name, forced(sample)))
    print()
    print("A row whose X moves is painted at a width TUIkit did not count.")
    print("REORDERING is the other question, and the X cannot answer it:")
    print("look at digits_after_rtl. Logical order puts 123 in the middle;")
    print("a terminal that reorders puts it first, against the opening |.")
    print("If the 'forced' rows line up, this host obeys LRO/PDF; if they")
    print("show boxes or blanks, it prints the controls and the wrap would")
    print("be a regression here (Apple Terminal does, measured 2026-09-01).")


main()
