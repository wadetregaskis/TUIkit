#!/usr/bin/env python3
"""Terminal GRAPHICS probe: Sixel, the iTerm2 inline-image protocol, and the
Kitty graphics protocol — what this terminal advertises, and what it does with
each when you send one.

Three questions, and they need three different instruments.

**Advertised.** Sixel is the only one of the three with a standard answer: a
terminal that supports it reports `4` among its Primary Device Attributes, and
that reply survives any number of ssh hops because the terminal itself answers
it. Kitty's protocol has a query of its own — `a=q` asks about an image id and
a supporting terminal answers `OK` — which is a real capability handshake and
the only one here. The iTerm2 protocol has neither; it is identified by knowing
which terminal you are talking to, the way OSC 8 support is.

**Safe.** All three ride escape families that end at a string terminator (DCS
for Sixel, OSC for iTerm2, APC for Kitty), so a terminal with a parser for the
family consumes the payload whether or not it implements the command — and one
without prints it. That is the same question `hyperlink_probe.py` asks of OSC 8
and it is answered the same way, by DSR: send the payload between two brackets,
ask where the cursor is, and compare against the brackets alone. The payloads
here are deliberately long enough that PRINTING one would wrap the row several
times, so "printed" and "rendered a small image" cannot be confused: the probe
reports the row and column deltas rather than a verdict.

**Rendered.** Whether an image actually appears, in the right place, at the
right size, is a question about pixels — so the probe draws a card and a human
looks at it. Same division as the hyperlink probe: the measurement is recorded,
the looking is asked for, and neither is dressed up as the other.

Run INSIDE the terminal under test. Writes JSON to $PROBE_OUT (default
./graphics_probe.json) and prints the card.
"""
import base64, json, os, select, struct, sys, termios, tty, zlib

import probe_stamp

FENCE_TIMEOUT = 1.0
# Decoding and drawing an image takes a terminal longer than answering a query,
# and iTerm2 was measured to miss a 1-second fence after one — reporting no
# cursor at all, which reads exactly like a host that hung. The wait after a
# payload is therefore its own, longer number: a slow answer is data, a missing
# one is not.
IMAGE_TIMEOUT = 4.0


# MARK: - A tiny image, three ways

def png(width, height, pixel):
    """A `width`x`height` PNG of one solid RGB `pixel`, built from zlib and
    struct so the probe needs nothing that is not in the standard library."""
    row = b"\x00" + bytes(pixel) * width
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height))
            + chunk(b"IEND", b""))


def sixel(columns=24, colour=(100, 20, 20)):
    """A DCS-wrapped sixel band: one row of sixels (6 pixels tall), all lit."""
    red, green, blue = colour                      # sixel colours are 0…100
    return ("\x1bPq"
            f"#0;2;{red};{green};{blue}"
            f"#0!{columns}~"
            "\x1b\\")


def iterm2(image, cells=2):
    """OSC 1337 File=…:<base64>, iTerm2's inline image."""
    payload = base64.b64encode(image).decode("ascii")
    return (f"\x1b]1337;File=inline=1;width={cells};height=1;preserveAspectRatio=0:"
            f"{payload}\x07")


def kitty(image, cells=2):
    """APC G …;<base64 PNG> ST — Kitty's transmit-and-display, one chunk."""
    payload = base64.b64encode(image).decode("ascii")
    return f"\x1b_Ga=T,f=100,c={cells},r=1;{payload}\x1b\\"


# MARK: - Asking

def ask(fd, query):
    """Send `query` fenced by DSR; return what came back before the fence."""
    os.write(fd, query + b"\x1b[6n")
    buf = b""
    while select.select([fd], [], [], FENCE_TIMEOUT)[0]:
        buf += os.read(fd, 4096)
        if buf.endswith(b"R") and b"\x1b[" in buf:
            break
    else:
        return None
    return buf[:buf.rfind(b"\x1b[")]


def render(raw):
    if raw is None:
        return "<no answer — even the fence timed out>"
    if raw == b"":
        return "<silent>"
    out = ""
    for byte in raw:
        if byte == 0x1B:
            out += "<ESC>"
        elif byte < 0x20 or byte == 0x7F:
            out += f"<{byte:02X}>"
        else:
            out += chr(byte)
    return out


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


def measure(fd, payloads):
    """Print each payload between two brackets and see where the cursor lands.

    The control is the brackets alone. A payload the terminal SWALLOWED leaves
    the cursor exactly where the control does; one it RENDERED moves it a
    little; one it PRINTED moves it by the payload's length, which for these is
    several rows.
    """
    results = {}
    for name, payload, what in payloads:
        os.write(fd, b"\r\x1b[2K")
        before = cursor(fd)
        os.write(fd, b"[" + payload.encode("latin-1") + b"]")
        after = cursor(fd, timeout=IMAGE_TIMEOUT)
        os.write(fd, b"\r\x1b[2K")
        results[name] = {
            "what": what,
            "payload_bytes": len(payload),
            "control_column": 3,
            "cursor_before": before,
            "cursor_after": after,
            "row_delta": None if not (before and after) else after[0] - before[0],
            "column_delta": None if not (before and after) else after[1] - before[1],
        }
    return results


def sixel_in_da1(reply):
    """Whether a Primary Device Attributes reply advertises sixel (parameter 4)."""
    if not reply:
        return None
    body = reply.decode("latin-1")
    at = body.find("\x1b[?")
    if at < 0:
        return None
    parameters = body[at + 3:].rstrip("c").split(";")
    return "4" in parameters


def main():
    out_path = os.environ.get("PROBE_OUT", "graphics_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("graphics_probe: stdin is not a terminal — run this IN the terminal under test")

    image = png(2, 2, (200, 40, 90))
    payloads = [
        ("control", "", "the brackets alone — the column the others are compared against"),
        ("sixel", sixel(), "DCS-wrapped sixel band"),
        ("iterm2", iterm2(image), "OSC 1337 File=inline — iTerm2's protocol"),
        ("kitty", kitty(image), "APC G a=T — Kitty's transmit-and-display"),
    ]

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "graphics_probe", use_alt=False)
        da1 = ask(fd, b"\x1b[c")
        answers = {
            "DA1": da1,
            # Kitty's own handshake: ask about an image id that does not exist.
            # A terminal implementing the protocol answers `ESC_Gi=31;…ESC\`;
            # one that does not says nothing at all.
            "KITTY_QUERY": ask(fd, b"\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\"),
            # `Su` is the terminfo capability tmux and others use for sixel.
            "XTGETTCAP_Su": ask(fd, b"\x1bP+q5375\x1b\\"),
            # UNICODE PLACEHOLDERS, the feature a TUI actually needs: transmit
            # an image with an id, then make a VIRTUAL placement of it, and the
            # image is drawn wherever cells containing U+10EEEE carry that id.
            # An image placed that way lives in the CELL GRID — it scrolls with
            # the rows, it is clipped by whatever clips them, and a row-diffing
            # writer can emit it as text. Every other placement mode puts pixels
            # at a position the grid knows nothing about.
            #
            # Sent as two steps so the reply says which half failed: `t=d,f=24`
            # transmits three bytes of RGB as a 1x1 image under id 42; `a=p,U=1`
            # asks for the virtual placement. `q=0` keeps the responses coming.
            "KITTY_TRANSMIT": ask(
                fd, b"\x1b_Gi=42,a=t,t=d,f=24,s=1,v=1,q=0;" + base64.b64encode(b"\xc8\x28\x5a")
                + b"\x1b\\"),
            "KITTY_VIRTUAL_PLACEMENT": ask(fd, b"\x1b_Ga=p,U=1,i=42,c=2,r=1,q=0\x1b\\"),
        }
        results = measure(fd, payloads)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    record = dict(stamp)
    record["advertised"] = {
        "sixel_in_da1": sixel_in_da1(da1),
        "kitty_answered_query": bool(answers["KITTY_QUERY"]),
        "kitty_virtual_placement_ok":
            b"OK" in (answers["KITTY_VIRTUAL_PLACEMENT"] or b""),
        "replies": {name: render(raw) for name, raw in answers.items()},
    }
    record["measurements"] = results
    record["rendered"] = "unmeasured — see the card; fill this in by hand"
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    print("\n  advertised")
    print(f"    sixel in DA1        {record['advertised']['sixel_in_da1']}")
    print(f"    Kitty answered      {record['advertised']['kitty_answered_query']}")
    print(f"    virtual placement   {record['advertised']['kitty_virtual_placement_ok']}")
    for name, raw in answers.items():
        print(f"    {name:<19} {render(raw)}")

    print(f"\n  {'payload':<10} {'bytes':>6} {'Δrow':>5} {'Δcol':>5}  reading")
    for name, result in results.items():
        row, column = result["row_delta"], result["column_delta"]
        if row is None:
            reading = "no DSR answer"
        elif name == "control":
            reading = "the control"
        elif (row, column) == (results["control"]["row_delta"],
                               results["control"]["column_delta"]):
            reading = "swallowed — consumed whole, nothing drawn"
        elif result["payload_bytes"] > 200 and row > 1:
            reading = "PRINTED — the payload went to the screen as text"
        else:
            reading = "moved the cursor — something was drawn; look at the card"
        print(f"  {name:<10} {result['payload_bytes']:>6} {str(row):>5} {str(column):>5}  {reading}")

    print("\n  Card — one 2x2 magenta square per protocol, two cells wide:\n")
    for name, payload, _ in payloads[1:]:
        print(f"    {name:<8} [", end="", flush=True)
        sys.stdout.write(payload)
        sys.stdout.flush()
        print("]")
    print("""
  What to answer by looking:

    1. Does a coloured square appear beside any of those labels? That is the
       protocol working.
    2. Does any of them leave VISIBLE JUNK — base64, `File=inline`, `#0!24~`?
       That host has no parser for the family and TUIkit must never emit it.
    3. Does the row afterwards still line up? A protocol that draws and then
       leaves the cursor somewhere unexpected is usable but needs its
       placement measured, which is what the Δrow/Δcol above records.
""")
    print(f"  written to {out_path}")


if __name__ == "__main__":
    main()
