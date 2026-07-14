#!/usr/bin/env python3
"""Mouse byte-capture probe with heartbeat. No alternate screen."""
import os, sys, termios, tty, signal, select, time

out = open(os.environ["PROBE_OUT"], "a", buffering=1)
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)

def cleanup(*_):
    os.write(1, b"\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1006l\x1b[0m")
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    out.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
tty.setraw(fd)
os.write(1, b"\x1b[42;30m\x1b[2J\x1b[H  MOUSE PROBE READY - aim events here ('q' quits)\r\n")
os.write(1, b"\x1b[?1000h\x1b[?1002h\x1b[?1006h")
out.write(f"--- start tty={os.ttyname(fd)} ---\n")
last_beat = time.time()
try:
    while True:
        r, _, _ = select.select([fd], [], [], 1.0)
        if time.time() - last_beat > 5:
            out.write("<beat>\n"); last_beat = time.time()
        if not r:
            continue
        data = os.read(fd, 4096)
        if not data:
            out.write("<eof>\n"); break
        printable = "".join(chr(b) if 32 <= b < 127 else f"<{b:02X}>" for b in data)
        out.write(printable + "\n")
        if b"q" in data:
            break
finally:
    cleanup()
