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
| **A — headless render harness** | `renderToBuffer(view:)` on fixed view trees in a tight loop — deterministic, fully CPU-bound, no input timing | 🔜 proposed (see below) |

Mode B is the realism check. Mode A (when built) is the microscope for
iterating on a fix; it pairs with the existing `swift package benchmark`
malloc/CPU counters for regression guards.

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
Tools/Profiling/record.sh list 15 80 24   # List page in an 80x24 terminal
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
`scroll`, `mouse`, `idle`.

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

## Proposed: Mode A — headless render harness

A small executable target (e.g. `Tools/Profiling/RenderHarness` or a
`--profile` flag on a dedicated target) that builds representative view
trees — the mixed-form page, a 1900-row `List`, a `Table`, a
`ScrollView` mid-scroll — and calls `renderToBuffer(view, context:)` in a
counted loop, then exits. Profile with:

```bash
xcrun xctrace record --template "Time Profiler" --output harness.trace \
    --launch -- .build/release/RenderHarness --tree list --iterations 5000
python3 Tools/Profiling/analyze_timeprofile.py harness.trace
```

This gives deterministic, fully-symbolicated, input-timing-free profiles
ideal for before/after comparisons while optimizing. The view trees in
`Benchmarks/TUIkitBenchmarks/RenderBenchmarks.swift` are the seed.
