# Unifying the menu implementations

**Status:** done. All four menu surfaces share one highlight, one drop-down
assembly and — for the three POP-UPS — one renderer. The inline style keeps the
focus ring, which was always the plan and is not a deferral (see below). Kept as
the record of what moved and why.

**Why:** TUIkit has two pop-up-menu implementations, and the differences between
them are user-visible. Every observable difference the owner named has been
fixed, but they were fixed *twice over* — once in each engine — which is the
symptom, not the disease.

---

## The two engines

|  | **A — index-owned** | **B — view-composed** |
|---|---|---|
| Renderer | `DropdownMenu` (`Rendering/DropdownMenuRenderer.swift`) | `renderMenuColumn` (`Modifiers/MenuPopover.swift`) |
| Used by | `Picker` drop-down (`_PickerMenuCore`), combo box (`TextInputSuggestions`) | `Menu` (`_MenuPopupCore`), `.contextMenu`, inline `Menu` (`_InlineMenuCore`) |
| Highlight is | an `Int` on one `Focusable` | `FocusManager.focusedID` over real `Button` rows |
| Rows are | pre-rendered single-line **strings** | **views**, styled by `_MenuItemButtonStyle` |

Everything else follows from that one difference. Engine A gets
`OptionListNavigation`, windowed scrolling with a real scrollbar, and
hover-moves-highlight for free, because it owns an index. Engine B gets arbitrary
`@ViewBuilder` content, `ButtonRole`, per-row `.disabled()` and key equivalents,
because its rows are views.

**Neither file survives whole. Both models must.**

---

## What is NOT in scope, and why

**The inline menu keeps the focus-ring model.** This is a real constraint, not a
deferral. If `.menuStyle(.inline)` rows stopped registering focus, four things
break — all of them live in the Example today:

- Tab cannot reach the landing screen at all (`MainMenuPage` is nothing *but* the
  menu);
- `.defaultFocus($focusedEntry, menuSelection)` can never resolve, so returning
  from a demo lands at the top instead of where you left;
- `OverlaysPage`'s description panel freezes on its first item, because
  `focusedDemo` is derived from `FocusManager.focusedID`;
- the focused row stops being revealable by an enclosing scroller, which matches
  on `region.focusID`.

Separately, if inline rows published their shortcuts to a menu-local table
instead of the global registry, all 31 main-menu accelerators die silently.

So the target is **one implementation for the three POP-UP surfaces** — Picker
drop-down, combo box, `Menu`/`.contextMenu` — with the inline style sharing row
rendering and the width/hint arithmetic but keeping page focus. If a commit has
to touch `_InlineMenuCore` beyond one argument, the design has drifted.

---

## Landed

- **`fc8da879`** — one dismiss backdrop (`DropdownMenu.attachDismissBackdrop`),
  was duplicated verbatim in both engines.
- **`a893ce34`** — menus answer Home/End/PageUp/PageDown/Shift+arrow through the
  same `OptionListNavigation` helper the drop-down uses; Left/Right swallowed;
  Escape claims the status-bar label (it was dismissing the whole page).
- **`f4531266`** — `MenuColumnRenderTests`: goldens for one mixed menu (a
  `@ViewBuilder` label, a `.destructive` role, a key equivalent, a `Divider`, a
  `.disabled` row, a CJK label) in both styles, plus the four invariants a golden
  cannot express. **This is the instrument every remaining commit is read
  against.**
- **the ownership flip** — `Rendering/MenuColumn.swift`: a pop-up's rows claim
  an ORDINAL from a `MenuRowSink` and report their action to it, and a
  `MenuPopupController` owns the highlight, the navigation and the activation.
  `_ButtonCore` branches on the sink; the inline style never sets one, so its
  rows are still page focus stops. Neither golden moved.

  Four things that were not obvious going in:

  - **Only a RENDER pass may claim.** A measure runs the same rows through
    `_ButtonCore` with its own identities, so letting it claim spends the
    ordinals the render then wants, and the highlight points at a row that never
    drew. (`FocusRegistration.register` is already measure-gated, so the
    non-menu path a measure falls back to registers nothing either.)
  - **`FocusRegistration.register` bundles three things.** Skipping it must not
    skip `stateStorage.markActive` (else the row's hover box and any `@State` in
    a `@ViewBuilder` label are collected at the end of the frame) nor
    `recordRenderSideEffect()` (else the row is cacheable, and a cached row
    freezes the highlight — the `ForEach` memo hole again).
  - **A tall menu still has to scroll to its highlight.** The reveal finds a
    control by matching a rendered region's `focusID` against the focused id, and
    a pop-up row now has neither. So the row's region is named from its ordinal
    (`menuRowRegionID`) and the column publishes `\.revealTargetID`, which
    `snapViewportToFocusedControl` prefers over the focus manager's answer.
    Everything downstream of that is unchanged.
  - **`markSectionFocusOptional` is now unconditional**, not the
    pointer-opened special case. The section holds no focus at all — but a tall
    menu's own `ScrollView` still registers in it, and without the mark the end
    of the render pass hands that scroller the focus for want of anything better.

  Rewritten, and each proven to fail on the unflipped code: the `MenuTests`
  cases that asserted ring membership now read the highlight out of the DRAWN
  frame instead (with `.selectionIndicatorStyle(.none)`, or the wall-clock pulse
  makes every frame differ), which is what a user sees and is engine-agnostic.

## Remaining

## Also landed: the renderer merge (step 3)

The blocker was getting per-row buffers out of a `@ViewBuilder`: the rows are
views, they render as one column, and you cannot tell which lines are which row
by looking at them. The ordinal-tagged hit regions the ownership flip added
solve it exactly — every row already publishes a region carrying
``menuRowRegionID``, so its precise line range is known without guessing heights
or classifying lines. Lines no row claims (a `Divider`, a heading) become
unselectable rows: placed as drawn, never highlighted, never clickable.

So `DropdownMenu.Row` gained `.rendered(_:isSelectable:)` — a row that arrives
already painted and must NOT be repainted (its highlight background is on it,
and its foreground was chosen against that backdrop) — and `renderMenuPopup`
slices the column into those.

What a pop-up `Menu` gained, all of it the drop-down's:

- a **scrollbar in its own column** instead of "N more above/below" lines, which
  replaced two rows of content;
- a **highlight spanning the whole interior**, so the pointer can hit the bar
  everywhere the eye says it can. The row's breathing room moved INSIDE its
  background as `menuRowInset` (1 for a pop-up, 0 for inline, which is padded as
  a column instead);
- a **flush divider** that pulses with the border, rather than an inset static
  rule.

Two cells narrower as a result, which the pop-up golden records.

One trap: the column must be rendered against a canvas TALLER than the screen.
The renderer is what windows the menu, and it can only window rows that exist —
laid out in the space actually available, the column is clipped to the overlay
height first and the rows past the fold are never drawn, so the scrollbar has
nothing to scroll to.

`onHover` is wired to the highlight (the drop-down calls it per row), but it has
not been demonstrated end to end — the hover state machine did not fire in the
test harness, and it is not claimed until it does.

## Chrome parity, once the assemblies agree

Measured: for identical labels and no key equivalent the two totals already
match (label + 6). What differs inside is the label's column (Picker starts at
popup column 4, `Menu` at 3), the highlight extent (Picker spans the whole
interior, `Menu` only the label width, leaving two dead gutters the pointer
cannot hit), and the divider (Picker's is flush to both borders and pulses with
the border; `Menu`'s is inset two cells and is static `palette.border`).

---

## Verifying

`swift test` in full, not filtered — `RenderBottleneckTests`,
`RenderPerformanceTests` and `MeasureRenderEquivalenceTests` all render an inline
menu and are the accidental tripwires. Then a PTY walk of both apps at 24 and 12
rows over Menus, Overlays, the main menu and Picker, with `TUIKIT_CONFIG_DIR` set
so the probe cannot touch real preferences.
