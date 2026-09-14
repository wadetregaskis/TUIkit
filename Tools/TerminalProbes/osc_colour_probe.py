#!/usr/bin/env python3
"""Colour-query probe: how does THIS terminal answer OSC 10, OSC 11 and OSC 4,
how fast, in what spelling, and in what ORDER against a status-report fence?

`palette_probe.py` records WHAT a terminal says its colours are. This asks the
questions an app has to settle before it can ask the same thing at startup and
in the middle of a session:

  * does every query get an answer, or is the host silent on some of them;
  * how is the reply spelled (`rgb:` or `rgba:`, digits per channel), and is it
    terminated with BEL or ST, whatever the query ended in;
  * how long does it take (an order of magnitude, not a benchmark);
  * can a reply arrive AFTER the fence reply that was sent behind it;
  * does a batch of queries cost one wait or one wait per query, and does the
    multi-pair spelling `OSC 4;0;?;1;?;2;?` work;
  * does anything PRINT.

Non-interactive. Run INSIDE the terminal under test (see `palette_probe.py` for
why a pipe or a private pty cannot stand in for the window). Nothing on the host
is changed: every request is a `?` query, and no colour is ever set. No DECRQM
is sent (Apple Terminal prints the final byte of `CSI ? Ps $ p`), so
`probe_stamp.stamp()` is NOT called; only its environment list and version
reader are reused.

What it sends, in this order:

  1. The pair `OSC 10;? ST OSC 11;? ST` in one write, fenced by `CSI 6n` (cursor
     position report, `CSI r;c R`), then again fenced by `CSI 5n` (status report,
     `CSI 0 n`).
  2. Two batches, each in one write and fenced by `CSI 5n`:
     `batch-native` is the pair plus `OSC 4;n;? ST` for n = 0...15, and
     `batch-multi-pair` is `OSC 4;0;?;1;?;2;? ST`, the spelling xterm documents
     for several slots in one sequence. They run early, so a host that stalls
     on OSC 4 still gets them recorded before the hard limit.
  3. OSC 11 and OSC 10 alone, with ST and with BEL, each fenced by 6n and by 5n.
  4. `CSI ? 996 n` (colour-scheme report request; answer `CSI ? 997 ; 1|2 n`),
     fenced by each.
  5. `OSC 4;n;?` for the sixteen ANSI slots, both terminators, both fences.
  6. A final drain, for anything later still.

For every exchange the record keeps the raw reply bytes with the colour spelling
taken apart; latency on the monotonic clock (from just before the write to the
read that completed the reply, Python's select wake-ups included); whether the
reply came BEFORE or AFTER the fence reply (byte order in the input stream) and
whether in the same read; and whether anything PRINTED: the cursor position is
read before the run and after every exchange, and put back if it moved. Output
that does not move the cursor would go unnoticed.

Environment:

  PROBE_OUT                  JSON path (default ./osc_colour_probe.json)
  PROBE_LABEL                free text stored in the record, e.g. the profile
  PROBE_HARD_LIMIT           seconds before it gives up and writes what it has
                             (default 20)
  PROBE_GRACE_DEFAULT        seconds to wait after the fence for OSC 10/11 and
                             996 (default 0.4, or 0.6 under tmux or screen)
  PROBE_GRACE_OSC4           the same for one OSC 4 (default 0.12)
  PROBE_GRACE_BATCH          the same for the pair and the batches (default 0.8)
  PROBE_FENCE_TIMEOUT        seconds to wait for a fence reply (default 1.0)
  PROBE_BATCH_FENCE_TIMEOUT  the same for the pair and the batches (default 10,
                             so a per-query stall is measured, not cut off)
  PROBE_TMUX                 the tmux binary for the pane context (default: PATH)

Under tmux, when the client OSC 4 is forwarded to does not answer it, every
OSC 4 exchange waits about half a second (tmux 3.7c, measured), so the hard
limit ends the run partway through section 5.

`python3 osc_colour_probe.py --summarise FILE...` prints the compact table for
records already written. `osc_colour_selftest.py` checks this probe against a
scripted terminal; run it after changing anything here.
"""
import datetime
import json
import os
import platform
import re
import select
import shutil
import signal
import statistics
import subprocess
import sys
import termios
import time
import tty

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from probe_stamp import ENV_KEYS, _macos_app_version  # noqa: E402  (no DECRQM: see above)

ST = b"\x1b\\"
BEL = b"\x07"
FENCES = {"6n": b"\x1b[6n", "5n": b"\x1b[5n"}
CPR = re.compile(rb"^\x1b\[(\d+);(\d+)R$")
STATUS = re.compile(rb"^\x1b\[(\d+)n$")
SCHEME = re.compile(rb"^\x1b\[\?997;(\d+)n$")
COLOUR = re.compile(
    rb"^(rgba?):([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)(?:/([0-9a-fA-F]+))?$")

PAIR = b"\x1b]10;?" + ST + b"\x1b]11;?" + ST
MULTI_PAIR = b"\x1b]4;0;?;1;?;2;?" + ST


def slot_queries(slots, terminator=ST):
    """One `OSC 4;n;?` per slot, concatenated."""
    return b"".join(b"\x1b]4;%d;?" % slot + terminator for slot in slots)


# Beyond probe_stamp's list: what names a multiplexer or a host that the stamp
# does not know. Chosen by name, so no session token or URL lands in a record.
EXTRA_ENV_KEYS = ["STY", "WINDOW", "TERM_FEATURES", "WARP_CLIENT_VERSION"]
APP_BUNDLES = {
    "Apple Terminal": "/System/Applications/Utilities/Terminal.app",
    "iTerm2": "/Applications/iTerm.app",
    "Ghostty": "/Applications/Ghostty.app",
    "Warp": "/Applications/Warp.app",
    "Hyper": "/Applications/Hyper.app",
}


def env_seconds(name, default):
    return float(os.environ.get(name, default))


# A multiplexer answers from its own state or forwards to a client, which takes
# longer, so its grace is wider.
MULTIPLEXED = bool(os.environ.get("TMUX") or os.environ.get("STY"))
GRACE_DEFAULT = env_seconds("PROBE_GRACE_DEFAULT", 0.6 if MULTIPLEXED else 0.4)
GRACE_OSC4 = env_seconds("PROBE_GRACE_OSC4", 0.12)
GRACE_BATCH = env_seconds("PROBE_GRACE_BATCH", 0.8)
FENCE_TIMEOUT = env_seconds("PROBE_FENCE_TIMEOUT", 1.0)
BATCH_FENCE_TIMEOUT = env_seconds("PROBE_BATCH_FENCE_TIMEOUT", 10.0)
HARD_LIMIT = env_seconds("PROBE_HARD_LIMIT", 20)
FINAL_DRAIN = 0.8


class HardLimit(Exception):
    pass


def ms(ns):
    return None if ns is None else round(ns / 1e6, 3)


def tokenize(data):
    """Complete control sequences and text runs in `data`: (tokens, consumed)."""
    tokens, i, n = [], 0, len(data)
    while i < n:
        if data[i] == 0x1B:
            if i + 1 >= n:
                break                                   # lone ESC: wait for more
            nxt = data[i + 1]
            if nxt in (0x5D, 0x50, 0x5F, 0x5E, 0x58):  # OSC DCS APC PM SOS
                kind = {0x5D: "osc", 0x50: "dcs", 0x5F: "apc", 0x5E: "pm", 0x58: "sos"}[nxt]
                j, end, term = i + 2, None, None
                while j < n:
                    if data[j] == 0x07:
                        end, term = j + 1, "BEL"
                        break
                    if data[j] == 0x9C:
                        end, term = j + 1, "C1-ST"
                        break
                    if data[j] == 0x1B:
                        if j + 1 >= n:
                            break
                        if data[j + 1] == 0x5C:
                            end, term = j + 2, "ST"
                            break
                    j += 1
                if end is None:
                    break                               # incomplete string
                tokens.append({"kind": kind, "start": i, "end": end, "terminator": term})
                i = end
                continue
            if nxt == 0x5B:
                j = i + 2
                while j < n and not (0x40 <= data[j] <= 0x7E):
                    j += 1
                if j >= n:
                    break                               # incomplete CSI
                tokens.append({"kind": "csi", "start": i, "end": j + 1})
                i = j + 1
                continue
            tokens.append({"kind": "esc", "start": i, "end": i + 2})
            i += 2
            continue
        j = i
        while j < n and data[j] != 0x1B:
            j += 1
        tokens.append({"kind": "text", "start": i, "end": j})
        i = j
    return tokens, i


def colour_spelling(raw, terminator):
    """Takes an OSC reply apart: prefix numbers, rgb:/rgba:, digits, 8-bit values."""
    cut = {"ST": 2, "BEL": 1, "C1-ST": 1}.get(terminator, 0)
    body = raw[2:len(raw) - cut]
    parts = body.split(b";")
    out = {"body": body.decode("latin-1"), "terminator": terminator,
           "numbers": [p.decode("latin-1") for p in parts[:-1]]}
    match = COLOUR.match(parts[-1])
    if not match:
        out["form"] = "unparsed"
        return out
    channels = [g for g in match.groups()[1:] if g is not None]
    out["form"] = match.group(1).decode()
    out["digits_per_channel"] = [len(c) for c in channels]
    out["rgb8"] = [round(int(c, 16) * 255 / (16 ** len(c) - 1)) for c in channels[:3]]
    if len(channels) == 4:
        out["alpha8"] = round(int(channels[3], 16) * 255 / (16 ** len(channels[3]) - 1))
    return out


class Wire:
    """The tty, with every read timestamped so a token knows when it landed."""

    def __init__(self, fd):
        self.fd = fd
        self.data = bytearray()
        self.chunks = []        # (end offset, monotonic ns)
        self.consumed = 0

    def write(self, payload):
        os.write(self.fd, payload)

    def pump(self, deadline_ns):
        timeout = max(0.0, (deadline_ns - time.monotonic_ns()) / 1e9)
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if not ready:
            return False
        got = os.read(self.fd, 4096)
        if got:
            self.data += got
            self.chunks.append((len(self.data), time.monotonic_ns()))
        return bool(got)

    def drain(self, seconds):
        deadline = time.monotonic_ns() + int(seconds * 1e9)
        while time.monotonic_ns() < deadline:
            self.pump(deadline)

    def arrival(self, offset):
        """(chunk index, ns) of the read that delivered byte `offset`."""
        for index, (end, stamp) in enumerate(self.chunks):
            if end > offset:
                return index, stamp
        return None, None

    def pending_tokens(self):
        tokens, used = tokenize(bytes(self.data[self.consumed:]))
        for token in tokens:
            token["start"] += self.consumed
            token["end"] += self.consumed
            token["raw"] = bytes(self.data[token["start"]:token["end"]])
        return tokens, self.consumed + used


def describe(wire, token, t_write):
    first_chunk, first_ns = wire.arrival(token["start"])
    last_chunk, last_ns = wire.arrival(token["end"] - 1)
    out = {"kind": token["kind"], "raw": token["raw"].decode("latin-1"),
           "hex": token["raw"].hex(), "first_byte_ms": ms(first_ns - t_write),
           "complete_ms": ms(last_ns - t_write), "read_index": last_chunk,
           "first_read_index": first_chunk}
    if token.get("terminator"):
        out["terminator"] = token["terminator"]
    if token["kind"] == "osc":
        out["spelling"] = colour_spelling(token["raw"], token["terminator"])
    return out


class Probe:
    """One run's exchanges over one tty."""

    def __init__(self, wire, t0):
        self.wire = wire
        self.t0 = t0
        self.fence_timeouts = {"6n": 0, "5n": 0}
        self.reference = None
        self.exchanges = []
        self.printing_events = []

    def exchange(self, name, request, wanted, fence, grace, fence_timeout=FENCE_TIMEOUT,
                 record=True, extra=None):
        """Writes `request` then `fence`, and reads until the fence reply and every
        `wanted` reply have arrived, until `grace` after the fence reply, or until
        `fence_timeout` with no fence reply at all.

        A fence that has timed out twice is left off later exchanges, so a host
        that never answers one cannot turn every exchange into a timeout."""
        use_fence = fence if fence and self.fence_timeouts.get(fence, 0) < 2 else None
        payload = request + (FENCES[use_fence] if use_fence else b"")
        t_write = time.monotonic_ns()
        self.wire.write(payload)
        found = [None] * len(wanted)
        fence_token = None
        while True:
            tokens, _ = self.wire.pending_tokens()
            for token in tokens:
                if use_fence and fence_token is None:
                    pattern = CPR if use_fence == "6n" else STATUS
                    if pattern.match(token["raw"]):
                        fence_token = token
                        continue
                for index, predicate in enumerate(wanted):
                    if found[index] is None and token is not fence_token and predicate(token):
                        found[index] = token
                        break
            now = time.monotonic_ns()
            done = all(f is not None for f in found)
            if use_fence:
                if fence_token is not None:
                    deadline = self.wire.arrival(fence_token["end"] - 1)[1] + int(grace * 1e9)
                else:
                    deadline = t_write + int(fence_timeout * 1e9)
                    if now >= deadline:
                        self.fence_timeouts[use_fence] += 1
                        break
                if fence_token is not None and (done or now >= deadline):
                    break
            else:
                deadline = t_write + int(grace * 1e9)
                if done or now >= deadline:
                    break
            self.wire.pump(deadline)

        tokens, consumed = self.wire.pending_tokens()
        self.wire.consumed = consumed
        result = {"name": name, "request": payload.decode("latin-1"),
                  "request_hex": payload.hex(), "fence": use_fence or "none",
                  "fence_requested": fence or "none", "grace_s": grace,
                  "t_write_ms": ms(t_write - self.t0)}
        if extra:
            result.update(extra)
        if use_fence:
            if fence_token is None:
                result["fence_reply"] = None
            else:
                result["fence_reply"] = describe(self.wire, fence_token, t_write)
                match = CPR.match(fence_token["raw"])
                if match:
                    result["cursor_after"] = [int(match.group(1)), int(match.group(2))]
        replies = []
        for token in found:
            if token is None:
                replies.append(None)
                continue
            info = describe(self.wire, token, t_write)
            if fence_token is not None:
                info["vs_fence"] = "before" if token["start"] < fence_token["start"] else "after"
                info["same_read_as_fence"] = (
                    self.wire.arrival(token["end"] - 1)[0]
                    == self.wire.arrival(fence_token["end"] - 1)[0])
                if info["vs_fence"] == "after":
                    info["after_fence_by_ms"] = round(
                        info["complete_ms"] - result["fence_reply"]["complete_ms"], 3)
            else:
                info["vs_fence"] = "no fence reply"
            replies.append(info)
        result["replies"] = replies
        # By byte offset: `tokens` was re-parsed, so its dicts are new objects.
        chosen = {(t["start"], t["end"]) for t in found if t is not None}
        if fence_token is not None:
            chosen.add((fence_token["start"], fence_token["end"]))
        result["other_tokens"] = [describe(self.wire, t, t_write)
                                  for t in tokens if (t["start"], t["end"]) not in chosen]
        if record:
            self.check_printing(result)
            self.exchanges.append(result)
        return result

    def position(self):
        result = self.exchange("position", b"", [], "6n", 0.0, record=False)
        return result.get("cursor_after"), result

    def check_printing(self, result):
        if self.reference is None:
            return
        cursor = result.get("cursor_after")
        if cursor is None:
            cursor, probe = self.position()
            result["cursor_check"] = cursor
            if probe.get("other_tokens"):
                result["cursor_check_other_tokens"] = probe["other_tokens"]
        result["printed"] = None if cursor is None else cursor != self.reference
        if result["printed"]:
            self.printing_events.append({"exchange": result["name"],
                                         "reference": self.reference, "cursor": cursor})
            row, col = self.reference
            self.wire.write(b"\x1b[%d;%dH\x1b[J" % (row, col))


def osc_reply(number):
    prefix = b"\x1b]%s;" % number.encode()
    return lambda token: token["kind"] == "osc" and token["raw"].startswith(prefix)


def scheme_reply(token):
    return token["kind"] == "csi" and SCHEME.match(token["raw"]) is not None


def parent_chain():
    """The process ancestry, which names a multiplexer the environment may not."""
    chain, pid = [], os.getpid()
    for _ in range(20):
        try:
            out = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
        except Exception:
            break
        if not out:
            break
        ppid, _, comm = out.partition(" ")
        chain.append({"pid": pid, "comm": comm.strip()})
        pid = int(ppid)
        if pid <= 1:
            break
    return chain


def tmux_context():
    """Who tmux thinks its clients are, when this runs in a pane."""
    if not os.environ.get("TMUX"):
        return None
    tmux = os.environ.get("PROBE_TMUX") or shutil.which("tmux")
    if not tmux:
        return {"error": "tmux is not on PATH; set PROBE_TMUX"}
    fmt = ("#{client_name}|#{client_tty}|#{client_termname}|#{client_termtype}|"
           "#{client_activity}|#{client_created}|#{client_theme}")
    info = {}
    for key, argv in {
        "list_clients": ["list-clients", "-F", fmt],
        "version": ["-V"],
        "pane": ["display", "-p", "#{pane_id} #{window_width}x#{window_height} #{client_name}"],
    }.items():
        try:
            run = subprocess.run([tmux] + argv, capture_output=True, text=True, timeout=3)
            info[key] = run.stdout.strip() + (" ERR:" + run.stderr.strip() if run.stderr.strip() else "")
        except Exception as error:
            info[key] = repr(error)
    return info


def run_exchanges(probe):
    """Sections 1-5 of the module docstring, in order."""
    for fence in ("6n", "5n"):
        probe.exchange("pair", PAIR, [osc_reply("10"), osc_reply("11")], fence, GRACE_BATCH,
                       fence_timeout=BATCH_FENCE_TIMEOUT, extra={"term": "ST"})

    probe.exchange("batch-native", PAIR + slot_queries(range(16)),
                   [osc_reply("10"), osc_reply("11")] + [osc_reply("4;%d" % n) for n in range(16)],
                   "5n", GRACE_BATCH, fence_timeout=BATCH_FENCE_TIMEOUT, extra={"term": "ST"})
    probe.exchange("batch-multi-pair", MULTI_PAIR, [osc_reply("4;%d" % n) for n in range(3)],
                   "5n", GRACE_BATCH, fence_timeout=BATCH_FENCE_TIMEOUT, extra={"term": "ST"})

    for number in ("11", "10"):
        for term_name, term in (("ST", ST), ("BEL", BEL)):
            for fence in ("6n", "5n"):
                probe.exchange("osc" + number, b"\x1b]%s;?" % number.encode() + term,
                               [osc_reply(number)], fence, GRACE_DEFAULT,
                               extra={"term": term_name})

    for fence in ("6n", "5n"):
        probe.exchange("csi?996n", b"\x1b[?996n", [scheme_reply], fence, GRACE_DEFAULT,
                       extra={"term": "-"})

    for slot in range(16):
        for term_name, term in (("ST", ST), ("BEL", BEL)):
            for fence in ("6n", "5n"):
                probe.exchange("osc4", slot_queries([slot], term),
                               [osc_reply("4;%d" % slot)], fence, GRACE_OSC4,
                               extra={"term": term_name, "slot": slot})


def build_summary(result):
    """Compact per-exchange table: answered?, forms, latency, order against the fence."""
    table = {}
    for exchange in result["exchanges"]:
        key = exchange["name"]
        if key == "osc4":
            key = "osc4;%d" % exchange["slot"]
        key += "/" + exchange.get("term", "-") + "/" + exchange["fence"]
        row = {"printed": exchange.get("printed"),
               "fence_ms": (exchange.get("fence_reply") or {}).get("complete_ms")}
        row["replies"] = [None if r is None else {
            "form": r.get("spelling", {}).get("form"),
            "digits": r.get("spelling", {}).get("digits_per_channel"),
            "rgb8": r.get("spelling", {}).get("rgb8"),
            "terminator": r.get("terminator"),
            "ms": r["complete_ms"], "vs_fence": r["vs_fence"],
            "same_read_as_fence": r.get("same_read_as_fence"),
            "raw": r["raw"] if r["kind"] != "osc" else None,
        } for r in exchange["replies"]]
        if exchange["other_tokens"]:
            row["other_tokens"] = [t["raw"] for t in exchange["other_tokens"]]
        table[key] = row
    osc4 = [e for e in result["exchanges"] if e["name"] == "osc4"]
    return {
        "osc4_exchanges": len(osc4),
        "osc4_answered_exchanges": sum(1 for e in osc4 if e["replies"][0] is not None),
        "table": table,
    }


def reply_text(reply):
    if reply is None:
        return "silent"
    spelling = reply.get("spelling")
    order = reply["vs_fence"] + (" same-read" if reply.get("same_read_as_fence") else "")
    if spelling is None:
        return "%r %.2fms %s" % (reply["raw"], reply["complete_ms"], order)
    return "%s %s %s %s %.2fms %s" % (
        spelling.get("form"), spelling.get("digits_per_channel"), reply.get("terminator"),
        spelling.get("rgb8"), reply["complete_ms"], order)


def summary_lines(result):
    lines = ["%s  %s  TERM_PROGRAM=%s %s" % (
        result.get("label") or "", result.get("measured"),
        result["env"].get("TERM_PROGRAM"), result["env"].get("TERM_PROGRAM_VERSION") or "")]
    lines.append("elapsed %ss, hard limit hit: %s, fence timeouts %s, printing events %d" % (
        result.get("elapsed_s"), result.get("hard_limit_hit"), result.get("fence_timeouts"),
        len(result.get("printing_events", []))))
    slots = {}
    for exchange in result["exchanges"]:
        fence_ms = (exchange.get("fence_reply") or {}).get("complete_ms")
        if exchange["name"] == "osc4":
            slots.setdefault(exchange["slot"], []).append(exchange)
            continue
        if exchange["name"].startswith("batch-"):
            answered = sum(1 for r in exchange["replies"] if r is not None)
            lines.append("%-17s %-3s fence %sms: %d of %d answered" % (
                exchange["name"], exchange["fence"], fence_ms, answered, len(exchange["replies"])))
            continue
        lines.append("%-17s %-3s %-3s fence %sms: %s" % (
            exchange["name"], exchange.get("term", ""), exchange["fence"], fence_ms,
            "; ".join(reply_text(r) for r in exchange["replies"])))
    for slot, exchanges in sorted(slots.items()):
        answers = [e["replies"][0] for e in exchanges if e["replies"][0] is not None]
        fences = [(e.get("fence_reply") or {}).get("complete_ms") for e in exchanges]
        fences = [f for f in fences if f is not None]
        lines.append("osc4;%-2d answered %d of %d, rgb8 %s, terminators %s, fence median %sms" % (
            slot, len(answers), len(exchanges),
            sorted({tuple(a.get("spelling", {}).get("rgb8") or ()) for a in answers}),
            sorted({a.get("terminator") for a in answers}),
            round(statistics.median(fences), 3) if fences else None))
    return lines


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--summarise":
        for path in sys.argv[2:]:
            with open(path) as handle:
                print("== " + path)
                for line in summary_lines(json.load(handle)):
                    print(line)
        return

    out_path = os.environ.get("PROBE_OUT", "osc_colour_probe.json")
    label = os.environ.get("PROBE_LABEL", "")
    result = {
        "probe": "osc_colour_probe",
        "label": label,
        "measured": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "os": platform.system() + " " + platform.release(),
        "machine": platform.machine(),
        "env": {k: os.environ.get(k) for k in ENV_KEYS if os.environ.get(k) is not None},
        "env_extra": {k: os.environ.get(k) for k in EXTRA_ENV_KEYS if os.environ.get(k) is not None},
        "screen": "primary",
        "method": "raw-mode tty; every OSC is a `?` query; fences CSI 6n / CSI 5n; "
                  "printing = cursor position differs from the reference after an exchange",
        "grace_s": {"osc10_11": GRACE_DEFAULT, "osc4": GRACE_OSC4, "batch": GRACE_BATCH,
                    "fence_timeout": FENCE_TIMEOUT, "batch_fence_timeout": BATCH_FENCE_TIMEOUT},
    }
    if platform.system() == "Darwin":
        try:
            result["os"] = "macOS " + subprocess.run(
                ["sw_vers", "-productVersion"], capture_output=True, text=True,
                timeout=5).stdout.strip()
        except Exception:
            pass
        # CFBundleVersion, which for some hosts is a build number, not the marketing version.
        result["app_bundle_versions"] = {
            name: _macos_app_version(path) for name, path in APP_BUNDLES.items()}
    result["parent_chain"] = parent_chain()
    result["tmux"] = tmux_context()

    fd = os.open("/dev/tty", os.O_RDWR)
    result["tty"] = os.ttyname(fd)
    try:
        size = os.get_terminal_size(fd)
        result["winsize"] = [size.columns, size.lines]
    except OSError:
        pass
    saved = termios.tcgetattr(fd)

    def on_alarm(signum, frame):
        raise HardLimit()

    signal.signal(signal.SIGALRM, on_alarm)
    t0 = time.monotonic_ns()
    probe = Probe(Wire(fd), t0)
    result["t0_wall"] = time.time()   # anchor for correlating with other processes' logs
    result["hard_limit_hit"] = False
    try:
        signal.setitimer(signal.ITIMER_REAL, HARD_LIMIT)
        tty.setraw(fd)

        # Whatever was already queued (a keypress, a late startup reply).
        probe.wire.drain(0.25)
        tokens, consumed = probe.wire.pending_tokens()
        result["pre_existing_input"] = [t["raw"].decode("latin-1") for t in tokens]
        probe.wire.consumed = consumed

        probe.wire.write(b"\x1b[H\x1b[2J osc_colour_probe: " + label.encode() +
                         b" (queries only; nothing is set)\r\n\r\n")
        probe.reference, reference_probe = probe.position()
        result["reference_cursor"] = probe.reference
        result["reference_probe"] = reference_probe

        run_exchanges(probe)

        probe.wire.drain(FINAL_DRAIN)
        tokens, consumed = probe.wire.pending_tokens()
        result["late_drain"] = [describe(probe.wire, t, t0) for t in tokens]
        probe.wire.consumed = consumed
    except HardLimit:
        result["hard_limit_hit"] = True
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        finally:
            subprocess.run(["stty", "sane"], stdin=fd, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=5)
        result["elapsed_s"] = round((time.monotonic_ns() - t0) / 1e9, 3)
        result["fence_timeouts"] = probe.fence_timeouts
        result["exchanges"] = probe.exchanges
        result["printing_events"] = probe.printing_events
        result["unparsed_tail_hex"] = bytes(probe.wire.data[probe.wire.consumed:]).hex()
        result["summary"] = build_summary(result)
        with open(out_path, "w") as handle:
            json.dump(result, handle, indent=1)
        os.close(fd)

    print("\r")
    for line in summary_lines(result):
        print(line)
    print("written to " + out_path)


if __name__ == "__main__":
    main()
