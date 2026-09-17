# Running the test suite in parallel

`parallel_test.py` runs the whole suite in several processes instead of one and
refuses to report success unless it can prove every test ran exactly once.

```bash
Tools/ParallelTest/parallel_test.py --calibrate   # once, ~95 s
Tools/ParallelTest/parallel_test.py               # thereafter, -j 6 by default
```

Measured on this repository at `510e0ad0`, 12 logical cores / 16 GiB, medians of
four consecutive runs per arm with the first discarded:

| command | median wall | range | speedup |
|---|---:|---|---:|
| `swift test` | 54.71 s | 52.53–57.08 | 1.00x |
| `parallel_test.py -j 6` | **21.79 s** | 21.10–21.92 | **2.51x** |
| `parallel_test.py -j 8` | 17.44 s | 17.20–17.70 | 3.14x |

That is **−32.9 s per run at `-j 6`**, or about 5.5 hours across a 600-run
landing batch. A paired A/B with the arm order randomised per rep agreed:
+40.9 s median paired difference for `-j 6`, +37.4 s for `-j 4`.

Those walls are end to end — they include the incremental build, the
enumeration and the planning done before anything is spawned, which together
cost about 1.6 s when the harness is run repeatedly. Running it straight after
a `swift test` or `swift build` costs roughly 6.6 s more, because SwiftPM
recompiles its plugins: measured 26.93 s end to end immediately after a build,
then 20.33 s on the very next run. A landing batch pays the cheap number.

## Why one process is slow

81% of this package's tests live in `@MainActor` suites. swift-testing already
runs suites concurrently *within* a process, so they all queue on that one
actor. Stack sampling from the experiment that preceded this harness — same
HEAD, not re-measured here — puts 77% of the late-regime CPU in
`syscall_thread_switch`, `__workq_kernreturn` and `__ulock_wait2`: eleven
cooperative-pool threads burning CPU taking turns rather than doing work.

Each process has its own main actor, so N processes turn that contention back
into throughput. The measurement that makes the point: a single process spends
~53 s of wall and ~175 CPU-seconds; eight processes finish the same tests in
~16 s for roughly the same total CPU.

## It is not a substitute for `swift test`

CI runs `swift test`, in one process, exactly the way a contributor does, and
that stays the gate. This harness is a local accelerant for anyone running the
suite repeatedly. It differs in three ways worth knowing:

* **Different interleaving.** Tests are spread across processes, so anything
  depending on the order a single process happens to give them can behave
  differently. That is a property of the test, not of the harness — see
  "Known order dependence" below.
* **Different driver.** It invokes `swiftpm-testing-helper` directly rather than
  going through `swift test` (see "Why not `swift test --filter`").
* **No XCTest.** The package has none; the harness drives swift-testing only.

## Usage

| flag | meaning |
|---|---|
| `-j N` | processes; default 6, or half the cores if fewer |
| `--calibrate` | one serial run that re-measures the weight table |
| `--plan-only` | print the partition and its proof, run nothing |
| `--filter REGEX` | restrict to matching test IDs (`Module.Suite/test()`) |
| `--no-build` | skip `swift build --build-tests` |
| `--expect-known-issues N` | fail unless the known-issue total is exactly N |
| `--json PATH` | write the full result, per group, as JSON |

`--calibrate` writes `.build/parallel-test/weights.json`. It is worth re-running
when the suite has grown a lot, but it is not required for correctness: the
groups are always derived at runtime from `--list-tests`, and a test the cache
has never seen is given the median weight and runs anyway.

## The reconciliation gate

Speed is worthless if a process quietly runs nothing, so every run is gated on:

* the union of test IDs equals the enumerated suite exactly — no missing, no
  extra, nothing run twice;
* every process ran exactly the number of tests the static proof predicted;
* every process produced a parseable summary line and exited 0.

All 21 full-suite harness runs in the session that built this, at `-j 3`
through `-j 8`, reconciled to 7,573 tests / 1,081 suites / 21 known issues.

## Four traps this is built around

Each of these was measured here, and each one shapes the code.

**1. `swift test --filter` cannot be used to shard.** Concurrent `swift test`
invocations serialise on the SwiftPM build-database lock — four concurrent 1.6 s
runs took 7.3 s — and a lock-starved process can die with "database is locked /
no tests found" having run *nothing*: one run in four silently lost 2,168 tests
while being the slowest of the set. So the build lock is taken exactly once, up
front, and the test processes are `swiftpm-testing-helper` invocations that
never open it.

**2. The helper silently ignores flags it does not recognise.** Passing
`--no-such-flag` does not error — it runs the entire suite. A typo, or a future
toolchain renaming `--filter`, would therefore make every process run everything
and still "pass". That is why each process's reported test count is checked
against the partition's prediction, and why `--list-tests` ignoring `--filter`
(it returns all 7,573 whatever you ask for) is worked around by filtering in
Python instead.

**3. A test's apparent duration is not its cost.** swift-testing starts tests
with unbounded concurrency, so in an ordinary run they nearly all start at once
and then queue: the median test "lasted" 49.05 s of a 53.1 s run, and the
durations summed to 296,541 s. The xunit `time` attribute has the same shape —
both are really completion timestamps. Weights therefore come only from a
serial `--calibrate` run, and are written only if the event stream proves the
run actually stayed serial (peak concurrency 1).

**4. A failing run's xunit is not well-formed XML.** Failure messages are
written verbatim, and this package's expectations quote ANSI escapes, so a
failed comparison puts a raw `0x1b` into an attribute — illegal in XML 1.0. The
file the gate most needs to read is exactly the one that will not parse, so
control characters are stripped before parsing.

## Where the limit is

The critical path can never fall below the slowest single test, because nothing
can split one test — and a test parameterised over N arguments is ONE test
here: the weights are keyed by test ID, so `foo(_:)` has a single weight
covering every argument, and no partition can deal its arguments out. What does
move the floor is splitting such a test into several FUNCTIONS, which is why
`PaletteSearchIndexTests` now asks its question from ten of them rather than
two. Re-measured serially at this HEAD:

| test | cost alone |
|---|---:|
| `TUIkitTests.MenuHeightCeilingTests/popUpReachesItsLastRow(count:)` | 5.73 s |
| `TUIkitTests.MenuHeightCeilingTests/inlineScrollsAtAnyLength(count:)` | 5.51 s |
| `TUIkitTests.MenuMeasureParityTests/everyWidthAgrees(rows:)` | 3.74 s |

Against 99.8 s of total serial work, that floor binds at about `-j 18`; beyond
it the extra processes finish early and wait. The harness prints the floor and
the `-j` past which it cannot help as part of its plan.

`PaletteSearchIndexTests/gamutSampleAgrees(_:)` headed that table at 12.21 s,
with `cornersAgree(_:)` second at 5.57 s; the pair's worst single test is now
2.96 s, and the suite enumerates 7,583 tests rather than 7,573. Both totals
here are a fresh serial measurement, not a delta against the 86.8 s this
section used to quote: five commits landed between that calibration and this
one, and the work they added — a wait whose deadline went to 60 s among it —
is most of the difference. Splitting the palette suite accounted for +1.4 s of
it, one index build per palette per process being the price of the split.

`-j 6` is the default rather than `-j 8` because it was the only arm that never
failed a run (7/7 clean, against 5/7 for both `-j 8` and single-process), it
leaves half the machine for whatever else is running, and the 4.4 s it gives up
is within the noise band this repo uses for wall-clock comparisons.

## Known order dependence, and flakes

Running serially — which only `--calibrate` does — fails one test outright:
`TUIkitTests.TranslucentGroundTests/rootBackgroundCodes()` reads background
codes another test leaves set, so it passes only under the interleaving a
parallel run happens to give it. Calibration reports the failure and still
writes the table, because a failure does not make a duration wrong.

Two tests failed intermittently across the runs that built this harness, and
**the flakiest arm was plain `swift test`**, not the partition:

| test | single | `-j 6` | `-j 8` |
|---|---:|---:|---:|
| `TerminalFocusPhaseTests/backgroundIgnoresReports(isFocused:)` | **2/7** | 0/7 | 1/7 |
| `FrameClockTests/defaultIsNow()` | 0/7 | 0/7 | 1/7 |

The first asserts `#expect(!AppState.shared.needsRender)` on a process-global
singleton, and it fails under plain `swift test` more often than under any
partition. The second failed as `(first → 0) > 0` — `FrameClock.nowNanos`
returned zero — which looks like a defect in the clock rather than a timing
race, and is worth a look independently of this harness.

They share a cause the harness cannot fix: swift-testing already runs suites
concurrently inside one process, so global state such as `AppState.shared` is
contended whether or not the suite is split across processes.

## Portability

Written for macOS, which is where the speedup was measured. The toolchain is
discovered from the `swift` on `PATH` rather than assumed, and Linux and Windows
testing-library paths are tried, but neither has been exercised. On a 2–4 core
CI runner the win would shrink toward the core count, which is another reason CI
keeps running plain `swift test`.

## Tests

```bash
python3 Tools/ParallelTest/test_parallel_test.py
```

31 tests covering the parts that can be tested without running the suite: ID
escaping and pattern anchoring, the partition proof rejecting a gap or an
overlap, bin packing, both weight paths, all four shapes of the summary line,
the malformed-xunit recovery, and the event-stream duration join.
