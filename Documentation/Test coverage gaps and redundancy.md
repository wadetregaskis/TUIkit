# Test coverage gaps and redundancy

A review of the unit-test suite (114 test files, 1560 tests
across 210 suites, all Swift Testing — `@Suite`/`@Test`/
`#expect`) against the source. Findings are grouped into
**coverage gaps** (untested or thinly-tested code, prioritised
by risk) and **redundancy / structure** (over-testing,
duplication, missed parameterisation). Every claim below was
verified by grepping the test tree, not inferred.

## Coverage gaps (prioritised)

### Critical — zero dedicated tests, high runtime risk

These have **no test file referencing them at all** and sit on
core paths:

- **`AppStorage` / `StorageBackend` / `JSONFileStorage` /
  `UserDefaultsStorage`** (`Sources/TUIkit/State/`). Persistence
  logic — Codable round-trips, the XDG/`~/.config` path
  resolution, the Linux-vs-Apple backend split, debounced
  writes — is entirely untested. This is the highest-value gap:
  it's pure, mockable (inject a `StorageBackend`), and a
  silent bug here loses user data.
- **`StdinArrivalStream` / `StdinArrivalNotifier`**
  (`Sources/TUIkit/App/`). The input-arrival race that replaced
  the bare `Task.sleep`. Async + `DispatchSource`; testable with
  a pipe FD. Untested.
- **`ViewRenderer`** (`Sources/TUIkit/Rendering/`). The core
  view→buffer entry point. Exercised incidentally but has no
  dedicated suite.

### High — no dedicated tests, but more contained / harder

- **`InputHandler`** (`Sources/TUIkit/App/`). Only *indirect*
  coverage (2 integration files reference it); no suite drives
  the five-layer dispatch chain directly. Worth a dedicated
  suite: synthesise `KeyEvent`s and assert which layer consumes
  each (text-input vs status-bar vs view-handler vs focus vs
  default), including the modal-Escape special case. Mockable
  via the existing `MockTerminal` + synthetic events.
- **`OnMouseEventModifier`** and **`DragGestureModifier`**
  (`Sources/TUIkit/Modifiers/`). The public mouse-event and
  drag-gesture entry points — zero references. Mouse plumbing
  underneath is tested, but these surfaces aren't.
- **`SignalManager`** (`Sources/TUIkit/App/`). Installs real
  SIGINT/SIGWINCH handlers — genuinely awkward to unit-test
  without side effects. Recommendation: either a narrow test of
  the non-installing logic, or a **documented rationale** that
  it's covered by manual/E2E testing (this is one of the "App/
  coverage" items in the project-analysis plan).

### Medium — thin coverage

- **`KeyPressModifier`** — referenced by only one test file;
  verify the modifier-registration + dispatch path is actually
  asserted, not just compiled.
- **`LocalizedString` / localization** — no references;
  low runtime risk but easy to cover (lookup, fallback,
  interpolation).
- **View extensions** (`Sources/TUIkit/Extensions/`, ~10 files)
  — no dedicated tests; behaviour is partly exercised through
  View tests. The project-analysis plan calls for targeted
  coverage here.

### Not a gap (verified, despite first appearances)

- **`RenderContext`** is referenced by ~60 test files — it's the
  standard fixture for nearly every render test, so it's
  exercised exhaustively even without a file named after it.
- **`ASCIIConverter` / `RGBAImage`** are well covered by
  `ImageTests.swift` (contra older notes that listed them as
  gaps; the project-analysis plan has been updated accordingly).

## Redundancy / structure

### The multi-file splits are mostly legitimate — don't merge reflexively

Earlier notes flagged "5 preference test files", "5 status-bar
test files", "5 colour test files" as redundant. On inspection
they're separation **by concern**, consistent with the project's
"one concern per file" rule, not duplication:

- Preference: `PreferenceKeyTests`, `PreferenceStorageTests`,
  `PreferenceValuesTests` — three different types.
- Status bar: `StatusBarItemTests`, `StatusBarStateTests`,
  `StatusBarViewTests`, `StatusBarSystemItemsModifierTests` —
  four distinct units.
- Colour: `ColorTests`, `ColorDownsamplingTests`,
  `ColorDepth*`, `PaletteDefaultTests`, `PaletteRegistryTests`,
  `PredefinedPaletteTests` — distinct types/behaviours.

Merging these would *hurt* navigability. No action recommended.

### The real opportunity: parameterisation

Several suites were shaped as N near-identical `@Test` functions
that differ only in an input value — exactly what Swift Testing's
parameterised tests are for. Benefit: fewer, denser tests; adding a
case is one row, not a new function; failures report the offending
argument.

**Done:**

- `ColorDownsamplingTests` — now `@Test(arguments:)` tables:
  RGB→palette256 index, colour→ANSI16, `downsample(colour, depth)`,
  fore/background codes per colour+depth, bright-passthrough per
  depth.
- `MouseEventSGRParsingTests` — now tables: SGR/legacy sequences →
  (button, phase, x, y), plus rejected-sequence tables (the
  shift-modifier case stays standalone, asserting a different field).

**Assessed, not worth it:** the cursor / list **style** suites
(`TextCursorStyleTests`, `ListStyleTests`) are a mix of
shape→character, default-value, custom-init and `Equatable` checks
rather than one repeated mapping; they're already small and tidy, so
parameterising only the handful of mapping rows would be churn for
little gain.

### Helper duplication

Context-creation and ANSI/render-assertion helpers are
copy-pasted across many files; there is one good shared mock
(`Tests/TUIkitTests/Mocks/MockTerminal.swift`). A
`Tests/TUIkitTests/TestHelpers/` area for the common
`makeContext()` / render-verifier helpers would cut duplication —
but it's a broad, churny migration touching many files, so it's
pinned for a decision rather than done unilaterally (see
`questions-for-wade.md`).

### Possibly over-tested (low priority)

`OptionalViewTests`, `TupleViewEquatableTests`, `EdgeInsetsTests`
lean toward testing trivial conformances. Not worth removing
(cheap, and they document intent), but not worth expanding
either.

## Suggested order of attack

1. ~~`AppStorage` + backends~~ — **done** (`AppStorageTests`, `MockStorageBackend`).
2. `InputHandler` five-layer dispatch suite — **still open** (the main
   remaining gap; only indirect coverage today).
3. ~~`StdinArrivalStream`~~ — **done** (`StdinArrivalNotifierTests`).
4. ~~`OnMouseEventModifier` / `DragGestureModifier`~~ — **done**, and the
   sibling gesture modifiers too: `onTapGesture`, `onScrollGesture`.
5. ~~Parameterise `ColorDownsampling` + SGR-parsing~~ — **done**. (The
   style suites were assessed as not worth parameterising — see above.)
6. View-extension targeted tests — **largely done** (gesture modifiers,
   `String.withPersistentBackground`; `truncatedToWidth` was already
   well covered via `TextTests`). `SignalManager` covered via the
   extracted `SignalFlags` + tests.

Also closed along the way: **`ViewRenderer`** now has a dedicated suite
(`ViewRendererTests`) — writing it uncovered and fixed a real crash in
`renderOnce(_:)` (it rendered with an empty environment).

Each remaining item is independent and can land as its own small, green
commit. The clear next one is the `InputHandler` five-layer suite.
