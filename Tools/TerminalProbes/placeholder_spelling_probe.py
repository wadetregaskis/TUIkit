#!/usr/bin/env python3
"""How must a Unicode placeholder cell be SPELLED for this terminal to draw it?

`pixel_format_probe.py` established that iTerm2 3.6.11 acknowledges every
kitty graphics command, draws a DIRECT placement correctly, and draws nothing
for a virtual one. The conclusion drawn from that — "iTerm2 does not implement
Unicode placeholders" — is one explanation. Here is another, and it is cheaper
to test than to argue about:

**TUIkit spells each placeholder cell with TWO combining marks** — row and
column — and omits the third, which states the most significant byte of the
image id (`KittyGraphics+Placeholders.swift`, "two marks per cell"). The
protocol allows that: a missing third mark means the id has no high byte.
A decoder that carries a sentinel for "absent" rather than zero, and then ORs
it into the id, looks up an image that was never transmitted — and draws
nothing, having acknowledged everything. Which is exactly what was measured.

The other thing never separated from it is the foreground SPELLING. The id
travels in the foreground colour, and TUIkit uses the 24-bit form
(`ESC[38;2;r;g;bm`) because one spelling carries the whole range. kitty's own
documentation example uses the 256-colour form (`ESC[38;5;Nm`). Both are
"read as numbers", and `KittyGraphics+Placeholders.swift` says both "were
measured to work" — but every one of those measurements was taken on Ghostty,
because iTerm2 has never drawn a virtual placement at all.

So: four cells of one 2x2 table, one image, no deletions, nothing to undo.

    1  two marks   256-colour foreground   (kitty's own doc example)
    2  three marks 256-colour foreground
    3  two marks   24-bit foreground       <- what TUIkit ships today
    4  three marks 24-bit foreground

If 3 is blank and 4 draws, the whole question is +2 bytes per cell. If 1 draws
and 3 does not, it is the foreground spelling. If none draws, the original
conclusion stands and placeholders really are unimplemented.

It also measures what U+10EEEE ADVANCES the cursor by on this host, which
`Documentation/Terminal-compatibility.md` records as "one cell, on every host"
having measured Ghostty, Warp and Apple Terminal — **iTerm2 is absent from
that table.** If it advances 0 or 2 here, every image row shears and no
spelling would have helped.

Run INSIDE the terminal under test.
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
PLACEHOLDER = "\U0010EEEE"

# Index 0 is U+0305. A third mark of index 0 states "the id's most significant
# byte is zero", which for every id below 65536 is the same claim as omitting
# it — unless the decoder disagrees, which is the hypothesis.
MARKS = ["̅", "̍", "̎", "̐", "̒", "̽"]

IMAGE_ID = 42


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
    return buf[: buf.rfind(b"\x1b[")]


def cursor_column(fd, timeout=FENCE_TIMEOUT):
    """The cursor's 1-based column, or None."""
    os.write(fd, b"\x1b[6n")
    buf = b""
    while select.select([fd], [], [], timeout)[0]:
        buf += os.read(fd, 4096)
        if buf.endswith(b"R"):
            break
    else:
        return None
    try:
        body = buf.split(b"\x1b[")[-1][:-1].decode("ascii")
        return int(body.split(";")[1])
    except (IndexError, ValueError):
        return None


def cell_pixels(fd):
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
        rows, cols, width, height = struct.unpack("HHHH", packed)
        if width and height and rows and cols:
            return max(1, width // cols), max(1, height // rows)
    except OSError:
        pass
    return 8, 16


def ramp(width, height):
    """A red-to-blue ramp, opaque, three bytes a pixel."""
    out = bytearray()
    for y in range(height):
        for x in range(width):
            t = x / max(1, width - 1)
            out += bytes((int(255 * (1 - t)), 40, int(255 * t)))
    return bytes(out)


def cells(marks, direct_colour, columns, rows):
    """`rows` lines of `columns` placeholder cells, spelled as asked."""
    if direct_colour:
        prefix = "\x1b[38;2;%d;%d;%dm" % (
            (IMAGE_ID >> 16) & 0xFF, (IMAGE_ID >> 8) & 0xFF, IMAGE_ID & 0xFF)
    else:
        prefix = "\x1b[38;5;%dm" % IMAGE_ID
    lines = []
    for row in range(rows):
        line = prefix
        for column in range(columns):
            line += PLACEHOLDER + MARKS[row] + MARKS[column]
            # The third mark: "the id's most significant byte is index 0".
            if marks == 3:
                line += MARKS[0]
        lines.append(line + "\x1b[39m")
    return lines


CASES = [
    (2, False, "two marks,   256-colour fg   (kitty's own doc example)"),
    (3, False, "three marks, 256-colour fg"),
    (2, True, "two marks,   24-bit fg        <- what TUIkit ships today"),
    (3, True, "three marks, 24-bit fg"),
]


def main():
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("run this inside the terminal under test")
    cell_width, cell_height = cell_pixels(fd)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)

    def out(text=""):
        os.write(fd, (text + "\r\n").encode("utf-8"))

    try:
        out()
        out(f"cell pixels: {cell_width}x{cell_height}")
        out()

        # One image, placed once, virtually. Every case below is the SAME
        # image and the SAME placement — only the spelling of the cells that
        # summon it differs, which is the whole experiment.
        payload = ramp(2 * cell_width, 2 * cell_height)
        encoded = base64.b64encode(payload).decode("ascii")
        head = (
            f"a=t,q=0,f=24,t=d,s={2 * cell_width},v={2 * cell_height},i={IMAGE_ID}")
        chunk = 4096
        parts = [encoded[i:i + chunk] for i in range(0, len(encoded), chunk)]
        if len(parts) == 1:
            # NO `m` key on a single escape. The protocol reads its absence as
            # "not chunked", which is a different statement from `m=0`, "the
            # last chunk of one" — and this probe must not vary anything but
            # the cell spelling, or four blanks would have two explanations.
            command = f"\x1b_G{head};{encoded}\x1b\\"
        else:
            command = ""
            for index, part in enumerate(parts):
                more = 0 if index == len(parts) - 1 else 1
                prefix = f"{head},m={more}" if index == 0 else f"m={more},q=0"
                command += f"\x1b_G{prefix};{part}\x1b\\"
        transmitted = ask(fd, command.encode("latin-1"))
        placed = ask(
            fd, f"\x1b_Ga=p,U=1,q=0,i={IMAGE_ID},c=2,r=2\x1b\\".encode("latin-1"))

        def show(raw):
            if raw is None:
                return "<no fence — timed out>"
            return raw.decode("latin-1").replace("\x1b", "<ESC>") if raw else "<silent>"

        out(f"  transmit -> {show(transmitted)}")
        out(f"  place    -> {show(placed)}")
        out()

        for marks, direct, description in CASES:
            out(f"  {description}")
            for line in cells(marks, direct, 2, 2):
                out("     " + line)
            out()

        # What does a placeholder ADVANCE the cursor by here? Twelve of them,
        # written from a known column, and ask. `Terminal-compatibility.md`
        # says one cell on every host and never measured iTerm2.
        os.write(fd, b"  advance: ")
        before = cursor_column(fd)
        os.write(fd, ("".join(PLACEHOLDER + MARKS[0] + MARKS[0] for _ in range(12))).encode("utf-8"))
        after = cursor_column(fd)
        out()
        if before is not None and after is not None:
            moved = after - before
            reading = "one cell each" if moved == 12 else f"{moved / 12:.2f} cells each — SHEARS"
            out(f"     12 placeholders moved the cursor {moved} columns — {reading}")
        else:
            out("     (no DSR reply — advance not measured)")
        out()

        for line in QUESTIONS.splitlines():
            out(line)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


QUESTIONS = """
  Each of the four labelled cases should show the SAME 2x2 red-to-blue ramp.
  They differ only in how the cells naming it are spelled.

  Report which of 1 2 3 4 drew, and the advance line.

    3 blank, 4 draws ............... the missing THIRD MARK is the cause.
                                     TUIkit appends U+0305 to every cell,
                                     +2 bytes, and iTerm2 works on the
                                     pipeline that already exists.
    1 draws, 3 blank ............... the FOREGROUND SPELLING is the cause:
                                     this host reads 256-colour and not
                                     24-bit.
    1 and 2 draw, 3 and 4 blank .... foreground spelling, independent of
                                     the mark count.
    none draws ..................... placeholders really are unimplemented;
                                     the earlier conclusion stands.
    all four draw .................. this host is fine and the fault is in
                                     something else TUIkit sends.
"""


if __name__ == "__main__":
    main()
