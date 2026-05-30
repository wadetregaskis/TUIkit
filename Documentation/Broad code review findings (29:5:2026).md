# Broad code-review findings (29/5/2026)

A broad pass over the library source (Sources/TUIkit,
TUIkitCore, TUIkitStyling, TUIkitView, TUIkitImage; the example
app was out of scope) looking for correctness bugs,
inefficiencies, and refactoring/readability opportunities.

**Headline: the library is in good shape.** There is no backlog
of safe, high-value fixes waiting to be applied. I deliberately
applied *no* code changes from this pass — every concrete
candidate I dug into was either already handled, not actually a
problem, or too delicate to change autonomously without better
test coverage first (detail below). I'd rather report that
honestly than make a token edit.

Findings are verified against the code, not assumed. Where a
plausible-sounding issue turned out to be a non-issue, it's
listed under "Checked and rejected" so it isn't re-chased later.

## The one real refactor candidate

### Consolidate ANSI-sequence scanning in `String+TerminalWidth.swift`

- **File:** `Sources/TUIkitCore/Extensions/String+TerminalWidth.swift`
  (672 lines — over the project's ~500-line guideline).
- **What:** The "scan past an ANSI escape sequence
  (`ESC [ … final-byte`)" logic is open-coded in roughly a dozen
  methods (`strippedLength`, `stripped`, `ansiAwarePrefix`,
  `ansiAwarePrefixForTerminalApp`, `ansiAwareSuffix`,
  `ansiSGRContextAndCleanSuffix`, `leadingANSISequences`,
  `containsTerminalAppCursorAdvanceQuirk`,
  `withTerminalAppCursorCompensation`, …). ~54 sites touch ESC/
  ANSI handling.
- **Why it's worth doing:** a single source of truth for "where
  does this escape sequence end" would cut duplication, shrink
  the file, and mean a parser fix lands in one place. Aligns
  with the repo's "reuse before adding" rule.
- **Why I did NOT do it now (RISK: MODERATE→HIGH):** these
  methods have genuinely *different* needs at the boundary
  (strip vs clip vs Terminal.app cursor compensation vs
  SGR-context preservation), so a shared scanner has to be
  carefully parameterised, not naively extracted. The
  Terminal.app emoji/cursor-advance behaviour is subtle (see
  `Emoji rendering bugs in macOS Sequoia's Terminal.app.md`),
  and the end-to-end test net here is shallow — a subtle
  regression could ship unnoticed.
- **Recommended approach:** *first* add characterisation tests
  that pin the current output of each public method across a
  matrix of inputs (plain / ANSI-heavy / emoji clusters /
  Fitzpatrick / CJK / boundary widths) — this doubles as closing
  a coverage gap — *then* extract a private
  `scanANSISequence(from:in:)` helper and route the methods
  through it, re-running the characterisation tests to prove
  byte-for-byte equivalence. The new `text/*` benchmarks can
  confirm no perf regression. Pinned for Wade because it's a
  judgement call on a delicate, central file.

## Minor / optional (low value, low risk)

- **`TextFieldContentRenderer.swift` (~line 157):** a boundary
  check uses a nested ternary inside a comparison
  (`visibleIndex < width - (textIndex >= clampedPosition ? 0 : 1)`).
  Correct, but hard to parse; extracting a named
  `reservedForCursor` local would read better. Cosmetic.
- **`Color+Downsampling.swift`:** the 6-entry cube-level array
  and 16-entry ANSI table use linear scans. This is *correct and
  fine* — at n=6/n=16 a linear scan beats binary search / LUT
  machinery (branch-predictable, cache-friendly). Noting it
  explicitly so the "optimise with binary search" idea isn't
  raised again: don't. A short comment naming why 6 levels exist
  would be the only worthwhile touch.
- **File-size guideline:** `String+TerminalWidth.swift` (672) is
  the main offender; `RenderLoop.swift` and a couple of others
  are worth a glance against the ~500-line guideline, but none
  are urgent.

## Checked and rejected (verified non-issues)

So these aren't re-investigated later:

- **`StateStorage.endRenderPass` "double filter":** the two
  filter loops operate on *two different dictionaries*
  (`values` and `trackedValues`); they can't be merged and the
  intermediate `staleKeys` array is needed to avoid
  mutate-while-iterate. Correct as written.
- **`TrackRenderer` `result += …` "should use a builder":** in
  Swift, `String` append is amortised O(1) on an owned buffer;
  switching to an `[String]` + `joined()` would add an array
  allocation and is not clearly faster. Not worth changing.
- **`ramp.last!` in `TrackRenderer`:** force-unwrap on a
  hardcoded non-empty `[Character]`; safe, and not in a position
  to crash.

## Positives confirmed during the pass

- No `try!` / `as!` / reachable `fatalError` found in hot paths;
  crash-safety discipline is strong.
- Darwin-only APIs are guarded with
  `#if canImport(Glibc) || canImport(Musl)`; cross-platform
  parity is maintained.
- `@unchecked Sendable` usage is minimal and justified.
- Equatable/Hashable conformances are consistent.
- The render diff / cache-invalidation path reads as correct.