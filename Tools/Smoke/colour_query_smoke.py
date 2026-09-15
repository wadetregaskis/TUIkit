#!/usr/bin/env python3
"""Does the app ask the terminal for its colours before its first frame, with
the request its host needs, and give back what was typed meanwhile?

`TerminalClient.detectColors(using:)` sends one request at startup: OSC 10
and 11 (the default foreground and background), OSC 4 for the sixteen ANSI
slots except under tmux, and `CSI 5n` as the fence. Whatever the terminal
answers is published to `TerminalColors.current` before `RenderLoop` draws
anything. The unit tests (`TerminalColorStartupTests`) cover the exchange, the
hand-back and what is published. What they cannot see is the WIRING:

  1. the request is sent at all, once, and before the first frame, which must
     wait for the fence: a frame drawn before the answer is a frame drawn with
     the colours unknown;
  2. the request follows the host: no OSC 4 under tmux, where a silent client
     holds the fence about half a second (measured, tmux 3.7c);
  3. a keystroke that arrives among the replies reaches the app;
  4. a terminal that answers the fence alone, or never answers it, still gets
     its first frame.

Runs the real binary under a PTY with a scrubbed environment, answers as each
case's terminal would, and reads the bytes. The first frame is recognised by
the Example header's glyph, as in `identity_smoke.py`. Exit 0 if every case
matches.

What this does NOT check: that frame one is drawn IN the reported colours. No
built-in palette paints a colour the report changes yet, so the bytes are the
same either way; the unit tests pin what is published.

Usage:
  colour_query_smoke.py <binary> [--case NAME|all]
"""
import argparse
import os
import pty
import re
import select
import shutil
import signal
import sys
import tempfile
import time

# Ghostty 1.3.1, default configuration, measured 2026-09-14.
FOREGROUND = (255, 255, 255)
BACKGROUND = (40, 44, 52)
SLOTS = [
    (29, 31, 33), (204, 102, 102), (181, 189, 104), (240, 198, 116),
    (129, 162, 190), (178, 148, 187), (138, 190, 183), (197, 200, 198),
    (102, 102, 102), (213, 78, 83), (185, 202, 74), (231, 197, 71),
    (122, 166, 218), (195, 151, 216), (112, 192, 177), (234, 234, 234),
]

ST = b"\x1b\\"
NATIVE_REQUEST = (
    b"\x1b]10;?" + ST + b"\x1b]11;?" + ST
    + b"".join(b"\x1b]4;%d;?" % n + ST for n in range(16))
    + b"\x1b[5n")
TMUX_REQUEST = b"\x1b]10;?" + ST + b"\x1b]11;?" + ST + b"\x1b[5n"

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM", "COLORFGBG", "STY",
)

GLYPH = "\U0001F5A5".encode()   # 🖥, the Example header's emoji: frame one is up

# An OSC colour query, or any CSI (DSR fences, DA, DECRQM).
QUERY = re.compile(rb"\x1b\](10|11|4;\d+);\?(?:\x1b\\|\x07)|\x1b\[[?>=]?[0-9;]*[$ ]?[a-zA-Z@]")


def spec(rgb):
    return b"rgb:" + b"/".join(b"%02x%02x" % (channel, channel) for channel in rgb)


def colour_reply(code):
    if code == b"10":
        rgb = FOREGROUND
    elif code == b"11":
        rgb = BACKGROUND
    else:
        rgb = SLOTS[int(code.split(b";")[1])]
    return b"\x1b]" + code + b";" + spec(rgb) + ST


# name: (tmux?, answers colours?, answers the 5n fence?, delay before answering,
#        a keystroke to slip in after the first reply, what must hold)
CASES = {
    # Replies held back 0.3 s: frame one must wait for them.
    "answering": (False, True, True, 0.3, None, "request, then frame after the answer"),
    "tmux": (True, True, True, 0.0, None, "no OSC 4 under tmux"),
    "silent": (False, False, True, 0.0, None, "frame drawn after a fence-only answer"),
    "no-fence": (False, True, False, 0.0, None, "frame drawn once the deadline passes"),
    # `q` quits the Example: if it reaches the app, the app exits on its own.
    "keystroke": (False, True, True, 0.0, b"q", "a key among the replies quits the app"),
}


def run(binary, case, config_dir, seconds):
    tmux, answers, fences, delay, key, _ = CASES[case]
    pid, fd = pty.fork()
    if pid == 0:
        for name in STRIPPED:
            os.environ.pop(name, None)
        os.environ["TERM"] = "xterm-256color"
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        if tmux:
            # A socket that does not exist, so the app's tmux commands (its
            # client-change hooks) fail rather than reach a real server.
            os.environ["TMUX"] = os.path.join(config_dir, "no-such-tmux-socket") + ",1,0"
        os.execv(binary, [binary])

    out = b""
    scan = 0
    queued = []          # (when, bytes)
    answered_at = None   # len(out) when the colour exchange was answered
    exited = False
    deadline = time.time() + seconds
    while time.time() < deadline:
        now = time.time()
        for item in [q for q in queued if q[0] <= now]:
            queued.remove(item)
            os.write(fd, item[1])
            if answered_at is None:
                answered_at = len(out)
        readable, _, _ = select.select([fd], [], [], 0.02)
        if readable:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            out += data
            while True:
                match = QUERY.search(out, scan)
                if not match:
                    break
                scan = match.end()
                sequence = match.group(0)
                if match.group(1) is not None:
                    if answers:
                        reply = colour_reply(match.group(1))
                        if key is not None and match.group(1) == b"10":
                            reply += key
                        queued.append((now + delay, reply))
                elif sequence == b"\x1b[5n":
                    if fences:
                        queued.append((now + delay, b"\x1b[0n"))
                elif sequence == b"\x1b[6n":
                    os.write(fd, b"\x1b[1;1R")   # the other exchanges' fence
        waited, _ = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            exited = True
            break
    # An app that quits closes the PTY, which ends the read loop above (EOF, or
    # EIO on Linux) before its `waitpid` runs. So give it a moment to be reaped
    # before calling it still running.
    grace = time.time() + 1.0
    while not exited and time.time() < grace:
        waited, _ = os.waitpid(pid, os.WNOHANG)
        exited = waited == pid
        if not exited:
            time.sleep(0.02)
    if not exited:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        os.waitpid(pid, 0)
    os.close(fd)
    return out, answered_at, exited


def check(case, out, answered_at, exited):
    tmux, answers, fences, delay, key, _ = CASES[case]
    request = TMUX_REQUEST if tmux else NATIVE_REQUEST
    problems = []
    count = out.count(request)
    if count != 1:
        problems.append(f"request sent {count} times")
    if tmux and b"\x1b]4;" in out:
        problems.append("OSC 4 sent under tmux")
    foreground_queries = out.count(b"\x1b]10;?")
    if foreground_queries != 1:
        problems.append(f"OSC 10 asked {foreground_queries} times")
    if key is not None:
        if not exited:
            problems.append("the key among the replies never reached the app")
        return problems
    if exited:
        problems.append("the app exited")
    if GLYPH not in out:
        problems.append("frame one was never drawn")
    elif count == 1 and out.find(GLYPH) < out.find(request):
        problems.append("frame one was drawn before the request")
    if delay and answered_at is not None and GLYPH in out[:answered_at]:
        problems.append("frame one was drawn before the answer arrived")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("--case", default="all", choices=[*CASES, "all"])
    parser.add_argument("--seconds", type=float, default=3.0)
    args = parser.parse_args()

    # A hard stop for the whole run, whatever a case does.
    signal.alarm(120)
    config_dir = tempfile.mkdtemp(prefix="tuikit-colour-query-smoke-", dir=os.environ.get("TMPDIR"))
    failures = 0
    try:
        for case in CASES if args.case == "all" else [args.case]:
            out, answered_at, exited = run(args.binary, case, config_dir, args.seconds)
            problems = check(case, out, answered_at, exited)
            failures += bool(problems)
            print(f"{case:<10} {'FAIL' if problems else 'ok  '} {CASES[case][5]}"
                  + (f": {'; '.join(problems)}" if problems else ""))
    finally:
        shutil.rmtree(config_dir, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
