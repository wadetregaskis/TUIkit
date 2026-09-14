//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalExchangeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The startup exchanges, run end to end against a scripted terminal.
///
/// A real exchange writes to stdout, waits on stdin and reads through
/// `Terminal.readSource`. Here the replies come through `readSource`, one
/// staged chunk per read, and `Terminal.exchangeTransport` takes the write and
/// the wait. The queries' own guards (a TTY in raw mode, a host that is not
/// Apple Terminal) are what `askMode` and `askGraphicsSupport` leave out.
@MainActor
@Suite("Terminal startup exchanges")
struct TerminalExchangeTests {

    /// The terminal's side: replies staged as reads, and the requests it was
    /// sent.
    private final class ScriptedTerminal {
        var reads: [[UInt8]] = []
        var requests: [String] = []
        var readCount = 0
    }

    private static let fence = "\u{1B}[24;1R"

    private func makeTerminal(reads: [String]) -> (Terminal, ScriptedTerminal) {
        let terminal = Terminal()
        let script = ScriptedTerminal()
        script.reads = reads.map { Array($0.utf8) }
        terminal.readSource = { buffer in
            script.readCount += 1
            guard !script.reads.isEmpty else { return 0 }
            let chunk = script.reads.removeFirst()
            precondition(chunk.count <= buffer.count, "a staged read larger than the buffer")
            for (index, byte) in chunk.enumerated() { buffer[index] = byte }
            return chunk.count
        }
        terminal.exchangeTransport = .init(
            send: { script.requests.append($0) },
            waitForInput: { _ in true })
        return (terminal, script)
    }

    // MARK: - Through the seams

    @Test("The mode exchange sends DECRQM and reads the DECRPM reply")
    func modeExchangeReadsItsReply() {
        let (terminal, script) = makeTerminal(reads: ["\u{1B}[?2027;2$y" + Self.fence])
        #expect(terminal.askMode(2027, timeout: 5) == .reset)
        #expect(script.requests == [TerminalModeQuery.request(mode: 2027)])
    }

    @Test("A terminal that answers only the fence says nothing about the mode")
    func modeExchangeSilence() {
        let (terminal, _) = makeTerminal(reads: [Self.fence])
        #expect(terminal.askMode(2027, timeout: 5) == nil)
    }

    @Test("The graphics exchange sends its request and reads both acknowledgements")
    func graphicsExchangeReadsItsReplies() {
        let placement = "\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);OK\u{1B}\\"
        let compression = "\u{1B}_Gi=\(TerminalGraphicsQuery.compressionProbeID);OK\u{1B}\\"
        let (terminal, script) = makeTerminal(reads: [placement, compression + Self.fence])
        #expect(terminal.askGraphicsSupport(timeout: 5) == .init(placement: true, compression: true))
        #expect(script.requests == [TerminalGraphicsQuery.request])
    }

    @Test("An exchange stops reading once the fence is in")
    func exchangeStopsAtTheFence() {
        let (terminal, script) = makeTerminal(reads: ["\u{1B}[?2027;1$y", Self.fence, "later"])
        #expect(terminal.askMode(2027, timeout: 5) == .set)
        #expect(script.readCount == 2, "the read after the fence belongs to the input parser")
        #expect(script.reads == [Array("later".utf8)])
    }
}
