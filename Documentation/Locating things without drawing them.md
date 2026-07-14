# Locating things without drawing them

*A design for reveal-on-focus, viewport-only rendering, and incremental
layout — which turn out to be one problem, not three.*

**Status:** proposed. Nothing here is implemented except the prerequisite
fix in §9. Revised once after adversarial review; §6 records every
alternative considered and why it lost.

---

## 1. Start with the bug

Type this into TUIkit today:

```swift
ScrollView {
    LazyVStack {
        ForEach(0..<500) { i in
            Button("row \(i)") { … }
        }
    }
}
```

Six buttons work. The other 494 cannot be focused or Tabbed to. Not "are
hard to reach" — they do not exist as far as the focus system is
concerned.

Measured (how many rows `focus(id:)` can actually land on; viewport ≈ 6):

| Composition | Reachable |
|---|---|
| plain `VStack` inside `ScrollView` | **60 / 60** ✓ |
| `LazyVStack` inside `ScrollView` | **6 / 60** ✗ |
| `LazyVStack` on its own | **6 / 60** ✗ |

Row 1 is the whole story. The plain `VStack` works — but not because
anything is right. It works because `ScrollView` renders **all** of its
content and throws most away. The bug exists in every container; it is
*hidden* by the exact wastefulness we want to remove.

**So this is not "fix the bug, then optimise". Optimising is what exposes
the bug everywhere.** They are the same work.

### Why it happens

1. `FocusRegistration.register` opens with
   `guard !context.isMeasuring else { return }`
   (`FocusRegistration.swift:109`) — registration happens only while
   *rendering*.
2. `FocusManager.beginRenderPass()` calls `sections.removeAll()`
   (`Focus.swift:620-621`) — the *enumeration* is rebuilt every frame.
   It deliberately **preserves `focusedID`** (`Focus.swift:626-627`).
3. `LazyVStack` skips off-window rows entirely — no `child.render`
   (`VStack.swift:390-394`).
4. `focus(id:)` for an unknown id silently does nothing
   (`Focus.swift:247-258`), so it fails quietly.

That asymmetry in (2) is the crux, and it is worth stating precisely:

> **Focus identity is durable. The enumeration of what can be focused is
> ephemeral — it is exactly the set of controls drawn last frame.**

Closing that gap is what this design is for.

---

## 2. The one idea

Three apparent features:

- **Reveal** — when focus moves, scroll so you can see it.
- **Windowing** — draw only what's on screen.
- **Enumeration** — know what exists, to Tab through it.

All ask one question:

> **"Where is X, and does it exist — without drawing X?"**

And they stack: you cannot reveal what you cannot focus; you cannot focus
what you cannot enumerate. Reveal — the feature we set out to build — sits
on top of the one that's broken.

That gives a single falsifiable test:

> **The disqualifier.** You cannot find, *by drawing*, the position of
> something you are not drawing. Any design that answers "where is X?" by
> searching a rendered buffer forces `ScrollView` to render what it must be
> free to skip. It cannot be optimised later; it must be *replaced*. That is
> not an open path — it's a dead end with a rewrite at the end.

Today's reveal is exactly that (`ScrollView.swift:265`):

```swift
fullBuffer.hitTestRegions.first(where: { $0.focusID == focusedID })
```

It can only find what is already drawn.

---

## 3. What we optimise for: the second frame

Almost no frame is the first. The user scrolls a line; a spinner ticks.
**Between frames, almost nothing changed.** A design that recomputes the
world every frame is wrong even if cold-start looks fine.

The stress case:

> A list is scrolled to line **50,000,000**. The user presses Up. Rows are
> **not** uniform height.

The right cost is: **look at row 49,999,999.** One row.

### Absolute positions are the trap

If the scroll position is "y = 3,204,918", drawing the viewport requires
the total height of rows 0…49,999,999 — measuring every one. That cost is
real: row *i*'s y genuinely isn't determined by anything less than every
height before it. It's information-theoretic, not a design flaw.

**So don't ask for it.**

### Anchors

Model the scroll position as a **place in the content**:

```swift
struct ScrollAnchor {
    var item: ViewIdentity   // "row 50,000,000"
    var offsetWithin: Int    // "…and 3 lines into it"
}
```

| Operation | absolute `y` | anchor |
|---|---|---|
| scroll up one line | recompute prefix sum | look at the row above — **O(1)** |
| draw the viewport | need y of every row above | fill from the anchor — **O(visible)** |
| `scrollTo(row 50M)` | measure 50M rows | **set the anchor — O(1)** |
| reveal a focused row | measure up to it | **set the anchor — O(1)** |

Revealing something 50 million rows away is **O(1)** because you never
compute where it is; you *declare* it the anchor and lay out around it. The
Ω(i) doesn't vanish by cleverness — it vanishes because nobody needs the
number.

### This already ships here

The strongest evidence isn't UIKit or VS Code — it's `ItemListHandler`,
which **is** this design, in production, proven on the megalist benchmark:

- `scrollOffset` is "first visible **item index**" and `scrollTopClipLines`
  is "how many lines of the top row are scrolled off"
  (`ItemListHandler.swift:214, 223`). That pair *is*
  `ScrollAnchor { item, offsetWithin }`.
- Its own doc comment says these "stay row-based (**O(1) for any list
  size**)" (`:219-223`).
- `rowHeight: ((Int) -> Int)?` (`:140`) is a per-index height oracle.
- `maxOffset` (`:153-179`) walks back from the tail accumulating real
  heights with an estimate short-circuit, explicitly "to avoid
  materialising tail rows' heights every frame on large lists".
- `ensureFocusedItemVisible` (`:689`) walks back from the focused index
  accumulating heights until the budget fills.

We are not inventing a model. We are **generalising `List`'s**, which is
why §6g is the option we adopt rather than reject.

### What we give up, honestly

The scrollbar thumb needs "how far through are we?" — `y / totalHeight`,
the number we refuse to compute. **Estimate it, and say so:** use item
index, refined as rows are measured. The thumb may drift and settle. This
is a terminal scrollbar; every virtualised list makes this trade, and
`maxOffset` above already does. Uniform-height content (TUIkit's default
`List`/`Table` line mode) is exact anyway.

---

## 4. The design

### 4a. The identity chain is the route

`ViewIdentity` is structural and parent-linked: `IdentityNode` has
`let parent` (`ViewIdentity.swift:240`), and the `child(…)` family —
`child(type:index:)` at `:109`, `child(erasedType:key:)` at `:147` —
**builds a child's identity without rendering it**. That is the whole
foundation: the address of a thing exists before the thing does.

So a container never searches. Given a target, a container at depth *d*
reads step *d+1* of the target's chain and knows which child leads there:

```
target chain:  Root → ScrollView → VStack → [child #37] → Button
container:     ────────────────────┘
                                     reads step d+1 → "child #37"
```

**O(1) per level.** Nothing measured, nothing drawn. (An earlier sketch had
containers *probing* each child — O(N) before pruning. The chain already
holds the answer.)

`ViewIdentity` is `Hashable` and public — it is the key type throughout.
(`IdentityNode.Step` is **not** usable: internal to TUIkitCore, `Sendable`
only, and its `.typed(Any.Type, …)` payload isn't `Hashable`.)

### 4b. One traversal, many visitors — and it must be seekable

Each container gains one method enumerating its children's **placements**
(child + identity + rect), computed from measurement, not rendering.

The signature must be **seekable and bidirectional from day one**:

```swift
protocol LayoutPlacing {
    /// Placements are addressed by ordinal so a caller can START at the
    /// anchor and walk OUTWARD in both directions, rather than from child 0.
    func placementCount(proposal: ProposedSize, context: RenderContext) -> Int
    func placement(at ordinal: Int, proposal: ProposedSize, context: RenderContext) -> Placement?
    func ordinal(of step: ViewIdentity, context: RenderContext) -> Int?
}
```

**Why seekable now, not later:** a `forEach`-with-`.stop` callback can only
*stop* early — reaching row 49,999,999 still costs 49,999,999 callbacks,
and filling a viewport upward from an anchor has no direction at all. By
this design's own falsification criterion (§8), a protocol that Stage 5
must change is a protocol that was wrong.

Everything else is a **visitor**:

| Visitor | Predicate | Cost |
|---|---|---|
| **Locate** | "does this lead to the target?" — route, don't scan | O(depth) |
| **Window** | "does this rect meet the viewport?" — walk out from the anchor | O(visible) |
| **Enumerate** | "is this focusable?" — see §4d | O(visible + margin) |
| **Extent** | sum / estimate | O(1) uniform |

These four **must agree** or reveal drifts — "scrolls to slightly the wrong
place, sometimes". Deriving them from one enumeration makes disagreement
impossible by construction. This isn't speculative:
`_VStackCore.renderViewportWindow` (`VStack.swift:369-411`) already *is*
this traversal, hand-written for one container against one ad-hoc
environment key.

**Locate returns an offset, resolved inner-first:**

```swift
enum LocateResult { case notMine, found(offsetWithinMe: Int, height: Int) }
```

Each level composes its child's answer with that child's own offset. A
nested `ScrollView` resolves in its content, sets its own anchor, and
reports the target's **viewport-relative** position upward. Nesting is the
recursion — the one genuinely good property of the rejected §6a, preserved.

### 4c. Fill rules (not an afterthought)

- **Forward, then backward.** Fill from the anchor downward; if the
  viewport is unfilled and the anchor isn't first, fill *upward*, then
  re-clamp. Without this, content shrinking above the anchor leaves the
  viewport half-blank.
- **Reveal only when needed.** If the target is already fully visible,
  **do nothing.** This rule is the difference between "reveal" and "the
  viewport jumps whenever I press an arrow key". Both shipping
  implementations are already conditional (`ScrollView.swift:280-301`
  adjusts only when the region falls outside; `ensureFocusedItemVisible`
  likewise). "Set the anchor to it" is the O(1) punchline but it is the
  *else* branch.

### 4d. What the focus ring contains

Apply §3's argument to focus: **"how many focusables exist in total" is
Ω(N) and must never be asked.** A flat registry of 50M rows is the same
mistake as an absolute y.

So the ring is not a list — it is a **directional query**. `FocusManager`
retains `focusedID` and its identity (it already preserves `focusedID`
across passes, §1), and answers *next* / *previous* by routing to the
owning container, which walks outward from the focused ordinal and only
escapes to its parent at its ends.

This is forced, not stylistic. Today `FocusSection.focusables` is a flat
`[Focusable]` whose `register` linear-scans for a duplicate focusID
(`FocusSection.swift:39-42`) — Ω(N²) to populate — and `moveFocusInSection`
does `section.focusables.filter { $0.canBeFocused }`, copying the array, on
**every arrow keypress** (`Focus.swift:732`; `focusBoundaryOfActiveSection`
copies it again at `:605`). A design headlining "50M rows, single-digit rows
touched" cannot leave that intact.

### 4e. State vs cache — the split that makes the invariant testable

```swift
// STATE: authoritative. Persisted in StateStorage beside ScrollViewHandler.
// Losing it loses the user's scroll position.
struct ScrollPosition {
    var anchor: ScrollAnchor
    var anchorLadder: [ViewIdentity]  // K neighbours, for recovery (§4f)
    var estimatedItemExtent: Int
    var measuredCount: Int
}

// CACHE: disposable. Framework-owned, keyed like RenderCache.SizeKey.
// Dropping it must change nothing but speed.
struct LayoutCache { /* [SizeKey: Int] */ }
```

Two rules make this safe:

- **The cache is never a source of truth.** Dropping it entirely must
  produce a byte-identical frame, only slower. There must be a test that
  clears it every frame and asserts identical output.
- **Key on the proposal; never clear on it.** `RenderCache.SizeKey`
  (`TUIkitView/Rendering/RenderCache.swift:141`) is already public,
  `Hashable`, and carries identity + proposal + available size +
  explicit-size flags. Reuse that shape. "Clear when the proposal changes"
  would be self-defeating: `resolveScrollbars` re-measures at several widths
  within a single frame, so a clear-on-change rule throws the cache away up
  to three times per frame.
- **Ownership and eviction already exist.** One framework-owned store keyed
  by `ViewIdentity`, living beside `RenderCache` in **TUIkitView** (the
  module below TUIkit, so containers can reach it), read through
  `RenderContext`, GC'd by the existing `markActive` (`:306`) /
  `removeInactive` (`:321`). No new lifecycle, no new module edge.

### 4f. When the anchor disappears

`ForEach` keys rows by `String(describing: element[keyPath: idKeyPath])`
(`ForEach.swift:113`), so identities survive reorder — but the anchored row
can be **deleted**, filtered out, or collapsed.

- The anchor is a **ladder**: primary identity plus K neighbours captured
  from last frame. On a miss, anchor to the nearest survivor, preserving
  `offsetWithin`.
- If the whole ladder is gone (list replaced), fall back to the last known
  *index*, clamped — approximate, and correct at the ends.
- Empty content: anchor is nil; viewport renders empty; scroll is a no-op.

---

## 5. Worked example

`ScrollView { LazyVStack { ForEach(0..<50_000_000) { Row($0) } } }`,
anchored at row 50,000,000. User presses Up.

1. **Input** → anchor moves to the previous row; its height is cached (it
   was just on screen). **O(1).**
2. **Render** → `placement(at:)` from the anchor's ordinal, walking down
   until the viewport fills; then the backward fill if needed. **~6 rows.**
3. **Enumerate** → the same walk registers those rows' focusables plus a
   margin. Rows beyond are *knowable* (§4d routes to them on demand) but
   never enumerated.
4. **Scrollbar** → `estimatedItemExtent × 50M`, refined.

Then Tab, where focus must leave the window:

1. `next` routes to the owning container, which walks outward from the
   focused ordinal — it does not consult a list of 50M.
2. `ScrollView` sees a new reveal generation, calls `locate`; the identity
   chain routes in O(depth).
3. Target already visible? **Do nothing** (§4c). Otherwise set the anchor.
   **O(1).**

---

## 6. Options considered, and why they lose

Eighteen, grouped. Each rejection is one paragraph; that is deliberate.

### The one we adopt

**6g. Generalise `List`'s model (`ItemListHandler`).** `_ListCore`
registers **one** `Focusable` for a whole list (`_ListCore.swift:391`);
the focused row is an index into the *data*; scroll is index + clip-lines;
heights come from an oracle. It is anchor-based, O(1) at any size, and it
ships. **Why it wins:** it's proven here, on this codebase, at scale. This
design is that model lifted out of `List` and made general — which is the
whole task, since "special-case for a subset of views" is what we were
asked to stop doing.

### Locate by drawing — fails the disqualifier

**6a. Anchors riding the `FrameBuffer`** *(the author's first proposal)*.
Views emit a reveal-anchor rect beside `hitTestRegions`; it's translated on
composite and clip; each `ScrollView` finds it in the full content buffer.
Genuinely elegant for nesting — bottom-up rendering means the inner view
fixes its offset before the outer looks. **Why it loses:** the anchor only
exists if the target was drawn. It doesn't merely fail to help with
windowing — it **depends on windowing never happening**, cementing the
thing we're removing. Its nesting property is preserved in §4b.

**6b. Hybrid: anchors when drawn, locate when not.** **Why it loses:** the
fast path optimises a case that doesn't exist — anchors cover what was
drawn; what was drawn is visible; **what is visible needs no revealing.**
Two mechanisms, two bug sets, and a seam where behaviour depends on whether
something happened to be on screen.

### Don't locate at all

**6n. Explicit-only reveal (`ScrollViewReader.scrollTo`).** SwiftUI's
actual answer; also a real parity gap (`ScrollViewReader`, `ScrollViewProxy`
have zero occurrences in `Sources/`). **Why it loses:** it doesn't fix the
bug — 494 buttons are still unfocusable, and `scrollTo(id:)` needs the very
"where is id?" query this design provides. We should ship it *on top* of
§4, not instead.

**6k. Roving cursor: the lazy container is one tab stop.** What the field
actually ships — react-window doesn't make off-screen rows tabbable.
**Why it loses:** it's `List`'s model applied by fiat to `LazyVStack`, and
it silently changes what `Button` means inside a lazy stack. Worth offering
as a *style*, not as the framework's answer to "reveal must be universal".

**6r. Make the composites leaves.** Nothing inside `Menu`/`List` is
independently focusable. **Why it loses:** this is precisely why `List`
works and `LazyVStack` doesn't — it is the special-casing we were asked to
eliminate, generalised in the wrong direction.

**6p. Materialise a bounded band** (viewport ± N screens, clamp scrolling).
**Why it loses:** the focus ring becomes the band — the 500-button bug
moved and rescaled, not fixed. And it breaks `scrollTo` past the band.

### Locate differently

**6m. Prefix-sum / order-statistics tree** (Fenwick; VS Code's
`PrefixSumComputer`). y(i) and y→row in O(log N). **Why it loses *here*:**
it's an excellent answer to a question we've decided not to ask. It buys
exact absolute offsets at the cost of maintaining a tree over 50M rows
whose heights we deliberately never measure. Keep it in the back pocket for
uniform-height content wanting an exact scrollbar.

**6l. Estimated absolute offsets (`estimatedRowHeight`).** Keep
`scrollOffset: Int`; estimate unmeasured rows. Cheapest migration.
**Why it loses:** estimates in an *absolute* space are cumulative — every
correction below the viewport shifts everything above it, so the content
jitters as you scroll. Anchors localise the error to one row.

**6q. Reveal by estimate, converge over frames.** **Why it loses:**
visible jumping; unbounded with variable heights, since each correction
changes the estimate that produced it; and it can oscillate.

**6o. Enumerate structurally, place lazily.** Walk the structure without
measuring, register every focusable, compute geometry only at reveal. The
obvious naive fix. **Why it loses:** the walk is Ω(N) per frame — it is the
flat 50M-entry registry §4d refuses.

### Change the architecture

**6i. Retained view tree (React fibers).** **Why it loses:** it doesn't
answer the question. A fiber exists only once created, so an uncreated row
is still invisible to focus. It's a large rewrite that leaves the bug.

**6j. Separate retained layout tree (Flutter `RenderObject`).** The
canonical "layout is retained though rendering isn't" answer, and honestly
the closest thing to a rival. **Why it loses *for TUIkit*:** it's a
ground-up re-architecture of a shipping immediate-mode renderer to buy what
§4e's cache buys incrementally. If TUIkit were greenfield this would
deserve a real hearing.

**6h. Adopt SwiftUI's `Layout` shape.** `sizeThatFits(proposal:subviews:cache:)`
+ `placeSubviews`, where `LayoutSubviews` is a **`RandomAccessCollection`**
of proxies. **Why it partly wins:** it validates §4b's seekable shape and
§4e's cache — we should borrow its vocabulary. **Why not wholesale:**
`LayoutSubviews` is still a materialised collection of every subview, which
is precisely the foundation problem in §8.

### Non-starters, recorded so nobody re-proposes them

**6e. Register focusables during measure** (delete the `!isMeasuring`
guard). **Why it loses:** measure is speculative and repeated —
`ViewThatFits` measures variants it won't show; `contentExtents` measures
everything up to three times a frame. You'd register controls that don't
exist, repeatedly.

**6c. A persistent geometry cache as *the mechanism*.** **Why it loses:**
a cache can't answer for content never seen, so cold reveal is undefined and
"converges over frames" means jumping. Its core idea is right and is adopted
as §4e — the distinction is *cache, never source of truth*.

**6d. UIKit-style imperative chain (`scrollRectToVisible`).** **Why it
loses:** it presumes retained geometry. TUIkit rebuilds every frame, and at
event time nothing off-screen has geometry, so it must run a layout query —
becoming §4 with ceremony. Its inner-first cascade is adopted (§4b).

**6f. Just don't window (status quo).** **Why it loses:** it's what makes
plain `VStack` "work", and it's ruled out. It isn't even cheap:
`contentExtents` measures 100% of content at `max(viewportHeight*64, 4096)`
rows (`ScrollView.swift:589`), up to three times per frame, plus a fourth
call in `renderedContent`. **Every frame.** The status quo is an expensive
baseline, not a cheap correct one.

---

## 7. What this costs

Counted, not estimated. There are **34** `_*Core` types in `Sources/`.
Exactly **7** of them resolve child views at all
(`resolveChildViews`/`childViews`); another **7** reach a single content
view via `renderChild`/`measureChild`; the remaining **20 are leaves**.
That distribution is the good news — the blast radius is small and it is
concentrated in the stacks:

| Tier | Who (measured) | Work |
|---|---|---|
| **0** | 20 leaf `_*Core`s (`_SpinnerCore`, `_GaugeCore`, `_SliderCore`, `_ImageCore`, `_TextFieldCore`, …); **every** app-level view with a real `body` | **nothing** |
| **1** | **6** true multi-child containers: `_VStackCore`, `_HStackCore`, `_ZStackCore`, `_ListCore`, `_SectionCore`, `_ViewThatFitsCore` | real `LayoutPlacing` |
| **2** | **7** single-content containers: `_ScrollViewCore`, `_ContainerViewCore`, `_TabViewCore`, `_TableCore`, `_NavigationSplitViewCore`, `_PanelCore`, `_ToggleCore` | forward + offset (a few lines) |
| **3** | 2 `ViewModifier`s: `PaddingModifier`, `BackgroundModifier` | a `contentOrigin` |
| **4** | ~5 composites (`_MenuCore`, `_ListCore`, `_PickerMenuCore`, …) | ~10 lines: "my current item is at ordinal N" |

**An app author writing `VStack { … }` inside a `ScrollView` implements
nothing.** Tier 1 is six types, and `_VStackCore`/`_HStackCore` already
share one implementation.

Tier 4 is the only per-view-type knowledge anywhere. It's irreducible (only
`Menu` knows which row is selected) and it's a *consolidation*, not an
addition — `_MenuCore` already builds `lineItemIndex` mapping content lines
back to items for click routing (`Menu.swift:303-321`). One function serves
both, so click routing and reveal cannot disagree.

Identity-transparent wrappers (`AnyView`, `EquatableView`, `_MemoizedRow`)
are `Renderable` and must **forward** placements — `_MemoizedRow` wraps
every `Equatable` `ForEach` row (`ForEach.swift:120-124`), so missing it
dead-ends the commonest list shape in the framework.

**If a container omits `LayoutPlacing`, fail loudly.** A silent
full-render fallback quietly re-closes the path we're opening.

| Query | uniform | variable |
|---|---|---|
| route to child | O(1) | O(1) |
| reveal (anchor) | **O(1)** | **O(1)** |
| draw viewport | O(visible) | O(visible) |
| scroll one line | O(1) | O(1) |
| steady state | O(1) — one comparison | O(1) |
| exact absolute y of item *i* | O(1) | Ω(i) — **never asked** |

---

## 8. Staging

| Stage | Goal | Test |
|---|---|---|
| **0** ✅ | `focusID` survives the scroll clip | `ScrollRevealTests` (`df23e1f2`) |
| **1** | `LayoutPlacing` + enumerate visitor on the stacks; focus becomes a directional query (§4d). **The 500-button bug is fixed.** | `focus(id:)` reaches row 499 |
| **2** | Locate visitor + reveal generation, conditional (§4c). Menu-in-ScrollView reveals. | reveal through 2 nested ScrollViews |
| **3** | Remove `measureFixedByRendering` from the stacks; `sizeThatFits` = union of placements | measuring draws nothing |
| **4** | **Lazy `childViews`** (below) | 50M-row `ForEach` builds no array |
| **5** | `ScrollPosition` anchors; hoist locate above `renderedContent` | scroll one line touches one row |
| **6** | `renderedContent` draws only the window | 50M-row list renders O(visible) |

**Stage 6 must require no protocol change.** It is: a window predicate, an
extent source, an offset hoist, over an unchanged `LayoutPlacing`. If it
forces a change, this design was wrong.

### The foundation blocker (Stage 4)

`ChildViewProvider.childViews(context:) -> [ChildView]` returns an **eager
array**, and `ForEach.childViews` (`ForEach.swift:105-128`) is
`data.map { element in let view = content(element); … String(describing:) … }`.
For 50M rows that invokes 50M closures and allocates 50M id strings
**before any visitor callback fires** — and every container's first
statement is `resolveChildViews`.

**O(visible) is unreachable until this is lazy** (a `RandomAccessCollection`
of thunks, à la SwiftUI's `LayoutSubviews`). This blocks Stages 5–6 and no
earlier stage depends on it, which is why it sits at 4.

### Two more things that are false today

- `_VStackCore.windowSizeThatFits` (`VStack.swift:143`) — the sizing path
  *for the windowed stack* — calls `measureFixedByRendering` →
  `renderToBuffer(isMeasuring: true)` → but the windowing branch requires
  `!context.isMeasuring` (`:272-274`) → so it **falls through to the eager
  path and renders every child**. TUIkit's only windowing implementation is
  defeated by its own measure pass. 16 files call `measureFixedByRendering`.
  Until Stage 3, "measure is cheaper than render" is **false** — measure
  *is* render.
- **No general measure cache.** `lookupSize`/`storeSize` are called from
  exactly two places in the whole codebase (`EquatableView.swift:178`,
  `MemoizedRow.swift:180`). A plain `VStack { ForEach { … } }` of
  non-`Equatable` content is fully re-measured every frame. Any claim that
  locate "rides the existing measure cache" is false — §4e's cache has to be
  built, not borrowed.

---

## 9. Already landed

**`df23e1f2`** — `ScrollView.windowedBuffer` rebuilt each surviving hit
region *without* `focusID`. The parameter defaults to `nil`, so it was
silent. Since reveal matches on `focusID`, every `ScrollView` handed its
parent anonymous regions and **nested ScrollViews could never reveal
anything.** Fixed; `ScrollRevealTests` pins it at one and two levels.

---

## 10. What this does not solve

- **Exact absolute position of item *i*** in variable-height content:
  Ω(i), unavoidable, deliberately never requested. Such scrollbars are
  estimated (as `maxOffset` already does).
- **Reveal into a container without `LayoutPlacing`**: fails loudly. A
  silent full-render fallback would re-close the path.
- **`ViewThatFits`**: its layout isn't a pure function of its children (it
  picks a variant). It reports placements for the *chosen* variant only,
  and the choice must be stable within a frame.
- **Horizontal**: stated vertically throughout. The machinery is per-axis;
  implement one axis, generalise deliberately.
- **Whole-frame incrementality**: this makes the *ScrollView's subtree*
  incremental. Ancestors still re-render top-down each frame. Genuinely
  incremental whole-frame rendering is a separate, larger problem.

---

## 11. Open questions

1. **Does `ScrollPosition` replace `scrollOffset: Int` or sit beside it?**
   Replacing is the only way to get the O(1) properties, and touches every
   consumer (`ScrollableOffsetState`, scrollbar maths). Note
   `ItemListHandler` has *already* made this move — its `scrollOffset` is an
   index, not a cell count. Aligning the two names would remove a real trap.
2. **Do `List`/`Table` drop internal windowing?** The consistent end state.
   Much larger; sequence separately.
3. **Over-draw margin**: one row, or a viewport fraction? Sets how often
   Tab-to-adjacent needs any scroll.
4. **Should `ScrollViewReader` ship at Stage 2?** It's a parity gap and
   nearly free once `locate` exists.
