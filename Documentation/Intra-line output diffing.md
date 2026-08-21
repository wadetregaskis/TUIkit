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
   terminal (``SGRState/rendered(changingFrom:)``). The last span in a row ends
   with the reset that stops its styling leaking into whatever is drawn next.
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
   escape, or an erase anywhere but the head. Single-cell characters have no
   such disagreement — box drawing, accented Latin, Greek and Cyrillic advance
   one everywhere — so the ordinary row still takes the fast path, on every
   host, including hosts whose advance model has never been measured. The
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

## What is left

- **Carrying SGR state across rows**, not only within one. Worth a few hundred
  bytes a frame, and it couples the diff writer to every other thing that might
  write between two rows. Not obviously worth the coupling.
- **The remaining 3,931.** At a gap of 8 the plan writes about 454 cells; the
  frame spends the rest on span framing and styling. The next honest lever is
  fewer *style transitions* per row, which is a rendering question rather than a
  writing one.
