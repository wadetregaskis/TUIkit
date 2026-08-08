# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

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
