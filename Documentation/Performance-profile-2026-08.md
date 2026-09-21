# Where TUIkit spends its time — a full profile of Stress and the Example

**Measured 2026-08-11**, on macOS 15.7 / arm64, release build (`-Xswiftc -g` for
symbols). Every number here is measured, not estimated; the method for each is
stated so it can be re-run and disagreed with.

This is a survey, not a fix. It ends with a ranked list of what the numbers say
is worth doing.

**It is also a dated record, and symbols in it are as they were named on the
day.** A few have since moved: `FrameNowNanosKey` is now `AnimationFrameKey` in
`AnimationEnvironment.swift` (with `frameNowNanos` a computed accessor into
`AnimationFrame`). Where a section describes work that was reverted rather than
shipped it says so at the point of reverting — §19's automatic memo, §23's
second attempt, §24's memo-and-digest — so a name from those sections not being
in the tree is the record working, not rotting.

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
only animating control is a button. Re-measured against the same binary pair
with a one-off driver — idle CPU per page, one page per run — that was never
committed; `Tools/Profiling/idle_cpu.py` is the committed probe that measures
the same thing (CPU and bytes over a no-input window), and takes the keys to
reach a page as its last argument:

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
producer. Identified by reading the RAW bytes written during an idle window —
which names what actually moves, rather than what a profile says is hot. That
was a one-off script at the time; `Tools/Smoke/raw_probe.py` (2026-08-24) does
it in committed form, and a `CSI row;col H` scan of its capture gives the same
per-row answer:

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
working. **Converted since** — see §15's table and the entry below it: the
multi-line geometry turned out to be two lines of arithmetic the row walk was
already doing, and leaving it cost 6.7% of a core.

Remaining producers, by the pages they would quiet: scrollbar +
`scrollIndicatorEmphasis` (Scroll View, Lists, Tables, Picker), Toggle (Forms,
Toggles), List/Table row cursors (Lists, Tables), then RadioButton, Slider, the
grids and the menu renderers.

## 10. The radio bullet converted (2026-08-11)

Same binary pair, the same one-off per-page driver as §9, 150×50, the Theme
page idle with its radio group focused:

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

**So the chip was never that page's cost.** §9 named it from the raw-byte
read —
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

The lesson for the remaining conversions: **reading the raw bytes finds what
moves, not
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

> **2026-09-12:** "never been hit" did not survive `.focusable()` publishing
> `\.isFocused` to an app's own view. `Card().equatable().focusable()` served
> the unfocused frame after Tab arrived, and so did every row of
> `VStack { ForEach(items) { Row($0) } }.focusable()` with no opt-in anywhere,
> because `ForEach` wraps each `Equatable` row in `_MemoizedRow`. Both
> publishers of `\.isFocused` — `.focusable()` and `.contextMenu` — now go
> through `FocusRegistration.publishIsFocused`, which notes the value with
> `noteAppliedEnvironment` and clears below on a change, as `TintModifier`
> does (Review-batch-2026-09-12 #44). The built-in controls are a different
> channel: they ask the focus manager inside their own cores, and their
> registration declines any memo around them. The general hole — a value
> published by bare assignment — stands for everything else.

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

**Re-derived against HEAD on 2026-09-10** — every percentage below was measured
on 2026-08-13 and three of the four have moved since. The verdicts are stated
first because a stale backlog is worse than none: it reads as a list of things
nobody got to.

1. **`ForEach.childViews`, "28.1% of a `fanout` frame" — PARTLY ADDRESSED; the
   percentage is dead.** `data.map(makeChild(for:))` is still there
   (`ForEach.swift:177`) and non-lazy stacks still call it, but two commits cut
   it from opposite ends. `6a7171bb` stopped `makeChild` calling
   `content(element)` at all for an `Equatable` element — `_MemoizedRow` stores
   `source` + `build` and builds only past a memo miss — for `fanout` −22.3%,
   `churn` −49.8%, `anyview` −36.3%, at up to +2.7% cold. `90a608df` then made
   `resolveChildViews` memoise the resolved array once per pass rather than once
   per walk (it ran five times a frame), for `fanout` −17.8%, `anyview` −16.9%,
   `textwall` −14.1%. What is left per row per pass is structural — an
   `identityKey` string, an `AnyEquatableBox`, a `_MemoizedRow` boxed into
   `ChildView.view`, and a 112-byte array element — and **three attempts on that
   shape are on the record as measured failures**: the reserve-and-append loop
   (`ba703f09`, reverted by `30bab0dc`, `modifiers` **+23.9%**), an uncommitted
   `@inline(never)` on `makeChild` (**+28.2%**), and P20's static
   `ChildViewProvider` witness (warm `deep` **+1.6%**). Do not re-run any of
   them. §35 names the real target — the unspecialised `RandomAccessCollection`
   index advance behind the `ChildViewProvider` existential — and the honest
   first step is a `--callers` profile confirming that cost survives
   `90a608df`, which no measurement has yet checked.
   *(§31's shas for the reverted attempt are wrong: `bdca102c`/`048708c2` are
   not ancestors of HEAD. The reachable pair is `ba703f09` → `30bab0dc`.)*
2. **`renderToBuffer`'s `view as? Renderable` — FIXED (`96953702`).** Both casts
   are gone: `View._renderSelf` and `View._measureSelf` are static witnesses
   (`View.swift:160`, `:170`), and no `as? Renderable` or `as? Layoutable`
   survives anywhere in `Sources/`. Eleven of seventeen scenarios faster, none
   slower — `preferences` −8.0%, `anyview` −7.5%, `framedcolumns` −5.4%,
   `modifiers` −4.4%, `deep` −2.4%. Note this **contradicts** `perf-dead-ends`
   item 5 ("eliminating succeeding dynamic casts buys nothing", from an earlier
   neutral `_isLayoutable` attempt); the later measurement wins.
3. **`element as? any Equatable` + `AnyEquatableBox` — STILL OPEN**, and the only
   one of the four with no prior measured failure. Still at `ForEach.swift:238`
   and `:246`, and now in two more places (`ListRowExtractor.swift:165`, `:199`,
   per *visible* row). `90a608df` divided its frequency by ~5 without removing
   it. The 26-line comment at `ForEach.swift:208` forecloses the three obvious
   fixes and is right to: a static witness cannot ask about `Data.Element`,
   which `ForEach` is deliberately unconstrained over; an
   `extension ForEach where Data.Element: Equatable` compiles and then binds
   statically, so the unconstrained overload wins for everyone and the memo is
   **silently** lost. The one shape not foreclosed is moving the question off
   the element and onto the row-memo maker, resolved once per `ForEach` at
   `init` where `Data.Element` is still concrete.
4. **The identity trio — PARTLY ADDRESSED.** The three key-side sites are fixed:
   `0217d67e` took the identity chain out of `MeasureKey`, `21c3675b` folded
   every composite key to one word before hashing, and `7db94fe9` moved `SizeKey`
   and `ChildViewsKey` onto an `identityHash` for `fanout` −6.4%, `modifiers`
   −6.3%, `anyview` −6.3%. `withChildIdentity` was never touched and got cheaper
   anyway — `5e239298` removed the `didSet` that re-derived two service mirrors
   on every context copy, `deep` −5.1%, `menus` −5.3%, 1.7 MB. What did **not**
   move is the buffer memo itself: `RenderCache.entries` is still
   `[ViewIdentity: CacheEntry]` (`RenderCache.swift:215`), so every *hit* walks
   the chain through `IdentityNode.structurallyEqual`, whose `===` shortcut
   cannot fire because the storing and probing walks build separate chains.

   **Correction, 2026-09-10 — the attribution first written here was a non
   sequitur, and it pointed at the wrong table.** It said §55's `--blame` figure
   of 3.8% for `IdentityNode.structurallyEqual` localised to `entries`, because
   `7db94fe9` had left `menus` flat. It cannot: §55's trace is of the **Mode A
   `menu` tree** (`Tools/Profiling/RenderHarness/Trees.swift:229`), a `Menu` and
   three `Button`s with no `ForEach` and no `.equatable()` — so
   `renderValueMemoized` is never entered and `entries` is never probed there at
   all. Ruling out `SizeKey` and `ChildViewsKey` does not implicate `entries`
   either: `structurallyEqual` has at least seven callers, including
   `StateStorage.StateKey`, both `activeIdentities` sets, `appliedEnvironment`'s
   `EnvironmentSlot`, `isAncestor(of:)` and `RetainedSubtreeIndex.retains`.

   `entries` is still worth converting, on a different argument — it is hot where
   the buffer memo actually SERVES, which is `fanout` far ahead of anything else,
   then `gradients`, `textwall` and `churn`. `menus` should be **predicted flat**
   there rather than hoped for. Two lessons, and the second one cost something: a
   percentage has a date, and a percentage also has a TREE — a `--blame` figure
   means nothing until you know which harness shape produced it.

**Item 4's `entries` table was then converted and measured — 2026-09-10,
`01008650`.** Warm: `textwall` **−3.2%**, `fanout` **−2.9%**, `modifiers`
**−1.9%**, `megalist` −0.8%, `scrollfollow` −0.6%, all with intervals clear of
zero; nothing slower. `--cold` (no hits, so purely the miss path): nineteen
scenarios indistinguishable. `menus` flat at −1.0%, as the correction above
predicted — the scenarios that moved are exactly the ones where the buffer memo
SERVES, and `--bench` prints `render: 2000` entries a frame on `fanout`, which is
why it is the headline. Checksums and prune summaries identical,
`TUIKIT_VERIFY_RENDER_MEMO` clean on 21/21.

What is left of item 4 is `activeIdentities: Set<ViewIdentity>`
(`RenderCache.swift`), which pays the same walk in `removeInactive`'s `contains`
once per cached entry per frame — ~2,000 times a frame on `fanout`. Its safety
argument is one-sided rather than a bargain: equal identities have equal hashes,
so a live entry can never be MISSED, and a collision can only keep a dead one a
pass longer. Memory, never wrong pixels. Its own commit, its own measurement.

**The original "what to measure first" recommendation**, kept for the reasoning:
item 4's `entries` table, on `7db94fe9`'s own recipe — an `identityHash` key with the `ViewIdentity` moved
into `CacheEntry` (already a `final class`) for `isLive`/`affects`. It is the
only survivor with a current measured size, a proven recipe, and a standing
verification net (`TUIKIT_VERIFY_RENDER_MEMO` checks 4,565 row serves). Two
risks worth stating: a collision here shows as **wrong pixels** rather than a
wrong number, and `perf-dead-ends` item 7's prohibition on hash-keying
`ViewIdentity` **does** still bind `StateStorage.StateKey` — where a collision
would alias `@State` — so that table must not be swept in alongside.

The pattern to keep: the leaf profile names ARC and casts, and that is never
where the fix is. Both wins above came from `--callers`, not from the
self-time table. And the pattern this re-derivation adds: **a percentage has a
date**, and four weeks of commits in the same subsystem is long enough for three
of four to stop being true.

---

## 31. Area 4 — a rejected change, and where the increment landed (2026-08-13)

### `data.map(makeChild(for:))` → a reserving loop. Committed, then reverted.

`ForEach.childViews` built its array through the fully generic
`Sequence.map`. `Data` is only a `RandomAccessCollection`, so handing `map` a
method reference builds a closure whose argument and result pass **indirectly**
through a reabstraction thunk, once per element:

    Collection.map<A, B>(_:) ......................... 1215 ms  27.7%
      thunk for @callee_guaranteed
        (@in_guaranteed A.Sequence.Element) -> (@out …) 1003 ms  22.8%
    ForEach.makeChild(for:) ........................... 862 ms  19.6%

The loop does remove those thunks. It is still a net loss. Interleaved
best-of-3 at **800** iterations:

| scenario | change |
|---|---|
| `modifiers` | **+23.9%** |
| `fanout` | −6.0% |
| `anyview` | −4.4% |

`fanout` rows are an `HStack` of four `Text`s; `modifiers` rows carry a deep
modifier chain, so `content(element)` returns a large nested `ModifiedView`
type. **Cheap row builders win, expensive ones lose several times more.**
Whatever the generic `map` buys back on a large row type outweighs the thunks.

`@inline(never)` on `makeChild` was tried on the theory that the loop inlined
a huge row builder into an oversized frame (`___chkstk_darwin` was already
1.6% self). `modifiers` went to **+28.2%** — theory wrong, mechanism still
unexplained. Reverted (commits bdca102c, 048708c2).

**How it got committed.** The original A/B ran 300 iterations over six
scenarios, and `modifiers` was not one of them. It surfaced in the cumulative
sweep as −1.9% where the width-scan change *alone* had given −13.3% — a win
that had gone missing, which is exactly the shape a regression makes when you
only look at totals. Two rules from it:

- **Sweep every scenario before claiming "no regressions."** A six-scenario
  sample is a spot check, not a sweep.
- **Re-measure anything whose cumulative number moves the wrong way.** The
  compounding arithmetic is the check on the per-change measurements.

`dashboard` in the same sweep first read **+8.8%** at 300 iterations and
−0.1% at 2000. At ~180 µs a frame, 300 iterations is 50 ms of measurement —
mostly warm-up. Scale iterations to the scenario.

### Where the increment landed

Interleaved best-of-3, **800** iterations, 120×40, session start → session
end (`317e8587`…`048708c2`) — **every scenario faster**:

| scenario | change | | scenario | change |
|---|---|---|---|---|
| `dashboard` | −43.4% | | `deep` | −12.4% |
| `kitchensink` | −36.0% | | `fanout` | −11.3% |
| `textwall` | −27.1% | | `scrollfollow` | −10.2% |
| `preferences` | −21.4% | | `anyview` | −9.4% |
| `modifiers` | −21.0% | | `tables-vstack` | −6.3% |
| `table-multiline` | −14.3% | | `customlayout` | −5.6% |
| `tables-scroll` | −13.8% | | `framedcolumns` | −5.1% |
| `table` | −13.5% | | `churn` | −3.3% |
| `megalist` | −13.4% | | | |

Three shipped changes: the width scan (§29), the identity key and the
state-storage mirror (§30). All 34 scenario/scale frame checksums are
byte-identical to the session's starting binary throughout.

---

## 32. Area 4 — the allocator, found by profiling a different shape (2026-08-13)

Everything above came from profiling `fanout`. Profiling `tables-scroll`
instead — the next most expensive scenario, and a completely different tree —
found a bottleneck none of the `fanout` work would ever have reached.

On `tables-scroll` the frame is dominated by **libsystem_malloc**, not by ARC,
casts or metadata (2500 iterations, 6862 ms on-CPU):

| ms | % | self time — leaf frames |
|---|---|---|
| 306 | 4.5 | `tiny_free_list_add_ptr` |
| 267 | 3.9 | `tiny_free_reattach_region` |
| 244 | 3.6 | `tiny_free_detach_region` |
| 238 | 3.5 | `tiny_malloc_from_free_list` |
| 231 | 3.4 | `tiny_free_list_remove_ptr` |
| 213 | 3.1 | `tiny_free_no_lock` |
| 154 | 2.2 | `tiny_free_scan_madvise_free` |
| 137 | 2.0 | `free_tiny` |
| | **26.2%** | **in the allocator** |

The `detach_region` / `reattach_region` / `scan_madvise_free` entries are the
giveaway: that is not steady free-list traffic, it is the heap repeatedly
growing and shrinking across region boundaries — the signature of large
transient allocations churning every frame.

Above them:

    _TableCore.renderRow(…) ......................... 2905 ms  42.3%
      Sequence.map<A, B>(_:) ........................ 2722 ms  39.6%
        partial apply for thunk … (@in_guaranteed
          TableColumn<…>) ............................1462 ms  21.3%
    static ANSIRenderer.render(_:with:) ............. 1242 ms  18.1%
    static ANSIRenderer.buildStyleCodes(_:) .......... 469 ms   6.8%

### Two costs, both per row

**Allocation.** `renderRow` built a spacing `String(repeating:)`, an array of
styled cells through a generic `map`, the `joined` result, three
concatenations and a padding `String(repeating:)` — ~N+5 allocations per row,
every one discarded immediately.

**Restyling.** It called `ANSIRenderer.colorize` once per cell with the *same*
foreground each time, rebuilding an identical `TextStyle`, re-deriving its
codes and re-joining them for every column of every row.

Now `ANSIRenderer.styleSequence(for:)` exposes the SGR introducer `render`
emits, so a row derives it once and wraps each cell as
`sequence + text + reset` — byte-for-byte what `colorize` produced — and the
row is appended into a single reserved buffer, with `asciiSpaces` for spacing
and padding. One allocation per row (commit a6b5aedb).

| scenario | change | | scenario | change |
|---|---|---|---|---|
| `table` | **−33.8%** | | `framedcolumns` | −1.2% |
| `tables-scroll` | **−29.8%** | | `dashboard` | −0.8% |
| `tables-vstack` | −12.3% | | others | −0.0 to −0.8% |
| `churn` | −2.3% | | `modifiers` | +1.2% (noise) |

`table-multiline` was **exactly 0.0%** — because multi-line cells compose
through `renderMultiLineRow`, which carried its own copy of the same pattern,
running once per *line* rather than once per row. Same treatment there
(commit df3a40e8): **`table-multiline` −25.1%**.

That "flat" result was the useful signal. A shared cost duplicated into a
sibling function shows up as one scenario stubbornly not moving while its
neighbours do.

### Measurement note

Every scenario outside the table family moved +1.0 to +5.4% on one pass of the
multi-line A/B. Re-running with the **binaries swapped** put `churn` at +4.5%
in the other direction — a contradiction, so it was drift, not an effect.
Swapping the order is the cheapest test for whether a small uniform shift is
real.

### Session total

Interleaved best-of-3 (800 iterations, 2500 for the sub-millisecond
scenarios), session start → `df3a40e8`:

| scenario | change | | scenario | change |
|---|---|---|---|---|
| `dashboard` | −44.1% | | `deep` | −13.8% |
| `table` | −43.7% | | `megalist` | −13.5% |
| `tables-scroll` | −36.4% | | `framedcolumns` | −13.5% |
| `table-multiline` | −34.9% | | `fanout` | −8.9% |
| `kitchensink` | −27.3% | | `anyview` | −8.5% |
| `textwall` | −26.6% | | `scrollfollow` | −8.2% |
| `tables-vstack` | −18.5% | | `customlayout` | −4.9% |
| `preferences` | −18.5% | | `churn` | −4.0% |
| `modifiers` | −17.5% | | | |

All 34 scenario/scale frame checksums byte-identical throughout; 4033 tests;
both apps smoke-walk clean with no structural render-lint findings.

---

## 33. Area 4 — localization runs per Text, per frame (2026-08-13)

Profiling `anyview` — a third shape, ARC-dominated rather than allocator- or
string-dominated — surfaced a cost that has nothing to do with the render
pipeline. 4000 iterations, 4948 ms on-CPU:

    ForEach.childViews(context:) ..................... 1670 ms  33.7%
      ForEach.makeChild(for:) ........................ 1424 ms  28.8%
        closure … in AnyViewStormView.body ........... 1157 ms  23.4%
          Text.init(_:) ................................445 ms   9.0%
            static LocalizedStringKey.substituting(…) . 259 ms   5.2%
            LocalizedStringKey.resolved(with:) ........ 146 ms   2.9%
            LocalizationService.string(for:) .......... 137 ms   2.8%
          LocalizedStringKey.StringInterpolation
            .appendInterpolation<A>(_:) ............... 132 ms   2.7%

`Text.init(_ key: LocalizedStringKey)` resolves eagerly — it looks the key up
and substitutes the interpolated arguments at **construction**. A list row
written `Text("Row \(index)")` therefore performs a table lookup and a
template substitution once per row, per frame, for as long as the row exists.
That is ~9% of this frame, none of it in the renderer.

### The obvious half of the fix measured as nothing

`substituting` appended the literal text between conversions one `Character`
at a time into an unreserved `String`. Rewriting it to reserve capacity and
copy a run at a time measured **neutral**, three A/B passes:

| pass | A | B | `anyview` |
|---|---|---|---|
| 1 | old | new | +5.2% |
| 2 | **new** | **old** | +3.5% |
| 3 | old | new | +2.3% |

In every pass the binary that ran **second** was slower — including pass 2,
where that was the *old* one. Position bias, not an effect. Reverted, because
an unvalidated change that adds `runStart` bookkeeping to five branches is
worse code for no measured gain.

So the cost inside `substituting` is the **scan**, not the append:
`Character`-at-a-time iteration, `Character.isNumber` (a Unicode property
query) per digit, and `"hlLqzjt".contains(…)` / `"@diufgGeExXos".contains(…)`
— each of which scans a `String` literal — per conversion. Whoever picks this
up should switch those to `switch` statements over the character and leave
the appending alone.

### The measurement floor is now the constraint

The remaining named targets are each 3–5% of a single scenario:
`view as? Renderable` (3.8%), the per-row `as? any Equatable` conformance cast
(3.3%), `withChildIdentity(erasedType:key:)` (5.3%), `RenderCache.lookup`
(7.2%), and this one. On this machine, with the desktop app taking ~18% of a
core and load average above 2, run-to-run variation on these scenarios is
**±3–5%** — the same size as the effects. Both changes reverted today
(§31 and this one) failed the same way: a plausible improvement whose
measurement could not be separated from drift.

Validating anything in that range needs a quiet machine and the order-swap
check as standard. Everything larger has been taken.

---

## 34. The measurement, rebuilt (2026-08-13)

§33 ended by naming the measurement floor as the constraint. This is the fix.
`Tools/Profiling/ab_bench.py` (commit fc59158d) replaces the hand-rolled A/B
loop; its README section is the usage, and this is the evidence.

**What was wrong.** Three things, and each cost something:

| | consequence |
|---|---|
| wall clock | every microsecond the scheduler spent elsewhere landed in the number |
| fixed A-then-B order | a fixed bias — *every* pass showed whichever ran second as slower, including the pass where that was the original (§33) |
| best-of-N per binary, unpaired | discards the pairing that cancels drift; a high-variance estimator from 3 samples |
| fixed iteration count | 300 iterations of a 160 µs scenario is 50 ms, mostly warm-up — that produced a phantom +8.8% (§31) |

**What replaced it.** `Stress --bench` now reports `cpu-per-frame` beside
`per-frame` (thread CPU time, `Sources/Stress/CPUClock.swift`); the tool reads
that, randomises the run order per rep, estimates the **median of the paired
per-rep ratios**, brackets it with a percentile bootstrap, and prints a
verdict. Iterations are calibrated per scenario to ~1.5 s a run.

**Null test** — a binary against a byte-identical copy of itself, on a machine
at load 1.68 with a browser taking 27% of a core. Every verdict must be
`indistinguishable`, and the interval width *is* the noise floor:

| scenario | change | 95% CI | verdict |
|---|---|---|---|
| `dashboard` | +0.2% | −0.7% … +0.7% | indistinguishable |
| `table` | +0.0% | −2.6% … +0.8% | indistinguishable |
| `churn` | +0.6% | −2.2% … +1.7% | indistinguishable |
| `fanout` | −0.0% | −2.7% … +3.5% | indistinguishable |

`fanout` narrows to ±2.0% at 40 reps — the interval shrinks as 1/√reps, so
resolution is now a dial rather than a limit.

**Positive control** — the map→loop change reverted in §31:

| scenario | change | 95% CI | verdict |
|---|---|---|---|
| `modifiers` | +29.9% | +28.2% … +31.0% | slower |
| `fanout` | −5.7% | −6.7% … −2.2% | faster |
| `anyview` | −1.7% | −2.7% … −0.7% | faster |

It resolves a **1.7%** improvement with an interval clear of zero — better
than the ±3–5% §33 was stuck at — and independently confirms that revert.

**Negative control** — the `substituting` rewrite reverted in §33 on
judgement: `anyview` +0.5% [−3.2, +3.1], `textwall` +0.2% [−0.2, +1.4],
`churn` +0.8% [−1.1, +3.4]. All indistinguishable. The judgement was right,
and now it is a measurement.

### Two knobs that measured worse

Both were tried and rejected, so neither is an option in the tool:

- **Min-of-k runs per binary per rep.** Widened `fanout` from ±3% to ±5%. The
  minimum is a biased estimator whose bias tracks the local noise level, and
  the extra runs push A and B further apart in time — which is exactly the
  pairing the design depends on.
- **Shorter runs with proportionally more reps** (same total time). Helped
  `churn` (±1.4%), hurt `fanout` (±4%): a big working set needs enough frames
  to amortise process start-up.

### The standing rule

Run the null test — `ab_bench.py X X` — whenever a result looks doubtful. It
costs one command and answers the only question that matters before believing
a number: what can this machine resolve right now.

---

## 35. Re-evaluating what the old method could not resolve (2026-08-13)

With §34's tool in place, the results that were previously "in the noise"
deserved a real answer rather than a shrug.

### Cross-module optimization — settled, both ways

§30 measured `-enable-default-cmo` as "net zero" from a mixed table
(`anyview` −5.4%, `churn` +4.2%, …) that the old method could not resolve.
Re-measured properly, from two builds of the same HEAD:

| scenario | change | 95% CI | verdict |
|---|---|---|---|
| `anyview` | −0.9% | −2.1% … +2.8% | indistinguishable |
| `fanout` | −0.7% | −1.9% … +2.8% | indistinguishable |
| `deep` | −0.1% | −1.2% … +0.9% | indistinguishable |
| `churn` | +0.1% | −1.7% … +2.0% | indistinguishable |

Every point estimate is inside ±1%. The −5.4% and +4.2% of §30 were both
noise. **The conservative flag does nothing here**, which retires the
"unspecialized generic metadata is the cost" hypothesis as far as this lever
can test it.

The aggressive form is not available at all: `-cross-module-optimization`
**crashes swift-frontend** on this codebase —

    While running pass #190002 SILModuleTransform "CrossModuleOptimization"
    compile command failed due to signal 6

on `TUIkitView`. Worth a minimised upstream report if anyone wants that lever;
until then it is not an option.

### The localization scan — shipped

§33 rewrote the *appending* half of `LocalizedStringKey.substituting` and
measured neutral, concluding the cost was the **scan**. That conclusion held:
replacing `"hlLqzjt".contains(…)` and `"@diufgGeExXos".contains(…)` — each of
which scans a `String` grapheme by grapheme, per conversion, per interpolated
`Text`, per frame — with two `switch` statements gives `churn` −2.4%,
`anyview` −1.4%, `dashboard` −0.9%, all with intervals clear of zero
(commit 114f7fa9).

Small, but it is the first change this programme has shipped that the previous
methodology could not have justified: every one of those effects is inside the
±3–5% that §33 called the floor.

### A false positive, caught

`table` first read **+0.7% [+0.0, +1.6] "slower"** — an interval whose edge
sits exactly on zero. Re-run at 40 reps with a different seed: **+0.5%
[−0.1, +1.0], indistinguishable.**

Seventeen scenarios at 95% confidence produce roughly one wrong verdict per
sweep by chance. A marginal verdict is a prompt to re-test with more reps and
a different seed, not a result — now noted in the tool's README.

### A null result worth recording: `.enumerated()` is not the tuple cost

`swift_getTupleTypeMetadata` is **5.8%** of a `fanout` frame — the runtime
being asked for two-element tuple metadata over and over. The obvious suspect
was `for (index, child) in children.enumerated()`, which the stacks use
thirteen times and which `fanout` runs 2000× a frame through `HStack`.

Converting all five `HStack` loops to `for index in children.indices`
measured **nothing**: `fanout` +1.1% [−0.7, +1.2], `framedcolumns` −0.5%,
`tables-vstack` −3.6% [−17.7, +4.0], `dashboard` −0.3% — every one
indistinguishable. Reverted: neutral, and `where` becoming `guard … continue`
reads worse. `.enumerated()` over a concrete `[ChildView]` specializes fine.

The real caller is elsewhere:

    swift_getTupleTypeMetadata2
      ← protocol witness for Collection.formIndex(after:) in conformance Range<A>

i.e. advancing an index over `ForEach`'s `Data` through the **unspecialized**
`RandomAccessCollection` witness — `ForEach(0..<n, id: \.self)` is
`Data == Range<Int>`, but `childViews` is reached through a
`ChildViewProvider` existential, so nothing specializes. That is the same
cost the map→loop change of §31 accidentally addressed on `fanout` (−6%)
while costing `modifiers` +30%. Whoever returns to it needs a mechanism for
that trade first; the target is real but the lever is not yet known.

---

## 36. One more round: the cache entry, and two scenarios that cannot measure (2026-08-13)

### `CacheEntry`: struct → `final class`

`RenderCache.lookup` must pull an entry out of the dictionary before it can
check anything, and `CacheEntry` was a struct holding a type-erased snapshot
plus a whole `FrameBuffer` — five arrays. Every lookup retained ~seven
refcounted fields and released them again, **including on the three reject
paths** that discard the entry immediately. `lookup` is 7.6% inclusive of a
`fanout` frame, against `swift_release` 6.9% and `swift_retain` 5.5% self.

A `final class` makes that one reference. Every property was already `let`, so
sharing cannot alias a mutation; the type is `public` but referenced in exactly
three places, all inside `RenderCache.swift`.

| scenario | change | 95% CI | verdict |
|---|---|---|---|
| `fanout` | −4.2% | −7.2% … −3.7% | faster |
| `textwall` | −2.1% | −3.4% … −0.9% | faster |
| `anyview` | −1.8% | −4.0% … −1.0% | faster |
| the other fourteen | | | indistinguishable |

Commit ffa28081; all 34 checksums unchanged.

### The null test was lying, and fixing it exposed two unusable scenarios

`ab_bench.py X X` keyed each rep by binary *path*. Passing the same path twice
collapsed the dictionary to one entry, so both sides read the **same** run:
every ratio was exactly 1.0 and it printed `+0.0% [+0.0, +0.0]`. A perfect
score from a measurement that never happened. (§34's null tests used two
separate copies, so those stand.) Fixed to index by position — commit
cbc88f97.

Re-run properly:

| scenario | null test | |
|---|---|---|
| `megalist` | −0.9% | [−13.4% … +17.3%] |
| `tables-vstack` | −9.2% | [−18.2% … +10.3%] |

**Both are ±15% scenarios on this machine** — their own run-to-run spread
swamps anything worth shipping. That retroactively explains two verdicts they
had just produced against the `CacheEntry` change (`tables-vstack` "+3.7%
slower", `megalist` "+7.8%"): neither was about the change. Check a scenario's
own floor before trusting its verdict.

### Also tried, also null

Making `HStack`'s five `.enumerated()` loops index-based, on the theory that
the 5.8% in `swift_getTupleTypeMetadata` was the `(index, element)` tuple:
indistinguishable on four scenarios, reverted. The real caller is
`Collection.formIndex(after:)` on `Range<A>` — see the note at the end of §35.

---

## 37. Is there more ARC and malloc to win? (2026-08-13)

The two changes that shipped today came from reference-counting and copy costs,
not algorithms, so the natural question is whether that seam has more in it.
Attributed on the `fanout` trace (2000 iterations):

| % of frame | what |
|---|---|
| 6.9 | `swift_release` |
| 5.5 | `swift_retain` |
| 3.1 | `swift_bridgeObjectRelease` |
| 2.4 | `swift_bridgeObjectRetain` |
| **17.9** | **ARC total** |
| 7.6 | `swift_allocObject` |
| ~3.6 | …of which `swift_allocBox` → `__swift_allocate_boxed_opaque_existential_1` |

### Where it comes from

**Half the object allocation is existential boxing.** `ChildView` stores its
child as `any View` — deliberately, so the view is boxed once rather than
copied into two closure contexts — and `makeChild` builds a *fresh* row view
every frame, so that box is a new heap allocation per row per frame.
`CacheEntry.viewSnapshot: Any` and `AnyEquatableBox.value: any Equatable` box
too, but only on a store and only for elements wider than three words
(`fanout`'s are `Int`, so they stay inline).

**The per-type copy work is thin and spread.** Self time, not inclusive:

    initializeWithCopy for ChildView ......... 0.4%
    initializeWithCopy for RenderContext ..... 0.3%
    outlined copy of IdentityNode.Step ....... 0.3%
    outlined init with copy of ChildView ..... 0.2%
    outlined destroy of RenderContext ........ 0.2%
    … and a similar tail for Text / TupleView

Nothing here is another `CacheEntry` — that one was ~7 refcounted fields
copied on a path taken several thousand times a frame *and thrown away on
three of four exits*. No remaining value type has that shape.

### What that leaves

1. **Structural, and the real one.** Every frame rebuilds every row view from
   scratch, boxes it into `any View`, copies it into a `ChildView`, puts that
   in an array, and the stacks copy each element out again — and then the row
   memo usually discards the result because the buffer was already cached.
   The allocation and the ARC both trace back to that single fact. Fixing it
   means the eager `childViews` path, which §31 already showed has a bad trade
   (`fanout` −6% / `modifiers` +30%) and no known lever.

2. **Considered and rejected on reasoning, not tried.** `RenderContext` now
   carries four refcounted fields (environment, `renderCache`, `stateStorage`,
   `identity`) and is copied at every descent, so consolidating the two
   services into one box would remove a retain per copy. But adding
   `stateStorage` as the fourth *was itself a win* (§30) — which says reads
   dominate copies on this path, and a box would add indirection to the
   dominant operation. Expect a loss; do not spend the build.

3. **`swift_bridgeObjectRetain`/`Release` at 5.5%** is String and Array
   traffic: `ChildView.identityKey: String?` and
   `IdentityNode.Step.keyed(_, key:)` are copied per row per pass. For
   `ForEach(0..<n)` those strings are small enough to live inline, so the
   calls are cheap — but they are still calls, and removing them means
   changing the identity key's representation away from `String`, which the
   scroll-targeting API (`scrollTo(key:)`) is built on.

**Assessment.** The one-line seam is worked out. What remains is one
architectural item with a known hazard, and a representation change to view
identity — both real, both far larger than anything shipped today, and neither
worth starting without deciding it is the priority.

## 38. The row the memo was going to throw away (2026-08-13)

§37 named the remaining seam as structural: *"every frame rebuilds every row
view from scratch, boxes it into `any View`, copies it into a `ChildView`,
puts that in an array, and the stacks copy each element back out — and then
the row memo usually discards the result because the buffer was already
cached."* This is that item, scoped to the last clause.

### What the profile said

`fanout`, Time Profiler with `--callers`:

```
implicit closure #2 in ForEach.childViews    22.9%  inclusive
  ForEach.makeChild(for:)                    21.3%  inclusive
    HStack.init                               8.3%
    (the caller's row closure)                8.1%
swift_allocObject                             7.6%  self
  ~half via swift_allocBox
    → __swift_allocate_boxed_opaque_existential_1
```

and the harness's own counter puts `fanout`'s row-memo hit rate at **94.2%**.

Those two facts together are the whole finding. `makeChild` built a row view
for every row on every pass — and on 94 of every 100 rows the very next thing
that happened was `_MemoizedRow` returning a cached buffer (or a cached size)
and never looking at the view it had just been handed.

### The change

`_MemoizedRow` stops storing a built `Content` and stores what it takes to
build one:

```swift
public let element: Element        // the memo key
private let source: Source         // the ForEach data element
private let build: (Source) -> Content
private var content: Content { build(source) }   // builds — past a miss only
```

`build` is the enclosing `ForEach`'s own content closure, which already exists
and is shared by every row, so storing it is a **retain, not an allocation**.
A capturing `() -> Content` would have been simpler and would have traded the
row view's allocations for one closure box per row per pass — which is the
trade this change exists to avoid.

`ForEach.makeChild` therefore no longer calls `content(element)` at all for an
`Equatable` element. `List` keeps the eager initializer (`init(element:content:)`,
constrained `where Source == Content` with an identity builder — a static thunk,
not an allocation) because it must read the row's `.badge(_:)` off the unwrapped
view before rendering it.

### Warm: the steady state

`ab_bench.py`, all 17 scenarios, 15 reps, CPU time, order randomised per rep:

```
scenario           iters     old µs     new µs   change           95% CI  verdict
churn                913     1648.2      834.1   -49.8%    -51.1%  -47.1%  faster
anyview              755     1814.7     1153.4   -36.3%    -37.2%  -33.8%  faster
modifiers           1282     1091.3      732.9   -32.8%    -33.2%  -31.8%  faster
fanout               357     4311.4     3345.3   -22.3%    -25.4%  -20.4%  faster
textwall            1410     1058.4      956.4    -9.3%    -11.1%   -8.1%  faster
preferences         6513      221.3      207.0    -5.2%    -11.0%   -4.2%  faster
kitchensink         3165      700.6      655.2    -4.7%     -7.3%   -0.5%  faster
customlayout        3909      352.2      344.4    -2.4%     -3.2%   -1.0%  faster
dashboard           9771      156.2      153.8    -1.6%     -2.5%   -1.0%  faster
```

The rest are indistinguishable, which is the right answer for a scenario with
no `Equatable`-element `ForEach` in it.

`modifiers` at **−32.8%** is worth dwelling on: it is the scenario that
*regressed* +23.9% and then +28.2% under the two attempts recorded in §31, and
it regressed there for the same reason it wins here. Its rows are expensive to
build. §31 tried to make building them cheaper; this stops building them.

### It grows with the data

The same A/B at `--scale 4` — four times the rows — on the six scenarios that
move:

```
scenario           iters     old µs     new µs   change           95% CI  verdict
churn                223     6383.1     3013.7   -54.2%    -55.6%  -51.5%  faster
anyview              156     9465.5     5399.3   -42.3%    -44.1%  -34.3%  faster
modifiers            318     4882.1     3028.4   -35.1%    -39.2%  -29.7%  faster
fanout                57    25010.5    18389.5   -27.0%    -32.7%   -6.9%  faster
textwall             304     4669.0     4085.7   -12.6%    -15.4%  -10.4%  faster
dashboard           4934      313.2      303.4    -3.3%     -3.5%   -2.6%  faster
```

Every one is **larger** than at scale 1 (−49.8 / −36.3 / −32.8 / −22.3 / −9.3 /
−1.6 respectively), which is the shape to expect: the work removed is per row,
so more rows means more of it. It is not a small-N artefact.

### Cold: the honest check

Deferring work behind a memo makes the **miss** path dearer — a full miss now
builds the row twice, once in `sizeThatFits` and once in `renderToBuffer`,
where before both shared one build. `ab_bench.py --cold` (§ the tool gained the
flag for exactly this) resets state and cache before every frame, so every
frame is all-miss:

```
anyview              116    12468.6    12829.6    +2.7%     +2.1%   +2.8%  slower
churn                125    11358.8    11694.3    +2.3%     +2.1%   +3.4%  slower
customlayout        3159      458.2      466.4    +2.2%     +0.5%   +2.7%  slower
tables-vstack       1266     1143.0     1154.0    +0.9%     +0.5%   +1.7%  slower
megalist            1640      836.7      841.5    +0.7%     +0.4%   +1.3%  slower
tables-scroll        501     2922.8     2943.0    +0.6%     +0.3%   +1.1%  slower
...
fanout                50    78659.6    77396.2    -1.6%     -1.9%   -1.1%  faster
textwall             185     7914.7     7821.4    -1.2%     -1.9%   -0.5%  faster
framedcolumns       1264     1130.4     1117.6    -1.1%     -1.6%   -0.6%  faster
```

**The trade, stated plainly:** up to **+2.7%** on a frame where nothing can be
served from cache, against **−22% to −50%** on the steady state a running app
lives in. `churn` is both the biggest warm win (−49.8%) and a cold loser
(+2.3%), which is the trade in a single row of the table.

Eight scenarios got *faster* cold, which was not predicted. The reason is a
second-order effect: `ChildView` now boxes a `_MemoizedRow` holding an element,
a source value and a closure reference, instead of boxing a fully-built row
view. The existential box is smaller and the `[ChildView]` array copies less.
That shows up only where the memo cannot mask it.

### A false positive, caught by the rule

The 15-rep warm sweep called `table-multiline` **+0.2% [+0.1, +1.3] slower** —
a verdict with a sign. Per the multiple-comparisons rule from §35, seventeen
simultaneous 95% intervals produce roughly one spurious verdict per run, so it
was re-tested rather than believed:

```
                          40 reps, warm            null test (base vs base)
table-multiline      +0.1%  [-0.2, +0.3]           -0.1%  [-0.3, +0.2]
```

Indistinguishable, and the null test against the binary itself has the same
width. There was no effect.

### Correctness

- Frame checksums **byte-identical on all 34** scenario × scale (1×, 4×)
  combinations.
- 4034 tests green; SwiftLint 0 violations in 886 files.
- `LazyChildViewsTests` gained the guarantee as a test: a second frame over a
  warm cache must not invoke the row builder once. The pre-existing
  "Subscripting builds exactly the touched rows" now asserts **zero** builds —
  subscripting a memoized ordinal no longer constructs anything.

## 39. The last focus-indicator producer: the menu row (2026-08-16)

Fourth and last of the four named in §13, and the largest number in the app.
The Example's **main menu sat at 35.0% of a core while idle**, emitting
654 bytes/s. That shape is the finding: the fewest bytes and the most CPU of
any screen — a whole view walk ~30×/s that changes almost nothing on screen.
The `menu` scenario in `Tools/Profiling/drive.py` traces at 99.2% inclusive in
`renderFrame` with no hot leaf, i.e. 32 inline rows re-rendered to recolour one.

### Why this one resisted the pattern the other three used

The others hand over a *mark* — a cap, a bullet, a chip — and a mark is one
glyph the producer can redraw per colour. A menu row's indicator is the ROW: a
full-width bar under whatever the row draws. Worse, `_MenuItemRow.foreground`
was `palette.readableText(on: highlight)`, so the *text* colour moved with the
bar; a run could not be built by recolouring the drawn line.

Both halves resolved at once, and the second is a fix in its own right:

- **The bar moved out of the row.** `_MenuItemRowBar` (a `Renderable`, because
  `ButtonStyle.makeBody` composes views and has nowhere to hang
  `animatedCells`) renders the row once *without* a background, then paints the
  cycle over the finished line — one `applyPersistentBackground` per step, each
  self-contained. 16 recolourings of one rendered line, not 16 renders.
- **The text stopped moving.** The focused row keeps `palette.foreground`, like
  the `Picker` drop-down and `List`'s focused row already do. Text that changes
  colour mid-breath reads as a glitch, and the alternative could flip from the
  light end of the palette to the dark one partway through a cycle. The pair is
  already measured: `PaletteContrastAuditTests` holds `foreground` over *both*
  pulse endpoints for every shipped palette — which is what bounds
  `ViewConstants.focusPulseMax` in the first place.

### Measured

| screen | idle CPU before | after | bytes/s | writes/s |
|---|---|---|---|---|
| **main menu** | **35.0%** | **0.3%** | 654 → 793 | 2.2 (unchanged) |
| Overlays & Modals | 10.4% | **0.2%** | | |
| Menus | 3.5% | 2.8% | 9016 | (animates legitimately) |

The write rate is the check that matters, and it is unchanged at 2.2/s — with
the same three background colours written (`48;5;16`, `22`, `28`) over a 6 s
window, before and after. It still breathes; it simply no longer walks the view
tree to do it. (2.2/s rather than ~20/s because the 256-colour cube quantises
this ramp to three distinct shades, so the ticks between them write nothing —
`lastSteps` per clock, from §11.)

Bytes/s rose 21%, which is the known per-run splice overhead (one dead escape
per run per tick, §10) applied to a run 20 cells wide.

All four producers named in §13 are now converted. What remained above 3% idle
was the **scrollbar** — converted shortly afterwards in 27a87525, "The scrollbar
breathes by the row, not by the frame".

**Do not read the numbers in the sentence this replaces.** They were wrong when
written and are wronger now. "Picker 24.5" was three `DatePicker`s sharing one
`$date`, retracted earlier in this file; List and Table bars never pulsed at all
(each builds a literal static `ScrollbarColors`). And "one run per bar row" is
not what shipped or what is right — the empty track cells are constant across
the cycle and earn nothing, so `verticalScrollbarRuns` keeps only the rows whose
bytes actually differ: about eight runs of width 1 for a 20-row bar, against a
floor of three. Measured on the current build, Scroll View idles at **1.2%** and
Picker and Lists at **0.2%**, focused or not.

## §14 — The spinner, and the container that ate its run

The producer §13 did not name, because at the time it was not one: `Spinner`
derived its glyph from wall-clock elapsed time and asked the run loop to
re-render it at the style's rate. A full measure-layout-render-diff of the whole
screen, ten times a second, to change one cell.

| screen | idle CPU before | after |
|---|---|---|
| **Spinners** (ten styles at once) | **16.3%** | **1.7%** |
| Progress View | 24.8% | 23.8% |

Converted the same way everything else was: the cycle is pre-rendered, one entry
per tick, and the loop splices it. A style's interval is **rounded** to a whole
number of ticks rather than resampled onto them — `.dots` runs at 0.10 s instead
of 0.11 — because every frame then lasts the same time. Resampling gives 2, 2, 3,
2, 2, 3 ticks and a visible limp for the sake of an average nobody perceives.

### The prerequisite, and the thing it found

A producer that leaves a run behind has **stopped asking to be re-rendered**.
That is the whole point, and it means a container which drops runs freezes
whatever was inside it — silently, while looking like a performance win. There is
no way to notice from outside except by watching the thing not move.

Two were dropping them:

- **`_ListCore`** built every row's lines by hand, so a row's own runs went
  nowhere. Measured with a two-frame run on each of three rows: a `VStack`
  carried 2 of 2, the `List` carried **0 of 3**. Both kinds of run now travel as
  one `RowRun` through one pipeline, because every clip, the reorder overrun and
  the overscroll slide key on the line index alone — two lists that had to be
  kept in step would drift, and a run spliced one line off repaints the row above
  or below, every tick, forever.
- **`Section`**, found by auditing all eighteen containers a spinner can sit in.
  That audit is now a standing test (`AnimatedRunPropagationTests`), for the same reason
  the failure is invisible.

Two places a run is still dropped, both deliberate:

- A List line whose content is **truncated for a badge**, after which a column no
  longer means what the child said it meant.
- Every line of a **breathing cursor row**, whose pulse repaints the whole line
  and would overwrite a narrower run on it. There the list **takes over the
  asking** on the dropped run's behalf, so a spinner on the cursor row costs
  exactly what every spinner used to, and only while the cursor is on its row.

A cycle whose frames differ in width cannot be a run at all — every frame must
occupy the cells the run claims — so a mixed-width `.custom(_:)` falls back to
asking for a re-render.

## §15 — The clock stops being a grid, and the last producer converts

A run's frames were indexed by TICK, and a tick was 0.05 s everywhere, so every
animation had to be resampled onto that grid. That forces a choice with no good
side — `.dots` wants 0.110 s a frame, so it either limps (2, 2, 3, 2, 2, 3
ticks) or changes speed — and it caps everything at 20 Hz however precise the
producer's own timing was.

A run now carries its own `frameDuration`, and the loop wakes on whatever mix is
on screen: `timeUntilChange(afterElapsed:)` answers in **seconds**, the loop
takes the soonest across every live run and sleeps exactly that long.
`AnimationClock.tickInterval` now means only what it should have — how often to
re-render a view that reads the phase *as it renders* and so cannot say what it
would draw next.

Two guards, both earned. A 10 ms floor on any frame duration. And
`timeUntilChange` computes from the frame's own end rather than with
`truncatingRemainder`, which is not exact in binary: `0.1 % 0.05` is 0.049999…,
so at every exact frame boundary the answer was one ulp short of a whole frame —
~1e-17, i.e. a spinning run loop, at the moment the loop is most likely to ask.

**Follow-up, 2026-09-12: the floor that replaced it had the same flaw, one level up.**
The frame's end was computed from `floor(elapsed / frameDuration)` in seconds, and the
clock's `elapsed` is a SUM of the sleeps it credited. Seven 0.05 s sleeps add to one ulp
under 0.35, so the floor picked the step before the one due — at every step from 6 to 12
of the grid, and at the literal `0.35 / 0.05` too — and the time to its already-passed
end was ~1e-17 again, raised to the 10 ms floor. A steady 350 ms blink became plans of
0.35 → 0.01 → 0.34 s, which with the timer's one-wake-stale sleep gave holds of ~370,
~700 and ~45 ms. Steps and ends are now counted in whole nanoseconds by one conversion,
`AnimationClock.step(atElapsed:frameDuration:)`, shared by the run index, the time to
change and `CursorTimer`'s tick count — and, since 2026-09-13, by the frame a `Spinner`
draws itself, which had kept its own seconds floor and drew the frame before the one its
run replays at steps 27–40 of a summed `.dots` clock. Measured on a focused field over 22 s: 17 of 53
holds within 350 ± 40 ms before, 54 of 54 after. The timer's other half — it slept on the
plan made one wake earlier, because the loop re-planned only after serving the tick —
is fixed beside it by planning at the wake (`CursorTimer.planner`); after both, 53 of 53
holds, 366–377 ms.

**Follow-up, 2026-09-13: those holds were long because the clock was slow.** A 350 ms
half held 366–377 ms because each wake credited the sleep it asked for, not the time that
passed, and every wake is several milliseconds late — a `Task.sleep` resumed on the main
actor overshoots by a median of 6–13 ms. The whole clock ran slow by `1 + N·L` for `N`
wakes a second of lateness `L`: 5–7% on the focused field above, 1.48× on the Spinners page. The
clock now reads `MonotonicClock` at every wake and every render, so a half is 350 ms of
wall clock, give or take one wake's lateness; the commit that made the change carries the
measurements.

### The indeterminate progress bar

The last live-clock producer, and the most expensive: it read `Date()` while
rendering, so `_ProgressViewCore` asked for **30 frames a second**.

| Progress View page | idle CPU |
|---|---|
| before | 24.2% |
| after | **2.8%** |
| bytes/s | 11,457 → 10,076 |

Determinate bars are untouched and were already free — their value is the
caller's data and they never animated.

**The cycle is memoised, and that is the feature rather than an optimisation.**
A 36-cell `.gradient` cycle is 72 frames of ~840 bytes. This measured **45.3%**
first — nearly double what it replaced — because
`StateStorage.storage(for:default:)` does not mark an identity active, so the
entry was swept every render pass and the cache built to build the cycle once
built it every time. One `markActive` is the difference between 45.3% and 2.8%.

That is the general shape for any large cycle, and the rule worth remembering:
**a long run costs at the producing end only.** Replay is O(width) per tick
whatever the length — `frame(atIndex:)` is an array index — so frames are cheap
to replay and expensive to build. Build them once.

### And the demo that was free-riding

`ProgressViewPage.animatedFraction()` read `Date()` at render time and moved only
because the indeterminate bars were forcing renders. Converting them froze it,
while leaving it looking correct in any screenshot. The same trick sat in
`TrackStyleEditor`.

Both now own their data — `@State` advanced by a `.task` — and advance at **the
data's rate, not a frame rate**. A first version at 10 Hz drew nine identical
screens out of ten and cost 11.5%; at the rate the value actually changes (1%
every half-second) it is 4.7%. The 1.9 points over a frozen bar is what honestly
showing a moving determinate bar costs.

**Nothing named in this file as an open live-clock producer is still open.** A
sweep of every remaining one — wall-clock reads, every `requestAnimation` caller,
every render-time read of the clock through the environment — found three, none
of them the scrollbar:

| producer | measured | verdict |
|---|---|---|
| `NotificationHostModifier.startAnimationTask` | 42 Hz full renders, **24–26% of a core** for the 3.5 s a toast is up; ~126 of ~147 frames byte-identical | Not a run: a toast appears and vanishes, and a run loops. Sleep to the next phase boundary instead — the opacity is a flat 1.0 for the whole visible duration. |
| `_TextEditorCore` caret | 20 Hz full renders, **6.7–7.0% of a core** at 120×40, against 0.2% for a focused `TextField` | Convert. `computeCursorCycle` is the converted twin; `computeCursorState` sets `usesCursor`, which kills replay for **every other run on the page**, not just its own. |
| `TextEditor.appendScrollbar` | zero today, but only because the caret above forces renders | Convert **with** the caret. Fix the caret alone and this bar freezes while looking correct. |

### The TextEditor pair, converted

Both, in one change, for the reason the table gives. Re-measured the same way
the row above was measured — the Example's Text Input page at 120×40, the
editor focused by clicking it, the caret set to blink, CPU over a quiet 6 s
window:

| | before | after |
|---|---|---|
| editor focused, blinking caret | **6.7%** of a core, 117 bytes/s | **0.2%**, 127 bytes/s |
| the `TextField` above it, for scale | 0.2%, 138 bytes/s | unchanged |

The output rate is the tell in both directions: it barely moved, because the
caret was always emitting about a hundred bytes a second. What changed is what
it cost to produce them. The editor now costs what the field costs, which is
what it should always have cost — same caret, same blink, same clock.

Verified in a PTY rather than only in test, by sampling every cell of the screen
over three seconds and reporting the ones that took more than one value:

- plain editor, block caret, blink → **one** cell moved, alternating between the
  character punched out of the caret block and the character on the field
  surface;
- bar/underscore caret, pulse → the same one cell, through ten tones;
- an overflowing editor → **five** cells: the caret, and the four scrollbar
  cells its thumb covers.

Nothing else on the page moved in any of the three, which is the property the
CPU number is a proxy for.

Two things came out of the doing.

**The multi-line geometry was not the obstacle.** The caret's row is
`cursorLine − scrollLine` and its column is the display column the row walk
already computes for tab expansion — the row returns where in itself the caret
landed and the loop, which knows which row it is, shifts it. That is the same
shape `TextFieldContentRenderer.FieldContent` has carried all along.

**The caret's cells are now drawn by the very code the field's are.** The editor
had its own copy of the shape switch — block punches the character out,
underscore underlines it, bar takes the first cell — which is how one
`.textCursor(_:)` setting came to mean two slightly different things. It calls
`TextFieldContentRenderer.caretFrames` now, and `computeCursorState`, whose last
caller this was, is deleted. One deliberate behaviour change comes with it: a
block caret punches its character out in the editor's own field surface rather
than the page background, which is what the field does and what the shared
code says.

## 40. The row pipeline's paper cuts, and the harness's own foreign string (2026-08-25)

A wide pass with fresh Time Profiler traces of ten scenario shapes. Six
commits shipped and one experiment reverted; every shipped change is
byte-identical by bench checksum, and every number below is a paired
`ab_bench.py` A/B (12 reps, CPU-per-frame) measured for that change alone, in
commit order, on clean builds.

**The trailing-padding clip (megalist −44.4% [−45.1, −43.9], kitchensink
−20.7%).** The List's scrollbar compose assembles every visible row line one
cell wider than its slot — `renderPlainLine`'s guaranteed right-padding space
meets the bar column that takes the cell back — and `fitted()` re-cut every
line with the escape-aware forward walk, per line, per frame, to remove the
one trailing space the assembly had just added. On megalist that walk was
21.9% of the frame inclusive and 48.6% of self time sat in the tiny
allocator's region detach/reattach/madvise churn, largely those string
rebuilds. `ansiAwarePrefix(visibleCount:knownVisibleWidth:)` now drops the
excess bytes when they are entirely trailing plain spaces — O(excess), a
vectorised re-scan guarding the equivalence (an escape's intermediate space
byte cannot slip through), the exact walk as fallback. Also wired into
`FrameBuffer.clamped` and `trimmingTrailingBlankCells`, the other two shapes
that clip assembled-over-wide lines.

**The harness's own foreign string (scrollfollow −11.7%, dashboard −9.0%,
churn −5.9%, ten more scenarios −0.7% to −3.7%).** The Stress harness's
`Lf()` substituted its placeholders with `replacingOccurrences`, which
returns an NSString-backed string — and every scenario rebuilds its heading
through it every frame, so the wrap memo hashed a foreign string through NFC
normalisation per lookup and character walks detoured through `objc_msgSend`
(6.3% of a scrollfollow frame matched the foreign machinery). The stdlib's
`replacing(_:with:)` is native. Same class as the textwall synthesis fix (4f67aea1),
and the same moral: that much of every earlier bench was measuring
Foundation's bridging, not the framework. (The framework's own localization
tables were checked with an `isContiguousUTF8` probe: already native on
current Foundation, whose JSONSerialization decodes to native Swift
strings.)

**Rows built for nobody (kitchensink −6.2% [−6.8, −5.9]).** The windowed
List's row thunk ran `content(element)` — the app's row builder — for every
visible row on every frame, then `_MemoizedRow` served the cached buffer and
discarded the view: §38's defect, one layer down. The thunk now uses the
deferred `_MemoizedRow` form, with one new piece — the badge peek needs a
BUILT view, so `viewTypeCarriesBadge(_:)` answers from the row's static type
(only a `.badge(_:)`-outermost row can carry one) and badge-less rows skip
the build entirely. kitchensink's rows are built inline in the ForEach
closure, which is exactly the shape that paid; megalist's rows are a
two-field struct whose cost lives in `body`, so its gain was small (−0.8%).
`ListRowBuildDeferralTests` pins a warm frame to zero builder invocations.

**The per-row environment write (megalist −2.4%, kitchensink −2.5%,
dashboard −1.2%).** Stamping `listRowEditIndex` into the environment copied
the whole copy-on-write `[ObjectIdentifier: Any]` storage — every entry
rehashed, reboxed, retained — once per visible row per frame, to record one
Int. The index now rides the `RowEditRestrictions` collector the environment
already carries once per List per frame; rows render strictly one at a time,
so the single slot cannot be observed with a neighbour's value.

**The fit memo (table-multiline −60.2% [−60.4, −60.0]; 1720 → 683 µs/frame).**
`fitMeasured` memoized its wrap and re-ran everything after it on every call:
the maxLines fold — `foldRemainder`, a character-by-character re-walk of the
source ending in a `replacingOccurrences` regex — plus the per-line
truncation. A multi-line Table asks it for every visible cell AND for every
cell the scrollbar's extent estimator samples, every frame: `fit` was 50.8% of
the frame, `foldRemainder` alone 19.4%. The fit now has its own memo beside
the wrap's, consulted only for line-LIMITED calls — without `maxLines` the
fold cannot run, and memoizing those anyway measured +1% on scenarios that
never fold.

**The estimator's sample (table-multiline −29.8% [−30.3, −29.4]; 711 → 499
µs/frame, on top of the fit memo).** The same trace showed the scrollbar's
extent estimator still asking 64 sample rows for their heights every frame, to
re-derive a mean that cannot change while the layout holds — and asking costs
a wrap per column (Table) or a full row materialisation (List). The mean is
now stashed on the `ItemListHandler` against a signature of everything that
shapes a row height, and re-derived only when that misses.

### 40.1 The experiment that did not ship, and what it cost to learn

A scrollbar's cells are also a pure function of their inputs, and a steady bar
rebuilds an identical ~40-cell string set every frame — 7.7% of a megalist
frame. Memoizing it looked like the same move as the two above, and the first
sweep was encouraging (megalist −3.4%, preferences −7.4%, anyview −5.5%,
modifiers −5.1%) with one ugly outlier: **scrollfollow +12.2%**. A scrolling
bar's key changes every frame, so every frame was a guaranteed miss plus a
store, flushing the cache on a cycle. Admission control — store only on the
second consecutive miss of the same key — fixed scrollfollow exactly (−0.1%,
indistinguishable) and kept every other number.

Except `fanout`, which read +4.4%, +7.4% and +11.1% across three sweeps
against a ±6% null floor. The memo's own work is a dictionary probe against a
12-field key: ~0.002% of a 5 ms frame. It cannot move that scenario 11%, so
either the number was noise or the mechanism was indirect. The decisive test
was to build the same code storing nothing at all: **fanout still read +11.5%,
and preferences still read −7.1%, anyview −4.9%.** The wins and the loss alike
survived the cache being inert — so none of them were the memo. Splitting one
function into a cached wrapper and an uncached implementation had changed
inlining, and *that* moved every one of those numbers.

The change was reverted. Two lessons worth more than the commit would have
been: **a plausible mechanism plus a matching measurement is still not
attribution** — the ±5% "wins" on scenarios that barely draw a scrollbar were
the tell, and they read as corroboration until they were tested; and **the
cheapest way to test attribution is to neuter the mechanism, not to re-run the
benchmark.** A memo that stores nothing should measure as nothing.

Disciplines this pass leaned on. **Attribution sweeps**: each change was
measured at its own boundary, on clean builds, after a joint sweep proved
un-attributable — and after a busy-box sweep flagged three ±1% "slower"
verdicts that a null test (the binary against itself) reproduced as the
machine's floor. **The stale-build rule extends to internal types**: adding a
stored property to a same-module class still earned a clean rebuild before its
bench binary was trusted. And the section above: **neuter the mechanism to
test attribution**.

## 41. Two string sites, and a struct that would not shrink (2026-08-25, later)

A second pass over the post-§40 profile, with fresh traces of the six
most expensive scenarios. Two commits shipped; one experiment reverted, and
the reverted one is the interesting half.

**The bordered line (deep −10.1% [−10.6, −9.9]).**
`BorderRenderer.contentLine` assembled every bordered content line as
`vertical + styledContent + ANSIRenderer.reset + vertical`, over a
`content + String(repeating:)` pad: a five-link `+` chain, each link
allocating. It runs per content line per container per frame, and down a
nested spine each level re-borders the lines below it, so the count is
O(depth²). On `deep` that was `String.+` at 14.2% of the frame (13.3% of it
under `_ContainerViewCore.renderToBuffer`, which the helper inlines into),
over `_allocateStringStorage` 13.9% and `_swift_allocObject_` 15.2%. The
unstyled case — nearly every line — now reserves the exact byte count once
and appends the five pieces. Byte-identical by construction.

**The shared spaces run (anyview −11.4% [−12.7, −9.6]).** `asciiSpaces(n)`
exists to hand out padding with no allocation, and it did — but produced the
slice with `run.prefix(n)`, and `Collection.prefix` advances an index n
places, which on a `String` is a GRAPHEME walk: one Unicode break query per
space, per call. The allocation was gone; the scan replacing it was not. It
is the most-called helper on the render path, and it showed as
`String.index(_:offsetBy:limitedBy:)` under `Collection.prefix` at 2.9% of a
`deep` frame, purely to re-derive an offset into a run of spaces that never
changes. Every index into the run is now computed once into a table, so the
slice is a subscript.

Cumulative for the two, clean build against clean build: `anyview` −12.0%,
`deep` −11.8%, `tables-scroll` −4.5%, `framedcolumns` −2.9%, `preferences`
−2.6%, `textwall`/`table` −2.2%, `table-multiline` −1.9%, `scrollfollow`
−1.8%, `customlayout` −1.4%, `megalist` −1.2%, `tables-vstack` −0.9%.
Nothing slower.

### 41.1 The struct that would not shrink, and a benchmark that lied

`ChildView` is built and copied per child per pass, and its own comment
records a stride step (96→112) that once cost `churn` ~16%. It measures
**105 bytes / 112 stride** today, so shrinking it looked like free money:
`childIndex` `Int`→`Int32` and `spacerMinLength` `Int?`→`Int32`-with-sentinel
took it to 88/88, a 21% cut in per-child copy bytes.

It measured **`churn` +10.4%**, everything else flat. A smaller struct with
the same job should not be slower, and that suspicion is what unpicked it:

1. **The A/B compared build states, not code.** The baseline binary was an
   incremental build; the variant came after a `swift package clean`. This
   project's own rule says never to trust incremental output across a
   stored-property layout change — and the proof arrived unprompted, when a
   later incremental binary **SIGSEGV'd** on `customlayout` mid-sweep, the
   documented signature of a mixed-layout build. Rebuilt clean on both
   sides, the same change read **+4.3%**, not +10.4%.
2. **The floor was higher than assumed.** A null test — the clean binary
   against *itself*, 24 reps — read `churn` +0.5% [−0.9, **+3.7**] and
   flagged `fanout` +2.0% as "slower". On a box this busy the tool can
   produce a false slower verdict at exactly the size being chased, so
   +4.3% is barely outside its own noise.
3. **The change was never "smaller, otherwise identical".** Shrinking
   required turning a stored property into a computed one (a branch and a
   conversion on every read) and `Int`→`Int32` (conversions at every
   construction and every `childContext`). `churn` rebuilds every
   `ChildView` every frame, so that is a coherent mechanism for a small
   real cost. And the genuinely behaviour-identical version — a pure field
   REORDER — measures **108/112**: no shrink at all. There is no free
   variant of this change to test.

Dropped, with the reason corrected: not "smaller is slower", but "the only
available way to make it smaller pays per access what it saves per copy,
and the net is somewhere between nothing and a small loss".

Three rules came out of it, all cheap to follow: **clean-build both sides
whenever a stored-property layout changes**; **run the null test on the
specific scenario making the claim, at the same rep count**, because the
floor is per-scenario and per-day; and **check the change is actually the
one being described** — this one had two accessors' worth of new work
hiding inside "just make it smaller".

## 42. The image paths — spelling, searching, copying (2026-09-04)

A pass over `ImageHarness` (Mode A′, `Tools/Profiling/README.md`) after the
image and gradient work of early September, in release and debug, base and
new binaries run back to back on an idle machine. Every change is
byte-identical by the harness checksum and the image suites. Four commits.

**The glyph renderer spent its frame spelling colours.** Instruments on
`--path glyph --mode truecolor` (120×50 cells, 1,500 iterations): 97.9% of
the frame inside `convertHalfBlocksColor`, 59.9% of it in
`foregroundColorCode` and 41.9% in `backgroundColorCode` — three escape
strings interpolated per cell, compared, and mostly discarded. The leaves
were `_StringGuts.append` 8.4% self, `_SmallString.init(appending:)` 4.5%,
`_int64ToString` 3.6%, the tiny allocator's malloc/free 15% between them,
and 9.1% inclusive in `__isPlatformVersionAtLeast`, String's availability
checks on macOS. 790 ns a cell for a mode that searches no palette at all.
`ANSIRowBuilder` decides each cell's colour as a `Color` through one
resolver, compares enums, and writes a change as bytes with a three-digit
formatter, one `String` per row.

| glyph, ns/cell (release) | before | after |
|---|---|---|
| truecolor | 768 | 93 |
| ansi16 | 142 | 65 |
| grayscale | 120 | 38 |
| shades8 | 495 | 63 |
| ansi256 | 742 | 513 |
| shades256 | 1,510 | 606 |

**Then the search was the frame** for the two large palettes. The
per-pixel path had long avoided the 240-entry walk with a quantisation
table and paid in exactness (a percent of near-boundary pixels take a
neighbour, §"Image palette mapping"); the per-cell path was built to be
exact and walked. `ASCIIPalette.SearchIndex` lists, per cell of the same
5-bit perceptual grid, the entries that can be nearest to some colour in it
— a triangle-inequality bound off the cell's centre and radius — so the
search is the walk over a few candidates and the answer is the walk's,
tie-break included. Palettes over sixteen entries use it; the table's
boundary fallback uses it too.

| ns per unit (release) | before | after |
|---|---|---|
| glyph ansi256 | 749 | 112 |
| glyph shades256 | 1,486 | 252 |
| glyph adaptive 64 | 832 | 360 |
| glyph adaptive 256 | 2,252 | 1,092 |
| pixel adaptive 64 | 63 | 34 |

Debug moved further, because the walk's cost there was an unspecialised
call per entry: glyph ansi256 9,038 → 1,780 ns a cell.

**The copy that had always been there.** Adding the index gave
`ASCIIPalette` a fourth reference, and the `.ansi256` pixel path — which
never searches — went from 14.0 to 18.8 ns a pixel. `quantizePixel`
switched on the colour mode per pixel and `case .palette(let palette)`
copied the palette out of the payload, every reference retained and
released, a million times a picture. A first rewrite put the resolved
pieces in an enum of their own and matched THAT per pixel: 2.7× slower
still (three arrays and the palette bound per pixel). `PixelQuantiser`
keeps its pieces as plain stored properties and runs both loops — the
straight quantise and the error-diffusing dither — over the pixel buffer and
the tables through pointers taken once, with the palette bound once outside
the loop (a `guard let` inside it cost the dithered path +31% until it was
hoisted). Cumulative on the pixel path, base against the final binary:

| pixel, ns/pixel (release) | before | after |
|---|---|---|
| truecolor | 9.4 | 8.2 |
| ansi256 | 12.7 | 10.5 |
| ansi16 | 19.8 | 17.8 |
| shades8 | 17.1 | 15.4 |
| adaptive 64 | 62.9 | 34.3 |
| ansi256 + Floyd–Steinberg | 21.4 | 19.8 |
| ansi16 + Floyd–Steinberg | 39.0 | 38.6 |

Debug, the same path: ansi256 561 → 420, ansi16 678 → 542, shades8 652 →
519, ansi256 dithered 872 → 766.

**And one bug the rewrite found.** `RGBAImage.addError` rebuilt every
neighbour it spread error into with `RGBA(r:g:b:)`, whose alpha defaults to
opaque, so a dithered picture with transparency came out solid everywhere
the error reached — which was everywhere but the first pixel. The pixels a
graphics terminal composites over the page are exactly the ones that go
through it. Fixed at both sites, with three tests.

The lesson this pass repeats from §32 and §41: in a per-pixel loop the
arithmetic is never the cost; a `String` built to be compared, an enum
payload bound per iteration, a struct copied out of an optional — each of
those was a bigger term than the colour maths, and each was invisible until
a profile or a same-run A/B put a number beside it.


## 43. The bench was measuring a different world (2026-09-05)

Three findings from one afternoon, each one the reason the previous one had
gone unseen. Every `cpu-per-frame` number in this document before this
section was taken by a bench that differed from the app in two ways, and
the app itself was throwing its render cache away every frame in any
program whose model changes per frame.

### 43.1 `Stress --bench` ran no per-pass lifecycle, and rooted at a string

`Headless.bench` called `renderToBuffer` in a loop and nothing else. The
live loop opens every pass with `StateStorage`/`RenderCache.beginRenderPass()`
and closes it with `endRenderPass()`/`removeInactive()`; without those the
cache was never pruned — an off-screen row's size entry was a hit in the
bench and a miss in the app — and the per-pass measure memo, emptied only
in `beginRenderPass`, grew by every miss forever: 2,400 entries a frame on
`kitchensink`, millions over a profile, which put dictionary resizes and
`tiny_free_detach_region` into profiles of code that allocates nothing of
the kind. The measure-memo hit rates the bench printed (25% `fanout`, 63%
`customlayout`) were CROSS-frame hits the app never gets; with the
lifecycle they read 0–4% everywhere but `customlayout` (63%, genuinely
intra-pass).

Adding the lifecycle exposed the second divergence: `modifiers` read
**290 ms** a frame, 94% of it in `StateStorage.isRetained` →
`ViewIdentity.path.getter` → `renderPath()` → `String.+`. The bench's
`RenderContext` took the initializer's default identity,
`ViewIdentity(path: "")`, a RAW root — and for raw-rooted identities
`isAncestor(of:)` has to render both full path strings and compare
prefixes. The end-of-pass prune asks that of every retained root against
every unvisited entry. `RenderLoop` roots at `ViewIdentity(rootType:)`,
which takes the O(depth) pointer walk, so the app never paid it. The bench
now roots at a type too. (The 104 headless tests built on the default
initializer are raw-rooted as well; correct, but never profile through
them.)

Old bench → bench with lifecycle and a typed root, cpu-per-frame µs, 300
iterations, 120×40:

    megalist          503 →    508      dashboard        170 →    373
    scrollfollow      488 →    553      framedcolumns    708 →    892
    table             511 →    584      churn           1248 →   1834
    table-multiline   526 →    526      kitchensink     5430 →   6744
    tables-scroll    2646 →   2711      customlayout     389 →    422
    tables-vstack    1041 →   1011      preferences      287 →    257
    deep             2186 →  10547      gradients       3341 →  27314
    fanout           7179 →  12801      animating       1094 →   1382
    modifiers        1222 →   8908      translucent      547 →    760
    textwall         2122 →   2240      anyview         1433 →   3100

`deep` is ×4.8 and `gradients` ×8: they never had a warm cache in the app,
and the old bench's was warm by accident. **Nothing above this section is
comparable to anything below it.** The commits carry their own before/after
pairs, measured the same way on both sides, and stand.

### 43.2 The app cleared the whole render cache on every `@Observable` change

The bench, honest, still read 2–25× under the app. `idle_cpu.py` on the
live `Stress` binary under autopilot (30 Hz ticks, CPU% ÷ frame rate) put
`dashboard` at 9 ms a frame against 0.37 warm — and against **7.0 ms
`--bench --cold`**. Every scenario fitted "cold every frame plus a fixed
overhead":

    scenario     live CPU%   cold ms   warm ms
    dashboard        27.3       7.0      0.37
    modifiers        75.2      43.1      8.9
    fanout           86.5     113.3     12.8
    kitchensink      57.7      27.5      6.7
    gradients        72.5      43.3     27.3
    deep             31.5       9.5     10.5
    megalist          4.3       1.2      0.5

`TUIKIT_DEBUG_RENDER=1` on the live app said why: `CLEAR ALL (64 entries)`
on 78 of 80 frames, hit rate 8%. `Renderable.swift` evaluated every
composite body under `withObservationTracking`, and its `onChange` was
`AppState.setNeedsRenderWithCacheClear()` → `clearAll()` at the next frame.
RenderCycle.md listed that as the design. A model that changes every frame
— a clock, a progress counter, a download's byte count — made every frame
a cold render of the entire tree, and the memo machinery never served a
buffer while it did.

The tracking is per body, so the identity whose body read the value is
known at the moment the change fires. The `onChange` now calls
`renderCache.invalidateRender(for: identity)` — the same sink and scope as
a `@State` write: the identity, its ancestors, and its descendants. The
descendants are not optional: `churn`'s rows fold `tick` into their hash
inside the row closure, keyed by index, and the old bench — which never
consumed the clear flag at all — rendered a DIFFERENT checksum from the
scoped build for `churn`, `animating` and `translucent`. It had been
serving last frame's rows (§16's captured-data hole, in the harness's own
scenarios). The scoped clear reaches them through the reader's subtree.

### 43.3 The reader decides what a change costs

Scoped or not, the live numbers did not move — the affected subtree was
`StressApp/WindowGroup<RootView>`, because the shell's root body read
`clock.tick` for its footer, and the root's subtree is everything. Moved
the read into a leaf (`AutopilotStatus`), which is the rule the framework
change makes available: **read a per-frame observable in the smallest view
that needs it, never in a root or shell body.** Live, under autopilot:

    scenario     before CPU%   after CPU%
    dashboard        27.3         5.7
    kitchensink      57.7        21.7
    modifiers        75.2        31.8
    fanout           86.5        50.7
    megalist          4.3         3.0
    gradients        72.5        72.2   (reads the tick: intended)
    deep             31.5        32.0   (no memo to keep)

`dashboard`'s cache reports `hits: 24, misses: 0, clears: 0` per frame and
one `CLEAR AFFECTED by …/AutopilotStatus.1`. The bench moved the other way
for the three tick-reading scenarios (`churn` 1834 → 15631, `animating`
1382 → 9474, `translucent` 760 → 16978) because it now invalidates what the
app invalidates and draws what the app draws; those are their honest
costs, and the old ones were the cost of serving stale rows.

The Example app's ordinary pages render two to four frames in five seconds
idle — nothing ticks — so they never showed any of this. Any app with a
live model did.

## 44. Five walks of one stack, and a hug that never changes (2026-09-05, later)

With the bench honest (§43) the shape of every scroll-heavy frame was the
same: the scroll content is walked about five times — the enclosing stack's
natural-size ask, one scrollbar probe per width tried, the stack's own
layout measure inside the render, and the render — and a memo lookup per
row per walk is not free. Three changes, each measured alone against the
commit before it (`ab_bench.py`, cpu-per-frame, 6 reps):

**A stack resolves its ForEach children once per pass** (90a608df).
`resolveChildViews` ran on every walk and built a `_MemoizedRow` per
element each time: 25.8% of a `fanout` frame. `ChildViewProvider` gained
`childViewsAreWorthMemoising` (ForEach: from 16 rows) and the resolved
array is kept for the pass, keyed by identity + type + raw bytes like the
measure memo. fanout −17.8%, anyview −16.9%, textwall −14.1%, modifiers
−3.3%; dashboard +0.8% (the witness call on stacks below the threshold —
3 µs of 370).

**A memoised child carries its identity** (fef8a149). The array was shared
but each walk still derived every child's identity — a namespaced key
string and a node per child per walk. The memo key carries the parent
identity, so the child's is resolved when the entry is stored. fanout
−8.3%, anyview −4.9%, modifiers −3.9%, textwall −3.8%.

**A hugging list remembers its widest row** (32b87838). §42's measured hug
was still 62% of `kitchensink`: a content box, two closures, an identity
node and a generic instantiation per row per frame, to look up sizes that
had not changed. The answer is a size entry under the list's identity,
compared against the rows' data (`listRowsSignature`, the collection boxed
as `AnyEquatableBox`), which inherits the row memo's three invalidation
rules for free. kitchensink −60.0%.

**Measured and reverted:** size-memo entries living "by use" (a frame stamp
instead of identity marks) — indistinguishable on ten scenarios, because a
non-lazy stack renders every row every frame and marks it anyway, and the
windowed bands already mark what they sample. Recorded in the dead-ends
memory; not retried without a scenario that measures rows it never draws.

## 45. Ink is not layout, and a colour is not a parse (2026-09-05, later still)

**A paint or tint change keeps the memoized sizes below it** (477e84d6).
`clearAffected(by:)` dropped a subtree's sizes with its buffers; for the
two paint slots and the tint that is half wasted, since ink moves no
cell. `gradients` rotates its ramp every frame, so its four measure walks
re-measured 400 rows a colour cannot resize. With `keepingSizes: true` at
those three sites: gradients −7.6%, animating −0.7% — smaller than the
44% the measure walks showed, because a hit per row per walk is what
those walks cost now and the render walk is the cold half. The contract
test that pinned "the measure memo sees the change too" pinned a
mechanism on a premise no paint meets; it pins both halves now.

**Blending a translucent cell states its colour** (b0eb4e9d).
`SGRState.settingBackground` built the `ESC[…m` a colour would emit and
parsed it back in — a split and an `Int` parse per code, per cell of
every translucent overlay: 17.4% of the `translucent` frame in that one
function. `setForeground(parameters:)`/`setBackground(parameters:)`
store the parameter list outright, byte-for-byte what the parse stores,
pinned equal for every colour kind and depth. translucent −20.1%.

Landscape on HEAD after §43–45, cpu-per-frame µs (300 iterations,
120×40, honest bench): gradients ≈42200, churn ≈15300, translucent
≈13800, deep ≈10500, fanout ≈9500, animating ≈9300, modifiers ≈8100,
kitchensink ≈2750, tables-scroll ≈2630, anyview ≈2450, textwall ≈1890.

## 46. The live frame, seen whole (2026-09-05, evening)

`analyze_timeprofile.py --process` (4d0bc5b0) reads one process out of an
`xctrace record --all-processes` recording, which is the only way to
profile a PTY app on this machine — and so the first profile of the
OUTPUT half of a frame. Dashboard under autopilot, 366 ms of process time
over 8 s: the scene render was 38% of the frame; `appendVerticalScrollbar`
15.6%; `writeFrame` 18%; `beginRenderPass` + `endRenderPass` 18%;
animation-tick service 12%; `IdentityNode.rootIsRaw.getter` 2.5% self.

**An identity node knows at birth whether its root is raw** (f8fedcd0).
`isAncestor(of:)` asked `rootIsRaw` of both sides and `rootIsRaw` walked
to the root; `clearAffected` and `isRetained` ask `isAncestor` of every
entry, every frame. Stored at creation: bench kitchensink −40.2%,
dashboard −24.0%; live kitchensink −35.1%, dashboard −13.0%. The biggest
single win of the pass after the bench was made honest, from a two-line
walk the old bench could not run.

**A scroll view keeps its vertical scrollbar** (5f2bdc3c). A focused bar's
pulse runs were one scrollbar render per pulse frame, every frame. Kept on
the handler with every input they depend on: live dashboard −10.0%,
textwall −2.8%, fanout −1.2%; the bench cannot see it (nothing is focused
there).

Method note: the two were measured together first, then split with a
third binary carrying only the flag — the bench win was ALL the flag, the
live scrollbar win only the memo. Measure each change alone before
attributing either.

## 47. Seven hundred entries, all retained, each climbing to every root (2026-09-05, night)

The `TUIKIT_DEBUG_RENDER` frame line gained the prune's own counts, and on
the live dashboard they read: 64 buffers, 724 sizes, **764 unmarked, 764
retained, 0 dropped** — every frame. A memo hit at a card's root marks
nothing below it; it declares the subtree retained, and the prune then
asks of each unmarked entry whether some retained root is its ancestor,
which was one climb per root per entry. `endRenderPass` 9.7% of the
frame, `isRetained` 7.5%; `clearAffected` at the pass's start, two climbs
per entry, 7.4%.

`RetainedSubtreeIndex` (TUIkitCore) indexes the pass's roots by structural
hash once; an entry climbs its own chain once and confirms structurally
only on a hash hit. `clearAffected` puts the changed identity's chain in a
set for the "above" half. Raw-rooted identities keep the prefix walk.
Bench kitchensink −55.6% (the hug's two thousand sizes under one retained
list), dashboard −3.8%; live kitchensink −30.4%. The diff writer now also
reports rows rebuilt per frame under the same switch, for the next look
at the output half.

## 48. Widths carried, and a state that is a number (2026-09-05, late)

**The scroll window and the clamp carry the widths they know** (9769bd6d).
`strippedLength` was 10.3% of the live dashboard frame: the window padded
every visible line by scanning it, its buffer measured every line again,
and the scrollbar scanned each a third time — for lines a stack had just
padded to one width and said so. The window reads the content buffer's
`linesAreUniformWidth`/`lineWidths`, pads through a known-width overload,
and says what it knows in turn; the clamp does the same on the way in and
carries what it measured on the way out. Live dashboard −5.6%; the bench
cannot see it.

**`SGRState` is a bitmask and two small colours** (this commit). The
per-cell type under the cell diff, the overlay split, the SGR collapse and
the opacity blend held a `Set<Int>`, two `[String]`s and a `[String]`, and
`apply` split every sequence into strings. Now a `UInt16`, an enum per
colour, and a byte walk that parses parameters where they stand. Bench
translucent −10.8%; live translucent −10.3%, dashboard −5.9%. Numerals
spell canonically on the way out, which no terminal can tell apart and
no test compares.

Live dashboard after §43–48, per frame: the scene ~30%, the diff writer
~20% (`buildLine` rebuilding the rows a pulse step moved, `collapsingAdjacentSGR`
under it), animation ticks ~14%, pass begin/end ~10%.

## 49. A merge that forgot, and two searches for one reset (2026-09-05, later)

**A stack of uniform rows keeps every line's width** (52e7585b). After
§48's window learned to read widths, `strippedLength` was still 7.7% of
the live dashboard frame — the stack it read from had nothing to say.
`appendVertically` carried per-line widths only when both sides held an
array, and a uniform side holds none, so a stack of uniform rows at two
widths (every page) forgot all of them. The uniform side now spells its
widths out for the merge. The bench sees it through `placeBuffer`'s pad:
dashboard −38.7%, textwall −16.9%, kitchensink −7.3%; live textwall −5.9%.

**A background is restated after resets in one pass** (this commit).
`restoringBackground` was two generic `String.replacing` searches per
rebuilt row and per patched run — `RangeReplaceableCollection.replacing`
8.1% of the live frame. One byte walk with the two-step's exact edge
semantics (a split it creates is not re-split; an `ESC[0m` a split forms
IS restored after), pinned equal on two thousand random strings, and a
scan that returns the line untouched when it holds no `ESC[0` at all.
Bench translucent −6.0%; live translucent −8.0%, dashboard −6.7% (interval
reaching 0). A first cut without the scan read kitchensink +1.5% on the
bench — the byte copy on lines with escapes and no reset — which the scan
removed.

## 50. The verdicts shared chains already know (2026-09-05, night)

`RetainedSubtreeIndex` (§47) climbed each unmarked entry's chain once; on
the dashboard that was still 764 climbs of ten or twelve levels through
the same few hundred nodes, 11% of the live frame. The index now
remembers each ancestor's verdict by structural hash for the pass: bench
dashboard −46.9%, kitchensink −10.9%; live dashboard −7.1%. Three forms
were measured. A stamp on `IdentityNode` (no dictionary) cost `modifiers`
+9.5% with zero climbs — two more words on the node every deep chain
allocates — and is a dead end recorded in memory. The dictionary bounded
to the roots' depths halved the dashboard win. The plain dictionary
reads modifiers +4.2%, where it never runs (the bench's new prune line
says `retainedChecks: 0`); a never-called padding function in the same
file moves modifiers by −1.1% on its own, so that is placement, and it is
stated in the commit rather than smoothed over.

`Stress --bench` prints its last prune's counts now, beside the measure
memo line. The scalar-walk `collapsingAdjacentSGR` was also built and
measured this session: translucent +2.4–2.9% slower in two forms, since
Character iteration's ASCII path is already fast and the cost charged to
the collapse is the netting's string building. Reverted, recorded.

## 51. One walk per patched run, and where the pass stands (2026-09-05, closing)

**Patching an animated run walks the line once** (4b66c123). Per run,
per tick, the patch walked the line four times — the state under the
run, the width, a pad to the run's end, and the insert's own split — for
answers the split already had. `ANSIOverlaySplit` carries the column its
suffix was dropped from, `insertOverlay` takes a split the caller made,
and the run-end pad is reproduced as trailing spaces after the suffix.
1,080 outputs pinned as hashes against the four-walk form. Live dashboard
−2.8% — and only a 12 s emission window could say so: at 0.12 s of CPU
per 4 s the ordinary window is twelve clock ticks wide.

Two experiments were reverted this evening and are in the dead-ends
memory: a scalar walk for `collapsingAdjacentSGR` (translucent +2–3%,
Character iteration's ASCII path already fast) and a verdict stamp on
`IdentityNode` (modifiers +9.5% with zero climbs — two words on every
node a deep chain allocates).

**Where the pass stands.** Landscape on HEAD, cpu-per-frame µs (300
iterations, 120×40, honest bench):

    megalist          507      dashboard         83
    scrollfollow     1051      framedcolumns    901
    table             570      churn          15283
    table-multiline   532      kitchensink      595
    tables-scroll    2506      customlayout     338
    tables-vstack    1004      preferences      239
    deep            10296      gradients      36840
    fanout           9448      animating       8987
    modifiers        2789      translucent    11353
    textwall         1579      anyview         2461

Live, `idle_cpu.py` under autopilot (30 Hz ticks, CPU% over 6 s):

    dashboard      2.7%   (27.3% at §43)
    kitchensink    3.7%   (57.7%)
    modifiers     12.3%   (75.2%)
    fanout        42.3%   (86.5%)
    deep          31.2%   (31.5%)
    gradients     70.0%   (72.5%, reads the tick by design)
    megalist       2.8%   (4.3%)

Against §43's first honest reading: dashboard 373 → 83 (and 27% → 2.7%
of a core live), kitchensink 6,744 → 595, modifiers 8,908 → 2,789,
fanout 12,801 → 9,448, translucent (from §48) 13,554 → 11,353. What
remains is structural: the five walks a scroll stack makes per frame,
rows that are cold by design (`gradients`, `churn`), the deep-nesting
re-measure, and the writer's per-row netting.

## 52. A row that measured twice to place a ramp once (2026-09-05, morning after)

The structural levers §51 left were put to a panel of five investigators and
ten refuters (two per proposal: is it byte-exact, and can the bench see it).
The smallest survivor went first. Under a `.gradientExtent(.subtree)` frame,
`_HStackCore.renderClip` measured every child a **second** time — at its
final width and the row height — to learn how tall it would stand so the ramp
could place it vertically. Its layout had just measured that child (at that
width or wider, un-squeezed), and for a rigid child a height proposal of
`rowHeight` cannot change the answer: `rowHeight` is at least every measured
height unless the stack was clamped, and a clamped child reports `rowHeight`
either way, so the slack is zero in both readings. The spacer was measured
too, and handed a context nothing used. `resolvedLayout` now returns the
per-child heights it already had, plus a bitmask of which children fill
their height (the one case a height proposal changes an answer; those are
still asked), and the ramp loop reads the height back.

The first cut carried the per-child flexibility as a `[Bool]` and read
**+1.9% on `churn`** (CI +0.5…+3.3) — one more array per row per walk, on a
page with no ramp at all. A `UInt64` mask instead: same information, no
allocation. Rendered bytes are unchanged (bench checksums identical on
gradients, churn, fanout, dashboard); `.onRenderPass` now sees one
`.measure` per rigid child of a ramp'd row instead of two.

`ab_bench.py`, cpu-per-frame, 120×40, 8 reps, paired ratio with 95% CI:

    scenario        old µs     new µs   change            95% CI
    churn          15378.2    15292.2    -0.2%    -1.0% … +0.7%   indistinguishable
    gradients      37174.8    35667.9    -3.9%    -5.1% … -3.0%   faster
    dashboard         88.0       87.4    -0.9%    -1.6% … +0.6%   indistinguishable
    fanout          9680.1     9708.9    +0.1%    -0.6% … +1.1%   indistinguishable

The refuters' bound (a `Text` measure ≤ 0.8 µs, from the `churn` trace) put
the prediction at −2…4% on `gradients`; the first cut read −2.3%, the mask
−3.9%.

**What the panel left standing, for next.** The larger lever both the `deep`
and the cold-row investigations converged on is a per-pass measure memo that
can serve a size measured under one height budget to a query under another:
a `ViewSize` bit, default *dependent*, that a `sizeThatFits` clears only when
it read no height budget and no clamp bit (Text, Spacer, Divider always;
padding when its insets fit; `_VStackCore`/`_HStackCore`/`_ContainerViewCore`
when every child's bit is clear and no clamp bit), with the memo keyed on
identity + type + bytes + effective width + available width and a short
per-key list of (proposal-width nil-ness, proposal height, available height,
size) entries — exact match first, then an invariant entry whose height fits
both the query's limit and its available height. The refuters' corrections
that must go in with it: keep the proposal width's nil-ness out of the merged
key only on the invariant path (ScrollView, TextField, Slider answer nil and
specified widths differently and stay dependent); condition every rule on
height alone (a width clamp cannot make an entry height-dependent, and the
`deep` chain collapses its width to zero at level 20, which otherwise poisons
every level above); migrate the container's empty-body early return; and a
`TupleView` is measured by rendering and is never invariant. Expected: `deep`
−50…70% (the render-side re-measure of each level's tail served from the
scrollbar probe's entry), `churn`/`gradients` −20…30% (walk 4 served from
walk 3 and walk 2 from walk 1). Declined from the same panel: a prior-frame
scrollbar hint (it is a fixpoint in a different place for content that fits
at full width and wraps one more line without it — hysteresis, not the same
answer), and relaxing the uniform lazy stack's saturated report to the limit
(a rendered-output change in its own right, worth its own decision).

## 53. A size measured under one budget, answering under another (2026-09-05, afternoon)

§52 left one lever standing: a measure memo that can serve a size taken under
one vertical budget to a query made under another. It shipped, and it is the
largest single win of the pass — but almost nothing about the prediction
survived contact, so the record here is the measurement first.

**What the memo was actually doing.** A temporary probe (not committed) counted,
for every measurement stored in a pass, whether an earlier store shared its
identity, type, value bytes and width but differed in the budget. The exact memo
was serving **0–1%** of lookups on every scenario. The opportunity underneath it:

    scenario   stores/pass   same key, different budget   with the width form merged
    deep            6,642                  22.8%                        24.6%
    churn           8,516                  18.4%                        25.8%
    gradients      17,743                  28.6%                        38.9%
    fanout         10,710                   2.2%                        47.6%

and, decisively, the *pairs*: every one of them was a walk at
`(proposal.width = nil, availableHeight = 40)` followed by a walk at
`(proposal.width = 120, availableHeight = 4096)` — the enclosing column's
natural-size ask and then the ScrollView's content-extent walk, at the same
available width. So the key had to lose the vertical budget **and** the
nil-ness of the proposed width, or it would gain nothing: merging the width
form alone hit *zero* extra times on every scenario, and merging the budget
alone left `fanout`'s rows (84,000 of its 214,210 stores) unserved.

**The shape.** `MeasureKey` is now what a measurement is *of* — identity hash,
type, value bytes, effective width, available width, the two explicit flags —
and the budget moves into a one-slot `MeasureEntry` beside the size. A query
hits either exactly (same width form, same budget) or through
`ViewSize.isNaturalSize`: a flag a `sizeThatFits` sets on the size it returns to
say *no budget shaped this*. It is set by `Text`, `Spacer`, `Divider`, and by
`_HStackCore`/`_VStackCore` when every child answer they consumed set it and
their own clamp did not bite. Everything else defaults to false and is measured
as before, which is what makes the change safe by construction: `_ImageCore`'s
zoom, `_ContainerViewCore`'s chrome, `ViewThatFits`, the lazy stacks' windowed
arms and any `Layout` written outside the package all stay budget-shaped.

**Three corrections from the refuter panel, all of them load-bearing.**

1. *A container may not claim natural below the tallest answer it consumed.* A
   child's claim only reaches budgets down to its own height. `_HStackCore`
   re-measures a child squeezed narrower than its ideal and that answer can come
   back **shorter**, so the row can end up shorter than an answer it was built
   from — and would then offer itself at budgets where the child's claim had
   lapsed. Both stacks now carry the tallest consumed height and test it. (For a
   column the sum already dominates its own maximum, except at negative
   `spacing`; the test is what makes that not need thinking about.)
2. *Padding cannot be caught by a runtime test.* The first cut let a modifier
   claim natural whenever it had not shrunk the vertical budget on *this* call.
   `PaddingModifier.remaining` gives the last cell to its content, so at
   `availableHeight <= 1` the whole inset vanishes and the test reads "no
   vertical dependence" for a modifier that has plenty at any taller budget. One
   call cannot see that, and the change bought nothing measurable, so
   `ModifiedView` claims nothing.
3. *The environment leg is not pinned.* The key holds no environment
   discriminator — it never did — so two measurements of one identity under
   different environments alias. Dropping the budget widens that: calls that
   used to differ by budget can now meet. The guard is empirical (below), and a
   digest remains the fix if one is ever needed.

**The guard, and why the obvious one was not enough.**
`MeasureMemoEquivalenceTests` draws a corpus twice — memo live, memo off — and
diffs the pictures. On its own it is too weak: with `_VStackCore` deliberately
claiming natural *through* its clamp, every case still passed, because a wrong
size only redraws the screen where something draws differently for it. So the
memo also has `RenderCache.verifiesMeasureMemo` (`TUIKIT_VERIFY_MEASURE_MEMO`,
or a path to log to), which re-measures every hit and reports any the fresh
measurement disagrees with. With that on, the same mutation is caught
immediately and names itself: *served 40x10 (natural) but a fresh measure at
proposal (40, nil) in 40x4096 says 40x24*. Run over all 20 stress scenarios and
over a 35-item PTY walk of `Example`, the shipped code reports **zero**
mismatches from the natural path.

The walk did surface one mismatch, from the *exact* path, and it is
pre-existing: a `LazyVStack`'s reported width changes between two measurements
in one pass (5 then 4), because the uniform hypothesis it answers from is grown
and broken by the render in between. Confirmed pre-existing by re-running the
walk with the natural serve switched off — the same line appears. The width of
a seeded lazy stack is documented as a heuristic whose only consumer discards
it; it is noted here rather than fixed.

`ab_bench.py`, cpu-per-frame, 120×40, 15 reps, paired ratio with 95% CI, over
the POD-key commit that precedes it:

    scenario        old µs     new µs   change            95% CI
    churn          14846.4     9900.3   -33.2%   -33.9% … -32.9%   faster
    gradients      34176.9    24049.1   -29.6%   -29.8% … -29.4%   faster
    fanout          9152.8     6720.1   -26.7%   -26.9% … -26.5%   faster
    textwall        1545.7     1240.7   -19.8%   -20.3% … -19.4%   faster
    anyview         2390.6     2006.3   -16.1%   -16.5% … -15.7%   faster
    deep            9849.7     9568.4    -2.9%    -3.3% … -2.1%    faster
    modifiers       2727.6     2670.9    -2.5%    -3.8% … -1.6%    faster
    dashboard         86.8       86.6    +0.1%    -1.1% … +0.7%    indistinguishable
    megalist         496.7      498.5    +0.4%    -0.2% … +1.0%    indistinguishable

Bench checksums identical on every scenario; the suite passes (6,164 tests, 21
known issues); the PTY walk of `Example` reaches all 35 items.

The bench is not the app, so the same pair was run live —
`idle_cpu.py <binary> 2 6` with `TUIKIT_STRESS_AUTOPILOT=1`, each reading taken
twice and identical to a tenth of a percent both times:

    scenario     CPU before   CPU after   render bytes/s before → after
    churn            51.5%       36.7%          50,500 →  51,300
    gradients        66.5%       56.8%          27,700 →  36,800
    textwall          8.0%        6.8%             470 →     470

`churn` and `textwall` hold their frame rate and spend less: −27% and −15% of a
core. `gradients` reads −15% of CPU while pushing **a third more rendered bytes
through the same window** — the autopilot renders as fast as the frame allows,
so there the win shows up as frames rather than as idle.

**Where the prediction was wrong.** §52 expected `deep` −50…70% and
`churn`/`gradients` −20…30%. The second half was right and the first was not:
`deep` is a chain of clamping containers, and the probe shows its repeats
*disagree* 62% of the time — its sizes really are budget-shaped, so no rule that
preserves the pixels can serve them. What paid instead was the row-shaped
scenarios, where a whole memoised row is served at the second walk.

**Still standing.** `dashboard` and `megalist` gain nothing (their frames are
already small or window-bounded), `modifiers` gains little because a padded row
never claims natural, and the environment leg of the key is unpinned. The next
lever here is not a bigger memo: it is `_ScrollViewCore` asking for its content
extent once instead of walking a ladder.


## 54. A gradient row was cut one run at a time, and rescanned for each (2026-09-05, evening)

With §53 in, `gradients` was still the largest scenario by a factor of two
(20–24 ms/frame against 11 for the next). A `sample` of the bench put ~22% of it
in `BackgroundModifier._modify`, and inside that, `String.ansiAwareSlice` and
`String.ansiSegments` between them at 14% of the whole frame.

The reason is the shape of the call, not the work. A ramp background cuts each
row at the ramp's own colour boundaries and fills the pieces separately, and for
a smooth truecolor ramp that is **one run per column** — 120 of them on a
120-cell row. `ansiAwareSlice` rebuilds the row's entire segment list and
rescans it from the first byte on every call, so the row was walked 120 times to
be cut into 120 pieces, and 120 segment arrays were allocated to do it.

`String.ansiAwareSlicedRuns(runCount:width:receive:)` cuts at every boundary in
ONE pass. Each piece is still exactly what the slice function would return —
`ANSIRunSlicingTests` states that as its property and checks it over a corpus of
styled, hyperlinked, wide-glyph and short rows against every partition it can
make of them, rather than restating the slicing rules. The three things a cut
carries fall out of the walk's own order: the style in force at a piece is a
snapshot of the SGR seen so far, what it owes an open hyperlink is the link
scan's state as the walk leaves it, and a glyph straddling a cut blanks its
in-window cells on both sides.

Two details earned their place by measurement. The pieces are **handed over one
at a time** rather than returned in an array, and the runs are described by a
count and a width function rather than an array: the first cut of this returned
`[String]` and read **+1.7% on `kitchensink`** (CI +0.1…+2.1), where rows have
two or three runs and the six little arrays cost more than the rescans they
saved. Streamed, the same scenario is indistinguishable and `dashboard` is
0.9% faster.

`ab_bench.py`, cpu-per-frame, 120×40, 15 reps, paired ratio with 95% CI:

    scenario        old µs     new µs   change            95% CI
    gradients      23960.2    20277.8   -15.2%   -15.8% … -14.0%   faster
    dashboard         85.8       84.9    -0.9%    -1.4% … -0.2%    faster
    kitchensink      592.2      590.7    -0.5%    -1.1% … +0.5%    indistinguishable
    churn           9815.8     9745.4    -0.6%    -1.7% … +0.7%    indistinguishable
    translucent    10880.8    10950.5    +0.6%    +0.1% … +1.1%    (re-run: +1.3%, -0.3 … +1.5, indistinguishable)

Bench checksums identical on all 20 scenarios; 6,166 tests pass with 21 known
issues; the PTY walk of `Example` reaches all 35 items.

## 55. Thirty-six reflections, and the twelve percent they cost (2026-09-06)

CI fails on the menu render budget, so the menu is where this pass started. Two
corrections had to land before any number about it meant anything.

The first was the harness (df7ad91d). `RenderLoop.buildEnvironment()` stores the
palette and the appearance and stamps the terminal size and the animation clock
every frame; Mode A stored four services and nothing else. `EnvironmentValues`
has two quite different read paths — a miss is a hash and a failed probe, a hit
is that plus an `Any` unbox, a `swift_dynamicCast` and a retain when the value is
an existential — so which one you are measuring depends entirely on whether the
key is present. Seeded like an app, the menu tree's miss rate falls from 70.9% to
40.5%, because the two hottest keys stop missing altogether.

The second was reading the profile at all. Self time on this trace says
`swift_release` 6.0%, `swift_retain` 4.3%, malloc 2.8% — all true, and none of it
names anything anyone can fix. `analyze_timeprofile.py --blame` (60258a57) walks
each sample from the leaf to the first frame in our own code and credits that
instead:

    ms       %  blamed function
  1289.0     8.8  specialized AnyIterator.next()
  1193.0     8.1  EnvironmentValues.subscript.getter
   552.0     3.8  specialized static IdentityNode.structurallyEqual(_:_:)
   530.0     3.6  resolveEnvironmentProperties<A>(of:in:)
   512.0     3.5  Environment.wrappedValue.getter
   382.0     2.6  _StyleEnvironmentView.childContext(_:)
   305.0     2.1  outlined init with copy of Any
   185.0     1.3  specialized __RawDictionaryStorage.find<A>(_:hashValue:)
   151.0     1.0  ObjectIdentifier._rawHashValue(seed:)

Thirty-one percent of the frame is the environment.

### What the counters said, and why they beat the percentages

Instrumenting the subscript and the resolver directly (that instrumentation is
not committed — the `String(describing:)` histogram costs 412 µs a frame against
the 244 µs frame it measures) gives per-frame counts for the `menu` tree:

    env.read            687.0    (40.5% miss)
    env.write            46.0    mean dictionary size at write 15.6
    bindStateProperties  35.0    100% served by its negative cache — 0 Mirror walks
    resolveEnvProps      35.0    74.3% negative-cache hits -> 9 Mirror walks, 36 children

Thirty-six children a frame, costing 12.4% of it. That is ~3.4 µs per walk, and
it is the count that makes the finding: a hot spot doing thirty-six things is a
hot spot with a cheap fix, where the same percentage spread over 687 things is
not. It also refutes the obvious reading of `AnyIterator` — with 45 reflective
operations in a frame the iteration cannot be the cost, so the cost has to be
what each step *does*.

It is. Each `Mirror.children` step builds a `Child` — a String allocated for the
field's name and the field's value boxed into an `Any` — on top of the reflective
field projection.

I had a tidier story than that and the measurement killed it. The self-time
profile puts ~10% of the run in `MetadataCacheKey::operator==`, `getCache`,
`getGenericContext` and `_swift_getGenericMetadata`, and since `_MenuItemRow`'s
fields are generic (`Environment<any Palette>`, `Environment<Int?>`,
`Environment<Int>`) it was natural to read that as Mirror instantiating metadata
per field per render. Removing Mirror entirely disproves it: those symbols go
from ~1,350 ms to ~1,250 ms, and `swift_retain`/`swift_release` do not fall at
all (850→863 and 647→695, marginally UP). Whatever drives the metadata cache on
this path, it is not this. The cost that did leave is inside `AnyIterator.next()`
itself, which is specialized into the binary and does not decompose further in
the profile — so the honest claim is the measured one, and the mechanism below
the walk stays unexplained.

### One type, and it cannot help it

Every reflecting call on the menu path is `_MenuItemRow`: 3 rows x 3 renders a
frame. It has three `@Environment` properties and no way to avoid them —
`ButtonStyle.makeBody` composes views and is handed no render context, so the
palette has to come from the environment. Any user-written `ButtonStyle` has the
same shape, which makes this the general path rather than a quirk of the menu.
The `_*Core` advice in CLAUDE.md — read the environment off `RenderContext` —
does not reach a style's body, because a style's body has no context to read.

### Key paths, because a key path outlives the instance

`Mirror` yields a *value*, which is useless on the next render of a freshly
constructed view. A key path is an accessor, so it can be found once per type and
kept. `resolveEnvironmentProperties` now memoizes each view type into one of
three buckets, checked in descending order of how often each answers:

    typesWithoutEnvironment  Set        74% of calls on this tree; a Set test, forever
    resolvablePaths          [AnyKeyPath]   found once, applied per render
    typesNeedingMirror       Set        the fallback, also memoized

The third bucket matters more than it looks. The first cut of this did not have
it: when `_forEachFieldWithKeyPath` declined a type, nothing was cached, so that
type paid a refused key-path walk *and* a Mirror walk on every render. That is
strictly more work than before, and the Stress sweep caught it as `deep` +1.6%
(CI +0.9…+2.4, verdict "slower") — the only scenario in that sweep that moved at
all.

### Numbers

Mode A, paired, order randomised per rep, 9 reps of 12,000 renders:

    tree        old µs/frame  new µs/frame   change  reps faster
    menu             264.2         234.2    -11.6%      9/9
    form             243.3         240.8     -1.7%      5/9
    memoRows          51.7          50.8     -1.6%      6/9
    paneled          191.7         189.2     -0.9%      7/9
    nested/stackRows/frames  —          —     +0.0%    2-3/9
    list             253.3         255.8     +0.7%      4/9
    alignment         91.7          94.2     +0.9%      3/9

Only the `menu` row is a result. `/usr/bin/time -p` reports hundredths of a
second, which over 12,000 iterations quantises every figure to 0.83 µs/frame —
visibly, since they are all multiples of it — so every other row is at or below
the instrument's resolution and none of them is being claimed.

Whole-run on-CPU for 60,000 renders of the same tree: **14,687 ms -> 13,245 ms**,
-9.8%, consistent with the paired figure. In the blame table `AnyIterator.next()`
disappears entirely and the new key-path apply, `resolve(_:of:in:)`, enters at
4.6% / 612 ms — so 1,819 ms of reflection became ~612 ms of key-path
application.

6,166 tests in 869 suites pass with 21 known issues, unchanged. Cross-compiles
to `aarch64-swift-linux-musl` on the 6.3.3 static SDK, so the SPI import travels.

### The blind spot this exposed

`ab_bench.py` across all 17 default scenarios reports "indistinguishable"
everywhere. That is not a null result about the change; it is a null result about
the sweep. `grep` finds no `Menu` and no `ButtonStyle` in any of the 20 Stress
scenarios, so not one of them contains a type that reflects. The benchmark set
has no coverage of the shape CI's failing test is made of.

### The dependency this takes on

`_forEachFieldWithKeyPath` is the only way to get key paths for a type's stored
properties, and it is `@_spi(Reflection)` rather than public API. Three things
make that acceptable here and they should be re-checked if any of them stops
being true: the `Mirror` path is retained and correct for anything the walk
refuses, so a future removal degrades to today's behaviour rather than breaking;
the whole change is one file; and the nightly-toolchain CI lanes are where SPI
breakage would surface first.

**Superseded by §58:** the first of those was never true on Xcode. Apple's SDKs
build `Swift` from its public interface, which carries no SPI, so this did not
compile with Xcode's toolchain at all and has been taken back out.

## 56. A button was drawn to be measured, and drawn again to be seen (2026-09-06, later)

§55 optimised the hottest thing on the menu path. This one asks the question that
should have come first: how much work is the frame doing at all?

    renderToBuffer  130.0/frame     measureChild  65.0/frame     memo hits 2.0
    _ButtonCore      9 render /  6 measure        (5 visits per button)
    _MenuItemRow     9 render /  0 measure
    Text            10 render /  9 measure

**195 view visits to draw three menu rows.** `_ButtonCore` is 69.4% of the frame
inclusive, and it is entered nine times for three buttons.

The reason is one line. `_ButtonCore.sizeThatFits` was
`measureFixedByRendering(self, ...)` — so **every measure of a button renders the
whole button** (style body, HStack, frames, text, cells) and keeps a width and a
height. Two-pass layout measures a stack's children before rendering them, so a
plain button is drawn twice a frame; inside a menu, which takes a hug measure of
the whole column first, three times.

### What it was worth

Caching each button's size across frames in the Mode A harness — exact there,
since it renders one unchanging tree — with every checksum unchanged:

    tree        old µs/frame  new µs/frame   change   reps
    menu             230.0         118.3    -48.4%    9/9
    paneled          187.5         129.2    -31.1%    9/9
    form             231.7         210.8     -9.0%    9/9
    (the six trees with no buttons)          +-0.7%   noise

### Why that cache was not the change

The same cache, emptied at the start of every pass, recovers **nothing**: `menu`
-0.4%, `paneled` -0.9%, reps split near evenly. Within one frame a button is
never measured twice at the same width — the asks are genuinely different
questions, and `_ButtonCore`'s within-pass repeats agree 0% of the time. So the
whole 48% was CROSS-frame, which is the variant whose failure mode is a stale
size and silently wrong layout. (A probe on `framedcolumns` did say 1,604 asks,
99.8% would hit, 0 would be wrong — but keyed on identity and widths only, and
that scenario never changes a button's label, so it is not a clearance.)

### The change: ask a cheaper question, not an older one

`ButtonStyle.makeBuffer` is `renderToBuffer(makeBody(configuration:), context:)`
and it lives in an **extension, not a protocol requirement** — so no style can
override it, and every style's buffer is its body's buffer. `_ButtonCore` then
appends a hit-test region to that buffer and never a cell. So the body's size IS
the button's size, and the way to ask for a size is `measureChild`.

`ButtonStyle.makeSize(configuration:proposal:context:)` sits beside `makeBuffer`
so `Body` stays concrete: erasing it to `AnyView` to measure would change the
answer, because a flexible child measures to the full available width through
`AnyView`. `_ButtonCore` now shares one `resolve(context:)` between both passes,
because the two must reach an identical `ButtonStyleConfiguration` — same focus,
same hover, same resolved shortcut, whose hint the row prints and which a measure
that missed it would size too narrow for the render to fit.

No cache, no key, no invalidation, nothing to go stale.

### The gate, which the first cut did not have

Ungated this was `menu` -12.1% but `paneled` **+1.3%, 0 of 9 reps faster** — a
real regression, and mine: `sizeThatFits` resolved the configuration, then the
procedural fallback rendered the button and resolved it again. Gated on
`Body.self is any Layoutable.Type`, a procedural body takes exactly its old path:

    tree        old µs/frame  new µs/frame   change   reps
    menu             231.7         199.2    -14.0%    9/9
    nested           260.8         255.0     -2.8%    8/9
    paneled          187.5         188.3     +0.4%    4/9
    (everything else within +-1.6%, reps split)

`_MenuItemButtonStyle` wins because `_MenuItemRowBar` answers `sizeThatFits` with
`measureChild(row)` and paints nothing. `DefaultButtonStyle` does not, because
`_ButtonStyleBody` is `Renderable` with no `Layoutable`.

### What was left on the table, deliberately

The other ~34 points of the 48% are `_ButtonStyleBody`, which computes its chrome
widths and label fitting procedurally. Giving it a hand-written `sizeThatFits`
would put one sizing rule in two places, and two copies of a rule drift — the
`List`/`Table` divergence this codebase already has scars from — with wrong
layout, not a crash, as the failure. Rendering to measure is the honest answer
there until the arithmetic itself is factored out to a single owner.

### An aside worth recording

The per-pass measure memo serves **6.2%** of lookups on `framedcolumns`, **1.1%**
on `kitchensink`, **11.7%** on `churn`. Its key includes `viewValueHash`, which
is `withUnsafeBytes(of: view)` — so any view holding a closure or a property
wrapper hashes differently on every construction, and every `Button` and every
`@State` view is invisible to it. Measured, two instances held alive at once:
plain `let x: Int` STABLE; one `@Environment` UNSTABLE; one `@State` UNSTABLE;
`Button("x") {}` UNSTABLE.

Verification: 6,166 tests in 869 suites pass with 21 known issues, unchanged; all
nine Mode A checksums identical; `Stress --selfcheck` renders all 20 scenarios;
`swiftlint --strict` clean.

---

## 57. A lock taken twelve thousand times to be handed the same object (2026-09-09)

§42 made the per-cell search exact and cheap, and left two things in the
per-cell loop that do not belong there. `cellColor(for:mode:)` switched on
`ASCIIColorMode` per cell, so `case .palette(let palette)` copied the palette
out of the enum payload — `colors`, `byTone`, `entries` and `search`, each
retained and released — and then `ASCIIPalette.nearestIndex(to:)` read
`searchIndex`, a computed property that takes the handle's `NSLock` on every
read. The default charset (`.blocks(.fine)`) calls `cellColor` **twice a cell**,
so a 120×50 half-block conversion took 12,000 payload copies and 12,000
uncontended locks to be handed the same index 12,000 times.

`CellColours` is the per-cell twin of §42's `PixelQuantiser`: a colour mode
resolved once per conversion into what the loop asks of it — a payload-free
kind, the palette as a plain stored property, and its search index resolved
once through the new `ASCIIPalette.consultedSearchIndex`. Each of the six
renderers builds one and asks it per cell.

`ImageHarness`, release, 120×50, six alternating pairs per mode with a
discarded warm-up, medians (base and new alternate order pair by pair — the
first ordering measured base always-first and gave it the cold cache, reading
−18.0% for the same change):

| glyph, ns/cell | base | new | |
|---|---|---|---|
| **ansi256** | **87.6** [86.6–89.3] | **71.6** [70.6–72.1] | **−18.3%** |
| ansi16 | 60.7 [60.0–61.5] | 59.6 [58.8–60.3] | −2.0% |
| shades8 | 52.1 [50.9–53.2] | 51.7 [51.0–52.5] | −0.9% |
| truecolor | 79.0 [78.0–79.9] | 77.4 [76.8–78.2] | −2.0% |
| grayscale | 33.1 [32.9–33.9] | 32.4 [32.3–32.7] | −2.3% |

Every checksum identical, mode for mode.

**The decomposition is in the table**, which is why those modes were run.
`ansi16` has sixteen entries, so it short-circuits before `searchIndex` and
never took the lock: its −2.0% is the payload copy alone. `truecolor` and
`grayscale` bind no palette at all, and still move about −2% — because even
they switched on the payload-carrying enum per cell, and now switch on a
payload-free `Kind`. So of `ansi256`'s 16 ns a cell, roughly 2 is the enum,
another 2 or so the payload, and the remaining ~12 the lock. `shades8` is the
canary rather than a subject: `consultedSearchIndex` gates on the entry count
*before* touching `searchIndex`, so an eight-entry palette still builds no
index, and its −0.9% says the gate held. Had that gate been missing it would
have built 32,768 cells of candidate lists and gone sharply the other way.

**The base is not §42's base.** That table reads ansi256 112, ansi16 65,
truecolor 93, grayscale 38; this one starts at 87.6, 60.7, 79.0, 33.1, because
`9348de75` and `5d9e7006` moved the resample and unsharp geometry underneath on
2026-09-08. Measured in this session rather than carried forward, per the rule
§31 was written for.

**What this does not touch**, stated so the ceiling is not mistaken for the
floor: the remaining ~72 ns of an `ansi256` cell is `Color.oklab` (three table
loads and three `cbrt` per call) and the candidate walk inside
`SearchIndex.nearestIndex`. Neither is addressed here.

### The pixel half, measured and reverted

P13 staged a second commit doing the same hoist inside `PixelQuantiser` — the
distrusted-cell fallback and both dither arms. It is a wash, and its own
pre-registered prediction said it would be ("commit 2 is a wash and gets
reverted"). Five alternating pairs per case, checksums identical throughout:

| pixel, ns/pixel | before | after | |
|---|---|---|---|
| ansi256 + Floyd–Steinberg | 17.15 | 17.13 | −0.1% |
| ansi256 | 7.11 | 7.25 | **+2.0%** |
| ansi16 + Floyd–Steinberg | 35.69 | 36.13 | +1.2% |
| ansi16 | 14.74 | 14.25 | −3.3% |
| shades8 + Floyd–Steinberg | 85.48 | 84.73 | −0.9% |
| shades8 | 12.95 | 12.57 | −2.9% |
| truecolor | 5.61 | 5.60 | −0.2% |

Movement in both directions with no mechanism behind either sign, which is the
signature to revert on rather than to bank the favourable half of. `ansi16` and
`shades8` have sixteen entries or fewer, so they never read `searchIndex` and
there is no lock in them to remove — a −3% there cannot be this change. And the
one case with a real mechanism, `ansi256 + Floyd–Steinberg` over a 240-entry
palette, is the one that did not move: the quantisation table answers almost
every pixel, so the fallback that takes the lock fires for the few percent near
a cell boundary and there was never per-pixel lock traffic to remove. The
glyph path had 12,000 locks a conversion because it has no table.

The asymmetry is the finding: **a table upstream of a lock makes the lock
unmeasurable**, and the per-cell path is fast now for the same reason the
per-pixel path always was.

This was **P13** of the 2026-09-09 batch, declined that day rather than
measured: its staged patch had drifted under the greyscale fix (`5631fde3`
replaced an inline luminance expression with `greyRampStep(for:)`, and the
patch would have silently put the old expression back), and its measurement
plan named two harness modes — `shades256` and `optimal64` — that
`ImageHarness` does not accept. Both were the reason to re-derive rather than
apply, and both were real.

## 58. The key paths §55 cached were never visible to Xcode (2026-09-14)

§55 swapped the per-render `Mirror` walk in `resolveEnvironmentProperties` for
key paths found once with the standard library's `_forEachFieldWithKeyPath`.
It named the risk: the function is `@_spi(Reflection)`. A removal would only
fall back to `Mirror`, it said, and the nightly lanes would catch any break
first. Neither held. Nothing was removed and no nightly moved. Xcode's own
toolchain has never been able to see the function.

### What the compiler says

Xcode 26.3's toolchain (`swiftlang-6.2.4.1.4`, MacOSX26.2 SDK) fails
`TUIkitView` in **debug** as well as release:

    EnvironmentProperty.swift:7:2: warning: '@_spi' import of 'Swift' will not
      include any SPI symbols; 'Swift' was built from the public interface at
      …/MacOSX26.2.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface
    EnvironmentProperty.swift:261:18: error: cannot find '_forEachFieldWithKeyPath' in scope

The warning is the whole explanation. That SDK's `Swift.swiftmodule` holds a
`.swiftinterface` per architecture and nothing else. There is no
`.private.swiftinterface` and no binary module, and the public interface has
no `@_spi` declaration in it at all (`grep -c @_spi` finds 0). The Command Line
Tools SDKs on this machine (14, 14.5, 15, 15.5) are laid out the same way. The
symbol itself is present: it is in the SDK's `libswiftCore.tbd` and exported
from `/usr/lib/swift/libswiftCore.dylib`. Only the declaration is withheld.

swift.org toolchains ship their own stdlib, with the private interface and a
binary module. That covers the swiftly 6.3.3 toolchain every local build and
gate here has been using, and the static-Linux and WASI SDKs as well. All of
them compile the call. That is why nothing noticed. **So this was not a Swift
6.2 incompatibility.** swiftly 6.3.3 compiles the call against the same Xcode
SDK. The split is Xcode's toolchain against swift.org's, whatever the version.

Minimal repro, `swiftc -typecheck`:

    @_spi(Reflection) import Swift
    struct S { var a = 1; var b = "x" }
    @available(macOS 11.3, *)
    func walk() -> Bool { _forEachFieldWithKeyPath(of: S.self) { _, _ in true } }

Xcode 26.3's toolchain fails with the error above. swiftly 6.3.3 against the
same SDK is clean, with or without `-O`.

**CI never saw it.** `ee3d422f` is not on `origin/main`. Once pushed, both
released macOS lanes would have failed at `TUIkitView`: they run Xcode 26's
`swift` on `macos-15` and `macos-26`. That holds for `macos-26`'s Xcode 26.6
only if its SDK is laid out like 26.3's, which is inferred and not checked.
The two snapshot lanes use swift.org toolchains and would have passed. So would
Linux, Windows and WASI. So would any package consumer building with
swift.org's toolchain, and no consumer building in Xcode.

### Why not keep it where it compiles

- No `#if` asks whether SPI is visible. `canImport(Darwin)` stands in for
  "Apple SDK", and it also turns the fast path off in swift.org macOS builds,
  which can compile it. It would leave the key-path branch compiled only on
  Linux, Windows and WASI, which is code this machine never type-checks.
- `@_silgen_name` onto the exported symbol means spelling the signature without
  its types. Its `options` parameter is `_EachFieldOptions`, a stdlib struct
  that is not `@frozen`, so library evolution passes it indirectly. Faking that
  is an ABI guess.
- No public API yields the key path of a stored property.

So `resolveEnvironmentProperties` goes back to its form before §55: a
per-type negative memo, then a `Mirror` walk for any type that has
`@Environment` properties.

### What that costs now

§55's −11.6% came from `_MenuItemRow`, and on the `menu` tree it was the only
view that reflected. Later on 2026-09-06, `8284610a` removed that row's
`@Environment` properties: its parent is `Renderable` and passes the three
values in. So the win's main customer had already gone before this change.

`ab_bench.py`, full sweep, 15 reps, the release `Stress` at `c33f8054` against
this change, both built with swiftly 6.3.3 (load 2.76):

    scenario        old µs    new µs   change   95% CI          verdict
    menus           2061.0    2045.2    -0.8%   -1.4% … +0.5%   indistinguishable
    kitchensink      468.9     474.8    -0.2%   -1.4% … +1.8%   indistinguishable
    deep           13747.6   13728.8    +0.0%   -0.7% … +0.7%   indistinguishable
    fanout          4180.0    4230.7    +1.1%   +0.1% … +2.0%   slower
    gradients      15310.3   15400.8    +1.2%   +0.4% … +3.6%   slower
    (the other 15)                              all indistinguishable

The two "slower" rows did not survive a second look. With the old binary run
against a byte-identical copy of itself, at 15 reps, the floor was
`fanout` +0.3% [-0.8, +1.2] and `gradients` +0.2% [-0.4, +0.5]. Old against new
again at 30 reps gave `fanout` +0.4% [-0.6, +1.2] and `gradients` -0.3%
[-0.7, +0.2], both indistinguishable. Neither scenario names a view type that
declares `@Environment`, and a type with none takes the same `Set` test before
and after. So no scenario in the sweep is being claimed to move. That is a
statement about today's sweep, not about reflection being free: a view that
does declare `@Environment` pays a `Mirror` walk per render again, as it did
before §55. §55 measured that walk at about 3.4 µs.

## 59. Every animation on the 1/60 s grid, and what it cost or saved (2026-09-14)

The owner's rule: every animation frame is a whole number of 1/60 s ticks, at
least one and, for a framework default, at least two, and the defaults are
chosen so that animations running together change on shared instants. A
terminal's paint ends up on a 60 Hz display, and a frame length that display
cannot hold judders and costs writes nobody sees. 25 ms, the lattice the
indicator-speed work had landed in `e9ff5b8c`, is 40 Hz and beats against 60.

This section is the record of that series: 30 commits from `cc88795c` to
`0da36bbb`, one of them a compiler workaround (`a37c2348`), measured end to
end. The work follows the owner's rule, not a profile, so it quotes
measurements rather than `analyze_timeprofile.py`.

### What changed

- **One time model.** `AnimationClock.nanoseconds(atTick: k)` is ⌈k·10⁹/60⌉ and
  `tick(atNanoseconds:)` is ⌊t·60/10⁹⌋, an exact inverse pair, so a wake at a
  tick's instant reads that tick. A run carries a whole `frameTicks` and its
  boundaries are tick instants computed from the step index, never
  accumulated (`9a54a38a`, `df46c96a`, `41a2bcc1`). Before, runs of 7 and 5
  ticks changed at 583,333,335 and 583,333,331 ns, and the loop woke twice for
  what is one instant.
- **Defaults on the lattice.** Spinner frames moved to the nearest whole tick,
  {5, 6, 7, 8, 9} (largest change −7.4%, `f857c2c1`). Bars keep 2-tick frames
  and their passes; a barberPole is 4 states of 9 ticks, 150 ms a cell
  (`0c31f337`, `b23b8177`, `f8dd0b54`). The blink half (21), breath (16 × 3),
  readers and `AnimationCycle` steps (3) were already whole ticks.
- **Grids on the lattice.** View animations and a drag's lift and return sample
  on a 2-tick lattice (`7d99c796`), drag auto-scroll on 3 (`2cc946e6`), a held
  scrollbar arrow on 4 (`2d81e417`), a toast's fade on 2-tick instants
  (`7d9d5bf9`), and `TimelineView(.animation)` on its tick lattice
  (`f7f87342`). The scheduler's frequency lock went with the last frequency
  request (`2ab97e64`).
- **Speeds in ticks.** `IndicatorAnimationSpeed.frameTicks(standard:)` and the
  ramp layout choose whole ticks; a tolerance may only move a sequence onto a
  frame divisible by 2 or 3, and `.automatic`'s ±0.05 moves no standard
  duration (`cc72219e`). The timer's shortest sleep ends at the next tick
  instant instead of 10 ms on (`6ffc0751`).
- **The Example shows it.** The Spinners page counts overrides and lists
  durations in ticks, with a model of instants on tick counts (`87ead7a9`,
  `5d63ff2f`); the ProgressView page picks its indeterminate catalogue's speed
  and width (`0da36bbb`).

### The bound, and the models

Every planned change instant of every framework animation is now
`nanoseconds(atTick: k)` on the content clock, so any mix of them plans at most
60 distinct instants a second. The bound is on PLANNED instants: the cursor
timer's task, the loop's scheduler wait and the notification task are separate
wakers, and replays are written without the frame pacer, so one planned
instant can still cost two writes. The measurements below are the evidence,
not the model.

Models of planned instants a second, from the design's scripts (outside the
repo); they are models, not measurements:

    screen                                      before   after
    Spinners page, 17 rows                      46.0     31.4
    Spinners + caret blink + breath             50.9     36.0
    ProgressView page, six 36-cell bars         30.0     33.3
    … with a focused breath                     50.0*    40.0
    Forms (breath 3, blink 21)                  20.0     20.0
    Every default at once (kitchen sink)        —        46.3

\* 50.0 distinct nanosecond instants, since the old 33,333,333 ns bar
boundaries never met 50 ms ones; about 40 wakes once boundaries a few
nanoseconds apart merge.

The ProgressView page's rise is the barberPole: its 9-tick steps are not
multiples of the other bars' 2 ticks. Before, it stepped on the same frames as
the other bars and, at 36 cells, stood still (`0c31f337`).

### Measured

Release builds of `37aa9b97`, the parent of `f857c2c1` (the first commit to
move a default), and of `0da36bbb`, each in its own tree, built with swiftly's
Swift 6.2.4, on macOS 15.7 / arm64. Three runs each of
`Tools/Profiling/idle_cpu.py BIN 3 10 --page P --wakeups`, the two binaries
alternating, then `Tools/Profiling/animation_rate.py BIN 12` on the spinners
and progress pages.

    spinners        before runs            median   after runs             median
    CPU %           4.4   3.6   4.2        4.2      3.3   3.3   3.5        3.3
    bytes/s         21636 21529 21561      21561    22552 22270 22058      22270
    bursts/s        37.5  37.0  36.4       37.0     30.6  30.2  29.8       30.2
    idle wakeups/s  32.3  31.6  32.6       32.3     26.2  25.4  27.2       26.2

    progress        before runs            median   after runs             median
    CPU %           11.6  9.8   9.6        9.8      12.5  12.9  12.3       12.5
    bytes/s         31376 31425 31290      31376    31435 31698 31768      31698
    bursts/s        32.4  32.8  32.4       32.4     32.8  32.5  33.0       32.8
    idle wakeups/s  28.2  27.8  27.8       27.8     30.0  30.2  30.6       30.2

    forms           before runs            median   after runs             median
    CPU %           0.9   0.8   0.9        0.9      0.9   0.7   0.8        0.8
    bytes/s         221   221   221        221      221   219   219        219
    bursts/s        10.0  10.0  10.0       10.0     10.0  9.9   9.9        9.9
    idle wakeups/s  9.0   8.8   8.8        8.8      7.9   8.5   9.1        8.5

**Spinners.** Bursts fell from 37.0 a second to 30.2 (−18%), idle wakeups from
32.3 to 26.2 (−19%), and CPU from 4.2% to 3.3%. The model's fall is larger,
46.0 planned instants to 31.4, because before, a wake that arrived a few
milliseconds late already served boundaries a few milliseconds apart, so the
loop never woke 46 times a second. Afterwards bursts sit just under the model.
Bytes rose 3.3%, with the same glyph changes: 1,570 against 1,565 in 12 s over
the 15 named rows. That rise is not explained here.

`animation_rate.py` shows each row stepping at its own frame. Before, dots and
dancingLine stepped at 109.9 ms, line at 140.1, column and bar at 80.5-80.6,
earth at 149.3, and the 120, 125 and 130 ms styles at 122.8-125.3, where
`.automatic` had moved them onto 125 ms. After, the 7-tick styles step at
116.4-116.9 ms, the 8-tick at 132.5 (box 130.3), column and bar at 83.9, and
earth at 150.1: a median ratio to the nominal of 0.998 over 16 named rows
(min 0.923, max 1.007). The minimum is `clock`, whose faces pyte measures at the
wrong width (see the script's docstring).

**Progress.** The model has planned instants rising 11%, from 30.0 to 33.3, and
idle wakeups rose 8.6%. The CPU rise did not hold. A second round of three
alternating runs, with a third binary at `f7f87342` (before either Example
commit, so without the page's new pickers), gave:

    progress        37aa9b97            f7f87342            0da36bbb
    CPU %           11.1  9.3  11.0     3.8  10.2 12.9      9.2  11.3 10.5
    bursts/s        31.6  31.9 33.4     35.4 32.5 34.1      32.6 32.4 32.4
    idle wakeups/s  28.3  27.4 28.9     8.4  30.8 30.7      29.5 28.7 28.2

The medians there are 11.0%, 10.2% and 10.5% CPU, and idle wakeups of 28.3
before against 28.7 after (+1.4%). The page's CPU moves by more than the change
from run to run, so no difference is claimed, and `0da36bbb`, with the page's
new pickers, reads no higher than `f7f87342`. One `f7f87342` run read 3.8% with
8.4 idle wakeups a second, unlike every other run of the page; it is left in.

`animation_rate.py --page progress` names no rows (the labels are on the left),
so they are identified by position. The barberPole row went from 38 changes in
12 s (a median of 47.9 ms, the glitches of a pattern that stood still at 36
cells) to 82 changes at 150.0 ms, one cell each 9 ticks. The sweep row held at
269 and 268 changes (39.2 and 39.3 ms), the knightRider row went from 371
changes at 33.7 ms to 346 at 33.2, and the Indeterminate section's bars stepped
358 and 356 times (34.0 and 32.7 ms).

**Forms.** Unchanged within the spread, as the model predicts: 10.0 bursts a
second before and 9.9 after, and 8.8 and 8.5 idle wakeups.

### What was left

- Separate wakers and unpaced replays, the source of extra writes per planned
  instant.
- A List's dropped-run wake uses the next step rather than the next change.
- Elapsed time is a `Double`; the round trip to nanoseconds is exact below
  2^51 ns, about 26 days of uptime. Past that a wake exactly on a tick instant
  may read the tick before.
- Example and Stress timers still sleep relative durations, among them the
  Mouse page's 90 ms poof, an Example animation off the grid.


## 60. A memo key that named an address it did not own (2026-09-20)

§53 moved the vertical budget out of `MeasureKey` and left five fields: the identity's
structural hash, the view's type, two widths, and the raw bytes of the view struct. The
bytes are the only field that tells two siblings apart, and for an `AnyView` the bytes are
a pointer to a heap box.

**A pointer names a value only while that value is alive.** Free the box and ask for
another, and the allocator hands back the address it has just taken — doing exactly its
job. The two views are then one key, and the memo answers the second question with the
first one's answer.

Five lines reproduce it, against a context shaped like the render loop's:

```swift
for label in ["aaaa", "bbbbbbbbbbbb"] {
    widths.append(measureChild(AnyView(Text(label)), proposal: .init(width: nil, height: nil),
                               context: context).width)
}
// widths == [4, 4]
```

With both views alive at once it reads `[4, 12]`, which is the control and the whole
mechanism: nothing is wrong with either measurement, only with the address one of them was
filed under.

**The live instance.** `_FormLayout.pillarWidth` measures every field LABEL to find the
column they align to, and measures them all at the form's OWN identity — so identity, type
and both widths are equal across the rows and the bytes decide. `TUIKIT_VERIFY_MEASURE_MEMO`
over `tui_walk`'s 35-page sweep of the Example reported 9 mismatches on one run and 19 on
the next, every one of them an `AnyView`, every one on the natural arm, all under the Form
page's `Section`. Sizes of 4, 5, 6, 7, 8 and 15 cells served for one another.

**The fix.** `viewValueHash` asks an `AnyView` for a hash of its CONTENT, opened back to
its concrete type, with that type's `ObjectIdentifier` mixed in — the key's own `viewType`
field says `AnyView` for every erased view, so without the type a `Text` and a `Divider`
whose structs happened to hold the same bytes would still be one key. Nested erasure
recurses through the same gate.

After: **0 mismatches** over the same sweep.

**What it cost, and the shape of the measurement.** `ab_bench.py`, cpu-per-frame, 120x40,
25 reps, paired ratio with 95% CI, null-tested first at ±0.5%:

    scenario      old µs     new µs   change           95% CI
    deep         13743.3    13867.0    +0.9%    +0.5% … +1.3%   slower
    modifiers     1899.9     1873.3    -1.2%    -1.7% … -1.0%   faster
    anyview       1378.0     1362.5    -1.0%    -1.5% … -0.8%   faster
    fanout        4257.2     4157.6    -2.0%    -2.3% … -1.7%   faster

Moves in both directions, so the interesting number is not in that table. The memo's own
counters over 200 frames say it is doing the SAME work: `fanout` 804,002 hits of 1,636,211
lookups before and after, `anyview` 151,123 of 412,086, `modifiers` 794 of 347,811 — bit
for bit. `deep` is the only one that changes, 162,823 hits to 162,423 of 1,971,810, and
those 400 are exactly the wrong ones. A fix that removes 400 false hits in 1.97 million
lookups does not make three scenarios 1–2% faster, so the spread is code layout and the
verdicts should be read as "no mechanism found", not as a win and a regression.

**Two shapes that did not survive measurement**, both of which read cheaper than the one
that shipped:

- `V.self == AnyView.self` in place of the static witness: `deep` +2.7%, `modifiers` +4.6%.
- Hoisting the byte loop into a second generic function so the gate could `return` it: a
  further point on top of the witness version.

`measureChild` is generic and public, so a caller in another module does not specialise it;
what it reads off `V` there is a witness-table access, and the cheapest-reading shapes are
not the cheapest-running ones.

**The residual.** A view that STORES an `AnyView` — `Toggle.label`, `Button.labelView`,
`TabContent.content`, the style configurations — holds that address in its own bytes, and
nothing about the outer type says so. `MeasureMemoErasedIdentityTests` carries a guard for
it; I could not make it alias, and the mechanism is unchanged, so it is a guard and not a
regression test. What the whole finding retires is the `valueHash` doc comment's old claim
that a value collision "cannot serve a wrong answer" because the key also carries identity,
type and widths. Siblings measured at one identity have all three in common.
