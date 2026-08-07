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
global has no readers and can be deleted, which moots (a) entirely and removes a
concept that has no SwiftUI analogue. Bigger, but it ends with *less* API rather
than differently-shaped API. The measure-path piece needs care — `Mirror`
reflection per measure is a real cost, though `EnvironmentResolutionCache`
already memoises types with no `@Environment` properties.

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

My recommendation is **(b) if you want it done properly, (a) if you want it done
now** — and (a) does not block (b) later. Either way it touches public surface,
so it is yours to say.

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
