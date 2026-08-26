#!/usr/bin/env python3
"""Does the app pin DEC mode 2027 when — and ONLY when — it should?

TUIkit's Ghostty advance model was measured with mode 2027 (grapheme
clustering) set, which is Ghostty's default. The mode persists across
processes, so a program that resets it and exits without restoring leaves
later sessions in a state where six of eleven measured cluster classes move
and the compensation is wrong in both directions: no CUF for a VS-16 cluster
that now under-advances, and a CUF for a VS-15 glyph that no longer does.
`Terminal.pinGraphemeClusteringIfNeeded()` closes that, and this checks it.

Two things have to hold, and only a live run can say so:

  1. The question is asked ONLY of a host identified as Ghostty. DECRQM is
     `CSI ? Ps $ p` — a private marker plus an intermediate byte, the one CSI
     shape Apple Terminal prints to the screen instead of consuming — so
     asking it blind would put a stray `p` on a user's shell.
  2. The mode is set only when the terminal says it is supported and off, and
     reset on exit only if this process set it.

Both depend on ordering that the type system cannot enforce: identification
must precede the question, and the question must precede `RenderLoop`, whose
`FrameDiffWriter` freezes the advance model at construction.

Runs the real binary under a PTY, answers DECRQM with each interesting
DECRPM value, and reads the escape sequences it emits. Exit 0 if every case
matches. Companion to `identity_smoke.py`, which checks the other half —
that identification reaches the compensation at all.
"""
import argparse
import os
import pty
import re
import select
import sys
import time

# (termtype, DECRPM reply value, expect_asked, expect_set)
# The reply values are the ones that mean different things: 2 = supported and
# off (the case this exists for), 1 = already on, 0 = the terminal has never
# heard of it. 4 (permanently reset) takes the same path as 0.
CASES = [
    ("xterm-ghostty", 2, True, True, "Ghostty, mode reset by a prior program"),
    ("xterm-ghostty", 1, True, False, "Ghostty, mode already set"),
    ("xterm-ghostty", 0, True, False, "Ghostty, mode not recognised"),
    ("xterm-ghostty", 4, True, False, "Ghostty, mode permanently reset"),
    ("xterm-256color", 2, False, False, "unidentified — must not be asked"),
]

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM",
)

DECRQM = b"\x1b[?2027$p"
SET = b"\x1b[?2027h"
RESET = b"\x1b[?2027l"


def run(binary, termtype, decrpm, config_dir, seconds):
    """Run `binary` under a PTY answering DECRQM with `decrpm`; return its output."""
    pid, fd = pty.fork()
    if pid == 0:
        for key in STRIPPED:
            os.environ.pop(key, None)
        os.environ["TERM"] = termtype
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        os.execv(binary, [binary])

    out = b""
    pending = b""

    def pump(until):
        nonlocal out, pending
        while time.time() < until:
            readable, _, _ = select.select([fd], [], [], 0.1)
            if not readable:
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            if not data:
                return
            out += data
            pending += data
            while True:
                # The `$` alternative matters: without it DECRQM is not matched
                # and the app waits out its timeout instead of being answered.
                match = re.search(rb"\x1b\[[?>=]?[0-9;]*[$ ]?[a-zA-Z@]", pending)
                if not match:
                    break
                sequence = match.group(0)
                pending = pending[match.end():]
                if sequence == DECRQM:
                    os.write(fd, b"\x1b[?2027;%d$y" % decrpm)
                elif sequence == b"\x1b[6n":
                    os.write(fd, b"\x1b[1;1R")   # the fence every terminal answers

    pump(time.time() + seconds)
    os.write(fd, b"q")
    pump(time.time() + 2.0)        # read through the clean shutdown, for the reset
    try:
        os.kill(pid, 9)
    except OSError:
        pass
    os.waitpid(pid, 0)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--seconds", type=float, default=2.0)
    args = parser.parse_args()

    config_dir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "tuikit-mode-pin-smoke")
    failures = 0
    for termtype, decrpm, expect_asked, expect_set, label in CASES:
        out = run(args.binary, termtype, decrpm, config_dir, args.seconds)
        asked, was_set, was_reset = DECRQM in out, SET in out, RESET in out
        # Whatever it turned on it must turn back off, and nothing else.
        ok = asked == expect_asked and was_set == expect_set and was_reset == expect_set
        failures += not ok
        print(
            f"{label:<40} {'ok  ' if ok else 'FAIL'} "
            f"asked={asked} set={was_set} restored={was_reset} "
            f"(expected asked={expect_asked} set={expect_set})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
