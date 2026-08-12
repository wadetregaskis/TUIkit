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
