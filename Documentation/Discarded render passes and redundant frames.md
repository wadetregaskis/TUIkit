# Discarded render passes and redundant frames

A design record of an investigation run on 2026-08-07, prompted by reviewing
upstream (phranck/TUIkit) PRs #59–#63. It concerns two related questions:

1. Why does a frame ever walk the view tree more than once, and what does that
   cost in correctness?
2. When a view writes `@State` during a walk, must the frame be rendered again?

Both were answered. Neither answer is the one the investigation started with,
and the corrections are recorded here alongside the conclusions, because two of
the wrong turns were more instructive than the right ones.

## 1. Every discarded pass we have exists to measure the App Header

`RenderLoop.renderContent` calls `renderScene` three times, and only ever draws
one buffer:

- a **first-frame measurement walk**, thrown away, whose only lasting output is
  `appHeader.height`;
- the **main walk**;
- a **correction re-render**, when the header's real height turns out to differ
  from the estimate the main walk was laid out against — discarding the main
  walk's buffer.

There is no other source. Nothing else in the loop renders and discards.

### Why the header needs a whole walk

Because `.appHeader { … }` is a **modifier applied inside the content tree**,
writing its rendered height into `AppHeaderState` as a side channel during
traversal. The loop cannot ask "how tall is the chrome?" without rendering the
entire app to find out.

So the discarded pass is not a property of the renderer. It is a consequence of
**chrome being declared inside the tree it displaces** — a layout circularity.

### The rule that follows

> **Never let a piece of chrome's height depend on rendering the content it
> displaces.**

This is not "remove the App Header". A wrapping menu bar, a navigation toolbar,
or a status area reintroduces the circularity exactly as the header does, if
declared the same way. Chrome should be **structural** — a sibling of the
content in the scene, sized independently:

```swift
WindowGroup { content } toolbar: { … }   // measurable on its own
content.toolbar { … }                     // NOT this: height needs the walk
```

Then chrome is measured, content laid out in the remainder, and the frame drawn
in one walk. No discarded pass exists to leak effects from.

## 2. What a discarded pass costs

Every guard written `!context.isMeasuring` — `onAppear`, `.task`, focus and
mouse registration, `onChange` — treats a walk as real unless told otherwise. A
discarded walk that is not marked therefore fires effects for a tree that is
never drawn.

Counting fires cannot detect it: `recordAppear` is idempotent, so `onAppear`
still fires exactly once. What is wrong is *which* walk it fires in — and it
matters because the walks see different heights, so a tree branching on
available space can hold a view in one walk and not the next. That view appears,
mounts a task, and is told it disappeared, having never been drawn.

**Frame 1 is fixed** (`cdea2eec`): that walk is knowable as throwaway *before*
it runs, so it is simply marked as a measurement. `AppHeaderModifier` is
deliberately not guarded on the measure phase, which is what lets the walk still
do its one job — anything that later guards itself that way must stay out of the
header's height.

**The correction re-render is not, and cannot be fixed the same way.** The loop
renders at the estimated height, learns the real one afterwards, and only then
re-renders. Marking its first walk would suppress effects on every frame where
the height turns out unchanged — nearly all of them. Pinned as a
`withKnownIssue` in `RenderPassScopeTests` (`a338e81f`), which flips to a plain
failure the day it closes.

## 3. Upstream's answer, and why it is not ours

PRs #60–#62 stage effects per walk (`RenderPassCollectors`), commit them once
from the final walk after terminal output (`PendingFrameEffects`), and add a
diagnostic for state written during traversal.

It is the only design that closes the correction-frame hole, because you cannot
know which walk is final until they have all run. It is also invasive —
RenderLoop, LifecycleModifier, OnChangeModifier, FocusRegistration,
EquatableView, Renderable, ObservationRegistry and four state holders — and its
whole correctness case is discarded passes.

**Decision: not adopted.** Make chrome structural (§1) and the requirement
disappears. Building machinery to make the smell safe is worse than removing the
smell, and the chrome redesign is happening regardless. Revisit if the header is
kept, if new chrome is built the modifier way, or if anything else ever needs to
render-then-discard.

**Taken separately, because it needs none of that:** the body-mutation
diagnostic (`727dbf71`).

## 4. `onAppear` timing

Apple documents `.onAppear(perform:)` as running *before* the view appears, and
specifically: **"the action closure completes before the first rendered frame
appears."** `.onDisappear` is documented as *after* — deliberately asymmetric.

SwiftUI can honour that because graph evaluation and the render-server commit
are separate: state written in `onAppear` folds into the same transaction, and
only then is anything presented.

**We have no such split — our walk is the commit.** Producing the buffer *is*
presenting it. Three options follow:

| | Matches the docs? | Can frame 1 tear? |
|---|---|---|
| Fire before the content renders (**what we do**) | yes | yes, from views walked earlier |
| Replay after `writeFrame` (upstream) | **no** | no; one stale frame instead |
| Converge before presenting (SwiftUI) | yes | no — but needs re-walking to fixpoint, i.e. a discarded pass, unbounded |

`OnAppearModifier` fires `recordAppear` **before** rendering its content, so a
view whose `onAppear` sets its own state is read by its own subtree in the same
frame. We match SwiftUI's contract; upstream's replay-after-write does not.

Deferral is therefore **declined**, not merely postponed: it would trade a
documented SwiftUI guarantee for avoiding a tear measured (§5) as a startup
one-off.

## 5. Can the redundant re-render be skipped?

When a mid-walk write happens, the frame-so-far is only wrong if something has
**already read that state this walk**. If nothing has, everything drawn is still
accurate and the re-render the write requests is waste.

The proposal: stamp each `StateBox` with the walk that last *read* it; on write,
compare. One integer, no allocation. It is a **conservative over-approximation**
(a view that reads state without using it in output counts as a reader), which
errs toward re-rendering unnecessarily — never toward skipping when it should
not. That makes it sound, and it is **not** taint-tracking: one bit per box per
walk, no propagation through computations.

### Two wrong measurements, recorded because they were instructive

**First attempt: "0% avoidable — the idea doesn't work."** Wrong, twice over. It
counted *every* mid-walk write, a population dominated by framework
read-modify-write bookkeeping (`_ImageCore` reads `lastSourceBox` to decide
whether to write it) rather than by effect closures. And it let a closure's own
reads stamp, so `count += 1` classified its own write as "something already
rendered from this". The conclusion did not follow from the data.

**Second attempt, scoped correctly** — `recordAppear` brackets the action
invocation, reads inside the bracket do not stamp, only writes originating there
are counted. Verified live (a probe with `.onAppear { count += 1 }` produces a
non-nil summary, so the counter is not inert). Two navigation paths through the
Example: **zero `onAppear` writes**.

That is a **weak zero**. `recordAppear` fires only on first appearance and the
paths visited roughly a dozen of ~30 pages. It shows those pages contain no
state-writing `onAppear`, not that the Example does not, and certainly not that
apps do not. A full `tui_walk.py` sweep over every page would be needed for a
number worth acting on.

### What is solid

All mid-walk writes observed were **frame 1**; none recurred. Post-`75a732fa`,
nothing in the framework writes state mid-walk during steady-state rendering.
The redundant frame is a startup one-off, not an ongoing tax.

### The cache interaction, which decides it

A memoised subtree does not run its body, so it stamps no reads — but its stored
buffer *was* computed from that state, and `@State` is not part of the view
value the cache keys on. Skip the invalidation and a stale buffer is served.
That is a correctness hole, not a missed optimisation.

Closing it means recording, per cache entry, which boxes the stored subtree
read. Implications:

- **Memory: not the problem.** A `Set<ObjectIdentifier>` per entry; empty sets
  cost nothing, a populated one is ~50–100 bytes. At realistic entry counts —
  one per `.equatable()` view plus one per memoised row, hundreds for a large
  list — tens of KB, noise beside the `FrameBuffer` line arrays already stored.
- **Render speed: that is the problem, in the worst place.** Collecting the sets
  means every `StateBox` read appends to a per-subtree collector, and cached
  subtrees nest, so it is a *stack* of collectors: a push/pop per cache boundary
  and an insert into every enclosing frame per read. O(reads × nesting depth),
  paid on every **cache miss** — precisely when the expensive work is already
  happening.
- It also reintroduces ambient per-walk bookkeeping on a hotter path than the
  one `7b2b7af4` just moved to a `@TaskLocal`.

**The arithmetic does not close.** A permanent per-miss render tax, paid by every
app, to remove a startup one-off.

## 6. Conclusions

1. Make chrome structural. It removes the discarded passes, which removes the
   effect-staging requirement, which removes most of this document.
2. Do not adopt the render-phase project. Revisit only on the triggers in §3.
3. Keep `onAppear` firing before its content renders. It matches SwiftUI's
   documented guarantee; deferral does not.
4. Do not build read-set skipping. Sound, but the cache fix it requires costs
   more than it saves.
5. The cheap generalisation is available and free: **a view that read-modify-
   writes its own state should compare before assigning.** That is the
   `_ImageCore` fix (`75a732fa`) as a rule, and it needs no machinery.
6. `TUIKIT_DIAGNOSE_BODY_MUTATION=1` names any view that breaks (5). That is how
   the next one gets found in a run rather than an investigation.

## See also

- `Documentation/Upstream-review/notes/PR-59.md`, `PR-60.md` — the per-commit
  verdicts.
- `Tools/Profiling/idle-image.sh` and `Tools/Profiling/IdleProbe` — the probe
  that measured an idle `Image` at 2% CPU and zero bytes.
- `Sources/TUIkitView/Rendering/BodyMutationDiagnostic.swift`.
