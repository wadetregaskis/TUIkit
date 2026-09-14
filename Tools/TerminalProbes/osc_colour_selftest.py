#!/usr/bin/env python3
"""Self-test for osc_colour_probe.py, against a scripted terminal on a pty.

NOT a measurement of any host. The master side of a pty plays a terminal, the
probe runs on the slave side, and the record it writes is checked. One run per
mode:

  answering  replies to OSC 10, 11 and 4 (`rgb:`, 4 digits, echoing the query's
             terminator), to `?996n`, and to both fences
  bel        the same, but always terminates with BEL, as Apple Terminal 455.1
             was measured to
  late       holds each OSC reply until 30 ms after the next fence reply
  silent     answers only the fences
  printing   answers, and moves the cursor for `?996n` as a host that printed
             the query would

Neither mode parses the multi-pair spelling, so `batch-multi-pair` is expected
silent throughout. Exits 1 if any check fails.

    python3 osc_colour_selftest.py              # every mode, about 20 s
    python3 osc_colour_selftest.py late silent
"""
import fcntl
import json
import os
import pty
import re
import select
import struct
import sys
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROBE = os.path.join(HERE, "osc_colour_probe.py")
MODES = ("answering", "bel", "late", "silent", "printing")
RGB = b"2828/2c2c/3434"
RGB8 = [40, 44, 52]
LATE_BY = 0.03
QUERY = re.compile(
    rb"\x1b\](10|11|4;\d+);\?(\x07|\x1b\\)"   # 1, 2: one OSC colour query
    rb"|\x1b\[(\?996|6|5)n"                   # 3: scheme report, CPR, status report
    rb"|\x1b\[(\d+);(\d+)H"                   # 4, 5: the probe putting the cursor back
)
# pair x2, two batches, OSC 11 and 10 x 2 terminators x 2 fences, 996 x2, 16 slots x 4.
EXPECTED_EXCHANGES = 2 + 2 + 8 + 2 + 64


def play(mode, out_path):
    """Runs the probe against a terminal scripted as `mode`; returns its record."""
    pid, master = pty.fork()
    if pid == 0:
        env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "STY")}
        env.update(PROBE_OUT=out_path, PROBE_LABEL="selftest-" + mode, TERM_PROGRAM="selftest",
                   PROBE_HARD_LIMIT="40", PROBE_GRACE_DEFAULT="0.15", PROBE_GRACE_OSC4="0.1",
                   PROBE_GRACE_BATCH="0.2")
        os.execve(sys.executable, [sys.executable, PROBE], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    row, col = 3, 1
    buffer = b""
    held = []
    deadline = time.time() + 90
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if not ready:
            continue
        try:
            data = os.read(master, 65536)
        except OSError:
            break                                  # the probe exited and closed the pty
        if not data:
            break
        buffer += data
        end = 0
        for match in QUERY.finditer(buffer):
            end = match.end()
            if match.group(1):
                if mode == "silent":
                    continue
                terminator = b"\x07" if mode == "bel" else match.group(2)
                reply = b"\x1b]" + match.group(1) + b";rgb:" + RGB + terminator
                if mode == "late":
                    held.append(reply)
                else:
                    os.write(master, reply)
            elif match.group(3):
                kind = match.group(3)
                if kind == b"?996":
                    if mode == "printing":
                        col += 1
                    elif mode != "silent":
                        os.write(master, b"\x1b[?997;1n")
                    continue
                os.write(master, b"\x1b[%d;%dR" % (row, col) if kind == b"6" else b"\x1b[0n")
                if held:
                    time.sleep(LATE_BY)
                    os.write(master, b"".join(held))
                    held = []
            else:
                row, col = int(match.group(4)), int(match.group(5))
        buffer = buffer[end:][-64:]
    os.waitpid(pid, 0)
    os.close(master)
    with open(out_path) as handle:
        return json.load(handle)


def check(mode, record):
    """Every way the record disagrees with what the scripted terminal did."""
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    exchanges = record["exchanges"]
    expect(not record["hard_limit_hit"], "hit the hard limit")
    expect(record["fence_timeouts"] == {"6n": 0, "5n": 0},
           "fence timeouts %s" % record["fence_timeouts"])
    expect(len(exchanges) == EXPECTED_EXCHANGES,
           "%d exchanges, expected %d" % (len(exchanges), EXPECTED_EXCHANGES))
    expect(record["late_drain"] == [], "late drain %s" % record["late_drain"])
    expect(record["unparsed_tail_hex"] == "", "unparsed tail %s" % record["unparsed_tail_hex"])

    answers = mode != "silent"
    for exchange in exchanges:
        name = "%s/%s/%s" % (exchange["name"], exchange.get("term"), exchange["fence"])
        expect(exchange["other_tokens"] == [], "%s: stray tokens %s" % (name, exchange["other_tokens"]))
        for reply in exchange["replies"]:
            if exchange["name"] == "batch-multi-pair":
                expect(reply is None, "%s: answered a spelling the script does not parse" % name)
                continue
            if exchange["name"] == "csi?996n":
                expect((reply is not None) == (answers and mode != "printing"),
                       "%s: %s" % (name, "answered" if reply else "silent"))
                continue
            expect((reply is not None) == answers, "%s: %s" % (name, "answered" if reply else "silent"))
            if reply is None:
                continue
            spelling = reply["spelling"]
            expect(spelling.get("form") == "rgb" and spelling.get("digits_per_channel") == [4, 4, 4]
                   and spelling.get("rgb8") == RGB8, "%s: spelling %s" % (name, spelling))
            wanted_terminator = "BEL" if mode == "bel" else exchange["term"]
            expect(reply["terminator"] == wanted_terminator,
                   "%s: terminator %s, expected %s" % (name, reply["terminator"], wanted_terminator))
            wanted_order = "after" if mode == "late" else "before"
            expect(reply["vs_fence"] == wanted_order,
                   "%s: %s the fence, expected %s" % (name, reply["vs_fence"], wanted_order))

    printed = sorted({event["exchange"] for event in record["printing_events"]})
    wanted_printed = ["csi?996n"] if mode == "printing" else []
    expect(printed == wanted_printed, "printing events in %s, expected %s" % (printed, wanted_printed))
    return failures


def main():
    modes = sys.argv[1:] or list(MODES)
    unknown = [mode for mode in modes if mode not in MODES]
    if unknown:
        raise SystemExit("unknown mode(s) %s; choose from %s" % (unknown, ", ".join(MODES)))
    failed = False
    with tempfile.TemporaryDirectory(prefix="osc_colour_selftest-") as directory:
        for mode in modes:
            started = time.time()
            record = play(mode, os.path.join(directory, mode + ".json"))
            failures = check(mode, record)
            failed = failed or bool(failures)
            print("%-9s %s in %.1fs" % (mode, "FAIL" if failures else "ok", time.time() - started))
            for failure in failures:
                print("    " + failure)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
