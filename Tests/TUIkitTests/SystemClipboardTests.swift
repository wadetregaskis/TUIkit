//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SystemClipboardTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Drives ``SystemClipboard``'s bounded child I/O against scripted stand-ins
/// for the real helpers, because the failure modes it exists to survive can't
/// be arranged with the genuine clipboard: a helper that exits without
/// reading (xclip with no display), one that stops reading mid-payload
/// (wedged X connection), and one that never closes its stdout. The old
/// implementation blocked forever — or died on SIGPIPE — in exactly these
/// cases, from a synchronous Ctrl+C/V/X on the main actor.
@Suite("System Clipboard child I/O")
struct SystemClipboardTests {
    /// Comfortably past the ~64 KB pipe buffer, so a child that isn't reading
    /// forces the writer into the would-block path.
    private static let bigPayload = Data(repeating: 0x41, count: 1_000_000)

    /// The deadline for exchanges that are supposed to SUCCEED.
    ///
    /// Those tests assert the data path — every byte written, every byte read
    /// back — and not that it happens quickly. `defaultDeadline` (2 s) is the
    /// right bound for a *real* clipboard helper, but using it here makes the
    /// assertion a race against the wall clock: this suite runs alongside 530
    /// others, and on a saturated machine a `/bin/sh` spawn, a pipe exchange
    /// and the reap can exceed 2 s with nothing wrong at all. Measured: these
    /// failed about one run in three, always as `result == nil` a hair past
    /// the deadline (2.156 s against 2 s), and that is what turned CI red on
    /// whichever lane lost the lottery.
    ///
    /// Promptness is still covered, by the deadline tests above: they assert a
    /// timeout *does* happen, and load only makes those more certain, never
    /// less. So the timing assertions live where load helps them, and the
    /// correctness assertions no longer depend on the scheduler.
    private static let generousDeadline: TimeInterval = 60

    /// Wall-clock guard: generous enough for a loaded machine, tight enough
    /// to prove nothing waited on a 30-second child.
    private func expectPrompt(_ start: DispatchTime, within seconds: Double = 5) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        #expect(elapsed < seconds, "bounded I/O must not wait on a wedged child (took \(elapsed)s)")
    }

    @Test("A payload to a child that exits without reading fails cleanly (no SIGPIPE death)")
    func writeToChildThatExitsEarly() {
        let start = DispatchTime.now()
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "exit 0"],
            writing: Self.bigPayload, readsOutput: false
        )
        #expect(result == nil, "an unread payload is a failed copy, reported cleanly")
        expectPrompt(start)
    }

    @Test("A child that stops reading mid-payload is abandoned at the deadline")
    func writeToChildThatStopsReading() {
        let start = DispatchTime.now()
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "sleep 30"],
            writing: Self.bigPayload, readsOutput: false, deadline: 0.3
        )
        #expect(result == nil)
        expectPrompt(start)
    }

    @Test("A child that never closes its stdout is abandoned at the deadline")
    func readFromChildThatHangs() {
        let start = DispatchTime.now()
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "printf hi; sleep 30"],
            writing: nil, readsOutput: true, deadline: 0.3
        )
        #expect(result == nil, "a half-delivered paste is worse than none")
        expectPrompt(start)
    }

    @Test("A well-behaved copy of a large payload succeeds")
    func largeWriteSucceeds() {
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "cat > /dev/null"],
            writing: Self.bigPayload, readsOutput: false, deadline: Self.generousDeadline
        )
        #expect(result != nil)
    }

    @Test("A well-behaved paste of a large payload succeeds")
    func largeReadSucceeds() {
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "head -c 200000 /dev/zero"],
            writing: nil, readsOutput: true, deadline: Self.generousDeadline
        )
        #expect(result?.count == 200_000)
    }

    /// Small enough to fit both pipe buffers: the exchange writes everything
    /// before reading (real clipboard exchanges are one-directional, so the
    /// sequencing never matters there).
    @Test("A round-trip through cat preserves the bytes")
    func roundTrip() {
        let payload = Data("hello clipboard ✂️".utf8)
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "cat"],
            writing: payload, readsOutput: true, deadline: Self.generousDeadline
        )
        #expect(result == payload)
    }

    @Test("A missing tool reports failure instead of throwing")
    func missingTool() {
        let result = SystemClipboard.run(
            tool: "/nonexistent/definitely-not-a-clipboard", arguments: [],
            writing: Data("x".utf8), readsOutput: false
        )
        #expect(result == nil)
    }

    @Test("A non-zero exit reports failure")
    func failingTool() {
        let result = SystemClipboard.run(
            tool: "/bin/sh", arguments: ["-c", "exit 3"],
            writing: nil, readsOutput: true
        )
        #expect(result == nil)
    }
}
