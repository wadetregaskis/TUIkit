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

## Upstream branches not on `main`

Not part of the numbered backlog: an unmerged branch is a proposal, and may
still change or be abandoned. Listed so they are not forgotten.

| Branch | Status |
|---|---|
| `issue/20-layout-primitives` | not yet examined |
| `issue/27-async-image-pipeline` | not yet examined |
| `issue/30-project-generator` | not yet examined |
| `issue/50-ci-node-24` | not yet examined |
