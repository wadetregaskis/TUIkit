# Intra-line output diffing

A design note for a deferred optimisation: shrinking the byte stream written to
the terminal by updating only the changed *cells* of a changed row, rather than
rewriting the whole row. Parked for now (see "Recommendation"); this captures
the idea, the measurements, and — importantly — the sharp edges, so we can pick
it up later without re-deriving them.

## What we already do

`FrameDiffWriter` does **line-level** diffing. `buildOutputLines(…reusingFor:)`
builds the new frame (reusing unchanged rows, commit 96357b13), then
`computeChangedRows` compares each new line to the previous frame's line and
writes **only the rows that changed** — each as a whole line:

```
move-to-(row,1)  +  bgCode + ESC[2K + content + padding + reset
```

So a static screen with one animating element already writes one row, not the
screen.

## The proposal

When a row changes, write only the changed *span* within it:

```
move-to-(row, firstChangedCol)  +  <SGR state at that column> + <changed cells> + reset
```

For a blinking text cursor that is one cell, that's a cursor-move plus a handful
of bytes instead of the whole line.

## Measured opportunity

A 24-row form, 80 cols, where a text cursor on row 10 toggles between frames
(measured via `MockTerminal.allOutput.count`):

| | bytes |
|---|---|
| First full paint (24 rows) | 3456 |
| Cursor-blink frame, today (1 whole row) | **144** (8-byte move + 137-byte line) |
| Cursor-blink frame, ideal (one cell) | **~35** |

So line-level diffing already turned 3456 → 144 (the 24× win). Intra-line would
take 144 → ~35 — a further ~4×, but on an already-small number.

## The sharp edges (why this is harder than it looks)

1. **A blinking/pulsing cursor changes no visible character — it changes the
   cell's *SGR* (reverse-video / colour).** The two row-10 strings are identical
   in *visible text* for all 80 cells; only `ESC[7m … ESC[27m` vs a plain space
   differs. So a `String`-prefix or stripped-text diff misses the change
   entirely. You need a **cell-level diff that compares (character **and** active
   SGR)**, walking the ANSI segments of both rows in lockstep.

2. **You need both prefix *and* suffix trimming.** A cursor mid-line (cell 33 of
   80) with prefix-trim alone still rewrites the 47-cell tail (~78 bytes — barely
   better than 144). The real win needs writing only the cells between the first
   and last change, which is the fiddliest part (extracting a *middle* slice with
   the right entry SGR and a clean end).

3. **You must re-establish the SGR state at the write column.** After a
   cursor-move the terminal's active colour is whatever the last write left, so
   the span must be prefixed with the colours active at that column. This part is
   already solved: `String.ansiSGRContextAndCleanSuffix(from:)`
   (`TUIkitCore/Extensions/String+TerminalWidth.swift`) reconstructs exactly that
   — it's what `repaintRightEdge` uses.

4. **It conflicts with the Terminal.app emoji compensation.** That same helper
   deliberately strips cursor-move (`CUF`) sequences from the suffix, but on
   Apple_Terminal those `CUF`s are the emoji fix (see
   `withTerminalAppCursorCompensation`, and the gating in commit 839173ca). So
   intra-line writes must be **gated to non-Apple terminals** (the majority);
   Apple_Terminal keeps the whole-line write.

5. **Correctness exposure is high.** This is the most user-facing code path:
   wide-character / grapheme-cluster boundaries and off-by-one column errors
   surface as *visible corruption*, not a slow frame. It needs a golden-output
   corpus, not just unit tests.

## Sketch of an approach

- Add a cell-level lockstep diff over `ansiSegments()` of the old and new row:
  walk both, tracking visible-cell index and SGR state, to find the first and
  last cells that differ in `(character, SGR)`.
- If the changed span is the whole row (e.g. a scroll where every cell shifts),
  fall back to the current whole-line write — no benefit, and it avoids the
  span machinery on the common all-changed case.
- Otherwise emit: `move-to-(row, firstCol)` + SGR-context-at-firstCol (via the
  existing helper) + the changed cells clipped to the span + a trailing reset.
  Do **not** emit `ESC[2K` (it would wipe the untouched prefix/suffix).
- Gate on `!isAppleTerminal`.
- Validate with a golden corpus over representative transitions: cursor blink at
  start / middle / end of line, a colour pulse over a span, a wide-emoji cell
  toggling, and a no-common-prefix scroll (must match the whole-line output).

## Recommendation

**Parked.** The win is real but modest now that line-level diffing exists
(~144→~35 bytes on the per-animation-frame output), and the frequent animations
(spinner, a pulsing border) change most of their row anyway, so they benefit far
less than the ideal single-cell cursor case. The payoff is mainly
**remote/SSH** responsiveness; locally it is negligible, and the downside is
display-corruption risk in the diff writer.

Worth doing **if low-bandwidth / SSH use becomes a priority** — implement the
scoped, golden-tested cell-level prefix+suffix trim above and A/B the byte
counts. Otherwise spend the risk budget on pure-CPU work (e.g. the measure-pass
`Layoutable` items) that has no display-correctness exposure.
