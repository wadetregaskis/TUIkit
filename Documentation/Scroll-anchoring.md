# Scroll anchoring

**Status:** specified (by the project owner, 2026-07-17), partially
implemented. This is a feature in its own right — related to, but
conceptually distinct from, "Locating things without drawing them", whose
anchor machinery is the natural substrate for it. This document records the
spec so no interim decision forecloses it, maps what exists today onto it,
and holds the open recommendations.

---

## 1. The specification

### 1.1 Anchor modes (code-settable)

| Mode | Meaning |
|---|---|
| **Top** | The view stays at the top, irrespective of rows being added, removed, or moved. |
| **Bottom** | The view stays at the bottom, irrespective of row changes (follow-the-log). |
| **Row** | A specific row stays in the same place on screen wherever possible, as other rows change around it. If a scroll is *forced* (rows above it removed, screen space must fill), the row pins to the nearest achievable position — and the anchor setting itself is unchanged. |
| **Window** (default) | Technically *no anchor*: the scroll position stays where it is **in line coordinates** unless an explicit action moves it (user scrolling, focus-driven reveal) or it must move to avoid rendering gaps (rows removed off the bottom → scroll up so no erroneous blank lines, observing the over/underscroll settings). |

### 1.2 User adjustability (code-settable, default on)

Whether the end-user may adjust the scroll position at all. When disabled,
scrollbars and other scroll chrome still render, in a disabled state.

When enabled, user actions move a **shadow** anchor mode — the code-set mode
is always preserved underneath:

- Selecting a row → shadow-switches Top/Bottom modes to **Row** (the
  selected row).
- Scrolling → shadow-switches to **Window**.

### 1.3 User-side restore of the code-set mode

- **Home** restores an anchor-to-top default; **End** restores
  anchor-to-bottom.
- **Sticky edges**: deliberately pushing *past* the top or bottom — arrow
  keys, wheel, trackpad, scrollbar — re-engages the corresponding edge
  anchor. Merely *grazing* the edge (a scroll that happens to land exactly
  there, no further) does not stick.
- Open: how a user expresses "restore to Row / Window" code defaults —
  see §3.1 below.

### 1.4 Code-side restore

Programmatic re-assertion of the code-set mode, so apps can wire explicit
"Return to top" / "Follow latest" buttons. Mechanism: see §3.2 below.

### 1.5 Overscroll / underscroll

Settings for whether — and by how much — the scroll position may exceed the
content, at both ends, specifiable as **absolute** rows (`5`) and
**relative** expressions (`height − 1`).

---

## 2. What exists today, mapped honestly

| Spec item | State on the `locating-without-drawing` branch |
|---|---|
| Bottom mode | **Shipped** as `defaultScrollAnchor(.bottom)`: starts at the tail, follows appends; user scrolling up releases (a shadow-switch to Window, in the spec's terms); **End re-engages**. The code-set mode (the environment value) is inherently preserved — an accidental match with the shadow-settings model. |
| Top mode | Not distinct yet. Today's top-ish behaviour is the *absence* of the bottom anchor, which is really… |
| Window mode (default) | **Resolved (slice 1).** Was divergent: the uniform-extent path behaved as Window, but the anchored (variable-height) path re-bound its anchor to the row's identity every frame (§5f ladder), so an insert-above *held the row* — Row semantics, silently, as the default. Policy is now explicit: `ScrollAnchorMode` (Top/Bottom/Row/Window) is resolved from the environment and passed to `rebindAnchor(mode:)`, which **skips the key re-bind in Window mode**, keeping the ordinal and therefore the position in line coordinates. The ladder machinery is untouched — it now runs only for the row-holding modes, exactly the one branch this row predicted. `AnchorLadderTests` asserts the new default (prepending shifts the view); the test that asserted the placeholder row-holding default was retargeted, not deleted. Note the trade-off the original entry recorded: identity-binding also stabilised against extent-estimate error, so Window leans harder on the estimate — watch for drift on very large variable-height data. |
| Row mode | The machinery exists internally (the §5f key-bound anchor + ladder *is* Row mode, applied to the implicit top-visible row) but there is no API to designate a row, and it only operates on the anchored path. |
| Gap avoidance | Partially: clamping (`maxOffset`) prevents scrolling past the end and content shrinkage pulls the view up — but with no over/underscroll allowance to observe. |
| User adjustability toggle | Not implemented. (`ScrollView.disabled` suppresses keyboard focus but the wheel still scrolls, and chrome doesn't grey out — not the spec's shape.) |
| Selection → Row shadow-switch | Not implemented (needs the selection↔anchor wiring). |
| Sticky edges | Not implemented. End/Home exist as jumps; the *push-past* detection (deliberate vs grazing) lives naturally in `ScrollViewHandler`'s event paths, which see each wheel tick / keypress and can distinguish "clamped this event" from "landed exactly". Additive; no conflict. |
| Code-side restore | The **vehicle shipped**: `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` (SwiftUI parity, all three seek paths, same-frame). The TUI restore extensions themselves (`restoreDefaultAnchor()` etc., §3.2) await this feature. |
| Over/underscroll | Not implemented. Clamping is centralised (`clampScrollOffset` / `maxOffset`), so the allowance is an additive parameter, not a rework. Note the negative-size crash class: over/underscroll maths must clamp at source and sink like all chrome subtraction. |

**Substrate compatibility:** the locating work *enables* rather than
obstructs this feature. All four modes are policies over the same
persisted triple the anchored path already keeps — (row key, ordinal,
offset-within) — plus the glue rule; the shadow/code split is one extra
stored mode enum; nothing in the sliced pipeline, the reply channel, or
the seek ladder assumes a particular policy.

---

## 3. Recommendations (open for owner review)

### 3.1 User-side restore of Row / Window defaults

**Owner decision (2026-07-17): Home and End keep their literal, well-known
meanings — scroll to top and bottom respectively — everywhere, always.**
Redefining Home as "restore the code-set anchor" was considered and
rejected: it would make Home behave inconsistently across Lists / Tables /
ScrollViews depending on each one's configured default.

Remaining candidates:

- **A modified Home (e.g. Option-Home) as "restore the code-set anchor"**,
  if it doesn't conflict with anything. Caveat to check at implementation
  time: modifier forwarding on Home/End is terminal-dependent (Terminal.app
  is known to strip modifiers from Up/Down while keeping them on
  Left/Right; Home/End forwarding is unmeasured). Probe per
  `Documentation/Terminal-compatibility.md` before committing to a binding.
- **Re-selection is the Row restore.** Since selecting a row shadow-switches
  to Row-anchoring *on that row*, "restore to the code-designated row" is
  only distinct when the user has selected a *different* row — and the code
  can always re-assert (§3.2). A dedicated keybinding for this seems
  unearned; recommend not inventing one until a real use asks for it.

### 3.2 Code-side restore — SUPERSEDED (owner decision, 2026-07-21)

~~Proxy extensions `restoreDefaultAnchor()` / `anchor(to:)` / `anchor(toRow:)`.~~

**Replaced by a single bound anchor**, which subsumes all three:

```swift
public enum ScrollAnchor<ID: Hashable> { case top, bottom, row(ID), window }

List { … }
    .defaultScrollAnchor(.bottom)     // the DECLARED anchor (SwiftUI parity)
    .anchorPosition($anchor)          // Binding<ScrollAnchor<ID>?> — live
```

**A non-nil binding overrides the declaration; `nil` means "no departure from
it".** Because a declarative modifier is re-asserted every render, the declared
anchor is always recoverable — so the framework needs no hidden shadow state,
and writing `nil` *is* `restoreDefaultAnchor()`. Writing `.row(id)` is
`anchor(toRow:)`; writing `.top`/`.bottom` is `anchor(to:)`. All three proxy
methods, and the `ScrollViewReader` wrapper they required, disappear.

**`nil` and `.window` are deliberately distinct.** `.window` is an *explicit
release* (the user scrolled away); `nil` is *never left*. Without that split
the binding could not answer "am I still following the log?" — with it, that
question is `anchor == nil`. An earlier `Binding<ID?>` sketch could not express
it: `nil` would have had to mean both "restore the declaration" (app-written)
and "released from it" (framework-written), which are opposites.

`.top`/`.bottom` are **positional**, `.row` is **identity**, and they are not
interchangeable — encoding the edges as sentinel row ids would collapse exactly
the divergence they exist to express (`.bottom` re-targets to the new last row
on append; `.row(lastID)` pins to the old one). See `ScrollAnchor`'s doc
comment.

Note the framework currently writes back only the id-free cases (`.window` on
user scroll); `.row` write-back needs the selection↔anchor wiring of §1.2 and
lands with it.

*Not yet reconsidered:* whether an app also wants a read-only *effective* mode
when the binding is `nil` (it reports "following the declaration", not which
edge). Deferred until a real use asks.

### 3.3 Over/underscroll API sketch

```swift
enum ScrollOverscroll {
    case none
    case absolute(Int)              // e.g. 5 rows past the edge
    case viewportRelative(Int)      // e.g. viewport height − 1
}
.scrollOverscroll(top: …, bottom: …)
```

Interacts with: clamp maths, the "N more" indicators (which must not count
overscroll as content), sticky-edge detection (pushing into overscroll is
the definitive "deliberate" signal — a nice synergy: the overscroll region
makes edge-stickiness discoverable and grazing-safe by construction).

**Implementation constraint, measured 2026-07-21 — overscroll must NOT be
expressed as an out-of-range `scrollOffset`.** §2's note that the allowance
is "an additive parameter, not a rework" is too optimistic: widening
`clampScrollOffset`'s bounds so the offset itself may go negative (or past
`maxOffset`) reaches consumers that assume the offset is in `[0, maxOffset]`
and **traps**, not merely misdraws —

- `_ListCore.swift` `(0..<handler.scrollOffset)` — a negative offset is a
  fatal range (`lowerBound <= upperBound`); an over-max offset indexes
  `source.row(at:)` past the data.
- `ScrollView.swift` `full.lines.dropFirst(scrollOffset)` — `dropFirst`
  traps on a negative count.
- `ScrollableOffsetState.hasContentAbove` / `rowsAbove` (`scrollOffset > 0`
  / `= scrollOffset`) report nonsense either side, which is the same
  "indicators must not count overscroll as content" problem seen from the
  other end.

This is the negative-size crash class (see the terminal-compatibility notes
on clamping chrome subtractions at source AND sink) applied to the scroll
axis. **Recommended shape:** keep `scrollOffset` in its current valid domain
and carry the excursion as a separate signed *rendering* quantity (blank
lines drawn past the edge) that the clamp permits, the renderer honours, and
the indicators ignore. Data-indexing consumers then need no audit at all,
and the sticky-edge detector reads the excursion directly — which is a
cleaner "deliberate push" signal than inferring it from a clamped offset.

---

## 4. Interim guardrails (in force now)

While the feature is pending, work on the branch observes:

1. No API is added that hard-codes a two-mode (top/bottom) worldview; the
   `UnitPoint`-based `defaultScrollAnchor` is forward-compatible (Row mode
   will arrive via a separate designator, as in SwiftUI).
2. The anchored path's row-holding default is understood to be a
   *placeholder policy*, not the final default; anything new that depends
   on hold-the-row semantics must go through `rebindAnchor` so the policy
   switch stays one branch.
3. Scroll-clamping changes keep the allowance parameter in mind (no new
   call sites that assume `[0, maxOffset]` is closed forever).
