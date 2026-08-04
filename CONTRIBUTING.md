# Contributing to TUIkit

TUIkit is a SwiftUI-like framework for building Terminal User Interfaces in pure Swift, with no ncurses or external C dependencies (the only C is the in-tree `stb_image` decoder, used as the image-decoding fallback where AppKit's `NSImage` is unavailable). It targets SwiftUI API parity wherever possible.

## Hard Requirements (non-negotiable)

| Requirement | Details |
|-------------|---------|
| **Swift 6.2** | `swift-tools-version: 6.2`. Language features up to 6.2 are fair game; nothing newer. |
| **Cross-platform** | Must build and run on macOS and Linux. Windows is a work in progress — see below. |
| **CI must pass** | All tests and linting must pass before merge. |

### What CI covers

Every lane runs `swift build`, `swift test`, and both smoke tests
(`Stress --selfcheck` everywhere; the PTY walk on macOS and Linux).

Swift 6.2, 6.3, 6.4 and trunk are each covered on every operating system:

| Swift | macOS | Linux | Windows |
|-------|-------|-------|---------|
| 6.2 | Xcode 26 on `macos-15` | `swift:6.2-noble` | `swift:6.2-…` |
| 6.3 | Xcode 26 on `macos-26` | `swift:6.3-noble` | `swift:6.3-…` |
| 6.4 | swift.org `6.4.x` snapshot | `nightly-6.4.x-noble` | `nightly-6.4.x-…` |
| main | swift.org latest snapshot | `nightly-main-noble` | — |

Released Swift comes from Xcode on macOS; unreleased Swift comes from
swift.org. Deliberately **not** from the Xcode 27 beta, even though it bundles
6.4 — the beta's 6.4 is an older build than the current branch snapshot, so it
gives weaker early warning of upcoming-compiler breakage, which is the whole
reason to run a 6.4 lane before 6.4 ships.

Linux additionally runs Swift 6.3 on arm64, and lint runs on Linux only — it
gates everything else, so a style slip fails in a minute rather than after
seventeen builds.

Everything except the 6.2/6.3 macOS and Linux lanes is **advisory**
(`continue-on-error`): visible, but unable to block a merge. Nightly toolchains
break for reasons that have nothing to do with this package, and Windows does
not build yet.

There is no macOS 27 runner image yet — macOS 27 is still a developer preview.
When one appears it should be added as a required lane alongside `macos-15` and
`macos-26`; see the `TODO(macOS 27)` at the top of the workflow.

#### The `CI` gate job

`CI` is a job that runs after everything else and fails if any non-advisory
lane did not succeed. **It is the only check that should be marked as a
required status check in the repository's branch-protection settings**
(Settings → Branches → branch protection rule for `main` → "Require status
checks to pass before merging"). A required check is one GitHub refuses to
merge a PR without.

Requiring it rather than the individual jobs matters for two reasons:

- Matrix job names change whenever the matrix changes, and branch protection
  matches checks *by name*. Requiring them directly means editing repository
  settings every time a Swift version is added.
- A **skipped** job reports as *success* to branch protection. If `macos` were
  required directly and it got skipped — because `lint` failed, say — the PR
  would look mergeable having built nothing. The gate treats `skipped` as a
  failure, so that cannot happen.

### Windows

Windows is **not supported yet** — the package does not build there. The CI
lane exists to make the port's progress visible, and is staged accordingly:

- `TUIkitCore`, `TUIkitStyling`, `TUIkitView` and `TUIkitImage` are expected to
  **pass**. Of 345 source files only 8 touch POSIX-only APIs, and 7 of those
  are in the umbrella module. Breaking one of these four is a real regression,
  so keep them free of `termios`/`ioctl`/signal dependencies.
- Building `TUIkit`, testing, and smoking are expected to **fail** until the
  console layer is ported. Each is its own CI step so all four can be watched
  going green independently.

The known blockers, in rough order of difficulty:

1. **stdin wake-up.** `StdinArrivalStream` uses
   `DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO,…)`.
   swift-corelibs-libdispatch's Windows backend explicitly refuses console
   handles (`FILE_TYPE_CHAR` → `WIN_PORT_ERROR()`), so the whole mechanism has
   to be rebuilt around a thread blocking on `ReadConsoleInput`.
2. **Resize notification.** Windows has neither `SIGWINCH` nor a
   `TIOCGWINSZ` equivalent. Size changes arrive as `WINDOW_BUFFER_SIZE_EVENT`
   records from `ReadConsoleInput`, which is the same call as (1) — so they
   want designing together. Do not plan around the in-band resize escape
   (`CSI ? 2048 h`); it is an unassigned backlog item on Windows Terminal.
3. **Raw mode and VT output.** `GetConsoleMode`/`SetConsoleMode` replace
   `termios`, and VT output must be opted into with
   `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN`.
   `GetConsoleScreenBufferInfo` replaces `ioctl(TIOCGWINSZ)`.
4. **The PTY smoke harness.** `Tools/Smoke/tui_walk.py` uses `pty`/`termios`,
   so it is POSIX-only; a Windows equivalent needs ConPTY.

Two things that are *not* blockers, despite looking like them: `@AppStorage`
already falls back to JSON-file storage off Apple platforms, so the open
Windows `UserDefaults` bug does not affect it; and SwiftLint gained Windows
support in 0.64.0.

## Build, Test & Lint

```bash
# Build
swift build

# Run all tests (~3,350 tests, Swift Testing framework)
swift test

# Run a single test suite. NOTE: --filter matches the Swift TYPE name, not the
# @Suite display string — `--filter AlertDismissalTests`, not "Alert dismissal".
swift test --filter <TestSuiteName>

# Lint (must report zero violations)
swiftlint

# Format (configured but not enforced in CI)
swift-format format -i -r Sources Tests

# Build the documentation (one archive covering every module)
Tools/BuildDocs/build-docs.sh            # add --analyze for every diagnostic
```

> Use the script, not `swift package generate-documentation --target TUIkit`.
> The latter documents only what the umbrella module itself declares, which
> silently omits `View`, `Color`, `Binding` and everything else the sibling
> modules define — see [`Tools/BuildDocs/README.md`](Tools/BuildDocs/README.md).

## Pull Request Requirements

1. Branch from `main`
2. Fill in the PR template completely
3. The `CI` gate check must be green (it covers macOS + Linux; the Windows and
   nightly-toolchain lanes are advisory and do not block)
4. No new SwiftLint warnings
5. Follow the architecture and API rules below

## Architecture

### SwiftUI API Parity

Public APIs **must** match SwiftUI signatures exactly unless terminal constraints require deviation (document why in comments).

| Aspect | Requirement |
|--------|-------------|
| Parameter names | Exact (`isPresented`, not `isVisible`) |
| Parameter order | Exact (title, binding, actions, message) |
| Parameter types | Match closely (ViewBuilder closures, not pre-built values) |
| Trailing closures | `@ViewBuilder () -> T`, not `String` |

**Before implementing any SwiftUI-equivalent API:** Look up the exact SwiftUI signature first.

### View Architecture

- Every **public** control must be a `View` with a real `body: some View`
- The `body` must return actual Views (not `Never`, not `fatalError()`)
- `Renderable` is only for leaf nodes (`Text`, `Spacer`, `Divider`), private `_*Core` views, layout primitives, and modifier infrastructure — never public controls
- All modifiers must propagate through the entire View hierarchy
- Environment values must flow down automatically

### General Principles

- No singletons
- Search the codebase for similar patterns before implementing anything new
- Consolidate and reuse before adding new functions or types

## Code Style

- Line length: 160 characters (warning), 200 (error)
- 4-space indentation
- Trailing commas in multi-line collections
- See `.swiftlint.yml` and `.swift-format` for full configuration

## Testing

- Uses Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- Tests run in parallel; the few that mutate global state are serialised
- Test files mirror source structure in `Tests/TUIkitTests/`
- Each library module also has its own test target (`TUIkitCoreTests`,
  `TUIkitStylingTests`, `TUIkitViewTests`, `TUIkitImageTests`) that links **only
  that module**, so a module test cannot reach across a layer boundary. Put a
  test in the module target it belongs to; `Tests/TUIkitTests` is for
  integration tests and everything in the umbrella module.
  `Tools/validate-test-boundaries.sh` checks this and runs in CI.

## The `project-template/` directory

`project-template/` is a starter kit for spinning up a new app built on
TUIkit (a `tuikit` scaffold plus an `install.sh` and its own README). It
is intentionally kept **inline in this repository** rather than split into
a separate repo: it's small, low-churn, and easiest to keep in step with
the library when it lives alongside it. It is excluded from source
archives / GitHub release tarballs via `export-ignore` in `.gitattributes`,
so it adds no weight for SwiftPM consumers. If it ever grows enough to
warrant independent versioning, revisit moving it out.

## Detailed Architecture Rules

For comprehensive architecture documentation including the `_*Core` pattern, focus system, state management, and interactive view rules, see [`.claude/CLAUDE.md`](.claude/CLAUDE.md).
