# Contributing to TUIkit

TUIkit is a SwiftUI-like framework for building Terminal User Interfaces in pure Swift, with no ncurses or external C dependencies (the only C is the in-tree `stb_image` decoder, used as the image-decoding fallback where AppKit's `NSImage` is unavailable). It targets SwiftUI API parity wherever possible.

## Hard Requirements (non-negotiable)

| Requirement | Details |
|-------------|---------|
| **Swift 6.2** | `swift-tools-version: 6.2`. Language features up to 6.2 are fair game; nothing newer. |
| **Cross-platform** | Must build and run on macOS and Linux. WebAssembly builds and runs (see below); Windows is a work in progress. |
| **CI must pass** | All tests and linting must pass before merge. |

### What CI covers

Every lane runs `swift build`, `swift test`, and both smoke tests
(`Stress --selfcheck` everywhere; the PTY walk on macOS and Linux).

The three released Swift versions, 6.2, 6.3 and 6.4, are each covered on every
operating system, and trunk on macOS and Linux:

| Swift | macOS | Linux | Windows |
|-------|-------|-------|---------|
| 6.2 | Xcode 26 on `macos-15` | `swift:6.2-noble` | `swift:6.2-…` |
| 6.3 | Xcode 26 on `macos-26` | `swift:6.3-noble` | `swift:6.3-…` |
| 6.4 | swift.org 6.4 release on `macos-26` | `swift:6.4-noble` | `swift:6.4-…` |
| main | swift.org trunk snapshot | `nightly-main-noble` | — |

Released Swift comes from Xcode on macOS wherever a generally available runner
image carries the Xcode that ships it. For 6.4 none does yet — Xcode 27 is only
on GitHub's `xcode-27` image, which is still a preview — so the 6.4 lane takes
swift.org's release toolchain on `macos-26`. Trunk comes from swift.org too:
the newest snapshot of `main`, never a release branch's, and the lane checks
the snapshot it installed says so. Windows has no trunk lane because its trunk image is rebuilt too rarely to be
worth reporting as a nightly (on 2026-09-27 it was eleven weeks old).

Until 6.4.0 shipped (2026-09-14) its row was `release/6.4.x` snapshots and
nightlies, advisory; the release images replaced them, and they block. The
next release branch's nightlies take that place when it is cut.

WebAssembly is built by its own lane, on a pinned 6.3.3 container plus the
matching Swift SDK — pinned because a Swift SDK loads only under the toolchain
version it was built for, and still 6.3.3 because that is the only version the
port has been measured with (see [`Documentation/WebAssembly.md`](Documentation/WebAssembly.md)).

Linux additionally runs Swift 6.3 on arm64, and lint runs on Linux only — it
gates everything else, so a style slip fails in a minute rather than after
eighteen builds.

Nightly-toolchain lanes are **advisory** (`continue-on-error`): visible, but
unable to block a merge, because they break for reasons that have nothing to do
with this package. Everything on a released toolchain — including Windows —
blocks, with one exception: the macOS 27 lane.

macOS 27 runs on GitHub's `xcode-27` image (macOS 27.0 with Xcode 27, and so
Xcode's own Swift 6.4), which GitHub still labels a preview. Until that label
goes, the lane is advisory like a nightly; when it does, it becomes a required
lane alongside `macos-15` and `macos-26`. See the `TODO(macOS 27)` at the top
of the workflow.

#### The `CI` gate job

`CI` is a job that runs after everything else and fails if any non-advisory
lane did not succeed. **It is the only check that should be marked as a
required status check in the repository's branch-protection settings**
(Settings → Branches → branch protection rule for `main` → "Require status
checks to pass before merging"). A required check is one GitHub refuses to
merge a PR without.

Requiring it rather than the individual jobs matters for two reasons:

- Matrix job names change whenever the matrix changes, and branch protection
  matches checks *by name*. Requiring them directly means editing repository
  settings every time a Swift version is added.
- A **skipped** job reports as *success* to branch protection. If `macos` were
  required directly and it got skipped — because `lint` failed, say — the PR
  would look mergeable having built nothing. The gate treats `skipped` as a
  failure, so that cannot happen.

### WebAssembly

TUIkit builds for `wasm32-unknown-wasip1`, and the Example app runs in a browser
— `Tools/Web/build.sh` compiles it, `Tools/Web/serve.py` serves it. The CI lane
builds every module and the Example for wasm and is **binding**: what compiles
for WebAssembly today has to keep compiling.

Three things about the toolchain are worth knowing before you try it locally,
because each fails in a way that does not name its cause:

* **Xcode's compiler cannot do it.** It is built without the WebAssembly LLVM
  target and stops at `No available targets are compatible with triple
  wasm32-unknown-wasip1`. Use a swift.org toolchain (`swiftly install 6.3.3`).
* **6.3 is what it has been measured with.** swift.org's 6.2 asserted on
  `TupleView`'s pack conformance, exactly as it did for the Linux static SDK, so
  `TUIkitView` would not build. That conformance no longer asserts
  (`Tools/CompilerBugs/README.md`, section 3), but nobody has built for
  WebAssembly on 6.2 since.
* **`--static-swift-stdlib` is required**, and the SDK must be named by its
  bundle id rather than by the triple. Without the first, Foundation is missing
  from an SDK that contains it; without the second, SwiftPM may pick the
  embedded-Swift SDK that ships in the same bundle and has no standard library.

The port's shape — what needed a platform arm, what does not work in a browser,
and the two latent bugs it turned up in platform-independent code — is in
[`Documentation/WebAssembly.md`](Documentation/WebAssembly.md).

### Windows

Windows is **not supported yet** — the package does not build there in full.
The CI lane is a **ratchet**: every step says for itself whether it is allowed
to fail, so the job as a whole promises exactly *"everything that builds on
Windows today still builds"*. That set can only grow — when a step goes green,
delete its `continue-on-error` and it is binding from then on. When the console
layer lands, the last flag goes and nothing staged is left in the file.

The lane is therefore **required** on released toolchains. Observed state:

| Step | Status |
|---|---|
| `TUIkitCore`, `TUIkitStyling` | pass everywhere — **binding** |
| `TUIkitView` | passes on 6.3+; **fails on 6.2**, cause not yet diagnosed — binding except there |
| `TUIkitImage` | failed everywhere until 2026-08-07; green on all five lanes since, `continue-on-error` removed 2026-09-04 — **binding** |
| the four modules' own test targets | advisory, each with a 30-minute timeout |
| `TUIkit`, build-tests, test, smoke | fail until the console layer is ported |

Do not take the table on trust — it is a record of what CI did, and the whole
point of binding the lane is that it stays true. `TUIkitImage`'s failure went
unnoticed for as long as the lane was advisory, and this file previously claimed
it passed. It then stayed *advisory in this table* for a month after the flag came
off in CI, which is the same failure from the other end: the ratchet only reads
as a ratchet if the record moves with it.

That failure, for the record, was `ShapeSampling.swift` importing
`Glibc`-or-`Darwin` and then calling `cos`/`sin` unconditionally: on Windows
neither module exists, so there was no `cos` to call. `StackGuard.swift` has the
same two-armed ladder and builds fine, because every *use* there sits behind the
same conditions — which is the distinction to check when adding one.

The known blockers, in rough order of difficulty:

1. **stdin wake-up.** `StdinArrivalStream` uses
   `DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO,…)`.
   swift-corelibs-libdispatch's Windows backend explicitly refuses console
   handles (`FILE_TYPE_CHAR` → `WIN_PORT_ERROR()`), so the whole mechanism has
   to be rebuilt around a thread blocking on `ReadConsoleInput`.
2. **Resize notification.** Windows has neither `SIGWINCH` nor a
   `TIOCGWINSZ` equivalent. Size changes arrive as `WINDOW_BUFFER_SIZE_EVENT`
   records from `ReadConsoleInput`, which is the same call as (1) — so they
   want designing together. Do not plan around the in-band resize escape
   (`CSI ? 2048 h`); it is an unassigned backlog item on Windows Terminal.
3. **Raw mode and VT output.** `GetConsoleMode`/`SetConsoleMode` replace
   `termios`, and VT output must be opted into with
   `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN`.
   `GetConsoleScreenBufferInfo` replaces `ioctl(TIOCGWINSZ)`.
4. **The PTY smoke harness.** Everything in `Tools/Smoke/` — `tui_walk.py`,
   `tui_screens.py`, `raw_probe.py`, `persistence_probe.py`,
   `faded_palette_sweep.py` — uses `pty`/`termios`, so it is POSIX-only; a
   Windows equivalent needs ConPTY. (`faded_palette_sweep.py` runs at `full`
   depth only, and is 7 min 15 s of the 11 min 23 s that costs; §68 of
   `Documentation/Opacity as composition.md` explains what it catches that a
   walk cannot.)
   `Tools/Smoke/ci-pty-smoke.sh` is skipped on the Windows lanes for this
   reason, and they run `Stress --selfcheck` alone.

Two things that are *not* blockers, despite looking like them: `@AppStorage`
already falls back to JSON-file storage off Apple platforms, so the open
Windows `UserDefaults` bug does not affect it; and SwiftLint gained Windows
support in 0.64.0.

## Build, Test & Lint

```bash
# Build
swift build

# Build with Xcode's own toolchain too, if `swift` on your PATH is a swift.org
# one (swiftly puts itself first, and DEVELOPER_DIR does not change that). The
# two differ by more than version: Apple's SDKs build the standard library from
# its PUBLIC interface, so an `@_spi` import of `Swift` sees nothing there, and
# the macOS CI lanes use Xcode's. A separate scratch path keeps the two builds
# from invalidating each other.
xcrun --toolchain XcodeDefault swift build --build-tests --scratch-path .build/xcode

# Run all tests (7,591 tests in 1,082 suites, Swift Testing framework)
swift test

# The same tests, in 12 processes instead of 1: 54.1s -> 14.0s (see below)
Tools/ParallelTest/parallel_test.py --calibrate   # once, ~95s
Tools/ParallelTest/parallel_test.py -j 12

# Run a single test suite. NOTE: --filter matches the Swift TYPE name, not the
# @Suite display string — `--filter AlertDismissalTests`, not "Alert dismissal".
swift test --filter <TestSuiteName>

# Lint (must report zero violations)
swiftlint

# Format (configured but not enforced in CI)
swift-format format -i -r Sources Tests

# Build the documentation (one archive covering every module)
Tools/BuildDocs/build-docs.sh            # add --analyze for every diagnostic
```

> Use the script, not `swift package generate-documentation --target TUIkit`.
> The latter documents only what the umbrella module itself declares, which
> silently omits `View`, `Color`, `Binding` and everything else the sibling
> modules define — see [`Tools/BuildDocs/README.md`](Tools/BuildDocs/README.md).

## Running the suite in parallel

`swift test` runs the suite in one process. 81% of the tests are in
`@MainActor` suites, so they queue on that one actor: 77% of the CPU in the
late part of a run is `syscall_thread_switch` and friends — threads taking
turns, not working. `Tools/ParallelTest/parallel_test.py` splits the suite
across processes, each with its own main actor. Re-measured here (12 logical
cores / 16 GiB) after the test splits in `a7bdea3f` and `638dd69f`, as the
suite time each command reports for itself:

| command | median suite wall | reps | sd | speedup |
|---|---:|---:|---:|---:|
| `swift test` | 54.10 s | 4 | 2.50 | 1.00x |
| `Tools/ParallelTest/parallel_test.py -j 6` | 20.73 s | 6 | 0.74 | 2.61x |
| `Tools/ParallelTest/parallel_test.py -j 8` | 17.32 s | 4 | 0.55 | 3.12x |
| `Tools/ParallelTest/parallel_test.py -j 12` | **13.96 s** | 10 | 0.59 | **3.88x** |

That is −40.1 s a run at `-j 12`, or ~6.7 hours across a 600-run landing batch.
Three paired reps with the arm order randomised agreed on all three arms:
`-j 6` − `-j 12` = +6.64 s, `-j 8` − `-j 12` = +3.47 s, `swift test` − `-j 12`
= +40.14 s, each with the same sign in every rep. The ±2.4 s band this repo
quotes for wall-clock noise is a SINGLE-PROCESS figure — the harness arms
repeat far more tightly, which is what makes the 3.5 s between `-j 8` and
`-j 12` readable at all.

**The curve has not flattened at 12.** The harness prints the floor as part of
its plan — today `popUpReachesItsLastRowAtItsLongest(count:)`, 3.85 s alone, so
`-j` beyond 28 cannot help — but `-j 12` is nowhere near it: the run reaches
10.2x cores on a 12-core machine, so what binds is the machine, not the slowest
test. More cores would keep paying until about 28.

Add ~1.5 s of enumeration, planning and reconciliation for the wall you
actually wait for, plus the incremental build — 0.1–0.8 s if the last thing you
ran was another harness run, but **6.5–7.2 s on the first `swift build
--build-tests` after a `swift test`** (5 of 5 observed; two consecutive builds
with nothing between them cost 0.3 s). A repeat `-j 12` run therefore lands
around 16.3 s of wall, against ~62 s for `swift test`.

Memory at `-j 12` on 16 GiB: the twelve test processes peaked at 2,576 MiB of
combined RSS, the largest single one 265 MiB. `swift test` peaks lower in total
(1,177 MiB) but far higher in one process (1,031 MiB). No arm touched swap —
`vm.swapusage` read `total = 0.00M` before, during and after every run, the
compressor never moved, and there were no swapins or swapouts. `-j 12` is
comfortable here; the ceiling is cores, not RAM.

**CI does not use it, and neither does the merge gate** — those run `swift
test` in one process, exactly as above, and that is unchanged. The harness is
for anyone running the suite repeatedly. It runs every test, and fails loudly
unless the union of test IDs returned by its processes matches the enumerated
suite exactly, so a process that quietly ran nothing cannot be mistaken for a
pass. That identity check held in all 25 full-suite runs behind this section:
7,591 tests, 1,082 suites, 21 known issues, nothing missing, extra or
duplicated. Two of the 25 did print a reconciliation problem, but it was a gap
in how the harness parsed a summary line — since closed, and recorded in its
README — and not a test that failed to run.

Because the tests are spread differently, anything depending on the
interleaving one process happens to give it can behave differently — that is a
property of the test. [`Tools/ParallelTest/README.md`](Tools/ParallelTest/README.md)
records the tests known to do that today, the flakes seen while measuring, and
why weights are measured serially rather than taken from the timings
swift-testing reports.

## Pull Request Requirements

1. Branch from `main`
2. Fill in the PR template completely
3. The `CI` gate check must be green — it covers macOS, Linux and, on
   released toolchains, Windows; only the nightly-toolchain lanes and the
   macOS 27 lane (a preview image) are advisory (see "What CI covers" above)
4. No new SwiftLint warnings
5. Follow the architecture and API rules below

## Architecture

### SwiftUI API Parity

Public APIs **must** match SwiftUI signatures exactly unless terminal constraints require deviation (document why in comments).

| Aspect | Requirement |
|--------|-------------|
| Parameter names | Exact (`isPresented`, not `isVisible`) |
| Parameter order | Exact (title, binding, actions, message) |
| Parameter types | Match closely (ViewBuilder closures, not pre-built values) |
| Trailing closures | `@ViewBuilder () -> T`, not `String` |

**Before implementing any SwiftUI-equivalent API:** Look up the exact SwiftUI signature first.

### View Architecture

- Every **public** control must be a `View` with a real `body: some View`
- The `body` must return actual Views (not `Never`, not `fatalError()`)
- `Renderable` is only for leaf nodes (`Text`, `Spacer`, `Divider`), private `_*Core` views, layout primitives, and modifier infrastructure — never public controls
- All modifiers must propagate through the entire View hierarchy
- Environment values must flow down automatically

### General Principles

- No singletons
- Built-in views draw with the palette's roles, never a literal colour, unless
  the colour is content (an image, a swatch, a user's gradient). SwiftLint's
  `framework_colour_literal` rule flags a new literal in `Sources/TUIkit` and
  `Sources/TUIkitView`; see "What built-in controls draw with" in the Theming
  Guide article
- Search the codebase for similar patterns before implementing anything new
- Consolidate and reuse before adding new functions or types

## Code Style

- Line length: 160 characters (warning), 200 (error)
- 4-space indentation
- Trailing commas in multi-line collections
- See `.swiftlint.yml` and `.swift-format` for full configuration

## Testing

- Uses Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- Tests run in parallel; the few that mutate global state are serialised
- **A test that asserts the framework's own UI words** — "No items", "dismiss",
  "Done" — depends on the language `LocalizationService.shared` picked from
  `LANGUAGE` / `LC_ALL` / `LC_MESSAGES` / `LANG`. Declare that on the suite with
  `.rendersEnglishUI` (see `Tests/TUIkitTests/TestHelpers/RendersEnglishUI.swift`),
  which pins English for the process before the suite runs. Without it the suite
  passes for you and fails for anyone whose POSIX locale is not English. Do not
  set a locale variable from inside a test: `LocalizationService.shared` is a
  lazy global whose first touch reads the live process environment, so a
  process-wide `setenv` latches that language for every test that follows.
- **Numbers** in rendered chrome are grouped by `\.locale`, which is republished
  from the app language every frame. A test asserting "4,994" pins
  `environment.locale` explicitly rather than relying on the default.
- Test files mirror source structure in `Tests/TUIkitTests/`
- Each library module also has its own test target (`TUIkitCoreTests`,
  `TUIkitStylingTests`, `TUIkitViewTests`, `TUIkitImageTests`) that links **only
  that module**, so a module test cannot reach across a layer boundary. Put a
  test in the module target it belongs to; `Tests/TUIkitTests` is for
  integration tests and everything in the umbrella module.
  `Tools/validate-test-boundaries.sh` checks this and runs in CI.
- `Tests/ExampleTests` holds tests of the Example app's own views
  (`@testable import Example`), for when a test must drive what the app
  ships rather than a copy of its shape: a copy goes on passing after the
  app's view is changed back.
- To run the whole suite faster while developing, see "Running the suite in
  parallel" above. CI and the merge gate still run plain `swift test`.

## The `project-template/` directory

`project-template/` is a starter kit for spinning up a new app built on
TUIkit (a `tuikit` scaffold plus an `install.sh` and its own README). It
is intentionally kept **inline in this repository** rather than split into
a separate repo: it's small, low-churn, and easiest to keep in step with
the library when it lives alongside it. It is excluded from source
archives / GitHub release tarballs via `export-ignore` in `.gitattributes`,
so it adds no weight for SwiftPM consumers. If it ever grows enough to
warrant independent versioning, revisit moving it out.

## Detailed Architecture Rules

For comprehensive architecture documentation including the `_*Core` pattern, focus system, state management, and interactive view rules, see [`.claude/CLAUDE.md`](.claude/CLAUDE.md).
