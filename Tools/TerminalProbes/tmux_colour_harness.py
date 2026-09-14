#!/usr/bin/env python3
"""What tmux does with a pane's colour queries, measured against SCRIPTED clients.

Real tmux, on a private socket with no configuration (`-f /dev/null`). Each
client is `tmux attach` on a pty whose master side this script plays, so the
client's answers are known and every query tmux forwards to it is logged with
the time it arrived. This measures tmux, not any emulator: what a real terminal
answers is `osc_colour_probe.py`'s question, run in that terminal.

Two experiments:

  clients [--order AB|BA]
      Two clients with deliberately different answers:

        client  foreground  background  OSC 4                      its ?996n
        A       ffffff      000000      answers, slot n is grey n  997;1 (dark)
        B       abb2bf      282c34      silent                     997;2 (light,
                                                                   contradicting
                                                                   its own dark
                                                                   background)

      The pane runs `osc_colour_probe.py` four times: the first client alone;
      both, with the second attached last; both, after the first typed a key;
      the first alone, after the second detached. The summary says whose OSC
      10/11 the pane saw, how many OSC 4 were answered, what tmux answered to
      `?996n`, and which client each OSC 4 was forwarded to. Run both orders:
      "first attached" and "most recently attached" are only told apart by
      swapping them.

  batch [--client answering|silent]
      One client with B's colours and a scheme report that matches them, which
      answers OSC 4 or not. The pane writes four batches, each in one write
      fenced by `CSI 5n`, and prints a marker line straight after each:

        startup-native  OSC 10, OSC 11, OSC 4;n for n = 0...15
        startup-tmux    OSC 10, OSC 11
        one-slot        OSC 4;1
        multi-pair      OSC 4;0;?;1;?;2;?

      Per batch: when the fence reply reached the pane and what came back with
      it; when the marker reached the client, which says whether tmux holds a
      pane's OUTPUT while a query of its is pending; and what tmux forwarded to
      the client.

Records go to $PROBE_OUT_DIR (default ./tmux_colour_harness): the probe records
and the client log for `clients`, one JSON for `batch`. tmux comes from PATH or
$PROBE_TMUX. The socket is named after this process and killed at the end, and
no other tmux server is touched. Timestamps that cross processes are wall-clock
(`time.time()`), all on this machine.

    PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py clients --order AB
    PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py clients --order BA
    PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py batch --client silent
    PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py batch --client answering

A `clients` order takes about a minute and a half when the probe's forwarded OSC
4 go to the silent client, because each probe run then ends at its 20 s limit.
"""
import argparse
import fcntl
import json
import os
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tty

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from osc_colour_probe import MULTI_PAIR, PAIR, slot_queries  # noqa: E402

PROBE = os.path.join(HERE, "osc_colour_probe.py")
SESSION = "colour"
PANE_COLUMNS, PANE_ROWS = 100, 29
LATE_DRAIN = 0.8
BATCHES = [
    ("startup-native", PAIR + slot_queries(range(16))),
    ("startup-tmux", PAIR),
    ("one-slot", slot_queries([1])),
    ("multi-pair", MULTI_PAIR),
]

QUERY = re.compile(
    rb"\x1b\]((?:10|11|12);\?|4(?:;\d+;\?)+)(\x07|\x1b\\)"  # 1, 2: OSC colour query, any number of OSC 4 pairs
    rb"|\x1b\[\?996n"                                        # colour-scheme report request
    rb"|\x1b\[([>=]?)0?c"                                    # 3: DA1 / DA2 / DA3
    rb"|\x1b\[>0?q"                                          # XTVERSION
    rb"|\x1b\[([56])n"                                       # 4: DSR
    rb"|\x1b\[\?(\d+)\$p"                                    # 5: DECRQM
    rb"|\x1bP\+q([0-9a-fA-F;]*)\x1b\\"                       # 6: XTGETTCAP
    rb"|\x1b\[\?(2031|1004|2004|996|997)[hl]"                # 7: modes worth logging; never answered
)
MARKER = re.compile(rb"MARK-[a-z0-9-]+")
STATUS_REPLY = re.compile(rb"\x1b\[0n")


class Log:
    """Everything the scripted clients saw, in arrival order."""

    def __init__(self):
        self.events = []
        self.markers = set()

    def event(self, kind, **fields):
        fields.update(kind=kind, t_wall=time.time())
        self.events.append(fields)


def grey(slot):
    channel = b"%04x" % (slot * 0x1111)
    return channel + b"/" + channel + b"/" + channel


def rgb8(body):
    """`abab/b2b2/bfbf` as [171, 178, 191]."""
    return [int(channel[:2], 16) for channel in body.split(b"/")]


class ScriptedClient:
    """One tmux client whose terminal is this script: known answers, every query logged."""

    def __init__(self, label, foreground, background, scheme, answers_osc4):
        self.label = label
        self.foreground = foreground    # an `rgb:` body, 4 hex digits per channel
        self.background = background
        self.scheme = scheme            # its own answer to ?996n: 1 dark, 2 light
        self.answers_osc4 = answers_osc4
        self.pid = None
        self.fd = None
        self.buffer = b""

    def describe(self):
        return {"label": self.label, "foreground": rgb8(self.foreground),
                "background": rgb8(self.background), "scheme_report": self.scheme,
                "answers_osc4": self.answers_osc4,
                "osc4_answer": "slot n is grey n*17" if self.answers_osc4 else None}

    def attach(self, tmux, socket, log):
        pid, fd = pty.fork()
        if pid == 0:
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith(("TMUX", "TERM_PROGRAM", "LC_TERMINAL"))}
            env["TERM"] = "xterm-256color"
            os.execve(tmux, [tmux, "-L", socket, "attach", "-t", SESSION], env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", PANE_ROWS + 1, PANE_COLUMNS, 0, 0))
        self.pid, self.fd = pid, fd
        log.event("attach", client=self.label, pid=pid)

    def answer(self, match):
        body, terminator = match.group(1), match.group(2)
        raw = match.group(0)
        if body is not None:
            if body == b"10;?":
                return b"\x1b]10;rgb:" + self.foreground + terminator
            if body == b"11;?":
                return b"\x1b]11;rgb:" + self.background + terminator
            if body.startswith(b"4;") and self.answers_osc4:
                return b"".join(b"\x1b]4;" + slot + b";rgb:" + grey(int(slot)) + terminator
                                for slot in re.findall(rb"(\d+);\?", body))
            return None
        if raw == b"\x1b[?996n":
            return b"\x1b[?997;%dn" % self.scheme
        if match.group(3) is not None:
            return {b"": b"\x1b[?62;22c", b">": b"\x1b[>1;10;0c", b"=": None}[match.group(3)]
        if raw.endswith(b"q"):
            return b"\x1bP>|ScriptedClient-" + self.label.encode() + b"(1)\x1b\\"
        if match.group(4):
            return b"\x1b[1;1R" if match.group(4) == b"6" else b"\x1b[0n"
        if match.group(5):
            return b"\x1b[?" + match.group(5) + b";0$y"
        if match.group(6) is not None:
            return b"\x1bP0+r\x1b\\"
        return None

    def pump(self, log):
        """Reads what tmux sent and answers every query. False once tmux has let go."""
        try:
            chunk = os.read(self.fd, 65536)
        except OSError:
            chunk = b""
        if not chunk:
            log.event("detached", client=self.label)
            os.close(self.fd)
            self.fd = None
            return False
        self.buffer += chunk
        for match in MARKER.finditer(self.buffer):
            text = match.group(0).decode()
            if text not in log.markers:
                log.markers.add(text)
                log.event("marker", client=self.label, text=text)
        end = 0
        for match in QUERY.finditer(self.buffer):
            end = match.end()
            reply = None if match.group(7) else self.answer(match)
            log.event("query", client=self.label, raw=match.group(0).decode("latin-1"),
                      answered=None if reply is None else reply.decode("latin-1"))
            if reply:
                os.write(self.fd, reply)
        self.buffer = self.buffer[end:][-256:]
        return True


def clients_for(order):
    catalogue = {
        "A": ScriptedClient("A", b"ffff/ffff/ffff", b"0000/0000/0000", scheme=1, answers_osc4=True),
        "B": ScriptedClient("B", b"abab/b2b2/bfbf", b"2828/2c2c/3434", scheme=2, answers_osc4=False),
    }
    return {label: catalogue[label] for label in order}


def tmux_binary():
    path = os.environ.get("PROBE_TMUX") or shutil.which("tmux")
    if not path:
        raise SystemExit("tmux not found: put it on PATH or set PROBE_TMUX")
    return path


def out_dir():
    path = os.path.abspath(os.environ.get("PROBE_OUT_DIR", "tmux_colour_harness"))
    os.makedirs(path, exist_ok=True)
    return path


def start_server(tmux, socket, pane_arguments):
    """A detached session whose one pane runs this script's pane side. Returns the
    socket's path, which `stop` removes: tmux 3.7c leaves the file behind."""
    subprocess.run([tmux, "-L", socket, "kill-server"], capture_output=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("TMUX")}
    command = " ".join(shlex.quote(part) for part in
                       [sys.executable, os.path.abspath(__file__)] + pane_arguments)
    subprocess.run([tmux, "-L", socket, "-f", "/dev/null", "new-session", "-d", "-s", SESSION,
                    "-x", str(PANE_COLUMNS), "-y", str(PANE_ROWS), command], env=env, check=True)
    return subprocess.run([tmux, "-L", socket, "display-message", "-p", "#{socket_path}"],
                          capture_output=True, text=True).stdout.strip()


def stop(tmux, socket, socket_path, clients):
    subprocess.run([tmux, "-L", socket, "kill-server"], capture_output=True)
    if socket_path and os.path.basename(socket_path) == socket and os.path.exists(socket_path):
        os.unlink(socket_path)
    for client in clients:
        if client.pid is None:
            continue
        try:
            os.kill(client.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(client.pid, 0)
        except ChildProcessError:
            pass


def touch(directory, name):
    open(os.path.join(directory, name), "w").close()


def write_json(path, value):
    """Written aside and renamed, so a reader polling for the file never sees half of it."""
    with open(path + ".partial", "w") as handle:
        json.dump(value, handle, indent=1)
    os.replace(path + ".partial", path)


def tmux_version(tmux):
    return subprocess.run([tmux, "-V"], capture_output=True, text=True).stdout.strip()


# -- clients -------------------------------------------------------------------------------


def run_clients(args):
    tmux = tmux_binary()
    directory = out_dir()
    control = tempfile.mkdtemp(prefix="tmux_colour_clients-")
    socket = "tuikit-colour-%d" % os.getpid()
    first, second = args.order[0], args.order[1]
    clients = clients_for(args.order)
    log = Log()
    socket_path = start_server(tmux, socket, [
        "pane-clients", "--order", args.order, "--out-dir", directory, "--control", control,
        "--tmux", tmux, "--hard-limit", str(args.hard_limit)])
    log.event("server-started", socket=socket)
    clients[first].attach(tmux, socket, log)
    typed = False
    finished_at = None
    deadline = time.time() + 600
    try:
        while time.time() < deadline:
            live = [client for client in clients.values() if client.fd is not None]
            if live:
                ready, _, _ = select.select([client.fd for client in live], [], [], 0.05)
                for client in live:
                    if client.fd in ready:
                        client.pump(log)
            else:
                time.sleep(0.05)
            if os.path.exists(os.path.join(control, "want-second")) and clients[second].pid is None:
                clients[second].attach(tmux, socket, log)
            if (os.path.exists(os.path.join(control, "want-first-key")) and not typed
                    and clients[first].fd is not None):
                os.write(clients[first].fd, b"x")
                typed = True
                log.event("typed", client=first, key="x")
                touch(control, "first-typed")
            if os.path.exists(os.path.join(control, "finished")):
                finished_at = finished_at or time.time()
                if not live or time.time() - finished_at > 5:
                    break
    finally:
        stop(tmux, socket, socket_path, clients.values())
    record = {"experiment": "clients", "order": args.order, "tmux": tmux_version(tmux),
              "clients": [client.describe() for client in clients.values()],
              "events": log.events}
    write_json(os.path.join(directory, "clients-%s-log.json" % args.order), record)
    summarise_clients(directory, args.order, clients, log)


def pane_clients(args):
    """Runs in the pane: probes at each client configuration, then ends the server."""
    first, second = args.order[0], args.order[1]
    steps = []

    def clients():
        out = subprocess.run([args.tmux, "list-clients", "-F",
                              "#{client_tty}|#{client_termtype}|#{client_activity}|#{client_theme}"],
                             capture_output=True, text=True, timeout=3).stdout
        return [line for line in out.splitlines() if line.strip()]

    def wait_clients(count, timeout=30):
        end = time.time() + timeout
        while time.time() < end and len(clients()) < count:
            time.sleep(0.1)
        return len(clients()) >= count

    def probe(step, label):
        path = os.path.join(args.out_dir, "clients-%s-%d.json" % (args.order, step))
        steps.append({"step": step, "label": label, "record": os.path.basename(path),
                      "clients": clients(), "t_wall": time.time()})
        env = dict(os.environ, PROBE_OUT=path, PROBE_LABEL=label, PROBE_TMUX=args.tmux,
                   PROBE_HARD_LIMIT=str(args.hard_limit))
        subprocess.run([sys.executable, PROBE], env=env)

    try:
        if not wait_clients(1):
            steps.append({"error": "the first client never attached"})
            return
        time.sleep(1.5)
        probe(1, "%s only" % first)
        touch(args.control, "want-second")
        if not wait_clients(2):
            steps.append({"error": "the second client never attached"})
            return
        time.sleep(1.5)
        probe(2, "%s and %s, %s attached last" % (first, second, second))
        touch(args.control, "want-first-key")
        end = time.time() + 10
        while time.time() < end and not os.path.exists(os.path.join(args.control, "first-typed")):
            time.sleep(0.1)
        time.sleep(1.0)
        probe(3, "%s and %s, after %s typed a key" % (first, second, first))
        for line in clients():
            if ("ScriptedClient-%s" % second) in line:
                subprocess.run([args.tmux, "detach-client", "-t", line.split("|")[0]], timeout=3)
        time.sleep(1.5)
        probe(4, "%s only, after %s detached" % (first, second))
    finally:
        write_json(os.path.join(args.out_dir, "clients-%s-steps.json" % args.order), steps)
        touch(args.control, "finished")
        subprocess.run([args.tmux, "kill-server"])


def summarise_clients(directory, order, clients, log):
    with open(os.path.join(directory, "clients-%s-steps.json" % order)) as handle:
        steps = json.load(handle)
    by_foreground = {tuple(rgb8(client.foreground)): client.label for client in clients.values()}
    print("tmux colour harness, clients, order %s" % order)
    for step in steps:
        if "error" in step:
            print("  " + step["error"])
            continue
        with open(os.path.join(directory, step["record"])) as handle:
            record = json.load(handle)
        pair = next(e for e in record["exchanges"] if e["name"] == "pair")
        foreground, background = [None if r is None else r["spelling"].get("rgb8")
                                  for r in pair["replies"]]
        osc4 = [e for e in record["exchanges"] if e["name"] == "osc4"]
        scheme = [r["raw"] for e in record["exchanges"] if e["name"] == "csi?996n"
                  for r in e["replies"] if r is not None]
        start, end = record["t0_wall"], record["t0_wall"] + record["elapsed_s"]
        forwarded = {}
        for event in log.events:
            if (event["kind"] == "query" and event["raw"].startswith("\x1b]4;")
                    and start <= event["t_wall"] <= end):
                forwarded[event["client"]] = forwarded.get(event["client"], 0) + 1
        print("  %d. %s" % (step["step"], step["label"]))
        print("     OSC 10/11 %s / %s (client %s); OSC 4 answered %d of %d run%s; ?996n %s; "
              "OSC 4 forwarded to %s" % (
                  foreground, background, by_foreground.get(tuple(foreground or ()), "?"),
                  sum(1 for e in osc4 if e["replies"][0] is not None), len(osc4),
                  " (hard limit)" if record["hard_limit_hit"] else "",
                  scheme[0].encode("unicode_escape").decode() if scheme else "silent",
                  forwarded or "nobody"))


# -- batch ---------------------------------------------------------------------------------


def run_batch(args):
    tmux = tmux_binary()
    directory = out_dir()
    control = tempfile.mkdtemp(prefix="tmux_colour_batch-")
    socket = "tuikit-colour-%d" % os.getpid()
    pane_path = os.path.join(control, "pane.json")
    client = ScriptedClient(args.client, b"abab/b2b2/bfbf", b"2828/2c2c/3434", scheme=1,
                            answers_osc4=args.client == "answering")
    log = Log()
    socket_path = start_server(tmux, socket, ["pane-batch", "--result", pane_path, "--control", control])
    client.attach(tmux, socket, log)
    started = time.time()
    went = False
    done_at = None
    try:
        while time.time() - started < 120 and client.fd is not None:
            if not went and time.time() - started > 1.5:       # after the attach queries settle
                touch(control, "go")
                went = True
            ready, _, _ = select.select([client.fd], [], [], 0.02)
            if ready:
                client.pump(log)
            if os.path.exists(pane_path):
                done_at = done_at or time.time()
                if time.time() - done_at > 0.3:
                    break
    finally:
        stop(tmux, socket, socket_path, [client])
    if not os.path.exists(pane_path):
        raise SystemExit("the pane never finished; client log: %d events" % len(log.events))
    with open(pane_path) as handle:
        pane = json.load(handle)
    for batch in pane["batches"]:
        arrived = [e["t_wall"] for e in log.events
                   if e["kind"] == "marker" and e["text"] == batch["marker"]]
        batch["marker_reached_client_ms"] = (
            round((arrived[0] - batch["t_write"]) * 1000, 3) if arrived else None)
        window_end = batch["t_write"] + (batch["fence_ms"] or 0) / 1000 + LATE_DRAIN
        batch["forwarded_to_client"] = [
            e["raw"] for e in log.events
            if e["kind"] == "query" and e["raw"].startswith("\x1b]")
            and batch["t_write"] <= e["t_wall"] <= window_end]
    record = {"experiment": "batch", "tmux": tmux_version(tmux), "client": client.describe(),
              "batches": pane["batches"], "events": log.events}
    path = os.path.join(directory, "batch-%s.json" % args.client)
    write_json(path, record)
    print("tmux colour harness, batch, client %s (%s)" % (args.client, record["tmux"]))
    for batch in pane["batches"]:
        forwarded = {}
        for raw in batch["forwarded_to_client"]:
            key = re.sub(r"4;\d+;", "4;n;", raw).encode("unicode_escape").decode()
            forwarded[key] = forwarded.get(key, 0) + 1
        print("  %-15s fence %sms; OSC 10 %d, OSC 11 %d, OSC 4 slots %s; late %d; "
              "marker reached the client after %sms; forwarded %s" % (
                  batch["name"], batch["fence_ms"], len(batch["replies"]["osc10"]),
                  len(batch["replies"]["osc11"]), sorted(int(s) for s in batch["replies"]["osc4"]),
                  len(batch["late"]), batch["marker_reached_client_ms"], forwarded or "nothing"))
    print("written to " + path)


def read_until(fd, pattern, limit):
    """(bytes, seconds until `pattern` matched, or None) reading `fd` for up to `limit` s."""
    data = b""
    started = time.time()
    while time.time() - started < limit:
        ready, _, _ = select.select([fd], [], [], 0.01)
        if ready:
            data += os.read(fd, 65536)
            if pattern is not None and pattern.search(data):
                return data, time.time() - started
    return data, None


def parse_replies(data):
    return {
        "osc10": [m.decode() for m in re.findall(rb"\x1b\]10;(rgba?:[0-9a-fA-F/]+)", data)],
        "osc11": [m.decode() for m in re.findall(rb"\x1b\]11;(rgba?:[0-9a-fA-F/]+)", data)],
        "osc4": {slot.decode(): body.decode()
                 for slot, body in re.findall(rb"\x1b\]4;(\d+);(rgba?:[0-9a-fA-F/]+)", data)},
        "raw": data.decode("latin-1"),
    }


def pane_batch(args):
    """Runs in the pane: writes each batch and its marker, and times the fence reply."""
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    batches = []
    try:
        while not os.path.exists(os.path.join(args.control, "go")):
            time.sleep(0.05)
        read_until(fd, None, 0.3)                     # whatever the attach left pending
        for index, (name, payload) in enumerate(BATCHES):
            marker = "MARK-%s-%d" % (name, index)
            t_write = time.time()
            os.write(sys.stdout.fileno(), payload + b"\x1b[5n")
            os.write(sys.stdout.fileno(), b"\r\n" + marker.encode() + b"\r\n")
            got, fence_s = read_until(fd, STATUS_REPLY, 15)
            late, _ = read_until(fd, None, LATE_DRAIN)
            batches.append({"name": name, "request": payload.decode("latin-1"),
                            "marker": marker, "t_write": t_write,
                            "fence_ms": None if fence_s is None else round(fence_s * 1000, 3),
                            "replies": parse_replies(got), "late": late.decode("latin-1")})
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        write_json(args.result, {"batches": batches})


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    clients = commands.add_parser("clients", help="two scripted clients, four configurations")
    clients.add_argument("--order", choices=["AB", "BA"], default="AB")
    clients.add_argument("--hard-limit", type=float, default=20)
    batch = commands.add_parser("batch", help="one scripted client, four batches")
    batch.add_argument("--client", choices=["answering", "silent"], default="silent")
    pane = commands.add_parser("pane-clients", help=argparse.SUPPRESS)
    pane.add_argument("--order", required=True)
    pane.add_argument("--out-dir", required=True)
    pane.add_argument("--control", required=True)
    pane.add_argument("--tmux", required=True)
    pane.add_argument("--hard-limit", required=True)
    pane = commands.add_parser("pane-batch", help=argparse.SUPPRESS)
    pane.add_argument("--result", required=True)
    pane.add_argument("--control", required=True)
    args = parser.parse_args()
    {"clients": run_clients, "batch": run_batch,
     "pane-clients": pane_clients, "pane-batch": pane_batch}[args.command](args)


if __name__ == "__main__":
    main()
