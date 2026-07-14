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
"""
import os, sys, termios, tty, struct, fcntl, select

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

print("TERM_PROGRAM =", os.environ.get("TERM_PROGRAM"),
      os.environ.get("TERM_PROGRAM_VERSION", ""))

rows, cols, xpix, ypix = ioctl_pixels()
print(f"ioctl winsize: {cols}x{rows} chars, {xpix}x{ypix} px")
if xpix > 0 and ypix > 0 and cols > 0 and rows > 0:
    cw, ch = xpix / cols, ypix / rows
    print(f"  cell = {cw:.2f}x{ch:.2f} px  ->  aspect (h/w) = {ch/cw:.3f}")
else:
    print("  ws_xpixel/ws_ypixel are 0 — ioctl path unavailable here")

try:
    area = parse_t(query("\x1b[14t"))   # text-area pixels: ESC[4;H;Wt
    chars = parse_t(query("\x1b[18t"))  # text-area chars:  ESC[8;rows;colst
    if len(area) >= 3 and len(chars) >= 3:
        _, ph, pw = area[:3]
        _, cr, cc = chars[:3]
        cw, ch = pw / cc, ph / cr
        print(f"CSI 14t/18t: area {pw}x{ph} px, {cc}x{cr} chars")
        print(f"  cell = {cw:.2f}x{ch:.2f} px  ->  aspect (h/w) = {ch/cw:.3f}")
    else:
        print("CSI 14t/18t: no usable reply")
except Exception as exc:  # noqa: BLE001
    print("CSI 14t/18t query failed:", exc)
