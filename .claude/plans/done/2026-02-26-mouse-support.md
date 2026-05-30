# Mouse Support — DELIVERED

> **Status: Delivered.** Moved to `done/` on 2026-05-30 after
> verifying the implementation against this plan. All four
> phases shipped. The as-built design deviates from the
> original sketch below in a few naming/structural ways (noted
> under "As-built"); the deviations are improvements, not gaps.

## As-built summary (what actually shipped)

- **Event model** — `MouseEvent` (`Sources/TUIkitCore/Input/
  MouseEvent.swift`) uses `button: MouseButton` + `phase:
  MousePhase` + `x`/`y` + `shift`/`ctrl`/`meta`, rather than the
  `kind` + `row`/`column` shape sketched here. The wrapper enum
  is `TerminalInput { case key(KeyEvent); case mouse(MouseEvent) }`
  (`TerminalInput.swift`), not `InputEvent`.
- **Parsing** — `MouseEvent.parseSGR` and `MouseEvent.parseLegacy`
  (SGR `ESC [ < b ; x ; y M/m` and legacy X10). Covered by
  `Tests/TUIkitTests/MouseEventSGRParsingTests.swift`.
- **Terminal** — `Terminal.readEvent() -> TerminalInput?`
  (internal to `Terminal`, not on `TerminalProtocol`). Mouse
  modes (`?1000h`/`?1002h`/`?1003h`/`?1006h`) are enabled per
  `MouseSupport` config via `applyMouseSupport()` and disabled
  in `disableRawMode()`, so no escape leakage on exit. The
  opt-in surface is the `MouseSupport` struct
  (`Sources/TUIkit/App/MouseSupport.swift`) with presets:
  `.disabled`, `.scrollOnly`, `.standard`, `.full`.
- **Dispatch** — the run loop in `App.swift` switches on
  `TerminalInput`; mouse events route through
  `MouseEventDispatcher` against per-frame `HitTestRegion`s
  (`Sources/TUIkitCore/Input/HitTestRegion.swift`). Re-render is
  triggered only when a handler reports the event consumed.
  (Mouse dispatch lives in the run loop rather than inside
  `InputHandler` — a deliberate split from the key chain.)
- **Wheel scroll (v1)** — `ScrollableOffsetState.handleWheelEvent(_:linesPerTick:)`
  (default 3 lines), shared by `ScrollViewHandler` and
  `ItemListHandler`.
- **Click-to-focus / row selection (v2)** — hit-test regions
  carry `focusID`; clicks resolve to the target, focus it, and
  toggle selection per the list's selection mode.
- **Generic click dispatch (v3)** — region-based dispatch
  reaches all focusable controls; `OnMouseEventModifier`
  (`Sources/TUIkit/Modifiers/OnMouseEventModifier.swift`) is the
  public per-view registration API. Hover (`.entered`/`.exited`)
  is wired across Button, Toggle, Slider, Stepper, Picker,
  SecureField, RadioButton, and status-bar items.
- **Beyond the original non-goals** — `DragGestureModifier`
  (`Sources/TUIkit/Modifiers/DragGestureModifier.swift`) adds
  drag-gesture support, which this plan listed as a v1 non-goal.

## Acceptance criteria — all met

- ✅ Apps run unchanged without mouse input (opt-in via
  `MouseSupport`; `.disabled` is a valid config).
- ✅ Wheel scroll works in focused `List`/`Table`.
- ✅ Click-to-focus and click-to-select for rows.
- ✅ Generic click dispatch reaches all focusable controls.
- ✅ No regressions in keyboard-driven tests (full suite green).
- ✅ Mouse modes disabled on shutdown (no escape leakage).

## Residual / deferred (tracked elsewhere, not blockers)

- **Per-row hover** for List/Table/Menu is deferred (pairs with
  the List/Table-on-ScrollView composition; see
  `Documentation/Composing List and Table on ScrollView.md`).
- **Double-click semantics** were a stated non-goal and remain
  unimplemented.
- `readEvent()` is not exposed on `TerminalProtocol`; if a
  third-party terminal backend ever needs it, promote it then.

## Stale constraint (for the record)

The original plan said **"Swift 6.0 only"**; the project now
targets **Swift 6.2**. Noted so the constraint isn't mistaken
for current policy.

---

<details>
<summary>Original plan (historical, as written 2026-02-26)</summary>

## Specification / Goal

Deliver SGR-mouse-protocol support across macOS and Linux terminals with the following acceptance criteria:

- Apps run unchanged without mouse input (opt-in, no regressions).
- Mouse wheel scroll works reliably in focused `List`/`Table` on macOS and Linux.
- Click-to-focus and click-to-select work for `List`/`Table` rows.
- Generalized click dispatch reaches all focusable controls.
- No regressions in existing keyboard-driven tests.
- Mouse modes are always disabled on app shutdown (no escape leakage).

**Non-goals (v1):** no full generic hit-testing across every view type; no drag gestures; no double-click semantics; no pixel/graphics mode support (text terminal only).

The original phased rollout (Phase 1 foundations → Phase 2 wheel scroll → Phase 3 click focus + selection → Phase 4 generic click dispatch) was followed; see the as-built summary above for how each landed.

</details>
