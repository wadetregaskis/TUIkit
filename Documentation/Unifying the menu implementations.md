# Unifying the menu implementations

**Status:** in progress. The shared pieces, the safety net and the ownership
flip have landed; the pop-up is not yet WINDOWED through the drop-down, and the
`Picker`/combo box have not yet been folded onto the controller. This is the
working plan, written down so it can be picked up cold.

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

### 4. Fold `_PickerMenuCore` and `TextInputSuggestions` onto the controller

`MenuPopupController` is the seat: it already owns the highlight, the clamped
navigation and the activation. What each caller still holds is its own drop-down
renderer and its own "opens with" rule.

The three deliberately different behaviours stay as **config, not code**:

| | marker | edge | opens with |
|---|---|---|---|
| Picker | ✓ | wrap | the selected row |
| combo box | ✓ | clamp | ✓ row if the text matches, else nothing (pointer) / row 0 (Down) |
| `Menu` / `.contextMenu` | — | clamp | nothing (pointer) / first (keyboard) |

Note "opens with" resolves per **input source**, not to a single case — collapsing
that regresses both the combo box and the menu. On the `Menu` side that decision
now lives in ``MenuPopupController.opened(withSelection:)``, called by the
trigger at the moment it opens, because only the trigger knows which device
pressed it.

The marker column is *not* the renderer's: `DropdownMenu` never inspects one, and
both callers hand-roll the same `maxLabel + 4` arithmetic into their row strings.
That duplication collapses into the column.

---

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
