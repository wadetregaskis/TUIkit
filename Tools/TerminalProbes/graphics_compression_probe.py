#!/usr/bin/env python3
"""Kitty DEFLATED TRANSMISSION probe: does `o=z` reach the screen?

The graphics protocol lets a transmission be zlib-compressed (`o=z`, RFC 1950,
compressed BEFORE base64). TUIkit uses it, where the terminal says it can,
because a gradient rendered as pixels is seventeen identical rows and deflates
by an order of magnitude — and because it can borrow the host's own `libz` at
runtime rather than carry an encoder.

Two questions, because "acknowledged" and "drawn" are different facts (iTerm2
acknowledged every placement command for a day and drew nothing — see
`placeholder_spelling_probe.py`):

1. **Is a deflated transmission acknowledged?** The same 32×32 block TUIkit's
   startup handshake sends, `q=0` so the reply comes back. `OK` means the
   bytes were understood; an error names why; silence is a terminal with no
   protocol at all. The SIZE of the probe is what makes it honest: twenty-six
   deflated bytes cannot be a 32×32 raw picture, so a terminal that ignored
   the `o=z` key would have to refuse it.
2. **Does a deflated picture DRAW?** A hue ramp, transmitted deflated and
   placed directly at the cursor (`a=T`), beside the same ramp transmitted raw.
   A person compares them. If the deflated one is blank or garbage, the
   terminal lied in (1) and `TUIKIT_GRAPHICS_COMPRESSION=0` is the answer for
   it until it is fixed.

Run INSIDE the terminal under test. Writes JSON to $PROBE_OUT (default
./graphics_compression_probe.json) and prints the card.
"""
import base64, json, os, select, sys, termios, tty, zlib

import probe_stamp

FENCE_TIMEOUT = 1.0
IMAGE_TIMEOUT = 4.0  # a picture is decoded and drawn, not merely parsed

# TUIkit's own probe block: 32×32 RGBA of nothing, deflated.
BLOCK = zlib.compress(bytes(32 * 32 * 4), 6)


def ramp(width, height):
    """A left-to-right hue ramp, RGB, so a wrong decode is visible as such."""
    out = bytearray()
    for _ in range(height):
        for x in range(width):
            t = x / max(1, width - 1)
            out += bytes((int(255 * (1 - t)), int(255 * t), int(255 * abs(0.5 - t) * 2)))
    return bytes(out)


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
    return buf[: buf.rfind(b"\x1b[")]


def render(raw):
    if raw is None:
        return "<no answer — even the fence timed out>"
    if raw == b"":
        return "<silent>"
    return "".join(
        "<ESC>" if b == 0x1B else (f"<{b:02X}>" if b < 0x20 or b == 0x7F else chr(b)) for b in raw)


def transmit(image_id, pixels, width, height, deflated, display):
    payload = zlib.compress(pixels, 6) if deflated else pixels
    keys = f"i={image_id},a={'T' if display else 't'},t=d,f=24,s={width},v={height},q=0"
    if deflated:
        keys += ",o=z"
    if display:
        keys += ",c=16,r=2,C=1"  # sixteen cells by two rows, cursor left where it is
    return f"\x1b_G{keys};".encode() + base64.b64encode(payload) + b"\x1b\\"


def main():
    out_path = os.environ.get("PROBE_OUT", "graphics_compression_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("graphics_compression_probe: stdin is not a terminal — run this IN the terminal under test")

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "graphics_compression_probe", use_alt=False)
        answers = {
            # The handshake's own two questions, in the order it asks them.
            "PLACEMENT": ask(
                fd,
                b"\x1b_Gi=16777215,a=t,t=d,f=32,s=1,v=1,q=2;AAAAAA==\x1b\\"
                b"\x1b_Ga=p,U=1,q=0,i=16777215,c=1,r=1\x1b\\"
                b"\x1b_Ga=d,d=I,q=2,i=16777215\x1b\\"),
            "DEFLATED_TRANSMIT": ask(
                fd,
                b"\x1b_Ga=t,q=0,f=32,t=d,o=z,s=32,v=32,i=16777214;" + base64.b64encode(BLOCK)
                + b"\x1b\\" + b"\x1b_Ga=d,d=I,q=2,i=16777214\x1b\\"),
        }
        # The card: the same ramp raw and deflated, one under the other.
        pixels = ramp(256, 32)
        os.write(fd, b"\r\n  raw:      ")
        raw_reply = ask(fd, transmit(901, pixels, 256, 32, deflated=False, display=True), IMAGE_TIMEOUT)
        os.write(fd, b"\r\n\r\n\r\n  deflated: ")
        deflated_reply = ask(fd, transmit(902, pixels, 256, 32, deflated=True, display=True), IMAGE_TIMEOUT)
        os.write(fd, b"\r\n\r\n\r\n")
        answers["RAW_DISPLAY"] = raw_reply
        answers["DEFLATED_DISPLAY"] = deflated_reply
        os.write(fd, b"\x1b_Ga=d,d=I,q=2,i=901\x1b\\\x1b_Ga=d,d=I,q=2,i=902\x1b\\")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    record = dict(stamp)
    record["deflated"] = {
        "placement_ok": b"OK" in (answers["PLACEMENT"] or b""),
        "deflated_transmit_ok": b"OK" in (answers["DEFLATED_TRANSMIT"] or b""),
        "block_bytes": len(BLOCK),
        "ramp_bytes_raw": len(pixels),
        "ramp_bytes_deflated": len(zlib.compress(pixels, 6)),
        "replies": {name: render(raw) for name, raw in answers.items()},
    }
    record["rendered"] = "unmeasured — compare the two ramps above and fill this in by hand"
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    print("  placement            ", render(answers["PLACEMENT"]))
    print("  deflated transmit    ", render(answers["DEFLATED_TRANSMIT"]))
    print("  raw display          ", render(answers["RAW_DISPLAY"]))
    print("  deflated display     ", render(answers["DEFLATED_DISPLAY"]))
    print(f"  ramp: {len(pixels)} bytes raw, {len(zlib.compress(pixels, 6))} deflated")
    print(f"\n  Are the two ramps identical? Record the answer in {out_path} under 'rendered'.")


if __name__ == "__main__":
    main()
