#!/usr/bin/env python3
"""Which kitty transmissions does this terminal actually DRAW?

`placement_probe.py` established that a terminal can answer `OK` to every
graphics command and composite nothing: iTerm2 3.6.11 acknowledges the
protocol query, the transmit and the virtual placement, returns a real
`ENOENT` for a placement after a delete — so it is genuinely tracking images
— and draws an empty rectangle. Ghostty, given byte-identical commands, draws
the picture.

So `OK` is not the question. This probe asks the question `OK` does not
answer, and separates the candidates that differ between the exchange iTerm2
acknowledges and the ones it ignores.

  A  1 cell   f=24  single escape, no `m`   virtual placement
  B  1 cell   f=32  single escape, no `m`   virtual placement
  C  12x4     f=24  chunked, m=1 … m=0      virtual placement
  D  12x4     f=32  chunked, m=1 … m=0      virtual placement
  E  12x4     f=24  chunked                 **DIRECT placement, no U=1**
     (placed once, in situ, at its own spot in the card)

**E is the control, and it is the one that matters most.** A–D all draw
through Unicode placeholders, so if the terminal's placeholder support is
what is missing they all fail together and say nothing about the pixels. E
draws the same bytes at the cursor with no placeholders involved. If E draws
and A–D do not, the transmission is fine and the fault is *specifically*
Unicode placeholders — which is a precise, filable bug rather than "images do
not work".

Every command is `q=0` and its reply is read. That is deliberate and it is
the fix for this probe's first version, which sent `q=2` — quiet — and so
could not tell a refusal from an acceptance that drew nothing. A diagnostic
must never suppress the errors it exists to find. (Anything on a RENDER path
must still use `q=2`: those replies arrive on the application's stdin, where
the input parser reads them as typing.)

Everything runs in raw mode and every byte — text included — goes out through
one `os.write` on the terminal's own descriptor. Two reasons, both learned the
hard way. Mixing buffered `print` with `os.write` reorders the text against
the escapes, and for a probe whose entire result is WHERE a picture landed
that is not cosmetic. And a DIRECT placement draws the instant it is sent, so
its reply has to be collected at the spot the picture belongs: an earlier
version placed it during a probing phase, drew it in the top-left corner, and
tried to take it back with `a=d,d=i` — which cost the image, so E stopped
drawing in Ghostty and only flashed in iTerm2 before the clear. A probe should
not need to undo something it should not have done.

Run INSIDE the terminal under test. Prints a card and asks; there is no way
to read back what was painted.
"""
import base64
import fcntl
import os
import select
import struct
import sys
import termios
import tty

FENCE_TIMEOUT = 2.0
CHUNK = 4096

PLACEHOLDER = "\U0010EEEE"
# Row/column travel in these combining marks — the head of the same table
# `KittyGraphics+Placeholders.swift` generates, and the one `placement_probe.py`
# is measured drawing correctly in Ghostty.
DIACRITICS = [
    "̅", "̍", "̎", "̐", "̒", "̽",
    "̾", "̿", "͆", "͊", "͋", "͌",
]


# MARK: - Asking

def ask(fd, query, timeout=FENCE_TIMEOUT):
    """Send `query` fenced by DSR; return what came back before the fence."""
    os.write(fd, query + b"\x1b[6n")
    buf = b""
    while select.select([fd], [], [], timeout)[0]:
        buf += os.read(fd, 65536)
        if buf.endswith(b"R") and b"\x1b[" in buf:
            break
    else:
        return None
    return buf[:buf.rfind(b"\x1b[")]


def reply(raw):
    """The APC body a terminal answered with, readable."""
    if raw is None:
        return "<no fence — timed out>"
    if not raw:
        return "<silent>"
    return raw.decode("latin-1").replace("\x1b", "<ESC>")


# MARK: - Geometry

def cell_pixels(fd):
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
        rows, cols, width, height = struct.unpack("HHHH", packed)
        if width and height and rows and cols:
            return max(1, width // cols), max(1, height // rows)
    except OSError:
        pass
    return 8, 16


def ramp(width, height, opaque):
    """A left-to-right hue ramp fading downwards, so a transposed or torn
    placement is visible and not merely 'something appeared'."""
    out = bytearray()
    for y in range(height):
        fade = 1.0 - (y / max(1, height - 1)) * 0.6
        for x in range(width):
            hue = (x / max(1, width - 1)) * 6.0
            sector, frac = min(5, int(hue)), hue - int(hue)
            rising, falling, full = int(255 * frac * fade), int(255 * (1 - frac) * fade), int(255 * fade)
            red, green, blue = [
                (full, rising, 0), (falling, full, 0), (0, full, rising),
                (0, falling, full), (rising, 0, full), (full, 0, falling),
            ][sector]
            out += bytes((red, green, blue)) if opaque else bytes((red, green, blue, 255))
    return bytes(out)


# MARK: - The protocol

def transmit_commands(payload, width, height, image_id, opaque):
    """`a=t` — store the image, draw nothing. Chunked only when the payload
    does not fit: a single escape carries NO `m` key, which the protocol reads
    as 'not chunked' and is a different statement from `m=0`, 'the last chunk
    of one'.

    Returns ONE byte string containing every chunk, so the caller fences the
    whole transmission rather than each chunk. Fencing between chunks would
    interleave a DSR query inside a chunked image, which is a thing to test
    deliberately and never by accident — and the acknowledgement is emitted
    when the transmission COMPLETES, so there is nothing to read until the
    last chunk anyway."""
    encoded = base64.b64encode(payload).decode("ascii")
    fmt = 24 if opaque else 32
    head = f"a=t,q=0,f={fmt},t=d,s={width},v={height},i={image_id}"
    if len(encoded) <= CHUNK:
        return f"\x1b_G{head};{encoded}\x1b\\".encode("latin-1")
    parts = [encoded[i:i + CHUNK] for i in range(0, len(encoded), CHUNK)]
    out = ""
    for index, part in enumerate(parts):
        more = 0 if index == len(parts) - 1 else 1
        prefix = f"{head},m={more}" if index == 0 else f"m={more},q=0"
        out += f"\x1b_G{prefix};{part}\x1b\\"
    return out.encode("latin-1")


def direct_placement(image_id, columns, rows):
    """A placement with NO `U=1`: the terminal draws it at the cursor, and no
    placeholder cell is involved anywhere."""
    return f"\x1b_Ga=p,q=0,i={image_id},c={columns},r={rows}\x1b\\".encode("latin-1")


def virtual_placement(image_id, columns, rows):
    return f"\x1b_Ga=p,U=1,q=0,i={image_id},c={columns},r={rows}\x1b\\".encode("latin-1")


def placeholder_rows(image_id, columns, rows):
    """The cells that draw a virtual placement: the id in a 24-bit foreground,
    then one placeholder per cell carrying its row and column."""
    red, green, blue = (image_id >> 16) & 0xFF, (image_id >> 8) & 0xFF, image_id & 0xFF
    return [
        "\x1b[38;2;%d;%d;%dm%s\x1b[0m" % (
            red, green, blue,
            "".join(PLACEHOLDER + DIACRITICS[row] + DIACRITICS[col] for col in range(columns)))
        for row in range(rows)
    ]


# MARK: - The card

CASES = [
    ("A", 1, 1, True, "f=24  single escape, no m   virtual"),
    ("B", 1, 1, False, "f=32  single escape, no m   virtual"),
    ("C", 12, 4, True, "f=24  chunked m=1 … m=0     virtual"),
    ("D", 12, 4, False, "f=32  chunked m=1 … m=0     virtual"),
]


def main():
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("run this inside the terminal under test")
    cell_width, cell_height = cell_pixels(fd)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)

    # Everything — text included — goes out through `os.write` on the same
    # descriptor `ask` uses. Mixing it with buffered `print` reorders the
    # output against the escapes, which for a probe whose whole result is
    # WHERE a picture landed is not a cosmetic problem.
    def out(text=""):
        os.write(fd, (text + "\r\n").encode("utf-8"))

    try:
        out()
        out(f"cell pixels: {cell_width}x{cell_height}")
        out()

        # A-D: transmit and place first — a VIRTUAL placement draws nothing
        # until a placeholder cell carrying its id is written, so the replies
        # can be collected here and the pictures appear below, in the card,
        # where those cells are printed.
        for index, (label, columns, rows, opaque, description) in enumerate(CASES):
            image_id = 7000 + index
            payload = ramp(columns * cell_width, rows * cell_height, opaque)
            transmitted = reply(ask(fd, transmit_commands(
                payload, columns * cell_width, rows * cell_height, image_id, opaque)))
            placed = reply(ask(fd, virtual_placement(image_id, columns, rows)))
            out(f"  {label}: {description}")
            out(f"       transmit -> {transmitted}")
            out(f"       place    -> {placed}")
            for line in placeholder_rows(image_id, columns, rows):
                out("       " + line)
            out()

        # E — the control. Same bytes, no placeholders, so it separates "can
        # this terminal put these pixels on the screen at all" from "does it
        # honour placeholder cells".
        #
        # Placed ONCE, here, at the cursor position where it belongs. A direct
        # placement draws the instant it is sent, so collecting its reply
        # anywhere else means drawing it somewhere else — which is what the
        # previous version did, and then tried to undo with `a=d,d=i`. That
        # delete cost the image: E stopped drawing in Ghostty and iTerm2 showed
        # it only as a flash in the top-left corner before it was cleared. The
        # lesson is not about `d=i`'s semantics, it is that a probe should not
        # need to undo something it should not have done.
        direct_id = 7100
        direct = ramp(12 * cell_width, 4 * cell_height, True)
        direct_transmitted = reply(ask(fd, transmit_commands(
            direct, 12 * cell_width, 4 * cell_height, direct_id, True)))
        out("  E: f=24  chunked            DIRECT placement, no placeholders")
        out(f"       transmit -> {direct_transmitted}")
        out("       the picture, if any, is drawn at the cursor — here:")
        out()
        os.write(fd, b"       ")
        direct_placed = reply(ask(fd, direct_placement(direct_id, 12, 4)))
        # Past whatever it drew, so the questions below are not written over it.
        for _ in range(5):
            out()
        out(f"       place    -> {direct_placed}")
        out()

        for line in QUESTIONS.splitlines():
            out(line)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


QUESTIONS = """
  A-D should each be followed by a hue ramp: one coloured cell for A and B,
  a 12x4 ramp fading downwards for C and D. E should have drawn one at its
  own spot, above its `place ->` line.

  Report which of A B C D E drew, and paste the transmit/place lines.

    E draws, A-D blank ............. UNICODE PLACEHOLDERS are the problem.
                                     The pixels and the transmission are
                                     fine; the terminal accepts a virtual
                                     placement and never honours it.
    A and B draw, C and D blank .... chunking
    A and C blank, B and D draw .... the f=24 pixel format
    all five blank ................. the terminal draws no kitty image at
                                     all, however it is asked — check the
                                     transmit lines for a refusal
    all five draw .................. this terminal is fine; the fault is in
                                     what TUIkit sends around them
"""


if __name__ == "__main__":
    main()
