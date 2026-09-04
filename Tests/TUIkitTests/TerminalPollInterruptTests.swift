//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalPollInterruptTests.swift
//
//  The three startup probes wait on stdin with `poll`, which POSIX names among
//  the calls `SA_RESTART` does NOT restart: a signal delivered during the wait
//  returns -1/EINTR. Reading that as "the terminal said nothing" abandons the
//  probe with most of its budget unspent.
//
//  Driven over a pipe rather than stdin, through the `on:` seam
//  `Terminal.waitForInput` exposes for exactly this.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A `pthread_t` handed between threads. Neither platform's is `Sendable` (an
/// opaque handle on Darwin, an integer on Linux), and a thread id is exactly
/// the kind of value that is safe to pass and unsafe to touch.
private struct ThreadHandle: @unchecked Sendable {
    let value: pthread_t
}

/// What the waiting thread reports back.
private struct WaitOutcome: Sendable {
    var thread: ThreadHandle?
    var readable: Bool?
    var elapsed: TimeInterval = 0
}

/// Serialized, and it must stay that way: SIGUSR1's default disposition
/// TERMINATES the process, so the window in which the no-op handler is
/// installed must not overlap another test raising one.
@Suite("poll interruption", .serialized)
struct TerminalPollInterruptTests {

    /// Runs the wait on a thread of its own and returns what it saw.
    ///
    /// A thread of its own is not tidiness. Swift Testing runs a test body on a
    /// libdispatch worker, and Darwin's `pthread_kill` refuses one outright —
    /// measured, it returns `ENOTSUP` (45) and delivers nothing — while
    /// libdispatch also masks SIGUSR1 there. A plain `Thread` is a real pthread
    /// that can be signalled, and it unblocks the signal on itself before
    /// waiting.
    ///
    /// - Parameters:
    ///   - descriptor: The descriptor to wait on.
    ///   - deadline: The wait's own deadline.
    ///   - interruptFor: How long to keep signalling the waiting thread. Every
    ///     10 ms, not once: a single shot could land before the wait begins,
    ///     and then the test would be asserting nothing.
    ///   - thenWrite: A descriptor to write one byte to once the signalling is
    ///     over, or `nil` to leave the pipe silent.
    private func waitWhileInterrupted(
        on descriptor: Int32,
        until deadline: Date,
        interruptFor interruptWindow: TimeInterval,
        thenWrite writeEnd: Int32? = nil
    ) -> (readable: Bool, elapsed: TimeInterval) {
        let outcome = Lock(initialState: WaitOutcome())
        let previous = signal(SIGUSR1, { _ in })
        defer { signal(SIGUSR1, previous) }

        Thread.detachNewThread {
            // The signal has to be deliverable on THIS thread; a `pthread_kill`
            // at a thread that has it blocked leaves it pending and interrupts
            // nothing.
            var wanted = sigset_t()
            sigemptyset(&wanted)
            sigaddset(&wanted, SIGUSR1)
            pthread_sigmask(SIG_UNBLOCK, &wanted, nil)

            outcome.withLock { $0.thread = ThreadHandle(value: pthread_self()) }
            let start = Date()
            let readable = Terminal.waitForInput(on: descriptor, until: deadline)
            outcome.withLock {
                $0.elapsed = Date().timeIntervalSince(start)
                $0.readable = readable
            }
        }

        // Wait for the thread to announce itself, then signal it for the window.
        while outcome.withLock({ $0.thread }) == nil { Thread.sleep(forTimeInterval: 0.001) }
        guard let thread = outcome.withLock({ $0.thread }) else { return (false, 0) }
        // The first send is asserted, because a signal that cannot be
        // delivered makes every assertion below vacuous. The rest are not: once
        // the wait has returned the thread exits and `pthread_kill` starts
        // answering ESRCH, which is the expected end of the window, not a fault.
        #expect(
            pthread_kill(thread.value, SIGUSR1) == 0,
            "the signal never reached the waiting thread — the test proves nothing")
        let stopSignalling = Date().addingTimeInterval(interruptWindow)
        while Date() < stopSignalling {
            Thread.sleep(forTimeInterval: 0.01)
            if pthread_kill(thread.value, SIGUSR1) != 0 { break }
        }
        if let writeEnd {
            var byte: UInt8 = 0x41
            #expect(write(writeEnd, &byte, 1) == 1)
        }

        while outcome.withLock({ $0.readable }) == nil { Thread.sleep(forTimeInterval: 0.001) }
        let final = outcome.withLock { $0 }
        return (final.readable ?? false, final.elapsed)
    }

    /// A pipe whose write end stays open for the test's duration, so the read
    /// end blocks rather than reporting `POLLHUP`.
    private func withPipe(_ body: (_ readEnd: Int32, _ writeEnd: Int32) -> Void) {
        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        defer {
            close(ends[0])
            close(ends[1])
        }
        body(ends[0], ends[1])
    }

    @Test("An interrupted wait keeps waiting for its deadline instead of reporting nothing")
    func interruptedWaitRunsItsFullDeadline() {
        withPipe { readEnd, _ in
            // Signals through the first half of the window and nothing ever
            // written, so the only correct answer is `false` AT the deadline.
            // Without the EINTR retry the call returns `false` within ~10 ms —
            // the bug, in one number.
            let (readable, elapsed) = waitWhileInterrupted(
                on: readEnd, until: Date().addingTimeInterval(0.4), interruptFor: 0.2)

            #expect(!readable, "nothing was ever written")
            #expect(
                elapsed >= 0.3,
                "gave up after \(elapsed)s of a 0.4s budget — an EINTR was read as a timeout")
        }
    }

    @Test("An interrupted wait still sees the bytes that arrive after the interruption")
    func interruptedWaitStillSeesLateData() {
        withPipe { readEnd, writeEnd in
            // The reply a real probe is waiting for arrives behind the signal,
            // which is the whole scenario: a SIGWINCH during the handshake.
            let (readable, _) = waitWhileInterrupted(
                on: readEnd, until: Date().addingTimeInterval(2), interruptFor: 0.1,
                thenWrite: writeEnd)

            #expect(readable, "the late byte was lost to the interruption")
        }
    }

    @Test("A wait with data already there returns at once")
    func readyDescriptorReturnsImmediately() {
        withPipe { readEnd, writeEnd in
            var byte: UInt8 = 0x41
            #expect(write(writeEnd, &byte, 1) == 1)

            let start = Date()
            #expect(Terminal.waitForInput(on: readEnd, until: Date().addingTimeInterval(5)))
            #expect(Date().timeIntervalSince(start) < 0.5, "a ready descriptor must not wait")
        }
    }

    @Test("A wait whose deadline has already passed does not poll at all")
    func expiredDeadlineReturnsFalse() {
        withPipe { readEnd, writeEnd in
            // Readable, so a `poll` with a zero timeout would say `true`. The
            // deadline check comes first, which is what keeps a probe that has
            // run out of time from taking one more turn.
            var byte: UInt8 = 0x41
            #expect(write(writeEnd, &byte, 1) == 1)

            #expect(!Terminal.waitForInput(on: readEnd, until: Date().addingTimeInterval(-1)))
        }
    }
}
