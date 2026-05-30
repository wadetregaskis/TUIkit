# State Persistence (Session Continuity / Crash Recovery)

## Preface

The goal is for session state to survive app restarts/crashes via a
disk-persisted `@RestoredState` wrapper around `@State`: values
auto-save on change (debounced) and auto-restore on startup, with
signal handlers flushing before shutdown. Useful for file managers,
editors, or any app tracking last directory, scroll position, or open
files. Builds on the State Storage Identity system to keep state stable
across renders while adding optional persistence.

> **Status (updated 2026-05-30): NOT IMPLEMENTED — still aspirational.**
> An earlier version of this preface claimed `@RestoredState` already
> shipped; that was incorrect. Verified against the codebase:
>
> - `@RestoredState` does **not** exist. Neither does the
>   `StatePersistenceAdapter` protocol or `StateStorage`-level disk
>   persistence — `StateStorage` is **in-memory only** (it keeps
>   `@State` stable across render passes; values die on exit).
> - What **does** exist, and partly overlaps the goal:
>   - `@AppStorage` (`Sources/TUIkit/State/AppStorage.swift`) — a
>     `Codable` property wrapper for **explicit** persistent
>     preferences, backed by a `StorageBackend` protocol with a
>     `JSONFileStorage` default (`~/.config/<app>/settings.json`, or
>     `XDG_CONFIG_HOME`) and a `UserDefaultsStorage` variant
>     (`UserDefaultsStorage.swift`; UserDefaults on Apple, JSON-file
>     emulation on Linux). Writes are debounced via a detached task.
>   - Signal handling (`Sources/TUIkit/App/SignalManager.swift`,
>     SIGINT/SIGWINCH) plus terminal raw-mode restore on exit — i.e.
>     the graceful-shutdown half of the story is in place, but it does
>     **not** flush `@State` to disk (there's nothing to flush yet).
>
> So the remaining work is the **automatic** `@State`-recovery layer
> (`@RestoredState` + `StateStorage` persistence integration). The
> explicit-preferences use case is already served by `@AppStorage`.
> Decide whether `@RestoredState` should build on the existing
> `StorageBackend` protocol rather than introducing a parallel
> `StatePersistenceAdapter` (pinned in `questions-for-wade.md`).

## Context / Problem

Builds on the State Storage Identity refactoring. `StateStorage` keeps `@State` values stable in memory across render passes. This feature would add optional disk persistence so that state can survive app restarts or crashes.

### Use Cases in Terminal Apps

1. **Crash Recovery**: SIGTERM/SIGINT: write last state to disk, restore on restart
2. **Session Continuity**. Ue.g. a TUI file manager remembers current directory, scroll position
3. **Explicit Save/Restore**. Uuser-triggered (keybinding for "Save Session")

**Not a use case:** iOS-style background killing (does not exist in terminal apps).

## Specification / Goal

Implement a disk-backed state persistence system with:
- `@RestoredState` property wrapper for `Codable` types
- `StatePersistenceAdapter` protocol with file-based default
- Signal handlers for graceful shutdown
- Automatic restoration on app startup
- Debounced writes for performance

## Design

### New Property Wrapper: `@RestoredState`

```swift
@RestoredState var currentPath: String = "~"
@RestoredState var scrollOffset: Int = 0
```

Difference from `@State`: values are serialized to disk on change (debounced) or on app shutdown, and restored on next launch.

**Constraint:** `Value` must be `Codable`. `@State` remains without this constraint.

### `StatePersistenceAdapter` Protocol

```swift
protocol StatePersistenceAdapter {
    func save(_ data: Data, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
    func removeAll() throws
}
```

Default implementation: JSON file at `~/.config/<app-name>/state.json` or XDG-compliant path.

### Integration with `StateStorage`

`StateStorage` gains an optional `persistence: StatePersistenceAdapter?`. On `storage(for:default:)` lookup, disk is checked first, then default is used. On value change, disk write is triggered (debounced).

### Signal Handler for Crash Recovery

`AppRunner` registers signal handlers for SIGTERM/SIGINT that call `StateStorage.flush()` before the app terminates.

## Implementation Plan

1. Finalize design and API surface
2. Implement `StatePersistenceAdapter` protocol + file implementation
3. Implement `@RestoredState` property wrapper
4. Integrate into `StateStorage`
5. Add signal handlers in `AppRunner`
6. Write comprehensive tests
7. Add documentation and examples

## Checklist

- [ ] Finalize design (incl. decision: reuse existing `StorageBackend` vs new `StatePersistenceAdapter`)
- [ ] Persistence adapter / backend for state — **note:** a general `StorageBackend` + `JSONFileStorage`/`UserDefaultsStorage` already exists for `@AppStorage`; prefer reusing it
- [ ] `@RestoredState` property wrapper — **not started**
- [ ] Integration into `StateStorage` (currently in-memory only) — **not started**
- [x] Signal handlers exist (`SignalManager`, SIGINT/SIGWINCH) + raw-mode restore on exit — **but they do not flush `@State` yet** (nothing to flush until the above lands)
- [ ] Tests
- [ ] Documentation

## Dependencies

- **State Storage Identity must be completed** (Phase 1-4 minimum)
- `Codable` constraint only affects `@RestoredState`, not `@State`
- Signal handlers must coordinate with existing terminal cleanup (raw mode restore)

## Open Questions

1. **Debounce interval?** Write every state change immediately vs. batched (e.g. every 500ms)?
2. **Encryption?** Sensitive data in state? Probably not needed for terminal apps.
3. **Migration?** What if state structure changes between app versions?
4. **Granularity?** Everything in one file or one file per view identity?
