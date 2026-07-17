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
| Window mode (default) | **Divergent, and inconsistent across paths.** The uniform-extent path behaves as Window (line coordinates: an insert-above shifts content down). But the anchored (variable-height) path re-binds its anchor to the row's identity each frame (§5f ladder), so an insert-above *holds the row* — that is **Row** semantics, silently, as the default. Chosen for the anchored path because identity-binding also stabilises against estimate error; the spec says the default must be Window. **Resolution when this feature lands:** the ladder machinery stays, but *policy* becomes explicit — Window mode keeps the ordinal (no key re-bind, line-coordinate-stable); Row mode re-binds by key. Both are one branch in `rebindAnchor`. No architectural conflict; flagged so the current default isn't mistaken for the intended one. |
| Row mode | The machinery exists internally (the §5f key-bound anchor + ladder *is* Row mode, applied to the implicit top-visible row) but there is no API to designate a row, and it only operates on the anchored path. |
| Gap avoidance | Partially: clamping (`maxOffset`) prevents scrolling past the end and content shrinkage pulls the view up — but with no over/underscroll allowance to observe. |
| User adjustability toggle | Not implemented. (`ScrollView.disabled` suppresses keyboard focus but the wheel still scrolls, and chrome doesn't grey out — not the spec's shape.) |
| Selection → Row shadow-switch | Not implemented (needs the selection↔anchor wiring). |
| Sticky edges | Not implemented. End/Home exist as jumps; the *push-past* detection (deliberate vs grazing) lives naturally in `ScrollViewHandler`'s event paths, which see each wheel tick / keypress and can distinguish "clamped this event" from "landed exactly". Additive; no conflict. |
| Code-side restore | Not implemented; recommendation in §3.2. |
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

Two candidate shapes, combinable:

- **Unify "restore" onto Home.** Redefine Home (in scroll contexts) as
  *"restore the code-set anchor"* rather than literally "go to top": when
  the default is Top it is identical to today; when Bottom, Home and End
  both restore (End stays literal for symmetry); when Row, Home returns to
  the anchored row; when Window, Home goes to the top (the natural reading
  of a no-anchor default). One key, one meaning: *back to how the code
  wants it*. The literal go-to-top remains reachable by holding a scroll
  key or the scrollbar. Risk: users expect literal Home; mitigable by
  making this per-ScrollView configurable.
- **Re-selection is the Row restore.** Since selecting a row shadow-switches
  to Row-anchoring *on that row*, "restore to the code-designated row" is
  only distinct when the user has selected a *different* row — and the code
  can always re-assert (§3.2). A dedicated keybinding for this seems
  unearned; recommend not inventing one until a real use asks for it.

### 3.2 Code-side restore

Recommend riding the `ScrollViewReader` parity surface (already on the
roadmap): the proxy gains, alongside SwiftUI's exact
`scrollTo(_:anchor:)`, TUI-specific extensions —

```swift
proxy.restoreDefaultAnchor()      // re-assert the code-set mode
proxy.anchor(to: .top / .bottom)  // imperatively change the CODE-set mode
proxy.anchor(toRow: id)           // Row mode on a designated row
```

SwiftUI source stays portable (the extensions are additive); "Return to
top" / "Follow latest" buttons are one closure each. The alternative — a
bindable `ScrollPosition`-style state object — is closer to iOS-18 SwiftUI
but heavier; the proxy can grow into it later without breaking.

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
