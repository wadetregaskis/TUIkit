# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. Does an on-screen `Image` stop the run loop idling?

**From** `39270268` (PR #63) · **ledger verdict** `queued`

`_ImageCore.manageLoadLifecycle` ends with `lastSourceBox.value = source`,
outside any change check, on every render pass. `StateBox.value`'s `didSet`
invalidates unconditionally — it cannot compare, since `Value` is not
constrained to `Equatable`. So every frame containing an `Image` appears to ask
for another one, and the demand-driven loop would never go idle.

Upstream hit exactly this: once their body-mutation diagnostic landed, *every*
image frame raised a violation, and they fixed it by deriving the placeholder
from `lastSource != source` instead of writing during traversal.

**Not yet established here.** A unit test failed to discriminate, because the
invalidation sink defers its mutation to the main-actor frame boundary and a
synchronous `renderToBuffer` never gets there. The probe was deleted rather than
left asserting something it does not test.

**What would settle it:** `Tools/Profiling/idle_cpu.py`, which exists for this
exact question — drive the Example to an image page, leave it alone, watch the
process. If it spins, the fix is one line (assign only on change) and the same
harness proves it. If it does not, something else already absorbs the
invalidation and that is worth knowing before touching it.

Queued rather than done because the fix is trivial and the measurement is not,
and shipping the trivial half without the measurement would be a guess.

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
