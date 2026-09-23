# Stress

A performance **stress harness shaped like an app**. Its primary purpose is to
be a reproducible instrument for profiling and optimising the TUIkit render
pipeline; it is *secondarily* a showcase of deliberately absurd TUIs.

Unlike `Example` (built for humans, to demonstrate features), every
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
swift run Stress

# Headless smoke test: render every scenario once, non-zero exit on empty.
swift run Stress --selfcheck

# Headless benchmark of one scenario (no PTY — see "Profiling" below).
swift run -c release Stress -- --bench --scenario fanout --iterations 2000 --cold
```

### Configuration (environment variable | CLI flag)

| Env | Flag | Meaning |
|---|---|---|
| `TUIKIT_STRESS_SCENARIO` | `--scenario <id>` | boot directly into a scenario |
| `TUIKIT_STRESS_VARIANT` | `--variant <id>` | pick a variant of a matrix scenario (see below) |
| `TUIKIT_STRESS_SCALE` | `--scale <n>` | size multiplier (1 is already heavy; 10/100 are pathological) |
| `TUIKIT_STRESS_SEED` | `--seed <n>` | synthetic-data seed |
| `TUIKIT_STRESS_AUTOPILOT` | `--autopilot` | self-drive continuous re-renders |

`--variants` lists every matrix scenario's variants, grouped by the axis each
one varies. `--bench` also takes `--iterations N`, `--cols C`, `--rows R`, and `--cold`
(fresh state + cache each frame → worst-case measure+render, vs the default
cache-warm steady state).

Interactive keys: `↑/↓` select · `enter` open · `esc` back/quit · `+/−` change
scale live · `a` toggle autopilot.

## Scenarios

| id | Stresses |
|---|---|
| `megalist` | `List`/`ForEach` windowing, row-id resolution, lazy row content, per-row memo |
| `scrollfollow` | bottom-anchored `ScrollView` over variable-height rows with one appended per tick — windowed band render, anchor advance, tail estimate, O(window) at any N |
| `table` | `Table` column-width computation, row windowing, per-cell value closures |
| `table-multiline` | multi-line cell wrapping, lazy row sizing (visible window + bottom suffix only), variable-height windowing |
| `truncate` | ANSI-aware clipping, all three truncation modes, per-cell measure/pad |
| `table-churn` | per-row re-render of *unchanged* rows — the data is replaced every frame but ~2% of rows differ |
| `table-churn-wrapped` | the same, 250 rows wrapped: below the extent estimator's row limit, where every row is measured |
| `table-tail` | a window over a growing sequence — rows keep their content and change position |
| `table-api` | **a matrix**: one `Table` built every way the API allows, one variant per point (see below) |
| `app-shapes` | **a matrix**: whole applications — file browser, log viewer, process monitor, mail client, settings form, code editor (settled and tailing), chat |
| `tables-scroll` | **multiple** `Table`s in a `ScrollView` — N per-table column-width computations, ScrollView windowing over the combined buffer |
| `tables-vstack` | **multiple** `Table`s in a `VStack` (no scroll) — N per-table column-width computations, VStack measure/layout over many table children |
| `deep` | structural `ViewIdentity` chain depth, measure recursion, context propagation |
| `fanout` | non-lazy container measure over **all** children (O(n) layout) |
| `modifiers` | `ModifiedView`/environment-modifier layering, per-node measure overhead |
| `preferences` | preference side-effect declaration, value-memo defeat, per-row re-measure |
| `customlayout` | `Layout` protocol call pattern, repeated subview measurement, `AnyLayout` erasure |
| `textwall` | text width measurement, word wrapping, glyph throughput |
| `anyview` | type-erasure fallback (render-to-measure), lost concrete dispatch |
| `dashboard` | `Panel`/`Card` container measure + flexible-width row sharing (also the showy demo) |
| `framedcolumns` | non-infinity `.frame` measure, frames-in-stacks-in-frames cascade, uncacheable interactive rows |
| `churn` | full re-render per frame, cache invalidation, measure with no memo hits |
| `animating` | animation store lookups, uncacheable subtrees, colour resolution per frame |
| `translucent` | cell decomposition of both sides, per-cell region lookup, SGR re-emission |
| `gradients` | ramp quantisation, per-cell geometry, origin propagation, re-ink on move, SGR runs |
| `alpharamp` | per-cell alpha compositing over a patterned ground, blend arithmetic |
| `menus` | `ButtonStyle` body measure, menu hug-width pass, shortcut hint column, per-row `@Environment` resolution |
| `keyrows` | per-row registrations (`onKeyPress`, `.statusBarItems`) under the row memo, per-frame key and status-bar registries, a `.refreshable` panel |
| `kitchensink` | split-view + list windowing + container grid simultaneously |

## Matrix scenarios and variants

Some questions are not about *a* shape but about a *space of* shapes: how a
`Table` behaves across every way an app can build one. There are dozens of those
points, they differ by a line each, and none of them wants a title a translator
will ever read — so they are **variants** of one registered scenario rather than
scenarios of their own.

```sh
swift run Stress -- --variants                                  # list them
swift run Stress -- --bench --scenario table-api --variant width-fit
```

`--selfcheck` renders every variant of every matrix scenario, not just the one a
config selects, so the whole space is smoke-tested (and, with
`TUIKIT_VERIFY_RENDER_MEMO=1`, memo-verified) on every run.

`app-shapes` is the other kind of matrix: not one API's space but whole
applications, because the costs worth finding live in the COMBINATIONS. A file
browser is a split view over a sortable table of formatter-built cells; a
process monitor re-sorts four hundred rows whose every number moved; a chat is
bottom-anchored bubbles of wildly unequal height. Nothing assembled from single
-purpose fixtures puts those together, and each of them has already priced
something the parts could not — `chat` against `chat-eager` is 1.4 ms against
189 ms for the same application, the only difference being `LazyVStack` where an
app would write `VStack`.

Several variants come in pairs for exactly that reason, and the pair is the
measurement: `chat`/`chat-eager` prices laziness, and `code-editor`/
`code-editor-tailing` prices a SETTLED document against a growing one. The
second of each pair exists because every memo keyed on the rows' data — the row
memo, a `Table`'s `.fit` column, a windowed stack's width over all rows — serves
100% on the settled shape and 0% on the growing one, and a matrix that only ever
measured the settled shape would report the memo's best day as its only day.

`table-api` is the first: 43 variants over seven axes — how a column gets its
value (key path, closure, sort-by-one-display-another, non-`Equatable` rows,
class rows), the four width modes, what a cell holds (interpolated integers,
Foundation formatters, SGR, CJK/emoji, over-long text), truncation mode, line
limits and alignment and column spacing, the selection and sort bindings, the
update pattern, and the size/chrome/surroundings. A variant is a struct literal
in `TableAPI*Variants.swift`; adding one costs no registry entry and no
translations.

## Sessions: a UI in use, over time

A scenario is a UI at rest, drawn again and again. A **session** is a UI in
use: an interaction script played against a page step after step — keys typed
into it, rows inserted and moved under it, the terminal resized around it. The
bugs of a UI in use are the ones that need a write, a scroll or a moved row
between two frames, and a screen drawn at rest never has one.

```sh
swift run Stress -- --sessions                                   # list them
swift run -c release Stress -- --session editor --steps 3000 --verify --resize-every 97
swift run -c release Stress -- --bench --scenario session/editor --iterations 2000
```

A session drives the REAL render loop headless (`HeadlessApp`): keys go through
the app's five-layer input chain to the focused control, and a frame is the
loop's own — header, status bar and diff writer included — at an instant the
runner supplies, so two runs of one script draw the same pictures. Its report
prices each KIND of step separately (mean, p50, p95, max, bytes emitted), since
a keystroke and a page-down are different frames.

`--verify` is the oracle, and it needs no expected pictures: a second instance
plays the same script with its render cache emptied before every frame, and
every frame must match. A cache is right exactly when a frame drawn through it
is the frame drawn without it, so any difference is a memo, a kept width or an
invalidation serving something stale — the class of bug that static renders
cannot see. `--selfcheck` plays every session a short way this way, the
terminal resized under it, so CI does too.

The oracle was checked the way a test is: with the kept all-rows width's
challenge disabled (the fix of `65d3015f`), `--session editor --steps 1500
--verify` reports 75 of 1,500 frames different from the twin's, the first at
step 1,106 — the stale width scrolls the rows to a different slice. Note
where: a hundred and fifty steps would not have reached it. The selfcheck is a
smoke test; a change to a memo or a kept value deserves a few thousand
verified steps of the sessions it touches.

`--bench --scenario session/<id>` plays one step per iteration and prints the
lines `ab_bench.py` reads, so a session is A/B'd exactly as a scenario is.

Writing one, `--trace` prints each step's action and keys as it is played, and
`--show` the last frame with its styling stripped — which is how you find out
that the keys you meant for the list went into the search field that held the
focus.

| id | Exercises |
|---|---|
| `editor` | an index-keyed code editor in a two-axis scroll view: a row's width moving under an unchanged collection, the kept all-rows width, `scrollTo` following the caret, per-keystroke frames |
| `inbox` | a searchable, selectable `List` of items that arrive, leave, move and change underneath: keyed rows around the selection, the row memo, `List` windowing, a search narrowing and restoring the collection, focus between a field and a list |
| `log` | a log viewer following its end while lines arrive in bursts, and a reader paging back: a bottom-anchored lazy stack growing under the viewport, wrapped lines of unequal height, `scrollPosition(id:)` reporting the top line |
| `settings` | a settings `Form` worked through with the keyboard while accounts sync in and out: focus traversal, toggles, a picker, a stepper, a disclosure group opening and closing, every row re-shown when the units change |
| `processes` | a sortable, filterable process `Table` whose numbers move on every step: `.fit` columns and the row memo under continuous churn, re-sorting, a filter narrowing the rows, rows appended and removed, selection moved with the keys |

Adding one: a `StressSession` — a page built once over a model the session
owns, and a `step(_:)` that makes that step's data changes on the model and
returns the input to deliver — plus a `SessionDescriptor` in `Sessions.all`.
Choices come from a `SessionRandom` seeded from the config, so the twin makes
the same ones.

## Profiling

The `--bench` mode is a counted `renderToBuffer` loop with **no PTY and no
debugger attach**, so — like `Tools/Profiling/RenderHarness` — it can be
profiled by having Instruments *launch* it (works in sandboxes/CI/VMs where
`--attach` is denied):

Each iteration runs the live loop's per-pass lifecycle around the render —
`StateStorage`/`RenderCache.beginRenderPass()` before, `endRenderPass()` /
`removeInactive()` after — and the identity tree is rooted at a type, as
`RenderLoop` roots an app. Both matter: without the lifecycle the cache was
never pruned and the per-pass measure memo never emptied, so an off-screen
row's size was a hit here and a miss in the app, and a memo that grew by
every miss forever put dictionary resizes into profiles of code that has
none; with a raw-string root, every identity's ancestor test rendered path
strings, and the end-of-pass prune was 88–95% of a frame that the app does
not pay. `cpu-per-frame` numbers from before 2026-09-05 were taken without
either and are not comparable.

`--bench` also reports **`rss-peak`, `rss-mean` and `rss-sampled-peak`** —
`ru_maxrss` for the high-water mark, plus the resident size sampled every 64th
frame so a peak reached once is distinguishable from one held all run. Sampling
sits outside the timed region, so the CPU and wall figures still measure exactly
the render. This exists because a render cache buys CPU by keeping buffers, and
until it did, nothing priced that side of the trade: `ab_bench.py` now prints
the peak beside the timing verdict.

```sh
swift build -c release --product Stress -Xswiftc -g
BIN="$(swift build -c release --product Stress --show-bin-path)/Stress"
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
- **`Stress`** (this) — large, realistic, *app-shaped* worst cases for
  finding where the pipeline falls over at scale. Start here to discover a
  bottleneck; reproduce it minimally in `RenderHarness`; lock it in
  `TUIkitBenchmarks`.

## Adding a scenario

1. Add `Sources/Stress/Scenarios/Foo.swift` with a `FooScenario.descriptor`
   (`Scenario` value) and a private `View`.
2. Append `FooScenario.descriptor` to `Scenarios.all` in `Scenario.swift`.
3. Prefer **on-demand** synthesis (`mix(seed, index)` per visible row) over a
   pre-materialised array, so memory stays O(visible). If you must materialise
   (e.g. `Table`), build it once in the view's `init`, not in `body`.

Adding a **variant** to an existing matrix scenario is smaller: append a
`variant(_:axis:_:_:)` literal to the relevant group in that scenario's
`*Variants.swift`. It is listed, benchable and self-checked from there, with no
registry entry and no strings to translate.
