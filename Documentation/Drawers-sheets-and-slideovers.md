# Drawers, sheets and slideover panes

**Status: draft for decision.** Nothing here is implemented, though the grabber
question §3 raises was answered elsewhere in the framework, as §3 now records.
It exists because `.presentationDetents` shipped with a hole in it, and closing
that hole properly means deciding what a "sheet that can be resized" *is* in a
terminal — which is a design question, not an implementation detail.

---

## 1. The hole

`.presentationDetents([.medium, .large])` compiles, measures and renders. It
also does nothing a user can reach. From `PresentationDetent.swift`:

> A terminal has no drag-grabber to move between them, so the binding is how a
> multi-detent sheet changes size.

SwiftUI's detents are a *gesture* feature. The API names the rest stops; the
user drags between them, and the sheet snaps. Take the gesture away and what
remains is `.presentationDetents([.medium])` — a verbose way of writing "this
sheet is half height". Every additional detent in the set is unreachable unless
the app also binds `selection:` and builds its own control, at which point the
detent set is doing no work the app is not already doing.

So the honest reading of the current state: **detents are a parity shim, not a
feature.** They keep SwiftUI code compiling. They do not give a TUIkit user
anything.

Two ways out, and they are not exclusive:

- **(A)** Give the terminal the gesture — a grabber the mouse can drag and the
  keyboard can drive. Detents become real.
- **(B)** Recognise that a resizable panel anchored to an edge is a *different
  control* from a modal sheet, name it, and build it deliberately.

The owner's framing — "this sounds like a drawer (in old Mac OS X parlance)" —
is (B), and it is the more interesting half. (A) is worth having anyway, and
falls out of (B)'s machinery.

---

## 2. Three things, currently conflated

| | Modal? | Anchored to | Resizable | Dismissed by |
|---|---|---|---|---|
| **Sheet** | yes — dims, traps focus | centred | no (fixed detent) | Escape, or its own button |
| **Drawer** | **no** | one edge of a parent view | yes, by its grabber | closing it; content keeps working |
| **Slideover** | no | one edge of the SCREEN | yes | closing it |

They differ on the axis that actually matters in a terminal: **does the rest of
the app keep working while it is open?** A sheet says no — it dims what is
behind it and takes the focus ring. A drawer says yes: it is a second pane, and
Tab moves between them.

That distinction is already load-bearing elsewhere. `NavigationSplitView` is
"two panes, both live"; a modal is "one pane, everything else inert". A drawer
is the first with a resize affordance and an open/closed state.

Which suggests the cheapest honest answer to "what is a drawer": **a
NavigationSplitView column that can be collapsed and dragged**, not a sheet that
can be resized. The framework already has resizable split panes with keyboard
and mouse handles (task #317). The question is whether a drawer should reuse
that or be its own thing.

**Recommendation: reuse it.** A drawer is a split-view column with

1. an open/closed binding,
2. an edge (leading / trailing / top / bottom),
3. a size the user can change and the app can persist.

Everything else — the divider, the drag handle, keyboard resize, size-to-fit —
already exists and is already tested. Building a parallel implementation would
be the "reinventing the wheel" smell the project's rules call out.

---

## 3. The grabber

The owner's suggestion: *"we can have a grabber at the top border of the
sheet"*. Yes — and the machinery is already written.

`DialogDrag` makes a presented dialog draggable by its title row and border. It
registers a mouse handler, appends grab regions to the buffer's hit-test
regions, and keeps a persisted `(x, y)` the compositor applies as a post-centre
delta. A grabber is the same shape with the delta applied to **height** instead
of position, and the grab region limited to one edge.

So the work is: generalise `DialogDrag` into a "grab this edge and give me a
delta" helper, and let both the drag-to-move and drag-to-resize cases use it.

**That question was answered elsewhere, and answered differently.**
`.userResizable(_:)` shipped on 2026-08-21 (`7aba17dd`; the design record is
`Documentation/Resizable views.md`) with its own core rather than a generalised
`DialogDrag`. `_UserResizableCore` marks a stretch of the bottom and right
borders as draggable, keeps the size the user chose in `StateStorage` under the
view's render identity, and resizes from the keyboard by one cell (Shift for
five), Home/End to the bounds, Escape back to the size the layout wanted. That
is §5's table for every row but the last, arrived at independently — §5 spends
Escape on closing the drawer, and a resizable view has nothing to close.
`DialogDrag` is untouched and still dialog-only, so "generalise it" is now a
choice between a *third* implementation and sitting a drawer's grabber on
`_UserResizableCore`'s. Sit on it.

### What it looks like

The border already draws. A grabber marks a stretch of it as grabbable:

```
╭──────────────── ▁▁▁▁▁▁ ────────────────╮     ← grabbable stretch, centred
│                                        │
```

Candidate glyphs, in the project's usual order of preference (see
`Terminal-compatibility.md` on chrome repertoires — anything chosen here needs
measuring on Apple Terminal, iTerm2, Ghostty and Warp before it ships):

| Glyph | Reads as | Risk |
|---|---|---|
| `▁▁▁▁` U+2581 | a lip to pull | fine everywhere; low contrast on some fonts |
| `═══` U+2550 | a doubled rule | reads as decoration, not a control |
| `⣿⣿` U+28FF | a knurled grip | Braille — the `.dots` spinner's coverage problem |
| `───` (plain) | nothing | invisible affordance |

`▁▁▁▁` is the recommendation. It differs from the border it sits in, it is
BMP-old, and it does not depend on Braille or emoji coverage.

What `.userResizable(_:)` shipped with is not `▁▁▁▁`, and is not a fixed glyph:
the handle is drawn in whichever Box Drawing weight stands out from the border
cell it lands on — doubled (`═` `║` `╝`) over a single-line or heavy border,
heavy (`━` `┃` `┛`) over a double one — because that modifier wraps a border it
did not draw and has only the drawn result to read. The stretch is 7 cells along
a bottom edge and 3 rows along a side, shrunk to fit a small view. A drawer's
grabber should match it rather than reopen this table.

**A grabber must not be the only affordance.** The framework's own rule (from
the iTerm2 right-click work) is that mouse-only features need a keyboard route.
See §5.

### Where it lives

On the drawer's edge nearest the content it resizes: bottom drawer → top
border; trailing drawer → leading border. That is the edge that moves.

---

## 4. Proposed API

### 4a. Drawer (TUI-specific, no SwiftUI equivalent)

```swift
ContentView()
    .drawer(isPresented: $showingInspector, edge: .trailing) {
        InspectorPane()
    }
```

with modifiers on the content, following the modifier-first principle:

```swift
    .drawerWidth(30)                    // initial; user-resizable from there
    .drawerWidthRange(20...60)          // resize limits
    .drawerResizable(false)             // fixed; no grabber drawn
```

Open questions on this shape:

- **Should the size be a binding?** `.drawer(isPresented:edge:size:content:)`
  with `size: Binding<Int>?` would let an app persist the user's drag across
  launches (`@AppStorage`). Without it the drawer forgets on every relaunch,
  which for an inspector pane is annoying. **Recommend: yes, optional binding**,
  same shape as `presentationDetents(_:selection:)`.
- **Does a drawer take focus when it opens?** macOS drawers did not. Tab-into
  seems right; auto-focus does not. Matches how `NavigationSplitView` behaves.
- **What happens at a terminal size where the drawer will not fit?** Proposal:
  it clamps to the range's minimum, and below THAT it refuses to open and the
  binding snaps back to `false`, so an app can notice. Silently opening a
  1-cell drawer is worse than not opening.

### 4b. Slideover (TUI-specific)

Same as a drawer but anchored to the screen rather than to a view — so it needs
the root-hosted overlay path modals already use (`OverlayLayer`, per
`modal-presentation-is-page-hosted`), not the parent's layout.

```swift
    .slideover(isPresented: $showingHelp, edge: .trailing) { HelpPane() }
```

**Question for the owner: is this worth having separately at all?** The visible
difference between "anchored to the page" and "anchored to the screen" is one
row of app header. If the answer is "not worth it", drop it and keep drawers.

### 4c. Sheet detents (SwiftUI parity, made real)

Keep the SwiftUI API exactly as it is and give it the gesture:

```swift
.sheet(isPresented: $showing) {
    Detail().presentationDetents([.medium, .large], selection: $detent)
}
```

- A sheet with **more than one** detent draws a grabber on its top border.
- Dragging it resizes; on release it **snaps to the nearest detent**, as
  SwiftUI does.
- `selection:` stays authoritative — dragging writes through it when bound, so
  an app observing the binding sees the user's choice.
- A sheet with **one** detent draws no grabber. Nothing to move to.

This is pure parity work: no new API, and the existing detent set finally means
something.

---

## 5. Keyboard

Every mouse route here needs a keyboard equivalent, and the keys are nearly
spoken for.

When the drawer (or its grabber) holds focus:

| Key | Does |
|---|---|
| ← / → (or ↑ / ↓, by edge) | resize by one cell |
| Shift + those | resize by five (`shiftStepMultiplier`, as sliders and steppers already do) |
| Home / End | minimum / maximum of the range |
| Escape | close the drawer |

For a **detented sheet**, arrows should move between *detents*, not by cells —
the detents are the rest stops, and one-cell nudges would fight the snap.

This wants the grabber to be a focusable element, which raises: **is the
grabber a Tab stop of its own, or does the drawer's own focus handle resize?**
The split-view divider work (#317) already made this choice — dividers are
focusable and resize with arrows. **Recommend matching it**, so a user who has
learned split views already knows drawers.

---

## 6. Mechanics

Grounded in what exists; nothing here needs new infrastructure.

| Need | Existing part |
|---|---|
| Grab region on a border | `_UserResizableCore`'s grabber (shipped 2026-08-21, `7aba17dd`); `DialogDrag.appendGrabRegions` is still dialog-only |
| Persisted drag delta | `DialogDrag`'s `StateBox` + `propertyIndex` pattern |
| Drag reporting | `MouseEventDispatcher.requestFeature(.drag)` |
| Screen-anchored placement | `OverlayLayer.placed(maxWidth:maxHeight:)` |
| Two live panes + divider | `NavigationSplitView` / split-view resize |
| Focus per pane | focus sections (`activeFocusSectionID`) |
| Persisting user size | `@AppStorage` |

Two traps worth naming in advance, both from the bug ledger:

- **Chrome height must not need the content.** A drawer's border and grabber
  have to be sizeable before its content renders, or the render pass is
  discarded (see `chrome-height-must-not-need-content`).
- **Measure must not mutate.** A drag delta is state; reading it during a
  measure pass and writing it back is the measure-side-effect class.
  `DialogDrag` already guards on `!context.isMeasuring` — keep that.

---

## 7. What I recommend building, in order

1. **Detent grabber** (§4c). Smallest, pure parity, makes a shipped API real.
   Proves the grabber glyph and the drag-resize helper.
2. **Drawer** (§4a) on top of the split-view machinery, with a size binding.
3. **Slideover** (§4b) only if §4b's question comes back "yes".

Step 1 is worth doing regardless of what happens to 2 and 3, because right now
`.presentationDetents` is a promise the framework does not keep.

---

## 8. Open questions for the owner

1. **Drawer as split-view column, or its own control?** (§2 — I recommend
   reusing the split view.)
2. **Is a slideover worth having separately from a drawer?** (§4b)
3. **Grabber glyph** — `▁▁▁▁`, or something else? (§3 — largely settled by
   `.userResizable(_:)`, which draws whichever Box Drawing weight stands out
   from the border cell it lands on rather than any fixed glyph.)
4. **Should a drawer's size be an app-visible binding** so it can persist?
   (§4a — I recommend yes.)
5. **Is the grabber its own Tab stop**, matching split-view dividers? (§5)
6. **Should a sheet drag snap to the nearest detent, or move freely** and only
   snap when released near one? SwiftUI snaps; free movement would make the
   detent set advisory. (§4c — I recommend snapping, for parity.)
