#!/usr/bin/env python3
"""
Drive a TUIkit terminal app inside a real pseudo-terminal (PTY): set the
window size, feed it a scripted sequence of keyboard + mouse input, and
continuously drain its ANSI output so the child never blocks on a full
PTY buffer.

A TUIkit app needs a real TTY — it puts stdin in raw mode (`tcsetattr`)
and asks for the window size with `ioctl(TIOCGWINSZ)`. Pipes don't
satisfy that; a PTY does. This script is the "end-to-end" profiling
driver: it exercises the full input -> dispatch -> render -> diff ->
write loop the way a real user does.

Two modes:
  • drive only   — run a scenario, print I/O stats (sanity check the app)
  • drive+record — pass --trace OUT.trace to attach Instruments' Time
                   Profiler (via xctrace) to the running app for the run

Usage:
    drive.py BIN [--scenario tour|list|table|emoji|scroll|mouse|idle]
                 [--loops N] [--rows R] [--cols C] [--settle S]
                 [--trace OUT.trace] [--time-limit MS] [--quiet]

Quits the app cleanly with 'q' (TUIkit's default quit shortcut), falling
back to SIGTERM/SIGKILL.
"""
import argparse
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import fcntl
import time

ESC = b"\x1b"
UP, DOWN, RIGHT, LEFT = ESC + b"[A", ESC + b"[B", ESC + b"[C", ESC + b"[D"
ENTER, TAB = b"\r", b"\t"
PGUP, PGDN = ESC + b"[5~", ESC + b"[6~"

# ContentView page shortcuts (see Sources/TUIkitExample/ContentView.swift).
PAGE_KEYS = {
    "lists": "-", "tables": "=", "scroll": "s", "emoji": ".", "mouse": "m",
    "text": "1", "colors": "2", "containers": "3", "buttons": "6",
    "radios": "9", "sliders": "[", "steppers": "]",
}


def mouse_sgr(button, col, row, press):
    """SGR (1006) mouse report; button 0=left, 64/65=wheel up/down."""
    return f"{ESC.decode()}[<{button};{col};{row}{'M' if press else 'm'}".encode()


def scenario_pages(page_keys, scroll=12):
    """Generic: jump to each page, scroll down then up, return to menu."""
    steps = []
    for p in page_keys:
        steps.append((0.10, p.encode()))
        for _ in range(scroll):
            steps.append((0.02, DOWN))
        for _ in range(scroll // 2):
            steps.append((0.02, UP))
        steps.append((0.05, ESC))
    return steps


def scenario_scroll(page_key, n=40):
    steps = [(0.20, page_key.encode())]
    for _ in range(n):
        steps.append((0.015, DOWN))
    for _ in range(n):
        steps.append((0.015, UP))
    for _ in range(6):
        steps.append((0.05, PGDN))
    for _ in range(6):
        steps.append((0.05, PGUP))
    return steps


def scenario_mouse(rows, cols):
    steps = [(0.20, PAGE_KEYS["mouse"].encode())]
    cx, cy = cols // 2, rows // 2
    for dx in range(-10, 11, 5):
        steps.append((0.03, mouse_sgr(0, cx + dx, cy, True)))
        steps.append((0.03, mouse_sgr(0, cx + dx, cy, False)))
    for _ in range(20):
        steps.append((0.02, mouse_sgr(65, cx, cy, True)))   # wheel down
    for _ in range(20):
        steps.append((0.02, mouse_sgr(64, cx, cy, True)))   # wheel up
    return steps


def build_scenario(name, rows, cols):
    if name == "tour":
        return scenario_pages(list(PAGE_KEYS.values()))
    if name == "list":
        return scenario_scroll(PAGE_KEYS["lists"])
    if name == "table":
        return scenario_scroll(PAGE_KEYS["tables"])
    if name == "emoji":
        return scenario_scroll(PAGE_KEYS["emoji"])
    if name == "scroll":
        return scenario_scroll(PAGE_KEYS["scroll"])
    if name == "mouse":
        return scenario_mouse(rows, cols)
    if name == "idle":
        # Sit on the emoji page (a heavy page) and let the pulse/cursor
        # timers re-render. Measures steady-state per-frame cost.
        return [(0.30, PAGE_KEYS["emoji"].encode())] + [(0.10, b"")] * 80
    raise SystemExit(f"unknown scenario: {name}")


def set_winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("--scenario", default="tour",
                    choices=["tour", "list", "table", "emoji", "scroll", "mouse", "idle"])
    ap.add_argument("--loops", type=int, default=1)
    ap.add_argument("--rows", type=int, default=50)
    ap.add_argument("--cols", type=int, default=160)
    ap.add_argument("--settle", type=float, default=0.6)
    ap.add_argument("--trace", default=None,
                    help="if set, attach Instruments Time Profiler and write this .trace")
    ap.add_argument("--time-limit", type=int, default=15000,
                    help="xctrace recording limit in ms (only with --trace)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    master, slave = pty.openpty()
    set_winsize(slave, args.rows, args.cols)

    pid = os.fork()
    if pid == 0:  # child
        os.close(master)
        os.login_tty(slave)  # setsid + TIOCSCTTY + dup2(0,1,2) + close
        env = dict(os.environ)
        env.update(TERM="xterm-256color", COLUMNS=str(args.cols), LINES=str(args.rows))
        os.execve(args.binary, [args.binary], env)
        os._exit(127)

    os.close(slave)
    total = 0

    def drain(timeout):
        nonlocal total
        while True:
            r, _, _ = select.select([master], [], [], timeout)
            if not r:
                return 0
            try:
                data = os.read(master, 65536)
            except OSError:
                return -1
            if not data:
                return -1
            total += len(data)
            timeout = 0.0

    drain(args.settle)  # startup + first frames

    xctrace = None
    if args.trace:
        xctrace = subprocess.Popen(
            ["xcrun", "xctrace", "record", "--template", "Time Profiler",
             "--attach", str(pid), "--time-limit", f"{args.time_limit}ms",
             "--output", args.trace],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(2.0)  # let xctrace begin sampling before we drive

    script = []
    for _ in range(args.loops):
        script.extend(build_scenario(args.scenario, args.rows, args.cols))

    for delay, payload in script:
        if delay:
            end = time.time() + delay
            while time.time() < end:
                if drain(min(0.01, max(0.0, end - time.time()))) < 0:
                    break
        if payload:
            try:
                os.write(master, payload)
            except OSError:
                break

    end = time.time() + 0.4
    while time.time() < end:
        if drain(0.05) < 0:
            break

    if xctrace:
        out, _ = xctrace.communicate(timeout=180)
        if not args.quiet:
            print("\n".join("[xctrace] " + l for l in out.strip().splitlines()[-6:]))

    try:
        os.write(master, b"q")
    except OSError:
        pass
    deadline = time.time() + 1.5
    while time.time() < deadline:
        if drain(0.1) < 0:
            break
        if os.waitpid(pid, os.WNOHANG)[0]:
            break
    else:
        try:
            os.kill(pid, signal.SIGTERM); time.sleep(0.2); os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass

    if not args.quiet:
        print(f"[drive] scenario={args.scenario} loops={args.loops} "
              f"size={args.cols}x{args.rows} output={total:,} bytes")
        if args.trace:
            print(f"[drive] trace written: {args.trace}")


if __name__ == "__main__":
    main()
