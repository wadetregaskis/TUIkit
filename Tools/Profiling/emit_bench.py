#!/usr/bin/env python3
"""Paired A/B of two `Stress` binaries over the EMISSION path, under a real PTY.

    Tools/Profiling/emit_bench.py OLD NEW [--scenarios a b] [--host Apple_Terminal]
                                 [--reps 9] [--window 4.0]

Why this exists — `ab_bench.py` cannot see this code
-----------------------------------------------------

`ab_bench.py` drives `Stress --bench`, which is a counted `renderToBuffer`
loop with no PTY (its own README says so). Everything downstream of the frame
buffer — `FrameDiffWriter.buildOutputLines`, the per-line right-edge clip, the
per-host cursor-compensation walks, the diff and the writes — is called only
from `RenderLoop` and therefore never runs. That is not a small blind spot: it
is the entire output half of the framework, and it is where every terminal
quirk workaround lives.

The check that proves it: force `TERM_PROGRAM=Apple_Terminal` (the heaviest
compensation walk of any host) against `ghostty` under `--bench` and the
numbers are identical — 144.3 vs 143.7 µs on `dashboard`. If emission were in
the timed region that could not happen.

So this runs the app for real: a PTY, `--autopilot` (self-driven continuous
re-renders), the host forced by environment, and the measurement is the
process's own CPU time over a fixed window — which is what
`Tools/Profiling/idle_cpu.py` already established as the way to measure a PTY
app on this machine (`ps -o cputime=`; `RUSAGE_CHILDREN` reads 0 for a live
child).

Method, borrowed wholesale from `ab_bench.py` because the traps are the same
- **CPU time, not wall clock**, so preemption is not charged to the code.
- **Order randomised per rep**, so a trend inside a rep is zero-mean noise
  rather than a bias charged to whichever binary ran second.
- **Paired ratios**, so whatever the machine was doing affected both.
- A **bootstrap interval**, and the verdict is "indistinguishable" whenever it
  spans 1.0. A number with a sign that the data does not support is the thing
  this is built to avoid saying.

Only the standard library, like the rest of this directory.
"""
import argparse
import fcntl
import os
import pty
import random
import statistics
import struct
import subprocess
import sys
import termios
import threading
import time

SCENARIOS = ["dashboard", "framedcolumns", "kitchensink", "megalist", "table"]


def cputime_secs(pid):
    out = subprocess.check_output(["ps", "-o", "cputime=", "-p", str(pid)]).decode().strip()
    days = 0
    if "-" in out:
        ds, out = out.split("-", 1)
        days = int(ds)
    secs = 0.0
    for part in out.split(":"):
        secs = secs * 60 + float(part)
    return secs + days * 86400


def measure(binary, scenario, host, settle, window, cols, rows):
    """CPU seconds and emitted bytes over `window`, for one autopilot run."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        try:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            if slave > 2:
                os.close(slave)
            env = dict(os.environ)
            env["TERM"] = "xterm-256color"
            env["TERM_PROGRAM"] = host
            # A probe must never touch the user's real config.
            env["TUIKIT_CONFIG_DIR"] = os.environ.get(
                "TUIKIT_CONFIG_DIR", "/tmp/tuikit-emit-bench-config")
            env.pop("TMUX", None)
            os.execve(binary, [binary, "--autopilot", "--scenario", scenario], env)
        except Exception:
            pass
        os._exit(127)
    os.close(slave)

    seen = {"bytes": 0}
    stop = threading.Event()

    def drain():  # the app blocks on a full pipe if nobody reads it
        while not stop.is_set():
            try:
                data = os.read(master, 65536)
                if not data:
                    break
                seen["bytes"] += len(data)
            except OSError:
                break

    threading.Thread(target=drain, daemon=True).start()
    try:
        time.sleep(settle)
        before, bytes_before = cputime_secs(pid), seen["bytes"]
        time.sleep(window)
        after, bytes_after = cputime_secs(pid), seen["bytes"]
    finally:
        stop.set()
        try:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except OSError:
            pass
        os.close(master)
    return after - before, bytes_after - bytes_before


def bootstrap_ci(ratios, confidence=0.95, resamples=10_000, seed=20260828):
    rng = random.Random(seed)
    medians = []
    for _ in range(resamples):
        sample = [rng.choice(ratios) for _ in ratios]
        medians.append(statistics.median(sample))
    medians.sort()
    low = medians[int((1 - confidence) / 2 * resamples)]
    high = medians[int((1 + confidence) / 2 * resamples) - 1]
    return low, high


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("--scenarios", nargs="+", default=SCENARIOS)
    parser.add_argument("--host", default="Apple_Terminal")
    parser.add_argument("--reps", type=int, default=9)
    parser.add_argument("--window", type=float, default=4.0)
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    args = parser.parse_args()

    print(f"metric=process CPU seconds over {args.window}s of autopilot  "
          f"host={args.host}  reps={args.reps}  order randomised per rep\n")
    print(f"{'scenario':<16}{'old s':>9}{'new s':>9}{'change':>9}"
          f"{'95% CI':>18}  verdict")
    print("-" * 78)
    rng = random.Random(20260828)
    for scenario in args.scenarios:
        ratios, olds, news = [], [], []
        for _ in range(args.reps):
            order = [("old", args.old), ("new", args.new)]
            rng.shuffle(order)
            result = {}
            for label, binary in order:
                cpu, _ = measure(binary, scenario, args.host, args.settle,
                                 args.window, args.cols, args.rows)
                result[label] = cpu
            if result["old"] <= 0 or result["new"] <= 0:
                continue
            olds.append(result["old"])
            news.append(result["new"])
            ratios.append(result["new"] / result["old"])
        if len(ratios) < 3:
            print(f"{scenario:<16}  no usable reps (the app may not have started)")
            continue
        median = statistics.median(ratios)
        low, high = bootstrap_ci(ratios)
        # An interval that TOUCHES 1.0 is indistinguishable, not a verdict.
        # Written as three exclusive tests rather than `low < 1.0 < high`,
        # which reported SLOWER for an interval of [-2.1%, 0.0%] — a tie that
        # `ps -o cputime=`'s centisecond granularity produces routinely on the
        # lighter scenarios.
        verdict = ("faster" if high < 1.0
                   else "SLOWER" if low > 1.0
                   else "indistinguishable")
        print(f"{scenario:<16}{statistics.median(olds):>9.3f}"
              f"{statistics.median(news):>9.3f}{(median - 1) * 100:>8.1f}%"
              f"{(low - 1) * 100:>8.1f}% {(high - 1) * 100:>7.1f}%  {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
