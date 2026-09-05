//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SignalManagerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// Exercises the libdispatch signal-source plumbing end to end by sending real
/// process signals and confirming the source handler ran (set its flag + woke
/// the loop).
///
/// `.serialized` because these send process-global signals — two of these
/// running concurrently would cross wires. Sending a signal is safe only
/// *after* `install()` returns: it awaits the registration barrier, so by then
/// every source is armed and even SIGTERM is caught rather than terminating
/// the test runner.
///
/// The time limit is for a source that never arms — a real bug, and one that
/// would otherwise hang the suite. It is five minutes rather than one because
/// of where the wake arrives. The source's handler runs on the main queue,
/// and in a full run that queue already holds every main-actor test not yet
/// started, so the handler cannot run until they have: the wake lands
/// seconds before the run ends, whatever the run's length. Measured on CI at
/// one commit, the first test here "passed after" 46.9 s of a 50.3 s macOS
/// run and 57.9 s of a 61.6 s Linux run, and failed a one-minute limit on a
/// Linux 6.2 lane whose run took 72.7 s. A limit inside the run's own length
/// is a limit on the run, not on signal delivery.
@MainActor
@Suite("SignalManager", .serialized, .timeLimit(.minutes(5)))
struct SignalManagerTests {
    /// Installs `signals`, sends `signal`, and returns once the source handler
    /// has run and woken us — proving delivery reached the main-actor handler.
    private func afterDelivering(_ signal: Int32, to signals: SignalManager) async {
        let (wakes, continuation) = AsyncStream.makeStream(of: Void.self)
        await signals.install(wake: { continuation.yield() })
        kill(getpid(), signal)
        var iterator = wakes.makeAsyncIterator()
        _ = await iterator.next()  // suspends → main queue pumps the source handler
    }

    @Test("SIGWINCH sets the resize flag (consume-once)")
    func sigwinchSetsResizeFlag() async {
        let signals = SignalManager()
        defer { signals.stop() }

        await afterDelivering(SIGWINCH, to: signals)

        #expect(signals.consumeResizeFlag() == true, "the resize flag is set after SIGWINCH")
        #expect(signals.consumeResizeFlag() == false, "and cleared by the first read (consume-on-read)")
        #expect(signals.shouldShutdown == false, "a resize does not request shutdown")
    }

    @Test("SIGTERM requests a graceful shutdown (sticky)")
    func sigtermRequestsShutdown() async {
        let signals = SignalManager()
        defer { signals.stop() }

        await afterDelivering(SIGTERM, to: signals)

        #expect(signals.shouldShutdown == true, "SIGTERM requests a graceful shutdown")
        #expect(signals.shouldShutdown == true, "and the shutdown flag is sticky, not consume-on-read")
        #expect(signals.consumeResizeFlag() == false, "a shutdown is not a resize")
    }

    @Test("stop() is idempotent")
    func stopIsIdempotent() async {
        let signals = SignalManager()
        await signals.install(wake: {})
        signals.stop()
        signals.stop()  // must not crash / double-cancel
    }
}
