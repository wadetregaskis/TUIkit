# Open questions

Items from the upstream review that need the owner's decision. Each carries
enough description to decide from without reading the upstream patch.

When one is decided, it moves out of here: the reasoning goes into the relevant
`notes/PR-NN.md`, and the ledger rows change from `queued` to the real verdict.

Empty is the healthy state.

---

## 1. Stop Windows progress from silently regressing

**From** `f75e9ae4` (PR #46) · **ledger verdict** `queued`

### The real gap

`TUIkitCore`, `TUIkitStyling`, `TUIkitView` and `TUIkitImage` build on Windows
today. Nothing stops that from breaking: `windows_container` carries a
**job-level** `continue-on-error: true`, and the `CI` gate job lists it under
"Advisory lanes (never block)" and never reads its result. A commit that broke
`TUIkitCore` on Windows would land with CI fully green.

### What I originally proposed, and why it was the wrong shape

A lint banning `termios` / `ioctl` / signals / `DispatchSource` outside the
`TUIkit` umbrella — a cheap proxy, run on macOS and Linux in milliseconds.

The owner's objection lands: **we do not actually care which module holds the
Windows-incompatible code.** The end state is every module building and working
on Windows, so a rule that blesses POSIX in one module and forbids it in four
encodes a staging line that is supposed to be moving, and will be wrong the day
the port lands. It also tests a proxy for portability rather than portability.

### What to do instead — a ratchet on the real platform

The lane is **already structured for this** and nobody noticed. Its steps
already split into two groups:

- four module builds with *no* per-step flag — "expected to pass";
- `Build TUIkit`, `Build everything`, `Test`, `Smoke`, each with its own
  `continue-on-error: true` — "expected to fail until the console layer lands",
  each separate so all four can be watched going green independently.

That is exactly the right design. The only thing defeating it is the *job*-level
flag sitting above it, which makes the four "expected to pass" steps
unenforceable. So the change is two edits, not twenty lines of new tooling:

1. Make the job-level flag conditional instead of unconditional, so released
   toolchains are binding and nightlies stay advisory for the same reason they
   are everywhere else:
   ```yaml
   continue-on-error: ${{ startsWith(matrix.swift, 'nightly') }}
   ```
2. Move `windows_container` from the gate's advisory list into `required`.

Then the guarantee is "what builds on Windows today still builds on Windows
tomorrow", checked on Windows — and it ratchets by construction: each blocker
fixed is one per-step `continue-on-error` deleted, and when the port lands the
last flag goes and the file is simply correct with no staging left in it.

### What to weigh

- **Merge latency and flakiness.** This lane pulls a
  `windowsservercore-ltsc2022` container; if that is ever slow or flaky, it now
  blocks merges. It runs three matrix entries, two of which would become
  binding.
- **`windows_native`** is separately advisory; the same reasoning may or may not
  apply — I have not examined what it covers.
- The `CLAUDE.md` rule about keeping POSIX inside the umbrella is still worth
  *stating* as guidance. It just should not be the thing enforced, because it is
  a description of where the port has got to, not of what correct looks like.

Recommended, but it changes what can block a merge, so it is yours to say.

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
