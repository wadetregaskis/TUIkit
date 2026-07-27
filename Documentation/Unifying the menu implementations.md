# Unifying the menu implementations

**Status:** the controller merge is done. All four menu surfaces now share one
highlight and one drop-down assembly; what is left is the RENDERER merge (step
3), which is what would give a pop-up `Menu` the marker column, the scrollbar
and hover-moves-highlight. This is the working plan, written down so it can be
picked up cold.

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

### 3. Window the pop-up through `DropdownMenu` *(optional; not render-identical)*

Only if the pop-up is to gain the scrollbar, the marker column and
hover-moves-highlight. Blocked on `DropdownMenu.Row` being able to carry a
rendered row: rows rendered as views arrive with their own ANSI and their own
highlight already applied, and the renderer must **not** re-paint them
(`withPersistentBackground` would, and it cannot pick a readable foreground the
way `_MenuItemRow` does with `palette.readableText(on:)`). Its own commit, its
own re-recorded golden, before/after pasted into the message.

`anchorHeight` is load-bearing in two places — `OverlayLayer.placed` flips a
pop-up above its control only when it is > 0, and `ScrollView` culls overlays by
`offsetY - anchorHeight`. Giving `Menu` the Picker's `1` starts flipping menus
that today only nudge.

## Also landed: the controller merge (step 4)

Two commits, from the outside in.

**The assembly.** `DropdownMenu.Entry` / `OptionMenu` / `attach` — an option is a
label and "is this the current value", and the marker column, the
`maxLabel + 4` width, the ordinal↔row maps and the `anchorHeight: 1` overlay all
follow from that. The `Picker` and the combo box had written that out twice,
identically, and `innerWidth(for:context:)` is separate because a `Picker`'s
COLLAPSED control is drawn to the width of the menu it opens.

**The walk.** `MenuHighlight` — the highlight is an ordinal, and every gesture
that moves it (the arrows, Home/End, Page, Shift-accelerated steps, via
`OptionListNavigation`) is one implementation. Three surfaces had written it out
three times, and the differences between them had never been decided anywhere:
the jump keys reached one long before the others.

The two places they genuinely differ are now **named configurations**, so a
control given the wrong one is a change the tests can see:

| | `MenuHighlight.popUpMenu()` | `.pickerDropDown()` | `.suggestions()` |
|---|---|---|---|
| edge | clamp | **wrap** | clamp |
| entered from nothing by | any key | any key | **arrows only** |
| used by | `Menu`, `.contextMenu` | `Picker` | combo box |

The wrap is the `Picker`'s alone because its list is the whole interaction while
it is up — nothing else is reachable to be jumped away from. The arrows-only
entry is the combo box's alone because with nothing highlighted its keyboard is
still at the CARET, so Home/End must move the caret and Shift+arrow must extend
the selection.

`MenuHighlightTests` is parameterised over those three factories rather than over
made-up ones, so mutating any shipping config fails it (checked: all four
mutations do, 2–12 expectations each).

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
