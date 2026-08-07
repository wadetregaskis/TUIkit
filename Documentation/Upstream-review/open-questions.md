# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. Guard the four lower modules against POSIX-only APIs

**From** `f75e9ae4` (PR #46) · **ledger verdict** `queued`

`CLAUDE.md` holds a non-negotiable rule: POSIX-only APIs — `termios`, `ioctl`,
signals, `DispatchSource` on stdin — stay inside the `TUIkit` umbrella, so
`TUIkitCore`, `TUIkitStyling`, `TUIkitView` and `TUIkitImage` keep building on
Windows.

The rule holds today; I checked, and none of those symbols appear in the lower
modules. What is missing is anything that would *notice* a violation. The
Windows lanes build exactly those four modules — and they are
`continue-on-error: true`, deliberately advisory until the port lands, so they
never block. A commit moving `termios` into `TUIkitCore` would land with CI
fully green, and be found whenever someone next read the Windows lane.

Upstream's version of this (`f75e9ae4`) bans C targets and platform frameworks
package-wide, which would outlaw `CSTBImage` and `NSImage` — an architecture we
chose. The scoped version bans only the specific POSIX terminal APIs, only in
the four modules the rule already names.

Roughly twenty lines beside `Tools/validate-test-boundaries.sh`, one step in the
`lint` job, milliseconds. Recommended, but it adds CI surface, so it is yours to
say.

---

## 2. `StateRegistration.activeEnvironment` — `@TaskLocal`, or retire it?

**From** `a0e4c389` (PR #52) · **ledger verdict** `queued`

```swift
nonisolated(unsafe) public static var activeEnvironment: EnvironmentValues?
```

An ambient mutable global holding "the environment of the body currently being
evaluated", saved and restored for nesting by
`StateRegistration.withHydration(context:)`. Upstream replaced theirs with a
`@TaskLocal`.

### What it is, and how it relates to SwiftUI

**It has no SwiftUI counterpart, and it is not our primary mechanism.**

In SwiftUI, `@Environment` is a `DynamicProperty`: before evaluating a view's
`body`, the attribute graph calls `update()` on each of the view's dynamic
properties, and the wrapper stores the resolved value in its *own* storage. That
is why a SwiftUI `Button` action closure can read `@Environment(\.dismiss)` and
get the right value — the value was written into the wrapper at update time and
captured with the view. There is no ambient "the environment currently
rendering" for anything to read.

We have exactly that mechanism, and it is the one that runs:
`Environment` holds a reference `EnvironmentBox`, and
`resolveEnvironmentProperties(of:in:)` walks the view's `Mirror` and populates
every box immediately before `body`
([Renderable.swift:189](../../Sources/TUIkitView/Rendering/Renderable.swift:189)).
Its doc comment records why it exists: reading an ambient environment lazily at
access time — the old behaviour — "returned defaults in deferred closures".

So `wrappedValue` resolves in three steps
([EnvironmentProperty.swift:111](../../Sources/TUIkitView/Environment/EnvironmentProperty.swift:111)):

```swift
let env = box.environment            // the SwiftUI-equivalent path
       ?? StateRegistration.activeEnvironment   // ← the ambient fallback
       ?? EnvironmentValues()        // framework defaults
```

`activeEnvironment` is the middle line: a TUIkit-only fallback for the places
that publish an environment but never run the box resolution.

### Who actually still depends on it

Written in two places — `withHydration`, and `RenderLoop.evaluateAppBody`
([RenderLoop.swift:808](../../Sources/TUIkit/App/RenderLoop.swift:808)). Read in
three:

1. **The measure pass.** `measureCompositeBody`
   ([ChildInfo.swift:425](../../Sources/TUIkitView/Rendering/ChildInfo.swift:425))
   calls `withHydration` but **not** `resolveEnvironmentProperties` — so during
   measure, `@Environment` resolves through the global. On the *render* path
   both are set and the box wins, which makes the global dead weight there.
2. **`App.body`.** `App` is not a `View` and never goes through
   `renderToBuffer`, so nothing populates its boxes; `evaluateAppBody` publishes
   the environment around `app.body` and clears it after.
3. **`@FocusState`**, twice
   ([FocusState.swift:114](../../Sources/TUIkit/Focus/FocusState.swift:114) and
   [:177](../../Sources/TUIkit/Focus/FocusState.swift:177)) —
   `focusManager ?? StateRegistration.activeEnvironment?.focusManager`, so a
   read at body-top works before a `.focused` modifier has wired the store, and
   `$field` captures a manager while projecting.

### The two ways forward

**(a) Make it a `@TaskLocal`**, as upstream did. Fixes the test-isolation hazard
below. Costs a public-API change (a `@TaskLocal` is settable only inside
`withValue`), ~20 test call sites, and a restructure of `evaluateAppBody`.
Behaviour changes in exactly one way, in the right direction: a detached `Task`
reading `@Environment` would see framework defaults rather than whatever the
render loop last published.

**(b) Retire it.** Close the three gaps instead — resolve boxes on the measure
path too, resolve `App`'s properties before `app.body`, and let `FocusState`
conform to `EnvironmentResolvable` (today `Environment` is its only conformer,
and `FocusState` uses a different seam, `RenderIdentityBindable`). Then the
global has no readers and can be deleted, removing a concept with no SwiftUI
analogue and ending with *less* API rather than differently-shaped API.

### What (b) costs beyond the work

Worth stating plainly, because the shape of it is worse than "same change, more
of it".

1. **The global is load-bearing for measure-time correctness, not a nicety.**
   `measureCompositeBody` hydrates but never populates boxes, so during measure
   *every* composite view's `@Environment` resolves through the global. Retire
   it without replacing it there and those reads silently become framework
   defaults — `\.terminalWidth` would answer `80`
   ([ViewEnvironmentKeys.swift:36](../../Sources/TUIkit/Environment/ViewEnvironmentKeys.swift:36))
   instead of the real width. `EmojiPage` and `ProgressViewPage` both branch on
   it, the former through `ViewThatFits`, so they would choose a different
   subtree at measure than at render: measured size ≠ rendered size, the
   divergence class the whole `Layoutable` effort exists to prevent.

   So resolving boxes on the measure path is **mandatory**, which forces (2).

2. **Reflection on the hottest path in layout.** `measureCompositeBody` is
   deliberately `@inline(never)`, with a comment about keeping the measure frame
   small "under deep nesting, where each level contributes a frame". A
   `Mirror(reflecting:)` walk there lands in the most-repeated operation in the
   pipeline. `EnvironmentResolutionCache` only memoises types *without*
   `@Environment`; the 21 files that have them would reflect on every measure of
   every instance. This needs a profile *before*, not after.

3. **Boxes would start holding measure-pass environments, and they persist.**
   `RenderCache.Entry.viewSnapshot` retains view values across frames, and their
   boxes with them. Today a box only ever holds a *render*-pass environment — a
   clean invariant. Writing measure environments in means a view measured but
   never rendered (an off-band lazy row, a losing `ViewThatFits` candidate, a
   hidden `TabView` tab) keeps one where `isMeasuring` is true.

4. **It converts a soft failure into a silent one.** Today any body-evaluating
   path that forgets to resolve still gets the right `@Environment` by the slow
   route. Afterwards it gets the default palette, `isEnabled`, locale `en`,
   width 80 — plausible-looking and hard to spot. Two such paths exist already;
   the change is only safe if every one has been found, and any *future* one
   becomes a silent wrong value instead of a slower right one. Mitigable with a
   debug assertion on an unpopulated box, but that is extra design.

5. **`@FocusState` has a precedence subtlety.** Today it is
   `focusManager ?? global` — the modifier-wired manager **wins**. Resolving from
   the environment at body-top would take the manager visible to the *owning
   view*, which is not always the one at the control: `isolatedForBackground()`
   injects a different `FocusManager` for a modal's background. Any conformance
   has to preserve that precedence.

6. **The test seam moves.** The call sites are in `TUIkitTests`, which
   `@testable import TUIkit` — that exposes TUIkit's internals, not
   TUIkitView's, which is *why* the property is `public`.
   `resolveEnvironmentProperties` would need `package` access, or those tests
   move to `TUIkitViewTests`.

### Why it is worth doing at all

The **test suite**. `EnvironmentPropertyTests` and `ObservableEnvironmentTests`
assign the global directly — they must, because they exercise the fallback path
that reads it — neither is `.serialized`, and swift-testing runs suites in
parallel. A render test entering `withHydration` concurrently saves the other
suite's value and restores it back over the top. That is the class already fixed
twice here: the render-cache shared-defaults flakes, and the StepperOverflow
colour-depth flake.

`.serialized` does **not** fix it — that trait orders tests *within* a suite,
not against other suites. A `@TaskLocal` does, because each test body is its own
task. Retiring the global does too, by leaving nothing to race on.

**Production is not affected:** rendering is single-threaded on the render loop.
**Evidence it is latent, not active:** fifteen consecutive full-suite runs, all
green; the window is a few instructions wide.

**Revised recommendation: (a).** An earlier draft of this note preferred (b) as
"the proper fix". Looking harder at what it touches — the measure path, focus
manager precedence, and App startup, three load-bearing areas — that is the
*riskier* option, taken on to close a hazard that has never fired outside a
thought experiment. (a) is mechanical and behaviour-preserving, and it does not
block (b) later: if the render pipeline is ever reworked with profiling in hand,
retiring the global belongs in that pass, not ahead of it.

Either way it touches public surface, so it is yours to say.

---

## Upstream branches not on `main`

Not part of the numbered backlog: an unmerged branch is a proposal, and may
still change or be abandoned. Listed so they are not forgotten.

| Branch | Status |
|---|---|
| `issue/20-layout-primitives` | not yet examined |
| `issue/27-async-image-pipeline` | not yet examined |
| `issue/30-project-generator` | not yet examined |
| `issue/50-ci-node-24` | not yet examined |
