#!/usr/bin/env python3
"""Prints a PICTURE built out of right-to-left characters, six ways.

`bidi_card.py` asks what a terminal does to a LINE OF TEXT containing an RTL
run. This asks what it does to a picture — a `TUIkitImage` render whose ramp
contains Hebrew letters, which is where the corruption was reported and where
the stakes differ: in text, reordering a run is arguably right and merely looks
odd; in a picture every character is a pixel, so moving one is corruption with
no upside at all.

**Why the first version of this card measured nothing.** It drew a staircase
out of ONE repeated letter and blanks. A run of identical characters looks
exactly the same reversed, and the blanks are neutrals which at end-of-line take
the paragraph's own direction and do not move — so a host doing precisely what
was suspected would have drawn that card correctly. A real image render never
looks like that: a ramp maps each luminance to a DIFFERENT glyph, so a row is a
run of distinct letters, and reversing those scrambles the picture.

So the picture here is a gradient with a FLAT END, and that is the reading.
Every row is a run of one repeated letter followed by the gradient:

    |אאאאאאאאאאאאבבבבגגגגדדדדההההווווזזזזח|X

Reversing an RTL run leaves each block of identical letters looking exactly as
it was and puts the BLOCKS in the opposite order — so the flat end moves from
the left of the row to the right. Compare each row against the ASCII control
above it: the flat run is on the LEFT there, and it must be on the left here.
Nobody needs to read a word of Hebrew to see which side it is on.

There is no column ruler, deliberately. Digits would move under the algorithm's
own rule for numbers after an RTL letter even on a host doing everything right,
so a ruler would report every compliant terminal as broken. What is wanted here
is narrower and harder: whether the PICTURE comes out mirrored.

The blocks:

  * `control`    — the same gradient drawn with an ASCII ramp. Whatever this
                   does is what correct looks like on this host.
  * `hebrew`     — the gradient with a ten-letter Hebrew ramp, as TUIkit emits
                   it today. Compare its shape with the control's.
  * `coloured`   — the same picture with an SGR colour change per cell, which
                   is what a real render emits and the one thing a plain text
                   card cannot ask about. If this differs from `hebrew`, the
                   host is not reordering the finished line but something
                   earlier.
  * `lrm`        — U+200E LEFT-TO-RIGHT MARK after each Hebrew cell, which ends
                   every RTL run at one character, and a run of one cannot be
                   reversed. If this block draws the picture the right way round
                   AND its `X` still lines up, interleaving the mark is the fix,
                   at three bytes per ink cell.
  * `positioned` — no added characters at all: every cell after an explicit
                   `ESC[<n>G` column move, which is what `FrameDiffWriter`
                   already does for a partial row. This asks whether the host
                   reorders what it is HANDED or what it has STORED, and those
                   have opposite consequences: the first is already TUIkit's
                   mechanism and costs no glyphs, the second closes that route.
  * `lrm+coloured` and `lrm+wide` — the two things the working `lrm` block
                   does NOT have, and the reason it is not trusted. Emitting
                   the mark from `ASCIIConverter` for every RTL glyph was
                   tried and reverted: in the Example's Image page it does not
                   merely fail to help, it destroys the page. The card's rows
                   are plain text about forty cells wide and stand alone; an
                   image row is FULL WIDTH and carries a colour change per
                   cell. These two blocks add one axis each, so a single
                   reading says which one costs the mark its freedom — or that
                   neither does, and the difference is the composed layout
                   around it.

U+202D … U+202C is not among them: Apple Terminal paints those two as the
missing-glyph box (measured 2026-09-01, in `Terminal-compatibility.md`).

Run INSIDE the terminal under test, and record what you saw in
`Documentation/Terminal-compatibility.md` under "Right-to-left text".
"""
import sys

LRM = "‎"

# Ten distinct letters, light → dense, the shape a `.customRamp` takes. Distinct
# is the whole point: identical glyphs hide a reversal.
HEBREW = "אבגדהוזחטי"
ASCII = " .:-=+*#%@"

WIDTH = 37
ROWS = 6
# Where the picture starts on screen: four spaces of indent, then the `|`.
FIRST_COLUMN = 6


def picture(ramp: str) -> list:
    """`ROWS` rows of `WIDTH` cells — a gradient brightening rightward, with a
    flat run of the first glyph growing along the left edge row by row.

    The flat run is the measurement: reversing the row moves it to the other
    end, and identical glyphs give a reversal nowhere to hide."""
    out = []
    steps = len(ramp) - 1
    for row in range(ROWS):
        flat = row * 5
        cells = [ramp[0]] * min(WIDTH, flat)
        remaining = WIDTH - len(cells)
        for column in range(remaining):
            cells.append(ramp[min(steps, (column * steps) // max(1, remaining - 1))])
        out.append(cells)
    return out


def block(title: str, rows: list, note: str) -> None:
    print(f"  {title}")
    for row in rows:
        print(f"    |{row}|X")
    print(f"      {note}")
    print()


def coloured(cells: list) -> str:
    """One 256-colour foreground change per cell, as an image render emits.

    Cycled through bright hues rather than the picture's own greys: what is
    being asked is whether an SGR between every pair of cells changes what the
    host does with them, and a ramp that fades into the background would hide
    the answer on half the hosts."""
    hues = [39, 45, 51, 82, 154, 190, 220, 208, 203, 199]
    out = []
    for index, cell in enumerate(cells):
        out.append(f"\x1b[38;5;{hues[index % len(hues)]}m{cell}")
    return "".join(out) + "\x1b[0m"


def wide_row(cells: list) -> list:
    """The row repeated out to the terminal's width, less the four-space indent.

    An image fills the space it is given, and the `lrm` block's forty-cell rows
    do not. Whether that matters is the point of asking.
    """
    try:
        import shutil

        width = max(20, shutil.get_terminal_size((80, 24)).columns - 4)
    except Exception:  # pragma: no cover - a pipe has no size
        width = 76
    return [cells[index % len(cells)] for index in range(width)]


def positioned(cells: list) -> str:
    """Every cell after an absolute column move, adding no characters."""
    return "".join(
        f"\x1b[{FIRST_COLUMN + index}G{cell}" for index, cell in enumerate(cells))


def main() -> int:
    hebrew = picture(HEBREW)
    print()
    print("RTL characters as image pixels — is the picture reordered?")
    print("Every row has a FLAT RUN of one repeated glyph at its LEFT, growing")
    print("row by row. Reversing a row moves that run to the RIGHT. Every X")
    print("should also land in one column.")
    print()
    block(
        "control    — an ASCII ramp: this is the picture, and it is correct here",
        ["".join(row) for row in picture(ASCII)],
        "the flat run of spaces is on the LEFT and grows row by row",
    )
    block(
        "hebrew     — the same picture, ten Hebrew letters as the ramp",
        ["".join(row) for row in hebrew],
        "flat run of one letter on the LEFT = correct; on the RIGHT = reversed",
    )
    block(
        "coloured   — the same, with a colour change per cell as a render emits",
        [coloured(row) for row in hebrew],
        "different from `hebrew`? then the finished line is not what is reordered",
    )
    block(
        "lrm        — the same, with U+200E after each cell",
        ["".join(cell + LRM for cell in row) for row in hebrew],
        "flat run back on the LEFT and X still aligned = the mark is the fix",
    )
    block(
        "positioned — the same, every cell after an ESC[nG column move",
        [positioned(row) for row in hebrew],
        "correct here = the host reorders what it is handed, not what it stored",
    )
    block(
        "lrm+coloured — marks AND a colour change per cell, which `lrm` lacks",
        [coloured([cell + LRM for cell in row]) for row in hebrew],
        "still correct? then colour is not what costs the mark its freedom",
    )
    block(
        "lrm+wide   — marks on a row run out to the terminal's right edge",
        ["".join(cell + LRM for cell in wide_row(row)) for row in hebrew],
        "no |X here: the row IS the width. Still a picture, or is the screen torn?",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
