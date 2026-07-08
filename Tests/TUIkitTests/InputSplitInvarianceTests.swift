//  🖥️ TUIKit — Terminal UI Kit for Swift
//  InputSplitInvarianceTests.swift
//
//  Property test over the terminal input parser: every escape sequence,
//  mouse report, paste bracket and multi-byte UTF-8 character must decode
//  to the same events regardless of where a read() boundary lands. This is
//  the class of bug behind the historical stray-'[' page jumps and leaked
//  'M' terminators; the whole corpus is checked at every split point.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Input split-read invariance")
struct InputSplitInvarianceTests {
    private final class ByteBox { var bytes: [UInt8] = [] }

    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    /// Drains events: pumps readEvent until `quietLimit` consecutive nils.
    private func drain(_ terminal: Terminal, quietLimit: Int = 8) -> [TerminalInput] {
        var events: [TerminalInput] = []
        var quiet = 0
        var calls = 0
        while quiet < quietLimit && calls < 60 {
            calls += 1
            if let event = terminal.readEvent() {
                events.append(event)
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return events
    }

    @Test("Sequences split at every byte boundary decode identically")
    func splitInvariance() {
        let esc: [UInt8] = [0x1B]
        let sequences: [(String, [UInt8])] = [
            ("up", esc + Array("[A".utf8)),
            ("down", esc + Array("[B".utf8)),
            ("shift+right", esc + Array("[1;2C".utf8)),
            ("ctrl+left", esc + Array("[1;5D".utf8)),
            ("home", esc + Array("[H".utf8)),
            ("pgdn", esc + Array("[6~".utf8)),
            ("delete", esc + Array("[3~".utf8)),
            ("F1-SS3", esc + Array("OP".utf8)),
            ("mouse-press", esc + Array("[<0;10;5M".utf8)),
            ("mouse-release", esc + Array("[<0;10;5m".utf8)),
            ("mouse-wheel", esc + Array("[<64;3;4M".utf8)),
            ("focus-in", esc + Array("[I".utf8)),
            ("paste", esc + Array("[200~hi".utf8) + esc + Array("[201~".utf8)),
            ("ascii", Array("abc".utf8)),
            ("utf8-2byte", Array("é".utf8)),
            ("utf8-3byte", Array("你".utf8)),
            ("utf8-4byte", Array("🎉".utf8)),
            ("text-then-arrow", Array("a".utf8) + esc + Array("[B".utf8)),
            ("arrow-then-text", esc + Array("[B".utf8) + Array("b".utf8)),
            ("two-arrows", esc + Array("[A".utf8) + esc + Array("[B".utf8)),
        ]

        var reports: [String] = []
        for (name, bytes) in sequences {
            let (wholeTerminal, wholeStage) = makeTerminal()
            wholeStage(bytes)
            let whole = drain(wholeTerminal)

            for splitAt in 1..<bytes.count {
                let (terminal, stage) = makeTerminal()
                stage(Array(bytes[..<splitAt]))
                var events: [TerminalInput] = []
                // One pump between the reads models the mid-sequence boundary.
                if let event = terminal.readEvent() { events.append(event) }
                stage(Array(bytes[splitAt...]))
                events.append(contentsOf: drain(terminal))

                if events != whole {
                    reports.append(
                        "\(name) split@\(splitAt): whole=\(whole) split=\(events)")
                }
            }
        }

        if !reports.isEmpty {
            print("=== SPLIT DIVERGENCES (\(reports.count)) ===")
            for report in reports.prefix(25) { print(report) }
        }
        #expect(reports.isEmpty, "\(reports.count) split divergences — see printed report")
    }
}
