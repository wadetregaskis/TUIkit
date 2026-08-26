#!/usr/bin/env python3
"""Drive a TUIkit app under a PTY that impersonates a known terminal, and check
that the app identifies it — or correctly declines to.

Why a PTY and not a unit test: the unit tests cover the parse
(`TerminalIdentityQueryTests`) and the fingerprint, but not the WIRING, and the
wiring is the fragile part. `TerminalHost`'s detectors are `static let`, so each
freezes on first read, and `FrameDiffWriter` reads all of them as its init
defaults — which means the startup query has to run before the render loop is
constructed. Nothing in the type system enforces that ordering. This does: it
runs the real binary with no `TERM_PROGRAM` (the ssh case), answers Device
Attributes as a chosen terminal would, and looks at the bytes that come out.

The check is the cursor compensation around 🖥️ (U+1F5A5 U+FE0F), which Apple
Terminal paints two cells wide while advancing one: the row must carry a CUF
(`ESC[1C`) after the glyph on Apple Terminal and must NOT on anything else —
absent explicit evidence a terminal is assumed to render correctly, so a
compensation applied to an unidentified host is a bug, not a safe default.

Usage:
  identity_smoke.py <binary> [--host apple|ghostty|silent|all] [--seconds 2.5]

Exit 0 if every host behaves as expected, 1 otherwise.
"""
import argparse
import os
import pty
import re
import select
import sys
import time

# What each impersonated terminal answers, and whether TUIkit should then
# compensate. Apple Terminal's replies are measured (455.1 / macOS 15.7, through
# ssh, identity_probe.py); Ghostty's DA strings were read from its shipped
# binary and its XTVERSION from Documentation/Terminal-compatibility.md.
HOSTS = {
    "apple": (
        {b"\x1b[c": b"\x1b[?1;2c", b"\x1b[>c": b"\x1b[>1;95;0c"},
        True,
    ),
    "ghostty": (
        {
            b"\x1b[c": b"\x1b[?62;22c",
            b"\x1b[>c": b"\x1b[>1;10;0c",
            b"\x1b[>0q": b"\x1bP>|ghostty 1.3.1\x1b\\",
        },
        False,
    ),
    # Answers the DSR fence and nothing else: a terminal we cannot name, which
    # must be left alone.
    "silent": ({}, False),
}

# NOT covered here, deliberately: Ghostty identified by TERM=xterm-ghostty.
#
# This harness's oracle is "did a CUF appear after the header glyph", and
# Example's first screen contains nothing Ghostty compensates — checked by
# scanning that screen for any character whose ghosttyCursorAdvance differs
# from its terminalWidth, and finding none. Its header emoji is a VS-16
# cluster, which Ghostty advances correctly, so an identified Ghostty and an
# unidentified terminal emit byte-identical output there and a case for it
# would pass whether or not the signal worked.
#
# The termtype path is covered by TerminalHostIdentificationTests (resolver and
# detectors) and was verified end-to-end in a real Ghostty with the environment
# scrubbed to what an ssh hop leaves. It also does not need this harness's
# specific guarantee: what makes the DA path fragile is ordering — the
# detectors are `static let` and freeze on first read, so the query must run
# before RenderLoop is built — and TERM is read from the environment at the
# same moment as TERM_PROGRAM, with no query involved.

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM",
)

GLYPH = "\U0001F5A5"          # 🖥 — the Example header's emoji, VS-16 in the app
CUF = "\x1b[1C"


def run(binary, replies, seconds, config_dir):
    """Run `binary` under a PTY answering `replies`; return everything it wrote."""
    pid, fd = pty.fork()
    if pid == 0:
        for key in STRIPPED:
            os.environ.pop(key, None)
        os.environ["TERM"] = "xterm-256color"
        # Never the real preferences.
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        os.execv(binary, [binary])

    out = b""
    pending = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.1)
        if not readable:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
        pending += data
        while True:
            match = re.search(rb"\x1b\[[?>=]?[0-9;]*[a-zA-Z@]", pending)
            if not match:
                break
            sequence = match.group(0)
            pending = pending[match.end():]
            if sequence in replies:
                os.write(fd, replies[sequence])
            elif sequence == b"\x1b[6n":
                os.write(fd, b"\x1b[1;1R")     # the fence every terminal answers
    os.write(fd, b"q")
    time.sleep(0.3)
    try:
        os.kill(pid, 9)
    except OSError:
        pass
    os.waitpid(pid, 0)
    return out.decode("utf8", "replace")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--host", default="all", choices=[*HOSTS, "all"])
    parser.add_argument("--seconds", type=float, default=2.5)
    args = parser.parse_args()

    config_dir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "tuikit-identity-smoke")
    hosts = list(HOSTS) if args.host == "all" else [args.host]
    failures = 0
    for host in hosts:
        replies, should_compensate = HOSTS[host]
        text = run(args.binary, replies, args.seconds, config_dir)
        at = text.find(GLYPH)
        if at < 0:
            print(f"{host:<8} INCONCLUSIVE — the app never drew {GLYPH}")
            failures += 1
            continue
        compensated = CUF in text[at:at + 12]
        ok = compensated == should_compensate
        failures += not ok
        print(
            f"{host:<8} {'ok  ' if ok else 'FAIL'} "
            f"compensation {'present' if compensated else 'absent'}, "
            f"expected {'present' if should_compensate else 'absent'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
