# Picking up where this leaves off

A handoff document for whoever — human or AI — works on TUIkit
next. Covers the current state of the codebase, the tooling
configured during this session, the open work and the context
for each piece, the architectural patterns worth knowing, and
the integration gaps that hide bugs between layers.

## The state of the codebase

**Tests:** 1560 tests across 210 suites pass on Linux Swift
6.3.2. The full suite runs in ~8 seconds.

**Build:** Clean on Linux. macOS build is presumed clean — the
last commit message says so and nothing in the recent changes
should affect platform compatibility, but the user has been
running the example app on macOS and the integration bugs that
came up are documented in `Documentation/`.

**The example app under `Sources/TUIkitExample/`** is the
primary smoke test surface. Test coverage of integration paths
is decent now (see `Tests/TUIkitTests/RenderLoopRegionMergeTests.swift`
for the gold-standard pattern) but the user-driven discovery
loop still surfaces gaps. Expect "I clicked this and nothing
happened" reports from time to time even with green tests.

## Tooling configured

### Swift toolchain on the build host

A Linux-side toolchain is configured at:

    /sessions/upbeat-trusting-ptolemy/.local/share/swiftly/bin/

This is a swiftly-managed install. The active toolchain is
Swift 6.3.2. The `swift` binary at that path is a symlink to
`swiftly` which routes to the version configured for the
project. Two toolchains are installed (6.0.3 and 6.3.2); 6.3.2
is the one tests are run against.

The user's stated target is Swift 6.2 — 6.3.2 is a superset
and works correctly for the project. CI presumably uses 6.2.

### jemalloc (for `ordo-one/benchmark`)

package-benchmark depends on a jemalloc system library. The
sandbox doesn't have `sudo`, so jemalloc was extracted from the
Ubuntu `libjemalloc-dev` `.deb` into a user-space directory:

    /sessions/upbeat-trusting-ptolemy/extra-libs/jemalloc/

A pkg-config file at `lib/pkgconfig/jemalloc.pc` makes it
discoverable. Builds need:

    export JEMALLOC_PREFIX=/sessions/upbeat-trusting-ptolemy/extra-libs/jemalloc
    export PKG_CONFIG_PATH=${JEMALLOC_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH

…and benchmarks need the runtime library:

    export LD_LIBRARY_PATH=${JEMALLOC_PREFIX}/lib/aarch64-linux-gnu

### Linker

Default `ld.gold` runs out of file descriptors on this
sandbox even at `ulimit -n 65535`. Use `lld` instead via
`-Xswiftc -use-ld=lld`. Combined incantation:

    ulimit -n 65535
    swift build --build-path .build-linux -Xswiftc -use-ld=lld
    swift test  --build-path .build-linux -Xswiftc -use-ld=lld

`.build-linux/` is the conventional path used in this session
(separate from `.build/` so macOS and Linux artefacts don't
collide).

### Benchmarks

`swift package benchmark` works after the above environment
variables are set. The full suite runs ~20 benchmarks under
`Benchmarks/TUIkitBenchmarks/` — see `Documentation/`-ish
context in commit `9bdf2580` and the related commits for
why view-using benchmarks are skipped pending #31.

For a quick run:

    export TUIKIT_BENCH_MAX_DURATION_MS=200
    swift package --scratch-path .build-linux benchmark --filter '<pattern>'

To attempt the view benchmarks (they will SIGTRAP — see
`Documentation/Actor isolation and the input-reader loop.md`):

    export TUIKIT_BENCH_RUN_VIEW=1
    swift package --scratch-path .build-linux benchmark --filter 'render/'

### MCP / Cowork sandbox specifics

Bash calls cap at 45 seconds; the harness kills child processes
when the bash invocation returns (`bwrap --die-with-parent`).
Long-running benchmarks need to fit inside that window — use
the `TUIKIT_BENCH_MAX_DURATION_MS` env var to shrink each
benchmark from the default 1 s. Backgrounding with `nohup &`
doesn't survive the bash exit. Pre-build aggressively in
separate `swift build` calls before running anything time-
sensitive.

`bash` calls share a single session named after the user, so
parallel invocations error with "process already running" —
serialise everything.

## Documentation/ trail

These were written deliberately during the session as design-
discussion artefacts. Read them before changing the related
subsystem:

- **`Layout constraint system.md`** — pre-existing. Plans the
  width / height constraint system. Not implemented yet.
- **`Emoji rendering bugs in macOS Sequoia's Terminal.app.md`**
  — pre-existing. Documents the cursor-advance quirks around
  emoji that TUIkit works around. Read before touching any
  code that thinks about character widths.
- **`Actor isolation and the input-reader loop.md`** —
  written this session. Catalogues the actor-model options
  (option-3 hybrid is the recommended destination for #31)
  and the DispatchSource + AsyncStream shape for the input
  reader. The actor refactor is deferred; the input-reader
  shape was partially adopted (commits `1bfe0cc3` and
  `e427f820`) — `await stdinArrival.waitForArrival(timeoutNanoseconds:)`
  replaces the bare `Task.sleep`.
- **`Composing List and Table on ScrollView.md`** — written
  this session. Records the four architectural mismatches
  blocking full composition (lazy-rendering invariant, focus-
  registration interaction, focusID-carrying for snap-to-
  focused, container chrome relocation) and what was *done*
  instead (deduplicating shared arithmetic into the
  `ScrollableOffsetState` protocol — commit `22b3982c`).

## Open work

### #31 — TUIkit core flow on a dedicated global actor

The only currently-open task. Fully documented in
`Documentation/Actor isolation and the input-reader loop.md`.
The short version:

- TUIkit's `View` API and render pipeline are `@MainActor`-
  isolated.
- package-benchmark blocks the main thread on a
  `DispatchSemaphore` while async benchmark closures run,
  which deadlocks any closure that hops to MainActor.
- Hence the view benchmarks are skipped (env-gated by
  `TUIKIT_BENCH_RUN_VIEW`).
- Hence — separately — a hybrid actor refactor (View construction
  nonisolated, render pipeline on `@TUIkitActor`, action
  callbacks stay `@MainActor`) is the recommended destination,
  but only when something concrete demands it. Possible
  triggers: benchmark coverage of view rendering becomes the
  bottleneck for a real perf investigation; embedding TUIkit
  inside another app's main thread becomes a real use case;
  some unforeseen third pain point.

Don't do #31 speculatively. It's days of careful refactoring
with API churn for users.

## Architectural patterns worth knowing

### The `_*Core` rendering pattern

Every public interactive view follows the same shape:

```swift
public struct Button: View {
    public var body: some View {
        _ButtonCore(label: label, action: action, ...)
    }
}

private struct _ButtonCore: View, Renderable {
    var body: Never { fatalError("_ButtonCore renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer { ... }
}
```

The public type has a real `body: some View`. The private
`_*Core` does the actual rendering and conforms to
`Renderable`. Modifiers propagate through the public layer
normally; the procedural ANSI assembly lives in the core.

The CLAUDE.md (`.claude/CLAUDE.md`) covers this in detail
under "View Architecture (non-negotiable)". Read it before
adding any new control — `Box.swift` is the reference
implementation for the pure-composition variant.

### `StateIndex` enums

Every `_*Core` that uses `StateStorage` declares its property
indices as named constants in a file-private enum, lifted
outside the generic struct (Swift doesn't allow static stored
properties in generic types):

```swift
private enum ButtonStateIndex {
    static let focusID = 0
    static let isHovered = 1
}

private struct _ButtonCore<...>: View, Renderable {
    private typealias StateIndex = ButtonStateIndex
    ...
}
```

This makes `StateStorage.StateKey(... propertyIndex:
StateIndex.isHovered)` readable and prevents the bare-integer
collision class that bit us in `SecureField` (commit
`fa16af1a`).

### The hover state machine

Hover state for a focusable control is stored in a
`StateBox<Bool>` (or `StateBox<Int>` for per-item-row controls
like `RadioButton`). The mouse handler's `.entered` /
`.exited` cases flip it. The render reads it and adjusts the
visual. Disabled and (usually) focused states clamp it to
false so the hover affordance doesn't compete with stronger
visual signals.

Canonical template: `Button.swift`. Per-item-row variant:
`RadioButton.swift`. Status-bar variant (uses
`StatusBarState.hoveredItemID`): `StatusBar.swift`.

Tests need a `FocusSentinel` helper (see
`Tests/TUIkitTests/ButtonTests.swift`) to claim the auto-
focused slot so the button under test stays unfocused — without
it, hover is suppressed and the test fails for the wrong reason.

### `ScrollableOffsetState` protocol

`Sources/TUIkit/Focus/ScrollableOffsetState.swift` (added in
commit `22b3982c`) shares scroll-position arithmetic between
`ScrollViewHandler` and `ItemListHandler`. Both conform with
different `extent` (lines vs. rows); the protocol extension
provides `maxOffset`, `hasContentAbove`, `hasContentBelow`,
`rowsAbove`, `rowsBelow`, `visibleRange`, `scroll(by:)`,
`clampScrollOffset()`, `handleWheelEvent(_:linesPerTick:)`.

If you find yourself reaching for scroll-offset arithmetic in
a third place, conform that type to the protocol rather than
copying.

### The build-buffer / write-buffer split for non-content render paths

The status bar (`buildStatusBarBuffer` /
`writeStatusBarBuffer`) and app header (`buildAppHeaderBuffer`
/ `writeAppHeaderBuffer`) in `RenderLoop.swift` each split
into two phases:

1. Build the `FrameBuffer` (which carries hit-test regions).
2. Caller intercepts the regions and merges them into the
   dispatcher's set with the right coordinate shift.
3. Write the buffer to the terminal.

The split exists because before commits `e5382a77` and
`714d3577`, the build-and-write was a single method that
silently dropped the buffer (and its `hitTestRegions`) on the
way out, leaving the status bar's and app header's mouse
handlers registered but unreachable. The two-phase split is
the *correct* shape — preserve it. Any *other* render path
that builds a buffer separately from the main content render
needs the same split.

The coordinate shifts are documented in
`RenderLoop.renderFrame`:

- Content regions: already in content-area coordinates, no
  shift.
- App-header regions: shifted by `-appHeader.height` (events
  arrive with negative y for header rows because the App input
  loop subtracts the header height).
- Status-bar regions: shifted by `+contentHeight` (status bar
  sits below the content area, events arrive with y ≥
  contentHeight).

### `synthesizeKeyEvent` — full-chain key dispatch

Added in commit `e99c2da5`. `TUIContext.synthesizeKeyEvent`
holds a `@MainActor (KeyEvent) -> Void` closure that
`AppRunner.run()` wires to `inputHandler.handle`. The closure
runs the event through all five layers of `InputHandler`:
text-input override, status-bar items, view handlers, focus
system, default quit / theme / appearance bindings.

Status-bar items that have only a `triggerKey` (e.g. "Back",
"Quit", "Show") call this closure on click to synthesise their
key — which routes through whichever layer would have handled
a physical keypress, including Layer 4 quit which only
`AppRunner` has the closure for.

If any other view ever needs "click this triggers a key
dispatch", read `synthesizeKeyEvent` from the environment
and call it. Don't reach for `KeyEventDispatcher.dispatch`
directly — that only hits Layer 2.

## Integration gaps and how the tests should catch them

The bug class that broke status-bar clickability for *months*
in this codebase is:

> A buffer carries hit-test regions at render time. The
> regions are never merged into the dispatcher's region set.
> Every unit test on either side passes; the integration
> point between them silently fails.

The unit tests in isolation:
- `StatusBar.applyHitTestRegions` correctly emits regions.
- `MouseEventDispatcher.dispatch` correctly routes events
  to registered handlers.

But the buffer those regions live in never reached `setRegions`,
so the dispatcher's region table was missing them. End-to-end
tests are the only way to catch this class of bug.

**The pattern to write:** see
`Tests/TUIkitTests/RenderLoopRegionMergeTests.swift`. The
`mergedRegionsRouteClicksToRightHandler` test builds three
buffers (content + app header + status bar) with handlers,
replicates `RenderLoop.renderFrame`'s merge with the same
coordinate shifts, dispatches synthetic mouse events at each
region's content-area coordinates, and asserts the right
handler fired.

Any new render path that produces a separate buffer (overlays,
modals, future windowed-content variants) needs a similar test
with the same shape.

## Recent commits worth knowing about

By topic, with brief context:

- **`9bdf2580`** — adopted `ordo-one/benchmark`. View
  benchmarks skip by default; image benchmarks run.
- **`d0d50a1d`** — documented that view benchmarks SIGTRAP
  under package-benchmark's main-thread-blocking model.
  Pointer for the #31 design.
- **`04ac8eba`** — fixed three pre-existing failing tests
  (two Button hover, one List ForEach). The List one
  surfaced a real `ForEach.extractListRows` bug.
- **`1bfe0cc3`** + **`e427f820`** — input-reader loop fixed.
  Bare `Task.sleep` replaced with a race against a
  `DispatchSource` on STDIN_FILENO. Source targeted at
  `.main` so the event handler runs on the main thread
  (which is where MainActor's executor pumps), avoiding the
  cross-thread continuation hop.
- **`22b3982c`** — `ScrollableOffsetState` protocol
  extracted. 65 lines of duplicated scroll-offset arithmetic
  collapsed into one place.
- **`74bedf4c`** — documented why the full
  List-on-ScrollView composition is deferred.
- **`fa16af1a`** + **`fefa6b6c`** — hover wired into
  SecureField, RadioButton, and Picker popup.
- **`e5382a77`** — status-bar item *click* path fixed
  (regions were being silently dropped). 12+ commit
  message worth of context, read it before touching the
  status bar.
- **`714d3577`** — same class of bug in the app-header path.
- **`2b6ca9e8`** — integration tests for the region-merge
  contract.
- **`e99c2da5`** — system status-bar items (Back / Quit /
  Show / Select) made clickable. `synthesizeKeyEvent`
  added.

## Conventions and policies

### `CLAUDE.md` at `.claude/CLAUDE.md`

The user's policy file. Non-negotiable rules — Swift 6.2
target, cross-platform (macOS + Linux), no singletons,
SwiftUI API parity, the `_*Core` view-architecture rule, the
focus-registration rules, the StateIndex constants rule, the
file-organisation rule (~500 line cap). Read this before any
substantial change. If a rule is binding you up,
ask — don't ignore.

### Ask before you assume

The user prefers being asked when a decision has significant
ramifications. Cosmetic / mechanical changes can proceed. Big
refactors, API changes, anything where you'd be uncertain
about the right answer — ask first. The `AskUserQuestion`
mechanism is available.

### Don't merge PRs autonomously

The user has the merge button. Create PRs, mark them ready,
stop.

### Commit messages

The commits in this session are verbose by design. The user
will read them when investigating a bug six months from now.
Aim for: what was broken, why it was broken (root-cause
diagnosis, not just symptoms), how it's now fixed, what tests
cover the fix. The `e5382a77`, `e99c2da5`, and `04ac8eba`
commits are good templates.

## Things to be aware of even if not urgent

### The benchmark suite is partial until #31

Image benchmarks work and produce real numbers. View
benchmarks (Layout, Render, ListTable, ScrollView) are
skipped because of the package-benchmark / MainActor
deadlock. The user-visible benchmark gap is that the
List/Table refactor regression-watch that motivated #26
isn't actually available — the 1900-row List benchmark
exists, it just doesn't run. If you tackle #29's full
composition (still deferred per the design doc), you'd want
the bench coverage first, which means #31 first.

### The end-to-end test surface is shallow

`RenderLoopRegionMergeTests.swift` is the only file that
exercises the full render → setRegions → dispatch path.
Anything else relies on unit tests at each layer. The
StatusBar / AppHeader bugs lived for months specifically
because of this gap. Likely candidates for similar gaps:
overlays (Picker popup), modals, anything involving
multi-buffer composition. Adding integration tests for
those paths would be a low-risk, high-value investment.

### macOS-only features

A few code paths assume `Darwin` is available (terminal
control, signal handling on macOS-specific signals,
`tcsetattr` flag types via the `TermFlag` typealias). Linux
parity is enforced by `#if canImport(Glibc) || canImport(Musl)`
guards. Watch for those guards if you add new platform-touching
code; the project tries to keep parity.

### The `nonisolated` audit on Focusables

`Focusable` is `nonisolated` (not `@MainActor`). That's why
`ItemListHandler`, `TextFieldHandler`, `RadioButtonGroupHandler`,
etc. can be class-typed without isolation crossings. Don't
make handlers `@MainActor` even when it seems convenient —
it propagates everywhere and breaks the existing
non-isolated chain.

## What you don't have to do

- **The actor refactor (#31)** — deferred. Wait for a real
  driver.
- **List/Table composition on ScrollView** — partially done
  via deduplication (`22b3982c`), the rest deferred. Wait
  for behaviour drift or a windowed-content use case.
- **Per-row hover for List/Table/Menu** — deferred for the
  same reason; per-row hit-test regions are a meaningful
  unwind that pairs naturally with the composition refactor.

These are all explicitly documented as "don't do
speculatively". Pursue them when you have a concrete reason.

## What to do next (suggestion, not prescription)

If the user hands you the next session and says "continue":

1. Ask what's bothering them most. The user-driven bug reports
   in the last hour of this session (status-bar items not
   responding, hover lost after click) surfaced architectural
   gaps the test suite didn't catch. Listening for the next
   such report is more valuable than picking up a backlog
   item.
2. If they want backlog work, the recommended order is:
   add end-to-end integration test coverage for the
   remaining render paths (overlays, modals) — the same
   pattern as `RenderLoopRegionMergeTests.swift`.
3. If they want a small win, look at the per-row hover for
   List/Table/Menu — the structural work is small and the
   UX win is concrete. The Picker popup case
   (`fefa6b6c`) is a good shape to follow.
4. Don't pick up #31 until something specifically needs it.

Good luck.
