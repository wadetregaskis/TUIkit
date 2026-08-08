# Unmerged upstream branches

Reviewed 2026-08-07 · 21 commits across four branches, none on `upstream/main`

Not part of the numbered ledger: an unmerged branch is a proposal, and may still
change or be abandoned. Judged the same way regardless, because two of them were
pushed *after* `upstream/main`'s last commit — upstream is still working here.

## `issue/20-layout-primitives` — 15 commits, the only substantial one

A SwiftUI-parity sweep over the layout surface. Split verdict, and the split is
the interesting part.

### Already ours

- **`ViewThatFits`** (`68489ec0`) — shipped; the SF Symbols table uses it.
- **`Edge`, `Edge.Set`, `EdgeInsets`, padding shapes** (`730d58eb`) — shipped in
  `PaddingModifier.swift`, same shapes: `Edge: Int8, CaseIterable` with a nested
  `Set: OptionSet`.

### Genuine gaps · `defer`

- **`GeometryReader`** (`68489ec0`) — we have no equivalent. A real parity gap,
  and unlike most it is a *capability* gap: nothing in TUIkit lets a view read
  the space it was given and branch on it. Worth wanting.
- **`Layout` protocol family + `AnyLayout`** (`9caf40c7`) — we have
  `LayoutPlacing`, which is our internal two-pass contract, not SwiftUI's public
  `Layout`. Adopting the public protocol would let apps write custom containers.
- **`AlignmentID`** (`a51c1693`) — extensible alignment guides. Ours are fixed.

All three belong with the SwiftUI-parity batch (PRs #67/#69/#70), answered
against the real SDK rather than ported.

### Actively wrong for us · `reject`

- **`f10b3296` / `4c6d856b`: move stack, spacer and frame geometry to
  `CGFloat`.** A terminal is an integer grid of cells. Every size in this
  framework is a cell count, every position a row and column, and the one thing
  that must never happen is a fractional cell. Upstream is heading toward
  `CGFloat` for SwiftUI signature parity and then quantizing on the way out —
  `9ce847a9` is literally "reference the package-scoped quantization policy".
  That trades a guarantee the type system currently makes for a convention a
  reviewer has to remember. Our `Int` geometry is a documented terminal
  constraint, and this is the clearest case yet of parity being the wrong goal.

`4c6d856b` also carries "adopt SwiftUI's center default" for `frame` alignment,
which **we already did** (§3.6 of the compatibility audit).

## `issue/27-async-image-pipeline` — 4 commits · `defer`

An `URLImageCoordinator`: async URL image loads with request dedup and an
injectable transport, routed through `PlatformImageLoader`.

Not the same thing as our image work. Ours is about *decoding* (`NSImage` when
`canImport(AppKit)`, else `stb_image`) and rendering to cells; theirs is about
*fetching*. `Image(url:)` is a capability we do not have at all, so this is a
feature question rather than a port: does a terminal UI framework want to pull
images over the network? If yes, dedup and an injectable transport are the right
bones and this is a reasonable sketch of them.

## `issue/30-project-generator` — 1 commit · `n-a`

A `tuikit` project-generator CLI, made cross-platform and testable. We ship no
generator; whether to is a product decision, not a review one.

## `issue/50-ci-node-24` — 1 commit · `n-a`

Bumps pinned GitHub Actions to Node.js 24 releases. Ours pins only
`actions/checkout@v7`, which is already past that line. Nothing to do.

## Summary

| Branch | Verdict |
|---|---|
| `issue/20-layout-primitives` | 2 `have`, 3 `defer` (GeometryReader, `Layout`/`AnyLayout`, `AlignmentID`), 2 `reject` (CGFloat geometry) |
| `issue/27-async-image-pipeline` | `defer` — a feature decision, not a port |
| `issue/30-project-generator` | `n-a` |
| `issue/50-ci-node-24` | `n-a` |

The one thing worth acting on soon is **`GeometryReader`**: it is the only item
here that an app cannot work around, and it is small next to the rest.
