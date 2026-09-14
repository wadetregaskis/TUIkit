//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SoftTrap.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Soft trap

/// A programming error the framework can carry on past: a value an app passed
/// that has no meaning, where a sensible fallback exists.
///
/// A debug build stops at the call with `assertionFailure`, because that is the
/// build a developer is looking at and the fallback would hide the mistake. A
/// release build takes the fallback and reports the message once per distinct
/// message, since a bad value in a view is usually met on every frame.
///
/// Where a release report goes follows ``DiagnosticChannel``:
///
/// - `TUIKIT_DIAGNOSTICS_FILE` names a file, and the report is appended to it
///   straight away.
/// - Otherwise the report goes to stderr. While an app owns the terminal,
///   stderr is the screen it is drawing, so the report is held and written
///   once the app gives the terminal back (``terminalRestored()``), when it can
///   be read. A process that ends without restoring the terminal loses what
///   was held.
package enum SoftTrap {
    /// The process's one log. Static because a soft trap is reported from
    /// wherever a bad value is met, with nothing to hand it down through.
    package static let log = SoftTrapLog(
        holdsWhileTerminalIsOwned: DiagnosticChannel.destination == nil,
        write: { DiagnosticChannel.emit($0) })

    /// Reports `message`: an assertion failure in a debug build, a report
    /// once per distinct message in a release build.
    ///
    /// - Parameter message: What was wrong, what the framework does instead, and
    ///   the API the value came from, in words an app developer can act on.
    package static func report(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
            log.record(message)
            assertionFailure(message, file: file, line: line)
        #else
            log.report(message)
        #endif
    }

    /// Every distinct message reported so far, oldest first.
    package static var recorded: [String] { log.recorded }

    /// Holds stderr reports from now on, because an app has just taken the
    /// terminal.
    package static func holdUntilTerminalRestored() { log.holdUntilTerminalRestored() }

    /// Writes the held reports, because the app has given the terminal back.
    package static func terminalRestored() { log.terminalRestored() }
}

// MARK: - Soft-trap log

/// What ``SoftTrap`` records and where it sends it, as an instance so tests can
/// read a log of their own without a debug build stopping at the report.
package final class SoftTrapLog: Sendable {
    private struct State: Sendable {
        var recorded: [String] = []
        var seen: Set<String> = []
        var held: [String] = []
        var isHolding = false
    }

    private let state = Lock(initialState: State())
    private let holdsWhileTerminalIsOwned: Bool
    private let write: @Sendable (String) -> Void

    /// Creates a log.
    ///
    /// - Parameters:
    ///   - holdsWhileTerminalIsOwned: Whether ``holdUntilTerminalRestored()``
    ///     holds reports back. `false` when they go to a file, which the
    ///     terminal cannot hide.
    ///   - write: Where a report's text goes.
    package init(holdsWhileTerminalIsOwned: Bool, write: @escaping @Sendable (String) -> Void) {
        self.holdsWhileTerminalIsOwned = holdsWhileTerminalIsOwned
        self.write = write
    }

    /// Every distinct message recorded so far, oldest first.
    package var recorded: [String] {
        state.withLock { $0.recorded }
    }

    /// Records `message` without writing it.
    ///
    /// - Returns: `true` the first time this message is seen.
    @discardableResult
    package func record(_ message: String) -> Bool {
        state.withLock { state in
            guard state.seen.insert(message).inserted else { return false }
            state.recorded.append(message)
            return true
        }
    }

    /// Records `message` and, the first time it is seen, writes it or holds it.
    package func report(_ message: String) {
        let text = Self.text(for: message)
        let writeNow = state.withLock { state in
            guard state.seen.insert(message).inserted else { return false }
            state.recorded.append(message)
            guard !state.isHolding else {
                state.held.append(text)
                return false
            }
            return true
        }
        // Outside the lock: a write is I/O, and the lock is an unfair one.
        if writeNow { write(text) }
    }

    /// Holds reports from now on, if this log holds at all.
    package func holdUntilTerminalRestored() {
        guard holdsWhileTerminalIsOwned else { return }
        state.withLock { $0.isHolding = true }
    }

    /// Stops holding, and writes what was held in the order it was reported.
    package func terminalRestored() {
        let held = state.withLock { state in
            let held = state.held
            state.held.removeAll()
            state.isHolding = false
            return held
        }
        for text in held { write(text) }
    }

    /// The words a report is written in.
    static func text(for message: String) -> String {
        """
        [TUIkit] \(message)
          A debug build stops here. This build carried on with the fallback, \
        and reports each distinct message once.

        """
    }
}
