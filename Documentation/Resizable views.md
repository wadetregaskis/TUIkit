# User-resizable views

**Status: shipped as `.userResizable(_:)`.** This note was the design; what
follows is it, updated where building it taught me something. Two things did.

TUIkit could already resize one thing by hand — a `NavigationSplitView` column,
by dragging its divider — and the question was what it would take to let any
view be resized the same way, by the person using the app rather than by the
layout.

## SwiftUI has no answer to copy

Worth stating plainly, because the parity rule (`CLAUDE.md`) means the first
question is always "what is the SwiftUI signature". Here there is none:

- **Window resizing is the window server's job.** A SwiftUI view does not draw a
  grip; the window chrome does, and `.frame(minWidth:idealWidth:maxWidth:)` only
  tells the window what sizes are acceptable.
- **`NavigationSplitView` column dragging** is the one place SwiftUI lets a
  person resize *within* a window, and it is not expressed as a modifier — it
  is behaviour the container has, configured by
  `.navigationSplitViewColumnWidth(...)`. TUIkit already mirrors this, including
  the modifier name.
- **`Image.resizable()`** is a false friend. It means "scale the content to fill
  the frame", not "let the user drag an edge". Any general TUIkit modifier must
  **not** be called `resizable()`, or the two meanings collide the moment
  `Image.resizable()` is added for parity.

So this is a TUI-specific API, and by the rule it stays deliberately separate
from anything SwiftUI-shaped. The name is **`.userResizable(_:)`** — it says who
does the resizing, which is exactly what distinguishes it.

### Axes and bounds

Four overloads, and one rule covering all of them: **naming an axis is what
makes it resizable.**

```swift
content.userResizable()                             // both, unbounded
content.userResizable(.horizontal)                  // width only
content.userResizable(width: 20...80)               // width only, bounded
content.userResizable(width: 20..., height: 5...30) // both; width has no ceiling
```

Bounds are Swift ranges, which is what makes "no maximum" and "no minimum"
spellable without inventing a vocabulary: `20...80` is both ends, `20...` a
floor with no ceiling, `...80` a ceiling with no floor. `ResizeBounds` reads
them through `RangeExpression.relative(to:)`, the standard library's own way of
asking a partial range for concrete bounds — so there are no per-range-type
overloads and no sentinel numbers standing in for "open".

There is deliberately no overload taking an axis set *and* a range, because
`.userResizable(.vertical, width: 20...80)` has no honest meaning. Nothing
contradictory is spellable.

A ceiling applies **before** anything is dragged, so `width: 12...40` reads as
"at most 40 wide", not "unbounded until someone touches it".

## What a terminal changes

Three things, and each pushes the design somewhere SwiftUI would not go.

1. **There is one window.** The terminal is the window, and the app cannot
   resize it. So the useful unit is a view *inside* the layout taking space from
   its siblings — much closer to a split divider than to a window grip.
2. **The pointer has no shape.** A GUI signals "you may drag here" by swapping
   the cursor as it crosses an edge, and only then. A terminal cannot, so the
   affordance has to be **drawn, and drawn before the pointer arrives**. That is
   the single biggest constraint here.
3. **Many users have no mouse at all**, or a terminal that does not report drags
   (see `Terminal-compatibility.md`). A resize that only works by dragging is a
   feature half the audience cannot reach, so the keyboard path is not a
   nice-to-have.

## What already exists to build on

`NavigationSplitViewResize.swift` is most of the machinery, and a general
version should be an extraction of it rather than a second implementation:

| Piece | What it does | Reusable as-is? |
|---|---|---|
| `_SplitDividerHandler` | a `Focusable` carrying the drag anchor and handling ←/→, Shift-←/→, Home/End | yes, generalised from "the column to my left" to "the view I belong to" |
| `SplitViewWidths` | per-index sizes, tracks which the user set, honours a reset token | yes, keyed by focus identity instead of column index |
| `.navigationSplitViewResizable(_:)` | the opt-in | the pattern, not the name |
| `.navigationSplitViewColumnWidthReset(_:)` | "put it back" as a token change | yes — the same token idea should serve any resizable view |

The important inherited property: the handler only records **raw intent**, and
the layout clamps it and writes back the effective value. That is what keeps the
arrow keys stepping from the real current size rather than from a stored wish
the layout never honoured. Any general version must keep it.

## The three placements, and the recommendation

The options as posed — a bottom-right corner grip, the whole border, or four
corners plus four edge midpoints — differ mostly in how much border they claim.

**Recommended: the bottom-right corner, plus the full run of the bottom and
right edges.** Reasoning:

- A corner-only grip is one cell. One cell is a hard target with a mouse and an
  invisible one without a cursor change, and the same corner is where a
  scrollbar's own arrows and the resize grip would compete.
- The whole border is too much: the top and left edges resize by moving the
  view's *origin*, which in a stack layout means taking space from a sibling
  above or to the left — a different and much more surprising operation than
  growing downward and rightward.
- Eight handles is a GUI idiom that depends on a cursor changing shape at each
  one. Drawn statically, eight marks on a border read as decoration or damage.

Bottom and right only also has a plain description a user can hold: **a
resizable view grows down and right, and never moves.**

## The affordance, as shipped

The design here was two tinted edge runs plus a corner glyph. Building it
settled that down to **a mark of one cell and a target of two whole edges** —
see "What building it changed" below. Drawn, always, not on hover:

- The **corner cell** carries the mark, and the glyph names the axes that
  actually work: `╝` for both, `╡` for width only, `╧` for height only. Box
  Drawing rather than a pictograph, so every repertoire in
  `Terminal-compatibility.md` advances it by the one cell claimed.
- **Resting** it takes the palette's border tint, **hovered** the hovered
  foreground, **focused** the accent — the three-step vocabulary every other
  affordance uses, floored through `ensuringRenderedContrast(atLeast:against:)`
  for the same reason everything else is.
- The **whole bottom edge and right edge** are the drag target, which is what
  makes a one-cell mark acceptable.

A `.block` border paints its cells rather than drawing lines on them, so
stamping `╝` onto one would punch a hole in a solid edge — the mark would read
as damage. The grip keeps whatever glyph is already there in that case and lets
the **tint alone** do the marking. It reads that from the CELL rather than from
`BorderStyle.paintsBackground`, because the border is inside the content and
this modifier is outside it: there is no style to consult, only the result.

## Keyboard

Identical to the split divider's, because it is the same gesture:

| Key | Effect |
|---|---|
| ←/→ | width by one cell |
| ↑/↓ | height by one cell |
| Shift + any of those | by five |
| Home / End | narrowest / widest the layout allows |
| Escape | back to the layout's own size (the reset token, applied locally) |

The handler sits in its own focus section, interleaved after the view it
resizes, exactly as a divider does today.

## Persistence, and what it should not do

- Sizes persist through the same store the split view uses, keyed by focus
  identity rather than column index — which means `.focusID(_:)` is what makes a
  size durable across a relayout, and a view that never sets one gets a size
  that lasts as long as its identity does. That is the honest behaviour and
  should be documented, not hidden.
- A resize is **intent, not law**: the layout still clamps. A terminal that
  shrinks below the stored size must win, and must not destroy the stored size —
  the same `set` / `setClamped` split `SplitViewWidths` already draws.
- **It should not resize the terminal**, offer a maximise/restore, or grow a
  view past its container. Those are window-manager operations, and a TUI
  pretending to be a window manager is the failure mode this whole note is
  trying to avoid.

## Open questions

- **The axis set was the open question, and it is answered.** The note asked
  whether `.userResizable` should take axes or always offer both. It takes them,
  and ranges name an axis as well as bounding it — one rule instead of two
  concepts.
- **Pinning a size to a name.** Sizes live in `StateStorage` keyed by render
  identity, so a relayout that changes the identity starts the view over at the
  layout's size. I wrote in an earlier version of this note that `.focusID(_:)`
  would extend it; that was wrong — `.focusID(_:)` is a property on the views
  that declare one (Picker, TextField), not a general modifier, and this one
  takes no id at all.

  I then wrote that `SplitViewWidths` was the shape to copy. That is wrong too,
  and for a more useful reason: `NavigationSplitView.resolvePersistedWidths`
  keys that store by `StateStorage.StateKey(identity:propertyIndex:)` as well.
  It survives a re-render, not a change of identity. **Column widths have
  exactly the same limitation**, and have had it all along — so there is no
  existing pattern to copy here, and building one means inventing an
  app-level registry keyed by a name rather than by a path.

  That is a real piece of design (who owns the registry, when an entry is
  collected, what two views sharing a name means) and not a modifier signature,
  which is why it is written down here rather than attempted at the end of a
  session. Both the resizable view and the split view would use it.
