//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SignalManager.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

// MARK: - Signal Flags

/// The three boolean flags a signal handler may set, plus the
/// consume-on-read logic the main loop uses to drain them.
///
/// Extracted into its own value type so the flag semantics can be
/// unit-tested in isolation (construct a `SignalFlags`, set a field,
/// assert `consume*` returns `true` once then `false`) without
/// installing real handlers, sending real signals, or touching the
/// process-global instance below.
///
/// ## Why three plain `Bool`s and not locks or atomics?
///
/// POSIX signal handlers may only call "async-signal-safe" functions.
/// Lock acquisition (pthread_mutex_lock, os_unfair_lock_lock) and most
/// Swift runtime functions are NOT safe. Writing a `Bool` field of this
/// struct at a fixed offset in the global instance is a single aligned
/// memory store — async-signal-safe. The worst case is a torn read,
/// which for a `Bool` just means we might miss one signal or see it
/// twice; both are acceptable (re-rendering twice is harmless, and a
/// missed signal is caught on the next iteration).
struct SignalFlags {
    /// Set by SIGWINCH (or `requestRerender`) to request a re-render.
    var needsRerender = false

    /// Set by SIGWINCH to indicate a terminal resize. Separate from
    /// `needsRerender` because resize requires additional work
    /// (invalidating the frame diff cache) beyond just re-rendering.
    var terminalResized = false

    /// Set by SIGINT to request a graceful shutdown. The actual cleanup
    /// (disabling raw mode, restoring cursor, exiting alternate screen)
    /// happens in the main loop — signal handlers must not call
    /// non-async-signal-safe functions like `write()` or `fflush()`.
    var needsShutdown = false

    /// Returns `true` if a re-render was requested since the last call,
    /// resetting the flag. This consume-on-read pattern prevents
    /// redundant renders.
    mutating func consumeRerender() -> Bool {
        guard needsRerender else { return false }
        needsRerender = false
        return true
    }

    /// Returns `true` if a terminal resize occurred since the last call,
    /// resetting the flag.
    mutating func consumeResize() -> Bool {
        guard terminalResized else { return false }
        terminalResized = false
        return true
    }
}

/// The process-global signal flags.
///
/// `nonisolated(unsafe)` is the correct annotation: the flags are
/// genuinely unsafe in the general case but safe in this specific usage
/// pattern (single writer from a signal handler, single reader from the
/// main loop), and the handler only ever performs an async-signal-safe
/// `Bool`-field store on it.
nonisolated(unsafe) private var signalFlags = SignalFlags()

// MARK: - Signal Manager

/// Manages POSIX signal handlers for the application lifecycle.
///
/// Encapsulates the global signal flags and handler installation.
/// The flags remain file-private globals because C signal handlers
/// cannot capture Swift object references.
///
/// ## Usage
///
/// ```swift
/// let signals = SignalManager()
/// signals.install()
///
/// while running {
///     if signals.shouldShutdown { break }
///     if signals.consumeRerenderFlag() { render() }
/// }
/// ```
internal struct SignalManager {
    /// Whether a graceful shutdown was requested (SIGINT).
    var shouldShutdown: Bool {
        signalFlags.needsShutdown
    }
}

// MARK: - Internal API

extension SignalManager {
    /// Checks and resets the rerender flag (SIGWINCH or state change).
    ///
    /// Returns `true` if a re-render was requested since the last call,
    /// then resets the flag. This consume-on-read pattern prevents
    /// redundant renders.
    ///
    /// - Returns: `true` if a rerender was requested.
    mutating func consumeRerenderFlag() -> Bool {
        signalFlags.consumeRerender()
    }

    /// Checks and resets the terminal resize flag (SIGWINCH).
    ///
    /// Returns `true` if the terminal was resized since the last call,
    /// then resets the flag. Used by `AppRunner` to invalidate the
    /// frame diff cache on resize.
    ///
    /// - Returns: `true` if a terminal resize occurred.
    mutating func consumeResizeFlag() -> Bool {
        signalFlags.consumeResize()
    }

    /// Requests a re-render programmatically.
    ///
    /// Called by the `AppState` observer to signal that application
    /// state has changed and the UI needs updating.
    func requestRerender() {
        signalFlags.needsRerender = true
    }

    /// Installs POSIX signal handlers for SIGINT and SIGWINCH.
    ///
    /// - SIGINT (Ctrl+C): Sets the shutdown flag for graceful cleanup.
    /// - SIGWINCH (terminal resize): Sets the rerender flag.
    ///
    /// Signal handlers only set boolean flags — all actual work
    /// happens in the main loop, which is async-signal-safe.
    func install() {
        // Each assignment is a single async-signal-safe Bool-field store
        // on the global `signalFlags`.
        signal(SIGINT) { _ in
            signalFlags.needsShutdown = true
        }
        signal(SIGWINCH) { _ in
            signalFlags.needsRerender = true
            signalFlags.terminalResized = true
        }
    }
}
