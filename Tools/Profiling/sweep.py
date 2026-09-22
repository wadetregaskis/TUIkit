#!/usr/bin/env python3
"""
Survey one `Stress` binary across many scenarios (and variants), one row each.

    Tools/Profiling/sweep.py [BIN] [--scenarios a b] [--variants-of table-api]
                             [--all] [--reps 3] [--scale N] [--cold] [--csv F]

Why this exists
---------------

`ab_bench.py` answers "did this change make that scenario faster", which is the
question you ask AFTER you know where to look. Finding where to look is the
other question — and it is a survey, not a comparison: forty shapes of one API,
one number each, read down the column for the one that does not belong.

That is how `.fit`'s O(rows) scan, the wrapped estimator's 256-row cliff and the
`.exact` precision's per-frame re-measure were all found: not by suspecting them,
but by seeing one row of a table cost six times its neighbours for no reason its
declaration explained.

What it reads
-------------

Per case: `cpu-per-frame` (thread CPU, so preemption is excluded), the rows
composed and served per frame, the cell values built per frame, the measure
memo's hit rate, and the resident peak. The per-frame row work is the part the
timing cannot say on its own — two scenarios at the same microseconds where one
composes 35 rows and the other serves 35 are not the same scenario.

Medians over `--reps` repetitions, and the spread is printed so a row whose
number is noise says so. No A/B, no bootstrap: this is a map, and its job is to
tell you which square to look at with the instrument that does have one.

Only the standard library, like the rest of this directory.
"""

import argparse
import os
import re
import statistics
import subprocess
import sys

CPU_RE = re.compile(r"cpu-per-frame=([\d.]+)(µs|ms|ns)")
ROWS_RE = re.compile(r"rows/frame: ([\d.]+) composed, ([\d.]+) served")
CELLS_RE = re.compile(r"cell values/frame: ([\d.]+)")
MEMO_RE = re.compile(r"measure memo: (\d+) hits / (\d+) lookups")
RSS_RE = re.compile(r"rss-peak=([\d.]+)MB")
UNIT = {"ns": 1e-3, "µs": 1.0, "ms": 1e3}


def variants_of(binary, scenario):
    """The variant ids the binary itself reports for a scenario."""
    out = subprocess.run([binary, "--variants"], capture_output=True, text=True).stdout
    found, listing = [], False
    for line in out.splitlines():
        if not line.startswith(" "):
            listing = line.split(" ")[0] == scenario
            continue
        if listing and line.startswith("    "):
            found.append(line.split()[0])
    return found


def scenarios_of(binary):
    """Every scenario id, from the binary's own usage text."""
    out = subprocess.run([binary, "--help"], capture_output=True, text=True).stdout
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("Scenario ids"):
            return [s.strip() for s in lines[i + 1].split(",")]
    return []


def run(binary, scenario, variant, iterations, scale, cold):
    cmd = [binary, "--bench", "--scenario", scenario, "--iterations", str(iterations),
           "--scale", str(scale)]
    if variant:
        cmd += ["--variant", variant]
    if cold:
        cmd.append("--cold")
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    cpu = CPU_RE.search(out)
    if not cpu:
        return None
    rows = ROWS_RE.search(out)
    cells = CELLS_RE.search(out)
    memo = MEMO_RE.search(out)
    rss = RSS_RE.search(out)
    hits, lookups = (int(memo.group(1)), int(memo.group(2))) if memo else (0, 0)
    return {
        "cpu": float(cpu.group(1)) * UNIT[cpu.group(2)],
        "composed": float(rows.group(1)) if rows else 0.0,
        "served": float(rows.group(2)) if rows else 0.0,
        "cells": float(cells.group(1)) if cells else 0.0,
        "memo": (hits / lookups * 100) if lookups else float("nan"),
        "rss": float(rss.group(1)) if rss else 0.0,
    }


def calibrate(binary, scenario, variant, scale, cold, target_ms=400):
    """Iterations that make a case last about `target_ms`, from a pilot run."""
    pilot = run(binary, scenario, variant, 40, scale, cold)
    if not pilot or pilot["cpu"] <= 0:
        return 200
    return max(20, min(4000, int(target_ms * 1000 / pilot["cpu"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("binary", nargs="?", default=None)
    ap.add_argument("--scenarios", nargs="*", default=[])
    ap.add_argument("--variants-of", default=None)
    ap.add_argument("--all", action="store_true", help="every scenario in the catalogue")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--cold", action="store_true")
    ap.add_argument("--csv", default=None)
    args = ap.parse_args()

    binary = args.binary or os.path.join(
        subprocess.run(["swift", "build", "-c", "release", "--product", "Stress",
                        "--show-bin-path"], capture_output=True, text=True).stdout.strip(),
        "Stress")
    if not os.path.exists(binary):
        sys.exit(f"no such binary: {binary}")

    cases = [(s, None) for s in args.scenarios]
    if args.all:
        cases = [(s, None) for s in scenarios_of(binary)]
    if args.variants_of:
        cases += [(args.variants_of, v) for v in variants_of(binary, args.variants_of)]
    if not cases:
        sys.exit("nothing to sweep: pass --scenarios, --variants-of or --all")

    print(f"{'case':34} {'cpu/frame':>10} {'±':>6} {'composed':>9} {'served':>8} "
          f"{'cells':>8} {'memo%':>6} {'rssMB':>6}")
    rows = []
    for scenario, variant in cases:
        iterations = calibrate(binary, scenario, variant, args.scale, args.cold)
        samples = [run(binary, scenario, variant, iterations, args.scale, args.cold)
                   for _ in range(args.reps)]
        samples = [s for s in samples if s]
        if not samples:
            print(f"{scenario + ('/' + variant if variant else ''):34} FAILED")
            continue
        cpus = sorted(s["cpu"] for s in samples)
        median = statistics.median(cpus)
        spread = (cpus[-1] - cpus[0]) / median * 100 if median else 0
        last = samples[-1]
        name = scenario + ("/" + variant if variant else "")
        print(f"{name:34} {median:9.1f}µs {spread:5.1f}% {last['composed']:9.1f} "
              f"{last['served']:8.1f} {last['cells']:8.1f} {last['memo']:6.1f} {last['rss']:6.1f}")
        rows.append((name, median, spread, last))

    if args.csv:
        with open(args.csv, "w") as f:
            f.write("case,cpu_us,spread_pct,composed,served,cells,memo_pct,rss_mb\n")
            for name, median, spread, last in rows:
                f.write(f"{name},{median:.2f},{spread:.2f},{last['composed']:.2f},"
                        f"{last['served']:.2f},{last['cells']:.2f},{last['memo']:.2f},"
                        f"{last['rss']:.2f}\n")
        print(f"\nwrote {args.csv}")


if __name__ == "__main__":
    main()
