#!/usr/bin/env python3
"""Self-test for `PROBE_SUITE=m3m7` in this directory's osc_colour_probe.py.

NOT a measurement of any host. The master side of a pty plays a scripted
terminal, the probe runs on the slave side, and its record is checked:

  clean     answers 6n/5n, DECRQM (tracks ?2031; ?25 is set), DECRQSS, and sends
            `CSI ?997;1n` on each 2031 reset->set transition; prints nothing
  apple     answers 6n/5n only; PRINTS the final byte of any CSI carrying both
            `?` and an intermediate (the measured Apple Terminal rule) and prints
            a DCS payload; run with TERM_PROGRAM=Apple_Terminal
  sgrprint  as clean, but the 997 is 0.3 s late, and any SGR containing `38;2`
            advances the cursor 3 cells (a host that printed part of it)

Exits 1 if any check fails.
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
MODES = ("clean", "apple", "sgrprint")


class Fake:
    def __init__(self, mode):
        self.mode = mode
        self.row, self.col = 1, 1
        self.m2031 = False
        self.pending = []          # (due monotonic, bytes)
        self.dcs_seen = []
        self.buf = b""

    def reply(self, data, delay=0.0):
        self.pending.append((time.monotonic() + delay, data))

    def csi(self, body, final):
        inter = bytes(c for c in body if 0x20 <= c <= 0x2F)
        priv = body.startswith(b"?")
        params = bytes(c for c in body if not (0x20 <= c <= 0x2F)).lstrip(b"?")
        if self.mode == "apple" and priv and inter:
            self.col += 1
            return
        f = chr(final)
        if f == "H":
            parts = (params.split(b";") + [b"", b""])[:2]
            self.row = int(parts[0] or 1)
            self.col = int(parts[1] or 1)
        elif f == "n" and not priv:
            if params == b"6":
                self.reply(b"\x1b[%d;%dR" % (self.row, self.col))
            elif params == b"5":
                self.reply(b"\x1b[0n")
        elif f in "hl" and priv and params == b"2031" and not inter:
            new = f == "h"
            if self.mode != "apple" and new and not self.m2031:
                self.reply(b"\x1b[?997;1n", 0.3 if self.mode == "sgrprint" else 0.0)
            self.m2031 = new
        elif f == "p" and priv and inter == b"$":
            mode = int(params)
            value = {2031: 1 if self.m2031 else 2, 25: 1}.get(mode, 0)
            self.reply(b"\x1b[?%d;%d$y" % (mode, value))
        elif f == "m" and self.mode == "sgrprint" and b"38;2" in params:
            self.col += 3

    def feed(self, data):
        self.buf += data
        b, i, n = self.buf, 0, len(self.buf)
        while i < n:
            c = b[i]
            if c == 0x1B:
                if i + 1 >= n:
                    break
                nxt = b[i + 1]
                if nxt == 0x5B:
                    j = i + 2
                    while j < n and not (0x40 <= b[j] <= 0x7E):
                        j += 1
                    if j >= n:
                        break
                    self.csi(b[i + 2:j], b[j])
                    i = j + 1
                    continue
                if nxt in (0x5D, 0x50):
                    j, end, payload_end = i + 2, None, None
                    while j < n:
                        if b[j] == 0x07:
                            end, payload_end = j + 1, j
                            break
                        if b[j] == 0x1B and j + 1 < n and b[j + 1] == 0x5C:
                            end, payload_end = j + 2, j
                            break
                        j += 1
                    if end is None:
                        break
                    if nxt == 0x50:
                        payload = b[i + 2:payload_end]
                        self.dcs_seen.append(payload)
                        if self.mode == "apple":
                            self.col += len(payload)
                        elif payload == b"$qm":
                            self.reply(b"\x1bP1$r0;7m\x1b\\")
                    i = end
                    continue
                i += 2
                continue
            if c == 0x0D:
                self.col = 1
            elif c == 0x0A:
                self.row += 1
            elif c >= 0x20:
                self.col += 1
            i += 1
        self.buf = b[i:]


def play(mode, out_path):
    pid, master = pty.fork()
    if pid == 0:
        env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "STY")}
        env.update(PROBE_OUT=out_path, PROBE_LABEL="selftest-" + mode, PROBE_SUITE="m3m7",
                   TERM_PROGRAM="Apple_Terminal" if mode == "apple" else "selftest",
                   PROBE_HARD_LIMIT="60", PROBE_GRACE_DEFAULT="0.15", PROBE_GRACE_997="0.5")
        os.execve(sys.executable, [sys.executable, PROBE], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    fake = Fake(mode)
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        now = time.monotonic()
        due = [p for p in fake.pending if p[0] <= now]
        fake.pending = [p for p in fake.pending if p[0] > now]
        for _, data in sorted(due):
            os.write(master, data)
        timeout = 0.02 if fake.pending else 0.1
        ready, _, _ = select.select([master], [], [], timeout)
        if not ready:
            continue
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        fake.feed(data)
    os.waitpid(pid, 0)
    with open(out_path) as handle:
        return json.load(handle), fake


def check(mode, record, fake):
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    steps = {e["step"]: e for e in record["exchanges"]}
    expect(len(steps) == len(record["exchanges"]), "step ids are not unique")
    expect(not record["hard_limit_hit"], "hard limit hit")
    expect(record["unparsed_tail_hex"] == "", "unparsed tail")
    rqm = lambda s: (steps[s]["replies"][0] or {}).get("raw")
    printed = {s: e.get("printed") for s, e in steps.items()}
    expect(all(v is not None for v in printed.values()), "a printing check was skipped: %s"
           % [s for s, v in printed.items() if v is None])

    if mode == "clean":
        expect(not any(printed.values()), "clean printed: %s" % [s for s, v in printed.items() if v])
        expect(rqm("m3-h-nofence") == "\x1b[?997;1n", "no 997 on first enable")
        expect(steps["m3-h-again-6n"]["replies"][0] is None, "997 on re-enable")
        expect(rqm("m3-h-6n") == "\x1b[?997;1n", "no 997 on 6n enable")
        expect(rqm("rqm-2031-reset-6n") == "\x1b[?2031;2$y", "reset rqm")
        expect(rqm("rqm-2031-reset-5n") == "\x1b[?2031;2$y", "reset rqm 5n")
        expect(rqm("rqm-25-control-6n") == "\x1b[?25;1$y", "control rqm")
        expect(rqm("rqm-2031-set-6n") == "\x1b[?2031;1$y", "set rqm")
        expect(rqm("rqm-2031-after-reset-6n") == "\x1b[?2031;2$y", "after-reset rqm")
        expect(rqm("m7-D-decrqss-6n") == "\x1bP1$r0;7m\x1b\\", "decrqss")
        expect(steps["m7-B-sgr-text-reset-6n"]["cursor_delta"] == [0, 2], "text advance")
    elif mode == "apple":
        for s, e in steps.items():
            if s.startswith("rqm-"):
                expect(e["printed"] is True and e["cursor_delta"] == [0, 1],
                       "apple %s: printed %s delta %s" % (s, e["printed"], e.get("cursor_delta")))
            else:
                expect(e["printed"] is False, "apple %s printed" % s)
        expect(not any(s.endswith("decrqss-6n") for s in steps), "decrqss asked of Apple Terminal")
        expect(fake.dcs_seen == [], "a DCS reached the apple fake")
        expect(record["summary"]["scheme_reports"] == [], "997 seen from apple")
    elif mode == "sgrprint":
        bad = {s for s, v in printed.items() if v}
        expect(bad == {"m7-D-sgr-6n", "m7-D-sgr-text-reset-6n"}, "sgrprint printed set: %s" % bad)
        expect(steps["m7-D-sgr-6n"]["cursor_delta"] == [0, 3], "sgrprint delta")
        expect(steps["m7-D-sgr-text-reset-6n"]["cursor_delta"] == [0, 5], "sgrprint text delta")
        expect(rqm("m3-h-nofence") == "\x1b[?997;1n", "late 997 missed")
    return failures


def main():
    modes = sys.argv[1:] or MODES
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        for mode in modes:
            record, fake = play(mode, os.path.join(tmp, mode + ".json"))
            failures = check(mode, record, fake)
            total += len(failures)
            print("%-9s %s (%d exchanges, %.1fs)" % (
                mode, "ok" if not failures else "FAIL", len(record["exchanges"]),
                record["elapsed_s"]))
            for failure in failures:
                print("   - " + failure)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
