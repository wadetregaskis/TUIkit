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

## 2. Make the render-hydration environment a `@TaskLocal`

**From** `a0e4c389` (PR #52) · **ledger verdict** `queued`

`StateRegistration.activeEnvironment` is an ambient mutable global, saved and
restored around body evaluation:

```swift
nonisolated(unsafe) public static var activeEnvironment: EnvironmentValues?
```

Upstream replaced theirs with a `@TaskLocal`. Production here is single-threaded
on the render loop, so **no production hazard is demonstrated** — this is not a
bug report.

The reason to consider it is our **test suite**. `EnvironmentPropertyTests` and
`ObservableEnvironmentTests` assign this global directly — they must, because
they exercise the fallback path that reads it — neither suite is `.serialized`,
and swift-testing runs suites in parallel. A render test entering
`withHydration` concurrently will save the other suite's value and restore it
back over the top. That is the class already fixed twice here: the render-cache
shared-defaults flakes, and the StepperOverflow colour-depth flake.

`.serialized` does **not** fix it — that trait orders tests *within* a suite,
not against other suites. A `@TaskLocal` does, because each test body is its own
task and no other task can write into its scope.

**Cost.** The property is `public`, and a `@TaskLocal` is settable only inside
`withValue` — so this is a public API change plus about twenty test call sites
and one restructure of `evaluateAppBody`. Behaviour changes in exactly one way,
and in the right direction: a detached `Task` reading `@Environment` would see
the framework defaults instead of whatever the render loop happened to have
published.

**Evidence it is latent, not active:** fifteen consecutive full-suite runs, all
green. The window is a few instructions wide.

Recommended, but it is a public-surface change, so it is yours to say.

---

## 3. Back `FrameBuffer` with a terminal-cell grid?

**From** `3e0db22c` / `cd52b8a5` and six refits (PR #53) · **ledger verdict**
`queued` · the largest architectural divergence in the review so far

**What upstream did.** `TerminalCell` is
`{ content: .empty | .grapheme(String, width: Int) | .continuation,
style: TerminalStyle, isTransparent: Bool }`; `TerminalSurface` is
`[[TerminalCell]]`. `FrameBuffer` stores one of those and keeps its `lines`
array as an adapter over a cached, sanitised encoding. Clipping, compositing,
transparency and vertical stacking then work in cell space, without reparsing
ANSI out of strings. Six follow-up commits repair what that broke — ZStack
alignment, text layout, diff clipping, background painting, notification
measuring, blank cells under foreground styling.

**Why it is tempting.** [[cells-not-characters-class]] is a standing bug class
here, fixed instance by instance over many commits. A cell grid makes half of it
— clipping a wide grapheme in half — *structurally* impossible, because the
second cell is an explicit `.continuation` rather than a byte you might slice.

**My recommendation: decline**, on three grounds, weakest first.

1. **It fights a profiling-driven design.** `linesAreUniformWidth` and
   `lineWidths` exist on our `FrameBuffer` because per-line `strippedLength` was
   the dominant cost in deeply-nested bordered layouts — the same lines
   re-measured at every enclosing level, O(depth²). A cell grid replaces that
   cost model wholesale, and the honest answer to "what does it cost?" is that
   nobody knows until `Tools/Profiling/` is re-run against it.

2. **Upstream's version does not escape strings either.** It keeps the `lines`
   adapter and parses strings *into* cells at the boundary — paying the parse
   **and** the per-cell allocation. It is a different point on the trade-off,
   not a strictly better one.

3. **It does not fix the hard part.** Nearly every bug we have had in this class
   was *width arithmetic*: is 〰️ two cells, is a lone Fitzpatrick modifier two,
   does Terminal.app under-advance VS-16 (see
   [[terminal-compatibility-doc]]). `TerminalCell.grapheme(_, width:)` still has
   to compute that number, from the same `terminalWidth`. The grid fixes
   splitting, which we already handle by padding the shortfall.

**The narrower alternative**, if the safety is wanted without the rewrite:
adopt cell-space **clip and composite primitives** for the handful of operations
that actually straddle graphemes — `ansiAwarePrefix`, the overlay compositor,
the diff writer's row clipping — and leave `FrameBuffer` as an array of strings.
That captures the structural guarantee where the straddling happens, at a
fraction of the blast radius, and can be profiled in isolation.

**If you would rather take the whole thing**, say so and the six refits come
with it; they have no meaning apart from the refactor, which is why they carry
the same `queued` verdict rather than a decision of their own.

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
