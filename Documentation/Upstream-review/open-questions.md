# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. Cap an image download at an encoded byte limit

**From** `f8655103` (PR #44) · **ledger verdict** `adapt` (half done)

`loadImage(fromURL:)` buffers the entire HTTP response into `Data` before
anything looks at it. `maxPixelCount` protects the *decoded* size; nothing
protects the *encoded* one, so a server that hands us a 2 GB body — hostile,
misconfigured, or just a wrong URL — gets 2 GB of resident memory before we
decide we did not want it.

Upstream's fix is a `URLSessionDataDelegate` that refuses on
`expectedContentLength`, counts bytes as they arrive, and cancels the task on
overflow. Correct in substance. But it drives that delegate with a
`DispatchSemaphore`, which is exactly the blocking design we deliberately
removed: ours suspends rather than parking a cooperative-pool thread, and
cancels promptly. `URLImageDownloadTests` has two tests guarding that. Porting
upstream's code as written would trade one real problem for a worse one.

**Options**

1. **`URLSession.bytes(for:)`** — an `AsyncSequence` of bytes; accumulate with a
   running cap and throw the moment it is exceeded. About fifteen lines, keeps
   `async` and cancellation for free, no delegate object at all. The risk is
   Linux: `bytes(for:)` exists in swift-corelibs-foundation but is less
   exercised there than on Darwin, so this wants a CI run on both before it is
   trusted. *Recommended.*
2. **A delegate, driven by a continuation rather than a semaphore.** Upstream's
   logic, our concurrency model — including the `expectedContentLength`
   pre-check, which refuses an oversized body before a single byte arrives.
   More code, one more `@unchecked Sendable` box to get right, but no doubt
   about platform support.
3. **Leave it.** The exposure needs an untrusted or broken URL, and the app
   chose that URL. Not nothing, but not urgent either.

**What is needed from you:** which of those, and what the default limit should
be (upstream ties it to the decoder's `maxInputBytes`; we have no encoded-size
limit at all today, so either a new environment value alongside
`imageMaxPixelCount` or a fixed ceiling would be new API surface).

---

## 2. Verify the package still works as a dependency

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
