# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. Verify the package still works as a dependency

**From** `178cf604` (PR #44) · **ledger verdict** `queued`

A 59-line script that tags a throwaway local release, resolves TUIkit through
it as an *exact external dependency*, and builds a minimal executable that
imports it. It catches the class of failure a normal `swift build` cannot see:
something public by accident, a resource bundle that only resolves in-tree, a
platform gate that only holds for the package itself.

We have nothing equivalent, and we do ship tagged releases (v0.6.0 is the
current tag). The cost is a CI job of a minute or two per run.

**What is needed from you:** whether to add it, and whether it should run on
every push or only on tags. Adding CI surface is not something I will do on my
own initiative.

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
