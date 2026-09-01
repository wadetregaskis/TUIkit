#!/usr/bin/env python3
"""Prints a static alignment card for RIGHT-TO-LEFT text.

TUIkit lays cells out in logical order and assumes the terminal paints them
that way. A terminal that implements the Unicode bidirectional algorithm does
not: a Hebrew or Arabic letter reorders the run around it, so what TUIkit
thinks is in column 7 is painted somewhere else and every column after it
shears. Nothing in `Documentation/Terminal-compatibility.md` records which
hosts do this, because it has never been measured.

This card measures it. Every row is  |<sample>|X  and the X column is the
answer: rows whose X lines up are painted in logical order, rows whose X
moves are not.

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
    print("Rows whose X moves are reordered by this terminal.")
    print("If the 'forced' rows all line up, LRO/PDF is the fix here.")
    print("If they show boxes or blanks, this terminal prints the controls.")


main()
