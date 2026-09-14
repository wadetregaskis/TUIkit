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

    // MARK: - What is not a reply reaches the input parser

    /// Every event the parser produces in `pumps` calls, nils dropped.
    private func events(_ terminal: Terminal, pumps: Int = 12) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    /// The two exchanges that used to discard what they read, each with a
    /// reply it credits.
    enum Exchange: String, CaseIterable, Sendable {
        case mode, graphics

        var reply: String {
            switch self {
            case .mode: "\u{1B}[?2027;2$y"
            case .graphics: "\u{1B}_Gi=\(TerminalGraphicsQuery.probeID);OK\u{1B}\\"
            }
        }

        /// Runs the exchange, and whether it credited the reply.
        @MainActor
        func run(on terminal: Terminal) -> Bool {
            switch self {
            case .mode: terminal.askMode(2027, timeout: 5) == .reset
            case .graphics: terminal.askGraphicsSupport(timeout: 5).placement
            }
        }
    }

    private static let focusIn = "\u{1B}[I"
    private static let focusOut = "\u{1B}[O"

    /// A terminal can send a focus report the instant `enableRawMode` turns
    /// reporting on, and a user can type while the app starts. Both land on
    /// stdin during whichever exchange is reading it, and both are the input
    /// parser's.
    @Test(
        "A keystroke and a focus report during the exchange reach the parser",
        arguments: Exchange.allCases)
    func interleavedInputReachesTheParser(exchange: Exchange) {
        let (terminal, _) = makeTerminal(
            reads: ["q" + exchange.reply + Self.focusIn + Self.fence])
        #expect(exchange.run(on: terminal), "the reply is still read")
        #expect(
            events(terminal) == [
                .key(KeyEvent(character: "q")), .focusChanged(isFocused: true),
            ])
    }

    @Test(
        "Input split across the exchange's reads still reaches the parser in order",
        arguments: Exchange.allCases)
    func splitInputReachesTheParser(exchange: Exchange) {
        let reply = Array(exchange.reply)
        let half = reply.count / 2
        let (terminal, _) = makeTerminal(reads: [
            Self.focusOut + String(reply[..<half]),
            String(reply[half...]) + "\u{1B}",
            "[A" + Self.focusIn + Self.fence,
        ])
        #expect(exchange.run(on: terminal))
        #expect(
            events(terminal) == [
                .focusChanged(isFocused: false), .key(KeyEvent(key: .up)),
                .focusChanged(isFocused: true),
            ])
    }

    @Test(
        "What arrives behind the fence in the same read reaches the parser",
        arguments: Exchange.allCases)
    func inputBehindTheFenceReachesTheParser(exchange: Exchange) {
        let (terminal, _) = makeTerminal(
            reads: [exchange.reply + Self.fence + Self.focusIn + "x"])
        #expect(exchange.run(on: terminal))
        #expect(
            events(terminal) == [
                .focusChanged(isFocused: true), .key(KeyEvent(character: "x")),
            ])
    }

    @Test("Replies and the fence never reach the parser", arguments: Exchange.allCases)
    func repliesStayWithTheExchange(exchange: Exchange) {
        let (terminal, _) = makeTerminal(reads: [exchange.reply, Self.fence])
        #expect(exchange.run(on: terminal))
        #expect(events(terminal).isEmpty)
        #expect(!terminal.hasPendingInput)
    }

    @Test(
        "A keystroke still reaches the parser when the fence never comes",
        arguments: Exchange.allCases)
    func inputReachesTheParserWithoutAFence(exchange: Exchange) {
        let (terminal, _) = makeTerminal(reads: [exchange.reply + "q"])
        #expect(exchange.run(on: terminal))
        #expect(events(terminal) == [.key(KeyEvent(character: "q"))])
    }

    // MARK: - The split itself

    private static func unconsumed(_ stream: String) -> String {
        let kept = TerminalQueryReplies.unconsumed(
            Array(stream.utf8), isReply: TerminalModeQuery.isReply,
            isFence: TerminalModeQuery.isFence)
        return String(bytes: kept, encoding: .utf8) ?? "<not UTF-8>"
    }

    @Test("Keys, Alt chords and a trailing bare ESC are kept byte for byte")
    func keysAreKeptVerbatim() {
        let reply = "\u{1B}[?2027;1$y"
        let keys = "\u{1B}[A" + reply + "\u{1B}x" + "\u{1B}\u{1B}[B" + "é" + "\u{1B}"
        #expect(Self.unconsumed(keys) == "\u{1B}[A\u{1B}x\u{1B}\u{1B}[Bé\u{1B}")
    }

    @Test("A sequence that is not this exchange's reply is kept, for the parser's own rules")
    func otherSequencesAreKept() {
        let osc = "\u{1B}]11;rgb:0000/0000/0000\u{1B}\\"
        let apc = "\u{1B}_Gi=1;OK\u{07}"
        #expect(Self.unconsumed(osc + apc + Self.fence) == osc + apc)
    }

    @Test("A sequence the bytes cut short is kept, with whatever the timeout left")
    func truncatedSequencesAreKept() {
        #expect(Self.unconsumed("\u{1B}[?2027;1$y" + "\u{1B}[24;") == "\u{1B}[24;")
        #expect(Self.unconsumed("\u{1B}]11;rgb:00") == "\u{1B}]11;rgb:00")
    }

    @Test("A string sequence a new ESC interrupts keeps its prefix, and the fence behind it counts")
    func interruptedStringSequenceKeepsItsPrefix() {
        #expect(Self.unconsumed("\u{1B}_Gi=1;O" + Self.fence + "z") == "\u{1B}_Gi=1;Oz")
    }

    @Test("The mode exchange's replies are DECRPM, and its fence a cursor report")
    func modeRepliesAndFence() {
        #expect(TerminalModeQuery.isReply(Array("\u{1B}[?2027;2$y".utf8)[...]))
        #expect(!TerminalModeQuery.isReply(Array(Self.focusIn.utf8)[...]))
        #expect(TerminalModeQuery.isFence(Array(Self.fence.utf8)[...]))
        #expect(!TerminalModeQuery.isFence(Array("\u{1B}[A".utf8)[...]))
    }

    @Test("The graphics exchange's replies are Kitty acknowledgements, and nothing else")
    func graphicsReplies() {
        #expect(TerminalGraphicsQuery.isReply(Array("\u{1B}_Gi=1;OK\u{1B}\\".utf8)[...]))
        #expect(!TerminalGraphicsQuery.isReply(Array("\u{1B}]11;rgb:0/0/0\u{07}".utf8)[...]))
        #expect(!TerminalGraphicsQuery.isReply(Array(Self.focusIn.utf8)[...]))
        #expect(TerminalGraphicsQuery.isFence(Array(Self.fence.utf8)[...]))
    }
}
