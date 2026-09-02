#!/usr/bin/env python3
"""Drive a TUIkit app in a PTY and examine the bytes it ACTUALLY emitted.

`tui_walk.py` and `tui_screens.py` decode the child's output with `pyte` and
ask questions about the resulting screen. That is the right tool for almost
everything and the wrong one for anything involving an emoji-presentation
cluster: **pyte abandons the rest of a write at a U+FE0F**, because VS-16 is
width 0 with combining class 0 and matches none of its draw branches. A row
carrying ⚙️ ⚠️ ✂️ therefore looks truncated in a pyte dump whatever the app
sent, which has cost real time — twice — chasing a bug the harness invented.

**pyte has no APC parser either**, and that one is louder: given the Kitty
graphics protocol's `ESC _ G …; <base64> ESC \\`, it prints the payload into the
screen — so an image page dumped through `tui_walk.py` shows kilobytes of
base64 across the top and bottom rows and the placement command as text. That
is the harness, not the app: every real terminal either consumes the sequence
or (Apple Terminal) is never sent one. The rows BETWEEN are still trustworthy,
which is how the placeholder cells' alignment was checked.

This probe decodes nothing. It records the child's bytes verbatim and counts
patterns in them, which is what the questions below actually need:

  * did this cluster reach the terminal with its cursor compensation?
    (`Documentation/Terminal-compatibility.md` — a cluster whose painted width
    and cursor advance disagree needs ECH before and CUF after on Terminal.app,
    and an emission missing them shifts the rest of the row one cell.)
  * does an IDLE app write anything at all, and how much?
  * what did one animation tick cost, in bytes?

Two phases are timed separately, because the interesting bugs live in the
difference: `settle` covers the render the last keystroke provoked, and
`watch` covers what happens afterwards with no input at all — animation
replay, and nothing else.

Usage:
  raw_probe.py <binary> --keys "down*10,enter,tab*7,down*8,space"
               [--cluster ⚙️] [--settle 0.6] [--watch 2.5] [--out FILE]
               [--term-program Apple_Terminal] [--cols N] [--rows N]

`--term-program` forces the host TUIkit detects, so a compensation path can be
exercised from any terminal (including CI). `--cluster` turns the byte counts
into a verdict: exit 1 if any emission of it in the watch phase is missing the
compensation the built rows carry, 2 if the phase never carried it at all
(inconclusive — the keys did not reach the row you meant).

The child runs with an isolated TUIKIT_CONFIG_DIR, never the real preferences.
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

# The same vocabulary `tui_walk.py` accepts, so a key script can be moved
# between the two probes unchanged.
SEQUENCES = {
    "down": "\x1b[B", "up": "\x1b[A", "left": "\x1b[D", "right": "\x1b[C",
    "enter": "\r", "esc": "\x1b", "tab": "\t", "space": " ",
    "ctrl-v": "\x16", "ctrl-r": "\x12",
}

# Erase Character, and Cursor Forward — what `withTerminalAppCursorCompensation`
# puts either side of an under-advancing cluster: erase the cells it claims in
# the current background, draw over the first, step past the last.
ECH = "\x1b[2X".encode()
CUF = "\x1b[1C".encode()


def parse_keys(script):
    """`"down*3,enter"` → the bytes to send, in order, one entry per press."""
    presses = []
    for token in script.split(","):
        token = token.strip()
        if not token:
            continue
        name, _, count = token.partition("*")
        if name not in SEQUENCES:
            raise SystemExit(f"unknown key {name!r}; known: {', '.join(sorted(SEQUENCES))}")
        presses += [SEQUENCES[name].encode()] * int(count or 1)
    return presses


class Child:
    """A TUIkit app on the other end of a PTY, and every byte it has sent."""

    def __init__(self, binary, cols, rows, term_program):
        self.all = bytearray()
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ["TUIKIT_CONFIG_DIR"] = os.path.join(
                os.environ.get("TMPDIR", "/tmp"), "tuikit-raw-probe")
            os.environ["TERM"] = "xterm-256color"
            if term_program:
                os.environ["TERM_PROGRAM"] = term_program
            os.execv(binary, [binary])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def drain(self, seconds):
        """Everything the child sends in `seconds`, also appended to `all`."""
        out = bytearray()
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if not ready:
                continue
            try:
                out += os.read(self.fd, 65536)
            except OSError:  # the child exited
                break
        self.all += out
        return bytes(out)

    def press(self, keys, gap):
        for key in keys:
            os.write(self.fd, key)
            self.drain(gap)

    def kill(self):
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass


def report(name, blob, cluster):
    counts = ""
    if cluster:
        emitted = blob.count(cluster)
        counts = (f", {emitted:3d} × {cluster.decode()}"
                  f" — {blob.count(cluster + CUF):3d} with CUF after,"
                  f" {blob.count(ECH + cluster):3d} with ECH before")
    print(f"{name:7s} {len(blob):7d} bytes{counts}")
    return blob.count(cluster) if cluster else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--keys", default="")
    parser.add_argument("--cluster", default=None,
                        help="a grapheme cluster to check the compensation of, e.g. ⚙️")
    parser.add_argument("--launch", type=float, default=1.5)
    parser.add_argument("--gap", type=float, default=0.15,
                        help="how long to let the app settle between keys")
    parser.add_argument("--settle", type=float, default=0.6)
    parser.add_argument("--watch", type=float, default=2.5)
    parser.add_argument("--cols", type=int, default=100)
    parser.add_argument("--rows", type=int, default=30)
    parser.add_argument("--term-program", default=None)
    parser.add_argument("--out", default=None, help="write the whole capture here")
    args = parser.parse_args()

    cluster = args.cluster.encode() if args.cluster else None
    child = Child(args.binary, args.cols, args.rows, args.term_program)
    try:
        child.drain(args.launch)
        child.press(parse_keys(args.keys), args.gap)
        settle = child.drain(args.settle)
        watch = child.drain(args.watch)
    finally:
        child.kill()

    if args.out:
        with open(args.out, "wb") as handle:
            handle.write(bytes(child.all))

    report("settle", settle, cluster)
    emitted = report("watch", watch, cluster)
    if not cluster:
        return 0
    print()
    if emitted == 0:
        print(f"INCONCLUSIVE: no {args.cluster} was emitted with no input pending; "
              "the keys did not reach the row you meant")
        return 2
    compensated = watch.count(cluster + CUF)
    if compensated == emitted:
        print(f"PASS: all {emitted} compensated")
        return 0
    print(f"FAIL: {emitted - compensated} of {emitted} uncompensated — "
          "the row will sit one cell left of where it belongs")
    return 1


sys.exit(main())
