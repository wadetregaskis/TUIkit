#!/usr/bin/env python3
"""Terminal cell aspect-ratio probe. Run INSIDE the terminal under test.

Reports the cell's height:width ratio two ways:
  1. ioctl(TIOCGWINSZ) ws_xpixel/ws_ypixel — the free path TUIkit's
     `Terminal.cellPixelAspect()` uses. Many terminals report 0 here.
  2. the CSI 14 t (text-area pixels) + CSI 18 t (text-area chars) escape
     query — the fallback when the ioctl fields are 0.

The ratio is what `Image` needs to render undistorted; the default is 2.0
(≈ Apple Terminal). Feed a measured value with `.imageCellAspect(_:)` if a
terminal neither fills ws_*pixel nor answers the escape queries.

Report goes to $PROBE_OUT (default: ./cell_aspect_probe.txt), matching the
sibling probes: stdout must stay attached to the terminal (it carries the
CSI queries and the ioctl target), so redirecting it breaks the probe.
"""
import os, sys, termios, tty, struct, fcntl, select

_out = open(os.environ.get("PROBE_OUT", "cell_aspect_probe.txt"), "w", buffering=1)
sys.stderr.write(f"writing report to {os.path.abspath(_out.name)}\n")

def report(*args):
    _out.write(" ".join(str(a) for a in args) + "\n")


def ioctl_pixels():
    buf = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\x00" * 8)
    rows, cols, xpix, ypix = struct.unpack("HHHH", buf)
    return rows, cols, xpix, ypix

def query(seq):
    """Write an escape query, read the reply up to 't'."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        sys.stdout.write(seq)
        sys.stdout.flush()
        out = b""
        while select.select([fd], [], [], 0.5)[0]:
            ch = os.read(fd, 1)
            out += ch
            if ch == b"t":
                break
        return out.decode(errors="replace")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

def parse_t(reply):
    # ESC [ 4 ; H ; W t   (14t)  or  ESC [ 8 ; rows ; cols t  (18t)
    body = reply.strip().lstrip("\x1b[").rstrip("t")
    parts = body.split(";")
    return [int(p) for p in parts if p.isdigit()]

report("TERM_PROGRAM =", os.environ.get("TERM_PROGRAM"),
      os.environ.get("TERM_PROGRAM_VERSION", ""))

rows, cols, xpix, ypix = ioctl_pixels()
report(f"ioctl winsize: {cols}x{rows} chars, {xpix}x{ypix} px")
if xpix > 0 and ypix > 0 and cols > 0 and rows > 0:
    cw, ch = xpix / cols, ypix / rows
    report(f"  cell = {cw:.2f}x{ch:.2f} px  ->  aspect (h/w) = {ch/cw:.3f}")
else:
    report("  ws_xpixel/ws_ypixel are 0 — ioctl path unavailable here")

try:
    area = parse_t(query("\x1b[14t"))   # text-area pixels: ESC[4;H;Wt
    chars = parse_t(query("\x1b[18t"))  # text-area chars:  ESC[8;rows;colst
    if len(area) >= 3 and len(chars) >= 3:
        _, ph, pw = area[:3]
        _, cr, cc = chars[:3]
        cw, ch = pw / cc, ph / cr
        report(f"CSI 14t/18t: area {pw}x{ph} px, {cc}x{cr} chars")
        report(f"  cell = {cw:.2f}x{ch:.2f} px  ->  aspect (h/w) = {ch/cw:.3f}")
    else:
        report("CSI 14t/18t: no usable reply")
except Exception as exc:  # noqa: BLE001
    report("CSI 14t/18t query failed:", exc)
