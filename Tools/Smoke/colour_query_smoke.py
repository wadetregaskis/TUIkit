#!/usr/bin/env python3
"""Does the app ask the terminal for its colours before its first frame, with
the request its host needs, give back what was typed meanwhile, and leave a
clear page to the terminal?

`TerminalClient.detectColors(using:)` sends one request at startup: OSC 10
and 11 (the default foreground and background), OSC 4 for the sixteen ANSI
slots except under tmux, and `CSI 5n` as the fence. Whatever the terminal
answers is published to `TerminalColors.current` before `RenderLoop` draws
anything. Under tmux the sixteen slots are asked for once frame one is out
instead (`TerminalColorRequester`), in a request of their own that nothing
waits for. The unit tests (`TerminalColorStartupTests`,
`TerminalColorRequesterTests`, `TerminalColorRequestWiringTests`) cover the
exchange, the hand-back, what is published and when the slots are asked;
`GroundedPaletteTerminalTests` covers how a translucent ground is spent
against it. What they cannot see is the WIRING:

  1. the request is sent at all, once, and before the first frame, which must
     wait for the fence: a frame drawn before the answer is a frame drawn with
     the colours unknown;
  2. the request follows the host. Off tmux the sixteen OSC 4 queries are in
     it. Under tmux they are not, because a silent client holds the fence
     about half a second (measured, tmux 3.7c); they follow frame one instead,
     where that half second holds up nothing that draws. So in a run where
     the screen is never thrown away (a resize, a resumed suspend, a tmux
     client change), the focus never comes back and the terminal never
     reports its theme, which is every run here, OSC 4 is asked sixteen times
     on any host: off tmux in the startup request, under tmux once after
     frame one and never before it. Each of those three asks the whole
     request again, OSC 4 included (`TerminalColorRequester`), so outside
     such a run neither "once" holds. Not "no OSC 4 under tmux": that was this
     check's rule, and it stopped being the app's when the post-frame request
     landed (2026-09-15);
  3. a keystroke that arrives among the replies reaches the app;
  4. a terminal that answers the fence alone, or never answers it, still gets
     its first frame;
  5. frame one of an app whose grounds are clear clears every row on SGR 49,
     the terminal's own background, never an RGB ground: when the terminal has
     reported its page (#282c34, which a clear ground must not paint either)
     and when it has reported nothing.

Runs the real binary under a PTY with a scrubbed environment, answers as each
case's terminal would, and reads the bytes. The first frame is recognised by
the Example header's glyph, as in `identity_smoke.py`. Exit 0 if every case
matches.

The clear grounds come from the Example's `TUIKIT_EXAMPLE_GROUND_ALPHA` seam at
0, which fades its page, app header, status bar and overlay to alpha 0. That is
not `.clear` spelled as such (black at alpha 0) but the green preset's own
grounds at alpha 0, and grounding treats the two alike: a root at alpha 0 is
the terminal's page. Before grounding each was painted as its own RGB, so
`.clear` came out `48;2;0;0;0` and this page `48;2;5;10;5`; the check therefore
rejects any ground on a frame-one row but 49, and black anywhere in frame one.
`COLORTERM=truecolor` makes a painted ground spell as RGB, as it did then.

What this does NOT check: that the rest of frame one is drawn in the reported
colours. No built-in palette paints a colour the report changes, so those bytes
are the same either way; the unit tests pin what is published and grounded.

Usage:
  colour_query_smoke.py <binary> [--case NAME|all]
"""
import argparse
import collections
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
# Spelled as `TerminalColorQuery` composes them: the pair, the sixteen slot
# queries, and the fence.
PAIR_QUERIES = b"\x1b]10;?" + ST + b"\x1b]11;?" + ST
SLOT_QUERIES = b"".join(b"\x1b]4;%d;?" % n + ST for n in range(16))
FENCE = b"\x1b[5n"
NATIVE_REQUEST = PAIR_QUERIES + SLOT_QUERIES + FENCE
TMUX_REQUEST = PAIR_QUERIES + FENCE
# What follows frame one under tmux, and only there.
SLOTS_REQUEST = SLOT_QUERIES + FENCE
OSC_4 = b"\x1b]4;"

STRIPPED = (
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "TUIKIT_TERM_PROGRAM", "COLORFGBG", "STY",
)

GLYPH = "\U0001F5A5".encode()   # 🖥, the Example header's emoji: frame one is up

# An OSC colour query, or any CSI (DSR fences, DA, DECRQM).
QUERY = re.compile(rb"\x1b\](10|11|4;\d+);\?(?:\x1b\\|\x07)|\x1b\[[?>=]?[0-9;]*[$ ]?[a-zA-Z@]")

# A full frame starts each row at its first column, sets the row's ground and
# erases the line in it (EL paints the current background), so the SGRs between
# the cursor move and `CSI 2K` say what the row was cleared on.
ROW_CLEAR = re.compile(rb"\x1b\[(\d+);1H((?:\x1b\[[0-9;]*m)*)\x1b\[2K")
SGR = re.compile(rb"\x1b\[([0-9;]*)m")
BLACK_GROUND = re.compile(rb"[\[;]48;2;0;0;0[;m]")

# Every ground at alpha 0, and a terminal that takes RGB (see the docstring).
CLEAR_GROUNDS = {"TUIKIT_EXAMPLE_GROUND_ALPHA": "0", "COLORTERM": "truecolor"}


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
#        a keystroke to slip in after the first reply, extra environment,
#        what must hold)
CASES = {
    # Replies held back 0.3 s: frame one must wait for them.
    "answering": (False, True, True, 0.3, None, {}, "request, then frame after the answer"),
    "tmux": (True, True, True, 0.0, None, {},
             "under tmux the slots are asked once, after frame one"),
    "silent": (False, False, True, 0.0, None, {}, "frame drawn after a fence-only answer"),
    "no-fence": (False, True, False, 0.0, None, {}, "frame drawn once the deadline passes"),
    # `q` quits the Example: if it reaches the app, the app exits on its own.
    "keystroke": (False, True, True, 0.0, b"q", {}, "a key among the replies quits the app"),
    # Held back too, so frame one is provably drawn with the page reported.
    "clear-answering": (False, True, True, 0.3, None, CLEAR_GROUNDS,
                        "clear grounds over a reported page: frame one clears on 49"),
    "clear-silent": (False, False, True, 0.0, None, CLEAR_GROUNDS,
                     "clear grounds, nothing reported: frame one clears on 49"),
    "clear-keystroke": (False, True, True, 0.0, b"q", CLEAR_GROUNDS,
                        "clear grounds: a key among the replies quits the app"),
}


def run(binary, case, config_dir, seconds):
    tmux, answers, fences, delay, key, environment, _ = CASES[case]
    pid, fd = pty.fork()
    if pid == 0:
        for name in STRIPPED:
            os.environ.pop(name, None)
        os.environ["TERM"] = "xterm-256color"
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        os.environ.update(environment)
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


def ground(sgrs):
    """The background the SGR sequences `sgrs` leave set: `49`, a reset (`0`),
    the colour's own spelling (`48;2;5;10;5`, `48;5;16`, `44`), or None."""
    current = None
    for parameters in SGR.findall(sgrs):
        values = [int(value) if value else 0 for value in parameters.split(b";")]
        index = 0
        while index < len(values):
            value = values[index]
            if value in (38, 48):
                # An extended colour's operands are not attributes of their own.
                mode = values[index + 1] if index + 1 < len(values) else None
                width = 3 if mode == 5 else 5 if mode == 2 else 1
                if value == 48:
                    current = ";".join(str(v) for v in values[index:index + width])
                index += width
                continue
            if value in (0, 49) or 40 <= value <= 47 or 100 <= value <= 107:
                current = str(value)
            index += 1
    return current


def frame_one_rows(out, start):
    """Each row of the first full frame after `start`, mapped to the ground it
    was cleared on, and where that frame ends (the next frame's first repeat)."""
    rows = {}
    for match in ROW_CLEAR.finditer(out, start):
        row = int(match.group(1))
        if row in rows:
            return rows, match.start()
        rows[row] = ground(match.group(2))
    return rows, len(out)


def check_clear_grounds(out, start):
    problems = []
    rows, end = frame_one_rows(out, start)
    if len(rows) < 3 or sorted(rows) != list(range(1, len(rows) + 1)):
        problems.append(f"frame one cleared rows {sorted(rows)}, not 1 to n")
    painted = collections.Counter(spelling for spelling in rows.values() if spelling != "49")
    if painted:
        problems.append("frame one cleared " + ", ".join(
            f"{count} rows on {spelling}" for spelling, count in painted.most_common())
            + f" of {len(rows)}, not 49")
    if BLACK_GROUND.search(out, start, end):
        problems.append("frame one paints a 48;2;0;0;0 ground")
    return problems


def check(case, out, answered_at, exited):
    tmux, answers, fences, delay, key, environment, _ = CASES[case]
    request = TMUX_REQUEST if tmux else NATIVE_REQUEST
    problems = []
    count = out.count(request)
    if count != 1:
        problems.append(f"request sent {count} times")
    # Sixteen slot queries whatever the host: off tmux they are the startup
    # request's (counted once above), under tmux the post-frame request's.
    # Thirty-two under tmux would also be the post-frame request sent a second
    # time, which the requester does when its fence is not back within a
    # second (`TerminalColorRequester.defaultFenceTimeoutNanos`); this smoke
    # answers that fence at once, so a resend is not expected here.
    slot_queries = out.count(OSC_4)
    if slot_queries != len(SLOTS):
        problems.append(f"OSC 4 asked {slot_queries} times, not {len(SLOTS)}")
    if tmux:
        # The startup request left the slots out: they follow frame one, once.
        frame_one = out.find(GLYPH)
        first_slot = out.find(OSC_4)
        if first_slot != -1 and not 0 <= frame_one < first_slot:
            problems.append("OSC 4 sent under tmux before frame one")
        # The whole request ends in the same sixteen queries and fence, so one
        # after frame one is counted as that, not as a second slots request.
        after = out[frame_one:] if frame_one != -1 else b""
        whole = after.count(NATIVE_REQUEST)
        slots = after.count(SLOTS_REQUEST) - whole
        if slots != 1:
            problems.append(f"slots request sent {slots} times after frame one, not once")
        if whole:
            problems.append(f"whole request sent {whole} times after frame one")
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
    if environment == CLEAR_GROUNDS and GLYPH in out and count == 1:
        problems += check_clear_grounds(out, out.find(request) + len(request))
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
            print(f"{case:<15} {'FAIL' if problems else 'ok  '} {CASES[case][6]}"
                  + (f": {'; '.join(problems)}" if problems else ""))
    finally:
        shutil.rmtree(config_dir, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
