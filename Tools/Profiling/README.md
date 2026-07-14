# Profiling TUIkit

Tooling for CPU-profiling TUIkit with Instruments' **Time Profiler**, from
the command line, with the results parsed into a ranked list of hot
functions. No GUI, no external Python packages — just the macOS toolchain
(`xcrun xctrace`) and the Python standard library.

## Why this exists

TUIkit's render pipeline is `@MainActor`-isolated, which blocks the
`ordo-one/benchmark` suite from measuring whole-view rendering (it traps
on a main-thread `DispatchSemaphore`; see
`Documentation/Benchmark coverage and deferred MainActor benchmarks.md`).
Instruments has no such limitation — a normal executable's main thread
*is* the main actor — so the Time Profiler can measure the real render
path end to end. This directory makes that repeatable.

## Two profiling modes

| Mode | What it profiles | Status |
|------|------------------|--------|
| **B — end-to-end (this toolkit)** | The real `TUIkitExample` driven through a PTY: input → 5-layer dispatch → render → diff → `write()` | ✅ working |
| **A — headless render harness** | `renderToBuffer(view:)` on fixed view trees in a tight loop — deterministic, fully CPU-bound, no input timing | ✅ working (`RenderHarness`) |

Mode B is the realism check. Mode A is the microscope for iterating on a
fix; it pairs with the existing `TUIKIT_BENCHMARKS=1 swift package benchmark`
malloc/CPU counters for regression guards (benchmarks are opt-in behind the
`TUIKIT_BENCHMARKS` flag).

> **`--attach` vs `--launch`.** Mode B has `drive.py` fork the app in a
> PTY and points `xctrace record --attach <pid>` at it. Some environments
> deny debugger attach entirely ("Not allowed to attach to process" — CI,
> locked-down VMs, sandboxes); there, Mode B cannot record. Mode A's
> harness needs no PTY, so Instruments can **launch** it
> (`xctrace record --launch -- RenderHarness …`), which those environments
> do allow. When attach is blocked, Mode A is the only profiling option.

## Prerequisites

- macOS with Xcode / Command Line Tools (`xcrun xctrace` — Instruments).
- `python3` (standard library only).
- Run from the repository root.

> Recording attaches Instruments to your own process; no `sudo` needed
> for locally-built binaries. The first run may prompt for Developer
> Tools access.

## Quick start

```bash
# Build (release+symbols), drive a scenario, record, and print hot functions:
Tools/Profiling/record.sh                 # 'tour', 15s, 50x160
Tools/Profiling/record.sh emoji 20        # hammer the 1212-row emoji list
Tools/Profiling/record.sh idle 12         # steady-state per-frame cost
Tools/Profiling/record.sh list 15 24 80   # List page in an 80x24 terminal
```

Traces land in `profiling-traces/` (git-ignored).

## The pieces

### `record.sh` — orchestrator
Builds `TUIkitExample` in release with `-g`, drives the chosen scenario
under the Time Profiler, then analyzes the trace.
`record.sh [scenario] [seconds] [rows] [cols]`.

### `drive.py` — PTY driver
Launches a binary inside a pseudo-terminal (so raw mode + `TIOCGWINSZ`
work), feeds it scripted keyboard/mouse input, and drains output so the
child never stalls. Scenarios: `tour`, `list`, `table`, `emoji`,
`scroll`, `mouse`, `idle`, `progress`.

```bash
# Drive without profiling — a fast sanity check that the app responds:
.build/release/TUIkitExample        # don't run this directly; use:
swift build -c release --product TUIkitExample
python3 Tools/Profiling/drive.py \
    "$(swift build -c release --product TUIkitExample --show-bin-path)/TUIkitExample" \
    --scenario mouse
```

Keyboard input is raw terminal bytes (arrows = `ESC[A/B/C/D`, page jumps
= the `ContentView` shortcut chars). Mouse input is SGR 1006 reports
(`ESC[<button;col;row;M/m`). It quits the app with `q`.

### `analyze_timeprofile.py` — trace → hot functions
Exports the trace's `time-profile` table via `xctrace export` and
aggregates CPU time into five views:

- **Self time** — leaf frame of each sample (where the CPU actually was)
- **Inclusive time** — every distinct function on a sample's stack
- **By module** — your code vs. system libraries
- **App only (self / inclusive)** — restricted to TUIkit / TUIkitExample

```bash
python3 Tools/Profiling/analyze_timeprofile.py profiling-traces/emoji-….trace
python3 Tools/Profiling/analyze_timeprofile.py TRACE --thread main --top 40
python3 Tools/Profiling/analyze_timeprofile.py TRACE --state all   # include off-CPU
```

**Why a custom parser instead of DuckDB?** Instruments' XML dedups
recurring stack frames with an id/ref scheme — the first
`<frame id="11" name="swift_release">`, every repeat `<frame ref="11"/>`
with no name. Tools that don't resolve frame refs (including the
common DuckDB exporter) drop the name on every repeat, which silently
**undercounts the hottest, most-repeated functions** and breaks the
inclusive roll-up. This parser resolves them, so the inclusive view
correctly attributes ~85% to `RenderLoop.renderScene → renderToBuffer`.

### `idle_cpu.py` — idle-cost probe
Launches the app in a PTY, waits a settle period (optionally sending keys
to reach another screen first), then measures CPU time and render output
bytes over a no-input window. A static screen must approach 0% CPU and
0 bytes/s; an animating one (spinner, focused pulse, text cursor) is
non-zero continuously. This is the probe behind the demand-driven
animation-clocks work.

```bash
python3 Tools/Profiling/idle_cpu.py BIN [settle_s] [window_s] [keys]
```

## Interpreting a run

A driven `tour` trace typically shows (on this hardware):

- ~99% of CPU on the **Main Thread** — the render loop is single-threaded.
- Inclusive: `AppRunner.run` → `RenderLoop.renderScene` → `renderToBuffer`
  (~85%), with `measureChild` / `ChildView.measure` (the two-pass layout
  **measure** pass) a large fraction of that.
- Self time dominated by **Unicode width measurement**
  (`_swift_stdlib_getBinaryProperties`, `Character.terminalWidth`) and
  **String/UTF-8 scalar-index** work — both prime caching / algorithmic
  targets.

Capture both a **driven** trace (page switches + scrolling: layout +
diff heavy) and an **idle** trace (`idle` scenario: steady-state per-frame
cost) — they stress different paths.

## Recording results

Profiling that motivates a change is recorded **in the commit message**,
not as committed files — raw `.trace` bundles are large and git-ignored.
A profiling-driven commit quotes the relevant `analyze_timeprofile.py`
excerpts (the hot functions / percentages that matter) and explains how
they informed the change (what was hot, why the change addresses it,
before/after when available). See the "Performance & profiling" rule in
[`.claude/CLAUDE.md`](../../.claude/CLAUDE.md).

## Mode A — headless render harness (`RenderHarness`)

`RenderHarness` is an executable target (`Tools/Profiling/RenderHarness`)
that builds a representative view tree and calls
`renderToBuffer(view, context:)` in a counted loop, then exits. Each tree
keeps its concrete `View` type (no `AnyView` erasure) so the profile
reflects the real `measureChild` / `Layoutable` dispatch.

Trees (`--tree`): `alignment` (three flexible bordered boxes — heavy on the
measure pass), `nested` (a Panel column beside that row), `frames` (bare
`.frame`s where each `FlexibleFrameView` is itself the measured child),
`paneled` (a Panel and a Card wrapping multi-line content — the
labeled-container measure path), `memoRows` (a column of `.equatable()`
bordered rows — the value-based measure memo), `stackRows` (plain
`ForEach` rows in a `VStack` — the automatic `Equatable`-element row
memo), `list` (a long `List` of `ForEach` rows — the lazy visible-window
row rendering), and `form` (a settings page of interactive controls).
Seeds: the shapes in `Benchmarks/TUIkitBenchmarks/RenderBenchmarks.swift`
and the layout tests.

```bash
swift build -c release --product RenderHarness -Xswiftc -g
BIN="$(swift build -c release --product RenderHarness --show-bin-path)/RenderHarness"
xcrun xctrace record --template "Time Profiler" --output harness.trace \
    --launch -- "$BIN" --tree alignment --iterations 10000
python3 Tools/Profiling/analyze_timeprofile.py harness.trace
```

This gives deterministic, input-timing-free profiles ideal for
before/after comparisons while optimizing. Because the harness exits
quickly and takes no input, a plain `/usr/bin/time -p "$BIN" --tree …` is
also a reliable, low-overhead before/after signal where Instruments
sampling is impractical (e.g. a VM where the Time Profiler runs slowly).

Build it with `--product RenderHarness` (or set `BENCHMARK_DISABLE_JEMALLOC=1`)
so the build does not pull the `jemalloc`-backed benchmark target.

Future trees worth adding: a `Table`, a `ScrollView` mid-scroll.
