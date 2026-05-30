# Benchmark coverage and deferred MainActor benchmarks

This document records the current state of the benchmark
suite, what is measured now, and the detailed list of
benchmarks that are **blocked** until the package-benchmark /
`@MainActor` deadlock has a workaround. Read it alongside
`Actor isolation and the input-reader loop.md` (the actor
refactor, #31, is the eventual unblock).

## Why some benchmarks are blocked

package-benchmark (`ordo-one/benchmark`) runs each benchmark
closure from a worker while **blocking the main thread** on a
`DispatchSemaphore`. Any benchmark body that hops to
`@MainActor` (directly, or by touching a `@MainActor`-isolated
type) queues work behind the blocked main thread; the runtime
detects the stall and traps with SIGTRAP.

TUIkit's `View` API, the render pipeline (`ViewRenderer`,
`Renderable.renderToBuffer`, `FrameDiffWriter`), layout
(`Layoutable.sizeThatFits`), modifier application, and the
focus/state services reached through rendering are all
`@MainActor`-isolated. So anything that renders a view, or
measures layout, or applies a modifier, cannot be benchmarked
under the current harness.

The escape hatch in code is `skipViewBenchmarks` /
`viewBenchmarkConfiguration()` in `Benchmarks/TUIkitBenchmarks/
Benchmarks.swift`: view-using suites stamp `skip:` true unless
`TUIKIT_BENCH_RUN_VIEW=1`. With that env var set they *attempt*
to run and SIGTRAP — useful only as a smoke test once a
workaround lands.

## What runs today (off the main actor)

These suites are pure, `nonisolated`, value-type computation
and run unconditionally under the default configuration:

- `image/*` — `ASCIIConverter` pipeline (style, colour mode,
  dithering). Pre-existing.
- `text/*` — `Character.terminalWidth`, `String.strippedLength`,
  `ansiAwarePrefix`/`ansiAwareSuffix`, `padToVisibleWidth`, and
  the Terminal.app cursor-advance workarounds. The hottest
  per-character path.
- `input/*` — `KeyEvent.parse`, `MouseEvent.parseSGR` /
  `parseLegacy`.
- `color/*` — `Color.downsampledToPalette256` /
  `downsampledToANSI16`, `lighter`/`darker`/`opacity`/`lerp`.
- `buffer/*` — `FrameBuffer` construction, stacking,
  compositing, clamping.
- `scroll-math/*` — `ScrollableOffsetState` arithmetic via
  `ScrollViewHandler`.
- `identity/*` — `ViewIdentity` path construction and ancestry.

## Deferred — benchmarks to add once the deadlock is worked around

Grouped by subsystem. Each entry names the type/method, why it
matters, and a realistic input size. The existing skipped
suites (`LayoutBenchmarks`, `RenderBenchmarks`,
`ListTableBenchmarks`, `ScrollViewBenchmarks`) already cover
some of this and simply need to *run*; the rest are new.

### 1. View render pipeline (highest value)

The end-to-end "render a view tree to a `FrameBuffer`" path is
the headline number for the whole library and is entirely
unmeasured at the integration level today.

- `ViewRenderer` full-tree render — render a representative
  page (the example app's mixed-form page is a good fixture) at
  a fixed terminal size. Input: ~80×40 viewport, 20–50 nodes.
- `Renderable.renderToBuffer` per-control — `Text`, `Button`,
  `Toggle`, `Slider`, `Stepper`, `TextField`, `Picker` in
  isolation. (The `render/*` suite already drafts these.)
- Re-render / diff cost — render the same tree twice and
  measure the second pass (exercises `RenderCache`).
- `FrameDiffWriter.computeChangedRows(newLines:previousLines:)`
  — pure line-array diff, but lives in a `@MainActor` class.
  Either run it once the deadlock is fixed, or extract it to a
  `nonisolated` free function and benchmark it now (see
  "Extraction candidates").

### 2. Layout

- `Layoutable.sizeThatFits(proposal:context:)` for the stacks
  (`VStack`/`HStack`/`ZStack`), `Spacer`, `LazyVStack`/
  `LazyHStack`, and `FrameModifier`. The `layout/*` suite
  already drafts VStack/HStack/LazyVStack/modifier-chain cases.
- Two-pass layout convergence — a deep nested stack tree
  (e.g. `VStack(HStack(Text×3))×50`) to catch quadratic blowups.
- `NavigationSplitView` column distribution.

### 3. List / Table (the regression-watch that motivated #26)

- `list/1900 rows, single-select (emoji-list-sized)` — the
  flagship regression guard. Exercises lazy windowing
  (`_ListCore` renders only `visibleRange`). Currently drafted
  in `ListTableBenchmarks` but skipped.
- `table/200 rows × 3 columns` — column layout + per-row render.
- Mid-scroll render (offset into a long list) vs top-of-list,
  to confirm lazy rendering keeps per-frame cost flat.

### 4. Modifiers

- `ViewModifier.modify(buffer:context:)` for the common
  modifiers: `PaddingModifier`, `BorderModifier`,
  `BackgroundModifier`, `FrameModifier`, `OverlayModifier`.
- A realistic modifier chain (4–6 modifiers) vs bare content,
  to measure per-modifier overhead.

### 5. ANSI emission (also blocked by access level, not just isolation)

- `ANSIRenderer.render(_:with:)`, `foregroundCodes`/
  `backgroundCodes`, `applyPersistentBackground`. NOTE: this
  type is **internal**, so even once the isolation issue is
  resolved it isn't reachable from the benchmark target (an
  external consumer) without either making it `public` or using
  `@testable import` in the benchmark target. Decide which when
  picking this up — see the pinned question for Wade.

### 6. Status bar / app header / overlays

- `RenderLoop` status-bar and app-header buffer build paths
  (`buildStatusBarBuffer` / `buildAppHeaderBuffer`) — per-frame
  chrome, currently `@MainActor` inside `RenderLoop`.
- Overlay/modal compositing through the full render path
  (Picker popup, Alert, Dialog).

## Extraction candidates (could be benchmarked *now* if refactored)

Some hot logic is pure but currently trapped inside a
`@MainActor` type. Extracting the pure core to a `nonisolated`
free function (or static method on a non-isolated type) would
let it be benchmarked immediately *and* unit-tested more
easily:

- `FrameDiffWriter.computeChangedRows(newLines:previousLines:)`
  — already a pure static method; just enclosed in a
  `@MainActor` class.
- `TextFieldContentRenderer` cursor-state / content-building
  helpers — pure given their inputs.

These are noted as refactor opportunities; doing them is a
judgement call (don't fragment a cohesive type just to satisfy
the benchmark harness). Flagged for the broad-review pass.

## Pointer

When the actor refactor (#31, hybrid option 3) lands — render
pipeline on `@TUIkitActor`, view construction `nonisolated` —
the `skipViewBenchmarks` gate can be removed and the four
existing skipped suites enabled, then the new entries above
added. Until then, this list is the backlog.
