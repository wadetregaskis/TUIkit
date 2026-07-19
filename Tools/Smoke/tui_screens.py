#!/usr/bin/env python3
"""Walk a TUIkit app in a real PTY, capturing the rendered screen at every
step and linting each capture for rendering defects that liveness walks and
unit tests cannot see.

Usage:
  tui_screens.py <binary> <item-count> [--per-item KEYS] [--cols N] [--rows N]
                 [--scale N] [--dump-dir DIR] [--settle S]

The walk mirrors tui_walk.py (Down×i, Enter, per-item keys, Esc), but after
every keystroke settles it snapshots the pyte-reconstructed screen. Each
snapshot is linted:

  * escape leakage  — CSI/SGR fragments appearing as literal text (a split or
                      malformed sequence printed instead of interpreted)
  * clipped labels  — scroll-indicator words cut mid-word ("more lines belo")
                      instead of degrading whole-word
  * box coherence   — unbalanced box-drawing corners on a row (┌ without ┐)
  * invisible text  — non-space cells whose fg == bg (both explicit): rendered
                      but unreadable, the inverted-highlight/dim-blend class
  * mojibake        — U+FFFD replacement characters
  * blank page      — a visited page painting (almost) nothing

With --dump-dir every snapshot is also written to DIR/item<NN>-<step>.txt
(plain text) for human review; lint findings print with their snapshot name.
Exit code: 0 = no findings and app survived; 1 otherwise. The child runs with
an isolated TUIKIT_CONFIG_DIR and TERM=xterm-256color, like tui_walk.py.
"""
import argparse
import fcntl
import os
import pty
import re
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

# CSI/SGR remnants showing as TEXT mean an escape byte went missing. Require
# a parameter digit and a final byte; '?' covers private modes (e.g. "[?25l").
ESCAPE_LEAK = re.compile(r"\[\?[0-9;]+[a-z]|\[[0-9;]{2,}[mHJKABCD]")

# An indicator label must never clip mid-word: catch tell-tale stumps of the
# vocabulary ("above/below/lines/rows/more") that aren't the whole word.
CLIPPED_LABEL = re.compile(
    r"\b(abov|belo|abo|bel|lin|line|row|mor|more line|more row)$")
INDICATOR_HINT = re.compile(r"[▲▼]")

CORNER_PAIRS = [("┌", "┐"), ("└", "┘"), ("╭", "╮"), ("╰", "╯"),
                ("╔", "╗"), ("╚", "╝")]


def is_block_element(char: str) -> bool:
    """Block-element glyphs (▀▄█▌▐░▒▓ …) drawn with fg == bg are the solid-
    fill idiom — half-block image cells whose two pixels share a colour,
    progress-bar fills, tab/swatch chrome — not invisible text."""
    return len(char) == 1 and 0x2580 <= ord(char) <= 0x259F


def lint_screen(screen: pyte.Screen, name: str, entered_page: bool) -> list:
    findings = []
    display = screen.display
    non_empty = sum(1 for line in display if line.strip())
    if entered_page and non_empty < 3:
        findings.append(f"{name}: page painted only {non_empty} non-empty rows")
    for y, line in enumerate(display):
        text = line.rstrip()
        if not text:
            continue
        if "�" in text:
            findings.append(f"{name} row {y}: replacement char: {text!r}")
        leak = ESCAPE_LEAK.search(text)
        if leak:
            findings.append(f"{name} row {y}: escape leakage {leak.group()!r}: {text!r}")
        if INDICATOR_HINT.search(text):
            stripped = text.strip()
            if CLIPPED_LABEL.search(stripped):
                findings.append(f"{name} row {y}: clipped indicator label: {stripped!r}")
        # Tab strips legitimately mix a selected tab's rounded corners with
        # its neighbours' ┬/┴ junctions on one row; only junction-free rows
        # are held to strict corner pairing.
        if "┬" not in text and "┴" not in text:
            for left, right in CORNER_PAIRS:
                if text.count(left) != text.count(right):
                    findings.append(
                        f"{name} row {y}: unbalanced corners {left}{right} "
                        f"({text.count(left)} vs {text.count(right)}): {text!r}")
    # Invisible TEXT is a run of letter-bearing cells whose fg == bg — a
    # label painted in its own background colour (the inverted-highlight /
    # dim-blend class). Isolated fg==bg cells are solid fills (see
    # is_block_element); image text-modes fill with digits/punctuation, so
    # a run only counts when it contains an actual letter.
    for y in range(screen.lines):
        row = screen.buffer[y]
        run: list = []

        def flush() -> None:
            if len(run) >= 2 and any(c.data.isalpha() for _, c in run):
                word = "".join(c.data for _, c in run)
                findings.append(
                    f"{name} row {y} col {run[0][0]}: invisible text "
                    f"(fg==bg=={run[0][1].fg}): {word!r}")

        for x in sorted(row.keys()):
            cell = row[x]
            eligible = (
                cell.data.strip() and cell.fg == cell.bg
                and cell.fg != "default" and not is_block_element(cell.data))
            continues = (
                eligible and run
                and x == run[-1][0] + 1 and cell.fg == run[-1][1].fg)
            if continues:
                run.append((x, cell))
            else:
                flush()
                run = [(x, cell)] if eligible else []
        flush()
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("count", type=int)
    parser.add_argument("--per-item", default="down*3,up")
    parser.add_argument("--cols", type=int, default=140)
    parser.add_argument("--rows", type=int, default=42)
    parser.add_argument("--scale", type=int, default=0)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--dump-dir", default=None)
    args = parser.parse_args()

    if args.dump_dir:
        os.makedirs(args.dump_dir, exist_ok=True)

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

    all_findings = []

    def capture(name: str, entered_page: bool) -> None:
        all_findings.extend(lint_screen(screen, name, entered_page))
        if args.dump_dir:
            path = os.path.join(args.dump_dir, f"{name}.txt")
            with open(path, "w") as handle:
                for line in screen.display:
                    handle.write(line.rstrip() + "\n")

    if not pump(1.5):
        print("FAIL: app died before the menu appeared")
        return 1
    capture("menu", entered_page=False)

    for item in range(args.count):
        ok = True
        for _ in range(item):
            ok = ok and send("down")
        ok = ok and send("enter") and pump(args.settle)
        capture(f"item{item:02}-enter", entered_page=True)
        for step, token in enumerate(t for t in args.per_item.split(",") if t):
            ok = ok and send(token)
            capture(f"item{item:02}-{step}-{token.replace('*', 'x')}",
                    entered_page=True)
        ok = ok and send("esc") and pump(0.3)
        for _ in range(item):
            ok = ok and send("up")
        if not ok:
            print(f"FAIL: app died while visiting item {item}")
            return 1
        print(f"ok item {item}")

    os.write(fd, b"q")
    pump(0.3)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    os.waitpid(pid, 0)

    if all_findings:
        print(f"\n{len(all_findings)} render-lint findings:")
        for finding in all_findings:
            print(f"  {finding}")
        return 1
    print(f"walked {args.count} items: all alive, no render-lint findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
