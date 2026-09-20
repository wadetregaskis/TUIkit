# Running the test suite in parallel

`parallel_test.py` runs the whole suite in several processes instead of one and
refuses to report success unless it can prove every test ran exactly once.

```bash
Tools/ParallelTest/parallel_test.py --calibrate   # once, ~95 s
Tools/ParallelTest/parallel_test.py -j 12         # thereafter; the flag's own
                                                  # default is 6, see below
```

Re-measured at `3fadcb1d`, after the test splits in `a7bdea3f` and `638dd69f`,
12 logical cores / 16 GiB. These are the suite times each command reports for
itself, which is the only figure the build cost below cannot distort:

| command | median suite wall | range | reps | sd | speedup |
|---|---:|---|---:|---:|---:|
| `swift test` | 54.10 s | 52.22–58.14 | 4 | 2.50 | 1.00x |
| `parallel_test.py -j 1` | 56.66 s | — | 1 | — | 0.95x |
| `parallel_test.py -j 6` | 20.73 s | 19.55–21.58 | 6 | 0.74 | 2.61x |
| `parallel_test.py -j 8` | 17.32 s | 16.87–18.19 | 4 | 0.55 | 3.12x |
| `parallel_test.py -j 12` | **13.96 s** | 13.41–14.90 | 10 | 0.59 | **3.88x** |

That is **−40.1 s per run at `-j 12`**, or about 6.7 hours across a 600-run
landing batch. Three paired reps with the arm order randomised per rep agreed
on every arm, same sign in every rep: `-j 6` − `-j 12` = +6.64 s, `-j 8` −
`-j 12` = +3.47 s, `swift test` − `-j 12` = +40.14 s. The ±2.4 s band this repo
quotes for wall-clock noise is a SINGLE-PROCESS figure and does not apply to
these arms — their own sd is 0.55–0.74 s, which is what makes the 3.5 s between
`-j 8` and `-j 12` readable at all.

**The curve has not flattened at 12**, even though the floor is far below it
(see "Where the limit is"). At `-j 12` the run reaches 10.2x cores on a 12-core
machine: what binds is the machine, not the slowest test.

Those are suite times. The wall you wait for adds about 1.5 s of enumeration,
planning and reconciliation, plus the incremental build — and the build is
bimodal. Two consecutive `swift build --build-tests` cost 0.3 s, but the first
one **after a `swift test` costs 6.5–7.2 s** (5 of 5 observed; a repeat
`-j 12` run therefore lands around 16.3 s of wall, and one following a
`swift test` around 22 s). Alternating the two routes pays that toll each time;
a landing batch that stays on one route does not. A handful of expensive builds
were also seen with no `swift test` before them, and those are unattributed —
touching `.build`, and `--plan-only`'s `swift build --show-bin-path`, were both
ruled out by direct probe.

Memory, at `-j 12` on 16 GiB: the twelve test processes peaked at 2,576 MiB of
combined RSS (`ps` RSS, which counts shared pages once per process, so this
over-estimates), the largest single one 265 MiB. `swift test` peaks lower in
total, 1,177 MiB, but far higher in one process, 1,031 MiB. No arm touched
swap: `vm.swapusage` read `total = 0.00M` before, during and after every run,
the compressor never moved, and there were no swapins or swapouts. `-j 12` is
comfortable on this machine; the ceiling is cores, not RAM.

## Why one process is slow

81% of this package's tests live in `@MainActor` suites. swift-testing already
runs suites concurrently *within* a process, so they all queue on that one
actor. Stack sampling from the experiment that preceded this harness — same
HEAD, not re-measured here — puts 77% of the late-regime CPU in
`syscall_thread_switch`, `__workq_kernreturn` and `__ulock_wait2`: eleven
cooperative-pool threads burning CPU taking turns rather than doing work.

Each process has its own main actor, so N processes turn that contention back
into throughput. The measurement that makes the point: one process spends
~57 s of wall and ~171 CPU-seconds; twelve processes finish the same tests in
~14 s for ~142 CPU-seconds — less total CPU, not more, because the CPU the one
process spent taking turns was never work.

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
* every process produced a parseable summary line, and any process that
  reports a failure is accounted for by a named failing test.

All 21 full-suite harness runs in the session that built this, at `-j 3`
through `-j 8`, reconciled to 7,573 tests / 1,081 suites / 21 known issues. A
later 25-run pass at `-j 1` through `-j 12` reconciled to 7,591 / 1,082 / 21,
every run, including the four runs that had a failing test.

### Reading the summary line

`parse_summary_text` used to match the final line shape by shape, and knew
three of the eight shapes the clause after `seconds` takes. A group that fails
with **no known issues of its own** ends `failed after N seconds with 1 issue.`
— neither `N known issues` nor `N issues (including M known issues)` — so it
matched nothing, and the gate reported "produced no summary line" for a group
that had in fact run and simply failed. That is the wording trap 1 gives a
process that died having run nothing, printed against the one group holding the
real failure. Seen twice, both at `-j 6`.

The clause is now captured whole and the known-issue count read out of it by
name, so all eight parse. The eight below are the literal output of a probe
package run against the toolchains, not transcribed from upstream source:
6.2.4 for the four without a warning, 6.3.3 for the four with one, because
6.2.4 ships no `Issue.Severity` and cannot record a warning-severity issue at
all. Five of the eight did not parse before; the four reachable on 6.2.4 are
marked.

| errors | warnings | known | verdict | clause after `seconds` | 6.2.4 |
|---|---|---|---|---|---|
| – | – | – | passed | *(none)* | yes |
| – | – | 3 | passed | ` with 3 known issues` | yes |
| – | 2 | – | passed | ` with 2 warnings` | – |
| – | 2 | 3 | passed | ` with 2 warnings and 3 known issues` | – |
| 1 | – | – | failed | ` with 1 issue` | yes |
| 2 | – | 3 | failed | ` with 5 issues (including 3 known issues)` | yes |
| 2 | 3 | – | failed | ` with 5 issues (including 3 warnings)` | – |
| 2 | 3 | 4 | failed | ` with 9 issues (including 3 warnings and 4 known issues)` | – |

Capturing the clause rather than enumerating it trades one failure mode for a
smaller one: a future rewording costs the known-issue count, which silently
reads 0, instead of costing the whole line. `--expect-known-issues` is the
cross-check for that, and the count this suite should report is 21. What the
fix restores is the trap-2 guard — the per-group `tests ran == tests predicted`
check, which was being skipped for exactly the group that failed.

One thing the unparseable line was doing by accident had to be replaced. An
issue recorded with no test in the task-local context is attributed to
`«unknown»` and produces no `<failure>` element, so a run can genuinely fail
with nothing in the xunit file to name; measured with a probe recording from a
detached `Task`, that run exits 1, writes zero `<failure>` elements, and ends
`failed after 0.001 seconds with 1 issue.` — the shape that did not parse. The
exit code catches it, and catches every failing shape reproduced so far, but
the gate now also reads the verdict it parses rather than resting on the helper
always exiting non-zero.

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
(it returns all 7,591 whatever you ask for) is worked around by filtering in
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
move the floor is splitting such a test into several FUNCTIONS, which is what
`PaletteSearchIndexTests` and `MenuHeightCeilingTests` now do. Re-measured
serially at this HEAD:

| test | cost alone |
|---|---:|
| `TUIkitTests.MenuHeightCeilingTests/popUpReachesItsLastRowAtItsLongest(count:)` | 3.85 s |
| `TUIkitTests.ColorPickerPanelCrashSafetyTests/keyEventMonkeyDoesNotTrap()` | 3.79 s |
| `TUIkitTests.MenuMeasureParityTests/everyWidthAgrees(rows:)` | 3.79 s |

Against 104.9 s of total serial work, that floor binds at about `-j 28`; beyond
it the extra processes finish early and wait. The harness prints the floor and
the `-j` past which it cannot help as part of its plan.

That floor was **12.21 s** before these splits, and the four tests that set it
are the four that moved: `gamutSampleAgrees(_:)` and `cornersAgree(_:)` each
walked all four palettes in one function, and both menu tests rendered 50-,
5,000- and 9,000-row menus in one. Fifteen functions now cover exactly what
those four covered — same pixels, same palettes, same lengths, same assertions
— and the suite went from 7,573 tests to 7,585. It enumerates 7,591 today; the
extra six are `561f7f0b`'s new conversion suite, not these splits'.

Treat the totals in this section as ±4 s. Three calibrations of this tree read
86.8 s, 99.8 s and 104.9 s, and most of that movement is not the splits: five
commits landed between the first two, and between the second and third — where
only the menu file was edited, worth +0.4 s — everything NOT edited still grew
3.9 s. One calibration is a single serial sample of a debug build, not a
constant.

`-j 6` remains the flag's default, but the reliability argument that chose it
no longer holds. Re-measured over 25 runs, `-j 6` was the *least* clean arm —
4/6, against 4/4 for `-j 8`, 8/10 for `-j 12` and 4/4 for `swift test` — and
both of its failures were a wall-clock budget that a loaded box fails, not
anything about six processes. `-j 12` is both the fastest arm and no worse for
reliability, so pass it explicitly; the default is left alone because changing
it is a code change, not a documentation one.

## Known order dependence, and flakes

Running serially — which only `--calibrate` does — fails one test outright:
`TUIkitTests.TranslucentGroundTests/rootBackgroundCodes()` reads background
codes another test leaves set, so it passes only under the interleaving a
parallel run happens to give it. Calibration reports the failure and still
writes the table, because a failure does not make a duration wrong.

Re-measured over 25 full-suite runs — 10 at `-j 12`, 6 at `-j 6`, 4 each at
`-j 8` and `swift test`, 1 at `-j 1` — of which 21 were clean. **The three
flakes this file used to list are gone**; none fired once:

| test | was | now | what closed it |
|---|---|---:|---|
| `FrameClockTests/defaultIsNow()` | 1/7 at `-j 8` | 0/25 | `561f7f0b` |
| `FrameBufferCombineScalingTests/verticalAppendWithKnownWidthsIsNotQuadratic()` | 1/8 at `-j 6` | 0/25 | `3fadcb1d` |
| `TerminalFocusPhaseTests/backgroundIgnoresReports(isFocused:)` | 2/7 single | 0/25 | probably `1d6eacd9` |

Its `AppState.shared` sibling `RunLoopFoldTests/idleIterationIsQuiet()` did not
fire either. Attributing the third to `1d6eacd9` is inference from what that
commit changed, not something these runs prove: 25 runs cannot distinguish a
fixed 2-in-7 flake from a lucky one, and nothing here re-measured it before.

One remains. The other was a **product defect, not a flaky test**, and is now
closed:

* **Fixed.** `ListRenderTests/emptyDefaultPlaceholder()` and
  `SnapshotCorpusTests/corpus()` used to fail **together**, 2 of 10 runs at
  `-j 12`, always in the same process, with the placeholder in Japanese:

  ```
  (joined → "╭────────╮│項目がありません│…").contains("No items")
  ```

  `LocalizationService.shared` is a lazy `public static let`, so its first
  touch in a process is what fixes its language, and `init()` asks
  `systemPreferredLanguage()`, whose `environment:` argument defaults to the
  live `ProcessInfo.processInfo.environment`. Meanwhile
  `LocalizationServiceTests/processEnvironmentIsTheDefault()` did
  `setenv("LC_ALL", "ja_JP.UTF-8", 1)` process-wide for the length of one test.
  Any test that first touched `.shared` inside that window latched Japanese for
  the **rest of the process**, and every view resolving `label.noItems` through
  `ViewConstants+Localized` then drew it. That test's own comment reasoned the
  `setenv` was safe because "neither Foundation's locale nor any other suite
  reads it" — `LocalizationService.init()` does, through the defaulted
  argument. Same shape as `561f7f0b`: a lazy global whose defect is *when* it
  is first touched.

  Closed from both ends, and the halves are worth telling apart. `76cd4d05`
  gave every suite that asserts the framework's own English words a
  `.rendersEnglishUI` trait, which pins English before that suite runs, so no
  earlier touch of `.shared` decides what it renders — measured on the filter
  that made the latch deterministic (`LanguageDetectionTests|ListRenderTests`,
  15 failures in 15 before), that alone took it to 0 of 15. The `setenv` then
  went as well, because setting a process-wide environment variable inside an
  in-process parallel runner is a hazard to every lazily-initialised global and
  not only to this one.

* `RenderBottleneckTests/analyzeForEachIterations()` failed 2 of 6 runs at
  `-j 6` — `#expect(time10 < 0.5)`, a wall-clock budget, which is the shape
  `3fadcb1d` fixed elsewhere by measuring thread CPU time instead. It is
  load-sensitive by construction and is not evidence about the partition.

What the harness cannot fix stays true: swift-testing already runs suites
concurrently inside one process, so process-global state — `AppState.shared`,
`LocalizationService.shared`, the process environment — is contended whether or
not the suite is split across processes.

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

36 tests covering the parts that can be tested without running the suite: ID
escaping and pattern anchoring, the partition proof rejecting a gap or an
overlap, bin packing, both weight paths, all eight shapes of the summary line
in both their singular and plural wordings, the malformed-xunit recovery, and
the event-stream duration join.

Four of those are a negative control on the summary parser and are the reason
to run it after touching `SUMMARY_RE`: a log with no run summary in it — empty,
build-lock-starved, per-test lines only, or cut off mid-line — must keep
returning `None`. A parse there would cost the gate its only sight of trap 1,
which is worse than the misreporting the parser was widened to fix.
