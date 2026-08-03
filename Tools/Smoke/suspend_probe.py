#!/usr/bin/env python3
"""Job-control smoke probe: Ctrl-Z suspend / fg resume.

Drives a TUIkit app (default: the debug Example) in a PTY and verifies the
suspend round trip:

  1. Ctrl-Z (0x1A — raw mode clears ISIG, so it arrives as a KEY) makes the
     app hand the terminal back FIRST (exit the alternate screen, show the
     cursor, mouse reporting off) and then genuinely stop (WUNTRACED).
  2. SIGCONT (what `fg` sends) resumes it: it re-enters the alternate screen,
     re-enables its modes, and repaints the UI.
  3. The app still quits cleanly afterwards.

Usage:  python3 Tools/Smoke/suspend_probe.py [path-to-binary]

Exits 0 on success; prints FAIL lines and exits 1 otherwise. Uses an isolated
TUIKIT_CONFIG_DIR so the probe never touches real preferences.
"""

import fcntl
import os
import pty
import select
import signal
import struct
import sys
import tempfile
import termios
import time

COLS, ROWS = 90, 30
BINARY = sys.argv[1] if len(sys.argv) > 1 else "./.build/debug/Example"

ENTER_ALT = "\x1b[?1049h"
EXIT_ALT = "\x1b[?1049l"
SHOW_CURSOR = "\x1b[?25h"

failures: list[str] = []


def check(condition: bool, label: str) -> None:
    print(("ok   " if condition else "FAIL ") + label)
    if not condition:
        failures.append(label)


env = dict(os.environ)
env["TERM"] = "xterm-256color"
env["LANG"] = "en_US.UTF-8"
env["TUIKIT_CONFIG_DIR"] = tempfile.mkdtemp(prefix="tuikit-suspend-probe-")

pid, fd = pty.fork()
if pid == 0:
    os.execve(BINARY, [BINARY], env)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

captured = ""


def pump(seconds: float) -> None:
    global captured
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            if not data:
                return
            captured += data.decode("utf-8", "replace")


# 1. The app starts up onto the alternate screen.
pump(2.0)
check(ENTER_ALT in captured, "startup enters the alternate screen")
check("TUIkit" in captured, "the UI painted")

# 2. Ctrl-Z: the app must restore the terminal, then stop.
marker = len(captured)
os.write(fd, b"\x1a")
deadline = time.time() + 5.0
stopped = False
while time.time() < deadline:
    pump(0.1)
    done, status = os.waitpid(pid, os.WNOHANG | os.WUNTRACED)
    if done == pid and os.WIFSTOPPED(status):
        stopped = True
        break
check(stopped, "Ctrl-Z genuinely stops the process (WUNTRACED)")
suspended_output = captured[marker:]
check(EXIT_ALT in suspended_output, "the alternate screen was exited BEFORE stopping")
check(SHOW_CURSOR in suspended_output, "the cursor was shown before stopping")

# 3. SIGCONT (fg): re-init + repaint.
marker = len(captured)
os.kill(pid, signal.SIGCONT)
pump(2.0)
resumed_output = captured[marker:]
check(ENTER_ALT in resumed_output, "resume re-enters the alternate screen")
check("TUIkit" in resumed_output, "resume repaints the UI")

# 4. Still alive and quits cleanly.
os.write(fd, b"q")
deadline = time.time() + 5.0
exited = False
while time.time() < deadline:
    pump(0.1)
    done, status = os.waitpid(pid, os.WNOHANG)
    if done == pid and os.WIFEXITED(status):
        exited = True
        break
check(exited, "the app quits cleanly after the round trip")
final_output = captured[len(captured) - 4096 :]
check(EXIT_ALT in final_output, "quitting leaves the alternate screen")

try:
    os.close(fd)
except OSError:
    pass

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall checks passed")
