#!/usr/bin/env python3
"""Which kitty transmissions does this terminal actually DRAW?

`placement_probe.py` established that a terminal can answer `OK` to every
graphics command and composite nothing: iTerm2 3.6.11 acknowledges the
protocol query, the transmit and the virtual placement, returns a real
`ENOENT` for a placement after a delete — so it is genuinely tracking images
— and draws an empty rectangle. Ghostty, given byte-identical commands, draws
the picture.

So `OK` is not the question. This probe asks the question `OK` does not
answer, and separates the two candidates that differ between the exchange
iTerm2 acknowledges and the ones it ignores:

  * **Pixel format.** The startup handshake transmits ONE RGBA pixel — `f=32`.
    Every real picture TUIkit sends for an opaque photograph is `f=24`, three
    bytes a pixel, which is a quarter less on the wire. `placement_probe.py`'s
    own card is `f=24` too, so its blank result and the app's are the same
    case, and neither has ever tested `f=32` at a size worth drawing.
  * **Chunking.** The handshake's one pixel fits in a single escape and
    carries no `m` key at all — the protocol reads its absence as "not
    chunked", which is a different statement from `m=0`, "the last chunk of
    one". Every real picture is split at 4096 base64 bytes with `m=1` … `m=0`.

Those two travel together in everything measured so far, which is why neither
has been ruled out. This draws the 2x2:

    A  1 cell   f=24  single escape, no `m`
    B  1 cell   f=32  single escape, no `m`
    C  12x4     f=24  chunked, m=1 … m=0
    D  12x4     f=32  chunked, m=1 … m=0

Read off which letters appear and the cause is pinned to a row, a column, or
a single cell of that table — which is what a bug report against a terminal
needs, rather than "images do not work".

Run INSIDE the terminal under test. Prints a card; there is nothing to parse
and no reply to read, because the question is what a human can see.
"""
import fcntl
import os
import struct
import sys
import termios

# ── Geometry ────────────────────────────────────────────────────────────────

PLACEHOLDER = "\U0010EEEE"
# Row/column travel in these combining marks; only the first few are needed
# here, and they are the same table `KittyGraphics+Placeholders.swift` uses.
DIACRITICS = [
    "̅", "̍", "̎", "̐", "̒", "̽", "̾", "̿",
    "͆", "͊", "͋", "͌",
]


def cell_pixels():
    """The terminal's cell size in pixels, or a plausible default."""
    try:
        packed = fcntl.ioctl(sys.stdout, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
        rows, cols, width, height = struct.unpack("HHHH", packed)
        if width and height and rows and cols:
            return max(1, width // cols), max(1, height // rows)
    except OSError:
        pass
    return 8, 16


def ramp(width, height, opaque):
    """A left-to-right hue ramp, so a transposed or torn placement is visible
    and not just 'something appeared'."""
    out = bytearray()
    for y in range(height):
        fade = 1.0 - (y / max(1, height - 1)) * 0.6
        for x in range(width):
            hue = (x / max(1, width - 1)) * 6.0
            sector, frac = int(hue) % 6, hue - int(hue)
            rising, falling = int(255 * frac * fade), int(255 * (1 - frac) * fade)
            full, none = int(255 * fade), 0
            red, green, blue = [
                (full, rising, none), (falling, full, none), (none, full, rising),
                (none, falling, full), (rising, none, full), (full, none, falling),
            ][sector]
            out += bytes((red, green, blue)) if opaque else bytes((red, green, blue, 255))
    return bytes(out)


# ── The protocol ────────────────────────────────────────────────────────────

import base64  # noqa: E402  (after the geometry helpers, for readability)

CHUNK = 4096


def transmit(payload, width, height, image_id, opaque, force_chunked=False):
    """`a=t` for one image. Emits a single escape with NO `m` key when the
    payload fits, which is the shape the handshake uses and the shape nothing
    has tested at a drawable size."""
    encoded = base64.b64encode(payload).decode("ascii")
    fmt = 24 if opaque else 32
    head = f"a=t,q=2,f={fmt},t=d,s={width},v={height},i={image_id}"
    if len(encoded) <= CHUNK and not force_chunked:
        return f"\033_G{head};{encoded}\033\\"
    parts, out, first = [encoded[i:i + CHUNK] for i in range(0, len(encoded), CHUNK)], "", True
    for index, part in enumerate(parts):
        last = index == len(parts) - 1
        prefix = f"{head},m={0 if last else 1}" if first else f"m={0 if last else 1},q=2"
        out += f"\033_G{prefix};{part}\033\\"
        first = False
    return out


def place(image_id, columns, rows):
    return f"\033_Ga=p,U=1,q=2,i={image_id},c={columns},r={rows}\033\\"


def placeholder_rows(image_id, columns, rows):
    """The cells that draw the image: the id in a 24-bit foreground, then one
    placeholder per cell carrying its row and column."""
    red, green, blue = (image_id >> 16) & 0xFF, (image_id >> 8) & 0xFF, image_id & 0xFF
    lines = []
    for row in range(rows):
        cells = "".join(
            PLACEHOLDER + DIACRITICS[row] + DIACRITICS[column] for column in range(columns))
        lines.append(f"\033[38;2;{red};{green};{blue}m{cells}\033[0m")
    return lines


# ── The card ────────────────────────────────────────────────────────────────

def main():
    cell_width, cell_height = cell_pixels()
    print(f"cell pixels: {cell_width}x{cell_height}\n")

    cases = [
        ("A", 1, 1, True, "f=24  single escape, no m"),
        ("B", 1, 1, False, "f=32  single escape, no m"),
        ("C", 12, 4, True, "f=24  chunked, m=1 … m=0"),
        ("D", 12, 4, False, "f=32  chunked, m=1 … m=0"),
    ]

    out = []
    for index, (label, columns, rows, opaque, description) in enumerate(cases):
        image_id = 7000 + index
        width, height = columns * cell_width, rows * cell_height
        payload = ramp(width, height, opaque)
        encoded_len = (len(payload) + 2) // 3 * 4
        chunks = 1 if encoded_len <= CHUNK else (encoded_len + CHUNK - 1) // CHUNK
        sys.stdout.write(transmit(payload, width, height, image_id, opaque))
        sys.stdout.write(place(image_id, columns, rows))
        out.append((label, description, columns, rows, image_id, encoded_len, chunks))

    for label, description, columns, rows, image_id, encoded_len, chunks in out:
        print(f"  {label}: {description}   ({encoded_len} base64 bytes, {chunks} escape(s))")
        for line in placeholder_rows(image_id, columns, rows):
            print("     " + line)
        print()

    print("""  Each letter above should be followed by a hue ramp — red -> yellow ->
  green -> blue, fading downwards for C and D, a single coloured cell for
  A and B.

  Report which of A B C D drew a picture and which are blank. That splits
  the cause:

    A and B draw, C and D blank .... CHUNKING is the problem
    A and C blank, B and D draw .... the PIXEL FORMAT f=24 is the problem
    only B draws ................... both, independently
    all four blank ................. neither — something else entirely
    all four draw .................. this terminal is fine; the fault is
                                     in what TUIkit sends around them
""")


if __name__ == "__main__":
    main()
