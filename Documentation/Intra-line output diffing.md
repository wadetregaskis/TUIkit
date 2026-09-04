# Intra-line output diffing

Shrinking the byte stream written to the terminal by updating only the changed
*cells* of a changed row, rather than rewriting the whole row.

**Status: shipped.** This note was written as a design sketch for a deferred
optimisation, and kept its "parked" recommendation for a while on the strength
of one measurement — a blinking text cursor, where the win was real but small.
That measurement was of the wrong gesture. What follows is the case that
changed the answer, what was built, and the sharp edges, which were all real and
one of which was worse than the sketch expected.

## What line-level diffing already does

`FrameDiffWriter.buildOutputLines(…reusingFor:)` builds the new frame (reusing
unchanged rows, commit 96357b13), then `computeChangedRows` compares each new
line to the previous frame's and writes only the rows that differ — each as a
whole line:

```
move-to-(row,1)  +  bgCode + ESC[2K + content + padding + reset
```

For a still page with one spinner on it, that is the whole answer: one row
written, not fifty.

## The case that changed the answer

It is a poor answer for a gesture that disturbs **many rows a little**. Dragging
a `NavigationSplitView` divider moves a boundary and shifts two panes, and at
140×42 in a release build, measured by capturing the PTY byte stream and
replaying it through a terminal model:

| per drag frame | |
|---|---|
| bytes emitted | **10,747** |
| rows rewritten | 27.9 of 42 |
| cells written | 3,906 |
| **cells that actually changed** | **393** of 5,880 |
| bytes per genuinely changed cell | **27.3** |

Ten times the cells written as changed. And that number is the frame rate,
because writes to a terminal block: the app renders exactly as fast as the
terminal absorbs bytes, so `fps = drain rate ÷ bytes per frame`. A user watching
a divider stutter is watching this table.

The blinking-cursor case the original sketch measured (144 bytes → ~35) was
correct and beside the point: it is a 4× on a number already small enough not to
matter. The drag is a 2–3× on a number that is the whole cost of the gesture.

## What was built

`String.ansiCellDiff(replacing:width:mergingGapsUpTo:)` in `TUIkitCore` returns
one of three answers for a row:

- `identical` — the two rows paint the same cells in the same styling. Not the
  same as the strings being equal: two escape spellings can land the terminal in
  the same place, and that row then needs nothing written at all.
- `spans([ANSICellSpan])` — rewrite these runs, in this order, and nothing else.
- `wholeLine` — column accounting cannot be trusted here; write it the old way.

`ANSIRowCells` is the row taken apart into one entry per visible **column**,
carrying the character drawn there and the netted `SGRState` in force. It is
public so `FrameDiffWriter` can decompose each row **once**: the row this frame
diffs as "new" is the row the next frame diffs as "previous".

### Comparing cells, not text

The comparison is the pair `(character, netted SGR)` per column. A pulsing
cursor or a hover tint changes no character at all, so a text diff reports the
rows identical; a byte diff reports a difference without being able to say
where. Only a cell comparison answers the question the writer is actually
asking.

### Merging gaps

Closing a run and opening another costs a cursor move plus a restatement of
styling — call it twenty bytes — so bridging a short gap of unchanged cells is
cheaper than skipping it. Measured over the drag:

| gap | cells written | spans | est. bytes |
|---|---|---|---|
| 0 | 393 | 75.6 | 2,971 |
| 4 | 411 | 59.9 | 2,628 |
| **8** | **454** | **53.1** | **2,577** |
| 16 | 492 | 50.1 | 2,606 |
| unbounded (one span per row) | 1,285 | 27.9 | 4,232 |

Flat from about 4 to about 16; `FrameDiffWriter.spanMergeGap` is 8, in the
middle of the flat stretch. Note the last row: a plain prefix/suffix trim — one
span per row — leaves more than half the available win on the table.

## The sharp edges

The sketch listed five. All were real. The fourth was worse than described, and
finding that out took a probe rather than a proof.

1. **A style-only change moves no character.** Handled by comparing cells (see
   above), not by any string operation.
2. **Both prefix and suffix must be trimmed.** Handled — and then some, since
   spans go further than a single middle slice.
3. **The SGR state at the write column must be re-established.** Each span opens
   by stating its styling; spans within a row are written back to back with only
   cursor moves between them, and a cursor move is not styling, so the second
   and later spans open with a *delta* from where the previous one left the
   terminal (``SGRState/rendered(changingFrom:)``). The same argument extends
   from one row to the next — see "Carrying state across rows" below — so the
   reset that stops a row's styling leaking is owed once per PASS rather than
   once per row.
4. **It conflicts with the emoji compensation — and more besides.** The sketch
   said to gate on `!isAppleTerminal`, because Terminal.app's compensation
   injects `CUF` sequences and a cursor move destroys column accounting. That is
   true, and it is not the whole problem.

   A whole-row rewrite **re-anchors at column 1 every time.** A terminal that
   advances a glyph differently from our claim therefore corrupts only that row,
   and only until it next changes. A span write has no anchor: it trusts our
   column count to say where the cursor goes, so a disagreement puts the span in
   the wrong place *and the row never recovers*. Every divergence in
   `Terminal-compatibility.md` has exactly this shape — a 2-cell claim meeting a
   1-cell advance (bare pictographs, lone regional indicators, SF-Symbol PUA
   glyphs, the VS-15 chrome glyphs, skin-tone clusters).

   So the gate is not per-host but **per-row, and stricter**: a row is declined
   if it carries any character claiming more than one cell, any cursor-moving
   escape, or an erase anywhere but the head — and two more things the code
   enforces that this sentence used to omit: any scalar that is not its own
   grapheme cluster (`Character.isStandaloneClusterScalar` — every combining
   mark, so a DECOMPOSED accented row, Hebrew with points or an image
   placeholder row bails even though each claims one cell; the row is walked
   scalar by scalar without segmenting, which is what makes it cheap), and
   any string-family introducer (OSC, DCS, APC). Precomposed single-cell
   characters have no such disagreement — box drawing, accented Latin in NFC,
   Greek and Cyrillic advance one everywhere — so the ordinary row still takes
   the fast path, on every host, including hosts whose advance model has never
   been measured. The
   Example's emoji page, which exists to demonstrate these divergences, takes
   the whole-line path on every row that demonstrates one.
5. **Correctness exposure is high — it needs a corpus, not just unit tests.**
   Agreed, and there are three layers:
   - `Tests/TUIkitCoreTests/CellSpanDiffTests.swift` grades the plan against an
     independent reference terminal: paint the previous row, apply the plan, and
     the screen must equal painting the new row outright. Hand-picked cases
     (cursor blink at each edge, style-only changes, a wide-emoji row, a
     whole-row shift, content shrinking, a CUF row, attribute on/off) plus 600
     seeded random pairs.
   - A PTY sweep drives twelve gestures across the Example — the divider drag,
     list and table scrolling, the theme page, the emoji page, text input, menus
     — against two builds, one with the span path forced off, and compares the
     reconstructed screens cell for cell. All twelve identical.
   - The standing `tui_walk.py` render-lint walk and the `Stress --selfcheck`
     scenarios.

   **A note on the sweep, because it cost an hour.** Feeding a terminal model in
   arrival-sized chunks splits multi-byte sequences at different offsets for
   each build, and `pyte` gets some of those wrong — which shows up as a
   difference between builds that the bytes do not have. Two of the sweep's
   early "failures" were this. Capture the whole stream and replay it in one
   go; then, and only then, is a difference a difference.

## Results

Measured at 140×42, release, over a divider drag, against the whole-line path
with every other optimisation of the same pass already in place:

| | bytes/frame | CPU/frame |
|---|---|---|
| whole-line | 9,135 | 7.0 ms |
| spans | **3,931** | 7.9 ms |

2.3× fewer bytes for 0.9 ms of CPU, and the trade is the right way round: the
CPU is not the constraint (23% of one core during the drag) and the bytes are.
Against the same drag before this pass began — whole-line writes and absolute
SGR restatement — it is 10,620 → 3,931, a **2.7×** cut.

The decomposition cache is worth about a third of the added CPU (8.4 ms → 7.9
ms) and is safe by construction: every entry carries the exact string it was
built from, so a stale one is impossible — anything that changes what is on
screen behind the cache's back (an animation replay patching a row, a rebuild, a
resize) simply misses and decomposes again.

`table`, `kitchensink`, `deep` and `textwall` are indistinguishable in the
paired A/B, which is the expected result: those scenarios measure the render
path, and this is a change to the write path.

## Fewer style transitions per row

The section below used to be "what is left", and the honest lever it named —
fewer style transitions per row — turned out to be the largest single win of the
whole exercise, and to sit one level LEFT of everything above. Not in the diff
at all: in the row builder, where the bytes are first written down.

### Where the bytes actually went

`drive.py --dump` and `analyze_stream.py` (commit 8316c653) split the stream
three ways. Over a divider drag at 140×42:

```
total             256,343
cells              48,201  ( 18.8%)
SGR               177,423  ( 69.2%)  17,367 escapes
cursor/erase       30,719  ( 12.0%)  3,874 escapes
```

Sixty-nine per cent styling, and one change of styling per 2.8 cells drawn. The
histogram says why:

| count | share | escape |
|---|---|---|
| 4,187 | 24.1% | `ESC[39m` |
| 2,646 | 15.2% | `ESC[38;5;22m` |
| 1,922 | 11.1% | `ESC[38;5;22;48;5;16m` |

The most frequent escape in the whole stream turns the foreground back to the
terminal's default; the second turns the same green straight back on. That is a
label, some padding, another label — and the padding is not green either way.

Worth noting what the analyser did **not** find: an escape that changes nothing
at all appeared once in the entire capture. The waste was not repetition. Every
one of those escapes was individually necessary *given where the renderer had
left the terminal*, which makes it a question about the renderer, not a peephole
pass over its output.

### The rule

Most of what SGR expresses is a property of a **glyph**, and a cell holding a
space has none. Bold, dim, italic, conceal and the foreground colour are all
unobservable on one. What a blank cell can show is its background, and the
attributes that put ink on an empty cell: underline, strikethrough, blink, and
reverse — which makes the foreground the colour the cell is painted, and so
brings the foreground back into the comparison whenever one of them is in force.

`SGRState.paintsBlankCellsIdentically(to:)` is that rule, and
`collapsingAdjacentSGR()` applies it: a state change whose only difference is
invisible on a space is **held** while the row prints spaces, and paid at the
first cell that can show it — by which time the row has usually changed its mind
and nothing needs emitting at all.

It is exact for the same reason the rest of that function is: nothing observed
the intermediate state.

### How far left this can go

The question this answers is whether such escapes can be *prevented* rather
than cleaned up afterwards. Three positions:

| where | what it would take |
|---|---|
| the diff (`ANSIRowCells`) | already there, and it only ever sees rows written incrementally — a full repaint bypasses it entirely |
| **the row builder (`collapsingAdjacentSGR`)** | **one function, one rule; catches every row, whole-line and span alike** |
| the renderer (`ANSIRenderer.render`) | a render-layer rewrite plus a public API break |

The last one is the true "never emit it in the first place", and the reason it
is not taken is worth writing down. `ANSIRenderer.render` returns
`sequence + text + reset` because the `String` it returns is **context-free**:
it knows neither what precedes it nor what follows, and 151 call sites
concatenate the results freely. Everything downstream is repair —
`applyPersistentBackground`, `applyPersistentDim`,
`FrameBuffer.restating(_:afterResetsIn:)`, and the `replacing(reset, …)` in
`FrameDiffWriter.buildLine` — four implementations of the same workaround, which
compose multiplicatively when nested. Fixing it at source means carrying a cell
grid rather than `lines: [String]`, which is read in 52 files across 145
references with 65 `FrameBuffer(lines:)` constructions.

The row builder is the last point at which the whole row is known and the first
at which it is known *completely*, which is why it is the right place — and it
gets essentially all of the available win without touching the API.

### Results

Median of five runs each, 140×42, release, against the whole pass before it:

| scenario | before | after | |
|---|---|---|---|
| `splitdrag` | 257,987 | **189,366** | −26.6% |
| `table` | 92,172 | **72,988** | −20.8% |
| `scroll` | 55,319 | **45,760** | −17.3% |
| `list` | 25,029 | **23,978** | −4.2% |

SGR escapes over the drag fell from 17,367 to 8,562 and SGR bytes from 177,423
to 107,841 — a 39% cut in styling, and 27% of everything written.

The rendered screens were compared cell by cell across ten scenarios, comparing
what a viewer can SEE rather than what the styling says, against a measured
run-to-run noise floor for each. Identical everywhere.

**A second pyte artefact, and it is not the one already documented above.**
`pyte` loses everything after a VS-16 emoji when the emoji and the text arrive
in the same `draw()` chunk. Moving an escape from one side of `🖥️` to the other
therefore changes what pyte believes is on screen, and the app is not involved.
It showed up as 26 and 37 stably-different cells on two pages — stable across
runs, which is exactly what a real bug looks like. Strip `U+FE0F` from both
streams before replaying: it is pyte's bug, and neutralising it identically
keeps the comparison about the app.

## Carrying state across rows

Listed above as "not obviously worth the coupling", on the strength of a guess
that it was worth a few hundred bytes a frame. Measured, it is worth 14.6% of
the `scroll` scenario, and the coupling turned out to be two lines.

The argument is the one already used *within* a row, extended: `writeDiff`
writes rows in ascending order with nothing between them but cursor moves, and a
cursor move is not styling. So the first span of row N+1 can open with a delta
from wherever row N's last span left the terminal, exactly as the second span of
a row does.

`ANSIRowCells.diff(replacing:mergingGapsUpTo:continuing:)` takes the running
state and hands it back; `ANSICellDiff.closingStyling(from:)` is what a caller
planning ONE row in isolation uses to close its own chain, and
`String.ansiCellDiff(replacing:width:mergingGapsUpTo:)` keeps doing exactly that
so its contract is unchanged.

Two places owe the terminal a reset, and both are the coupling:

- **Before a row written whole.** A built row opens by stating its *background*,
  not by resetting, so a bold or a reverse carried into it would still be in
  force — and the `ESC[2K` the row opens with would erase under it.
- **At the end of the pass**, before the loop that erases rows the previous
  frame had and this one does not. `ESC[2K` clears with the background in force,
  and the last row painted must not choose the colour of a row it is not
  painting.

| scenario | without carry | with carry | |
|---|---|---|---|
| `scroll` | 52,994 | **45,264** | −14.6% |
| `list` | 24,398 | **23,947** | −1.8% |
| `table` | 73,275 | 73,485 | +0.3% |
| `splitdrag` | — | — | no change |

`splitdrag` and `table` are unchanged because their rows are written whole,
which is the honest shape of this win: it is worth having exactly where the span
path is doing the work.

## Carrying state across PASSES

The section above stops at the pass boundary, and named the reason: two places
owe the terminal a reset, one of them "at the end of the pass". That second one
turned out to be a statement about the erase loop and nothing else — and the
erase loop runs only when the previous frame had more rows than this one, which
is almost never.

So the closing reset moved inside that `if`, and `FrameDiffWriter.terminalStyle`
carries what the pass left in force to the next one. Nothing happens between
them: the loop writes app header, content and status bar inside one
`beginFrame`/`endFrame`, flushes once, and then waits for input. The boundary is
a cursor move, and a cursor move is not styling — the same argument as within a
row and between rows, taken one step further.

What it removes is the most stereotyped pair in the stream. Measured on a slider
drag before the change: of 608 SGR escapes, 228 were a bare `ESC[0m` and 213
more were `0;`-prefixed restatements — a state the terminal had been in a
moment earlier, torn down and rebuilt across a cursor move.

    ESC[29;95H '1' ESC[0m   ESC[29;4H ESC[0;38;5;40;48;5;16m '▉'

Paired captures of the same 1,020-step drag, release build, a fresh config
directory each run so a persisted toggle cannot leak between them:

| track | before | after | |
|---|---|---|---|
| plain | 65,438 | **41,195** | −37.0% |
| gradient, spanning the track | 72,087 | **55,323** | −23.3% |
| gradient, scaled to the fill | 166,639 | **150,079** | −9.9% |

The relative win is largest where the per-frame content is smallest, which is
the honest shape of it: the pair was a fixed cost per pass, so it dominated a
frame that changed two cells and disappeared into one that changed eighty. A
first paint barely moves (−0.3% to −5.1%) — those are whole-line writes, which
state their own styling. CPU is unchanged either way.

**What the carry costs is a promise that had been kept by accident.** The
terminal used to be handed back unstyled at the end of every frame, so nothing
had to think about the app giving it away. It can now end a frame styled, and
leaving the alternate screen does NOT restore SGR — so
`RenderLoop.restoreTerminalStyling()` says it explicitly, at both places the app
hands the terminal over: the shell on the way out, and a job-control suspend.

Two writers can invalidate the belief because they emit bytes this one did not
plan: `repaintRightEdge` (Terminal.app's phantom-cell workaround, which replays
a row's own SGR context) and `ViewRenderer.flush` (a one-off render outside the
run loop). Both set it to `nil`, which is the honest "not known" the pass used
to start from every time.

## What is left

- **The remaining bytes.** The frame still spends most of itself on styling
  (49% after this pass, down from 58% and 69% before that), and the next lever
  is genuinely the renderer: a cell grid rather than `lines: [String]`, which is
  the API break described above. `What makes a page slow to open.md` reaches the
  same conclusion from the other end — allocation is the largest identifiable
  share of a cold render, and `lines: [String]` is where it comes from.
