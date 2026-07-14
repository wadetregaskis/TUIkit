#!/usr/bin/env python3
"""Mouse byte-capture probe with heartbeat. No alternate screen.

Writes captured bytes to $PROBE_OUT if set, else to ./mouse_probe.log
(stdout is unusable: the probe holds the tty in raw mode).
"""
import os, sys, termios, tty, signal, select, time

out_path = os.environ.get("PROBE_OUT", "mouse_probe.log")
out = open(out_path, "a", buffering=1)
sys.stderr.write(f"logging to {os.path.abspath(out_path)}\n")
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
term = os.environ.get("TERM_PROGRAM", "?")
version = os.environ.get("TERM_PROGRAM_VERSION", "?")
out.write(f"--- start tty={os.ttyname(fd)} term={term} {version} ---\n")
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
