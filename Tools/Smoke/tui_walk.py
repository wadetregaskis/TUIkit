#!/usr/bin/env python3
"""Walk a TUIkit app's menu in a real PTY, visiting every item and checking
the process stays alive and keeps painting.

Usage:
  tui_walk.py <binary> <item-count> [--per-item KEYS] [--cols N] [--rows N]
              [--scale N]

Visits item i (for i in 0..<count) as: Down×i, Enter, wait, [KEYS], Esc.
KEYS is a comma list of: down, up, enter, esc, tab, space, or wait<seconds>,
each optionally repeated as `down*5`. The child runs with an isolated
TUIKIT_CONFIG_DIR (never the user's real preferences) and TERM=xterm-256color.

Exit code: 0 if the app survived every visit, 1 otherwise (the failing item
index and final screen are printed). This is the standing regression net for
crash classes unit tests cannot see — e.g. the Deep Recursion debug-build
stack overflow of 2026-07-17, which only manifested in the interactive
render loop, in a specific build state, and never under --selfcheck.
"""
import argparse
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

import pyte

SEQUENCES = {
    "down": "\x1b[B", "up": "\x1b[A", "left": "\x1b[D", "right": "\x1b[C",
    "enter": "\r", "esc": "\x1b", "tab": "\t", "space": " ",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("count", type=int)
    parser.add_argument("--per-item", default="down*3,up")
    parser.add_argument("--cols", type=int, default=140)
    parser.add_argument("--rows", type=int, default=42)
    parser.add_argument("--scale", type=int, default=0)
    parser.add_argument("--settle", type=float, default=1.0)
    args = parser.parse_args()

    screen = pyte.Screen(args.cols, args.rows)
    stream = pyte.ByteStream(screen)
    config_dir = os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "tuikit-smoke-config")

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        os.environ["TERM"] = "xterm-256color"
        if args.scale:
            os.environ["TUIKIT_STRESS_SCALE"] = str(args.scale)
        os.execv(args.binary, [args.binary])

    fcntl.ioctl(fd, termios.TIOCSWINSZ,
                struct.pack("HHHH", args.rows, args.cols, 0, 0))

    def alive() -> bool:
        finished, _ = os.waitpid(pid, os.WNOHANG)
        return finished == 0

    def pump(seconds: float) -> bool:
        end = time.time() + seconds
        ok = True
        while time.time() < end:
            readable, _, _ = select.select([fd], [], [], 0.1)
            if fd in readable:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    ok = False
                    break
                if not data:
                    ok = False
                    break
                stream.feed(data)
        return ok and alive()

    def send(token: str) -> bool:
        if token.startswith("wait"):
            return pump(float(token[4:]))
        reps = 1
        if "*" in token:
            token, count = token.split("*")
            reps = int(count)
        for _ in range(reps):
            os.write(fd, SEQUENCES[token].encode())
            if not pump(0.25):
                return False
        return True

    def dump_screen() -> None:
        for index, line in enumerate(screen.display):
            text = line.rstrip()
            if text:
                print(f"{index:3}| {text}")

    if not pump(1.5):
        print("FAIL: app died before the menu appeared")
        dump_screen()
        return 1

    for item in range(args.count):
        ok = True
        for _ in range(item):
            ok = ok and send("down")
        ok = ok and send("enter") and pump(args.settle)
        for token in args.per_item.split(","):
            if token:
                ok = ok and send(token)
        ok = ok and send("esc") and pump(0.3)
        # Return the selection to the top for the next item's Down-walk.
        for _ in range(item):
            ok = ok and send("up")
        if not ok:
            print(f"FAIL: app died while visiting item {item}")
            dump_screen()
            return 1
        print(f"ok item {item}")

    os.write(fd, b"q")
    pump(0.3)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    os.waitpid(pid, 0)
    print(f"walked {args.count} items: all alive")
    return 0


if __name__ == "__main__":
    sys.exit(main())
