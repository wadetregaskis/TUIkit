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
| Bottom mode | **Shipped**, on every scrollable (`db848b03`, `2d9931e3`). Starts at the tail and follows appends; scrolling up releases it and scrolling back re-engages, because engagement is POSITIONAL (being at the tail *is* the follow — no stored flag to fall out of step). Available from the declaration *and* from a bound `.anchorPosition`, whose write jumps to the edge (§3.2's `anchor(to:)`). **End re-engages** it explicitly. |
| Top mode | **Shipped** (`28ef33e6`), and smaller than it looks. Top asks only that the view stay at the start, and a scroll offset of 0 is not moved by *any* data change — so once the edge modes stopped hijacking the row-identity re-bind (below), Top needed no offset logic at all. Writing `.top` into the binding jumps there; after that it is positional like Bottom. It is deliberately indistinguishable from Window once the user has scrolled away — snapping back unconditionally would nail a `.defaultScrollAnchor(.top)` view to the top and make it unscrollable, which is worse than useless. |
| Window mode (default) | **Resolved (slice 1).** Was divergent: the uniform-extent path behaved as Window, but the anchored (variable-height) path re-bound its anchor to the row's identity every frame (§5f ladder), so an insert-above *held the row* — Row semantics, silently, as the default. Policy is now explicit: `ScrollAnchorMode` (Top/Bottom/Row/Window) is resolved from the environment and passed to `rebindAnchor(mode:)`, which **skips the key re-bind in Window mode**, keeping the ordinal and therefore the position in line coordinates. The ladder machinery is untouched — it now runs only for the row-holding modes, exactly the one branch this row predicted. `AnchorLadderTests` asserts the new default (prepending shifts the view); the test that asserted the placeholder row-holding default was retargeted, not deleted. Note the trade-off the original entry recorded: identity-binding also stabilised against extent-estimate error, so Window leans harder on the estimate — watch for drift on very large variable-height data. |
| Row mode | **Shipped.** `.anchorPosition(_:)` designates a row, and every scrollable holds it — the three stack render paths, `List`, and `Table` (`017683fa`; Table had never been wired to the anchor at all). See §3.4. The one remaining restriction is that a raw stack must be LAZY. |
| Gap avoidance | Partially: clamping (`maxOffset`) prevents scrolling past the end and content shrinkage pulls the view up — but with no over/underscroll allowance to observe. |
| User adjustability toggle | **Shipped** (`bc3c829d`) as `.scrollDisabled(_:)`, SwiftUI's own name. Gates gestures only — wheel, scrollbar, scroll keys, drag auto-scroll — while `scrollTo`, anchors and reveal-on-focus keep working, and a List still follows its selection. Chrome renders in a disabled state, and a blocked wheel tick chains to the parent rather than being swallowed. See below. |
| Selection → Row shadow-switch | **Shipped** (`04b3034c`). Selecting a row — by key or click — turns a declared Top/Bottom anchor into Row on that row, via `ItemListHandler.anchorOnSelection(at:)`. Scoped by two negatives it also tests: a view already released to `.window` is being browsed and is left alone, and Window declares no edge policy to depart from. |
| Sticky edges | **Partly shipped, and partly obsoleted.** Home/End now engage their edge anchor rather than releasing (§1.3's first bullet). The *push-past* half — re-engaging by deliberately scrolling past an edge — is not implemented, but note that the positional engagement above already gives most of it for free: scrolling back to the edge re-engages the follow, with no push required. The spec's "grazing must not stick" caveat now holds **for free** wherever an overscroll allowance is configured: `userScrollFine(by:)` tries ordinary movement before the allowance, so the step that reaches an edge is spent getting there and only the next one pushes into the excursion. Push-past detection therefore has a clean signal to read (`overscrollState.excursion != 0`) and needs no timing or gesture heuristics. |
| Code-side restore | **Shipped** as §3.2 designed it: writing into the bound `.anchorPosition` IS the restore. `.top`/`.bottom` jump to that edge (`anchor(to:)`), `.row(id)` pins that row (`anchor(toRow:)`), `nil` returns to the declaration (`restoreDefaultAnchor()`). No proxy extensions were needed. `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` remains for one-shot SwiftUI-parity seeks. |
| Over/underscroll | **Shipped** on every scrollable (`dbd0fa1f` ScrollView, `b0661dfd` List/Table) as `.scrollOverscroll(top:bottom:)`. The "additive parameter" hope in this row was wrong and §3.3 records the measurement: widening `scrollOffset`'s range TRAPS. The excursion is a separate signed rendering quantity instead, which left the offset's domain — and therefore every data-indexing consumer and both "N more" counts — untouched. |

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

### 3.3 Over/underscroll API — SETTLED (owner decision, 2026-07-26)

```swift
public enum ScrollOverscroll {
    case none
    case rows(Int)              // e.g. 5 rows past the edge
    case viewport(minus: Int)   // the viewport height, less n — `minus: 0` is a full viewport
}
.scrollOverscroll(top: .rows(5), bottom: .viewport(minus: 1))
```

Chosen over the earlier `.absolute` / `.viewportRelative(-1)` sketch because
the call site reads as prose and the relative case says what it means; per-end
(`top:` / `bottom:`) rather than one value, since §1.5 specifies both ends
independently.

**A view whose content already fits may still overscroll** (owner decision).
The allowance is not gated on overflow: a short view can be pushed its full
allowance past the edge and stops there. Note this deliberately *diverges* from
`scroll(by:)`'s existing `extent > viewportHeight` guard, so the excursion
cannot simply ride on that path — the guard governs the offset, and the
excursion is a separate quantity (below).

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

## 3.4 Which scrollables honour a designated row

**Measured 2026-07-21; the size/uniformity restriction below was fixed the same
day (`f1ce2ed6`).**

`.anchorPosition(.row(id))` originally held a row's screen position **only on
the *anchored* render path** — which needs both >256 rows AND variable row
heights. On everything else (so: most real lists) the designation was *silently
inert*: the API accepted it, reported it back through the binding, and did
nothing. That was a spec violation, since §1.1 scopes the modes by *policy*,
never by list size or row uniformity.

All three render paths now honour a designation:

| Path | Rows | How it holds the row |
|------|------|----------------------|
| Anchored walk | >256, variable heights | Structural — rows are laid out RELATIVE to the anchor |
| Uniform arithmetic | any count, equal heights | Corrects the offset; row y is `ordinal * pitch` |
| Exact full walk | ≤256, variable heights | Corrects the offset; row y comes from the walked slot |

The two offset-correcting paths share one adoption rule
(`StackDesignatedAnchor.swift`) and report the corrected offset up the Stage-6
reply channel as `seekResolvedOffset` — a designation is, in effect, a seek
re-issued every frame.

### Still restricted (for a raw stack): it must be LAZY

Anchoring is a property of the **windowed** render paths. A plain `VStack`
inside a `ScrollView` draws its whole canvas and lets the ScrollView clip it —
there is no window, so there is no anchor to hold, and `.anchorPosition` is
silently inert exactly as it used to be everywhere else. Use `LazyVStack`
(or `List`/`Table`).

This was found by running the Example, not by the tests: every unit test used
`LazyVStack`, so the whole suite passed while the demo did nothing.

### List / Table hold too (`8ebace6a`, `017683fa`)

`List` and `Table` do not use a windowed lazy stack for their rows — they scroll
through `ItemListHandler`'s own row-based offset — so the LazyVStack hold above
does not reach them. They had wired the anchor STATE (the §1.2 selection
shadow-switch set the bound anchor onto the picked row, and a wheel scroll
released it) but never adjusted the offset, so the row jumped while the read-out
said "holding row N".

`ItemListHandler.applyAnchorHold` (`ItemListHandler+Anchor.swift`) closes that
gap: it is the row-offset counterpart of `offsetHoldingDesignatedRow` — resolve
the bound `.row(id)` to its ordinal, set `scrollOffset` to keep the row on its
screen row, adopt on change, sticky re-anchor at the edges, reserve both
indicator lines. Gated on a bound `.row` anchor, so every list that doesn't use
`.anchorPosition` is byte-for-byte unaffected. So selecting a List row now both
flips the read-out AND pins the row as data changes around it.

> **Correction (`017683fa`).** This section originally said "List / Table hold
> too" on the strength of Table sharing `ItemListHandler`. That was wrong, and
> wrong for a reason worth keeping: **sharing a handler TYPE is not sharing
> behaviour when each view wires its own per-frame inputs.** Neither of Table's
> two handler-resolution paths captured `environment.anchorPosition`, so the
> binding never reached the handler and *every* anchor behaviour was dead there
> — the row hold, the wheel release, the selection shadow-switch — while its
> twin `List` had them all. `TableRowAnchorHoldTests` now mirrors
> `ListRowAnchorHoldTests` case for case so the two cannot drift apart again.

### The edge modes are POSITIONAL (`28ef33e6`)

`ScrollAnchorMode.holdsRowIdentity` used to read `self != .window`, so `.top`
and `.bottom` re-bound the persisted anchor to a row key exactly as Row mode
does. On the anchored walk that had teeth: under `.top`, a prepend re-bound to
the row that HAD been at the top and the view followed it *down*, away from the
top — Top silently behaving as Row. Only `.row` re-binds now. Bottom is
unaffected in fact as well as in principle: its follow is offset-driven (glue to
`maxOffset`), never key-driven.

### The bound anchor drives the edges too (`db848b03`, `2d9931e3`)

`isGluedToBottom` read `defaultScrollAnchor` alone, so three of the four edge
cases were wrong: a bound `.bottom` was inert, and a bound `.window` or `.top`
did not override a declared `.bottom` — meaning `.window`, the explicit release
that exists precisely to be distinguishable from `nil`, was a read-out with no
behaviour behind it. Both now resolve through
`ScrollAnchorMode.effective(boundAnchor:...)`, and a *newly written* edge jumps
there (§3.2's `anchor(to:)`) — on the change only, since holding an edge every
frame would make the view unscrollable.

Two things worth remembering from wiring the List/Table side:

- **The focus cursor comes along.** A follow that moved the offset alone was
  undone within the same frame: focus registration calls
  `ensureFocusedItemVisible()`, which drags the viewport back to the cursor
  (row 0 by default), and row 0 is not visible from the tail. That reveal is the
  shipped "selection must stay visible" invariant, so the follow carries the
  cursor to the last row instead — which is what following a log means anyway.
- **`maxOffset` needs reading twice.** It early-outs to a cheap floor while the
  offset is far from the tail (so a huge list needn't materialise tail row
  heights every frame). That floor is a lower bound, so one assignment lands
  short; the assignment itself brings the offset within reach of the exact walk,
  so a second read converges. By construction, not a loop.

Home and End engage their edge rather than releasing to `.window` (§1.3), and
`engageEdgeAnchor` writes **`nil`** when the view's own declaration already names
that edge — so pressing End on a `.defaultScrollAnchor(.bottom)` log leaves the
app's "am I still following?" test (`anchor == nil`) answering yes.

### Adoption is now consistent across all three paths (`7a338d0d`)

Every path adopts a designated row by **holding the screen line it already
occupies** (and revealing an off-screen one by minimal movement). This was the
last inconsistency: the anchored walk used to slam the row to the viewport
**top**, so identical app code jumped or didn't depending purely on row count,
and the §1.2 selection shadow-switch inherited that jump on every first
arrow-key press.

The fix generalised `anchorOffsetWithin` to **signed** — negative meaning the
anchor sits that many lines *below* the viewport top, which is exactly the
"anchor below the top" the invariant `anchorY = offset - anchorOffsetWithin`
could not previously express. Adoption walks real pitches from the old anchor to
find the row's current line (bounded — a visible row is at most a viewport of
rows away; farther is off-screen and revealed at the top edge), and `fill` walks
upward from the anchor to draw the now-visible rows above it (collapsing to the
old single-margin-row behaviour when the anchor is at/above the top). A
sticky-top clamp (`clampDesignatedHold`) rides the row up if the rows above it
are deleted past its held line, so it never leaves a blank strip.

### Overscroll shipped for `ScrollView` (§1.5) — List/Table still to come

`.scrollOverscroll(top:bottom:)` is live on `ScrollView`. The constrained design
of §3.3 held up: `scrollOffset` never leaves `[0, maxOffset]`, and the excursion
is a separate signed quantity on `ScrollOverscrollState`. Consequences that fell
out rather than being built:

- **The indicators needed no work at all.** They read the offset, so "N more
  below" stays 0 while the view is pushed past the bottom — pushing past an edge
  does not invent content.
- **No data-indexing consumer needed auditing**, which was the whole point of
  not widening the offset's range.
- **§1.3's graze-versus-push distinction is free.** `userScrollFine(by:)` tries
  ordinary movement *before* the allowance, so the step that reaches an edge is
  spent getting there and only the next one pushes. A scroll that happens to
  land on the edge therefore never sticks.

Rendering is a post-hoc slide of the finished viewport buffer
(`_ScrollViewCore.applyOverscroll`), applied to the content *before* the chrome
so the scrollbar and indicators stay put — and via `replacingLines`, so hit
regions and overlays travel with the content and a control pushed down the
screen is still clickable where it is drawn.

Verified live: with `top: .rows(2)`, a wheel tick at the top opens exactly two
blank rows above `Line 1`, and a second tick adds nothing.

**`List` and `Table` now covered too.** They could not reuse the `ScrollView`
technique: that one slides the finished viewport buffer, which works only
because the bar is appended as a whole column afterwards. `_ListCore` and
`Table` merge a bar cell into each line as they build it
(`lines.append(fitted + pad + barCell(at: lines.count))`) and stitch the "N more"
indicators in at top and bottom, so sliding the finished lines would carry the
chrome with the content.

All five composition sites (List: bar / bar-less; Table: bar / single-line /
multi-line) now collect **content-only row lines**, slide those, and assemble the
chrome around them afterwards — the bar re-paired by absolute line index so it
cannot move. `_ListCore`'s `VisibleRowRange`s take the same slide (clipped, not
translated, so a partly-visible row stays clickable over the part that is drawn),
or clicks would land on the wrong row.

> **Table configures its handler from TWO independent places** — `resolveHandler`
> for single-line rows, and an inline block in `buildMultiLineContent` for
> multi-line ones. Anything captured in only one is silently dead on the other
> path. This is `017683fa` recurring, and it caught a **real shipped bug**:
> `bc3c829d` put `handler.isScrollEnabled` in the multi-line block only, so
> `.scrollDisabled` never reached a single-line Table. Fixed alongside; both
> captures now live in `resolveHandler` as well.

### User adjustability shipped as `.scrollDisabled(_:)` (§1.2, first half)

The "whether the end-user may adjust the scroll position at all" half of §1.2
is done. It needed no new vocabulary: SwiftUI already names it, so the modifier
is `scrollDisabled(_ disabled: Bool)` exactly, over an internal
`\.isScrollEnabled` environment value that each scrollable captures onto its
handler each render (event-time code cannot reach the environment).

The line it draws is **user input versus everything else**:

| Stops | Keeps working |
|---|---|
| Wheel / trackpad | `ScrollViewProxy.scrollTo(_:)` |
| Scrollbar arrows, track, thumb (and any auto-repeat mid-hold) | Anchors — the hold, the edge follow, `.anchorPosition` |
| Arrows / Page / Home / End on a focused `ScrollView` | Reveal-on-focus, and a List/Table following its selection |
| Drag auto-scroll (the zone is not registered at all) | The clamp after data shrinks |

Three consequences worth keeping:

- **A blocked wheel tick is not consumed**, so it chains to the enclosing
  scroller — the same rule as a tick at a scroller's own edge. A pinned inner
  pane must not trap the wheel over the page behind it. Confirmed live: pinning
  the Example's configurable demo leaves it on line 1 while the wheel over it
  scrolls the page.
- **Selection is not scrolling.** A `List` still moves its cursor under the
  arrow keys and still reveals it. Gating that too would let the cursor leave
  the viewport for good, which is unusable — and moving a cursor was never
  "adjusting the scroll position".
- **A pinned `ScrollView` leaves the focus ring** (`canBeFocused` gains
  `isScrollEnabled`), for the same reason a non-overflowing one does: with no
  scroll command left, the Tab stop is only an obstacle.

The chrome requirement is met literally — `ScrollbarColors.focusIndicating`
gains a disabled branch one step quieter than the resting bar (tertiary thumb,
quaternary arrows), so the bar keeps its arrows and thumb and simply reads as
inert. It must not vanish, or the view reads as having run out of content.

The second half of §1.2 — the shadow/code-set split — is separate and already
largely landed (selection → Row, scroll → Window; see above).

---

## 4. Interim guardrails (in force now)

While the feature is pending, work on the branch observes:

1. ~~No API is added that hard-codes a two-mode (top/bottom) worldview; the
   `UnitPoint`-based `defaultScrollAnchor` is forward-compatible (Row mode
   will arrive via a separate designator, as in SwiftUI).~~ **Discharged:**
   the designator shipped as `.anchorPosition(_:)`, taking a
   `Binding<ScrollAnchor<ID>?>` rather than a `UnitPoint`.
2. ~~The anchored path's row-holding default is understood to be a
   *placeholder policy*, not the final default.~~ **Discharged (slice 1):**
   the default is now explicitly Window. The surviving half of the rule
   still holds — anything depending on hold-the-row semantics goes through
   `rebindAnchor`/`ScrollAnchorMode` so the policy switch stays one branch.
3. Scroll-clamping changes keep the allowance parameter in mind (no new
   call sites that assume `[0, maxOffset]` is closed forever).
