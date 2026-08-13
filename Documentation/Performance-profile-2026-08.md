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
| Theme | 16.4 | 17.5 → **0.7** | radio bullet converted, see §10 |
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

## 10. The radio bullet converted (2026-08-11)

Same binary pair, `idlepage.py`, 150×50, the Theme page idle with its radio
group focused:

| | idle CPU | writes/s | bytes/s |
|---|---|---|---|
| before | 16.6% | 10.8 | 2 667 |
| after | **0.7%** | 11.4 | 3 288 |

**24× less CPU at the same write rate.** The rate is the part that matters as
much as the CPU: it says the bullet is still breathing at the same cadence, and
that the loop is splicing cells rather than a view being asked anything. A
frozen indicator would have shown ~0 writes/s (the replay suppresses a tick
that lands on the same picture), which is precisely how a broken conversion
disguises itself as a win. Bytes are up 23%, the known ~12%-per-run dead-escape
overhead the SGR netting will collect.

The shared parts moved to `SelectionEmphasisCycle` first — `colorNow(dim:bright:)`
and `run(_:dim:bright:offsetX:offsetY:)` — because the three rules a converted
producer has to get right (index the cycle modulo its length; emit nothing when
it is still; measure the run in cells, not characters) should exist once.
`ButtonCapCycle` was rebuilt on them in the same pass.

One thing radio buttons need that buttons did not: **the run's row is the
focused item's row**. A group is a list, so a run left at row 0 would repaint
the wrong item — and still look plausible, because *something* would be
pulsing. `FocusIndicatorAnimationTests` asserts the offset moves with the focus
(vertical) and with the item's column (horizontal); the replay-is-identity
check alone does not catch it, since every item's bullet is the same glyph.

Remaining, in the order their pages cost: scrollbar + `scrollIndicatorEmphasis`
(Scroll View 27.4, Picker 27.4, Lists 10.0, Tables), the TabView active chip
(Tab Views 12.5), then Toggle, List/Table row cursors, Slider, the grids and
the menu renderers. And the Mouse page (11.0), which still does not fit the
pattern.

## 11. The tab chip converted — and what it did NOT buy (2026-08-11)

The active tab chip now hands its cells to the run loop like the button caps
and the radio bullet: `ActiveChipCycle`, both strip styles, one run for the
active chip only. It is correct — `FocusIndicatorAnimationTests` pins the run's
row and column in both styles (the bordered chip sits under a row of tab tops
and inside the box's left wall, so an unshifted run would land on chrome), and
a `VolatileReadTracker` probe of the page's controls reports **0 clock reads
and 1 animating run**.

It bought nothing measurable:

| Example page: Tab Views | idle CPU | writes/s |
|---|---|---|
| before | 11.5% | 2.2 |
| after | 12.4% | 2.2 |

**So the chip was never that page's cost.** §9 named it from `rawidle.py` —
what *changes on screen* when the page is idle — and that is a different
question from what *keeps the clock running*. Only one reader anywhere in the
frame is needed to force a full render for everyone; the chip was simply the
one thing whose appearance depended on it visibly.

What the numbers say now:

- **Sliders (7.7%, 10.3 writes/s)** is the honest shape of an unconverted
  producer: a focused Slider reads the phase, the page re-renders ~10×/s, and
  the diff emits every time because the knob's colour really does change.
- **Tab Views (12.4%, 2.2 writes/s)** is the other shape: something re-renders
  the page ~10×/s and almost nothing changes, so the writes are rare and the
  CPU is all view walk. That page's frames are expensive — three `TabView`s,
  each measuring every tab's content — which is why it costs more than Sliders
  while writing five times less.
- The reader is **not** in the page's own controls: rendering the page's shape
  headless (three tab views, toggles, a slider, a picker, an overflowing
  `ScrollView` with focus on a descendant) reports zero reads. It needs the
  live app shell — header, status bar, navigation bar — to reproduce, and that
  is where to look next.

The lesson for the remaining conversions: **`rawidle.py` finds what moves, not
what costs.** Before converting a producer to quiet a page, confirm the page's
clock is actually being held open by *that* producer — a `VolatileReadTracker`
render of the page is the cheap way to ask.

## 12. What Tab Views actually cost: a write during the measure pass (2026-08-12)

§11 said the reader was not in the page's controls and had to be found in the
live app. It was not a reader at all.

`_TabViewCore.tabContentSizes` memoises each tab's measured size in a
`StateBox`, and wrote it back **unconditionally** — from `sizeThatFits`, i.e.
during the MEASURE pass. Writing a `StateBox` invalidates the render cache and
requests another render; that render measures; that measure writes again. **An
idle page containing a tab view re-rendered itself forever**, producing
byte-identical frames.

| Example page: Tab Views | idle CPU | writes/s |
|---|---|---|
| §11 (after the chip conversion) | 12.4% | 2.2 |
| now | **0.5%** | 2.3 |

The write rate is unchanged, so the chip still breathes — through the replay,
which is what it was converted for. The fix is one line plus `Equatable`: store
the memo only when it changed. A memo is not state; re-storing an identical one
must not dirty anything.

**How it was found.** Not by reading code. Three instrumented runs, each
answering one question:

1. Dump a stack whenever `VolatileReadTracker.recordVolatileRead()` fires →
   **nothing**, so no view read the pulse clock.
2. Same for the cursor clock's own flag (`CursorTimer.didReadThisFrame`, which
   is tracked *separately* — that asymmetry is worth remembering) → the only
   hits came from the main menu **while navigating**, not while idle. Gating
   the dump on "more than 5.2 s since launch" was what made that visible; the
   first two runs were reading navigation-time noise.
3. Dump a stack from `AppState.setNeedsRender()` instead → straight to
   `StateBox.value.set` → `RenderCache.invalidateRender` →
   `_TabViewCore.tabContentSizes` → `widestContentWidth` → `sizeThatFits`.

`BodyMutationDiagnostic` already existed for exactly this class and now has a
regression test in `TabViewTests`: render twice, assert the second pass writes
nothing. On the unfixed code it fails naming the culprit —
`identity: "/_TabViewCore<Int>"`.

### The sweep after both fixes

| page | idle% |
|---|---|
| Scroll View | 27.0 |
| Picker | 24.9 |
| Progress & Gauges | 19.9 (legitimate) |
| Mouse | 10.5 |
| Overlays & Modals | 10.4 |
| Layout System | 9.5 |
| Spinners | 9.0 (legitimate) |
| Image (File) | 9.0 |
| Lists | 8.5 |
| Sliders | 7.5 |
| Toggles | 7.0 |
| Text Styles | 4.5 |
| Menus | 3.5 |
| Tables | 3.0 |
| **Tab Views, Theme, Forms, Buttons, Radio, Steppers, Split View, Image (URL), Empty State, everything else** | **0.5 or less** |

Two thirds of the Example is now genuinely idle, and everything left is a named
producer. The four pages with no obvious animator were put under the same
probes, and none of them is a second dirty-state loop — `setNeedsRender` fires
zero times while idle on all four. Each is a focused control reading the
**cursor** clock:

| page | idle% | who reads the clock |
|---|---|---|
| Mouse | 10.5 | `_PickerMenuCore.collapsedLine` — the *closed* picker's focus indicator |
| Image (File) | 9.0 | the same |
| Layout System | 9.5 | `_ToggleCore.indicatorBracketColor` |
| Overlays & Modals | 10.4 | `_MenuItemRow.highlight` |

So the whole remainder is four producers, each shared across many pages:

1. **The scrollbar** — Scroll View 27.0, Picker 24.9, Lists 8.5, Tables. The
   biggest, and the awkward one: the whole bar pulses, so it wants one run per
   bar row. Measure rather than assume.
2. **`_PickerMenuCore.collapsedLine`** — Picker, Mouse, Image (File), and every
   page carrying a picker.
3. **`_ToggleCore.indicatorBracketColor`** — Toggles 7.0, Layout System 9.5,
   Forms, and everywhere else a toggle appears.
4. **`_MenuItemRow.highlight`** — Overlays & Modals 10.4, Menus 3.5.

Progress & Gauges (19.9) and Spinners (9.0) animate legitimately and are not
waste.

## 13. The toggle indicator converted (2026-08-12)

Second of the four producers §12 named. Both built-in indicator styles now
pre-render their whole cycle and leave one `AnimatedCellRun`: the checkbox's
bracket colour (or its self-contained glyph's colour) and the switch's
*track* background, which is what carries focus on the coloured-track styles.

| page | idle CPU before | after | writes/s |
|---|---|---|---|
| Toggles | 7.0% | **0.3%** | 10.6 (unchanged) |
| Layout System | 9.5% | **0.6%** | 10.6 (unchanged) |

The write rate is untouched at both, so the indicators still breathe at the
same cadence — through the replay, with no view walk behind them.

Two things this one needed that the earlier conversions did not:

- **The animated colour is a *background* in the switch's case**, not a
  foreground on a glyph, so it uses the `draw:`-closure form of
  `SelectionEmphasisCycle.run` rather than the glyph form. `IndicatorCycle`
  (private to `_ToggleCore`) holds the cycle plus a `resting` colour, because
  disabled and hovered are separate answers from "focused at phase 0".
- **Two existing tests asserted the old mechanism** — that the drawn line
  differs across `environment.pulsePhase`. That is no longer how it works and
  the tests were rewritten to the new contract: exactly one animating run, more
  than one distinct picture in it, every frame the same cell width, replaying
  this tick's frame changes nothing, and — the point of the original test — the
  OFF cycle's frames are disjoint from the ON cycle's, so a breathing off
  switch can never be mistaken for on.

Remaining: the scrollbar (Scroll View 27.0, Picker 24.9, Lists 8.5, Tables),
`_PickerMenuCore.collapsedLine` (Picker, Mouse 10.5, Image (File) 9.0), and
`_MenuItemRow.highlight` (Overlays & Modals 10.4, Menus 3.5).

## 14. The picker's collapsed control converted (2026-08-12)

Third of the four. A closed `Picker` is a bracketed button in all but name —
`▐ label ⌄ ▌`, with only the caps breathing — so it now shares `ButtonCapCycle`
rather than resolving the phase itself.

| page | idle CPU before | after | writes/s |
|---|---|---|---|
| Mouse | 10.5% | **0.6%** | 10.3 (unchanged) |
| Image (File) | 9.0% | **0.6%** | 10.6 (unchanged) |
| Picker | 24.9% | 24.5% | 10.6 |

Mouse and Image (File) are done. **The Picker page does not move, and that is
the expected answer**: its cost is the long-menu demo's scrollbar, not the
collapsed control — the same distinction §11 drew, arrived at deliberately this
time rather than by surprise.

One test premise needed correcting: a picker draws its *label* before the
control, so its caps do not sit at the row's ends the way a button's do. The
replay-is-identity check catches a wrong offset regardless; the explicit
assertion just had to stop assuming.

Remaining: the **scrollbar** (Scroll View 27.0, Picker 24.5, Lists 8.5, Tables)
and `_MenuItemRow.highlight` (Overlays & Modals 10.4, Menus 3.5).

## 15. A second measure-pass write — and a correction (2026-08-12)

A read-only audit for siblings of the §12 bug (four agents, one prompt each,
no edits) found `_DatePickerCore.renderToBuffer` doing the same thing in a
different disguise:

```swift
selection.wrappedValue = model.clamp(selection.wrappedValue)   // every pass
```

Writing a `Binding` backed by `@State` writes a `StateBox`, which invalidates
the render cache and requests another render. `Date` is not `Equatable`-gated
anywhere on that path, so re-storing an identical date still dirties the tree:
**every frame scheduled the next one, forever.** Fixed by comparing first.

**This corrects §11 and §14.** Both said the Picker page's cost was the
long-menu demo's scrollbar. It was not — that page carries three `DatePicker`s
bound to one `$date`:

| Example page: Picker | idle CPU |
|---|---|
| §14 | 24.5% |
| now | **0.5%** |

I had asserted the scrollbar twice without measuring it, on the strength of the
page's name. The audit was not looking for that and found it anyway.

**The test that nearly wasn't.** The first regression test used
`.constant(date)` and passed against the *unfixed* code — a constant binding's
setter is a no-op, so nothing reaches a `StateBox` and the bug is invisible to
it. The real test builds a `StateBox`-backed binding and asserts
`BodyMutationDiagnostic` reports nothing on the second render; it fails on the
unfixed code naming `<root>`. **A regression test that has not been run against
the unfixed code is a guess.**

### The sweep after this fix

| page | idle% |
|---|---|
| Scroll View | 25.0 |
| Progress & Gauges | 18.5 (legitimate) |
| Lists | 8.5 |
| Overlays & Modals | 8.5 |
| Sliders | 8.0 |
| Spinners | 6.5 (legitimate) |
| Text Styles | 4.5 |
| Menus | 3.5 |
| Tables | 3.0 |
| Steppers | 2.0 |
| **everything else — 22 of 32 pages** | **≤ 1.0** |

Two of the four audit reports are still unworked, and they name more of this:
`scrollIndicatorEmphasis` (ScrollIndicator.swift:47) resolves the clock whenever
its scrollable is *focused*, before the test of whether an indicator will be
drawn at all — four call sites (ScrollView.swift:550, _ListCore.swift:895,
Table.swift:1300 and :1645), which is very likely most of Lists 8.5 and some of
Scroll View 25.0. `FocusSectionModifier.swift:63` and
`NavigationSplitView.swift:282` read `pulsePhase` for a value only a *bordered*
container consumes, so a focus section around plain content reads the clock and
throws it away.

## 16. The scroll-indicator read follows the draw — with no measured win

The audit's second finding: `scrollIndicatorEmphasis` resolves the cursor clock
whenever its scrollable is **focused**, at four call sites, all of them *before*
the test of whether an indicator will be painted (`ScrollView.swift:550`,
`_ListCore.swift:895`, `Table.swift:1300` and `:1645`). Resolving is a clock
read, and a clock read is what tells the demand-driven loop the frame consumed
it — so a focused scrollable that draws no indicator re-renders the whole page
~20 times a second and paints nothing. The `Table.swift:1300` case is the
clearest: when the table shows a *scrollbar*, the emphasis is resolved and then
never used, because both draw sites are behind `!showsBar`.

Each call site now resolves only when an indicator will actually be drawn.

**It bought nothing measurable**, and the reason is honest: on every Example
page that has a focused scrollable, the content overflows and the indicators
*are* drawn, so the read was legitimate there all along.

| page | before | after |
|---|---|---|
| Lists | 8.5% | 8.3% |
| Scroll View | 25.0% | 23.9% |
| Tables | 3.0% | 3.2% |

All three are inside run-to-run noise.

**And the test does not prove it either.** Two attempts failed to build a case
that fails on the unfixed code: a fitting List/ScrollView in the harness does
not report focus (plausibly it is not focusABLE when its content fits —
see #192 — which would make that half of the finding unreachable rather than a
live bug). Rather than ship a green assertion that proves nothing, the test was
deleted. What is kept is the guard itself: it is small, local, and makes the
read follow the draw everywhere, which is the rule the Stepper fix established.

Recorded as a change kept for correctness and consistency, **not** as a
performance win. The remaining Lists 8.3 / Scroll View 23.9 are still
unexplained by anything found so far, and the next step for them is the
`setNeedsRender` stack dump from §12 rather than another conversion on spec.

## 17. The "N more" indicators converted (2026-08-12)

The producer §12's probe named on the Scroll View page —
`scrollIndicatorEmphasis` ← `_ScrollViewCore.applyChrome` — now hands its cells
to the run loop. `renderScrollIndicator` grew a cycle-aware overload returning
`(text, AnimatedCellRun?)`; `applyScrollIndicators` collects one run per
indicator and attaches them to the buffer.

| Example page: Scroll View | idle CPU | writes/s | bytes/s |
|---|---|---|---|
| before | 23.9% | 20.4 | 8 785 |
| after | **16.0%** | 32.0 | 14 512 |

**A third off, not a collapse — and the remainder is explained.** That page
demos scrollbars *as well as* indicators, and the bar is still an unconverted
producer: `ScrollbarColors.focusIndicating` (Scrollbar.swift:147) reads the
cursor clock at `ScrollView+Scrollbars.swift:103` and `:130`. So the page still
renders in full for the bar's sake while the indicators now replay.

The write rate roughly doubled, which is expected and worth stating: the
indicator used to advance only when a full render happened to produce different
bytes, and now it advances on the cursor clock's own 20 Hz. 14.5 KB/s is
noise on a terminal link, but it is a real increase, not a rounding artefact.

Two details this conversion needed:

- **The run covers the arrow and label, not the leading blanks.** An indicator
  is centred by padding; repainting spaces on a clock is bytes for nothing. The
  renderer was split so the static line and every animated frame are laid out by
  one piece of arithmetic (`ScrollIndicatorParts`), which is what keeps the run's
  `offsetX` and the render's padding from drifting apart.
- **The bottom indicator's run is built at row 0** — `renderScrollIndicator`
  does not know which row its caller put it on — so `applyScrollIndicators`
  shifts it to `lines.count - 1`. The replay-is-identity assertion in
  `ScrollbarFocusPulseTests` is what would catch getting that wrong.

The rewritten test replaces one that asserted the *old* mechanism (output varies
with `environment.pulsePhase`). It fails on the unfixed code with
`animatedCells.count → 0 == 2`, checked by reverting the run attachment — the
third time today a mechanism change has invalidated a test that asserted the
implementation rather than the behaviour.

**Next for this page:** the scrollbar itself, which is the last producer. The
scout established its geometry — one run per animated bar row (arrows animate;
thumb cells animate; empty track cells do not), `thumbSpan` is the authority on
which rows those are.

## 18. The scrollbar converted — and the Scroll View page's floor explained

The last producer. `ScrollbarColors.focusIndicating` no longer resolves the
clock: it takes its accent from the cycle (`colorNow`), and the bar's cells go
to the run loop.

**One run per row that actually changes.** The runs are built by rendering the
whole bar once per colour of the cycle and keeping the rows that differ — so the
glyph logic (thumb spans in eighths, partial end cells, arrow reserve) stays
written once and the animation cannot disagree with the render about which cells
are thumb. Empty track cells come out identical at every colour and earn no run,
which is what stops a 40-row bar repainting its whole length 20 times a second to
move a two-cell thumb. The horizontal bar takes one whole-row run instead:
splitting it would need a second cell-diffing routine that could drift from the
renderer, and one row of bytes per tick is the cheaper mistake.

| Example page: Scroll View | idle CPU |
|---|---|
| §17 (indicators converted) | 16.0% |
| now | 17.0% |

**No further win, and the probe says why.** All three drivers report *nothing*
on that page now: no pulse read, no cursor read, no `setNeedsRender`. What is
left is the page's own animated-row demo — a `Spinner` inside a scroll view,
put there deliberately (#222/#235) to prove animation-in-a-cell works. That is
scheduler-driven animation doing exactly what it is for, the same category as
Spinners 6.5 and Progress & Gauges 18.5, and the same answer the probe gave for
Lists in §16.

So the honest accounting for that page is 23.9% → ~17%, all of it from the
indicators, with the bar conversion contributing nothing *measurable here*
because the page never idles. Kept anyway, and not as a consolation: it removes
the **last live-clock read from the scrolling path**, so a focused bar in an app
without a spinner on screen now costs nothing, and `ScrollbarFocusPulseTests`
proves the cells still breathe (it fails on the unfixed code with
`runs → []`).

**The idle-load programme is now complete in the sense that matters**: every
Example page that renders while nothing changes has been found and fixed, and
every page still burning CPU is animating something on purpose. What remains
above 3% — Scroll View 17.0, Progress & Gauges 18.5, Lists 8.4, Spinners 6.5,
Overlays & Modals 8.5, Sliders 8.0 — is legitimate animation plus two
unconverted producers (`_MenuItemRow.highlight`, the Slider's own indicator)
whose pages animate anyway.

## 19. Area 2 — how much of a frame is redundant, and why memoizing it is blocked (2026-08-12)

The second optimisation area asked: if only one part of the page changed, can we
re-layout and re-render only that part? Before designing anything, the question
worth answering is how much that could possibly be worth. This section records
the measurement and the wall the obvious implementation hits.

### The instrument

A temporary `RenderRedundancyProbe` bracketed the render dispatcher
(`renderToBuffer(_:context:)`) and `measureChild`, recording per node: the view
value's raw bytes, the inclusive time, the subtree size, and whether the
produced `FrameBuffer` equalled the previous frame's for that node. Nodes were
keyed by `(identity.path, type, occurrence-within-pass)` — the occurrence index
matters because a `Renderable` adds no child identity, so wrappers and (on the
legacy `TupleView` row path) siblings share one `ViewIdentity`.

"Reusable" counts only **maximal identical subtrees**: walk pre-order, and when
a node's output matched, add its whole subtree and skip past it. That is the
ceiling for any memo — an oracle that knows the answer in advance.

Driven through a PTY at 150×50, tabbing through each page (so frames really
happen; an idle page renders nothing at all since §12).

| page | nodes/frame | reusable nodes | reusable render time |
|---|---|---|---|
| Layout System | 301 | 88% | 68% |
| Buttons & Links | 225 | 86% | 61% |
| Tables | 210 | 85% | 53% |
| Theme | 803 | 95% | 86% |
| Colors | 898 | 100% | 100% |

So the premise is confirmed and then some: while the user tabs between
controls, **85–100% of the render walk reproduces byte-identical output**. The
measure pass is 15–33% of the two passes' combined time, so the render walk is
the larger half and worth attacking first.

### Where the reusable time sits — and why that is the problem

Aggregating the maximal identical roots by view type puts essentially all of it
in *app-level composite views*:

```
ROOT  1.476ms x1 (36 nodes) DemoSection<VStack<TupleView<Pack{Text, Toggle<Text>, …}>>>
ROOT  0.833ms x1 (38 nodes) LazyVStack<ForEach<Range<Int>, Int, …>>
ROOT  0.540ms x1 (25 nodes) DemoSection<HStack<TupleView<Pack{VStack<…>, VStack<…>}>>>
ROOT  0.278ms x1 (13 nodes) DemoAppHeader
```

Not framework primitives — the Example's own `DemoSection`. Self time is spread
thin and sits in the layout cores (`_ScrollViewCore` 1.18ms, `_LayoutCore`
0.94ms, `_VStackCore` 0.56ms — compositing), not in leaves (`Text` × 65 totals
0.18ms). A leaf-level cache would buy nothing; the win is only available at the
composite boundary.

`DemoSection` does not conform to `Equatable`, and neither will most app views,
so `EquatableView` cannot reach any of this. Hence the idea below.

### Raw-byte equality as a conformance-free key

A Swift view tree is stored **inline**, so one `memcmp` of the root struct
covers the whole subtree's inputs. Byte equality is a conservative stand-in for
value equality: it can only report "same" when the values occupy identical
memory — equal inline payloads, or the same heap pointer (for a `String`, the
same storage and therefore the same contents). Rebuilt arrays, interpolated
strings and fresh closure contexts all compare unequal, so it misses; it cannot
invent a hit.

Measured coverage, restricted to subtrees the existing cache gates would allow
storing (no hit-test regions, no overlays):

| page | oracle ceiling | byte-key achievable | false hits |
|---|---|---|---|
| Layout System | 68% | 47% | 0 |
| Buttons & Links | 61% | 16% | 0 |
| Tables | 53% | 9% | 0 |
| Theme | 86% | 19% | 0 |
| Forms | — | 5% | **8** |

The gap between ceiling and achievable is closures and heap-built strings —
which is also why the control-heavy pages score low, and that is *correct*:
their subtrees must run every frame anyway.

### The wall: focus is an untracked dependency

Forms reported **8 false hits** — bytes identical, output different — in
`Button` and its ancestors. A control's appearance depends on the focus manager,
which is neither in the view value nor in `@State`, so nothing invalidates the
cache when focus moves.

An implementation confirmed this is not a probe artefact. An automatic
byte-keyed memo on the composite path, reusing every existing gate (measure
pass, hit regions, overlays, `VolatileReadTracker`, invalidation-during-render,
incomparable environment), builds and passes 4010 of 4015 tests but fails two
real ones:

- `ContextMenuTests` — "The content is told whether its focus stop holds the
  focus" reports `no` where `yes` is required;
- `MenuTests` — the open caret never appears, because the label was served from
  cache.

Root cause: `\.isFocused` (and friends) are published with
`environment.setting(_:to:)`, which **bypasses `noteAppliedEnvironment`** — the
hook that detects an environment change at its application site and clears the
cache below it. Only the `.environment(_:_:)` *modifier* goes through that hook.
So a subtree whose output depends on framework-published environment can be
served stale, and no existing gate notices.

That is a pre-existing hole in `EquatableView` too; it has simply never been hit
because `.equatable()` is opt-in and is not applied to focus-dependent views.
Making the memo automatic exposes it everywhere at once.

**The automatic memo was therefore reverted, not shipped.** It is not merely
unprofitable — it is incorrect.

### What would unblock it

Routing `EnvironmentValues.setting(_:to:)` through the same change-detection as
the `.environment` modifier, so any environment a subtree's output depends on
invalidates it. That is a change on one of the hottest paths in the framework
and needs its own measurement; it is the prerequisite for *any* broader
memoization, including a future subtree re-render, not just for this scheme.

Two things are worth carrying forward regardless:

1. **The ceiling is real and large** (53–86% of render time). Whatever finally
   collects it, the work is there.
2. **Byte-keying works.** Zero false hits on every page whose environment
   dependencies were already tracked; the only failures came from the
   environment hole above, not from the key.

## 20. The environment digest — experiment, and what it settled (2026-08-12)

§19 ended on a blocker: a memo cannot see environment published with
`EnvironmentValues.setting(_:to:)` / direct assignment, because only the
`.environment(_:_:)` modifier routes through `noteAppliedEnvironment`. This
section records the experiment that attacked it. **Nothing from it is
committed** except the `Hashable` conformances it required (915518d1); the
findings are the deliverable.

### The idea: digest the environment instead of watching its writers

Per-site change detection needs every publisher to cooperate, and the
framework publishes by assigning on a copied `EnvironmentValues` in roughly a
hundred places. But every one of those assignments funnels through **one**
place: `EnvironmentValues.subscript<K: EnvironmentKey>`'s setter. So instead of
watching writers, keep a running digest of the contents:

```swift
public private(set) var digest: UInt64 = 0
set {
    if let old = storage[id] { digest ^= slotDigest(id, old) }   // XOR out
    storage[id] = newValue
    digest ^= slotDigest(id, newValue)                            // XOR in
}
```

XOR makes it order-independent (two subtrees reaching the same environment by
different routes agree) and makes re-writing the same value a no-op. The memo
then compares one `UInt64` per lookup instead of walking a dictionary — which
is what the original design rejected fingerprinting for.

### Cost: small, and concentrated where you would expect

Interleaved A/B of two binaries, `Stress --bench`, 800 iterations, mean of two
runs each. Within-build variance measured separately at 0.5–1.7%.

| scenario | base µs | digest µs | delta |
|---|---|---|---|
| megalist | 411.6 | 398.2 | −3.3% |
| deep | 7038.0 | 7510.1 | **+6.7%** |
| fanout | 22306.8 | 22358.3 | +0.2% |
| modifiers | 7035.4 | 7074.6 | +0.6% |
| textwall | 4003.8 | 4051.1 | +1.2% |
| dashboard | 332.0 | 307.2 | −7.5% |
| kitchensink | 820.4 | 803.0 | −2.1% |

Several scenarios came out *faster*, which adding work cannot cause: that is
code-layout noise between two different binaries, and it sets the honest error
bar at about ±5%. The real read is **≤1% on most trees, ~5–7% on `deep`**,
which is the environment-write-heaviest scenario and so exactly where the cost
should land.

### Two traps worth remembering

**`as? AnyObject` succeeds for everything on Apple platforms.** The first
version digested class references by `ObjectIdentifier(value as AnyObject)`.
Structs bridge into a freshly allocated `__SwiftValue` box, so the identifier
differed on every write — the digest would have changed every frame and
nothing would ever have hit, while *looking* like it worked. `type(of: value)
is AnyClass` is the test that means what it says.

**`Optional<AService>` is neither a class nor `Hashable`.** Almost everything
the framework puts in the environment is an optional service — the focus
manager, the state storage, the render cache. Before unwrapping, *every*
environment in the tree was undigestable, so no subtree anywhere was
comparable. This is the failure mode where a scheme reports "safe" by simply
never engaging.

### What had to become Hashable, and what could not

With optionals unwrapped, the undigestable set on three Example pages was:

```
Appearance   Color   StyleCascade   SystemPalette   ToggleCharacterSet
InlineMenuStyle   _MenuItemButtonStyle   RadioGroupPickerStyle
@MainActor @Sendable (KeyEvent) -> ()
```

The first five are in *every* environment, so they had to be hashable or
nothing memoizes — they were all already `Equatable`, and the conformance came
for free except `Appearance` (custom `==`). That is commit 915518d1.

The rest are fine left alone, and this is the pleasing part of the design: a
style existential or a key-handler closure marks its environment undigestable,
which disables memoization **only in the subtree that carries it**. The
mechanism degrades locally instead of globally.

### Result: the digest fixes the focus class

With the digest in the memo's key, `ContextMenuTests` — "the content is told
whether its focus stop holds the focus", the §19 failure that proved the memo
was serving stale pixels — **passes**. The idea works.

Two failures remained, and neither is the environment:

1. Three `TupleViewEquatableTests` assert exact `stats.misses` / `stats.stores`
   counts. The automatic memo shares those counters, so the numbers move. A
   real API question (should the automatic memo have its own counters?), not a
   correctness one.
2. `MenuTests` — the drop-down caret stays closed. This one **passes when the
   test is run alone, with or without the memo**, and only fails in the full
   suite, so it is a test-isolation interaction (cf. `RenderCache` state shared
   between tests) that the memo makes visible, not a rendering defect.

Worth noting what `Menu` showed on the way: `MenuPopupState` is a **class**
held in a `StateBox`, so `state.isOpen = true` mutates the object and
`StateBox.didSet` never fires — no invalidation is enqueued at all. Any memo
has to treat in-place mutation of persisted reference state as a third
untracked-dependency channel alongside focus and environment. Today the
hit-region gate covers the controls that do it, but that is a coincidence of
those controls being clickable, not a guarantee.

### Where this leaves it

The digest is the right shape and is affordable. The remaining work before an
automatic memo could ship is bounded and now known: separate memo counters,
the test-isolation interaction, and a decision on reference-typed view state.
That is a much smaller list than §19's, and none of it is architectural.

## 21. Landing the memo: three gates, and the one that does not close (2026-08-12)

§20 left a short list before an automatic memo could ship. Working it down
resolved everything on it and then found the actual blocker, which was not on
it. Reverted again; here is the chain, because each step failed in a way worth
recognising.

**Separate counters — done, and it fixed two of the three items.** The
automatic memo now has its own `autoStats` rather than sharing `stats`, whose
existing meaning ("how the *opt-in* memos are doing") several tests assert
exact figures on. With that, the full suite passed 4015/4015 — three runs, to
be sure the order-dependent `MenuTests` failure was really gone.

**And a green suite meant nothing.** Instrumenting the live app showed
`entries 0, hits 0, misses 0` on every page: the memo was never running at
all. `hasUndigestableValue` is sticky and inherited, and the app installs its
default styles on the **root** environment — so one unhashable style
existential there disabled memoization for the entire tree. Every test passed
because nothing was memoized. This is the failure mode the whole scheme is
most prone to, and it is invisible to a test suite; only a hit-rate
measurement finds it.

**So make everything digestable.** Values that are neither `Hashable` nor a
class fall back to hashing their raw bytes — conservative in the same way the
view-value key is, and local in effect. The flag disappears entirely. Now the
memo ran: 350–945 lookups a frame.

**Still zero hits, and zero entries.** Gate counters showed stores *were*
happening — ~52 a frame, with only hit-test regions declining any real number
(2106 declined vs 4229 stored, cumulative). The entries were being collected
by `removeInactive()` at the end of the very pass that stored them: only
`EquatableView` and `_MemoizedRow` call `cache.markActive`, and the automatic
memo did not. One line.

**Entries then persisted — 11 to 52 a page — and hits stayed at zero.** That
is the real blocker, and it is the direct consequence of the previous fix.
Hashing raw bytes gives a *stable* digest only for values whose bytes are
stable. A closure's context pointer and a heap-boxed existential's payload are
freshly allocated on every write, so the environment digest changes every
frame, and every lookup misses. Removing the poison flag converted "disabled
everywhere" into "misses everywhere" — the same nil result by a different
route.

### What that actually settles

The three dependency channels are now all handled or understood, and none of
them is the problem:

- **view value** — raw bytes, zero false hits measured (§19);
- **environment** — the digest, which demonstrably fixes the focus class (§20);
- **per-frame registries** — the existing region/overlay/volatile gates, which
  the counters show are doing their job and declining only what they should.

What is left is narrower than any of those: **an environment slot needs a
digest that is stable across frames**, and for a closure or a boxed existential
there is no such thing without deciding that its *type* is the identity. That
is a real correctness compromise (two instances of one style type with
different stored properties would collide), not an implementation detail — so
it wants a decision, not another attempt.

Three options, in order of how much they give up:

1. **Digest style existentials by type identity**, and require framework style
   types to be stateless. Cheap, and true of every built-in style today, but a
   third-party style with stored properties would be silently wrong.
2. **Make the style protocols refine `Hashable`.** Correct, and synthesis makes
   it free for most conformers, but it is a public API change and constrains
   every user-defined style.
3. **Keep a per-slot "unstable" set** rather than one sticky flag, and let the
   memo ignore slots a subtree provably never read. That needs environment
   *read* tracking, which does not exist and is not cheap.

Option 2 is the honest one and is the only one with no silent-wrongness mode.
It is also the one that cannot be decided inside a performance pass.

## 22. The miss-reason diagnostic, and what it eliminated (2026-08-12)

§21 ended with the memo storing buffers and hitting none of them, and four
rounds of "found a cause, fixed it, number didn't move". This round replaced
guessing with a five-line instrument, which is what should have happened
first: on a miss, record **which component of the key differed**.

```swift
guard let entry = autoEntries[key] else { autoMisses.noEntry += 1; return nil }
guard entry.contextWidth == …, entry.contextHeight == … else { autoMisses.size += 1; … }
guard entry.environmentDigest == digest else { autoMisses.digest += 1; … }
guard entry.bytes == bytes else { autoMisses.bytes += 1; … }
```

A miss that is `noEntry` indicts the **key**; the others indict the **payload**.
That one distinction did more than the previous four rounds combined.

### First reading: the payload was never the problem

```
Layout System:  noEntry 19   size 0   digest 52   bytes 0
```

**`bytes 0`** — the view values were byte-identical every frame, all 52 of
them. The conformance-free key from §19 works exactly as measured. Every
theory about localised strings or rebuilt view trees was wrong.

**`digest 52`** — every entry failed on the environment. And the cause was
sitting in `ServiceEnvironment`: `FrameNowNanosKey`, the current frame's
monotonic timestamp, lives *in the environment*. It differs on every frame by
definition, so every subtree below it digested differently, forever. Same for
`PulsePhaseKey` and `CursorTimerKey`.

The fix is principled rather than a special case: those are **clocks**, and
reading one is already recorded by `VolatileReadTracker`, which makes the
reading subtree decline caching. The tracker is the mechanism for time; the
digest must not also encode it. Marking them `InfrastructureEnvironmentKey`
took digest misses from 52 to 0.

(The same marker fixed a self-inflicted instance: the memo installs a fresh
`VolatileReadTracker` into the environment on every miss. It is a class, so it
digested by identity — a new one each frame changed the digest of everything
below. The memo was measuring its own instrumentation. `EquatableView` does
the same thing and never noticed, because its key ignores the environment.)

### Second reading: the key, and two suspects eliminated

With the payload clean, every remaining miss is `noEntry` — the lookup does
not find what the previous frame stored. Two candidates were ruled out by
measurement rather than argument, on the same page and the same frames:

```
AUTO  — hits: 0, … entries: 32 | miss: noEntry 10 size 0 digest 7 bytes 0
FRAME — hits: 6, misses: 0, … subtreeClears: 0, entries: 2, hit rate: 100%
```

- **`subtreeClears: 0`** — nothing is being evicted by invalidation. The
  entries survive; the lookups do not find them.
- **`hit rate: 100%`** on the opt-in memo, on the same page, in the same
  frames — so `ViewIdentity` is stable across frames and hashes correctly.
  `EquatableView` keys on identity alone and hits every time.

That leaves `occurrence` — the component this design *added* to the key — as
the remaining suspect, plus a small residual digest churn (7 of 17 lookups).

`occurrence` exists to separate sibling nodes that share one `ViewIdentity`,
since a `Renderable` adds no child identity. It is positional, so it was moved
to reset per *walk* rather than per pass (a frame walks the scene more than
once — header height discovery, then correction) exactly as
`RenderLoop.beginSceneRender()` already documents for the mouse dispatcher's
positional handler ids. That fix was necessary and reduced `noEntry`
substantially, but did not eliminate it.

### Where this leaves the design

Every dependency channel is now demonstrably handled:

| channel | mechanism | evidence |
|---|---|---|
| view value | raw bytes | `bytes 0` — never a mismatch, never a false hit |
| environment | digest, clocks excluded | `digest 52 → 0` |
| registries | region/overlay/volatile gates | gate counters: only regions decline, 2106 vs 4229 |
| eviction | `markActive` + invalidation | `subtreeClears 0`; entries persist |

The one unresolved component is the one that is *not* required by the theory:
`EquatableView` gets a 100% hit rate with **identity alone**. The obvious next
move is therefore to drop `occurrence` from the key and pay for sibling
collisions differently — the byte comparison already rejects a wrong sibling
(two different views at one identity have different bytes), so the occurrence
number may be redundant with the payload check it sits in front of. That is a
one-line experiment with a measurement attached, and it is where the next
round should start.

## 23. First hits — and the two things that cost the rest (2026-08-12)

§22's instrument pointed at `occurrence`, the one key component this design
added. Removing it was right but insufficient; carrying on from there produced
**the first non-zero hit rate**, and named the two causes that still hold the
number down.

### `occurrence` was never needed

Dropped entirely: the key is now `(identity, viewType)`. Two same-typed
siblings sharing one identity overwrite each other and then both miss — the
stored bytes belong to the other sibling and are rejected — which costs a
re-render and never a wrong buffer. `EquatableView` keys on identity alone and
reaches 100%, which was the clue.

### Cause 1: the digest slot nobody would guess

Extending the miss diagnostic to name *which environment key* changed turned a
week of hypotheses into one line of output:

```
DIGEST changed=["SynthesizeKeyEventKey"] gone=[]
```

`synthesizeKeyEvent` is the closure that routes a synthesised `KeyEvent`
through the input chain. It is wired **once** at start-up, so it ought to
digest identically every frame — and it did not, for a reason worth recording:

**Hashing an `Any`'s raw bytes hashes uninitialised padding.** A closure is two
words; `Any`'s inline buffer is three. The leftover word is whatever was on the
stack, so two copies of the *same* closure hash differently. The §21 "hash a
function's bytes at the leaf" rule was wrong for exactly this reason, and wrong
invisibly — it produced a digest that churned rather than an error.

Functions are therefore reported unstable again, and the key itself is marked
`InfrastructureEnvironmentKey`: it is a *dispatch service*, not a rendering
input. Nothing renders differently because of which synthesiser is installed.

### Cause 2: infrastructure in the environment, in general

That makes four environment slots that must be excluded, and they form a
category rather than a list of exceptions:

| slot | why it can never digest stably |
|---|---|
| `frameNowNanos` | it *is* the clock — differs every frame by definition |
| `pulsePhase` | derived from the clock |
| `cursorTimer` | the blink clock |
| `volatileReadTracker` | a fresh instance the memo itself installs per miss |
| `synthesizeKeyEvent` | a closure; no stable digest exists for one |

The first three are already covered by `VolatileReadTracker`: *reading* one is
recorded, and the reading subtree declines caching. The tracker is the
mechanism for time, and the digest must not duplicate it. The fourth is the
memo's own instrumentation — it was measuring itself. The fifth is a service.

### The result

With all five excluded, the memo hits for the first time:

| page | entries | hits / 5 frames | hit rate |
|---|---|---|---|
| Container Views | 32 | 5 | 8% |
| Text Styles | 45 | 5 | 2% |
| Layout System | 52 | 5 | 1% |
| Theme | 41 | 5 | 1% |
| Tables | 30 | 2 | 1% |

**Proof of life, not a win.** One hit per frame against 12–190 lookups is far
below the point where the memo pays for itself, so it is reverted again. But
the failure mode has changed shape: it is no longer "nothing works and the
cause is unknown", it is "the mechanism works and something is still
invalidating most candidates each frame". The next diagnostic is the same one
that worked twice here — extend the per-miss reason breakdown to the *storing*
nodes and see which of `noEntry` / `digest` / `bytes` dominates now that the
known offenders are gone.

### The general lesson, recorded because it cost five rounds

Every failure in §20–§23 was a **silent no-op**, never an error:

- a sticky flag disabled the memo tree-wide, and the whole suite passed;
- `as? AnyObject` succeeded for every value and hashed a fresh box each time;
- `Optional<Service>` made every environment undigestable;
- the memo's own tracker changed the digest of everything below it;
- byte-hashing an existential hashed uninitialised padding.

None of these can be caught by an assertion, because in every case the code
does something reasonable — it just never engages. **The only test that
catches them is a live hit-rate measurement**, and it should be the first
thing built for any cache, before the cache itself.

## 24. The mailbox in the environment — 1% to 39% (2026-08-12)

§23 ended with the memo hitting once per frame. Extending the miss breakdown
one more step found why, and the cause turned out to be a defect in its own
right rather than anything about caching.

### The breakdown that localised it

Two additions to the instrument: split `noEntry` into **evicted** (stored last
frame, gone now) versus **never-stored** (gated out and never a candidate),
and count what `removeInactive()` collects.

```
Container Views: hits 1  | noEntry 10 (evicted 0, never-stored 10)
                         | size 0  digest 2  bytes 0  | collected 0
Text Styles:     hits 1  | noEntry 10 (evicted 0, never-stored 10)
                         | size 0  digest 40 bytes 0  | collected 0
```

`evicted 0` and `collected 0` cleared the entire eviction theory: nothing was
being lost. `never-stored 10` is a constant — the outermost nodes, correctly
declined because their buffers carry the page's hit-test regions. And every
remaining miss was `digest`, on exactly the population that does store.

Naming the offending slot took one more line of output:

```
AUTOCULPRIT ScrollContentWindowKey=40
```

### The defect

`ScrollContentWindow` travels down the environment carrying the visible slice.
It also carries `reply` — the Stage-6 channel a windowed stack reports its
rendered slice back through — and that slot is deliberately reference-typed:

```swift
let contentReply = ScrollContentReply()          // fresh, every render pass
measureContext.environment.scrollContentWindow = ScrollContentWindow(
    offset: verticalScrollOffset, viewportHeight: viewportHeight, …,
    reply: contentReply, …)
```

`ScrollContentReply` compares and hashes by `ObjectIdentifier`. Synthesised
`Hashable` on the enclosing struct folded that in — so two windows describing
the **same** visible slice compared unequal and hashed differently on every
frame, because the mailbox was new each time.

Every Example page sits inside a `ScrollView`, so this value is in the
environment of essentially every view, and a value that changes every frame
propagates to everything below it.

The fix writes out `==` and `hash(into:)` to exclude `reply`. A window is
identified by what it *describes* — offset, viewport, whose content, edge
inset, pending seek — not by which mailbox is attached. Committed on its own
merits (c0b22635) with a regression test that fails on the unfixed code:
equal windows compare unequal and hash differently.

**This was never really a caching bug.** Any code comparing or hashing a
window — a cache key, a change check, a `Set` — was already being told the
slice had changed on every frame when it had not.

### The measurement

| page | before | after | remaining miss reason |
|---|---|---|---|
| Text Styles | 1 hit/frame | **13 hit/frame (39%)** | 10 never-stored, 10 bytes |
| Container Views | 1 | **2 (17%)** | 10 never-stored |
| Layout System | 1 | ~9 | 47 digest (a second window instance) |
| Tables | ~0.4 | ~1 | 30 evicted, 28 never-stored |

Still not a shippable memo — 39% on the best page, with the per-node cost of
asking not yet measured against it — so the memo and digest are reverted
again. But the shape of the remaining work is now concrete and small:

1. **Layout System still reports `ScrollContentWindowKey`.** That page nests a
   second scroll view; either another field of the window varies legitimately
   there, or the two walks of a frame publish different windows. The same
   culprit diagnostic will say which.
2. **Text Styles now reports `bytes 10`** — the first time the view-value key
   has *ever* mismatched. Ten nodes on that page rebuild their view value
   differently each frame; worth knowing which, since §19 measured zero.
3. **Tables reports `evicted 30`** — the first real eviction seen, so that page
   does invalidate its own entries. Expected for a page with live state, but
   worth confirming it is the demo's doing and not the memo's.

## 25. Why the byte key cannot work — and a correction (2026-08-12)

A 24-agent read-only analysis (four lenses — environment writes, available
size, view-value bytes, entry lifetime — each finding adversarially verified)
settled the automatic memo's viability. The answer is that **the byte-keyed
design is structurally wrong**, and two of this document's earlier claims need
correcting.

### Correction: `bytes 0` was never a measurement

§22–§24 read `bytes 0` off the memo's miss breakdown and concluded "the view
values are byte-identical every frame". That was wrong. The instrument is a
**short-circuiting guard chain** — `noEntry`, then `size`, then `digest`, then
`bytes` — so a node that failed the digest check *never reached* the byte
comparison. `bytes 0` meant "nothing got that far", not "nothing differed".
§24's "the first time the view-value key has ever mismatched" is the same
error: earlier readings could not have mismatched.

§19's byte measurement stands — that came from the redundancy probe, which
compared every node's bytes independently and cross-tabulated against output
identity (67% of nodes byte-stable, zero false hits). But it measured *all*
nodes, not the storing population, and the storing population is gated to
subtrees that turn out to be the byte-stable minority.

### Why the bytes cannot be stable, in general

Every one of these allocates fresh heap storage per frame, and its pointer sits
in the view struct's inline bytes:

| source | what is fresh each frame |
|---|---|
| `@State` | a `StateBacking` class per construction |
| `@Environment` | an `EnvironmentBox` class per property |
| `$state` (`Binding`) | two closure contexts, per access |
| `ForEach` / `for`-in in a ViewBuilder | `ViewArray`'s `[Element]` buffer |
| an array literal passed as a view property | the buffer (contents stable, pointer not) |
| `any ButtonStyle` and friends | the existential box |

And three sources of undefined bytes that `memcmp` reads but Swift never
promises to initialise: inter-field **struct padding**, **enum/Optional payload
slack** (`ConditionalView` is sized to the larger branch), and the unused words
of an **existential's inline buffer** — the last already proved in §23.

**The amplifier:** a composite's bytes include its *entire inline subtree*, so
one unstable word anywhere below poisons every ancestor. That is why the memo
stored only 7–52 nodes a page: those are the subtrees containing none of the
above.

### The contrast that names the fix

`EquatableView` keys the same cache by `Equatable.==`, which by construction
ignores heap identity, padding and closure contexts — and it reaches a **100%
hit rate** on the same pages where the byte key reaches 1–39%. The key was
never the hard part; using bytes as a stand-in for equality was the mistake.

### And a second, independent design error

`AutoKey` is `(identity, type)` and carries **no size**, while two-pass layout
structurally offers each child *two* different extents every frame — its
parent's whole remaining extent while measuring, its allocated extent while
rendering. `storeAuto` writes both into one dictionary slot, so each clobbers
the other and both lookups miss. This is precisely the failure mode
`_MemoizedRow` documents at length and guards against by refusing to store
measure-pass buffers — a guard the automatic memo copied for `isMeasuring` but
not for the size, and `isMeasuring` is set only on the `Layoutable` branch of
`measureChild`, so it does not identify the walk.

Compounding it, several containers render the *same* node twice per frame as
real, non-measuring renders at different sizes: `_ContainerViewCore`'s footer
(full inner width, then `innerWidth - footerPadding`), `MenuPopover`'s rows
(into a `max(availableHeight * 64, 4096)` canvas, then for real), `ViewThatFits`
(a 1,000,000² probe, then the real size), and the scrollbar reservation's
monotonic fixpoint (W, then W−1, then H−1).

### Other confirmed per-frame churn, for whoever returns to this

- **`focusIndicatorColor` launders the excluded `pulsePhase` back in.** The
  active focus section lerps a `Color` from the pulse phase and writes it to a
  *non-infrastructure* key, so excluding `pulsePhase` itself buys nothing. It
  stops at the first bordered `ContainerView` (which nils it), so it reaches
  everything only where a section wraps unbordered content — the Example's
  Focus page exactly. Already open as task #519 / §15.
- **Freshly allocated classes written into the environment every frame:**
  `isolatedForBackground()` (a new `FocusManager` + `KeyEventDispatcher` per
  call, once per frame under `NavigationStack`), `.focused(_:equals:)`'s
  `AssignedFocusID`, `.refreshable`'s `RefreshAction`/`ActionBox`,
  `MenuPopover`'s `MenuRowSink`, and `StackFocusReach`'s scratch `FocusManager`.
  Each digests by identity and so changes every frame.
- **Closure-carrying environment values** (`DismissAction`, `onSubmit`) have no
  frame-stable digest at all, so they mark their whole subtree unmemoizable.

Two useful negative results: **`ViewIdentity` is fully structural and stable
across frames** — never a source of misses, and can be excluded from future
investigation. And **`L()` is not a suspect**: it returns the `String` stored in
the cached dictionary, so its two words are bit-identical every frame.

### Verdict

Area 2 stops here. An automatic render memo needs a key that compares *values*,
not memory — which is `Equatable`, which is what the opt-in memo already uses
and which reaches 100%. Making that automatic means either app-side
`.equatable()` (SwiftUI's own answer) or a synthesised structural comparator
that ignores heap identity; the byte shortcut cannot be repaired, because the
instability is in the language's representation, not in TUIkit.

---

## 26. Area 3 — the super-linear band was one copying accumulator (2026-08-12)

Area 3's brief was "improve the time complexity of the superlinear algorithms,
ideally down to O(N) or better". The 17-scenario scale sweep had already
isolated the band and, importantly, ruled out the obvious causes:

| scenario | exponent before | per 2x scale |
|---|---|---|
| `anyview` | 1.54 | 2.5-3.1x |
| `textwall` | 1.64 | 2.9-3.4x |
| `fanout` | 1.74 | 3.0-3.6x |
| `modifiers` | 1.81 | 3.3-3.7x |
| `deep` | 1.82 | (depth, not breadth) |

Three hypotheses were dead on arrival: **not** the ScrollView natural-extent
ladder (its rung count is constant across 4->8, where time still rises 3.6x);
**not** text volume (halving the terminal columns moved `textwall` 0.3%); and
**not** call-count growth — `measureChild` calls are exactly linear in the child
count (14.4k / 28.8k / 75.2k / 150.4k). What did grow was the cost *per call*:
1.49 -> 2.18 -> 2.96 -> 5.35 microseconds, with an unchanged instruction mix.
The self-time split said the same thing from another angle — 48-64% in
libswiftCore (ARC, generic metadata, `tryCast`), 6-18% in malloc, only 17-27%
in TUIkit's own code.

Same work, more expensive each time, dominated by retain/release and
allocation. That is not an algorithm doing more; it is an array being copied.

### The accumulator

`FrameBuffer.appendVertically` — the operation every stack calls once per child:

```swift
var combined = lines               // `lines` is `_read { yield storage }`,
combined.append(contentsOf: other.lines)   // so this copies, not appends
self = FrameBuffer(lines: combined, ...)
```

`combined` held a second reference to `storage`, so the array was no longer
uniquely referenced and `append` copied the whole accumulated buffer —
retaining every `String` row on the way. Four sibling accumulators in the same
function did it too: `lineWidths` by the same copy-then-append, and `overlays` /
`hitTestRegions` / `animatedCells` through `a + b`, which always allocates and
copies both sides. `appendHorizontally` carried the same three concatenations.

A stack appends N children into one buffer, so each container was O(n²) in its
child count, with an O(n²) count of ARC retains on top. Timing a bare
accumulation of single-line children:

| n | before | ratio | after | ratio |
|---|---|---|---|---|
| 500 | 0.534 ms | | 0.008 ms | |
| 1000 | 1.793 ms | 3.36 | 0.016 ms | 2.04 |
| 2000 | 6.114 ms | 3.41 | 0.030 ms | 1.87 |
| 4000 | 25.806 ms | 4.22 | 0.053 ms | 1.73 |
| 8000 | 103.499 ms | 4.01 | 0.104 ms | 1.98 |

4x per doubling is the quadratic; 2x per doubling is linear.

### Effect on the band

Exponents recomputed as log2(t8/t1)/3, and per-frame microseconds from an
interleaved A/B of two prebuilt binaries:

| scenario | exponent | scale 1 | scale 4 |
|---|---|---|---|
| `fanout` | 1.74 -> **1.17** | -50.4% | -73.5% |
| `modifiers` | 1.81 -> **1.12** | -57.2% | -81.0% |
| `textwall` | 1.64 -> **1.09** | -41.8% | -68.6% |
| `anyview` | 1.54 -> **1.11** | -34.1% | -54.8% |
| `churn` | — | -13.9% | -27.9% |

Every scenario's frame checksum is unchanged at both scales, so the rendered
output is byte-identical. The windowed scenarios (`megalist`, `scrollfollow`,
`dashboard`, `table`) are flat; a 25-iteration sample had shown a spurious +19%
on `megalist` that vanished at 400 iterations.

`deep` is unmoved at -2%, exactly as expected — its quadratic is in the
re-measure ladder, and remains the open item (see §Q1 / the `measure-memo`
branch: it needs a layout tree, not a patch).

### What generalises

The signature to look for is **cost per call growing while the call count stays
linear and the instruction mix stays flat**. That is never "the algorithm got
harder"; it is a buffer being reallocated and recopied underneath. In Swift the
specific trap is that a `_read`-yielded property assigned to a local becomes a
*second reference*, so the next `append` silently deep-copies — the code reads
like an amortised append and behaves like a full copy. `a + b` on arrays is the
same defect written more honestly.

This was the third O(n²) compositing bug in this file's neighbourhood
(`insertOverlay` rescanning the line per child, `ansiAwareSlice`, now this), so
the accumulators are worth auditing as a class rather than one at a time.

Guarded by `FrameBufferCombineScalingTests`, which asserts the *shape* of the
growth (under 20x for 8x the children) rather than an absolute speed; both
guards fail on the unfixed code, at 31.7x and 45.9x.

---

## 27. Area 3 — the last quadratic, and the option the earlier attempt missed (2026-08-12)

After §26 the landscape has exactly one super-linear scenario left. Exponents
(log2(t8/t1)/3) for all 17, measured on the fixed build:

| band | scenarios |
|---|---|
| flat (≤0.15) | `megalist` -0.07, `table` -0.06, `table-multiline` -0.02, `scrollfollow` -0.04, `preferences` 0.08, `kitchensink` 0.15 |
| sub-linear (0.70–0.98) | `framedcolumns` 0.70, `tables-vstack` 0.78, `dashboard` 0.80, `churn` 0.94, `customlayout` 0.97, `tables-scroll` 0.98 |
| linear (1.09–1.16) | `modifiers` 1.09, `textwall` 1.12, `anyview` 1.15, `fanout` 1.16 |
| **super-linear** | **`deep` 1.80** |

### Why the earlier memo failed, and what it missed

`deep`'s quadratic is structural: two-pass layout has level i's PASS 1 measure
everything below i, then the render descends to i+1 whose PASS 1 measures
everything below i+1. Measure *roots* are linear in depth (~2 per level); total
measures are quadratic.

Branch `measure-memo` (edda12ae) built a per-pass memo keyed by (identity, view
type, proposal, extent) and rejected it: `EquatableViewMeasureMemoTests`'
`valueGating` measures two different view values at one identity in one pass,
and the memo served the first one's size for the second. Its own conclusion was
that the fix needed a reflection digest ("costs what the memo saves") or a
layout tree.

The option it skipped is the view's **raw bytes** — `withUnsafeBytes(of: view)`
into a `Hasher`. No reflection, no conformance requirement, and a view struct is
a handful of words.

The obvious objection is §25: the byte key was proved unusable. But §25's
failure was specifically about **cross-frame** stability — `@State`,
`@Environment`, `Binding` and existential boxes embed a freshly-allocated
pointer every frame, so nothing ever matched. That does not apply *within* one
pass, where the same value copied down the tree has byte-identical storage,
pointers included. And the failure mode is asymmetric: undefined padding makes a
lookup **miss** and re-measure, which is correct but unsaved. A false *hit*
would need a 64-bit collision among the few hundred entries a pass stores.

### Result

| scale | before | after | hit rate |
|---|---|---|---|
| 1 | 7 275 µs | 2 278 µs (−68.7%) | 25.2% |
| 2 | 22 083 µs | 3 705 µs (−83.2%) | 31.4% |
| 4 | 80 488 µs | 8 882 µs (−89.0%) | 36.2% |
| 8 | 319 219 µs | 29 474 µs (−90.8%) | 39.2% |

Exponent **1.80 → 1.23**. The win growing with depth, and the hit rate climbing
with it, is the quadratic coming out rather than a constant being shaved.

Any nesting pays some of this, so it is not confined to `deep`: `anyview`
−34.8%, `modifiers` −25.9%, `textwall` −25.6%, `framedcolumns` −24.7%, `fanout`
−23.5%, `preferences` −22.9%, `customlayout` −21.1%, `table` −16.1%. Two
scenarios regress where the memo mostly misses and still pays the hash: `churn`
+8.8%, `dashboard` +6.3%. All 34 scenario/scale checksums are unchanged.

### The harness bug this exposed, which is the real lesson

`measureChild` consults the memo only when a `VolatileReadTracker` is installed
— that tracker is the gate deciding whether a measurement is safe to remember.
Only `RenderLoop` installs one. `Headless` builds its own environment and did
not, so **in the bench the memo was unreachable code that still cost a call**:
it measured as a flat ~10% regression across every scale, with the curve
untouched, and looked exactly like "the idea does not work".

That is §25's lesson recurring in a new place: the failure was a silent no-op,
and only a hit-rate count distinguished "engaged and did not help" from "never
engaged". The counters are now permanent, in `logFrameStats`. A bench harness
that does not reproduce the app's environment will keep producing confident
measurements of nothing.

---

## 28. Area 4 — why the memo's two regressions resist the obvious fixes (2026-08-12)

§27 left `churn` +8.8% and `dashboard` +6.3% against wins of 16–90% elsewhere.
The first Area-4 item was to remove them. Both obvious gates were tried and
both are **rejected on measurement**; do not retry them without new evidence.

Per-scenario hit rates, now printed by `--bench` unconditionally:

| scenario | rate | | scenario | rate |
|---|---|---|---|---|
| `textwall` | 79.6% | | `anyview` | 1.4% |
| `fanout` | 75.3% | | `kitchensink` | 4.8% |
| `modifiers` | 48.7% | | `dashboard` | 2.6% |
| `deep` | 39.9% | | `churn` | 0.2% |

### Gate 1 — on hit rate. Rejected.

The tempting design is to suppress the memo on frames whose previous hit rate
was low. It is wrong: **`anyview` gains 34.8% on a 1.4% hit rate**. Its 638
hits per 40 frames each skip an entire subtree, so a rate-based gate would
switch the memo off precisely where it pays best. Hit *count* is not benefit;
work *skipped* is.

### Gate 2 — on subtree cost. Also rejected.

So price each measurement: count nested `measureChild` calls across it (one
increment on the hot path, one subtraction per store) and refuse to store
anything cheap, on the theory that a leaf measured once and never revisited
pays a hash and a dictionary insert for nothing — `churn` performs ~32 000
lookups a frame for 74 hits, i.e. ~32 000 inserts never read.

At a threshold of 8 nested measures, **`fanout` went from 75.3% hits to 0.0%**.
Its rows are an `HStack` of four `Text`s — subtree cost ~5 — so the gate
excluded exactly the entries its 75% hit rate was built from. The premise
("wins come from skipping large subtrees") was false: `fanout` wins through
many cheap hits, `anyview` through few expensive ones, and a single cost
threshold cannot serve both.

At a threshold of 2 (excluding only true leaves) the trade is real but still a
trade — measured best-of-3 at 200 iterations against the ungated memo:

| scenario | change |
|---|---|
| `churn` s4 | **−15.1%** |
| `dashboard` s4 | −3.8% |
| `anyview` s4 | −2.2% |
| `deep` s1 | −1.4% |
| `textwall` s1 | −0.9% |
| `fanout` s1 | **+8.8%** |

That fixes the two regressions by creating a new one on a shape that matters
more (wide non-lazy lists are ordinary; "every view changes every frame" is
synthetic). Reverted.

### What the two failures say

A stored entry pays iff the node is **revisited within the pass**, and that is
not predictable at store time from anything local — not from the hit rate the
cache is currently achieving, and not from what the measurement cost. Any
future attempt needs a signal about *revisiting*, which is structural: the
repeat visits come from the two-pass ladder (a measure nested inside another
measure is the reusable case), not from any property of the view itself.

The regressions stand. They are the price of a mechanism worth 16–90% on nine
other scenarios, and the hit-rate counters are now permanent so the next
attempt starts from data rather than from a plausible story.

---

## 29. Area 4 — the width scan stops segmenting text (2026-08-12)

Re-profiling after Area 3 put a single family at the top of the trace. On
`kitchensink` at scale 4 (8 000 iterations, 10 239 samples, 4907 ms on-CPU),
Unicode grapheme segmentation was **14.6% of all CPU**:

| ms | % | self time — leaf frames |
|---|---|---|
| 231 | 4.7 | `_swift_stdlib_getGraphemeBreakProperty` |
| 227 | 4.6 | `Unicode._GraphemeBreakProperty.init(from:)` |
| 112 | 2.3 | `_GraphemeBreakingState.shouldBreak(between:and:)` |
| 76 | 1.5 | `_StringGuts._opaqueComplexCharacterStride(startingAt:)` |
| 73 | 1.5 | `_StringGuts._opaqueCharacterStride(endingAt:in:)` |

with `String.strippedLength` at **38.0% inclusive** above it, and
`_slowRoundDownToNearestCharacter` at 7.9%.

### Two causes, both in `strippedLength`

1. **The ASCII fast path was all-or-nothing.** `visibleRunWidth` counted
   bytes until the first byte ≥ 0x80, then re-walked the *whole* run by
   `Character`. A box-drawing border is non-ASCII, so **every bordered line
   in the framework took the segmenting path** — for content that is almost
   entirely ASCII plus a handful of `│` and `─`.

2. **Slicing a run rounded its bounds.** `forEachVisibleANSIRun` scans at the
   scalar level (it must: an `Extend` scalar after an SGR terminator would
   otherwise fuse onto the `m`), but yielded `self[runStart..<index]`. Those
   are scalar indices, not necessarily cluster boundaries, so building the
   `Substring` made the standard library round each bound down — segmenting
   the line again, twice per escape sequence, to hand back a slice whose only
   consumer wanted its scalars.

### The fix: a pairwise break guarantee

Unicode suppresses a grapheme break only for `Extend`, `ZWJ`, `SpacingMark`,
`Prepend`, `Regional_Indicator`, Hangul jamo and `CR`/`LF`. Between two
scalars in none of those categories there is *always* a break (GB999). So
`Character.isStandaloneClusterScalar` is a conservative allow-list of the
blocks terminal UIs are built from (ASCII, box drawing and block elements,
Latin, punctuation, arrows, geometric shapes, CJK, fullwidth, the SF Symbols
PUA); when every scalar in a run is admitted, the width is the sum of the
scalars' own widths and no clustering is required. Emoji, flags, keycaps,
combining marks and jamo are all excluded, and fall back to the exact path.

Three supporting changes: `Unicode.Scalar.loneTerminalWidth` factored out of
`Character.terminalWidth` (which keeps only the multi-scalar rules on top);
runs yielded as scalar-view slices so no bound is rounded; and
`asciiStrippedLength`, which runs the CSI state machine over UTF-8 bytes so an
all-ASCII line — styled or not — never decodes a scalar at all.

### Result

Same trace after: **3630 ms on-CPU**. Every segmentation entry above is gone
(absent from the top 200 self-time frames). `String.strippedLength`:
38.0% → **15.6%** inclusive, 1863 ms → 568 ms.

Interleaved best-of-3 A/B, 300 iterations, 120×40 — **every scenario faster**:

| scale 1 | | scale 4 | |
|---|---|---|---|
| `dashboard` | −43.4% | `dashboard` | −42.1% |
| `kitchensink` | −36.7% | `kitchensink` | −36.0% |
| `textwall` | −19.0% | `textwall` | −20.1% |
| `preferences` | −18.1% | `megalist` | −16.9% |
| `table-multiline` | −13.7% | `table` | −15.5% |
| `modifiers` | −13.3% | `churn` | −9.2% |
| `tables-scroll` | −12.9% | | |
| `table` | −12.8% | | |
| `deep` | −12.4% | | |
| `megalist` | −12.3% | | |
| `tables-vstack` | −7.5% | | |
| `scrollfollow` | −7.2% | | |
| `churn` | −5.1% | | |
| `framedcolumns` | −3.4% | | |
| `anyview` | −2.5% | | |
| `customlayout` | −2.3% | | |
| `fanout` | −2.0% | | |

**The ASCII byte path was not optional.** The first cut kept only the scalar
scan, and *regressed* `textwall` +4.4% and `churn` +3.4%: styled ASCII went
from a byte loop to a scalar loop, and for an all-ASCII string the standard
library's own cluster stride is already trivial, so there was nothing to win
and a decode to pay. Adding the byte path turned those two into −20.1% and
−9.2%. A fast path that is faster than the general path is not automatically
faster than the path it replaced.

### How it is guarded

Commit 317e8587. Three independent pins, none of them a hand-written table:

- all 34 scenario/scale frame checksums byte-identical;
- `loneTerminalWidth` equals `Character.terminalWidth` for **every**
  single-scalar cluster in Unicode (1.1M scalars);
- every scalar the allow-list admits (169k) is checked against the standard
  library's own segmenter — it must break before a base, after a base, and
  against itself, the three probes that between them cover every rule that
  can suppress a break. A wrongly *excluded* scalar only costs speed; only a
  wrongly *included* one could mis-measure, so this sweeps all of Unicode
  rather than a sample.

`strippedLength` is additionally compared against an independent
`ansiSegments()` oracle over ASCII, styled ASCII, box drawing, CJK,
fullwidth, emoji, ZWJ families, flags, keycaps, skin tones, NFD accents and
malformed escapes.

### What is at the top now

| % | self time by module |
|---|---|
| 48.7 | libswiftCore (ARC, generic metadata, `tryCast`) |
| 28.4 | TUIkit's own code |
| 12.9 | libsystem_malloc |

with `swift_release` 5.0%, `swift_retain` 4.3%, `tryCast` 2.0% and
`getGenericContext` 2.0% the largest individual leaves. The next Area-4
targets are therefore allocation and reference-counting traffic, not string
work.

---

## 30. Area 4 — what the caller attribution found next (2026-08-12)

With the width scan fixed, `fanout` (the slowest scenario, and the shape of an
ordinary wide non-lazy list) became the profiling target. Its leaf profile is
almost entirely runtime, not TUIkit: ARC 18%, generic-metadata instantiation
~14%, `tryCast` 4%. None of that is actionable *as leaves* — the question is
who is calling it, which is what `analyze_timeprofile.py --callers` is for.

### First: cross-module optimization is not the answer

The metadata instantiation (`_swift_getGenericMetadata`, `TupleCacheEntry`,
`MetadataCacheKey::operator==`, `hash_short`) is what unspecialized generic
code costs — `V.Body.self` for a `TupleView<(Text, Text, Text, Text)>` is a
runtime cache lookup keyed on four metadata pointers, not a constant. The
obvious lever is to let the optimizer specialize across module boundaries.

Measured: `-Xswiftc -enable-default-cmo`, interleaved best-of-3, 300
iterations — `anyview` −5.4%, `fanout` −1.3%, `deep` −1.1%, `churn` +4.2%,
`textwall` +1.8%, `kitchensink` +1.1%, `modifiers` +0.7%, `table` +0.2%. Net
zero, and `unsafeFlags` would bar the package from being a versioned
dependency anyway. Dropped.

### `String(describing:)` on every row id — 5.1%

    swift_dynamicCast .............. 797 ms  16.0%
      String.init<A>(describing:) .. 204 ms   4.1%   ← top named caller
    String.init<A>(describing:) .... 255 ms   5.1%
      ForEach.makeChild(for:) ...... 252 ms   5.1%

`String(describing:)` probes `TextOutputStreamable`,
`CustomStringConvertible` and `CustomDebugStringConvertible` by dynamic cast
before it can print anything, and `ForEach` ran it once per row per pass to
build each row's identity key. Six sites spelled that conversion
independently — and they *have* to agree, because `ScrollViewReader` matches
a row by reproducing the key `ForEach` gave it.

Now one function, `identityKey(_:)` (commit 0f748fff), with metatype-compared
fast paths for `String`, `Int` and `UUID`. `fanout` −5.2% against a predicted
5.1%.

**The metatype comparison in front of each cast is load-bearing.** A dynamic
cast looks *through* `Optional` and `AnyHashable`: a bare `id as? Int`
succeeds for an `Int?` id and keys that row `"5"` where it had been
`"Optional(5)"` — silently relocating its `@State`, focus and scroll target.

### The state storage, read through the environment — 5.2%

    EnvironmentValues.subscript.getter ....... 360 ms   8.2%
      EnvironmentValues.stateStorage.getter .. 228 ms   5.2%

`RenderContext` already mirrors `renderCache` into a stored field for exactly
this reason (§ the field's own doc comment: ~4.5% of a text-heavy frame).
`stateStorage` is read more often still — every composite view binds `@State`
and marks its identity active, on both passes — and was not mirrored.

Now mirrored, and both mirrors are re-derived by a `didSet` on `environment`
rather than by hand, so in-place mutation of one environment value can no
longer leave a mirror stale (commit 5691dff4). `fanout` −8.0%, `modifiers`
−3.0%, `megalist` −2.4%, `churn` −2.3%, `textwall` −1.9%, others −0.7 to
−1.1%, `table` +0.8% (variance).

### Still open, in rough order of size

1. **`ForEach.childViews` is 28.1% of a `fanout` frame** — `Collection.map`
   over every element building a `ChildView` array eagerly, of which
   `makeChild` is 19.6%. The lazy path (`childViewCollection`) exists; the
   eager one is what non-lazy stacks still call.
2. **`renderToBuffer`'s `view as? Renderable`** is the top Swift-level caller
   of `swift_dynamicCast` (3.8%), twice per view counting
   `measureChildUncached`'s `as? Layoutable`.
3. **`element as? any Equatable` + `AnyEquatableBox`** per row per pass in
   `makeChild` — a protocol conformance cast and an allocation.
4. `RenderContext.withChildIdentity(erasedType:key:)` 5.3%,
   `RenderCache.lookup` 7.2%, `IdentityNode.structurallyEqual` 2.1%.

The pattern to keep: the leaf profile names ARC and casts, and that is never
where the fix is. Both wins above came from `--callers`, not from the
self-time table.
