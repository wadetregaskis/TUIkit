#!/usr/bin/env python3
"""Prints a PICTURE built out of right-to-left characters, four ways.

`bidi_card.py` measures what a terminal does to a LINE OF TEXT containing an
RTL run. This one measures what it does to a picture — a `TUIkitImage` render
whose ramp contains Hebrew letters, which is where the corruption was reported
and where the stakes are different: in text, reordering a run is arguably the
right thing and merely looks odd; in a picture every character is a pixel, and
moving one is corruption with no upside at all.

The picture is a STAIRCASE, so nobody has to read Hebrew to judge it. Each row
is a run of ink followed by a run of blank, one cell longer per row, and every
row ends with `|X`. Correct output is a clean diagonal with every X in one
column. A terminal that reorders shows it two ways at once: the ink run and
the blank run swap (the diagonal flips to the other side of the row) and, if
the controls are painted rather than obeyed, the X column shears.

The four renderings:

  * `ascii`    — the same staircase drawn with `#`, as the control. Whatever
                 this row does is what "correct" looks like on this host.
  * `plain`    — Hebrew ink, exactly as TUIkit emits it today.
  * `lrm`      — Hebrew ink with U+200E LEFT-TO-RIGHT MARK after each RTL
                 cell (not after the blanks — a mark is only needed to END a
                 run). The standard way to do that without overriding
                 anything: each letter becomes a run of one, and a run of one
                 cannot be reordered. If this block draws the same staircase as
                 `ascii` AND keeps its X in the same column, interleaving the
                 mark is the fix, and it costs three bytes per ink cell.
  * `isolate`  — each RTL cell wrapped in U+2068 FIRST STRONG ISOLATE …
                 U+2069 POP DIRECTIONAL ISOLATE. Same idea, stronger
                 statement, six bytes a cell. Worth measuring separately
                 because Apple Terminal paints U+202D/U+202C as the
                 missing-glyph box (measured 2026-09-01) and may well do the
                 same to these.
  * `positioned` — no added characters at all: every cell written after an
                 explicit `ESC[<n>G` column move, which is what
                 `FrameDiffWriter` already does for a partial row. This asks
                 whether the host reorders what it is HANDED or what it has
                 STORED. If a host reorders per write, this block is correct
                 and costs nothing but bytes; if it reorders the stored line,
                 this block is as corrupt as `plain` and that route is closed.

Read the four blocks against each other and record what you saw in
`Documentation/Terminal-compatibility.md`, under "Right-to-left text".

Run INSIDE the terminal under test.
"""
import sys

LRM = "‎"
FSI, PDI = "⁨", "⁩"

# One Hebrew letter as the "ink" and a space as the "paper" — the two levels a
# two-glyph ramp has. Reordering swaps them within a row, which is the whole
# point of using a staircase rather than a photograph.
INK = "א"  # HEBREW LETTER ALEF
WIDTH = 12
ROWS = 6


def staircase(ink: str, decorate=lambda cell, is_ink: cell) -> list:
    """`ROWS` rows of `WIDTH` cells: n cells of ink, then blank."""
    out = []
    for row in range(ROWS):
        filled = (row + 1) * WIDTH // ROWS
        cells = [(ink, True)] * filled + [(" ", False)] * (WIDTH - filled)
        out.append("".join(decorate(c, is_ink) for c, is_ink in cells))
    return out


def positioned_rows(ink: str, column: int) -> list:
    """The same staircase, each cell written after an absolute column move.

    `column` is where the first cell lands — the `|` is printed first, so the
    cells start one further right. Costs one CHA per cell and adds no
    characters to the line, which is the point.
    """
    out = []
    for row in range(ROWS):
        filled = (row + 1) * WIDTH // ROWS
        parts = []
        for index in range(WIDTH):
            parts.append(f"\x1b[{column + index}G" + (ink if index < filled else " "))
        out.append("".join(parts))
    return out


def block(title: str, lines: list, note: str) -> None:
    print(f"  {title}")
    for line in lines:
        print(f"    |{line}|X")
    print(f"      {note}")
    print()


def main() -> int:
    print()
    print("RTL characters as image pixels — is the picture reordered?")
    print("Every row should be  |<ink…><blank…>|X  with X in one column.")
    print()
    block(
        "ascii   — the control: this is what correct looks like here",
        staircase("#"),
        "the diagonal grows to the RIGHT, X aligned",
    )
    block(
        "plain   — Hebrew ink, as TUIkit emits it today",
        staircase(INK),
        "same shape as ascii? or has the ink jumped to the right-hand end?",
    )
    block(
        "lrm     — U+200E after each ink cell",
        staircase(INK, lambda c, is_ink: c + LRM if is_ink else c),
        "same shape as ascii AND X still aligned = the fix",
    )
    block(
        "isolate — U+2068 … U+2069 around each ink cell",
        staircase(INK, lambda c, is_ink: FSI + c + PDI if is_ink else c),
        "boxes or a shifted X = this host paints the controls",
    )
    # The cells start in column 6: four spaces of indent, then the `|`.
    block(
        "positioned — each cell written after an ESC[nG column move",
        positioned_rows(INK, column=6),
        "correct here = the host reorders what it is handed, not what it stored",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
