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

## CI runs it

CI's macOS and Linux lanes run the suite through this harness —
`python3 Tools/ParallelTest/parallel_test.py -j 4 --no-build
--full-failing-logs`, after their own `swift build --build-tests` — and no
longer through `swift test`. One `swift test` process queues every
`@MainActor` test on one main actor however many cores the runner has; whole-
suite runs there had grown from 120–290 s (early 2026-09) to 290–650 s, and on
2026-09-28 the trunk lane's 640.6 s run outlasted a test's 600 s `Task.sleep`
and failed it (`LifecycleManagerTests`, fixed in `a3bb5790`). The Windows lanes
still run `swift test`: they are advisory for tests, and the harness does not
support Windows.

`-j 4` is an experiment, to be tuned from the lanes' own timings. GitHub's
arm64 macOS runners have 3 M1 cores and 7 GB, the Linux ones 4 cores and
16 GB. Four processes oversubscribe the macOS CPU slightly, deliberately — much
of their time is spent waiting on their own main actor — and the macOS memory
is the risk: the only figures are this machine's (~265 MiB per process split
twelve ways, ~1 GiB for the whole suite in one), not a runner's. CI has no
weight cache, so the groups are split by test COUNT, not cost: at `-j 4` here
that gave one group 147 s and another 46 s, so the critical path is roughly
twice what balanced groups would give. A committed weight table, or a smaller
`-j` on macOS, are the obvious next tunings.

It still differs from `swift test` in three ways worth knowing:

* **Different interleaving.** Tests are spread across processes, so anything
  depending on the order a single process happens to give them can behave
  differently. That is a property of the test, not of the harness — see
  "Known order dependence" below.
* **Different driver.** It invokes `swiftpm-testing-helper` (on Linux, the test
  binary) directly rather than going through `swift test`, with the arguments
  and environment `swift test` would use (see "Toolchains and platforms"), so
  that the processes never touch the build database (trap 1 below).
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
| `--full-failing-logs` | print the whole log of every failing process, not only its issues |
| `--json PATH` | write the full result, per group, as JSON |

| environment | meaning |
|---|---|
| `SWIFT` | the `swift` to build, list and run with, e.g. `xcrun --toolchain org.swift.640202609131a swift`; default `swift` from `PATH` |
| `TUIKIT_PARALLEL_TEST_LOCK` | the run lock's path (see below) |

`--calibrate` writes `.build/parallel-test/weights.json`. It is worth re-running
when the suite has grown a lot, but it is not required for correctness: the
groups are always derived at runtime from `--list-tests`, and a test the cache
has never seen is given the median weight and runs anyway.

## One run at a time

A run takes a machine-wide lock (`/tmp/tuikit-parallel-test.lock`, or
`$TUIKIT_PARALLEL_TEST_LOCK`) before it builds, so a second run — from another
worktree, or an agent — waits for the first and says whose run it is waiting
for. One run already fills half the cores with test processes; on the 16 GiB
machine this is used on, two at once, with their builds, push each other into
memory compression and swap, so each is slower and the pair is slower than the
same two in turn. It is a `flock`, which the kernel drops when its holder
exits however it exits, so a crashed run cannot leave the next one waiting.
`--plan-only` runs nothing and takes no lock. There is no lock on Windows,
which has no `flock`.

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
cross-check for that. The count this suite should report was 21 when this was
written; it was 62 by 2026-09-28, and is 64 since the two checks that
`ProcessWideState` refuses a write outside an exit test. What the
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

**2026-09-28: the floor had crept back to 47.5 s.** One test,
`ReplayedRunFieldTests/everyTickMatchesARender(ground:)`, walked a catalogue of
controls through the run loop on ten grounds in one function, and had grown
into 23% of the suite's 204.5 s of serial work; every `-j 12` run waited for
it alone (55.8 s calibrated, 76 s from a cold cache). It is ten functions now,
one per ground, and a `-j 12` run on a calibrated cache finishes in **32.2 s**.
A split like that used to cost one bad run first: tests the cache has never
measured were priced at the median — near-free — so all ten pieces went to one
process (67 s). An unmeasured test is now priced at its suite's share of the
work the cache recorded for tests that no longer exist, never below the
median, so the pieces of a split are dealt out from the first run
(`fill_weights`). A new test in a new suite still gets the median.

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

Two more flakes surfaced on 2026-09-28. Both were one test writing
process-wide state that another test in the same process was reading, and
both are now closed at the writer:

* **Fixed.** `ANSIPrefixKnownWidthTests/fuzzMatchesExactWalk()`
  (`TUIkitCoreTests`) compares two width walks of each line. Beside it,
  `TerminalWidthTraitsProcessTests` moved the process-wide width traits from
  the main actor, so a skin-tone or ZWJ cluster was measured under one claim
  in one walk and another in the other. Deterministic with a probe: 10 of
  10 runs diverged with the real writers looping beside the fuzz, and none
  alone.
* **Fixed.** `BackdropMemoTests/thePageBehindASheetIsServed()` expects a frame
  served from the memo. `TerminalColorsProcessTests/generationTracksRealChanges()`
  is not main-actor isolated, and it moved `TerminalColors.generation`, which
  the render cache clears on, between two of that test's frames. With the
  writer between the frames it fails 10 of 10.

Every write that SwiftLint's `process_wide_write_in_tests` names now happens
only inside an exit test, through `ProcessWideState`, and the rule forbids the
raw writes; see CONTRIBUTING's Testing section. That is not every
process-wide write in the suite. The rule's comment lists the ones left in the
shared process and why each is safe today: main-actor state written and
restored in one synchronous stretch (the memo verifiers' switches,
`TerminalHost.startupIdentity`, `StackGuard.cachedExtent`),
`StorageDiagnostics.onFailure` swaps in the `.serialized` storage suite, and
the real signals `SignalManagerTests` sends. What the harness cannot fix stays
true: swift-testing runs suites concurrently inside one process, so
process-global state is shared, whether or not the suite is split across
processes. That includes `AppState.shared` (`DismissActionTests` requests an
exit through it), `LocalizationService.shared` (one test redirects its
persistence) and the process environment.

## Toolchains and platforms

The harness launches swift-testing the way `swift test` does, on each
toolchain, so a run here is the same program in the same environment. What
follows is transcribed from SwiftPM's own sources — `TestRunner.args(forTestAt:)`
in `SwiftTestCommand.swift`, `TestingSupport.constructTestEnvironment`,
`UserToolchain.deriveSwiftTestingPath`, `SwiftSDK.sdkPlatformPaths` and
`BuildParameters.binaryRelativePath` — at `release/6.2`, `release/6.3` and
`swift-6.4.0-RELEASE`.

**Which `swift`.** `$SWIFT` if set, else `swift` from `PATH`. CI's macOS lanes
export `SWIFT="xcrun --toolchain <bundle id> swift"` for a swift.org toolchain
and `SWIFT=swift` under Xcode; locally it is usually unset, which means
swiftly's default. The build, `--show-bin-path` and `-print-target-info` all go
through it, so the tests run on the toolchain that built them. (`xcrun
--toolchain` needs Xcode as the developer directory: under the Command Line
Tools it silently runs their own `swift`, 6.2.4 on this machine, whatever
toolchain it is given.)

**macOS** runs the toolchain's `swiftpm-testing-helper`
(`<usr>/libexec/swift/pm/`) with `--test-bundle-path <bin> <bin>`, and the
environment `constructTestEnvironment` builds. The testing library is in one of
three places, looked for in SwiftPM's order, and only the first found is used:

| toolchain | swift-testing | variables |
|---|---|---|
| Command Line Tools | `<toolchain>/Library/Developer/Frameworks/Testing.framework` | that directory on `DYLD_FRAMEWORK_PATH`; `<toolchain>/Library/Developer/usr/lib` on `DYLD_LIBRARY_PATH` (6.4 adds this; harmless where it does not exist) |
| swift.org (swiftly, CI's swift.org lanes) | `<usr>/lib/swift/macosx/testing` | that directory on `DYLD_LIBRARY_PATH` |
| Xcode | neither: it is in the macOS **platform** | — |

Then, for every toolchain, the macOS platform
(`xcrun --sdk macosx --show-sdk-platform-path`, or
`$SWIFTPM_PLATFORM_PATH_macosx`) when there is one:
`<platform>/Developer/Library/{Frameworks,PrivateFrameworks}` on
`DYLD_FRAMEWORK_PATH` and `<platform>/Developer/usr/lib` on
`DYLD_LIBRARY_PATH`. They are appended — after anything already set, and after
the toolchain's own — so a swift.org toolchain run with Xcode selected still
loads its own swift-testing, not Xcode's. Under the Command Line Tools there is
no platform and xcrun fails, so for swiftly's toolchains here the environment is
exactly what this harness always set, one `DYLD_LIBRARY_PATH`. Under Xcode 26.3
without the platform directories the helper cannot load the bundle at all
(`Library not loaded: @rpath/Testing.framework/Versions/A/Testing`); with them,
the processes report `Testing Library Version: 1501`, which is what `swift test`
reports under the same Xcode. Not mirrored: `NO_COLOR` (SwiftPM sets it when
its output is not a terminal; this suite does not read it),
`SWIFT_TESTING_XCTEST_INTEROP_MODE` (6.4 sets it only for tools version 6.4 or
later; this package is 6.2), and the coverage and sanitizer variables.

**Linux** has no helper. The test product is an executable, and SwiftPM runs it
directly — `<bin> <arguments…> --testing-library swift-testing`, the last flag
being what tells the product's entry point to run swift-testing rather than
XCTest — with the environment untouched. The harness does the same. This is
the one path that cannot be run on the machine this was written on; its
evidence is the SwiftPM source above and CI.

**One test binary or several.** SwiftPM's native build system makes one test
product for the package (`TUIkitPackageTests`). swift-build — the default from
6.4 (`swift build --help`: "default: swiftbuild"), so on CI's 6.4 and trunk
lanes — makes one per test TARGET: six here. On macOS each is
`<name>.xctest/Contents/MacOS/<name>`, as before; on Linux, native builds
produce `<name>.xctest` as an executable file and swift-build a
`<name>-test-runner` launcher beside `<name>.so` (CI's 6.4 build log links
`TUIkitViewTests-test-runner` and five siblings, and runs six test runs). The
harness lists every binary, maps each test ID to the binary that listed it
(each test target is its own module, so an ID in two binaries is refused), and
proves the partition over the union as before. A group whose tests span
several binaries becomes one invocation per binary, run **one after another in
that group's slot**, so there are still never more than `-j` processes at once;
each invocation's count is checked against the proof on its own.

**When something fails**, the lines that explain it go to the output, not only
to a file under `.build`: every failing process's issue blocks (the `recorded
an issue` line and its details; known issues are left out), or, for a process
that crashed or ran nothing, its last 40 lines and the signal that killed it.
`--full-failing-logs` adds the whole log, and on GitHub Actions
(`GITHUB_ACTIONS=true`) folds it into a collapsible group and makes each failed
test an `::error` annotation.

**Windows** is not supported and has never been run: there is no `flock`, the
binary discovery does not know `.exe`, and SwiftPM's Windows `PATH` additions
are not mirrored. CI's Windows lanes keep running `swift test`.

## Tests

```bash
python3 Tools/ParallelTest/test_parallel_test.py
```

68 tests covering the parts that can be tested without running the suite: ID
escaping and pattern anchoring, the partition proof rejecting a gap or an
overlap, bin packing, both weight paths, all eight shapes of the summary line
in both their singular and plural wordings, the malformed-xunit recovery, the
event-stream duration join, and the run lock making a second run wait. And,
for the toolchains: `$SWIFT` parsing; the macOS environment for each of the
three layouts in "Toolchains and platforms" (a mutation that lets the platform
come before a swift.org toolchain's own swift-testing, or puts two copies on the
path, fails them); test-binary discovery for native and swift-build output on
both platforms; the helper and direct command lines; the per-binary plan; a
slot running its invocations in turn while slots run at once; and the failure
excerpt on real Linux (CI) and macOS (probe) output.

Two of those are a negative control on the summary parser and are the reason
to run it after touching `SUMMARY_RE`: a log with no run summary in it — empty,
build-lock-starved, per-test lines only, or cut off mid-line — must keep
returning `None`. A parse there would cost the gate its only sight of trap 1,
which is worse than the misreporting the parser was widened to fix.
