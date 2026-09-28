#!/usr/bin/env python3
"""
Run the whole test suite in N processes instead of one, and prove it ran.

WHY THIS EXISTS
---------------
`swift test` runs the suite in a single process. swift-testing already runs
suites concurrently *within* that process, but 81% of this package's tests are
in `@MainActor` suites, so they queue on one actor. Sampling a single-process
run shows 77% of the late-regime CPU in `syscall_thread_switch` /
`__workq_kernreturn` / `__ulock_wait2` — eleven cooperative-pool threads
burning CPU taking turns at the main actor. That CPU is contention, not work.

Each process gets its OWN main actor, so splitting the suite across processes
turns that contention back into throughput. Measured on this repo, 12 logical
cores (see CONTRIBUTING.md for the full before/after):

    swift test (one process)   51.6 s suite / 59.7 s wall
    this harness, -j 6         ~15 s

WHAT IT DOES NOT DO
-------------------
It does not replace the `swift test` CI lanes. CI runs the suite exactly the
way a contributor does, in one process; this is a local accelerant for anyone
running the suite repeatedly. It is also not a different *selection* of tests:
it runs all of them, and refuses to report success unless it can prove it.

THE FOUR TRAPS THIS HARNESS IS BUILT AROUND
-------------------------------------------
1. `swift test --filter` CANNOT be used to shard. Concurrent `swift test`
   invocations serialise on the SwiftPM build database lock (4 concurrent
   1.6 s runs took 7.3 s), and worse, a lock-starved process can die with
   "database is locked / no tests found" having run NOTHING. Measured: 1 run
   in 4 silently lost 2,168 tests while being the slowest of the four. So we
   take the build lock exactly once, up front, and then invoke
   `swiftpm-testing-helper` directly — it touches no build database.

2. The helper SILENTLY IGNORES unknown flags. Passing `--no-such-flag` does
   not error; it runs the entire suite. So a typo or a future toolchain
   renaming `--filter` would make every process run everything — slow, and
   still "passing". Hence `check_selection`: every process must report the
   exact number of tests the partition predicted for it.

3. Nothing may be hard-coded. The groups are derived at runtime from
   `--list-tests`, so a suite added today is partitioned today. Weights come
   from a cache that is advisory only: an unknown test gets the median weight
   and still runs.

4. A test's apparent DURATION is not its cost. swift-testing starts tests with
   unbounded concurrency, so in an ordinary run they nearly all start at once
   and then queue on the main actor: the median test "lasted" 49.05 s of a
   53.1 s run. Both obvious timing sources are really completion timestamps —
   the xunit `time` attribute has the same shape. Weights therefore come only
   from a `--calibrate` run, which is serial, and are written only if the
   event stream proves it stayed serial.

RECONCILIATION IS THE POINT
---------------------------
Speed is worthless if a process quietly runs nothing. Every run is gated on:
  * the union of test IDs equals the enumerated suite exactly (no missing, no
    extra), and no test ran twice;
  * each process ran exactly the count the static proof predicted;
  * every process produced a parseable summary line, and any process that
    reports a failure is accounted for by a named failing test.
Any of those failing is a hard failure, whatever the exit codes said.

Usage:
    Tools/ParallelTest/parallel-test.py [-j N] [--calibrate] [--plan-only]
                                        [--filter REGEX] [--no-build]
                                        [--expect-known-issues N] [--json PATH]
"""

import argparse
import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(REPO, ".build", "parallel-test")
WEIGHTS = os.path.join(WORK, "weights.json")

# One run at a time on a machine, whichever checkout or worktree it comes from.
# A run already fills half the cores with test processes, and on a 16 GiB
# machine two of them (plus their builds) push each other into memory
# compression and swap: each gets slower, and together they are slower than
# the same two in turn. So a second run waits for the first. Deliberately in
# /tmp rather than $TMPDIR, which can differ per sandbox or agent, and a flock
# rather than a pid file: the kernel drops it when its holder exits, however
# that happens, so a crashed run never leaves the next one waiting.
LOCK_PATH = os.environ.get("TUIKIT_PARALLEL_TEST_LOCK", "/tmp/tuikit-parallel-test.lock")

# swift-testing's final line. Everything after "seconds" is one clause built
# from a three-way switch on (any error, any warning, any known issue), and it
# is captured WHOLE rather than matched shape by shape. An earlier version
# enumerated the shapes, knew three of the eight, and so reported "produced no
# summary line" — which reads like a dead or hung process — for a group that
# had simply failed. All eight, transcribed from a probe package run against
# the toolchains themselves (the warning shapes need 6.3: 6.2.4 ships no
# Issue.Severity, so there a run can only take the four without one):
#   passed after 0.001 seconds.
#   passed after 0.001 seconds with 3 known issues.
#   passed after 0.001 seconds with 2 warnings.
#   passed after 0.001 seconds with 2 warnings and 3 known issues.
#   failed after 0.001 seconds with 1 issue.
#   failed after 0.001 seconds with 5 issues (including 3 known issues).
#   failed after 0.001 seconds with 5 issues (including 3 warnings).
#   failed after 0.001 seconds with 9 issues (including 3 warnings and 4 known issues).
# The known count is then read out of that clause BY NAME, so a reworded or
# newly added clause costs the count and not the whole line; --expect-known-
# issues is the cross-check that a silent rewording has not zeroed it. `\n` is
# in the character class because Python's `[^.]` DOES match a newline, and
# without it a summary line that lost its period would swallow the lines after
# it — including, on a killed process, lines that are not a summary at all.
SUMMARY_RE = re.compile(
    r"Test run with (\d+) tests? in (\d+) suites? (passed|failed) after "
    r"([\d.]+) seconds( with [^.\n]*)?\.")
KNOWN_ISSUES_RE = re.compile(r"(\d+) known issues?")

# The event stream spells a test's ID with its declaration site appended:
#   TUIkitViewTests.BindableTests/projectedValueRoundTrip()/BindableTests.swift:41:6
# `--list-tests` and the xunit output both omit that, so strip it to join them.
SOURCE_LOC_RE = re.compile(r"/[^/]+\.swift:\d+:\d+$")

# Control characters XML 1.0 forbids outright (tab, LF and CR are legal).
XML_ILLEGAL_RE = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f]")

# Metacharacters common to Python's `re` and Swift's `Regex`. Test IDs today use
# only [A-Za-z0-9_./():] — `:` and `/` are literal in both engines and are
# deliberately NOT escaped, because Python's own re.escape would emit e.g. `\&`
# for other characters and Swift's engine rejects unknown escapes.
META = set(r".^$*+?()[]{}|\/")


def escape_regex(s):
    """Escape for both Python `re` and Swift `Regex`."""
    return "".join("\\" + c if c in META else c for c in s)


def suite_of(test_id):
    """'Module.Suite/test()' -> 'Module.Suite'. Nested suites keep their dots."""
    return test_id.split("/", 1)[0]


def strip_source_location(event_test_id):
    """Event-stream test ID -> the ID `--list-tests` and xunit use."""
    return SOURCE_LOC_RE.sub("", event_test_id)


def pattern_for_suite(suite):
    """Every test in a suite, and nothing that merely starts with its name."""
    return "^" + escape_regex(suite) + "/"


def pattern_for_test(test_id):
    """One test. The trailing `(?:/|$)` is what keeps `foo()` from also
    selecting a hypothetical `foo()Extra`, while still matching the
    source-location-suffixed spelling the runtime may hand the matcher."""
    return "^" + escape_regex(test_id) + r"(?:/|$)"


def parse_summary_text(text):
    """The LAST summary line's numbers, or None.

    Last, not first: per-test lines also say "recorded a known issue", and a
    first-match parse reports a handful of known issues for a run whose summary
    says 21.
    """
    ms = SUMMARY_RE.findall(text)
    if not ms:
        return None
    tests, suites, verdict, secs, clause = ms[-1]
    m = KNOWN_ISSUES_RE.search(clause)
    return {
        "tests": int(tests),
        "suites": int(suites),
        "passed": verdict == "passed",
        "seconds": float(secs),
        "known": int(m.group(1)) if m else 0,
    }


class XunitError(Exception):
    """An xunit file that could not be read even after sanitising."""


def parse_xunit(path):
    """-> (set of 'Module.Suite/test()' ids, set of failed ids, count).

    The sanitising step is not defensive programming, it is required: swift-
    testing writes failure messages verbatim, and this package's expectations
    quote ANSI escape sequences, so a failed comparison puts a raw 0x1b into an
    attribute. That is illegal in XML 1.0 and makes the file unparseable — and
    it happens only on a FAILING run, which is the one file the gate most needs
    to read. Strip the control characters rather than lose it.
    """
    ids, failed, n = set(), set(), 0
    if not os.path.exists(path):
        return ids, failed, n
    with open(path, "rb") as fh:
        raw = XML_ILLEGAL_RE.sub(b"", fh.read())
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        raise XunitError("%s is not parseable even sanitised (%s)" % (path, exc))
    for case in root.iter("testcase"):
        tid = "%s/%s" % (case.get("classname"), case.get("name"))
        ids.add(tid)
        n += 1
        if case.find("failure") is not None or case.find("error") is not None:
            failed.add(tid)
    return ids, failed, n


def durations_from_event_stream(path):
    """Per-test wall durations from a swift-testing v0 event stream.

    ONLY MEANINGFUL FROM A `--no-parallel` RUN. swift-testing starts tests with
    unbounded concurrency, so in a normal run nearly every test is "started"
    immediately and then sits queueing on the main actor: measured here, the
    median test "lasted" 49.05 s of a 53.1 s run and the durations summed to
    296,541 s. Those numbers describe the queue, not the test. The same run
    with --no-parallel gives a median of 0.11 ms and a sum that matches the
    reported suite time. `peak_concurrency` is the guard that tells the two
    apart before any of it is believed.
    """
    started, ended = {}, {}
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("kind") != "event":
                continue
            p = rec.get("payload", {})
            tid = p.get("testID")
            if not tid or "/" not in tid:  # suites have no '/', and we want tests
                continue
            when = p.get("instant", {}).get("absolute")
            if when is None:
                continue
            if p.get("kind") == "testStarted":
                started[tid] = when
            elif p.get("kind") == "testEnded":
                ended[tid] = when
    return {strip_source_location(t): ended[t] - started[t]
            for t in ended if t in started}


def peak_concurrency(path):
    """The most tests ever in flight at once in an event stream.

    1 means the run really was serial and its durations are costs. Anything
    higher means they are queueing times and must not become weights. This
    exists because the helper SILENTLY IGNORES flags it does not recognise, so
    `--no-parallel` going away in some future toolchain would not raise an
    error — it would quietly poison the weights instead.
    """
    marks = []
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("kind") != "event":
                continue
            p = rec.get("payload", {})
            tid, kind = p.get("testID"), p.get("kind")
            if not tid or "/" not in tid or kind not in ("testStarted", "testEnded"):
                continue
            when = p.get("instant", {}).get("absolute")
            if when is not None:
                marks.append((when, 1 if kind == "testStarted" else -1))
    marks.sort()
    live = peak = 0
    for _, delta in marks:
        live += delta
        peak = max(peak, live)
    return peak


def lpt(items, n):
    """Longest-processing-time-first bin packing. items: [(key, weight)]."""
    bins = [[] for _ in range(n)]
    loads = [0.0] * n
    for key, weight in sorted(items, key=lambda kv: -kv[1]):
        i = loads.index(min(loads))
        bins[i].append(key)
        loads[i] += weight
    return bins, loads


def build_items(ids, weights, n):
    """Group tests into packable items, splitting only the suites that need it.

    A suite is kept whole — related tests share fixtures and cache lines — but a
    suite heavier than one bin's fair share would set the critical path all by
    itself, so those are exploded into individual tests. The floor is then the
    single slowest TEST, which nothing can split further.
    """
    by_suite = {}
    for tid in ids:
        by_suite.setdefault(suite_of(tid), []).append(tid)
    suite_weight = {s: sum(weights.get(t, 0.0) for t in ts)
                    for s, ts in by_suite.items()}
    total = sum(suite_weight.values())
    fair = total / n if n else total
    items, split = [], []
    for s, ts in by_suite.items():
        if suite_weight[s] > fair and len(ts) > 1:
            split.append(s)
            items += [(("test", t), weights.get(t, 0.0)) for t in ts]
        else:
            items.append((("suite", s), suite_weight[s]))
    return items, split, total


def group_pattern(keys):
    """One `--filter` regex selecting exactly the given suites and tests."""
    bodies = []
    for kind, name in sorted(keys):
        pat = pattern_for_suite(name) if kind == "suite" else pattern_for_test(name)
        bodies.append(pat[1:])  # drop the per-alternative '^'; hoisted below
    return "^(?:" + "|".join(bodies) + ")"


def prove(patterns, ids):
    """Re-derive what each pattern selects and refuse anything but a partition.

    The proof runs in Python's regex engine while the selection will run in
    Swift's. They agree on this dialect, but 'agree' is an assumption, so the
    runtime `check_selection` gate re-checks the counts against these numbers
    from the processes' own output.
    """
    ids = set(ids)
    seen, dupes, counts = set(), set(), []
    for pat in patterns:
        rx = re.compile(pat)
        sel = {i for i in ids if rx.search(i)}
        dupes |= seen & sel
        seen |= sel
        counts.append(len(sel))
    return {
        "counts": counts,
        "union": len(seen),
        "missing": sorted(ids - seen),
        "extra": sorted(seen - ids),
        "dupes": sorted(dupes),
        "exact": seen == ids and not dupes,
    }


# ---------------------------------------------------------------- environment

def toolchain():
    """Locate swiftpm-testing-helper and the testing library beside it.

    Derived from the `swift` on PATH rather than assumed, so swiftly's default
    toolchain, an Xcode one and a CI one all resolve to their own helper.
    """
    info = json.loads(subprocess.run(
        ["swift", "-print-target-info"], capture_output=True, text=True,
        check=True).stdout)
    res = info.get("paths", info)["runtimeResourcePath"]      # <usr>/lib/swift
    usr = os.path.dirname(os.path.dirname(res))               # <usr>
    helper = os.path.join(usr, "libexec", "swift", "pm", "swiftpm-testing-helper")
    if not os.path.exists(helper):
        sys.exit("parallel-test: no swiftpm-testing-helper at %s" % helper)
    for platform in ("macosx", "linux", "windows"):
        lib = os.path.join(res, platform, "testing")
        if os.path.isdir(lib):
            return helper, lib
    sys.exit("parallel-test: no testing library under %s/*/testing" % res)


def bundle_path(bin_dir):
    """The Mach-O INSIDE the .xctest bundle — not the bundle directory, which
    the helper accepts and then fails to dlopen."""
    bundles = glob.glob(os.path.join(bin_dir, "*.xctest"))
    if len(bundles) != 1:
        sys.exit("parallel-test: expected one .xctest in %s, found %d"
                 % (bin_dir, len(bundles)))
    b = bundles[0]
    name = os.path.basename(b)[: -len(".xctest")]
    inner = os.path.join(b, "Contents", "MacOS", name)
    return inner if os.path.exists(inner) else os.path.join(b, name)


def child_env(base_lib, slot):
    """Per-process isolation.

    Each process gets its own config directory and TMPDIR: the persistence
    tests write real files under TUIKIT_CONFIG_DIR, and N processes sharing one
    would race. Everything else the suite touches that is process-global
    (signal handlers, TERM, fd 2, the colour report) is per-process already,
    which is the whole point of using processes.

    DYLD_LIBRARY_PATH must be set HERE, by this unprotected Python parent: SIP
    strips DYLD_* across a protected binary, so wrapping the helper in
    /usr/bin/time or /usr/bin/env silently breaks the dlopen.
    """
    env = dict(os.environ)
    env["DYLD_LIBRARY_PATH"] = base_lib
    for key, sub in (("TUIKIT_CONFIG_DIR", "config"), ("TMPDIR", "tmp")):
        d = os.path.join(WORK, "slot%d" % slot, sub)
        os.makedirs(d, exist_ok=True)
        env[key] = d
    return env


def helper_cmd(helper, bundle, filt, xunit=None, events=None, serial=False):
    cmd = [helper, "--test-bundle-path", bundle, bundle,
           "--testing-library", "swift-testing"]
    if filt:
        cmd += ["--filter", filt]
    if xunit:
        cmd += ["--xunit-output", xunit]
    if events:
        cmd += ["--event-stream-output-path", events, "--event-stream-version", "0"]
    if serial:
        cmd += ["--no-parallel"]
    return cmd


def select_ids(ids, pattern):
    """Apply a user `--filter` here rather than at the helper.

    `--list-tests` IGNORES `--filter`: asking it to list `^TUIkitViewTests\\.`
    returns all 7,573 tests, so a filtered run built from its output would
    quietly run the whole suite. Selecting in Python also keeps the partition
    proof authoritative — the groups are derived from exactly the set of IDs
    the reconciliation gate will demand back.
    """
    if not pattern:
        return list(ids)
    rx = re.compile(pattern)
    return [i for i in ids if rx.search(i)]


def list_tests(helper, bundle, lib):
    cmd = helper_cmd(helper, bundle, None) + ["--list-tests"]
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO,
                         env=child_env(lib, 0))
    ids = [l.strip() for l in out.stdout.splitlines() if l.strip() and "/" in l]
    if not ids:
        sys.exit("parallel-test: --list-tests returned nothing\n" + out.stderr[:2000])
    return sorted(set(ids))


def run_processes(cmds, lib, tags):
    """Spawn every process at once and reap in EXIT order.

    Each child writes to its own FILE. Never a pipe the parent drains in order:
    with N children and a 64 KiB pipe buffer, the parent blocks on the first
    child while the others block writing, and the run fabricates a perfect
    serialisation staircase that looks like a real finding.
    """
    procs = []
    t0 = time.time()
    for slot, (cmd, tag) in enumerate(zip(cmds, tags)):
        log = os.path.join(WORK, "out", tag + ".log")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        fh = open(log, "wb")
        # cwd MUST be the repo root: the localization-parity tests resolve
        # Sources/Example/Localization/Generated/ relative to it.
        p = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT,
                             cwd=REPO, env=child_env(lib, slot))
        procs.append({"p": p, "fh": fh, "t0": time.time(), "tag": tag, "log": log})
    by_pid = {r["p"].pid: r for r in procs}
    for _ in procs:
        pid, status, ru = os.wait4(-1, 0)
        r = by_pid[pid]
        r["wall"] = time.time() - r["t0"]
        r["rc"] = os.waitstatus_to_exitcode(status)
        r["cpu"] = ru.ru_utime + ru.ru_stime
        r["maxrss"] = ru.ru_maxrss
        r["fh"].close()
        r["p"].returncode = r["rc"]
    return procs, time.time() - t0


# ------------------------------------------------------------------- weights

def load_weights():
    if not os.path.exists(WEIGHTS):
        return {}, None
    try:
        with open(WEIGHTS) as fh:
            doc = json.load(fh)
        return doc.get("weights", {}), doc.get("generated")
    except (ValueError, OSError):
        return {}, None


def save_weights(weights, source):
    os.makedirs(WORK, exist_ok=True)
    with open(WEIGHTS, "w") as fh:
        json.dump({"version": 1, "source": source,
                   "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
                   "weights": weights}, fh)


def fill_weights(ids, weights):
    """Unknown tests get the work their suite has lost, or the median.

    A test the cache has never measured is usually one of two things: a test
    added to a new suite, which is as likely as any to be quick, so the median
    serves; or one of several tests a slow test was SPLIT into, which is the
    fix "Where the limit is" recommends. The median treated those pieces as
    near-free, so the partition dealt all of them to one process — ten pieces
    of a 48 s test made one group 67 s long, the very tail the split was meant
    to remove. So where a suite's recorded weights include tests that no
    longer exist, the work they recorded is shared among the suite's unknown
    tests, never below the median; the next --calibrate replaces the guess."""
    known = [weights[t] for t in ids if t in weights]
    median = sorted(known)[len(known) // 2] if known else 1.0
    current = set(ids)
    lost = defaultdict(float)
    for t, w in weights.items():
        if t not in current:
            lost[suite_of(t)] += w
    unknown_in = defaultdict(int)
    for t in ids:
        if t not in weights:
            unknown_in[suite_of(t)] += 1
    filled = {}
    for t in ids:
        if t in weights:
            filled[t] = weights[t]
        else:
            s = suite_of(t)
            filled[t] = max(median, lost[s] / unknown_in[s])
    return filled, len(ids) - len(known)


# --------------------------------------------------------------------- report

def machine_lock(path=LOCK_PATH, out=sys.stdout):
    """Takes the machine-wide run lock (`LOCK_PATH`), waiting for it if another
    run holds it, and returns the open file that holds it — keep it alive
    until the run ends. `None` where there is no `flock` (Windows)."""
    try:
        import fcntl
    except ImportError:
        return None
    fh = open(path, "a+")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fh.seek(0)
        holder = fh.read().strip() or "another run"
        print("parallel-test: waiting for %s (one run at a time on this machine)"
              % holder, file=out, flush=True)
        waited = time.time()
        fcntl.flock(fh, fcntl.LOCK_EX)
        print("parallel-test: waited %.0fs" % (time.time() - waited), file=out, flush=True)
    fh.seek(0)
    fh.truncate()
    fh.write("pid %d in %s" % (os.getpid(), REPO))
    fh.flush()
    return fh


def plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def main():
    ap = argparse.ArgumentParser(
        description="Run the test suite across N processes, with reconciliation.")
    ap.add_argument("-j", "--jobs", type=int, default=0,
                    help="processes (default: 6, or half the cores if fewer)")
    ap.add_argument("--filter", default=None,
                    help="regex; restrict the run to matching tests")
    ap.add_argument("--calibrate", action="store_true",
                    help="one single-process run that re-measures the weights")
    ap.add_argument("--plan-only", action="store_true",
                    help="print the partition and its proof, run nothing")
    ap.add_argument("--no-build", action="store_true",
                    help="skip `swift build --build-tests`")
    ap.add_argument("--expect-known-issues", type=int, default=None,
                    help="fail unless the known-issue total equals this")
    ap.add_argument("--json", default=None, help="write the full result as JSON")
    args = ap.parse_args()

    # Before the build, which is half of what two runs at once would fight over.
    lock = None if args.plan_only else machine_lock()  # noqa: F841 — held until exit
    started = time.time()
    cores = os.cpu_count() or 4
    jobs = args.jobs or max(1, min(6, cores // 2))
    if args.calibrate:
        jobs = 1

    helper, lib = toolchain()

    if not args.no_build:
        # The ONLY place the SwiftPM build database is touched. Everything
        # after this is the helper, which never opens it.
        rc = subprocess.run(["swift", "build", "--build-tests"], cwd=REPO).returncode
        if rc != 0:
            return 2
    bin_dir = subprocess.run(["swift", "build", "--show-bin-path"], cwd=REPO,
                             capture_output=True, text=True, check=True).stdout.strip()
    bundle = bundle_path(bin_dir)

    ids = select_ids(list_tests(helper, bundle, lib), args.filter)
    if not ids:
        sys.exit("parallel-test: --filter %r matched no tests" % args.filter)
    print("parallel-test: %s in %s, %d process%s"
          % (plural(len(ids), "test"),
             plural(len({suite_of(i) for i in ids}), "suite"),
             jobs, "" if jobs == 1 else "es"))

    raw_weights, generated = load_weights()
    weights, unweighted = fill_weights(ids, raw_weights)
    if raw_weights:
        print("parallel-test: weights from %s (%d test%s unweighted)"
              % (generated, unweighted, "" if unweighted == 1 else "s"))
    else:
        print("parallel-test: no weight cache — splitting by test count. "
              "Run --calibrate once to measure them.")

    items, split, total = build_items(ids, weights, jobs)
    bins, loads = lpt(items, jobs)
    patterns = [group_pattern(b) for b in bins]
    proof = prove(patterns, ids)

    if not proof["exact"]:
        print("parallel-test: PARTITION PROOF FAILED — refusing to run")
        print("  union %d of %d; %d missing, %d extra, %d duplicated"
              % (proof["union"], len(ids), len(proof["missing"]),
                 len(proof["extra"]), len(proof["dupes"])))
        for label in ("missing", "extra", "dupes"):
            for t in proof[label][:5]:
                print("    %s: %s" % (label, t))
        return 2

    print("parallel-test: partition proved — %d of %d selected exactly once%s"
          % (proof["union"], len(ids),
             (", %d heavy suite%s split by test"
              % (len(split), "" if len(split) == 1 else "s")) if split else ""))
    for i, (b, load) in enumerate(zip(bins, loads)):
        print("  group %d: %5d tests  %4d item%s  predicted %6.2fs"
              % (i, proof["counts"][i], len(b), " " if len(b) == 1 else "s", load))

    # Where more processes stop paying. A single test cannot be split, so the
    # critical path can never fall below the slowest one; past that point a
    # larger -j only adds processes that finish early and wait.
    if raw_weights and weights:
        slowest = max(weights, key=weights.get)
        heaviest = weights[slowest]
        useful = int(math.ceil(total / heaviest)) if heaviest > 0 else jobs
        print("  floor: %s alone takes %.2fs, so -j beyond %d cannot help"
              % (slowest, heaviest, max(1, useful)))

    if args.plan_only:
        return 0

    shutil.rmtree(os.path.join(WORK, "out"), ignore_errors=True)
    os.makedirs(os.path.join(WORK, "out"), exist_ok=True)
    tags = ["g%d" % i for i in range(jobs)]
    cmds = [helper_cmd(helper, bundle, pat,
                       xunit=os.path.join(WORK, "out", "%s.xml" % t),
                       events=os.path.join(WORK, "out", "%s.jsonl" % t),
                       serial=args.calibrate)
            for pat, t in zip(patterns, tags)]
    procs, wall = run_processes(cmds, lib, tags)

    # ------------------------------------------------------------ reconcile
    union, failed, counted, known = set(), set(), 0, 0
    problems = []
    for i, r in enumerate(procs):
        gi = tags.index(r["tag"])
        xml = os.path.join(WORK, "out", "%s.xml" % r["tag"])
        try:
            gids, gfailed, n = parse_xunit(xml)
        except XunitError as exc:
            gids, gfailed, n = set(), set(), 0
            problems.append("group %s: %s" % (r["tag"], exc))
        with open(r["log"], errors="replace") as fh:
            summary = parse_summary_text(fh.read())
        r["summary"], r["selected"], r["ran"] = summary, proof["counts"][gi], n
        counted += n
        union |= gids
        failed |= gfailed
        if summary is None:
            problems.append("group %s produced no summary line (see %s)"
                            % (r["tag"], r["log"]))
        else:
            known += summary["known"]
            # The helper ignores flags it does not recognise and then runs
            # EVERYTHING, so a count that disagrees with the proof is the only
            # way to catch a filter that silently stopped filtering.
            if summary["tests"] != r["selected"]:
                problems.append(
                    "group %s ran %d tests, the partition predicted %d"
                    % (r["tag"], summary["tests"], r["selected"]))
        # A group can report a failure that xunit never names. An issue
        # recorded with no test in the task-local context is attributed to
        # «unknown» and produces no <failure> element, so `gfailed` is empty
        # for a run that genuinely failed. Measured here with a probe that
        # records from a detached Task: rc 1, zero <failure> elements, and
        # `failed after 0.001 seconds with 1 issue.` — the summary shape that
        # until now did not parse, which is how this case used to be caught,
        # by accident, as a missing summary line. The exit code covers every
        # failing shape reproduced so far; the parsed verdict is read as well
        # so the gate does not rest on the helper always exiting non-zero.
        if not gfailed and (r["rc"] != 0
                            or (summary is not None and not summary["passed"])):
            problems.append("group %s reported a failure (exit %d) that no test "
                            "accounts for (see %s)" % (r["tag"], r["rc"], r["log"]))

    missing, extra = sorted(set(ids) - union), sorted(union - set(ids))
    if missing or extra or counted != len(union):
        problems.append("union %d of %d expected — %d missing, %d extra, %d duplicated"
                        % (len(union), len(ids), len(missing), len(extra),
                           counted - len(union)))
    if args.expect_known_issues is not None and known != args.expect_known_issues:
        problems.append("known issues %d, expected %d"
                        % (known, args.expect_known_issues))

    suites = {suite_of(t) for t in union}
    cpu = sum(r["cpu"] for r in procs)
    print()
    for i, r in enumerate(procs):
        s = r["summary"]
        print("  group %s: %5d tests  %6.2fs wall  %6.1fs cpu  %s"
              % (r["tag"], r["ran"], r["wall"], r["cpu"],
                 "ok" if s and s["passed"] else "FAILED"))
    print()

    ok = not problems and not failed
    print("parallel-test: %s in %s %s in %.2fs across %d process%s "
          "(%.2fs end to end, %.1f cpu-s, %.1fx cores) with %s"
          % (plural(len(union), "test"), plural(len(suites), "suite"),
             "passed" if ok else "FAILED", wall, jobs, "" if jobs == 1 else "es",
             time.time() - started, cpu, cpu / wall if wall else 0,
             plural(known, "known issue")))

    for t in sorted(failed):
        print("  FAILED: %s" % t)
    for p in problems:
        print("  RECONCILIATION: %s" % p)
    for t in missing[:10]:
        print("    never ran: %s" % t)
    for t in extra[:10]:
        print("    not enumerated: %s" % t)

    # Weights come only from --calibrate, and only if the stream proves the run
    # stayed serial. An ordinary parallel run's durations are queueing times;
    # writing those back would let the partition chase its own tail.
    #
    # A calibration is a MEASUREMENT, not a gate, so it writes the table even
    # when tests failed: a failure does not make a duration wrong. It matters
    # here because running this suite serially currently fails a handful of
    # tests outright — they depend on the interleaving a parallel run happens
    # to give them. What a calibration will not do is trust a run that was not
    # really serial, or one that failed to time every test.
    if args.calibrate and not args.filter:
        ev = os.path.join(WORK, "out", "%s.jsonl" % procs[0]["tag"])
        peak = peak_concurrency(ev) if os.path.exists(ev) else 0
        if peak != 1:
            print("parallel-test: NOT writing weights — the calibration ran %d "
                  "tests at once, so its durations are queueing times, not "
                  "costs (is --no-parallel still honoured?)" % peak)
            return 2
        measured = durations_from_event_stream(ev)
        if len(measured) != len(ids):
            print("parallel-test: NOT writing weights — timed %d of %d tests"
                  % (len(measured), len(ids)))
            return 2
        save_weights(measured, "calibrate")
        print("parallel-test: wrote weights for %d tests (serial run confirmed, "
              "%.1fs of measured work)" % (len(measured), sum(measured.values())))

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"wall": wall, "cpu": cpu, "jobs": jobs, "ok": ok,
                       "tests": len(union), "suites": len(suites),
                       "known": known, "failed": sorted(failed),
                       "problems": problems,
                       "groups": [{"tag": r["tag"], "wall": r["wall"],
                                   "cpu": r["cpu"], "ran": r["ran"],
                                   "predicted": r["selected"],
                                   "maxrss": r["maxrss"]} for r in procs]}, fh, indent=1)

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
