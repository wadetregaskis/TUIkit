# Where TUIkit spends its time — a full profile of Stress and the Example

**Measured 2026-08-11**, on macOS 15.7 / arm64, release build (`-Xswiftc -g` for
symbols). Every number here is measured, not estimated; the method for each is
stated so it can be re-run and disagreed with.

This is a survey, not a fix. It ends with a ranked list of what the numbers say
is worth doing.

---

## 1. Method

**Stress — throughput.** `Stress --bench --scenario <id> --scale N --cols 120
--rows 40`, all 17 scenarios × scales 1/2/4/8. Iteration counts are chosen per
cell to target ~1.2 s of render work (5–400 iterations), with one discarded
warm-up run per cell, so no cell is dominated by first-frame costs. The harness
times `renderToBuffer` only — its own checksum/blank-frame bookkeeping is
outside the timer.

**Stress — attribution.** `xctrace record --template "Time Profiler" --launch`
on each scenario at scale 2, ~6 s of render work each, analysed with
`Tools/Profiling/analyze_timeprofile.py`. Traces are ~15 MB each and were
deleted after analysis; nothing was committed.

> A trap worth recording: `swift build` with and without `-Xswiftc -g`
> **removes the other product's binary**. A whole batch of traces came back
> "malformed — run data is missing" because `xctrace --launch` was pointed at a
> path SwiftPM had deleted when the flags changed. Build every product you are
> about to profile with the same flags, and check the binary exists first.

**Example — per-page cost.** One live PTY session at 150×50 walking all 32
pages, with `TUIKIT_CONFIG_DIR` set to a scratch directory (never the user's
real preferences). Per page: `idle%` is CPU over a 2 s window with no input;
`ms/pass` is CPU per forced full render, driven by toggling the pty window
between two adjacent widths — a resize forces a genuine relayout on *every*
page, where Tab does nothing on a page with nothing focusable.

---

## 2. Stress: how cost relates to scale

`--scale N` multiplies each scenario's base count (`config.sized(base)`). The
exponent is a least-squares fit of log(time) against log(scale) over the four
points; `×/2×` is the factor per doubling.

| scenario | 1× | 2× | 4× | 8× | ×/2× | exponent | what scale multiplies |
|---|---:|---:|---:|---:|---:|---:|---|
| megalist | 414 | 429 | 421 | 406 | 0.99 | −0.01 | List rows (50 000) |
| table | 971 | 963 | 957 | 957 | 1.00 | −0.01 | Table rows (20 000) |
| preferences | 338 | 332 | 332 | 335 | 1.00 | 0.00 | preference rows (400) |
| table-multiline | 2098 | 2217 | 2120 | 2144 | 1.00 | 0.00 | Table rows (20 000) |
| scrollfollow | 451 | 458 | 474 | 482 | 1.02 | 0.03 | rows (1 000 000) |
| kitchensink | 839 | 1152 | 1203 | 1280 | 1.14 | 0.19 | mixed |
| dashboard | 326 | 594 | 635 | 730 | 1.28 | 0.36 | panels (12) |
| framedcolumns | 912 | 1369 | 2271 | 3939 | 1.63 | 0.71 | columns (5) |
| tables-vstack | 1308 | 2148 | 3813 | 7288 | 1.77 | 0.83 | tables (8) |
| customlayout | 493 | 951 | 1850 | 3617 | 1.94 | 0.96 | subviews (20) |
| tables-scroll | 4236 | 8167 | 15886 | 31365 | 1.95 | 0.96 | tables (8) |
| churn | 3069 | 6190 | 14280 | 36690 | 2.29 | 1.19 | ticking rows (300) |
| **anyview** | 5441 | 13737 | 44066 | 139500 | 2.97 | **1.57** | erased rows (500) |
| **textwall** | 4006 | 11450 | 36067 | 127398 | 3.17 | **1.66** | paragraphs (300) |
| **fanout** | 22429 | 67104 | 242355 | 854440 | 3.39 | **1.76** | VStack children (2000) |
| **modifiers** | 7048 | 23659 | 79908 | 301278 | 3.48 | **1.80** | wrapped rows (400) |
| **deep** | 7231 | 22434 | 82734 | 315366 | 3.54 | **1.82** | nesting *depth* (40) |

(µs per frame, 120×40.)

Three bands, and the boundaries are exactly where the design says they should
be:

**Flat (exponent ≈ 0) — windowing works.** `megalist`, `table`,
`table-multiline`, `scrollfollow`, `preferences`. A million rows costs the same
as fifty thousand. This is the payoff from the O(visible) work in `List` and
`Table`, and it holds at every scale tested.

**Sub-linear to linear (0.7–1.0) — shared viewport.** `framedcolumns`,
`tables-vstack`, `customlayout`, `tables-scroll`. More tables in the same
viewport means each one windows to fewer rows, so doubling the count costs less
than double. Nothing to fix.

**Super-linear (1.6–1.8) — the interesting band.** `anyview`, `textwall`,
`fanout`, `modifiers`, `deep`.

`deep` is expected: it scales *depth*, and the O(depth²) re-measure in the
nesting limiter is known and documented. The other four scale a **count of
siblings**, where the intended cost is O(N). They are the finding.

**In the vocabulary of the earlier `deep` characterisation — "3× slower per 2×
scale" — the four sibling-count scenarios run at 3.0–3.5× per 2× scale, i.e.
they are as bad as the known-quadratic case.**

---

## 3. Why the sibling-count scenarios are super-linear

The obvious suspects were tested and are **not** the cause.

**Not the ScrollView's natural-extent ladder.** `measureNaturalExtent` grows its
budget ×8 per rung, each rung a full measure. Counting rungs directly (temporary
instrumentation, since reverted): `fanout` runs **1** rung at scales 1–2 and
**2** at scales 4–8. The rung count is constant across 4→8, where the time still
rises 3.62×.

**Not text volume.** Halving the terminal width halves every row's string
content and changes the time by **0.3%**:

| | 120 cols | 60 cols |
|---|---:|---:|
| fanout scale 4 | 226 297 µs | 227 035 µs |
| fanout scale 8 | 804 809 µs | 807 928 µs |

**Not call-count growth.** Counting `measureChild` / `renderChild` calls per
frame:

| scale | children | measures/frame | renders/frame | µs/frame | **µs per measure** |
|---:|---:|---:|---:|---:|---:|
| 1 | 2 000 | 14 409 | 3 603 | 21 425 | 1.49 |
| 2 | 4 000 | 28 809 | 7 203 | 62 833 | 2.18 |
| 4 | 8 000 | 75 212 | 14 403 | 222 456 | 2.96 |
| 8 | 16 000 | 150 412 | 28 803 | 804 874 | 5.35 |

Call counts are **linear** in the child count (the jump at scale 4 is the extra
ladder rung, and it is a one-off step, not growth). What grows is the **cost of
each call — 3.6× from 2 000 to 16 000 children**, with an unchanged instruction
mix in the profile.

That is the signature of the memory hierarchy, not of an algorithm: the same
work, done over a larger live object graph, missing cache on every pointer
chase. The width experiment says the working set that matters is **counted in
objects, not bytes** — halving the string content changed nothing, because the
cost is in the per-node graph (contexts, identity nodes, cache entries, sizes),
which halving the width does not shrink.

**Consequence for optimisation.** Cutting the ~4 measures per render down to 2
would halve the time at every scale — worth a lot — but it would not change the
exponent. Bending the curve means shrinking or flattening the per-node object
graph, not removing calls.

---

## 4. Stress: where the time goes

The module split is the headline, and it is remarkably consistent across all 17
scenarios:

| | share of self time |
|---|---|
| `libswiftCore.dylib` (ARC, generic metadata, dynamic casts, conformances) | **48–64%** |
| `libsystem_malloc.dylib` | **6–18%** |
| TUIkit + Stress's own code | **17–27%** |

**TUIkit spends roughly a fifth of its time in its own logic.** The rest is
Swift runtime overhead: `swift_retain`/`swift_release`/`swift_bridgeObjectRelease`
dominate every leaf profile, followed by `tryCast`,
`_swift_getGenericMetadata`, `swift_conformsToProtocolMaybeInstantiate…` and
`__swift_instantiateConcreteTypeFromMangledName`. This is the same finding as
§3 seen from the other side — a large graph of small reference-counted objects,
walked generically.

Within TUIkit's own ~20%, the hot functions fall into two clean families:

**Family A — cell-width machinery** (`megalist`, `table`, `table-multiline`,
`tables-scroll`, `tables-vstack`, `dashboard`, `kitchensink`, `customlayout`):
`_StringGuts.validateScalarIndex` (0.9–2.2%), `Character.terminalWidth`
(0.9–1.4%), `String.UnicodeScalarView.distance(from:)`,
`String.forEachVisibleANSIRun`. These are the render-dominated, flat-scaling
scenarios; they are paying for cells-not-characters correctness.

**Family B — identity and memo machinery** (`fanout`, `modifiers`, `textwall`,
`anyview`, `churn`, `scrollfollow`, `framedcolumns`, `preferences`):
`IdentityNode.structurallyEqual` (0.6–2.0%), `AnyEquatableBox.==`,
`__RawDictionaryStorage.find`, `__swift_instantiateConcreteTypeFromMangledName`.
These are the measure-heavy, super-linear scenarios.

Measure/render split, inclusive (a scenario can exceed 100% across both because
they nest):

| measure-dominated | | render-dominated | |
|---|---:|---|---:|
| deep | 84% measure | preferences | 90% render |
| modifiers | 57% / 79% | tables-scroll | 98% |
| churn | 57% / 71% | tables-vstack | 95% |
| fanout | 56% / 75% | megalist | 89% |
| table-multiline | 54% | table | 88% |
| anyview | 53% / 74% | framedcolumns | 88% |
| textwall | 41% / 78% | customlayout | 86% |

---

## 5. The Example: per-page cost

150×50, one live session, all 32 pages. `idle%` is CPU with no input at all.

| page | idle % | ms/pass | KB/pass |
|---|---:|---:|---:|
| Forms | **38.8** | n/m | 15.6 |
| Scroll View | **32.0** | 1.57 | 16.0 |
| Lists | **26.0** | 4.58 | 12.4 |
| Picker | **22.4** | n/m | 11.1 |
| Progress & Gauges | 17.5 | 0.57 | 70.1 |
| Theme | 15.0 | **10.23** | 12.8 |
| Image (File) | 11.5 | 3.96 | 67.9 |
| Tab Views | 10.9 | 2.15 | 13.5 |
| Layout System | 9.5 | 6.17 | 14.3 |
| Sliders | 9.5 | 5.14 | 21.7 |
| Mouse | 9.5 | 5.74 | 14.7 |
| Toggles | 8.5 | 6.58 | 12.3 |
| Overlays & Modals | 8.0 | 5.18 | 12.8 |
| Spinners | 6.5 | 0.81 | 13.6 |
| Image (URL) | 6.0 | 2.33 | 10.5 |
| Buttons & Links | 5.5 | 3.71 | 11.8 |
| State Persistence | 5.0 | 3.07 | 10.6 |
| Lifecycle | 5.0 | 1.86 | 10.9 |
| Text Styles | 4.5 | 3.01 | 10.8 |
| Menus | 4.5 | 2.95 | 11.4 |
| Navigation | 4.5 | 2.54 | 16.8 |
| Tables | 3.5 | **7.50** | 18.7 |
| Split View | 3.5 | 2.15 | 16.3 |
| Emoji & SF Symbols | 3.5 | 3.01 | 19.4 |
| Radio Buttons | 3.0 | 2.42 | 10.6 |
| Preferences | 3.0 | 2.80 | 10.8 |
| Empty State | 2.5 | 1.35 | 10.1 |
| Container Views | 2.0 | 2.45 | 12.6 |
| Steppers | 2.0 | 4.05 | 10.5 |
| Colors | 0.0 | **13.75** | 28.9 |
| Text Input | 0.0 | 4.17 | 12.5 |
| Focus & Input | 0.0 | 3.75 | 11.4 |

`n/m` = not measurable: the idle rate swamped the resize delta, so the
subtraction floors at zero. Those two pages' story is the idle column anyway.

**Most expensive single render pass:** Colors (13.8 ms), Theme (10.2 ms),
Tables (7.5 ms), Toggles (6.6 ms), Layout System (6.2 ms). All comfortably
interactive.

**Most bytes per pass:** Progress & Gauges (70 KB) and Image (File) (68 KB) —
both legitimately repaint large coloured areas.

---

## 6. The finding that matters most: idle CPU with nothing changing

Four pages burn a quarter to nearly two-fifths of a core while sitting
completely still. Reconstructing the screen from the pty and diffing
consecutive idle frames:

| page | idle CPU | writes/s | bytes/s | lines that change between idle frames |
|---|---:|---:|---:|---|
| **Forms** | 38.0% | 2.9 | 969 | **none** |
| Scroll View | 28.7% | 19.3 | 8768 | 11 — a Braille spinner and an animated row |
| **Picker** | 25.8% | 11.0 | 3138 | **none** |
| **Lists** | 25.3% | 2.5 | 692 | **none** |

Scroll View is honest: it has visible animation and pays for it.

Forms, Picker and Lists are not. Instrumenting the render loop (temporarily;
reverted) shows the Forms page running **23 full render passes per second at
~16 ms each — 38% of a core — while producing no visible change at all.** The
`FrameDiffWriter` is doing its job: it correctly emits under 1 KB/s, because
there is nothing to emit. The whole cost is upstream of it.

The driver is not a runaway timer. `App.swift:416` gates both timers correctly
on what the frame actually reported (`activity.usesPulse`, `activity.usesCursor`).
It is that **each tick of either timer re-renders the entire page**:

- `PulseTimer` — 100 ms steps → 10 Hz, whenever any focused control breathes.
- `CursorTimer` — 50 ms ticks → 20 Hz, whenever a text cursor blinks.

Coalesced, ~23 Hz. The Forms page has both a text field and a focused control,
so it pays both — and because the cost is a full re-render, **the most complex
page pays the most for animating two cells.** CPU stays flat as the terminal
shrinks (38.6% at 150×50, 35.9% at 110×40), which fits: the cost is in walking
the view tree, and the tree does not shrink with the window.

The project's own stated invariant, from `Tools/Profiling/idle_cpu.py`:

> The render loop should do nothing while nothing changes, so a static screen
> with no input must approach 0% CPU and 0 bytes/s of render output.

The bytes half holds. The CPU half does not.

---

## 7. What the numbers say to do, in order

1. **Stop animating a cursor or a focus ring by re-rendering the page.** Biggest
   measured win available: 25–38% of a core on ordinary pages, permanently,
   for zero visible change. Options worth costing: render the pulse/cursor as a
   compositor-level overlay over a cached frame; or let a view declare that its
   animation touches only its own cells, so the loop can re-render that subtree
   and composite. Either way the invariant to restore is "no visible change ⇒
   no full pass".

2. **Attack per-node object-graph cost, not call count.** §3 shows the calls are
   already linear and the *per-call* cost is what scales — 1.5 µs → 5.4 µs per
   measure between 2 000 and 16 000 siblings. Fewer, smaller, less
   reference-counted objects per node (contexts, identity nodes, cache entries)
   is what bends the curve. §4 agrees from the other direction: ~60% of self
   time is ARC and generic-metadata machinery.

3. **Then cut the measure redundancy.** ~4 `measureChild` calls per
   `renderChild` in `fanout`. Halving that halves the time at every scale — a
   large constant-factor win even though it does not change the exponent.

4. **Leave the flat scenarios alone.** `megalist`, `table`, `table-multiline`,
   `scrollfollow` and `preferences` are flat from 1× to 8×. Windowing works;
   there is nothing here to win.

5. **`Character.terminalWidth` and `_StringGuts.validateScalarIndex` are the
   render-side floor** for every table/list-shaped page (~2–4% of self time
   combined). Worth a memo keyed on the scalar only if something else does not
   pay off first — it is a small, safe, bounded win.

---

## 8. Reproducing this

```bash
swift build -c release --product Stress -Xswiftc -g
.build/arm64-apple-macosx/release/Stress --bench --scenario fanout --scale 8 \
    --iterations 5 --cols 120 --rows 40
```

For the attribution pass see `Tools/Profiling/README.md`; `xctrace record
--launch` works on `Stress` with no PTY, which matters in environments where
debugger attach is denied. Traces are git-ignored and must stay that way —
~15 MB each.

---

## 9. Follow-up: the first two producers converted (2026-08-11)

`AnimatedCellRun` (§6, §7) is now shipped *and* delivering on the pages whose
only animating control is a button. Re-measured with `pagecost.py` against the
same binary pair:

| page | idle% before | idle% after |
|---|---|---|
| Buttons & Links | 5.8 | **0.5** |
| Empty State | 2.2 | **0.5** |
| Text Styles | 4.8 | 4.5 |

Text Styles barely moves, and that is the migration rule reporting honestly:
its focused control is not a button, so a reader still forces the frame.

**The bug that hid in the mechanism.** The replay spliced each run's next frame
into the lines it had patched *last* time, and stored the result back.
Compositing replaces a cell's glyph but keeps the styling around it, so the
colour code of the frame being replaced stayed behind as an empty run — one
dead escape accumulated per run per tick, unbounded. Nothing looked wrong: the
visible text and width never change, so the screen is correct and every
pyte-style reconstruction agrees. Only the byte count showed it (2.7 KB/s →
75 KB/s and climbing). Fixed in `450a0c4a` by always patching the last
*render*'s lines. **Verify a converted producer with CPU *and* a byte/write
count** — CPU alone reads a frozen indicator as a total win, and a correct
screen hides an output leak.

### Where the idle cost is now

Full sweep, 150×50, after the conversions **and** the Stepper fix. Pages that
legitimately animate (Spinners, Progress & Gauges) are not waste; the rest is.

| page | idle% at §5 | now | note |
|---|---|---|---|
| Forms | 41.3 | **0.5** | caret converted + the Stepper bug |
| Scroll View | 26.9 | 27.4 | scrollbar focus pulse — next |
| Picker | 23.9 | 27.4 | scrollbar / menu indicator |
| Progress & Gauges | 19.0 | 20.4 | indeterminate bars (legitimate) |
| Theme | 16.4 | 17.5 | focused **RadioButton** bullet — unconverted producer |
| Tab Views | 11.4 | 12.5 | active **tab chip** background — unconverted producer |
| Mouse | 10.0 | 11.0 | button caps, already converted — see below |
| Lists | 17.9 | **10.0** | |
| Image (File) | 13.0 | **9.0** | |
| Overlays & Modals | 8.5 | 9.5 | |
| Toggles | 7.5 | 8.0 | |
| Sliders | 7.5 | 8.0 | |
| Buttons & Links | 5.8 | **0.5** | |
| Image (URL) | 7.0 | **0.5** | |
| Emoji & SF Symbols | 3.5 | **1.0** | |

**The Stepper bug is the lesson of this round.** It read `pulsePhase`
unconditionally and used it only when focused. That read is volatile — it is
how a frame tells the demand-driven loop it consumed the clock — so one resting
stepper kept the 10 Hz timer alive and re-rendered its whole page forever. It
alone accounted for Forms going 15.9% → 0.3%, and it moved five other pages.

Nothing about it was visible: correct screen, no output, CPU only. It survived
this profile, a bug hunt, and two rounds of conversions. `IdleClockReadTests`
now asserts that resting controls consult no clock, with a complement test that
focused ones still animate — so the class cannot come back silently.

Everything above ~8% that is not a legitimate animation is now a known
producer. Identified with `rawidle.py`, which shows what is actually written:

- **Theme** — the focused radio button's `●`, pulsing at 12 writes/s
  (`RadioButton.swift:515`). A straight conversion.
- **Tab Views** — the active tab chip's background
  (`TabView.activeChipBackground`). Also a straight conversion.
- **Scroll View / Picker / Lists** — a genuinely focused scrollbar.
  `IdleClockReadTests` covers all three and they pass, so this is a real
  animation, not a resting control holding the clock open. Note the scrollbar
  is not a two-cell indicator: the WHOLE BAR pulses, so it wants one run per
  bar row. Measure that rather than assume it — it is still likely a win,
  because the render already rewrites those lines every tick.
- **Mouse** — worth a second look, and the one that does NOT fit. Its animator
  is the bracketed button's caps, which are already converted, and its write
  rate (11/s, 5.5 KB/s) matches replay rather than render. Yet it costs 11%
  against Buttons & Links' 0.5% at the same write rate. Its `ms/pass` is 7.03,
  among the highest, so the likely story is a few genuinely expensive renders
  rather than the animation — but that is a hypothesis, not a measurement.

`TextEditor` is deliberately left on the old path: its caret has multi-line
geometry. It costs exactly what it cost before, which is the migration rule
working.

Remaining producers, by the pages they would quiet: scrollbar +
`scrollIndicatorEmphasis` (Scroll View, Lists, Tables, Picker), Toggle (Forms,
Toggles), List/Table row cursors (Lists, Tables), then RadioButton, Slider, the
grids and the menu renderers.
