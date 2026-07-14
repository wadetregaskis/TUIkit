# TUIkitStress

A performance **stress harness shaped like an app**. Its primary purpose is to
be a reproducible instrument for profiling and optimising the TUIkit render
pipeline; it is *secondarily* a showcase of deliberately absurd TUIs.

Unlike `TUIkitExample` (built for humans, to demonstrate features), every
scenario here is built to **push a specific part of the pipeline to its limit**:
deep recursion, wide fan-out, very large data sets, heavy modifier chains,
type-erasure, all-invalidating churn, and so on.

## Why it stays small on disk

There is no bundled data. Every data set is synthesised at launch from a seed
(`Synth.swift`, SplitMix64). The same `(scenario, scale, seed)` always produces
byte-identical content, so:

- a "1,000,000-row" list costs **O(1) memory and zero disk** — rows are hashed
  from their index on demand (`mix(seed, index)`), never stored;
- two profiling runs render exactly the same tree, so before/after comparisons
  are meaningful.

## Running it

```sh
# Interactive (needs a terminal): a menu of scenarios.
swift run TUIkitStress

# Headless smoke test: render every scenario once, non-zero exit on empty.
swift run TUIkitStress --selfcheck

# Headless benchmark of one scenario (no PTY — see "Profiling" below).
swift run -c release TUIkitStress -- --bench --scenario fanout --iterations 2000 --cold
```

### Configuration (environment variable | CLI flag)

| Env | Flag | Meaning |
|---|---|---|
| `TUIKIT_STRESS_SCENARIO` | `--scenario <id>` | boot directly into a scenario |
| `TUIKIT_STRESS_SCALE` | `--scale <n>` | size multiplier (1 is already heavy; 10/100 are pathological) |
| `TUIKIT_STRESS_SEED` | `--seed <n>` | synthetic-data seed |
| `TUIKIT_STRESS_AUTOPILOT` | `--autopilot` | self-drive continuous re-renders |

`--bench` also takes `--iterations N`, `--cols C`, `--rows R`, and `--cold`
(fresh state + cache each frame → worst-case measure+render, vs the default
cache-warm steady state).

Interactive keys: `↑/↓` select · `enter` open · `esc` back/quit · `+/−` change
scale live · `a` toggle autopilot.

## Scenarios

| id | Stresses |
|---|---|
| `megalist` | `List`/`ForEach` windowing, row-id resolution, lazy row content, per-row memo |
| `table` | `Table` column-width computation, row windowing, per-cell value closures |
| `table-multiline` | multi-line cell wrapping, lazy row sizing (visible window + bottom suffix only), variable-height windowing |
| `tables-scroll` | **multiple** `Table`s in a `ScrollView` — N per-table column-width computations, ScrollView windowing over the combined buffer |
| `tables-vstack` | **multiple** `Table`s in a `VStack` (no scroll) — N per-table column-width computations, VStack measure/layout over many table children |
| `deep` | structural `ViewIdentity` chain depth, measure recursion, context propagation |
| `fanout` | non-lazy container measure over **all** children (O(n) layout) |
| `modifiers` | `ModifiedView`/environment-modifier layering, per-node measure overhead |
| `textwall` | text width measurement, word wrapping, glyph throughput |
| `anyview` | type-erasure fallback (render-to-measure), lost concrete dispatch |
| `dashboard` | `Panel`/`Card` container measure + flexible-width row sharing (also the showy demo) |
| `framedcolumns` | non-infinity `.frame` measure, frames-in-stacks-in-frames cascade, uncacheable interactive rows |
| `churn` | full re-render per frame, cache invalidation, measure with no memo hits |
| `kitchensink` | split-view + list windowing + container grid simultaneously |

## Profiling

The `--bench` mode is a counted `renderToBuffer` loop with **no PTY and no
debugger attach**, so — like `Tools/Profiling/RenderHarness` — it can be
profiled by having Instruments *launch* it (works in sandboxes/CI/VMs where
`--attach` is denied):

```sh
swift build -c release --product TUIkitStress -Xswiftc -g
BIN="$(swift build -c release --product TUIkitStress --show-bin-path)/TUIkitStress"
xcrun xctrace record --template 'Time Profiler' --output stress.trace \
    --launch -- "$BIN" --bench --scenario megalist --iterations 5000 --cold
python3 Tools/Profiling/analyze_timeprofile.py stress.trace
```

Always profile a **release** build; debug Swift is an order of magnitude slower
and the relative hot-spots shift.

### How this relates to the other harnesses

- **`Tools/Profiling/RenderHarness`** — tiny, AnyView-free trees for *micro*
  profiling a single shape with maximum signal. Add a tree there when you want
  to isolate one view's dispatch.
- **`Benchmarks/TUIkitBenchmarks`** (ordo-one) — statistical benchmarks with
  warmup/baselines for regression tracking.
- **`TUIkitStress`** (this) — large, realistic, *app-shaped* worst cases for
  finding where the pipeline falls over at scale. Start here to discover a
  bottleneck; reproduce it minimally in `RenderHarness`; lock it in
  `TUIkitBenchmarks`.

## Adding a scenario

1. Add `Sources/TUIkitStress/Scenarios/Foo.swift` with a `FooScenario.descriptor`
   (`Scenario` value) and a private `View`.
2. Append `FooScenario.descriptor` to `Scenarios.all` in `Scenario.swift`.
3. Prefer **on-demand** synthesis (`mix(seed, index)` per visible row) over a
   pre-materialised array, so memory stays O(visible). If you must materialise
   (e.g. `Table`), build it once in the view's `init`, not in `body`.
