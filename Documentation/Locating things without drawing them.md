# Locating things without drawing them

*A design for reveal-on-focus, viewport-only rendering, and incremental
layout — which turn out to be one problem, not three.*

**Status:** proposed. Nothing here is implemented except the prerequisite
fix in §11. Revised twice after adversarial review: §7 records every
alternative considered and why it lost; §4 places the design against what
Compose, SwiftUI, Flutter, the web, and UIKit actually shipped; §5g–§5j
and §9 came out of the second review (windowing semantics, state
retention — including a measured live bug — the uniform fast path, and
SwiftUI portability).

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
why §7g is the option we adopt rather than reject.

### What we give up, honestly

The scrollbar thumb needs "how far through are we?" — `y / totalHeight`,
the number we refuse to compute. **Estimate it, and say so:** use item
index, refined as rows are measured. The thumb may drift and settle. This
is a terminal scrollbar; every virtualised list makes this trade, and
`maxOffset` above already does. Uniform-height content (TUIkit's default
`List`/`Table` line mode) is exact anyway (§5i).

---

## 4. What the field does

None of this is a novel problem. Every mature UI framework has been asked
"where is row 50,000,000?" and each shipped an answer. They sort on one
axis — **what kind of number is the scroll position?** — and most of their
other disagreements follow from that choice.

| | Scroll position | Rows exist… | Off-screen focus / reveal | Known-height fast path |
|---|---|---|---|---|
| **Jetpack Compose** `LazyColumn` | **anchor**: `firstVisibleItemIndex` + `firstVisibleItemScrollOffset` | while visible (+ prefetch); disposed after | **yes** — beyond-bounds focus search materialises items toward the target | per-index sizes cached; `scrollToItem(index:)` exact |
| **SwiftUI** `List` / `LazyVStack` | opaque; identity-addressed (`scrollPosition(id:)`) | identity eager, views lazy; lazy stacks never recycle | `ScrollViewReader.scrollTo(id:anchor:)` reaches unrealised rows | detected internally; no public oracle |
| **UIKit** `UITableView` | absolute pixels, but the *API* is index paths | recycled cells; data always addressable by index | `scrollToRow(at: IndexPath)` — index space | fixed `rowHeight` → everything exact |
| **Flutter** slivers | **absolute pixels** + estimates + `scrollOffsetCorrection` | while visible + `cacheExtent`; destroyed after (keep-alive opt-in) | **no** — keyboard traversal reaches built children only | `itemExtent` / `prototypeItem` → exact offsets |
| **react-window / TanStack Virtual** | absolute pixels + estimates + corrections | while visible (+ overscan); not in the DOM otherwise | **no** — off-DOM rows invisible to focus and AT; `aria-rowcount` lies to compensate | `FixedSizeList` is a *separate component* |
| **React Native** `FlatList` | absolute pixels + estimates | windowed | `scrollToIndex` **fails** without `getItemLayout` or a rendered row (`onScrollToIndexFailed`) | `getItemLayout` oracle |
| **CSS** `content-visibility: auto` | n/a (browser scrolling) | **always in the DOM**; layout/paint skipped | **yes** — focus, find-in-page, `scrollIntoView` force layout on demand | `contain-intrinsic-size` estimate |
| **TUIkit** (this design) | **anchor**: identity + offset | windowed (§5g) | **yes** — directional query (§5d) + locate (§5b) | extent oracle (§5i) |

### The two camps

**Absolute-plus-corrections** (Flutter, the web virtualisers, UIKit
self-sizing): keep a pixel offset, estimate unmeasured extents, and when a
row turns out to be a different height than estimated, *patch the lie*.
The patching is real, shipped machinery: Flutter's
`SliverGeometry.scrollOffsetCorrection` re-runs viewport layout with an
adjusted offset; TanStack Virtual shifts `scrollTop` when a measured item
disagrees with its estimate; UIKit's self-sizing cells nudge
`contentOffset`. The artifacts are equally real and user-visible — the
documented scroll-up jumps in Flutter issue trackers, the "jumpy reverse
scrolling" FAQ entries of every web virtualiser. This is §7l/§7q, shipped
at scale, with the exact failure mode §7l predicts.

**Anchored** (Compose, UITableView's *API surface*, `ItemListHandler`,
this design): the scroll position names an item. Compose's `LazyListState`
persists `firstVisibleItemIndex + firstVisibleItemScrollOffset` — that
pair is, symbol for symbol, `ScrollAnchor { item, offsetWithin }`. There
is no correction machinery in the anchored camp *because there is no lie
to patch*: a mis-estimated row above the anchor moves nothing the user is
looking at.

Flutter deserves one more note: its `Viewport` has a `center` sliver —
content laid out in both directions *from an anchor* — which is how
bidirectional infinite lists (chat history) are built there. When the
absolute camp needs the hard case to work, it reaches for an anchor.

### Off-screen focus: mostly a graveyard, with two survivors

Most of the field shipped the 500-button bug and papered over it:
react-window's own docs recommend ARIA attributes that *describe* rows
that don't exist; Flutter's keyboard traversal silently skips unbuilt
children; the standard web advice is a roving tabindex (§7k — one tab
stop for the whole list).

Two systems actually solved it, and they validate the two halves of this
design:

- **Compose** added beyond-bounds layout: when focus search walks off the
  visible edge of a `LazyColumn`, the list materialises items *in the
  search direction* until the query is satisfied. That is §5d — the focus
  ring as a directional query that the owning container answers on demand
  — shipped in production by the framework whose scroll model we already
  match.
- **CSS `content-visibility: auto`** keeps off-screen content in the DOM
  with an *estimated* size (`contain-intrinsic-size`) and skips its layout
  and paint until it becomes "relevant to the user" — where the spec's
  definition of relevant includes *being focused* and *being found by
  find-in-page*, both of which force real layout on demand. That is
  "exists, estimated, realised on demand" — locate-without-drawing as a
  browser primitive.

### The identity tax

One more lesson, a warning rather than a validation. SwiftUI's lazy
containers read the **identity of every element eagerly** — Apple's own
performance guidance says so explicitly — while building row *views*
lazily. That's why `scrollTo(id:)` can find an unrealised row, and why
SwiftUI can prune per-row state precisely when data is deleted: it always
holds the full id set. The price is O(N) identity extraction per update,
which for 50M rows is exactly the cost §10's Stage 4 refuses to pay.
Compose ducks the tax by addressing items by *index* (with optional keys);
so does `ItemListHandler`. This design ducks it the same way — and §5h and
§12 record what that honestly costs us (imprecise pruning of deleted rows'
state, and Ω(N) worst-case id→ordinal lookup on anchor recovery). Nobody
gets all three of {lazy identity, precise pruning, O(1) lookup}; pick two
is the actual menu.

---

## 5. The design

### 5a. The identity chain is the route

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

### 5b. One traversal, many visitors — and it must be seekable

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

    /// Non-nil when every placement has exactly this extent along the
    /// scroll axis under this proposal. The uniform fast path (§5i):
    /// placement arithmetic and the scrollbar become exact and O(1).
    func uniformExtent(proposal: ProposedSize, context: RenderContext) -> Int?
}
```

**Why seekable now, not later:** a `forEach`-with-`.stop` callback can only
*stop* early — reaching row 49,999,999 still costs 49,999,999 callbacks,
and filling a viewport upward from an anchor has no direction at all. By
this design's own falsification criterion (§10), a protocol that Stage 5
must change is a protocol that was wrong.

Everything else is a **visitor**:

| Visitor | Predicate | Cost |
|---|---|---|
| **Locate** | "does this lead to the target?" — route, don't scan | O(depth) |
| **Window** | "does this rect meet the viewport?" — walk out from the anchor | O(visible) |
| **Enumerate** | "is this focusable?" — see §5d | O(visible + margin) |
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
recursion — the one genuinely good property of the rejected §7a, preserved.

**Pull, not push.** The current windowing hands a visible slice *down* via
an environment value (`scrollContentWindow`) and hopes the child can act on
it. That direction cannot generalise: to push a correct rect down, the
parent would already need the child's heights — the very information the
child exists to provide. With variable heights the dependency only resolves
in one direction: the scroll container *pulls* placements outward from the
anchor, and each level answers for its own children. §6b walks an example.

### 5c. Fill rules (not an afterthought)

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
- **Edge affinity.** An anchor binds to the viewport's top edge *or its
  bottom edge*. Top is the default. Bottom is follow mode — the anchor is
  "the last item, offset from the bottom" — and it is how a log view
  stays glued to the tail while lines pour in (§6c). The user scrolling
  up flips affinity to top on whatever row is then under the top edge;
  scrolling to the end flips it back. SwiftUI spells the same idea
  `defaultScrollAnchor(.bottom)`.
- **Reveal alignment.** Reveal and `scrollTo` take an alignment —
  top / center / bottom — mapping to "place the target's rect at that
  fraction of the viewport". It costs nothing (reveal already sets
  `anchor` + `offsetWithin`; alignment just picks the offset) and it is
  SwiftUI's `scrollTo(_:anchor:)` signature, so parity is free.

### 5d. What the focus ring contains

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

It is also not exotic: Compose's beyond-bounds focus search (§4) is this
exact shape in production — the lazy container materialises items in the
search direction until the focus query resolves.

### 5e. State vs cache — the split that makes the invariant testable

```swift
// STATE: authoritative. Persisted in StateStorage beside ScrollViewHandler.
// Losing it loses the user's scroll position.
struct ScrollPosition {
    var anchor: ScrollAnchor
    var anchorLadder: [ViewIdentity]  // K neighbours, for recovery (§5f)
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

(That's three rules; the third is free.)

### 5f. When the anchor disappears

`ForEach` keys rows by `String(describing: element[keyPath: idKeyPath])`
(`ForEach.swift:113`), so identities survive reorder — but the anchored row
can be **deleted**, filtered out, or collapsed.

- The anchor is a **ladder**: primary identity plus K neighbours captured
  from last frame. On a miss, anchor to the nearest survivor, preserving
  `offsetWithin`.
- If the whole ladder is gone (list replaced), fall back to the last known
  *index*, clamped — approximate, and correct at the ends.
- Empty content: anchor is nil; viewport renders empty; scroll is a no-op.

### 5g. Two kinds of windowing — existence and paint

"Draw only what's on screen" conflates two operations with very different
observability, and the design must keep them distinct:

- **Paint windowing** skips *drawing*. The child still exists: its body
  is available for measurement, its `@State` is live, its lifecycle
  status is unchanged. Dropping the paint of an off-viewport row is
  observationally invisible (nobody can see the pixels that weren't
  drawn) — it is pure optimisation, legal for **every** container.
- **Existence windowing** skips *building*. Off-window rows are never
  constructed: no view values, no body evaluation, no `@State`
  instantiation, no `onAppear`. This is observable — lifecycle hooks
  become viewport signals — and therefore it is a *semantic*, not an
  optimisation.

The rule that keeps TUIkit portable (§9) is:

> **Existence windowing is legal exactly where SwiftUI is lazy** —
> `LazyVStack`, `LazyHStack`, `List`, `Table` — **and nowhere else.** A
> plain `VStack`'s children exist every frame, however far off screen,
> because that is what SwiftUI code observes: `onAppear` in an eager
> stack fires at mount even for content below the fold (the classic
> SwiftUI gotcha), and pagination-by-`onAppear` works only in lazy
> containers *because* they window existence.

Two corollaries:

- A plain `VStack` in a `ScrollView` stays O(N) in *construction* — as it
  is in SwiftUI — but gets paint windowing for free, so it stops being
  O(N) in *drawing*. Apps with a few hundred eager rows get faster; apps
  with 50M rows must say `Lazy`, exactly as they must in SwiftUI.
- `.onAppear` / `.onDisappear` / `.task` cancellation in lazy containers
  are *specified* to track the window (+ margin). Today's implementation
  already behaves this way (`LifecycleModifier.swift` — a token not
  recorded this frame "disappears", cancelling its task); the design
  keeps it, because it is also SwiftUI's lazy-container behaviour.

### 5h. State must outlive the window — today it doesn't

The GC contract for `@State` is currently: `markActive(identity)` runs on
body hydration in the *render* path (`Renderable.swift:207`), and
`StateStorage.endRenderPass()` **prunes every identity not marked this
frame** (`StateStorage.swift:205-224`). "Left the window" and "left the
tree" are the same event as far as state is concerned.

Measured, with a scratch probe driving the real windowing path
(`scrollContentWindow`, 20 rows, viewport 4, `@State` stamped by
`onAppear`, value recorded at body-evaluation time each frame):

| Frame | Window | Row 1's `@State` at body time |
|---|---|---|
| 1 | rows 0–3 | 0 (fresh; `onAppear` stamps 99) |
| 2 | rows 0–3 | **99** ✓ |
| 3 | rows 10–13 | **99** — still there… |
| 4 | rows 10–13 | **0 — pruned.** |
| 5 | rows 0–3 | 0 (fresh again) |

Two findings, one worse than the other:

- **A windowed-out row loses its `@State` one frame after leaving the
  window.** A `Toggle` in a lazy row silently resets when scrolled away
  and back. SwiftUI does not do this: lazy stacks keep instantiated views
  (their documented memory trade), and `List` preserves per-identity row
  state through cell recycling. This is a live portability bug **today**,
  independent of everything else in this design.
- The same probe shows every off-window row's **body still evaluates
  every frame** (the measure pass hydrates it — rows 4–19 recorded a
  value at body time in all five frames). So the current `LazyVStack`
  pays the eager cost *and* delivers the lazy semantics — the worst
  quadrant. (Hydration during measure doesn't `markActive`; only the
  render path does. Retention isn't riding on the wasted work — nothing
  is.)

The contract this design needs instead:

> **State is pruned when a row leaves the *data*, or when the owning
> container leaves the tree — never merely because a row left the
> window.**

Mechanism: a windowing container declares its subtree **retained** —
`endRenderPass` skips identities under a retained root, and the subtree
is dropped whole when the container itself dies. What this deliberately
does *not* do is prune per-row on data deletion: knowing a row was
deleted requires the full id set, which is the identity tax §4 refuses
(SwiftUI can prune precisely *because* it reads every id eagerly). So
state for deleted rows lingers until the container dies — bounded by the
set of rows the user actually visited and interacted with, which for a
50M-row list is a vanishingly small fraction. Compose makes the opposite
choice (disposed items lose plain `remember` state; survival is opt-in
via `rememberSaveable`); we follow SwiftUI because SwiftUI portability is
the goal (§9).

Ordering note for §10: this contract must land **no later than Stage 3**.
It fixes a live bug now, and Stage 3/4 (measure without render; lazy
construction) will stop off-window bodies from even evaluating — at which
point any code that accidentally depended on re-hydration behaves worse,
not better.

### 5i. The uniform fast path

Variable heights are the hard case; they are not the common case. A
line-mode `List`, a `Table` in row granularity, any `ForEach` of
`.frame(height: k)` rows — most big TUI collections have an extent that
is *provably identical for every row*. The design must exploit that, not
merely tolerate it:

```swift
enum ExtentSource {
    case uniform(Int)          // every row: exactly this, no exceptions
    case oracle((Int) -> Int)  // exact per ordinal, cheap, no view built
    case measured              // §5e cache + estimatedItemExtent
}
```

With `.uniform(h)` (surfaced through `LayoutPlacing.uniformExtent`):

- `placement(at: i)` is `i × (h + spacing)` — **O(1), exact**.
- `ordinal(atY:)` is a division — scrollbar clicks and drags land on the
  exact row, page-up/down is exact, and the thumb **never drifts**,
  because `totalExtent = count × (h + spacing)` is exact too.
- Anchors remain the representation. Uniform is a fast path through the
  same model, not a second model — the estimate just happens to have zero
  error, so every "estimated, refined as measured" sentence in §3
  degrades to "exact".

`.oracle` is `ItemListHandler.rowHeight` (`:140`), already shipped. The
field ships this split explicitly: react-window makes it two component
types (`FixedSizeList` / `VariableSizeList`), React Native makes it a
prop (`getItemLayout`), Flutter makes it `itemExtent` (and its docs call
out the same three wins: exact scrolling, exact scrollbar, no estimate
churn). Sources, in priority order: declared by the container (`List`
line mode **is** `uniform(1)`), proven from the row view type (a
`ForEach` whose row is `.frame(height: k)`-wrapped), else `measured`.

### 5j. The cross-axis rule

Windowing breaks one more thing silently if unaddressed: a stack's
cross-axis size today is the **max over all children** (a `VStack` is as
wide as its widest row). Under windowing, "all children" becomes "visited
children" — so a `.leading`-aligned windowed list whose widest row lives
at index 40,000 would *change width* when that row scrolls in, shifting
every border and alignment on screen. The alternatives are Ω(N)
(measure everything to find the max — the cost we exist to remove) or
jitter. Choose neither:

> **A windowed container's cross-axis extent is the proposal** — it fills
> the width it is offered, and its rows lay out within that. Eager
> containers keep max-of-children.

This is what the field does, invisibly: Flutter's list children get tight
cross-axis constraints from the viewport; SwiftUI's `List` fills its
proposed width regardless of row content. Terminal lists are
full-width-fill in practice already (`List`, `Table`, and every demo page
fill their panel), so the rule mostly *ratifies* current behaviour — but
it must be stated, because a windowed `LazyVStack` of short `Text` rows
genuinely changes reported width under this rule (it stops shrink-wrapping
to its widest visited row). `ScrollView`'s horizontal axis needs the same
statement when horizontal windowing arrives (§12).

---

## 6. Worked examples

### 6a. One line up, then Tab, at row 50,000,000

`ScrollView { LazyVStack { ForEach(0..<50_000_000) { Row($0) } } }`,
anchored at row 50,000,000. User presses Up.

1. **Input** → anchor moves to the previous row; its height is cached (it
   was just on screen). **O(1).**
2. **Render** → `placement(at:)` from the anchor's ordinal, walking down
   until the viewport fills; then the backward fill if needed. **~6 rows.**
3. **Enumerate** → the same walk registers those rows' focusables plus a
   margin. Rows beyond are *knowable* (§5d routes to them on demand) but
   never enumerated.
4. **Scrollbar** → `estimatedItemExtent × 50M`, refined.

Then Tab, where focus must leave the window:

1. `next` routes to the owning container, which walks outward from the
   focused ordinal — it does not consult a list of 50M.
2. `ScrollView` sees a new reveal generation, calls `locate`; the identity
   chain routes in O(depth).
3. Target already visible? **Do nothing** (§5c). Otherwise set the anchor.
   **O(1).**

### 6b. Nesting: the ScrollView pulls, the stacks answer

```swift
ScrollView {
    VStack {
        Text(longWrappedHeader)          // ordinal 0
        LazyVStack {                     // ordinal 1
            ForEach(0..<1_000_000) { Row($0) }
        }
        Text(footer)                     // ordinal 2
    }
}
```

Anchored at row 517,203, two lines in. The frame renders as:

1. The `ScrollView` holds the anchor. Its content is the `VStack`; the
   anchor's identity chain names the lazy stack at step d+1 — **child
   ordinal 1**, read in O(1), nothing probed.
2. The `VStack` places *outward from ordinal 1*: the lazy stack places
   outward from its own ordinal 517,203; if the viewport isn't filled
   upward, the `VStack` continues to ordinal 0 and measures the header
   (it's about to be visible — measuring it is O(its size), and correct).
3. The footer — ordinal 2, the millionth row's neighbour — is **never
   touched**. Whether it is on screen was answered by the *fill running
   out of viewport*, not by computing the lazy stack's total height.

Note what made this work: the pull direction (§5b). The old push model —
parent hands "rows 517,203…517,209 are visible" down an environment key —
cannot even be *stated* here: to compute which of the `VStack`'s lines
are visible, the parent would need the header's wrapped height and the
lazy stack's total height first. With pull, each level answers only for
its own children, outward from an anchor it was handed, and unknown
extents are never demanded.

### 6c. Follow the log

A build-log pane: `ScrollView { LazyVStack { ForEach(lines) { … } } }`
with bottom edge affinity (§5c), lines appended at 100/s.

- Glued to the tail: anchor = (last item, bottom edge, offset 0). Each
  frame fills *upward* from the tail — O(visible). Appending costs
  nothing until the next frame, and the next frame still costs
  O(visible). No total height, no correction, ever.
- The user scrolls up three lines to read an error: affinity flips to the
  top edge on the row now under it. Appends continue below — **the view
  does not move.** This is the "scroll lock" every terminal user expects
  from `less +F` / `tmux` copy-mode, and in the anchor model it is not a
  feature — it's the absence of one. Nothing had to be built; the anchor
  simply doesn't reference the tail any more.
- In the absolute camp this exact scenario is the jitter generator:
  every append grows `totalHeight`, the ratio `y/totalHeight` changes,
  and the thumb (or worse, the content) crawls.

### 6d. Prepending history

A chat view loads 50 older messages when the user nears the top.

- **Absolute camp:** content above the viewport grows by Σ(new heights);
  the same `y` now shows different content; the view visibly jumps unless
  someone patches `y` by exactly that Σ. Browsers grew an entire feature
  — scroll anchoring, `overflow-anchor` — to bolt this correction onto
  absolute scroll positions after the fact.
- **Anchor camp:** the anchor names a message. Fifty rows appeared at
  ordinals *before* it; its identity didn't change; the view doesn't
  move. There is no code path for this case — which is the point. The
  prepend cost is O(visible), same as any frame.

### 6e. Uniform rows: everything exact

A process monitor: 1M rows, line granularity, `uniform(1)` (§5i).

- Click at 40% of the scrollbar track: target ordinal = ⌊0.4 × 1M⌋ —
  exact, lands on row 400,000, **O(1)**.
- PageDown = anchor ordinal + viewport height — exact.
- The thumb position is `anchorOrdinal / 1M` — exact, never drifts,
  because no height is ever estimated.
- Total extent = 1M × 1 — exact, computed without touching a row.

Every estimate-flavoured sentence in §3 quietly disappears; no code
changes shape, because uniform is the same model with error zero.

### 6f. The anchor dies

Same process monitor, anchored on PID 4821's row. The process exits and
the data source drops it.

- Next frame, `ordinal(of:)` misses. The ladder (§5f) holds the
  neighbours captured last frame; the nearest survivor above becomes the
  anchor, `offsetWithin` preserved. Visual result: the row below slides
  up by one row height — which is exactly what happened to the data.
- Harder: the user flips a filter and 1M rows become 12. The whole ladder
  is gone. Fall back to the remembered *index*, clamped into 0..<12 —
  lands at the bottom of the short list. Approximate, correct at the
  ends, and precisely what `UITableView` does after `reloadData` — the
  accepted floor for "the world was replaced under me".

### 6g. Lifecycle as a contract, both directions

Pagination, the SwiftUI idiom, unchanged:

```swift
LazyVStack {
    ForEach(items) { ItemRow($0) }
    ProgressView().onAppear { loadNextPage() }   // fires on scroll-near
}
```

Under existence windowing (§5g) this is *specified*: the spinner's
`onAppear` fires when it enters the window + margin, because in a lazy
container existence tracks the window. The same code means the same thing
in SwiftUI.

And the inverse, the gotcha preserved deliberately:

```swift
VStack {                                          // ← not Lazy
    ForEach(0..<100) { i in
        AnalyticsRow(i).onAppear { logImpression(i) }  // ALL fire at mount
    }
}
```

All 100 impressions log immediately, viewport notwithstanding — because a
plain `VStack`'s children exist from mount, in SwiftUI and therefore in
TUIkit. If we "fixed" this by firing lazily, we would be silently
changing what ported code does. Paint windowing still applies; the rows
simply exist without being drawn.

---

## 7. Options considered, and why they lose

Eighteen, grouped. Each rejection is one paragraph; that is deliberate.

### The one we adopt

**7g. Generalise `List`'s model (`ItemListHandler`).** `_ListCore`
registers **one** `Focusable` for a whole list (`_ListCore.swift:391`);
the focused row is an index into the *data*; scroll is index + clip-lines;
heights come from an oracle. It is anchor-based, O(1) at any size, and it
ships. **Why it wins:** it's proven here, on this codebase, at scale. This
design is that model lifted out of `List` and made general — which is the
whole task, since "special-case for a subset of views" is what we were
asked to stop doing. (It is also, per §4, the model Compose ships for
exactly this problem.)

### Locate by drawing — fails the disqualifier

**7a. Anchors riding the `FrameBuffer`** *(the author's first proposal)*.
Views emit a reveal-anchor rect beside `hitTestRegions`; it's translated on
composite and clip; each `ScrollView` finds it in the full content buffer.
Genuinely elegant for nesting — bottom-up rendering means the inner view
fixes its offset before the outer looks. **Why it loses:** the anchor only
exists if the target was drawn. It doesn't merely fail to help with
windowing — it **depends on windowing never happening**, cementing the
thing we're removing. Its nesting property is preserved in §5b.

**7b. Hybrid: anchors when drawn, locate when not.** **Why it loses:** the
fast path optimises a case that doesn't exist — anchors cover what was
drawn; what was drawn is visible; **what is visible needs no revealing.**
Two mechanisms, two bug sets, and a seam where behaviour depends on whether
something happened to be on screen.

### Don't locate at all

**7n. Explicit-only reveal (`ScrollViewReader.scrollTo`).** SwiftUI's
actual answer; also a real parity gap (`ScrollViewReader`, `ScrollViewProxy`
have zero occurrences in `Sources/`). **Why it loses:** it doesn't fix the
bug — 494 buttons are still unfocusable, and `scrollTo(id:)` needs the very
"where is id?" query this design provides. We should ship it *on top* of
§5, not instead.

**7k. Roving cursor: the lazy container is one tab stop.** What the field
actually ships — react-window doesn't make off-screen rows tabbable.
**Why it loses:** it's `List`'s model applied by fiat to `LazyVStack`, and
it silently changes what `Button` means inside a lazy stack. Worth offering
as a *style*, not as the framework's answer to "reveal must be universal".

**7r. Make the composites leaves.** Nothing inside `Menu`/`List` is
independently focusable. **Why it loses:** this is precisely why `List`
works and `LazyVStack` doesn't — it is the special-casing we were asked to
eliminate, generalised in the wrong direction.

**7p. Materialise a bounded band** (viewport ± N screens, clamp scrolling).
**Why it loses:** the focus ring becomes the band — the 500-button bug
moved and rescaled, not fixed. And it breaks `scrollTo` past the band.

### Locate differently

**7m. Prefix-sum / order-statistics tree** (Fenwick; VS Code's
`PrefixSumComputer`). y(i) and y→row in O(log N). **Why it loses *here*:**
it's an excellent answer to a question we've decided not to ask. It buys
exact absolute offsets at the cost of maintaining a tree over 50M rows
whose heights we deliberately never measure. Keep it in the back pocket for
uniform-height content wanting an exact scrollbar — though note §5i gets
the uniform case exact with arithmetic alone.

**7l. Estimated absolute offsets (`estimatedRowHeight`).** Keep
`scrollOffset: Int`; estimate unmeasured rows. Cheapest migration, and —
per §4 — the *most shipped* answer in the field (Flutter, the web
virtualisers, UIKit self-sizing). **Why it loses:** estimates in an
*absolute* space are cumulative — every correction below the viewport
shifts everything above it, so the content jitters as you scroll. The
field's own correction machinery (`scrollOffsetCorrection`, scroll
anchoring) is the size of the wound, not a refutation: they built an
anchor-shaped patch on top of an absolute foundation. Anchors localise
the error to one row by construction.

**7q. Reveal by estimate, converge over frames.** **Why it loses:**
visible jumping; unbounded with variable heights, since each correction
changes the estimate that produced it; and it can oscillate.

**7o. Enumerate structurally, place lazily.** Walk the structure without
measuring, register every focusable, compute geometry only at reveal. The
obvious naive fix. **Why it loses:** the walk is Ω(N) per frame — it is the
flat 50M-entry registry §5d refuses.

### Change the architecture

**7i. Retained view tree (React fibers).** **Why it loses:** it doesn't
answer the question. A fiber exists only once created, so an uncreated row
is still invisible to focus. It's a large rewrite that leaves the bug.
(React's own ecosystem confirms: fibers didn't make react-window's
off-screen rows focusable — nothing did.)

**7j. Separate retained layout tree (Flutter `RenderObject`).** The
canonical "layout is retained though rendering isn't" answer, and honestly
the closest thing to a rival. **Why it loses *for TUIkit*:** it's a
ground-up re-architecture of a shipping immediate-mode renderer to buy what
§5e's cache buys incrementally. And §4 shows it doesn't even buy the
feature: Flutter has the retained tree *and* the 500-button bug (unbuilt
sliver children aren't focus-traversable), because retention doesn't
answer "where is what I never built". If TUIkit were greenfield this would
deserve a real hearing — as infrastructure, not as the fix.

**7h. Adopt SwiftUI's `Layout` shape.** `sizeThatFits(proposal:subviews:cache:)`
+ `placeSubviews`, where `LayoutSubviews` is a **`RandomAccessCollection`**
of proxies. **Why it partly wins:** it validates §5b's seekable shape and
§5e's cache — we should borrow its vocabulary. **Why not wholesale:**
`LayoutSubviews` is still a materialised collection of every subview, which
is precisely the foundation problem in §10.

### Non-starters, recorded so nobody re-proposes them

**7e. Register focusables during measure** (delete the `!isMeasuring`
guard). **Why it loses:** measure is speculative and repeated —
`ViewThatFits` measures variants it won't show; `contentExtents` measures
everything up to three times a frame. You'd register controls that don't
exist, repeatedly.

**7c. A persistent geometry cache as *the mechanism*.** **Why it loses:**
a cache can't answer for content never seen, so cold reveal is undefined and
"converges over frames" means jumping. Its core idea is right and is adopted
as §5e — the distinction is *cache, never source of truth*.

**7d. UIKit-style imperative chain (`scrollRectToVisible`).** **Why it
loses:** it presumes retained geometry. TUIkit rebuilds every frame, and at
event time nothing off-screen has geometry, so it must run a layout query —
becoming §5 with ceremony. Its inner-first cascade is adopted (§5b).

**7f. Just don't window (status quo).** **Why it loses:** it's what makes
plain `VStack` "work", and it's ruled out. It isn't even cheap:
`contentExtents` measures 100% of content at `max(viewportHeight*64, 4096)`
rows (`ScrollView.swift:589`), up to three times per frame, plus a fourth
call in `renderedContent`. **Every frame.** The status quo is an expensive
baseline, not a cheap correct one.

---

## 8. What this costs

Counted, not estimated. There are **34** `_*Core` types in `Sources/`.
Exactly **7** of them resolve child views at all
(`resolveChildViews`/`childViews`); another **7** reach a single content
view via `renderChild`/`measureChild`; the remaining **20 are leaves**.
That distribution is the good news — the blast radius is small and it is
concentrated in the stacks:

| Tier | Who (measured) | Work |
|---|---|---|
| **0** | 20 leaf `_*Core`s (`_SpinnerCore`, `_GaugeCore`, `_SliderCore`, `_ImageCore`, `_TextFieldCore`, …); **every** app-level view with a real `body` | **nothing** |
| **1** | **6** true multi-child containers: `_VStackCore`, `_HStackCore`, `_ZStackCore`, `_ListCore`, `_SectionCore`, `_ViewThatFitsCore` | real `LayoutPlacing` (incl. `uniformExtent`, §5i) |
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

| Query | uniform (§5i) | variable |
|---|---|---|
| route to child | O(1) | O(1) |
| reveal (anchor) | **O(1)** | **O(1)** |
| draw viewport | O(visible) | O(visible) |
| scroll one line | O(1) | O(1) |
| steady state | O(1) — one comparison | O(1) |
| scrollbar thumb | O(1) **exact** | O(1) estimated |
| exact absolute y of item *i* | O(1) | Ω(i) — **never asked** |

---

## 9. What downstream code notices

The goal is that SwiftUI code drops into TUIkit unmodified. Scored
against that, this design's ledger:

**Invisible (the bulk of it).** `LayoutPlacing`, visitors, anchors,
ladders, the extent oracle — all internal to container implementations.
App code sees no new required protocol, no changed initialiser, no new
parameter. An app-level custom container is a `body` composing framework
containers, and those carry it.

**Convergences — differences from SwiftUI that this design *removes*:**

- Off-window lazy rows keep their `@State` (§5h). Today they lose it;
  SwiftUI keeps it. Ported code with stateful rows stops misbehaving.
- `focus(id:)` / Tab reaches everything that exists (§1). SwiftUI's
  platform focus reaches off-screen `List` rows; TUIkit couldn't.
- `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` — a parity
  gap today, nearly free at Stage 2 (§13), with SwiftUI's exact
  signature including the anchor.
- `defaultScrollAnchor(.bottom)` (§5c edge affinity) — SwiftUI's own API
  for follow mode.

**Divergences that remain, deliberately, eyes open:**

- **Lifecycle timing in lazy containers** matches SwiftUI in *kind*
  (appear/disappear track the window) but not necessarily in *distance* —
  SwiftUI's prefetch margins are undocumented and ours (the over-draw
  margin, §13) won't coincide. Code that treats `onAppear` as "roughly
  near the viewport" ports fine; code that depends on exact fire counts
  was already fragile in SwiftUI.
- **Deleted rows' state lingers** until the container dies (§5h), where
  SwiftUI prunes on data diff. Observable only by memory footprint, not
  by behaviour — SwiftUI code cannot observe its own pruning either.
- **The scrollbar thumb on variable-height content is an estimate**
  (§3). SwiftUI's is too (its platforms estimate), but ours may drift
  more visibly on pathological content. Uniform content is exact (§5i).
- **Cross-axis fill in windowed containers** (§5j): a windowed
  `LazyVStack` fills its proposed width instead of shrink-wrapping its
  widest visited row. SwiftUI's `LazyVStack` *does* shrink-wrap — but
  against *all* instantiated rows, a set that grows monotonically, which
  is its own subtle drift. Content that cares should state a `frame`;
  content that doesn't won't notice in a full-width terminal panel.

**Name discipline.** SwiftUI has a public `ScrollPosition` type (its
`scrollPosition(_:)` family). Our internal struct (§5e) must not go
public under that name with a different shape — rename it internally
(`ScrollAnchorState`) or match the SwiftUI API if it ever surfaces.
TUI-specific surface stays where it always goes: optional modifiers
(`.focusID`, an extent-oracle hint if we ever expose one), never required
parameters — so SwiftUI source stays valid TUIkit source.

---

## 10. Staging

| Stage | Goal | Test |
|---|---|---|
| **0** ✅ | `focusID` survives the scroll clip | `ScrollRevealTests` (`df23e1f2`) |
| **1** | `LayoutPlacing` + enumerate visitor on the stacks; focus becomes a directional query (§5d). **The 500-button bug is fixed.** | `focus(id:)` reaches row 499 |
| **2** | Locate visitor + reveal generation, conditional (§5c). Menu-in-ScrollView reveals. | reveal through 2 nested ScrollViews |
| **3** | Remove `measureFixedByRendering` from the stacks; `sizeThatFits` = union of placements | measuring draws nothing |
| **4** | **Lazy `childViews`** (below) | 50M-row `ForEach` builds no array |
| **5** | `ScrollPosition` anchors; hoist locate above `renderedContent` | scroll one line touches one row |
| **6** | `renderedContent` draws only the window | 50M-row list renders O(visible) |

**Stage 6 must require no protocol change.** It is: a window predicate, an
extent source, an offset hoist, over an unchanged `LayoutPlacing`. If it
forces a change, this design was wrong.

**Stage-independent: the state-retention contract (§5h).** It fixes a
measured live bug (a lazy row's `@State` is pruned one frame after
leaving the window) and it must land **no later than Stage 3**, because
Stage 3/4 remove the off-window body evaluation that currently at least
*re-runs* the reset rows. Its test: a `@State`-bearing row keeps its
value across leaving and re-entering the window; a row whose *container*
leaves the tree still loses it.

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

Being precise about *which* costs Stage 4 removes, because "lazy" hides
three different meanings (§4's identity tax):

| Cost | When paid | Can it be avoided? |
|---|---|---|
| `count` | every frame | free — `RandomAccessCollection.count` is O(1) |
| build the row view (call the closure) | per ordinal *touched* | **yes — this is Stage 4** |
| read element + derive its id | per ordinal touched | yes for positional identity (`ForEach(0..<n)`); per-touch for keyed |
| id → ordinal (find a row by identity) | anchor recovery, `scrollTo(id:)` | **Ω(N) worst case, unavoidable** with opaque data (§12) — mitigated by searching outward from the last known ordinal |

SwiftUI pays the id column eagerly (O(N) per update, per its own
guidance) to make the last row O(1)-ish. We refuse the eager pass, so we
pay Ω(N) on the rare id-lookup miss instead. Both are defensible;
`ItemListHandler` (index-addressed) shows the miss essentially never
happens for the workloads that need 50M rows.

### Two more things that are false today

- `_VStackCore.windowSizeThatFits` (`VStack.swift:143`) — the sizing path
  *for the windowed stack* — calls `measureFixedByRendering` →
  `renderToBuffer(isMeasuring: true)` → but the windowing branch requires
  `!context.isMeasuring` (`:272-274`) → so it **falls through to the eager
  path and renders every child**. TUIkit's only windowing implementation is
  defeated by its own measure pass. 16 files call `measureFixedByRendering`.
  Until Stage 3, "measure is cheaper than render" is **false** — measure
  *is* render. (§5h's probe confirmed this from the outside: every
  off-window row's body evaluates every frame, today.)
- **No general measure cache.** `lookupSize`/`storeSize` are called from
  exactly two places in the whole codebase (`EquatableView.swift:178`,
  `MemoizedRow.swift:180`). A plain `VStack { ForEach { … } }` of
  non-`Equatable` content is fully re-measured every frame. Any claim that
  locate "rides the existing measure cache" is false — §5e's cache has to be
  built, not borrowed.

---

## 11. Already landed

**`df23e1f2`** — `ScrollView.windowedBuffer` rebuilt each surviving hit
region *without* `focusID`. The parameter defaults to `nil`, so it was
silent. Since reveal matches on `focusID`, every `ScrollView` handed its
parent anonymous regions and **nested ScrollViews could never reveal
anything.** Fixed; `ScrollRevealTests` pins it at one and two levels.

---

## 12. What this does not solve

- **Exact absolute position of item *i*** in variable-height content:
  Ω(i), unavoidable, deliberately never requested. Such scrollbars are
  estimated (as `maxOffset` already does). Uniform content is exact (§5i).
- **Finding a row by identity in opaque data**: `ordinal(of:)` for an id
  not near the last known position is Ω(N) worst case — there is no index
  over ids we refuse to build (§4, the identity tax). Steady state never
  asks; anchor-ladder misses and cold `scrollTo(id:)` might. An optional
  app-supplied `index(ofID:)` oracle is the escape hatch if it ever
  matters in practice.
- **Global aggregates over all rows**: "widest row", "total exact
  height", `Table` `.fit` column widths — Ω(N) by information content,
  same as the absolute-y trap (§3). The design's answers are: cross-axis
  fill (§5j) so stacks never ask; estimates for extents (§3); and `.fit`
  stays what it is today — an eager scan, documented as such, for tables
  small enough to want it. A sampled `.fit` (visited rows only, sticky
  maxima) is possible but jitters column edges on scroll; not proposed.
- **Precise pruning of deleted rows' state** under deferred identity:
  lingers until the container dies (§5h). Bounded by visited-and-stateful
  rows; revisit only if real apps accumulate meaningful state across
  millions of visited rows in one screen's lifetime.
- **Reveal into a container without `LayoutPlacing`**: fails loudly. A
  silent full-render fallback would re-close the path.
- **`ViewThatFits`**: its layout isn't a pure function of its children (it
  picks a variant). It reports placements for the *chosen* variant only,
  and the choice must be stable within a frame.
- **Horizontal**: stated vertically throughout. The machinery is per-axis;
  implement one axis, generalise deliberately. (§5j's cross-axis rule is
  the vertical case's statement about width; the transpose holds.)
- **Whole-frame incrementality**: this makes the *ScrollView's subtree*
  incremental. Ancestors still re-render top-down each frame. Genuinely
  incremental whole-frame rendering is a separate, larger problem.

---

## 13. Open questions

1. **Does `ScrollPosition` replace `scrollOffset: Int` or sit beside it?**
   Replacing is the only way to get the O(1) properties, and touches every
   consumer (`ScrollableOffsetState`, scrollbar maths). Note
   `ItemListHandler` has *already* made this move — its `scrollOffset` is an
   index, not a cell count. Aligning the two names would remove a real trap.
   (And whatever the internal name, not `ScrollPosition` if it ever goes
   public — SwiftUI owns that name with a different shape, §9.)
2. **Do `List`/`Table` drop internal windowing?** The consistent end state.
   Much larger; sequence separately.
3. **Over-draw margin**: one row, or a viewport fraction? Sets how often
   Tab-to-adjacent needs any scroll, and how early lazy `onAppear` fires
   relative to visibility (§9).
4. **Should `ScrollViewReader` ship at Stage 2?** It's a parity gap and
   nearly free once `locate` exists — including the `anchor:` parameter,
   which §5c's reveal alignment provides.
5. **The retained-subtree mechanism for state (§5h)**: a flag on the
   container's own identity that `endRenderPass` consults, or a separate
   retained-roots set alongside `activeIdentities`? And do `List`/`Table`
   adopt the same contract when (2) lands, replacing whatever
   `ItemListHandler` does implicitly today?
6. **How far to *prove* uniformity (§5i)?** Container-declared and
   `.frame(height:)`-derived are safe; inferring "every `Text` row of a
   non-wrapping list is height 1" is attractive and probably right, but
   wrong the day someone embeds a newline. Decide the inference boundary
   before Stage 5, where the extent source starts mattering.
7. **Does plain-`VStack` paint windowing ship, and when?** It's
   observationally invisible (§5g) and strictly saves work, but it rides
   the same placement machinery — cheapest right after Stage 3. Decide by
   measurement on the example app's long pages.
