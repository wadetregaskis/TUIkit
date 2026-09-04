#!/usr/bin/env python3
"""Kitty UNICODE PLACEHOLDER probe: does an image behave like CELLS?

`graphics_probe.py` asked which of the three graphics protocols a terminal
speaks. This asks the one question that decides whether TUIkit can use the
answer: with a *virtual* placement and Unicode placeholders, is an image
addressable as ordinary text — C columns by R rows of real cells that the
cursor walks one at a time, that scroll with their row, and that anything drawn
afterwards covers?

Everything TUIkit does downstream of a view is defined on cells: `clamped`
clips them, `composited(with:at:)` overlays them, `ScrollView` windows them,
`FrameDiffWriter` diffs them one cell at a time and rewrites only the runs that
differ. An image drawn at the cursor is none of those things. An image drawn
INTO the grid is all of them for free — if, and only if, the terminal really
does treat a placeholder cell as one cell.

Five questions, and the first is the one everything else rests on:

1. **Does a placeholder cell advance the cursor exactly one column?**
   U+10EEEE sits inside the Plane-16 Private Use Area, and every host this
   project has measured paints a Plane-16 codepoint two cells wide while
   advancing one — it is how SF Symbols behave, and TUIkit compensates for it
   by erasing under the glyph and pushing the cursor on. If the placeholder
   inherited that rule, every image would shear. So the advance is measured,
   per row, against the number of cells actually written.

2. **Is the picture right?** Row and column travel in combining diacritics, so
   a wrong table, a transposition, or an off-by-one shows up as a scrambled
   image and as nothing else. The card is a left-to-right hue ramp under a
   top-to-bottom fade: order is visible on both axes, which a flat colour
   would hide.

3. **Does the run-length elision work?** Kitty lets a cell with no diacritics
   continue the previous one, which is the difference between three scalars per
   cell and one. Worth knowing before the encoder picks a spelling.

4. **Is a 256-colour foreground enough to carry an image id?** Ids above 255
   need a direct-colour triple, which costs bytes on every row of every image.

5. **Does deleting by id actually free it?** A retained image is a resource the
   application now owns; a probe that never deletes cannot say whether deleting
   works.

> **`q=2` matters more than it looks.** Without it the terminal answers every
> graphics command with `ESC_G…;OK ESC\\`, and in a real application those bytes
> arrive on *stdin*, where the input parser reads them as keystrokes. This
> probe uses `q=0` deliberately — it wants the answers and reads them itself.
> Anything on a render path must use `q=2`.

Run INSIDE the terminal under test. Writes JSON to $PROBE_OUT (default
./placement_probe.json) and prints the card.
"""
import base64, fcntl, json, os, select, struct, sys, termios, time, tty

import probe_stamp

FENCE_TIMEOUT = 1.0
# An image is decoded and drawn, not merely parsed; iTerm2 was measured to miss
# a one-second fence after a graphics payload. See graphics_probe.IMAGE_TIMEOUT.
IMAGE_TIMEOUT = 4.0

# The placeholder character. Not a glyph the terminal draws: it is intercepted
# and replaced by whatever part of the image the cell's diacritics name.
PLACEHOLDER = "\U0010EEEE"

# Kitty's row/column diacritics, verbatim from `gen/rowcolumn-diacritics.txt`
# in the kitty repository — combining marks of class 230 from Unicode 6.0.0
# that neither decompose nor fuse with a base. The Nth entry means N, so the
# table's length (297) is the largest image dimension addressable in cells.
DIACRITICS = [
    0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F,
    0x0346, 0x034A, 0x034B, 0x034C, 0x0350, 0x0351, 0x0352, 0x0357,
    0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
    0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F, 0x0483, 0x0484,
    0x0485, 0x0486, 0x0487, 0x0592, 0x0593, 0x0594, 0x0595, 0x0597,
    0x0598, 0x0599, 0x059C, 0x059D, 0x059E, 0x059F, 0x05A0, 0x05A1,
    0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4, 0x0610, 0x0611,
    0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617, 0x0657, 0x0658,
    0x0659, 0x065A, 0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8,
    0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF, 0x06E0, 0x06E1, 0x06E2,
    0x06E4, 0x06E7, 0x06E8, 0x06EB, 0x06EC, 0x0730, 0x0732, 0x0733,
    0x0735, 0x0736, 0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743,
    0x0745, 0x0747, 0x0749, 0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE,
    0x07EF, 0x07F0, 0x07F1, 0x07F3, 0x0816, 0x0817, 0x0818, 0x0819,
    0x081B, 0x081C, 0x081D, 0x081E, 0x081F, 0x0820, 0x0821, 0x0822,
    0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082A, 0x082B, 0x082C,
    0x082D, 0x0951, 0x0953, 0x0954, 0x0F82, 0x0F83, 0x0F86, 0x0F87,
    0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75, 0x1A76,
    0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D,
    0x1B6E, 0x1B6F, 0x1B70, 0x1B71, 0x1B72, 0x1B73, 0x1CD0, 0x1CD1,
    0x1CD2, 0x1CDA, 0x1CDB, 0x1CE0, 0x1DC0, 0x1DC1, 0x1DC3, 0x1DC4,
    0x1DC5, 0x1DC6, 0x1DC7, 0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1,
    0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5, 0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9,
    0x1DDA, 0x1DDB, 0x1DDC, 0x1DDD, 0x1DDE, 0x1DDF, 0x1DE0, 0x1DE1,
    0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE, 0x20D0, 0x20D1,
    0x20D4, 0x20D5, 0x20D6, 0x20D7, 0x20DB, 0x20DC, 0x20E1, 0x20E7,
    0x20E9, 0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2,
    0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6, 0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA,
    0x2DEB, 0x2DEC, 0x2DED, 0x2DEE, 0x2DEF, 0x2DF0, 0x2DF1, 0x2DF2,
    0x2DF3, 0x2DF4, 0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA,
    0x2DFB, 0x2DFC, 0x2DFD, 0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D,
    0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1, 0xA8E2, 0xA8E3, 0xA8E4, 0xA8E5,
    0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA, 0xA8EB, 0xA8EC, 0xA8ED,
    0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2, 0xAAB3, 0xAAB7,
    0xAAB8, 0xAABE, 0xAABF, 0xAAC1, 0xFE20, 0xFE21, 0xFE22, 0xFE23,
    0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186, 0x1D187,
    0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243,
    0x1D244,
]


# MARK: - A picture whose ORDER is visible

def ramp_image(width, height):
    """RGB bytes for a left-to-right hue ramp under a top-to-bottom fade.

    A flat colour would prove the image arrived and nothing else. This one
    fails visibly and specifically: a transposed placement swaps the ramps, an
    off-by-one in the diacritics tears a stripe out of the middle, and a
    terminal that draws only the first cell shows one hue instead of six.
    """
    out = bytearray()
    for y in range(height):
        fade = 1.0 - 0.6 * (y / max(1, height - 1))
        for x in range(width):
            hue = 6.0 * x / max(1, width)
            sector, frac = int(hue) % 6, hue % 1.0
            rising, falling = frac, 1.0 - frac
            red, green, blue = [
                (1, rising, 0), (falling, 1, 0), (0, 1, rising),
                (0, falling, 1), (rising, 0, 1), (1, 0, falling),
            ][sector]
            out += bytes(int(255 * channel * fade) for channel in (red, green, blue))
    return bytes(out)


# MARK: - The protocol

def transmit(image, image_id, width, height, chunk=4096):
    """`a=t` — put the image in the terminal's store under `image_id`.

    Chunked because the protocol caps an escape sequence's payload: `m=1` says
    another chunk follows, `m=0` ends it. The control keys ride on the first
    chunk only.
    """
    payload = base64.b64encode(image).decode("ascii")
    pieces = [payload[at:at + chunk] for at in range(0, len(payload), chunk)] or [""]
    out = []
    for index, piece in enumerate(pieces):
        more = 1 if index < len(pieces) - 1 else 0
        head = (f"a=t,t=d,f=24,s={width},v={height},i={image_id},q=0,m={more}"
                if index == 0 else f"m={more}")
        out.append(f"\x1b_G{head};{piece}\x1b\\")
    return "".join(out)


def place(image_id, columns, rows):
    """`a=p,U=1` — a VIRTUAL placement: no pixels yet, just a declaration that
    this image is `columns` x `rows` cells and will be drawn wherever cells
    carrying its id appear."""
    return f"\x1b_Ga=p,U=1,i={image_id},c={columns},r={rows},q=0\x1b\\"


def foreground(image_id):
    """The SGR that carries the image id. Ids through 255 fit the 256-colour
    form; above that the id's low 24 bits go in a direct-colour triple."""
    if image_id <= 255:
        return f"\x1b[38;5;{image_id}m"
    return (f"\x1b[38;2;{(image_id >> 16) & 0xFF};"
            f"{(image_id >> 8) & 0xFF};{image_id & 0xFF}m")


def cell(row, column, image_id=None, elide=False):
    """One placeholder cell. `elide` drops the diacritics, which Kitty reads as
    "same row, next column" — the run-length form.

    THREE marks, always — row, column, and the image id's high byte even when
    it is zero. The spec lets a cell omit the third and inherit it, and this
    probe once did for ids under 2^24 (every id TUIkit issues); measured
    2026-09-03, iTerm2 3.6.11 acknowledges such a cell and draws nothing,
    while kitty and Ghostty read both spellings alike. The encoder writes all
    three since 0d4d2015, and a probe that spelled cells differently from the
    encoder could no longer see a disagreement between them."""
    if elide:
        return PLACEHOLDER
    high_byte = ((image_id or 0) >> 24) & 0xFF
    return PLACEHOLDER + chr(DIACRITICS[row]) + chr(DIACRITICS[column]) + chr(DIACRITICS[high_byte])


def placeholder_rows(image_id, columns, rows, elide=False):
    """The image as text: one string per row, ready to print like any other."""
    sgr = foreground(image_id)
    out = []
    for row in range(rows):
        body = cell(row, 0, image_id) + "".join(
            cell(row, column, image_id, elide=elide) for column in range(1, columns))
        out.append(sgr + body + "\x1b[39m")
    return out


# MARK: - Asking

def ask(fd, query, timeout=FENCE_TIMEOUT):
    """Send `query` fenced by DSR; return what came back before the fence."""
    os.write(fd, query + b"\x1b[6n")
    buf = b""
    while select.select([fd], [], [], timeout)[0]:
        buf += os.read(fd, 4096)
        if buf.endswith(b"R") and b"\x1b[" in buf:
            break
    else:
        return None
    return buf[:buf.rfind(b"\x1b[")]


def cursor(fd, timeout=FENCE_TIMEOUT):
    """DSR — (row, column), 1-based, or None."""
    os.write(fd, b"\x1b[6n")
    got = b""
    while select.select([fd], [], [], timeout)[0]:
        got += os.read(fd, 1024)
        if got.endswith(b"R"):
            break
    else:
        return None
    try:
        body = got[got.rfind(b"\x1b[") + 2:-1].split(b";")
        return int(body[0]), int(body[1])
    except (IndexError, ValueError):
        return None


def render(raw):
    if isinstance(raw, str):
        return raw
    if raw is None:
        return "<no answer — even the fence timed out>"
    if raw == b"":
        return "<silent>"
    out = ""
    for byte in raw:
        out += "<ESC>" if byte == 0x1B else (
            f"<{byte:02X}>" if byte < 0x20 or byte == 0x7F else chr(byte))
    return out


def grid(fd):
    """The terminal in cells, from TIOCGWINSZ — the size a full-screen image
    would have to cover."""
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    except OSError:
        return (80, 24)
    rows, columns, _, _ = struct.unpack("HHHH", packed)
    return (columns or 80, rows or 24)


def cell_pixels(fd):
    """Cell size in pixels, from the same ioctl the framework uses. `None`
    where the terminal reports no pixel size — which is most of them, and the
    reason `imageCellAspect` has a default at all."""
    try:
        packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    except OSError:
        return None
    rows, columns, x_pixels, y_pixels = struct.unpack("HHHH", packed)
    if not (rows and columns and x_pixels and y_pixels):
        return None
    return (x_pixels // columns, y_pixels // rows)


def timed_transmit(fd, image, image_id, width, height):
    """Transmit `image` and time it end to end, including the terminal's ack.

    The number that decides whether a transmit can sit on a render path. The
    payload is raw RGB at the size the cells will occupy, which for a Retina
    cell is three bytes per physical pixel — a full screen is megabytes, and
    "megabytes through a PTY" is a guess until somebody measures it.
    """
    payload = transmit(image, image_id, width, height).encode("latin-1")
    started = time.monotonic()
    reply = ask(fd, payload, timeout=IMAGE_TIMEOUT)
    return {
        "seconds": time.monotonic() - started,
        "base64_bytes": len(base64.b64encode(image)),
        "acknowledged": bool(reply) and b"OK" in reply,
    }


# MARK: - The measurement that decides it

def advance_of(fd, text, expected_cells):
    """Write `text` on a cleared row and report how far the cursor moved.

    The whole of question 1 in one number. `expected_cells` is what the caller
    believes it wrote; anything else is the Plane-16 rule leaking onto a
    codepoint that is not a glyph.
    """
    os.write(fd, b"\r\x1b[2K")
    before = cursor(fd)
    os.write(fd, text.encode("utf-8"))
    after = cursor(fd, timeout=IMAGE_TIMEOUT)
    os.write(fd, b"\r\x1b[2K")
    if not (before and after):
        return {"expected": expected_cells, "advance": None, "row_delta": None}
    return {"expected": expected_cells,
            "advance": after[1] - before[1],
            "row_delta": after[0] - before[0]}


def main():
    out_path = os.environ.get("PROBE_OUT", "placement_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("placement_probe: stdin is not a terminal — run this IN the terminal under test")

    columns, rows = 12, 4
    pixels = cell_pixels(fd)
    # Transmit at the size the cells will actually occupy where the terminal
    # says how big a cell is, so nothing is scaled twice. Where it does not,
    # assume a plausible cell and let the terminal scale.
    cell_width, cell_height = pixels or (8, 17)
    image = ramp_image(columns * cell_width, rows * cell_height)
    # Two ids, because the id travels in the FOREGROUND COLOUR: one that fits
    # the 256-colour form and one that forces a direct-colour triple.
    small_id, large_id = 31, 0x00BEEF

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "placement_probe", use_alt=False)
        # The placement query has to name an image that EXISTS, or the reply
        # says nothing about placements. Asked cold, Ghostty answers
        # `ENOENT: image not found` — which is the terminal getting as far as
        # the lookup, i.e. evidence FOR the feature, read by an earlier probe
        # of mine as evidence against it. Transmit one pixel first and the
        # reply becomes unambiguous: `OK` supports virtual placements, a named
        # refusal (Warp: `UnicodePlaceholderUnsupported`) does not, silence is
        # a terminal with no protocol at all.
        answers = {
            "KITTY_QUERY": ask(fd, b"\x1b_Gi=1,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\"),
            "PROBE_TRANSMIT": ask(
                fd, b"\x1b_Gi=9,a=t,t=d,f=24,s=1,v=1,q=0;"
                + base64.b64encode(b"\xc8\x28\x5a") + b"\x1b\\"),
            "VIRTUAL_PLACEMENT": ask(fd, b"\x1b_Ga=p,U=1,i=9,c=1,r=1,q=0\x1b\\"),
        }
        # Everything below sends real payloads, so it is gated on the terminal
        # having answered the protocol query at all.
        record_supports_apc = bool(answers["KITTY_QUERY"])
        wide, tall = columns * cell_width, rows * cell_height
        card = timed_transmit(fd, image, small_id, wide, tall)
        card_seconds = card["seconds"]
        answers["TRANSMIT_SMALL"] = "OK" if card["acknowledged"] else "<no OK>"
        answers["PLACE_SMALL"] = ask(fd, place(small_id, columns, rows).encode("latin-1"))
        answers["TRANSMIT_LARGE"] = "OK" if timed_transmit(
            fd, image, large_id, wide, tall)["acknowledged"] else "<no OK>"
        answers["PLACE_LARGE"] = ask(fd, place(large_id, columns, rows).encode("latin-1"))

        # What a full-screen photo actually costs, at this terminal's real cell
        # resolution. Transmitted and then deleted: the probe is measuring the
        # wire and the decode, not filling the terminal's image store.
        #
        # Skipped outright on a terminal that answered no Kitty query, and that
        # is not tidiness. Apple Terminal does not parse APC — it PRINTS the
        # payload (measured; see `Documentation/Terminal graphics protocols.md`)
        # — so sending it megabytes of base64 would spray them across the
        # screen and take a long time doing it. A probe may not wedge the
        # terminal it is measuring.
        screen_columns, screen_rows = grid(fd)
        if record_supports_apc:
            big = ramp_image(screen_columns * cell_width, screen_rows * cell_height)
            full_screen = timed_transmit(
                fd, big, 77, screen_columns * cell_width, screen_rows * cell_height)
            ask(fd, b"\x1b_Ga=d,d=I,i=77,q=0\x1b\\")
        else:
            full_screen = {"seconds": None, "base64_bytes": None, "acknowledged": False}
        full_screen["cells"] = f"{screen_columns}x{screen_rows}"

        explicit = placeholder_rows(small_id, columns, rows)
        elided = placeholder_rows(small_id, columns, rows, elide=True)
        measurements = {
            "plain_text_control": advance_of(fd, "x" * columns, columns),
            "placeholder_row_explicit": advance_of(fd, explicit[0], columns),
            "placeholder_row_elided": advance_of(fd, elided[0], columns),
            "single_placeholder": advance_of(fd, placeholder_rows(small_id, 1, 1)[0], 1),
        }
        answers["DELETE"] = ask(
            fd, f"\x1b_Ga=d,d=I,i={small_id},q=0\x1b\\".encode("latin-1"))
        # Whether the delete freed anything can only be asked of something that
        # does a LOOKUP and does not transmit. `a=q` is the obvious candidate
        # and the wrong one: its `t=d,f=24;AAAA` payload re-creates the image
        # it is asking about, so it answers OK whatever the delete did. A
        # placement request is the honest question — ENOENT means the id is
        # gone, OK means the delete did not take.
        answers["PLACE_AFTER_DELETE"] = ask(
            fd, f"\x1b_Ga=p,U=1,i={small_id},c=1,r=1,q=0\x1b\\".encode("latin-1"))
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    record = dict(stamp)
    record["cell_pixels"] = {"width": cell_width, "height": cell_height,
                             "reported": pixels is not None}
    record["advertised"] = {
        "kitty_answered_query": bool(answers["KITTY_QUERY"]),
        "virtual_placement_ok": b"OK" in (answers["VIRTUAL_PLACEMENT"] or b""),
        "replies": {name: render(raw) for name, raw in answers.items()},
    }
    record["measurements"] = measurements
    record["bytes"] = {
        "image": len(image),
        "transmitted_base64": len(base64.b64encode(image)),
        "row_explicit": len(explicit[0].encode("utf-8")),
        "row_elided": len(elided[0].encode("utf-8")),
        "full_screen_base64": full_screen["base64_bytes"],
    }
    record["transmit_seconds"] = {
        "card_image": card_seconds,
        "full_screen": full_screen["seconds"],
        "full_screen_cells": full_screen["cells"],
    }
    record["rendered"] = "unmeasured — see the card; fill this in by hand"
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    print("\n  advertised")
    print(f"    Kitty answered      {record['advertised']['kitty_answered_query']}")
    print(f"    virtual placement   {record['advertised']['virtual_placement_ok']}")
    print(f"    cell pixels         {cell_width}x{cell_height}"
          f"{'' if pixels else '  (NOT reported — assumed)'}")
    for name, raw in answers.items():
        print(f"    {name:<19} {render(raw)}")

    print(f"\n  {'what':<26} {'cells':>6} {'advance':>8} {'drow':>5}  reading")
    for name, result in measurements.items():
        advance = result["advance"]
        if advance is None:
            reading = "no DSR answer"
        elif advance == result["expected"]:
            reading = "one cell each — behaves like text"
        elif advance == 2 * result["expected"]:
            reading = "TWO cells each — the Plane-16 width rule caught it"
        else:
            reading = "neither 1 nor 2 per cell — read the card"
        print(f"  {name:<26} {result['expected']:>6} {str(advance):>8} "
              f"{str(result['row_delta']):>5}  {reading}")

    print(f"\n  bytes: image {record['bytes']['image']}, "
          f"base64 {record['bytes']['transmitted_base64']}, "
          f"one row explicit {record['bytes']['row_explicit']} / "
          f"elided {record['bytes']['row_elided']}")
    if full_screen["seconds"] is None:
        print(f"  transmit: card {card_seconds * 1000:.0f} ms; full screen "
              f"({full_screen['cells']}) SKIPPED — this terminal answers no "
              "Kitty query, and one that does not parse APC would print it")
    else:
        print(f"  transmit: card {card_seconds * 1000:.0f} ms, "
              f"full screen ({full_screen['cells']}) "
              f"{full_screen['base64_bytes'] / 1e6:.1f} MB in "
              f"{full_screen['seconds'] * 1000:.0f} ms"
              + ("" if full_screen["acknowledged"] else "  (NOT acknowledged)"))

    print(f"\n  Card — a hue ramp left to right, fading top to bottom,\n"
          f"  {columns} cells wide and {rows} rows tall, drawn as TEXT:\n")
    for line in placeholder_rows(large_id, columns, rows):
        sys.stdout.write("    " + line + "\n")
    sys.stdout.flush()
    print(f"    {'-' * columns}   <- the image should be exactly this wide\n")
    print("  Look at it and answer, in the JSON's \"rendered\" field:\n"
          "    1. Is there a picture there at all?\n"
          "    2. Does the hue run red -> yellow -> green -> blue -> red LEFT TO\n"
          "       RIGHT, and does it FADE from top to bottom? A transposed\n"
          "       placement swaps those; a wrong diacritic tears out a stripe.\n"
          f"    3. Is it exactly {columns} cells wide and {rows} rows tall?\n")


if __name__ == "__main__":
    main()
