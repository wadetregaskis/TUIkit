//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorStartupTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The startup colour exchange: which request a host is sent, how long it is
/// waited for, what it hands back to the input parser, and what it publishes.
///
/// Run through `Terminal.askColors(isTmux:timeout:)`, the exchange without
/// its guard (a TTY in raw mode, which a test process does not have), with a
/// scripted terminal behind `readSource` and `exchangeTransport`, as
/// TerminalExchangeTests does for the other startup exchanges. The wiring
/// into the app, before the first frame, is checked by
/// `Tools/Smoke/colour_query_smoke.py`.
@MainActor
@Suite("Terminal colour startup exchange")
struct TerminalColorStartupTests {

    typealias RGB = TerminalColors.RGB

    private static let fence = "\u{1B}[0n"
    private static let focusIn = "\u{1B}[I"

    /// Ghostty 1.3.1's default configuration, as it answered on 2026-09-14.
    private static let ghosttyForeground = RGB(red: 255, green: 255, blue: 255)
    private static let ghosttyBackground = RGB(red: 40, green: 44, blue: 52)
    private static let ghosttySlots = [
        RGB(red: 29, green: 31, blue: 33), RGB(red: 204, green: 102, blue: 102),
        RGB(red: 181, green: 189, blue: 104), RGB(red: 240, green: 198, blue: 116),
        RGB(red: 129, green: 162, blue: 190), RGB(red: 178, green: 148, blue: 187),
        RGB(red: 138, green: 190, blue: 183), RGB(red: 197, green: 200, blue: 198),
        RGB(red: 102, green: 102, blue: 102), RGB(red: 213, green: 78, blue: 83),
        RGB(red: 185, green: 202, blue: 74), RGB(red: 231, green: 197, blue: 71),
        RGB(red: 122, green: 166, blue: 218), RGB(red: 195, green: 151, blue: 216),
        RGB(red: 112, green: 192, blue: 177), RGB(red: 234, green: 234, blue: 234),
    ]

    /// An XParseColor spec as the measured hosts spelled it: `rgb:`, each
    /// channel as four hex digits, its byte repeated.
    private static func spec(_ rgb: RGB) -> String {
        let channels = [rgb.red, rgb.green, rgb.blue].map { channel in
            let digits = String(channel, radix: 16)
            let byte = digits.count == 1 ? "0" + digits : digits
            return byte + byte
        }
        return "rgb:" + channels.joined(separator: "/")
    }

    /// A reply ending in ST, as Ghostty mirrors the query's terminator.
    private static func reply(_ code: String, _ rgb: RGB) -> String {
        "\u{1B}]\(code);\(spec(rgb))\u{1B}\\"
    }

    private static var ghosttyColourReplies: String {
        reply("10", ghosttyForeground) + reply("11", ghosttyBackground)
    }

    private static var ghosttySlotReplies: String {
        ghosttySlots.enumerated().map { reply("4;\($0.offset)", $0.element) }.joined()
    }

    private static var ghosttyColours: TerminalColors {
        TerminalColors(
            foreground: ghosttyForeground, background: ghosttyBackground,
            slots: TerminalColors.Slots(ghosttySlots), prefersDark: true)
    }

    // MARK: - A scripted terminal

    /// The terminal's side: replies staged as reads, the requests it was sent,
    /// and the deadlines the exchange waited against.
    private final class ScriptedTerminal {
        var reads: [[UInt8]] = []
        var requests: [String] = []
        var deadlines: [Date] = []
        var readCount = 0
    }

    /// A terminal whose staged reads are all it will ever send: once they are
    /// gone, the wait for input reports the deadline passed, as a terminal
    /// that never answers the fence does.
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
            waitForInput: { deadline in
                script.deadlines.append(deadline)
                return !script.reads.isEmpty
            })
        return (terminal, script)
    }

    private func events(_ terminal: Terminal, pumps: Int = 12) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    // MARK: - The request

    @Test("A native host is sent the whole request: both colours and the sixteen slots")
    func nativeHostRequest() {
        let (terminal, script) = makeTerminal(reads: [Self.fence])
        _ = terminal.askColors(isTmux: false)
        #expect(script.requests == [TerminalColorQuery.nativeRequest])
    }

    /// tmux forwards OSC 4 to one client and holds the fence about half a
    /// second when that client does not answer (measured, tmux 3.7c).
    @Test("Under tmux only the two colours are asked, and no slot")
    func tmuxRequest() {
        let (terminal, script) = makeTerminal(reads: [Self.fence])
        _ = terminal.askColors(isTmux: true)
        #expect(script.requests == [TerminalColorQuery.tmuxStartupRequest])
        #expect(script.requests.allSatisfy { !$0.contains("\u{1B}]4;") })
    }

    @Test("The exchange waits half a second for the fence, and no longer")
    func startupTimeout() {
        #expect(TerminalColorQuery.startupTimeout == 0.5)
        let (terminal, script) = makeTerminal(reads: [])
        let start = Date()
        _ = terminal.askColors(isTmux: false)
        let waited = script.deadlines.map { $0.timeIntervalSince(start) }
        #expect(!waited.isEmpty)
        #expect(waited.allSatisfy { (0.45...0.75).contains($0) }, "deadlines \(waited)")
    }

    // MARK: - What is published

    @Test("Ghostty's whole answer publishes both colours, all sixteen slots, and dark")
    func answeringHostPublishes() {
        let (terminal, script) = makeTerminal(reads: [
            Self.ghosttyColourReplies, Self.ghosttySlotReplies + Self.fence, "later",
        ])
        let report = terminal.askColors(isTmux: false)
        #expect(TerminalColorQuery.colorsToPublish(report, environment: [:]) == Self.ghosttyColours)
        #expect(script.readCount == 2, "the read after the fence belongs to the input parser")
        #expect(!terminal.hasPendingInput, "replies and the fence are not handed back")
    }

    @Test("Under tmux the two colours are published, and the slots stay unknown")
    func tmuxHostPublishesColoursOnly() {
        let (terminal, _) = makeTerminal(reads: [Self.ghosttyColourReplies + Self.fence])
        let report = terminal.askColors(isTmux: true)
        #expect(
            TerminalColorQuery.colorsToPublish(report, environment: ["TMUX": "/tmp/tmux-501/default,1,0"])
                == TerminalColors(
                    foreground: Self.ghosttyForeground, background: Self.ghosttyBackground, prefersDark: true))
    }

    /// GNU screen 4.00.03 and every other silent host answer the fence alone.
    @Test("A terminal that answers only the fence publishes nothing")
    func silenceWithAFencePublishesNothing() {
        let (terminal, _) = makeTerminal(reads: [Self.fence])
        let report = terminal.askColors(isTmux: false)
        #expect(TerminalColorQuery.colorsToPublish(report, environment: [:]) == nil)
    }

    @Test("A terminal that answers nothing at all, not even the fence, publishes nothing")
    func silenceWithoutAFencePublishesNothing() {
        let (terminal, _) = makeTerminal(reads: [])
        let report = terminal.askColors(isTmux: false)
        #expect(TerminalColorQuery.colorsToPublish(report, environment: [:]) == nil)
    }

    @Test("On a silent terminal, a COLORFGBG hint is still published, and no colour")
    func silenceKeepsTheEnvironmentHint() {
        let (terminal, _) = makeTerminal(reads: [Self.fence])
        let report = terminal.askColors(isTmux: false)
        #expect(
            TerminalColorQuery.colorsToPublish(report, environment: ["COLORFGBG": "0;15"])
                == TerminalColors(prefersDark: false))
    }

    @Test("When the fence never comes, the replies that arrived before the deadline are kept")
    func fenceTimeoutKeepsWhatArrived() {
        let (terminal, _) = makeTerminal(reads: [
            Self.reply("10", Self.ghosttyForeground), Self.reply("11", Self.ghosttyBackground),
        ])
        let report = terminal.askColors(isTmux: false)
        #expect(!report.sawStatusFence)
        #expect(
            TerminalColorQuery.colorsToPublish(report, environment: [:])
                == TerminalColors(
                    foreground: Self.ghosttyForeground, background: Self.ghosttyBackground, prefersDark: true))
    }

    @Test("Slots cut off by the deadline are no slots, and the colours before them are kept")
    func fenceTimeoutMidTable() {
        let partial = Self.ghosttySlots.prefix(15).enumerated()
            .map { Self.reply("4;\($0.offset)", $0.element) }.joined()
        let (terminal, _) = makeTerminal(reads: [Self.ghosttyColourReplies, partial])
        let report = terminal.askColors(isTmux: false)
        let published = TerminalColorQuery.colorsToPublish(report, environment: [:])
        #expect(published?.slots == nil)
        #expect(published?.background == Self.ghosttyBackground)
    }

    // MARK: - What is handed back

    @Test("A keystroke and a focus report typed during the exchange reach the app, around the replies")
    func inputDuringTheExchangeReachesTheApp() {
        let (terminal, script) = makeTerminal(reads: [
            "q" + Self.reply("10", Self.ghosttyForeground),
            Self.focusIn + Self.reply("11", Self.ghosttyBackground) + Self.ghosttySlotReplies,
            Self.fence + "j",
        ])
        let report = terminal.askColors(isTmux: false)
        #expect(TerminalColorQuery.colorsToPublish(report, environment: [:]) == Self.ghosttyColours)
        // The exchange took every byte, so what the parser reads next is only
        // what the exchange handed back.
        #expect(script.reads.isEmpty, "the exchange read all three reads")
        #expect(
            events(terminal) == [
                .key(KeyEvent(character: "q")), .focusChanged(isFocused: true), .key(KeyEvent(character: "j")),
            ])
    }
}
