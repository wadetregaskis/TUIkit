# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. The `.equatable()` cache key has no environment component

**From** `c48e35d78d` (PR #64) · **ledger verdict** `queued` ·
**reproduced 2026-08-07**, `RenderCacheContractTests`

`RenderCache.lookup` keys on identity, view value and available size. Nothing
else. So a **scoped** style change *above* an `.equatable()` boundary — the view
value itself unchanged — has nothing to miss on, and the buffer rendered under
the old style is served. That is **wrong pixels**, not extra work. The measure
memo (`lookupSize`) has the same blind spot.

Global changes are covered (`RenderLoop.invalidateCacheIfEnvironmentChanged`
drops everything), and so is the common scoped case, by accident: a
`.foregroundStyle` driven by `@State` invalidates through the declaring view's
identity, and `clearAffected(by:)` clears every descendant. What is *not* covered
is a style whose source is neither global nor an ancestor — a preference written
by a sibling, or `@AppStorage`, whose setter calls `setNeedsRender()` and does
not touch the cache at all.

**The decision is which shape to fix it with**, and they differ materially:

| | What it costs | What it misses |
|---|---|---|
| **A. Fingerprint a fixed list** (upstream's `EnvironmentFingerprint`: `foregroundStyle` + `focusIndicatorColor`) | ~nothing | every style value nobody remembered to add — the same bug, narrower |
| **B. Hash everything hashable, deny-list the services** | a dictionary walk + N casts per lookup, per `.equatable()`, per frame | nothing by default; a *new service* not on the deny-list costs memoization, which is a perf regression rather than a correctness one |
| **C. Invalidate at the modifier** — `EnvironmentModifier` compares the value it applied here last frame and clears the subtree on change | one comparison per environment modifier per frame | needs `V: Equatable`; non-Equatable values would have to decline caching |

B inverts upstream's fragility in the right direction — a newly added *style*
value is covered automatically — but it is the one with a real per-frame cost,
and there is a live perf concern already. C is the most correct and the most
invasive.

Not guessed at, because all three change the framework's shape differently and
the cheap one is the one that leaves the bug in.

---

## Upstream branches not on `main`

Not part of the numbered backlog: an unmerged branch is a proposal, and may
still change or be abandoned.

**Still unreviewed, and upstream is still active on them** — the last two were
pushed *after* `upstream/main`'s final commit (2026-07-22).

| Branch | Ahead of `upstream/main` | Last commit |
|---|---|---|
| `issue/20-layout-primitives` | 15 commits | 2026-07-22 |
| `issue/27-async-image-pipeline` | 4 | 2026-07-24 |
| `issue/30-project-generator` | 1 | 2026-07-24 |
| `issue/50-ci-node-24` | 1 | 2026-07-24 |

21 commits in total. `issue/20-layout-primitives` is the only substantial one
and the only one plausibly relevant — the other three are a project generator, a
CI bump, and an async image pipeline we have already solved differently
(`NSImage` when `canImport(AppKit)`, else `stb_image`).

Worth a pass, at roughly a tenth of the main backlog's size. Not started because
the backlog was scoped to `main`.
