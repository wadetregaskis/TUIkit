# Emoji rendering bugs in macOS Sequoia's Terminal.app

This document catalogues the Terminal.app rendering quirks that TUIkit has
to work around in macOS 15 (Sequoia), the approaches that were tried during
the investigation in this branch (12 commits on top of `a95d7164`), and why
the bug class that affects Fitzpatrick skin-tone clusters has no clean
workaround using pure ANSI escape sequences.

The empirical statements below were verified against Terminal.app on a
Sequoia VM by a combination of frame dumping (via the `` ` `` debug
shortcut added in `f19d0b59`) and pixel-level inspection of the rendered
output.

## The bugs

Terminal.app exhibits **two distinct cursor-advance quirks** around emoji.
Both involve the glyph's *visible cell width* (1–2 cells) disagreeing with
the *number of cells Terminal.app advances its internal cursor counter*.

### Bug A — VS-16 pictographic emoji under-advance

Any grapheme cluster of the form `<pictographic-base>` + `U+FE0F`
(emoji-presentation variation selector), where the base lies in the
`U+1F000`–`U+1FBFF` block, **paints 2 cells but advances the cursor by 1**.
Example: `🖥️` (= `U+1F5A5` `U+FE0F`).

Subsequent characters written inline land on top of the glyph's right
half. There is also a "phantom cell" left at the default terminal
background at the row's right edge if the cluster sits near it.

### Bug B — Fitzpatrick skin-tone cluster over-advance

Any grapheme cluster of the form `<pictographic-base>` + `U+1F3FB`–`U+1F3FF`
(Fitzpatrick skin-tone modifier), where the base lies in the
`U+1F000`–`U+1FBFF` block, **paints 2 cells but advances the cursor by 4**.
Example: `🤙🏽` (= `U+1F919` `U+1F3FD`).

Worse, Bug B is *compound*:

- **B1 — Modifier-killing on backward movement.** Any backward cursor
  movement on the same row after the cluster — `CUB`, `CHA`, `CUP`,
  backspace, `DECRC` — makes Terminal.app silently strip the Fitzpatrick
  scalar and re-render the base emoji in the default ("Simpson yellow")
  tone. The strip happens regardless of what is written in between
  (a committing space, multiple frames, intervening SGRs).

- **B2 — Row-wide LEFT shift.** When the modifier is preserved (no
  backward movement), Terminal.app applies a **row-wide visual shift of
  ~2 columns to the LEFT** to every cell on the row. Bytes written at
  column N visually render at column N − 2. The rightmost 2 cells of the
  row are left at the default terminal background (typically white in
  light themes) — they fall off the right edge in the LEFT shift and
  are never painted by the line's content. This shift applies row-wide
  and survives every recovery attempt (overdraw past the edge, `CUP`
  past the edge, separate-frame writes, `DECSC`/`DECRC`).

- **B3 — Cluster-overflow wrap-to-next-row.** If the cluster's *visible*
  cells fit on the row but the cluster's *cursor advance* (4) would
  push the cursor past the terminal's right edge, Terminal.app **wraps
  the entire glyph onto the start of the next row**, corrupting that
  row's content. (B3 is what makes width 88/89/90 special — the
  cluster's last visible cell fits at the rightmost column, but the
  4-cell advance pushes the cursor past the right edge.)

## Approaches tried

Twelve commits, four working theories. The table summarises each approach,
in chronological order, and the failure mode that drove the next attempt.

| # | Commit     | Strategy                                                                                     | Modifier preserved? | Layout intact? | Verdict |
|---|------------|-----------------------------------------------------------------------------------------------|---------------------|----------------|---------|
| 1 | `f19d0b59` | Add `` ` `` shortcut that dumps the current frame to a file                                   | n/a                 | n/a            | Tooling for the investigation, not a fix |
| 2 | `96f4ad60` | Two-pass `repaintRightEdge` (erase + rewrite suffix) for VS-16 phantom cells                  | n/a (VS-16 fix)     | n/a            | Fixed Bug A's right-edge phantom cells; scaffold for Bug B work |
| 3 | `880f1086` | Detect Bug B and emit `CUB(actual − claimed)` after the cluster to rewind the cursor          | ❌ dropped           | ✅              | Backward movement → Bug B1, modifier silently stripped |
| 4 | `b4388087` | Pre-clip lines to terminal width before compensation (visible-cell budget only)               | n/a (clip path)     | partial        | Prevented over-wide wraps; didn't address Bug B3 |
| 5 | `d513c2c8` | Scope `repaintRightEdge` to rows that actually contain a quirky character                     | n/a                 | improved       | Stopped the repaint from destroying CJK glyphs at the clip boundary |
| 6 | `4398ecfc` | Drop the CUB compensation; accept the cursor over-advance, let `repaintRightEdge` fix the edge | ✅                  | ❌ (shift right) | Approach gave up alignment; subsequent inline chars shifted ~2 cells right of layout |
| 7 | `d68b3791` | Cursor-based clip: keep an over-advancer as the last visible char on the row whenever its visible cells fit | ✅                | ❌ (right border lost) | "Pretty close" per user — border dropped within 4 cells of right edge; otherwise OK |
| 8 | `25b75b93` | Drop the over-advancer entirely at the right edge (don't try to keep it)                      | ❌ dropped           | ✅              | Clean but loses the emoji; trade-off rejected |
| 9 | `ccc632db` | Always strip the Fitzpatrick scalar in cursor compensation                                    | ❌ dropped           | ✅              | Same trade-off, applied universally — rejected at the time |
| 10 | `01f17d9e` | `cluster + space + CUB(3)` — write a space to commit the cluster, then rewind                | ❌ dropped           | ✅              | Tested empirically: backward movement *after* the commit still strips the modifier |
| 11 | `ca8c0427` | Defer the cluster to end-of-line via `CHA(col) + cluster`; main pass writes a `CUF` over its cells | ✅              | ❌ (shift left)  | Modifier preserved; row-wide LEFT shift (Bug B2) discovered — `│` lands 2 cells left of corners |
| 12 | `8698eec0` | Same deferral as #11, but use real spaces as placeholder and re-emit `bgCode` before the deferred section | ✅              | ❌ (shift left)  | Cleaner bytes than #11, same visual shift |
| 13 | (working tree, abandoned) | "Bare under-advancer" theory — add `🥳` (`U+1F973`) etc. to the under-advance set with `CUF(1)` compensation | depends | ❌ | Empirical re-test showed `🥳` does *not* under-advance — direction was wrong |
| 14 | (working tree, abandoned) | DECSC/DECRC around the cluster — save cursor before any emoji is written, restore after the row is laid out, write the cluster last | ✅ (some widths) | ❌ | DECRC is backward movement on emoji rows in Terminal.app's logic — modifier was stripped in TUIkit context, even though isolated tests preserved it |
| 15 | (working tree, abandoned) | Absorb the over-advance by consuming subsequent skippable spaces from the input without emitting them | ✅ (some widths) | ❌ | Compressed the row by 2 cells visually → `│` ended up 2 cells *further* left, not aligned |
| 16 | (working tree, abandoned) | `+2` bump to `repaintRightEdge` CUP target on skin-tone rows                                  | ✅                  | partial         | `│` appeared at the right column in some screenshots; rightmost 2 cells still left at default bg |
| 17 | (working tree, abandoned) | Append 2 overdraw `bg`-spaces past the line's logical end on skin-tone rows                  | ✅                  | ❌               | Bytes past terminal width either wrap or clamp; right-edge cells stay at default bg |
| 18 | **Shipping fix** (working tree) | Combine **cursor-aware clip** (Bug B3) + **followed-by-content strip** (Bug B2)         | ✅ when last on row | ✅              | Trade-off accepted: when the cluster is *the last visible character on the line*, the modifier is preserved; otherwise the Fitzpatrick scalar is stripped (base emoji renders alone). Skin tone is lost in the FeatureBox case; the layout never breaks. |

## Detail on selected approaches

### CUB after the cluster (#3, #6, #10)

The naive symmetric reading of Bug B says: cursor advances 2 cells more
than it should, so emit `CUB(2)` (or `CUB(actual − claimed)`) right after
the cluster to rewind.

Doesn't work. **Any backward cursor movement after the cluster strips the
modifier** (Bug B1) — verified at every variant: bare CUB, CUB after a
committing space (#10), CUB with intervening SGR-only sequences, CUB
across separate writes/frames. The modifier dies the moment Terminal.app
sees a backward cursor command on the row.

### Cursor-based clipping that keeps the cluster (#7)

When the cluster's visible cells fit at the right edge, accept the
over-advance — the cluster becomes the last visible character and there
is no inline content after it to be displaced. Worked at most widths;
broke at widths where the right border `│` would have been within 4
cells of the edge — the clip dropped the border too, because the
border's column was past `terminal_width − advance_overflow`.

### Defer the cluster to end-of-line with CHA (#11, #12)

The main pass writes the line with a `CUF` (or, in #12, two real
spaces) covering the cluster's visible cells. The cluster itself is
emitted at the very end of the row as `\e[<col>G<bytes>` so it lands
where the layout reserved it *after* the rest of the row's content.

Preserved the modifier — no backward movement was needed in the
deferred path. But this is the approach that brought Bug B2 — the
row-wide LEFT shift — to light. With the cluster on the row, all
previously-painted cells visually shifted ~2 columns left, the
rightmost cells fell off the right edge, and the `│` border ended up
visually 2 columns left of the box's corners.

### DECSC/DECRC bracketing (#14, abandoned in working tree)

The idea: save the cursor with `\e7` *before* any emoji has been
written on the row (so Terminal.app's cursor frame is still unbroken),
write the row's normal content with plain-space placeholders where the
cluster will go, and finally — after all other writes on the row are
done — restore the cursor with `\e8` and write the cluster bytes last.

Worked in isolated test scripts. In TUIkit's `FrameDiffWriter` context
the modifier was stripped — most likely because the longer SGR-rich
content path between the DECSC and DECRC counts as backward movement
once `\e8` fires. Inconclusive but unrelable.

### Absorb-by-skipping (#15, abandoned in working tree)

Emit the cluster inline (no compensation escape), advance the
internal `col` counter by `actual` (4) rather than `claimed` (2), and
*consume — but do not emit* — up to `actual − claimed` cells of
subsequent plain-space input. The cells the over-advance "skipped" are
bg-painted by the row's initial `ESC[2K`, visually indistinguishable
from the spaces we dropped.

Conceptually clean and the cleanest theoretical fit — but the
empirical row-wide LEFT shift (Bug B2) made the absorbed cells
visually land *further left*, not at the layout's reserved column,
and the `│` came out 2 cells further left of the corners than #12 had
produced.

### `+2` CUP bump + overdraw past edge (#16, #17, abandoned)

Tried to use the LEFT shift constructively: write the cluster's
trailing content 2 cells past the right edge in counter terms, and
Terminal.app's row-wide LEFT shift should pull it back to the layout
position. Both `+2` on the `repaintRightEdge` CUP target and inline
overdraw bytes appended past the line's end were tried. Results were
inconsistent — Terminal.app sometimes clamps `CUP` to `terminalWidth`,
sometimes wraps inline writes that overflow, and either way the
rightmost 2 cells stayed at the default terminal background.

### Shipping fix (#18, current working tree)

Two coordinated changes that *don't* try to undo the bug, only avoid
provoking it:

1. **`ansiAwarePrefixForTerminalApp` — cursor-aware clip.** When an
   over-advancing cluster's `terminalAppCursorAdvance` would push
   Terminal.app's internal cursor past `visibleCount`, replace the
   cluster with `claimed` plain spaces. This is the only thing that
   prevents Bug B3 (cluster wraps to next row) at widths where the
   advance overflows.

2. **`withTerminalAppCursorCompensationParts` — followed-by-content
   strip.** When an over-advancing cluster has *any* visible
   character following it on the same input line, strip the
   Fitzpatrick scalar and emit only the base pictographic scalar(s).
   Terminal.app renders a normal 2-cell emoji with no over-advance,
   no row-wide shift, and no white phantom cells. When the cluster
   is the line's last visible character, the modifier is kept —
   nothing follows the cluster for the shift to displace.

VS-16 emoji (Bug A) continue to be handled with `CUF(claimed − actual)`
plus the existing two-pass `repaintRightEdge` for the phantom-cell
right-edge bug — those workarounds were never the problem.

## Conclusion: why Bug B can't be worked around perfectly

The bug has two independent halves that pull against each other:

- **Any backward cursor movement on the row after the cluster strips
  the Fitzpatrick scalar.** This rules out every "undo the
  over-advance" approach: `CUB`, `CHA`, `CUP`, `DECRC`, and any
  technique that depends on writing the cluster first and repositioning
  afterward.

- **Keeping the modifier triggers a row-wide LEFT shift of ~2 columns
  that survives every recovery attempt.** The shift is uniform across
  the row, applies regardless of whether the cluster was written
  inline or via `CHA` to its column, and is not undone by any ANSI
  sequence — `CUP` past `terminalWidth` clamps, inline writes past
  `terminalWidth` wrap, and writes in subsequent frames land at the
  same shifted positions. The rightmost 2 cells of the row are simply
  unreachable when the cluster is present.

These two halves form a no-win: preserving the modifier requires never
writing anything to the row after the cluster, but a layout with the
cluster anywhere except at the row's end *has* content to write after
it (padding, borders, the rest of a centred string). You can have the
modifier and a corrupted right edge, or you can have an intact right
edge and a stripped modifier. The shipping fix takes the second
option in the followed-by-content case and the first in the
cluster-at-end-of-row case — that's the best ANSI-only outcome
reachable in Terminal.app on macOS 15 with the tools available today.
