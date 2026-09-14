//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SoftTrapTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// A log whose writes a test can read back.
private final class LogProbe: Sendable {
    private let writes = Lock(initialState: [String]())
    let log: SoftTrapLog

    init(holdsWhileTerminalIsOwned: Bool) {
        let writes = writes
        log = SoftTrapLog(holdsWhileTerminalIsOwned: holdsWhileTerminalIsOwned) { text in
            writes.withLock { $0.append(text) }
        }
    }

    var written: [String] { writes.withLock { $0 } }
}

@Suite("Soft trap")
struct SoftTrapTests {

    #if DEBUG
        /// The half of the contract a developer sees. It runs in a child process,
        /// because a stop in this one would end the whole test run.
        @Test("A debug build stops at a soft trap")
        func debugBuildStops() async {
            await #expect(processExitsWith: .failure) {
                SoftTrap.report("a deliberate soft trap")
            }
        }
    #endif

    @Test("Each distinct message is recorded and written once, however often it is reported")
    func distinctMessagesAreWrittenOnce() {
        let probe = LogProbe(holdsWhileTerminalIsOwned: true)

        probe.log.report("first")
        probe.log.report("second")
        probe.log.report("first")
        probe.log.report("second")

        #expect(probe.log.recorded == ["first", "second"])
        #expect(
            probe.written == [
                """
                [TUIkit] first
                  A debug build stops here. This build carried on with the fallback, \
                and reports each distinct message once.

                """,
                """
                [TUIkit] second
                  A debug build stops here. This build carried on with the fallback, \
                and reports each distinct message once.

                """,
            ])
    }

    @Test("Recording without writing still counts towards the one report")
    func recordingCountsAsSeen() {
        let probe = LogProbe(holdsWhileTerminalIsOwned: true)

        #expect(probe.log.record("once"))
        #expect(!probe.log.record("once"))
        probe.log.report("once")

        #expect(probe.log.recorded == ["once"])
        #expect(probe.written.isEmpty)
    }

    /// Stderr is the screen while an app owns the terminal, so a report written
    /// then would be drawn over by the next frame and gone when the app quits.
    @Test("While an app owns the terminal, stderr reports wait for it to be restored, in order")
    func stderrReportsWaitForTheTerminal() {
        let probe = LogProbe(holdsWhileTerminalIsOwned: true)

        probe.log.holdUntilTerminalRestored()
        probe.log.report("first")
        probe.log.report("second")
        #expect(probe.written.isEmpty, "written while the app owned the terminal: \(probe.written)")
        #expect(probe.log.recorded == ["first", "second"])

        probe.log.terminalRestored()
        #expect(probe.written == [SoftTrapLog.text(for: "first"), SoftTrapLog.text(for: "second")])

        probe.log.report("third")
        #expect(probe.written.last == SoftTrapLog.text(for: "third"))
        #expect(probe.written.count == 3)

        probe.log.terminalRestored()
        #expect(probe.written.count == 3, "a second restore wrote the held reports again")
    }

    @Test("A report bound for a file is written straight away, terminal or not")
    func fileReportsAreNotHeld() {
        let probe = LogProbe(holdsWhileTerminalIsOwned: false)

        probe.log.holdUntilTerminalRestored()
        probe.log.report("to a file")

        #expect(probe.written == [SoftTrapLog.text(for: "to a file")])
    }
}
