# PR #46 — `codex/issue-29-module-tests`

Commits 37–54 · 2026-07-19 · merged as `7d72c38f`
(commit 36 is an unrelated badge bump that landed direct on main)

Per-module test targets: each links only its own module plus that module's real
dependencies, so a test reaching across a boundary fails to compile rather than
failing review.

## Decision

**Already shipped here** — `a268ac63`, 2026-07-20 — so nearly every commit in
this branch records as `adapt` pointing at it. The scope differed: only 24 of
our 298 tests were extractable (9 Core / 8 Styling / 4 View / 3 Image), because
the rest genuinely need the umbrella — they build real controls, which all live
in `Sources/TUIkit`, or they use the `@testable`-umbrella render helpers.

Two things from that port worth keeping in view:

- Classify by **referenced types**, not by imports. The umbrella
  `@_exported`-re-exports every submodule, so an `import TUIkit`-only file may
  be using lower-module types throughout. Strip comments and strings first —
  doc-comment example types (`NavigationTitleKey`, `My*`) poison a name-based
  classifier.
- The split **unmasked a false pass**. `StatePropertyTests`' "mutation triggers
  render" asserted on the process-wide `AppState.shared.needsRender`, which
  parallel hydrated-state tests in the monolithic target kept true. Alone, it
  exposed that an unbound `@State` has a nil sink. See
  [[interaction-test-discipline]].

Enforcement is `Tools/validate-test-boundaries.sh`, wired into CI ahead of the
build.

## The one thing not taken

`f75e9ae4` — "Reject native linker dependencies" — is upstream refusing any C
target or platform framework anywhere in the package. We deliberately keep
`CSTBImage` and `NSImage` ([[nsimage-decoder-selection]]), so their rule as
written would ban an architecture we chose.

But a **scoped** version of it maps onto a rule we already hold and do not
enforce. `CLAUDE.md` says POSIX-only APIs — `termios`, `ioctl`, signals,
`DispatchSource` on stdin — stay inside the `TUIkit` umbrella so the four lower
modules keep building on Windows. That is true today (verified: none of those
symbols appear in `TUIkitCore`, `TUIkitStyling`, `TUIkitView`), and the only
thing standing behind it is the Windows CI lanes — which are
`continue-on-error: true` and never block. A violation could land with CI fully
green.

**Resolved 2026-08-07 — `inspired`, and not in the shape first proposed.**

The owner's objection retired the module-scoped lint: we do not care *which*
module holds Windows-incompatible code, because the end state is every module
building there. A rule blessing POSIX in one module and forbidding it in four
encodes a staging line that is meant to move, and tests a proxy for portability
rather than portability.

What went in instead (`ac22b9c6`) is a **ratchet on the real platform**. The
Windows lane already split its steps into "expected to pass" and "expected to
fail"; only the job-level `continue-on-error` and the gate's advisory treatment
made that unenforceable. Both are gone, so the job now promises exactly
*"everything that builds on Windows today still builds"* — a set that can only
grow.

Checking what that set actually was found the real defect: **`TUIkitImage` had
never built on Windows**, on any lane, while `CONTRIBUTING.md` asserted it
passed. `ShapeSampling.swift` imported `Glibc`-or-`Darwin` and called `cos`/`sin`
unconditionally, so Windows had no `cos` at all — fixed in `e20e2d94` by adding
the `Musl` and `ucrt` arms. `TUIkitView` also fails on Swift 6.2 specifically,
cause not yet diagnosed; it is fenced there and binding everywhere else.

Which is the argument for the change, made by the change: the claim had been
false for as long as nothing checked it.
