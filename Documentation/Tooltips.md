# Tooltips — `help(_:)` in a terminal

**Status: design, 2026-08-24. Nothing implemented.** Written before building
because the affordance is the expensive part to change later, and because
mapping the spec onto the render loop turned up two things the spec could not
have known.

The specification is the project owner's, and is taken as given:

- SwiftUI's `help(_:)`, shown on **mouse hover after a configurable delay** or
  on **keyboard focus** — but *not* when focus arrives from a mouse click.
- A view that cannot take focus shows its tooltip on hover only.
- Tooltips are switchable on and off, and the **presentation is the app's
  choice**, from (1) a row in the status bar above the shortcuts, or (2) a
  popover attached to the control.
- Presentation (1) first, then evaluate whether the varying height disturbs
  the content.

---

## 1. Where the help text lives

`help(_:)` goes on *any* view, so it cannot ride the focus system — most views
it will be written on are not focusable. What every such view needs is a
hit-test region, so the pointer can be known to be over it, and TUIkit already
has the modifier that establishes one: `.onHover`.

So `HelpModifier` is `.onHover` plus a publication, and it publishes to a
per-frame sink in the environment — the same shape as
`StatusBarState.activationLabelOverride`, which is already how a focused
control contributes a string to the bar.

```
HelpModifier(content, text)
  ├─ .onHover { entered in tooltips.hovering(text, at: <region>, entered) }
  └─ if context.environment.isFocused { tooltips.focusing(text, at: <region>) }
```

`TooltipState` (a service, not a singleton — one per `TUIContext`, as
`StatusBarState` is) holds at most one candidate: its text, its anchor
rectangle, its source (hover or focus), and the moment it became a candidate.

**Hover wins over focus** when both are true. The pointer is a deliberate act
aimed at one thing; focus is where the keyboard happens to be.

## 2. The delay, and what it costs

A hover tooltip appears only after the pointer has rested. That needs a clock,
and the run loop is demand-driven — it renders when something asks. So
`TooltipState` must **request a wake** at the moment the delay expires, exactly
as an animation does (`context.requestAnimation`), or the tooltip appears only
if something else happens to redraw.

That is one scheduled wake per hover, not a poll, and it stops as soon as the
tooltip is shown or the pointer leaves. A tooltip that is already showing costs
nothing.

## 3. "Not when focus arrives from a click" needs the focus manager to say why

`FocusManager.focus(id:)` takes no reason, and five call sites drive it from a
mouse handler (`FocusableModifier`, `TextFieldMouseHandler`, `Color256Grid`,
`_PickerMenuCore`, and `FocusReference` for the programmatic case). A tooltip
that cannot tell those from a Tab will pop up on every click, which is exactly
what the spec rules out.

**This wants `focus(id:reason:)`** — `.keyboard` / `.pointer` / `.programmatic`
— with the default keeping today's behaviour and the five sites naming theirs.
Small, exact, and useful beyond tooltips: "was this focus change the user's
keyboard?" is a question the reveal machinery also asks in a roundabout way.

The alternative — infer it from a mouse event having arrived this frame — is a
heuristic that fails when a click focuses one view while the pointer rests over
another, which is the ordinary case for a click on a scrollbar.

## 4. Presentation 1 — a status-bar row

`StatusBar.height` is `style.barHeight(contentRows: 1)`; the tooltip makes that
`1 + wrapped lines`. The content area is whatever is left.

**The finding, and it is the one the owner asked to watch for.** The bar's
height is computed in `RenderLoop` *before* the content renders
(`RenderLoop.swift:451`), and the tooltip's text is published *during* that
render, by whichever view the pointer is over. So the height is known one frame
late: the tooltip appears, and the content shifts up on the NEXT frame.

Three ways out, and the choice is a UX one:

| | content shift | wasted space | obstructs |
|---|---|---|---|
| **Accept the lag** — bar grows next frame | one frame of jump, every appear and disappear | none | no |
| **Reserve the row always** | none | one row, forever | no |
| **Draw it as an overlay** over the bar's rows | none | none | the bar's own items, while shown |
| **Two-pass the frame** — render, read the height, render again | none | none | no (costs a second render pass) |

The last is what `RenderLoop` already does for a header whose height changed
(there is a correction re-render), so the machinery exists and the cost is
bounded to frames where the tooltip appears or disappears. **That is the
recommendation**; the lag is the fallback if the second pass proves expensive.

Wrapping is ordinary text wrapping at the bar's width, and the row is drawn
above the shortcut items, in the bar's own chrome.

## 5. Presentation 2 — a popover

Attached to the **control**, not the pointer. The placement rules, in order:

1. Prefer **below** the control, left-aligned to it.
2. If it does not fit below, **above**; then to the **side**.
3. Never overlap the control itself.
4. Prefer a position that does not sit under the **pointer** — but only after
   1–3, because full visibility beats getting out of the way.
5. Never truncate. If no placement fits the text without truncation, the text
   wraps to a narrower box before any placement is rejected.

This is `DropdownMenuRenderer`'s problem with one extra constraint, and that
renderer already solves flipping and clamping (`OverlayLayer.placed(maxWidth:maxHeight:)`).
The popover reuses it.

It **cannot take focus** and must not move focus when it appears or
disappears — it is not in the focus ring at all, which is simply not
registering. It **dismisses on any click**, as the escape hatch for the case
where it is in the way despite rule 4.

## 6. API

```swift
extension View {
    public func help(_ text: LocalizedStringKey) -> some View
    public func help(_ text: Text) -> some View
    public func help<S: StringProtocol>(_ text: S) -> some View     // SwiftUI's three

    public func tooltips(_ visibility: TooltipVisibility) -> some View   // .automatic/.hidden
    public func tooltipStyle(_ style: TooltipStyle) -> some View          // .statusBar/.popover
    public func tooltipDelay(_ seconds: Double) -> some View
}
```

Three overloads because SwiftUI has three; the rest are TUI-specific and go
through the environment like every other subtree setting, so an app can turn
tooltips off for one panel.

## 7. Open questions for the owner

1. **A view with help AND a status-bar verb.** The bar already carries a verb
   from the focused control ("↵ choose"). Does the tooltip row displace it,
   sit above it, or only show when there is no verb? The row is above the
   shortcuts, so *both* is the natural reading and is what this assumes.
2. **Nested help.** `help` on a container and on a child inside it: innermost
   wins, as with every other cascade — but a hover over the child is also a
   hover over the container, so this is a rule rather than an accident.
3. **A non-focusable view with no hit region.** `.onHover` establishes one, so
   `help` on a `Text` makes that `Text` hit-testable where it was not. That is
   a small behavioural change to anything sitting under it.

## 8. Staging

1. `TooltipState` + `HelpModifier` + `help(_:)`, publishing to nothing.
   Testable on its own: does the right text become the candidate, does hover
   beat focus, does the delay hold it back?
2. `focus(id:reason:)` and the five call sites — its own commit, since it is
   useful on its own and its risk is unrelated.
3. Presentation 1, with the two-pass height. Evaluate.
4. Presentation 2, on the overlay placement machinery.
5. The Example demo, which is also where the presentations get compared.
