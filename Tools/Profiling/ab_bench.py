#!/usr/bin/env python3
"""
Paired A/B benchmark of two prebuilt `Stress` binaries, with an honest
confidence interval and a verdict.

    Tools/Profiling/ab_bench.py OLD NEW [--scenarios a b c] [--scale N] [--cold]

Why this exists
---------------

The obvious A/B — run each binary a few times, compare the best of each — is
wrong in three ways that between them cost two reverted commits (see §31 and
§33 of `Documentation/Performance-profile-2026-08.md`):

1. **Wall clock measures the machine, not the code.** Every microsecond the
   scheduler spends elsewhere lands in the number. This reads the harness's
   `cpu-per-frame`, which is thread CPU time and excludes preemption.

2. **A fixed run order is a fixed bias.** With A always before B, any trend
   inside a rep — thermal, a background process ramping — is charged to
   whichever ran second. Twice this session a "regression" turned out to be
   exactly that: *every* pass showed the second binary slower, including the
   pass where that was the original. Here the order is **randomised per rep**,
   which converts that bias into zero-mean noise the statistics can price.

3. **Unpaired minima throw away the pairing.** A and B run adjacent in time, so
   whatever the machine was doing affected both. Comparing per-rep **ratios**
   cancels that; comparing two independent minima does not. The estimator is
   the median of the paired ratios, and a bootstrap gives its interval.

The verdict is the point. If the interval spans 1.0 the honest answer is
"indistinguishable", not a number with a sign — and that is the answer this
tool is built to give, because it is the one that was missing.

A fixed iteration count is also a trap: 300 iterations of a 160 µs scenario is
50 ms of measurement, mostly warm-up. Iterations are calibrated per scenario
from a pilot run so every measurement lasts about the same wall time.

Only the standard library, like the rest of this directory.
"""
import argparse
import os
import random
import re
import statistics
import subprocess
import sys

# Scenarios the default sweep leaves out: `animating` and `translucent` are both
# driven by the harness's frame counter, so a fixed-iteration run measures a
# different mix of in-flight work each time — ask for them by name, where the
# question is about animation or compositing rather than about layout.
EXCLUDED_FROM_SWEEP = {"animating", "translucent"}

# The fallback list, for a binary too old to be asked. The live list comes from
# the binary itself (`scenario_ids`) — a hard-coded one goes stale silently, and
# did: `menus` and `gradients` were added to `Stress` and never added here, so
# every "full sweep" for weeks quietly skipped the only scenario with a `Menu`
# in it. That is the same failure the `menus` scenario was written to fix.
FALLBACK_SCENARIOS = [
    "megalist", "scrollfollow", "table", "table-multiline", "tables-scroll",
    "tables-vstack", "deep", "fanout", "modifiers", "textwall", "anyview",
    "dashboard", "framedcolumns", "churn", "kitchensink", "customlayout",
    "preferences", "gradients", "menus",
]

# The `--quick` sweep: six shapes that between them cover a deep tree, a wide
# eager one, styled controls, modifier chains, type erasure and an ordinary
# page — and that all resolve tightly enough to trust at twelve reps (see
# README.md for the measured floor). For iterating on a change; run the full
# sweep before committing one.
QUICK_SCENARIOS = ["deep", "fanout", "menus", "modifiers", "anyview", "framedcolumns"]


def scenario_ids(binary):
    """The scenarios `binary` actually has, minus the ones the sweep excludes.

    Asked of the binary rather than hard-coded so a new scenario joins the sweep
    the day it is written.
    """
    try:
        out = subprocess.run([binary, "--help"], capture_output=True, text=True,
                             timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return list(FALLBACK_SCENARIOS)
    for line in out.splitlines():
        if "," in line and "scenario" not in line.lower():
            ids = [part.strip() for part in line.split(",")]
            if len(ids) > 5 and all(part and " " not in part for part in ids):
                return [name for name in ids if name not in EXCLUDED_FROM_SWEEP]
    return list(FALLBACK_SCENARIOS)

WALL_RE = re.compile(r"(?<!-)\bper-frame=([0-9.]+)")  # not `cpu-per-frame=`
CPU_RE = re.compile(r"cpu-per-frame=([0-9.]+)")
# Peak resident size, which the harness started reporting beside the timings so
# that "is this cheaper?" stops being a question about one resource out of two.
# A render cache is the case that needs it: it buys an order of magnitude of CPU
# by keeping buffers, and nothing here used to price that.
RSS_RE = re.compile(r"rss-peak=([0-9.]+)")


def run(binary, scenario, scale, iterations, cols, rows, cold=False):
    """One bench run; returns (wall_us, cpu_us, peak_rss_mb)."""
    out = subprocess.run(
        [binary, "--bench", "--scenario", scenario, "--scale", str(scale),
         "--iterations", str(iterations), "--cols", str(cols), "--rows", str(rows)]
        + (["--cold"] if cold else []),
        capture_output=True, text=True, check=True).stdout
    wall = WALL_RE.search(out)
    cpu = CPU_RE.search(out)
    rss = RSS_RE.search(out)
    if not wall:
        raise RuntimeError(f"no timing in output of {binary} {scenario}:\n{out}")
    return (float(wall.group(1)),
            float(cpu.group(1)) if cpu else None,
            float(rss.group(1)) if rss else None)


def calibrate(binary, scenario, scale, target_seconds, cols, rows, cold=False):
    """Iterations that make one run last roughly `target_seconds`."""
    wall_us, _, _ = run(binary, scenario, scale, 30, cols, rows, cold)
    iterations = int(target_seconds * 1_000_000 / max(wall_us, 1.0))
    return max(50, min(iterations, 200_000))


def bootstrap_ci(ratios, confidence=0.95, resamples=10_000, seed=20260813):
    """Percentile-bootstrap interval for the median of `ratios`."""
    rng = random.Random(seed)
    n = len(ratios)
    medians = sorted(
        statistics.median(rng.choices(ratios, k=n)) for _ in range(resamples))
    lo = medians[int((1 - confidence) / 2 * resamples)]
    hi = medians[min(resamples - 1, int((1 + confidence) / 2 * resamples))]
    return lo, hi


def quiesce_report():
    """What else the machine is doing — the numbers that invalidate a run."""
    try:
        load = os.getloadavg()[0]
    except OSError:
        load = float("nan")
    busiest = ""
    try:
        lines = subprocess.run(
            ["ps", "-Ao", "pcpu,comm", "-r"],
            capture_output=True, text=True, check=True).stdout.splitlines()[1:4]
        busiest = "; ".join(
            f"{l.split(None, 1)[0]}% {os.path.basename(l.split(None, 1)[1])[:28]}"
            for l in lines if l.strip())
    except (subprocess.SubprocessError, IndexError, OSError):
        pass
    return load, busiest


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("--scenarios", nargs="*", default=None,
                        help="scenario ids (default: every one the binary has, "
                             "less the frame-counter-driven pair)")
    parser.add_argument("--quick", action="store_true",
                        help="six representative scenarios at 12 reps — about "
                             "four minutes instead of twenty-five. For iterating; "
                             "run the full sweep before committing.")
    parser.add_argument("--scale", type=int, default=1)
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("--reps", type=int, default=None,
                        help="paired measurements per scenario (default 15, or "
                             "12 with --quick)")
    parser.add_argument("--target-seconds", type=float, default=1.5,
                        help="how long one run should take (default 1.5)")
    parser.add_argument("--metric", choices=["cpu", "wall"], default="cpu")
    parser.add_argument("--seed", type=int, default=20260813,
                        help="run-order seed; change it to re-randomise")
    parser.add_argument("--cold", action="store_true",
                        help="reset state + render cache every frame, so every "
                             "frame is an all-miss frame. The steady state the "
                             "default measures is what a running app spends its "
                             "life in; this is the other end — the first frame "
                             "of a page, and the honest check on any change that "
                             "makes a cache MISS cost more than it used to.")
    args = parser.parse_args()
    if args.scenarios is None:
        args.scenarios = QUICK_SCENARIOS if args.quick else scenario_ids(args.old)
    if args.reps is None:
        args.reps = 12 if args.quick else 15

    load, busiest = quiesce_report()
    print(f"load {load:.2f} · busiest: {busiest or 'n/a'}")
    if load > 1.5:
        print("  NOTE: the box is busy. CPU-time metric absorbs preemption, but "
              "cache and memory-bandwidth contention still inflate real work.")
    print(f"metric={args.metric}-per-frame  reps={args.reps}  "
          f"target={args.target_seconds}s/run  order randomised per rep"
          f"{'  COLD (cache reset every frame)' if args.cold else ''}\n")

    index = 1 if args.metric == "cpu" else 0
    if index == 1:
        # A binary built before the harness reported CPU time cannot supply it;
        # say so rather than comparing against nothing.
        for binary in (args.old, args.new):
            if run(binary, args.scenarios[0], args.scale, 30, args.cols, args.rows,
                   args.cold)[1] is None:
                print(f"  {binary} predates cpu-per-frame — falling back to wall clock, "
                      "which is preemption-sensitive; expect wider intervals.\n")
                index = 0
                break
    rng = random.Random(args.seed)
    header = f"{'scenario':<16}{'iters':>8}{'old µs':>11}{'new µs':>11}{'change':>9}{'95% CI':>17}  verdict"
    print(header)
    print("-" * len(header))

    for scenario in args.scenarios:
        iterations = calibrate(
            args.old, scenario, args.scale, args.target_seconds, args.cols, args.rows,
            args.cold)
        # A discarded pilot per binary, so neither pays first-touch costs
        # (page-ins, file cache) inside a measured rep.
        for binary in (args.old, args.new):
            run(binary, scenario, args.scale, iterations, args.cols, args.rows, args.cold)

        olds, news, ratios = [], [], []
        old_rss, new_rss = [], []
        for _ in range(args.reps):
            # Indexed by POSITION, not by path: a null test (`ab_bench.py X X`)
            # passes the same path twice, and keying by path would collapse the
            # two runs into one and report a fake, perfect +0.0%.
            order = [0, 1]
            if rng.random() < 0.5:
                order.reverse()
            binaries = (args.old, args.new)
            results = [0.0, 0.0]
            memory = [None, None]
            for position in order:
                reading = run(
                    binaries[position], scenario, args.scale, iterations,
                    args.cols, args.rows, args.cold)
                results[position] = reading[index]
                memory[position] = reading[2]
            old_us, new_us = results[0], results[1]
            olds.append(old_us)
            news.append(new_us)
            ratios.append(new_us / old_us)
            if memory[0] and memory[1]:
                old_rss.append(memory[0])
                new_rss.append(memory[1])

        median_ratio = statistics.median(ratios)
        lo, hi = bootstrap_ci(ratios)
        verdict = ("faster" if hi < 1.0 else
                   "slower" if lo > 1.0 else
                   "indistinguishable")
        # RAM is reported as plain medians rather than through the bootstrap:
        # peak RSS barely varies between runs of the same binary, so a
        # confidence interval on it would be theatre. A change of more than a
        # megabyte is worth a look; below that it is allocator noise.
        if old_rss and new_rss:
            old_mb, new_mb = statistics.median(old_rss), statistics.median(new_rss)
            ram = f"  ram {old_mb:.1f}->{new_mb:.1f}MB {(new_mb - old_mb):+.1f}"
        else:
            ram = ""
        print(f"{scenario:<16}{iterations:>8}{statistics.median(olds):>11.1f}"
              f"{statistics.median(news):>11.1f}{(median_ratio - 1) * 100:>+8.1f}%"
              f"{(lo - 1) * 100:>+9.1f}%{(hi - 1) * 100:>+7.1f}%  {verdict}{ram}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
