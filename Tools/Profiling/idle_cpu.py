#!/usr/bin/env python3
"""Measure a PTY TUI app's idle cost: CPU time and render output (bytes) over a
no-input window on a static screen.

The render loop should do nothing while nothing changes, so a static screen with
no input must approach 0% CPU and 0 bytes/s of render output. This is the probe
behind the "demand-driven animation clocks" work (see git log).

    swift build -c release --product Example -Xswiftc -g
    BIN="$(swift build -c release --product Example --show-bin-path)/Example"
    python3 Tools/Profiling/idle_cpu.py "$BIN" [settle_s] [window_s] [keys]
    python3 Tools/Profiling/idle_cpu.py "$BIN" 3 10 --page spinners --wakeups

`keys` (optional) is sent after the settle delay to drive to another screen
first; escapes like \\t and \\x1b are interpreted. `--page NAME` launches the
binary with `--page NAME` instead, which lands on that page without navigating
(the Example matches a `DemoPage` case name: `spinners`, `forms`,
`scrollView`, ...). With neither, it measures the initial screen.

Output, over the window:

    CPU x.x%   bytes/s N   bursts/s B   [idle wakeups/s W]

- `bursts/s` counts reads of the child's output that arrive more than 5 ms after
  the previous one: roughly one per frame or replayed tick the app wrote, since
  one frame's bytes arrive together. A proxy for how often the loop woke AND had
  something to say; a wake that wrote nothing is invisible to it.
- `--wakeups` also samples `top -stats pid,cpu,idlew` once a second across the
  window and reports the IDLEW difference between the first and last sample per
  second: every time the process left an idle state, whether or not it wrote
  anything. macOS only.

A static screen → ~0 / 0 / 0; an animating screen (spinner, focused pulse, text
cursor) → non-zero, continuously.

The child runs with `TUIKIT_CONFIG_DIR` set to a fresh temporary directory, so a
run cannot read or write the user's settings, and the directory is removed
afterwards. The run is bounded by an alarm, and the child's whole process group
is killed and reaped on the way out.
"""
import argparse, fcntl, os, pty, re, shutil, signal, struct, subprocess, sys, tempfile, termios, threading, time

parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("binary")
parser.add_argument("settle", nargs="?", type=float, default=2.5, help="seconds before measuring")
parser.add_argument("window", nargs="?", type=float, default=5.0, help="seconds measured")
parser.add_argument("keys", nargs="?", default="", help="keystrokes sent after the settle")
parser.add_argument("--page", help="launch with `--page NAME`")
parser.add_argument("--wakeups", action="store_true", help="also report top's IDLEW per second")
args = parser.parse_args()
binary, settle, window, keys = args.binary, args.settle, args.window, args.keys


class Timeout(Exception):
    pass


def on_alarm(signum, frame):
    raise Timeout("idle_cpu.py: run exceeded its time bound")


# Raised rather than the default action, so the `finally` below still kills and
# reaps the child and removes the config directory.
signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(int(settle + window + len(keys) * 0.12 + 30))

config_dir = tempfile.mkdtemp(prefix="tuikit-idle-cpu-")
argv = [binary] + (["--page", args.page] if args.page else [])

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
pid = os.fork()
if pid == 0:  # child: become the controlling tty for `binary`
    try:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
        os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        env = dict(os.environ)
        env["TERM"] = "xterm-256color"
        env["TUIKIT_CONFIG_DIR"] = config_dir
        os.execve(binary, argv, env)
    except Exception:
        pass
    os._exit(127)
os.close(slave)

received = {"bytes": 0, "bursts": 0}
stop = threading.Event()
BURST_GAP = 0.005


def drain():  # read child output so it never blocks on a full pipe
    last = 0.0
    while not stop.is_set():
        try:
            d = os.read(master, 65536)
            if not d:
                break
            now = time.monotonic()
            if now - last > BURST_GAP:
                received["bursts"] += 1
            last = now
            received["bytes"] += len(d)
        except OSError:
            break


threading.Thread(target=drain, daemon=True).start()


def keystrokes(data):
    """`data` split into one escape sequence or one byte at a time.

    An escape sequence has to travel whole — split across two writes it reaches
    the parser as a stray ESC and then as text — so ESC runs to the final byte
    of a CSI (`@` through `~`), or covers just the next byte for the two-byte
    forms (ESC O P, Alt-key).
    """
    index = 0
    while index < len(data):
        if data[index] != 0x1B or index + 1 >= len(data):
            yield data[index : index + 1]
            index += 1
            continue
        end = index + 1
        if data[end] in b"[O":
            end += 1
            while end < len(data) and not (0x40 <= data[end] <= 0x7E):
                end += 1
        yield data[index : end + 1]
        index = end + 1


def cputime_secs(p):
    out = subprocess.check_output(["ps", "-o", "cputime=", "-p", str(p)]).decode().strip()
    days = 0
    if "-" in out:
        ds, out = out.split("-", 1); days = int(ds)
    secs = 0.0
    for part in out.split(":"):
        secs = secs * 60 + float(part)
    return secs + days * 86400


def idle_wakeups_per_second(output, p, interval):
    """IDLEW's rise from top's first sample of `p` to its last, per second.

    top prints one row per sample, `PID %CPU IDLEW`; IDLEW is cumulative, so a
    single row says nothing about a window and the difference is the reading.
    """
    counts = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0] == str(p):
            match = re.match(r"\d+", fields[2])
            if match:
                counts.append(int(match.group(0)))
    if len(counts) < 2:
        return None
    return (counts[-1] - counts[0]) / ((len(counts) - 1) * interval)


try:
    time.sleep(settle)
    if keys:
        # One keystroke at a time, with a beat between them. Written as a single
        # burst they arrive in one read, and an app that renders per keystroke
        # then coalesces the lot into one frame — which is fine for "press 0 to
        # reach the spinners page" and wrong for anything whose later keys
        # depend on what the earlier ones drew (a Tab walk, or a mouse click at
        # a position that scrolling put there).
        for stroke in keystrokes(keys.encode().decode("unicode_escape").encode("latin-1")):
            os.write(master, stroke)
            time.sleep(0.12)
        time.sleep(1.2)
    top = None
    if args.wakeups:
        samples = max(2, int(window) + 1)
        top = subprocess.Popen(
            ["top", "-l", str(samples), "-s", "1", "-pid", str(pid), "-stats", "pid,cpu,idlew"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    t0, b0, n0 = cputime_secs(pid), received["bytes"], received["bursts"]
    time.sleep(window)
    t1, b1, n1 = cputime_secs(pid), received["bytes"], received["bursts"]
    line = (f"CPU {(t1 - t0) / window * 100:4.1f}%   bytes/s {int((b1 - b0) / window):7d}   "
            f"bursts/s {(n1 - n0) / window:5.1f}")
    if top is not None:
        output = top.communicate(timeout=15)[0].decode(errors="replace")
        wakeups = idle_wakeups_per_second(output, pid, 1.0)
        line += "   idle wakeups/s " + ("   n/a" if wakeups is None else f"{wakeups:6.1f}")
    target = f"page={args.page!r}" if args.page else f"keys={keys!r}"
    print(f"{line}   (over {window:.0f}s, {target})")
finally:
    signal.alarm(0)
    stop.set()
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        if sig == signal.SIGTERM:
            time.sleep(0.2)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    shutil.rmtree(config_dir, ignore_errors=True)
