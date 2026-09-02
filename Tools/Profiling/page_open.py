#!/usr/bin/env python3
"""Measure the cost of opening a page the FIRST time versus later times.

    page_open.py BIN 1,13,20 [--rounds 4] [--cols 200] [--rows 50] [--quiet 0.12]

`drive.py` measures a scenario running; this measures a page ARRIVING, which is
the thing a user calls "slow to open". For each menu item: Up×40 to reset the
cursor, Down×i, Enter, then read until the output has been quiet for `--quiet`
seconds. Prints the wall time from the keystroke to that silence, and the bytes
written in the window, once per round.

The comparison it exists for is ROUND 0 against the rest, in one process: a
cost paid once per page per session — a cold memo, a lazily-built table —
shows there and nowhere else. A page that never goes quiet (anything animated,
`progress` among them) reads as the `--quiet` cap instead; that is a limit of
the oracle, not a measurement.

`PROBE_HOST` sets `TERM_PROGRAM`, which selects the per-host compensation
walks in `FrameDiffWriter` — those run only in emission and so are invisible
to `Stress --bench`.
"""
import argparse, fcntl, os, pty, select, struct, sys, termios, time
import pyte

ap = argparse.ArgumentParser()
ap.add_argument("binary")
ap.add_argument("items", help="comma-separated menu item indices")
ap.add_argument("--rounds", type=int, default=3)
ap.add_argument("--cols", type=int, default=100)
ap.add_argument("--rows", type=int, default=34)
ap.add_argument("--quiet", type=float, default=0.15, help="seconds of silence = settled")
args = ap.parse_args()

env = dict(os.environ)
env["TERM"] = "xterm-256color"
if os.environ.get("PROBE_HOST"):
    env["TERM_PROGRAM"] = os.environ["PROBE_HOST"]
# Its own config directory, so a run cannot read or write the user's state.
env["TUIKIT_CONFIG_DIR"] = os.path.join(
    os.environ.get("TMPDIR", "/tmp"), "tuikit-page-open-probe")
os.makedirs(env["TUIKIT_CONFIG_DIR"], exist_ok=True)

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(args.binary, [args.binary], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))
screen = pyte.Screen(args.cols, args.rows)
stream = pyte.ByteStream(screen)

def drain(seconds):
    """Read for `seconds`, returning the bytes seen."""
    total = 0
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], max(0, end - time.time()))
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return total
            if not data:
                return total
            total += len(data)
            stream.feed(data)
    return total

def settle(quiet, cap=8.0):
    """Read until `quiet` seconds pass with no output. Returns (elapsed, bytes)."""
    start = time.time()
    total = 0
    last = time.time()
    while time.time() - start < cap:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            total += len(data)
            stream.feed(data)
            last = time.time()
        elif time.time() - last >= quiet:
            break
    return (last - start, total)

drain(1.5)
items = [int(v) for v in args.items.split(",")]
print(f"{'item':>5} {'round':>5} {'ms':>9} {'bytes':>9}  title")
for item in items:
    for round_index in range(args.rounds):
        for _ in range(40):
            os.write(fd, b"\x1b[A")
        drain(0.35)
        for _ in range(item):
            os.write(fd, b"\x1b[B")
            drain(0.02)
        drain(0.15)
        os.write(fd, b"\r")
        elapsed, total = settle(args.quiet)
        title = screen.display[1].strip().split("  ")[0][1:].strip()
        print(f"{item:>5} {round_index:>5} {elapsed*1000:>9.1f} {total:>9}  {title}")
        os.write(fd, b"\x1b")
        drain(0.4)
os.write(fd, b"q")
time.sleep(0.3)
try:
    os.kill(pid, 9)
except ProcessLookupError:
    pass
