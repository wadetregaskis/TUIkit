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
Instruments has no such limitation — it samples whatever thread is running,
and never needs to block the main actor to take a measurement — so the Time
Profiler can measure the real render path end to end. This directory makes
that repeatable.

> Do not read that as "the main thread *is* the main actor", which this
> README used to claim. It is false on Linux: from the first suspension
> point onward the main actor is drained by a cooperative pool thread, not
> the process main thread (measured; see the "Thread correctness" note in
> `Sources/TUIkitCore/Concurrency/StackGuard.swift`). Profile by sampling
> the process, not by assuming which thread the render is on.

## Two profiling modes

| Mode | What it profiles | Status |
|------|------------------|--------|
| **B — end-to-end (this toolkit)** | The real `Example` driven through a PTY: input → 5-layer dispatch → render → diff → `write()` | ✅ working |
| **A — headless render harness** | `renderToBuffer(view:)` on fixed view trees in a tight loop — deterministic, fully CPU-bound, no input timing | ✅ working (`RenderHarness`) |
| **A′ — headless image harness** | `ASCIIConverter` over a picture, per cell and per pixel separately | ✅ working (`ImageHarness`) |

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

## What a page costs to ARRIVE — `page_open.py`

`drive.py` measures a scenario running; this measures a page arriving, which is
what "slow to open" means. It resets the menu cursor, opens item *i*, and reads
until the output has been quiet, reporting wall time and bytes per round — in
ONE process, so a cost paid once per page per session shows up as round 0 and
nowhere else.

```bash
Tools/Profiling/page_open.py .build/release/Example 1,13,20 --rounds 4 --cols 200 --rows 50
PROBE_HOST=Apple_Terminal Tools/Profiling/page_open.py .build/release/Example 1
```

`PROBE_HOST` sets `TERM_PROGRAM`, which selects the per-host compensation walks
in `FrameDiffWriter` — those run only in emission, so `Stress --bench` cannot
see them. An animated page never goes quiet and reads as the `--quiet` cap;
that is a limit of the oracle, not a measurement.

## Deciding whether a change actually helped — `ab_bench.py`

Profiling says *where* the time goes. Deciding whether a change moved it is a
separate, and surprisingly easy to get wrong, question:

```bash
swift build -c release --product Stress && cp .build/release/Stress /tmp/old
# …make the change…
swift build -c release --product Stress && cp .build/release/Stress /tmp/new
Tools/Profiling/ab_bench.py /tmp/old /tmp/new                    # all 17 scenarios
Tools/Profiling/ab_bench.py /tmp/old /tmp/new --scenarios fanout --reps 40
Tools/Profiling/ab_bench.py /tmp/old /tmp/new --cold             # all-miss frames
```

`--cold` resets the state store and render cache before every frame, so nothing
is ever served from a cache. The default (warm) run measures the steady state an
app spends its life in; `--cold` measures the other end — the first frame of a
page, and, more to the point, **the honest check on any change that trades a
cheaper cache hit for a dearer miss.** Run it whenever the change touched what
happens on a miss.

It prints a change, a 95% interval and a **verdict** per scenario:

```
scenario           iters     old µs     new µs   change           95% CI  verdict
modifiers           1077     1154.7     1492.3   +29.9%    +28.2%  +31.0%  slower
fanout               349     4724.5     4463.0    -5.7%     -6.7%   -2.2%  faster
anyview              727     1974.2     1996.2    +0.5%     -3.2%   +3.1%  indistinguishable
```

`indistinguishable` is the answer that matters. Two changes were committed and
reverted on 2026-08-12/13 (§31 and §33 of
`Documentation/Performance-profile-2026-08.md`) because a hand-rolled A/B gave
them a number with a sign where the honest answer was "cannot tell".

Four things make it trustworthy, and each was validated by measurement:

| | |
|---|---|
| **CPU time, not wall clock** | Reads the harness's `cpu-per-frame`. Preemption by everything else on the box no longer lands in the number. |
| **RAM beside CPU** | Reads the harness's `rss-peak` and prints `ram OLD->NEW` after the verdict. Plain medians, not a bootstrap: peak RSS barely varies between runs of one binary, so an interval on it would be theatre. A change over a megabyte is worth a look; below that it is allocator noise. |
| **Randomised run order** | A fixed order is a fixed bias — every hand-run pass showed whichever binary ran *second* as slower, including the pass where that was the original. |
| **Paired ratios + a bootstrap CI** | A and B run adjacent in time, so drift hits both; comparing per-rep ratios cancels it, and the interval prices what is left. |
| **Calibrated iteration count** | 300 iterations of a 160 µs scenario is 50 ms of measurement, mostly warm-up. Each run is sized to ~1.5 s. |

**Noise floor** (identical binary against a copy of itself, machine at load
1.7 with a browser taking 27% of a core): `dashboard` ±0.7%, `table` ±1.7%,
`churn` ±2%, `fanout` ±3% at the default 15 reps and ±2% at 40. Run the null
test yourself — `ab_bench.py X X` — whenever you doubt a result; it costs one
command and tells you exactly what this machine can resolve today.

**Some scenarios cannot resolve anything small.** `megalist` and
`tables-vstack` null-test at **±15%** on this machine — their own run-to-run
spread swamps any change worth making. Both produced spurious verdicts on a
change that was fine (`tables-vstack` "+3.7% slower", `megalist` "+7.8%"), and
the null test is what exposed them. Check a scenario's floor before trusting
its verdict.

**One false positive per sweep is expected.** Seventeen scenarios at 95%
confidence means roughly one verdict per run is wrong by chance. Treat a
`faster`/`slower` whose interval *edge* sits on zero as a prompt to re-test —
`--reps 40 --seed <something else>` — not as a result. That is exactly what
happened to `table` in commit 114f7fa9: +0.7% [+0.0, +1.6] "slower" on the
first pass, +0.5% [-0.1, +1.0] indistinguishable on the second.

**Two tuning knobs that measured worse, so they are not options:** taking the
minimum of several runs per binary per rep (widened `fanout` to ±5% — the min
is a biased estimator whose bias tracks the local noise, and the extra runs
push A and B further apart in time, weakening the pairing); and shorter runs
with proportionally more reps (helped `churn`, hurt `fanout`, which needs
enough frames to amortise process start-up).

## `ab_bench.py` is blind to the whole output half — `emit_bench.py`

`--bench` is a counted `renderToBuffer` loop with **no PTY**. Everything
downstream of the frame buffer therefore never runs:
`FrameDiffWriter.buildOutputLines`, the per-line right-edge clip, the per-host
cursor-compensation walks, the diff, the writes. `buildOutputLines` is called
only from `RenderLoop`, and `ab_bench.py` never starts one.

That is not a small blind spot. It is where every terminal quirk workaround in
the framework lives, and a change there can be measured by `ab_bench.py` as
exactly zero while being worth 2% of a real app's CPU.

The one-command proof, worth re-running whenever this is doubted — force the
heaviest compensation walk of any host and compare it against the lightest:

```sh
TERM_PROGRAM=Apple_Terminal $BIN --bench --scenario dashboard --iterations 4000
TERM_PROGRAM=ghostty        $BIN --bench --scenario dashboard --iterations 4000
```

144.3 µs vs 143.7 µs — identical. If emission were in the timed region it
could not be.

`emit_bench.py` measures that half. It runs the app for real — a PTY,
`--autopilot`, the host forced by environment — and reads the process's own
CPU time over a fixed window, the technique `idle_cpu.py` already established
here (`ps -o cputime=`; `RUSAGE_CHILDREN` reads 0 for a live child). The
statistics are `ab_bench.py`'s, for the same reasons: CPU time not wall clock,
order randomised per rep, paired ratios, a bootstrap interval, and
"indistinguishable" whenever that interval touches 1.0.

```sh
Tools/Profiling/emit_bench.py /tmp/old /tmp/new --host Apple_Terminal
Tools/Profiling/emit_bench.py /tmp/old /tmp/new --scenarios dashboard --window 8.0
```

**Its resolution is coarser than `ab_bench.py`'s**, and the reason is `ps`:
CPU time comes back in centiseconds, so a scenario burning 0.25 s over the
window has two significant digits and ties are common. Lengthen `--window`
before believing a small number — the same measurement went from ±5.2% at
`--window 3.0` to ±3.5% at 8.0. A tie is reported as indistinguishable, not
as a verdict.

## The pieces

### `record.sh` — orchestrator
Builds `Example` in release with `-g`, drives the chosen scenario
under the Time Profiler, then analyzes the trace.
`record.sh [scenario] [seconds] [rows] [cols]`.

### `drive.py` — PTY driver
Launches a binary inside a pseudo-terminal (so raw mode + `TIOCGWINSZ`
work), feeds it scripted keyboard/mouse input, and drains output so the
child never stalls. Scenarios: `tour`, `list`, `table`, `emoji`,
`scroll`, `mouse`, `idle`, `progress`.

```bash
# Drive without profiling — a fast sanity check that the app responds:
.build/release/Example        # don't run this directly; use:
swift build -c release --product Example
python3 Tools/Profiling/drive.py \
    "$(swift build -c release --product Example --show-bin-path)/Example" \
    --scenario mouse
```

Keyboard input is raw terminal bytes (arrows = `ESC[A/B/C/D`, page jumps
= the `ContentView` shortcut chars). Mouse input is SGR 1006 reports
(`ESC[<button;col;row;M/m`). It quits the app with `q`.

### `analyze_timeprofile.py` — trace → hot functions

> **`--blame` is usually the one you want.** Self time says where the CPU was,
> and for this framework the honest answer is `swift_release`, `swift_retain`
> and `malloc` — true, and useless, because none of them is a thing anyone can
> go and fix. `--blame` credits each sample to the nearest TUIkit frame
> *beneath* the leaf, turning "the runtime is busy" into "this function is
> making it busy". With a regex it restricts to samples that bottomed out in a
> particular kind of work:
>
> ```sh
> python3 Tools/Profiling/analyze_timeprofile.py t.trace --blame
> python3 Tools/Profiling/analyze_timeprofile.py t.trace \
>     --blame 'swift_retain|swift_release|_malloc|tiny_|Metadata'
> ```
>
> On the `menu` tree the leaf view said 55% libswiftCore and named nothing
> actionable; `--blame` said environment access 15.8%, `AnyIterator.next()`
> 9.2%, identity nodes 3.8%, string building 3.3% and array regrowth 3.0%.

**Profiling the live app, emission included.** Instruments cannot `--launch`
a PTY app and `--attach` is denied here, but `xcrun xctrace record
--all-processes --time-limit 8s` records everything on the machine while
`idle_cpu.py` drives the app under autopilot; `--process <name>` then keeps
only that process's samples. That is the only profile that shows the output
half of a frame (`FrameDiffWriter`, the cell diff, `SGRState`), which
`--bench` never runs. The recording is large and Instruments leaves an
`instruments*.ktrace` of 100–900 MB in `$TMPDIR` after EVERY recording —
delete both once analysed.
Exports the trace's `time-profile` table via `xctrace export` and
aggregates CPU time into five views:

- **Self time** — leaf frame of each sample (where the CPU actually was)
- **Inclusive time** — every distinct function on a sample's stack
- **By module** — your code vs. system libraries
- **App only (self / inclusive)** — restricted to TUIkit / Example

```bash
python3 Tools/Profiling/analyze_timeprofile.py profiling-traces/emoji-….trace
python3 Tools/Profiling/analyze_timeprofile.py TRACE --thread main --top 40
python3 Tools/Profiling/analyze_timeprofile.py TRACE --state all   # include off-CPU
python3 Tools/Profiling/analyze_timeprofile.py TRACE --process Stress  # one process of an --all-processes trace
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

### `analyze_stream.py` — where the BYTES went
Attributes the output a run produced, rather than the time it took. Give it a
stream captured by `drive.py --dump OUT.ansi` and it splits it into the three
things a stream can be — styling (SGR), positioning and erasing (other CSI),
and the cells themselves — then replays it through a minimal terminal model to
say how much of the styling was *necessary*. That last part is the point: a
frame can be correct, fast to produce, and still spend most of itself
restating a colour the terminal already had.

```bash
python3 Tools/Profiling/drive.py BIN --dump /tmp/frames.ansi
python3 Tools/Profiling/analyze_stream.py /tmp/frames.ansi
```

### `idle-image.sh` + `IdleProbe` — idle cost with nothing else awake
`idle_cpu.py` answers "what does a static screen cost?" only for a screen that
is genuinely static, and every `Example` page carrying an `Image` also carries
focusable controls — a focused control pulses, so the loop is legitimately
awake and the reading says nothing about the image. `IdleProbe` is a minimal
app whose whole scene is the thing under test and nothing else;
`idle-image.sh` builds and runs it for the `Image` case.

```bash
Tools/Profiling/idle-image.sh
```

Reach for this shape whenever the question is "does X keep the loop awake?"
and X shares a page with anything else that legitimately does.

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

The harness installs what `RenderLoop` installs — state storage, a render
cache, a preference store, a **volatile read tracker** (a precondition of the
measure memo, not a diagnostic), an identity tree rooted at a TYPE — and runs
the per-pass lifecycle around every iteration. That is fidelity, not ceremony:
without the prune this harness reported `list` at 108 MB of peak RSS and
`memoRows` at 23 MB, against 8.3 MB and 7.9 MB once the pass closes properly.
A harness that never prunes is measuring itself.

This gives deterministic, input-timing-free profiles ideal for
before/after comparisons while optimizing. Because the harness exits
quickly and takes no input, a plain `/usr/bin/time -p "$BIN" --tree …` is
also a reliable, low-overhead before/after signal where Instruments
sampling is impractical (e.g. a VM where the Time Profiler runs slowly).

Build it with `--product RenderHarness` (or set `BENCHMARK_DISABLE_JEMALLOC=1`)
so the build does not pull the `jemalloc`-backed benchmark target.

Future trees worth adding: a `Table`, a `ScrollView` mid-scroll.

## Mode A, for pictures — `ImageHarness`

`RenderHarness` loops a view render; `ImageHarness`
(`Tools/Profiling/ImageHarness`) loops an `ASCIIConverter` over a picture. It
needs a target of its own because the image pipeline has **two halves with
costs two orders of magnitude apart**, and a change to one of them says nothing
about the other:

| `--path` | what it runs | asked | reported as |
|---|---|---|---|
| `glyph` | `convert` — an SGR per cell | ~2 per CELL | ns/cell |
| `pixel` | `recoloured` — the picture a graphics protocol carries | once per PIXEL | ns/pixel |
| `colour` | `Color.downsampledToPalette256()` alone, over distinct colours | — | ns/colour |

A cell is about 8×17 device pixels, so the same picture asks the pixel path
roughly two hundred times more often than the glyph path. That is why an exact
palette search is affordable per cell and ruinous per pixel, and why a table
lookup can be the right trade in one and pointless in the other.

`--path colour` exists because in both of the others the quantiser is a small
part of a large total — resampling, sharpening, glyph choice and string
building are most of what a conversion costs — so a quantiser that got four
times dearer can hide inside `--path glyph`'s noise and still be the wrong
trade. It uses distinct colours deliberately: `Color`'s answer is memoised, and
a loop over one colour measures a dictionary.

```bash
swift build -c release --product ImageHarness
BIN="$(swift build -c release --product ImageHarness --show-bin-path)/ImageHarness"
"$BIN" --path glyph --mode ansi256 --iterations 30
"$BIN" --path pixel --mode ansi256 --dither floyd --iterations 8
"$BIN" --path colour --cols 400 --rows 100 --iterations 3
```

Modes (`--mode`): `truecolor`, `ansi256`, `ansi16`, `grayscale`, `mono`,
`shades8`. The source picture is synthetic but has a photograph's colour
*statistics* — smooth gradients with enough grain that the colours are nearly
all distinct — because a picture of flat bands is answered by any memo and
would measure the memo instead of the quantiser.

Each run prints a checksum derived from the output, both to defeat dead-code
elimination and so two builds that should agree can be seen to.

For an A/B, build both binaries, keep a copy of each, and alternate them —
`ab_bench.py`'s statistics do not apply here (this harness reports wall time
for one binary, not paired CPU-time ratios), so run three or more alternating
reps and look at the spread before believing a small difference.
