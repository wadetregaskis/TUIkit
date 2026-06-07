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

/// Read/write ends of a self-pipe. A signal handler writes one byte to `write`
/// (async-signal-safe); the run loop watches `read` with a `DispatchSource` and
/// wakes. This lets the demand-driven loop — which blocks indefinitely when
/// nothing needs rendering — notice SIGWINCH (resize) / SIGINT without polling.
/// `(-1, -1)` until ``SignalManager/install()`` creates it.
nonisolated(unsafe) private var signalWakePipe: (read: Int32, write: Int32) = (-1, -1)

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
        // Self-pipe (non-blocking both ends): the run loop watches the read end
        // to wake on signals, since it is otherwise demand-driven and may block
        // indefinitely. Best-effort — if `pipe` fails the flags still work, the
        // loop just won't be woken by signals until its next wake from elsewhere.
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 {
            for fd in fds {
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            }
            signalWakePipe = (read: fds[0], write: fds[1])
        }

        // Each handler does only async-signal-safe work: aligned Bool stores on
        // `signalFlags`, then a single non-blocking one-byte write to the
        // self-pipe to wake the loop.
        signal(SIGINT) { _ in
            signalFlags.needsShutdown = true
            let fd = signalWakePipe.write
            if fd >= 0 {
                var byte: UInt8 = 0
                _ = write(fd, &byte, 1)
            }
        }
        signal(SIGWINCH) { _ in
            signalFlags.needsRerender = true
            signalFlags.terminalResized = true
            let fd = signalWakePipe.write
            if fd >= 0 {
                var byte: UInt8 = 0
                _ = write(fd, &byte, 1)
            }
        }
    }

    /// The read end of the signal self-pipe (`-1` if `install()` hasn't run or
    /// the pipe couldn't be created). The run loop watches this with a
    /// `DispatchSource` to wake on SIGWINCH / SIGINT.
    var signalWakeReadFD: Int32 {
        signalWakePipe.read
    }
}
