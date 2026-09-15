//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorQueryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The colour query's requests, its reply parsers, and the pure resolution of
/// what a terminal said.
///
/// The exchange-level tests here run the pieces through
/// `Terminal.fencedExchange` and the hand-back, with a scripted terminal
/// behind `readSource` and `exchangeTransport`, as TerminalExchangeTests does
/// for the other startup exchanges. The startup exchange that asks these
/// questions is TerminalColorStartupTests'.
@MainActor
@Suite("Terminal colour query")
struct TerminalColorQueryTests {

    typealias RGB = TerminalColors.RGB

    private static let bel = "\u{07}"
    private static let st = "\u{1B}\\"
    private static let fence = "\u{1B}[0n"
    private static let focusIn = "\u{1B}[I"

    private static func bytes(_ string: String) -> [UInt8] { Array(string.utf8) }

    private static func parse(_ string: String) -> TerminalColorReport {
        TerminalColorQuery.parse(bytes(string))
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies spelled
    /// them on 2026-09-14 (four digits per channel, BEL-terminated).
    private static let appleTerminalSlotSpecs = [
        "0000/0000/0000", "9999/0000/0000", "0000/a666/0000", "9999/9999/0000",
        "0000/0000/b333", "b333/0000/b333", "0000/a666/b333", "bfff/bfff/bfff",
        "6666/6666/6666", "e666/0000/0000", "0000/d999/0000", "e666/e666/0000",
        "0000/0000/ffff", "e666/0000/e666", "0000/e666/e666", "e666/e666/e666",
    ]

    /// The same sixteen, as the probe scaled them to eight bits.
    private static let appleTerminalSlots = [
        RGB(red: 0, green: 0, blue: 0), RGB(red: 153, green: 0, blue: 0),
        RGB(red: 0, green: 166, blue: 0), RGB(red: 153, green: 153, blue: 0),
        RGB(red: 0, green: 0, blue: 179), RGB(red: 179, green: 0, blue: 179),
        RGB(red: 0, green: 166, blue: 179), RGB(red: 191, green: 191, blue: 191),
        RGB(red: 102, green: 102, blue: 102), RGB(red: 230, green: 0, blue: 0),
        RGB(red: 0, green: 217, blue: 0), RGB(red: 230, green: 230, blue: 0),
        RGB(red: 0, green: 0, blue: 255), RGB(red: 230, green: 0, blue: 230),
        RGB(red: 0, green: 230, blue: 230), RGB(red: 230, green: 230, blue: 230),
    ]

    private static func slotReplies(_ indices: some Sequence<Int>, terminator: String = bel) -> String {
        indices.map { "\u{1B}]4;\($0);rgb:\(appleTerminalSlotSpecs[$0])\(terminator)" }.joined()
    }

    // MARK: - Requests

    @Test("The native request asks fg, bg and each of the sixteen slots on its own, then the status fence")
    func nativeRequest() {
        let slots = (0..<16).map { "\u{1B}]4;\($0);?\u{1B}\\" }.joined()
        #expect(
            TerminalColorQuery.nativeRequest
                == "\u{1B}]10;?\u{1B}\\" + "\u{1B}]11;?\u{1B}\\" + slots + "\u{1B}[5n")
        #expect(TerminalColorQuery.nativeRequest.utf8.count == 170)
    }

    @Test("The tmux startup request asks only fg and bg, then the status fence")
    func tmuxStartupRequest() {
        #expect(
            TerminalColorQuery.tmuxStartupRequest
                == "\u{1B}]10;?\u{1B}\\\u{1B}]11;?\u{1B}\\\u{1B}[5n")
    }

    @Test("The slots request asks the sixteen slots one query each, then the status fence")
    func slotsRequest() {
        let slots = (0..<16).map { "\u{1B}]4;\($0);?\u{1B}\\" }.joined()
        #expect(TerminalColorQuery.slotsRequest == slots + "\u{1B}[5n")
    }

    // MARK: - The status fence

    @Test("CSI 0 n is the status fence, and nothing else is")
    func statusFence() {
        #expect(TerminalColorQuery.sawStatusFence(Self.bytes(Self.fence)))
        #expect(TerminalColorQuery.sawStatusFence(Self.bytes("q\u{1B}]11;rgb:0/0/0\u{07}\u{1B}[0n")))
        #expect(!TerminalColorQuery.sawStatusFence(Self.bytes("\u{1B}[0")), "its final byte is still coming")
        #expect(!TerminalColorQuery.sawStatusFence(Self.bytes("\u{1B}[24;1R")), "a cursor report is another fence")
        #expect(!TerminalColorQuery.sawStatusFence(Self.bytes("\u{1B}[?997;1n")))
        #expect(!TerminalColorQuery.sawStatusFence(Self.bytes("\u{1B}[3n")))
        #expect(!TerminalColorQuery.sawStatusFence(Self.bytes("0n")))
        #expect(!TerminalColorQuery.sawStatusFence([]))
        #expect(TerminalColorQuery.isStatusFence(Self.bytes(Self.fence)[...]))
        #expect(!TerminalColorQuery.isStatusFence(Self.bytes("\u{1B}[24;1R")[...]))
    }

    @Test("A terminal that answers only the fence reports nothing, and resolves to unknown")
    func fenceOnly() {
        let report = Self.parse(Self.fence)
        var expected = TerminalColorReport()
        expected.sawStatusFence = true
        #expect(report == expected)
        #expect(TerminalColorQuery.resolve(report, environment: [:]) == .unknown)
    }

    // MARK: - Colour specs

    @Test(
        "Each channel may be one to four hex digits, scaled to eight bits",
        arguments: [
            ("f", 255), ("8", 136), ("0", 0),
            ("ff", 255), ("80", 128), ("28", 40),
            ("fff", 255), ("800", 128),
            ("ffff", 255), ("8000", 128), ("2828", 40), ("0000", 0),
            // Scaled with rounding, not the high byte: 0x18f1 is 24.84 of 255.
            ("18f1", 25), ("FFFF", 255), ("bFfF", 191),
        ])
    func digitWidths(digits: String, expected: Int) {
        let value = UInt8(expected)
        let report = Self.parse("\u{1B}]11;rgb:\(digits)/\(digits)/\(digits)\u{1B}\\")
        #expect(report.background == RGB(red: value, green: value, blue: value))
    }

    @Test("Channels of different widths in one spec are each scaled on their own")
    func mixedWidths() {
        #expect(Self.parse("\u{1B}]10;rgb:f/80/0000\u{07}").foreground == RGB(red: 255, green: 128, blue: 0))
    }

    @Test("An rgba spec reads its colour and ignores its alpha")
    func rgbaSpec() {
        let report = Self.parse("\u{1B}]11;rgba:ffff/0000/8000/0000\u{1B}\\")
        #expect(report.background == RGB(red: 255, green: 0, blue: 128))
    }

    @Test(
        "A malformed or overlong spec reports nothing, and is still this exchange's reply",
        arguments: [
            "rgb:fffff/ffff/ffff",  // five digits
            "rgb:ffff/ffff",  // two channels
            "rgb:ffff/ffff/ffff/ffff",  // four channels without the a
            "rgba:ffff/ffff/ffff",  // rgba with three
            "rgb:gg/00/00",  // not hex
            "rgb:/00/00",  // an empty channel
            "rgb:00/00/00/",  // a trailing separator
            "rgb:00/00/00;extra",
            "RGB:00/00/00",
            "#000000",
            "?",
            "",
        ])
    func malformedSpec(spec: String) {
        for code in ["10", "11"] {
            let reply = "\u{1B}]\(code);\(spec)\u{1B}\\"
            #expect(Self.parse(reply) == TerminalColorReport(), "\(reply.debugDescription)")
            #expect(TerminalColorQuery.isReply(Self.bytes(reply)[...]))
        }
        let slot = "\u{1B}]4;1;\(spec)\u{07}"
        #expect(Self.parse(slot) == TerminalColorReport(), "\(slot.debugDescription)")
        #expect(TerminalColorQuery.isReply(Self.bytes(slot)[...]))
    }

    // MARK: - Terminators

    /// Apple Terminal answers an ST query with BEL, and iTerm2 answers a BEL
    /// query with ST, so a parser takes both whatever it sent.
    @Test("Every reply is read with either terminator", arguments: ["\u{07}", "\u{1B}\\"])
    func terminators(terminator: String) {
        let report = Self.parse(
            "\u{1B}]10;rgb:0000/0000/0000\(terminator)"
                + "\u{1B}]11;rgb:ffff/ffff/ffff\(terminator)"
                + Self.slotReplies(0..<16, terminator: terminator) + Self.fence)
        #expect(report.foreground == RGB(red: 0, green: 0, blue: 0))
        #expect(report.background == RGB(red: 255, green: 255, blue: 255))
        #expect(report.slots == Self.appleTerminalSlots)
        #expect(report.sawStatusFence)
    }

    @Test("iTerm2's slot 0, spelled with ST, reads as the probe recorded it")
    func iTerm2Slot() {
        let report = Self.parse("\u{1B}]4;0;rgb:150b/18f1/1da2\u{1B}\\")
        #expect(report.slots[0] == RGB(red: 21, green: 25, blue: 30))
        #expect(report.slots[1...].allSatisfy { $0 == nil })
    }

    // MARK: - Slot indices

    @Test(
        "A slot index outside 0...15, or not a number, reports nothing",
        arguments: ["16", "255", "99999999999999999999999", "-1", "", "1a", "?"])
    func slotIndexOutOfRange(index: String) {
        let reply = "\u{1B}]4;\(index);rgb:ffff/ffff/ffff\u{07}"
        #expect(Self.parse(reply) == TerminalColorReport())
        #expect(TerminalColorQuery.isReply(Self.bytes(reply)[...]))
    }

    @Test("Slot 15, the last one asked for, is in range")
    func lastSlotInRange() {
        #expect(Self.parse(Self.slotReplies([15])).slots[15] == Self.appleTerminalSlots[15])
    }

    // MARK: - The appearance report

    @Test("CSI ? 997 ; 1 n reports dark, 2 light, and any other value nothing")
    func appearanceReport() {
        #expect(Self.parse("\u{1B}[?997;1n").appearance == .dark)
        #expect(Self.parse("\u{1B}[?997;2n").appearance == .light)
        for other in ["\u{1B}[?997;3n", "\u{1B}[?997;n", "\u{1B}[?997;99999999999999999999n"] {
            #expect(Self.parse(other) == TerminalColorReport())
            #expect(TerminalColorQuery.isReply(Self.bytes(other)[...]))
        }
        #expect(!TerminalColorQuery.isReply(Self.bytes("\u{1B}[?996n")[...]))
        #expect(!TerminalColorQuery.isReply(Self.bytes("\u{1B}[?997;1$y")[...]))
    }

    // MARK: - Replies and everything else

    @Test("Replies are OSC 10, 11 and 4 and the 997 report; keys, focus reports and other OSCs are not")
    func whatIsAReply() {
        for reply in ["\u{1B}]10;rgb:0/0/0\u{07}", "\u{1B}]11;?\u{1B}\\", "\u{1B}]4;3;rgb:0/0/0\u{07}"] {
            #expect(TerminalColorQuery.isReply(Self.bytes(reply)[...]), "\(reply.debugDescription)")
        }
        for other in [
            Self.focusIn, "\u{1B}[A", Self.fence, "\u{1B}]104;1\u{07}", "\u{1B}]12;rgb:0/0/0\u{07}",
            "\u{1B}]8;;https://example.com\u{1B}\\", "\u{1B}_Gi=1;OK\u{1B}\\",
        ] {
            #expect(!TerminalColorQuery.isReply(Self.bytes(other)[...]), "\(other.debugDescription)")
        }
    }

    @Test("A reply behind the fence is not recorded, since the hand-back leaves it for the input parser")
    func replyBehindTheFence() {
        let report = Self.parse(Self.fence + "\u{1B}]11;rgb:ffff/ffff/ffff\u{07}")
        #expect(report.sawStatusFence)
        #expect(report.background == nil)
    }

    @Test("A later reply for the same colour replaces an earlier one; a malformed one does not")
    func laterReplyWins() {
        let report = Self.parse(
            "\u{1B}]11;rgb:0000/0000/0000\u{07}\u{1B}]11;rgb:ffff/ffff/ffff\u{07}\u{1B}]11;rgb:zz/zz/zz\u{07}")
        #expect(report.background == RGB(red: 255, green: 255, blue: 255))
    }

    // MARK: - Through the exchange

    private final class ScriptedTerminal {
        var reads: [[UInt8]] = []
        var requests: [String] = []
        var readCount = 0
    }

    private func makeTerminal(reads: [String]) -> (Terminal, ScriptedTerminal) {
        let terminal = Terminal()
        let script = ScriptedTerminal()
        script.reads = reads.map(Self.bytes)
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

    /// Runs the exchange as a caller will: read to the status fence, hand
    /// back what is not a reply, parse what was read.
    private func exchange(_ terminal: Terminal, request: String) -> TerminalColorReport {
        let collected = terminal.fencedExchange(
            request: request, timeout: 5, sawFence: TerminalColorQuery.sawStatusFence)
        terminal.handBackUnconsumed(
            from: collected, isReply: TerminalColorQuery.isReply,
            isFence: TerminalColorQuery.isStatusFence)
        return TerminalColorQuery.parse(collected)
    }

    private func events(_ terminal: Terminal, pumps: Int = 12) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    @Test("A reply and the fence split across reads are read whole, and the read ends at the fence")
    func splitRead() {
        let (terminal, script) = makeTerminal(reads: [
            "\u{1B}]10;rgb:0000/00", "00/0000\u{07}\u{1B}]11;rgb:ffff/ffff/ffff\u{1B}",
            "\\" + Self.slotReplies(0..<16) + "\u{1B}[0", "n", "later",
        ])
        let report = exchange(terminal, request: TerminalColorQuery.nativeRequest)
        #expect(script.requests == [TerminalColorQuery.nativeRequest])
        #expect(script.readCount == 4, "the read after the fence belongs to the input parser")
        #expect(report.foreground == RGB(red: 0, green: 0, blue: 0))
        #expect(report.background == RGB(red: 255, green: 255, blue: 255))
        #expect(report.slots == Self.appleTerminalSlots)
        #expect(script.reads == [Self.bytes("later")])
        #expect(!terminal.hasPendingInput, "replies and the fence are not handed back")
    }

    @Test("A keystroke and a focus report interleaved with the replies are left for the input parser")
    func interleavedInputIsLeftUnconsumed() {
        let stream =
            "q\u{1B}]10;rgb:0000/0000/0000\u{07}" + Self.focusIn
            + "\u{1B}[?997;2n\u{1B}]11;rgb:ffff/ffff/ffff\u{07}" + Self.fence
        let kept = TerminalQueryReplies.unconsumed(
            Self.bytes(stream), isReply: TerminalColorQuery.isReply,
            isFence: TerminalColorQuery.isStatusFence)
        #expect(kept == Self.bytes("q" + Self.focusIn))

        let (terminal, _) = makeTerminal(reads: [stream])
        let report = exchange(terminal, request: TerminalColorQuery.tmuxStartupRequest)
        #expect(report.foreground == RGB(red: 0, green: 0, blue: 0))
        #expect(report.background == RGB(red: 255, green: 255, blue: 255))
        #expect(report.appearance == .light)
        #expect(
            events(terminal) == [
                .key(KeyEvent(character: "q")), .focusChanged(isFocused: true),
            ])
    }

    // MARK: - Resolution

    private static let black = RGB(red: 0, green: 0, blue: 0)
    private static let white = RGB(red: 255, green: 255, blue: 255)

    /// No `TMUX`, no `STY`, no `COLORFGBG`: a native host that sets nothing.
    private static let bareEnvironment: [String: String] = [:]

    private static func report(
        foreground: RGB? = nil, background: RGB? = nil, slots: Int = 0,
        appearance: TerminalColorReport.Appearance? = nil
    ) -> TerminalColorReport {
        var report = TerminalColorReport()
        report.foreground = foreground
        report.background = background
        for index in 0..<slots { report.slots[index] = appleTerminalSlots[index] }
        report.appearance = appearance
        return report
    }

    private static func resolve(
        _ report: TerminalColorReport, environment: [String: String] = bareEnvironment
    ) -> TerminalColors {
        TerminalColorQuery.resolve(report, environment: environment)
    }

    @Test("A terminal that answered nothing, in a bare environment, resolves to unknown")
    func resolveNothing() {
        #expect(Self.resolve(TerminalColorReport()) == .unknown)
    }

    @Test("Both colours answered are both kept, and the background decides prefersDark")
    func resolveBothReported() {
        let dark = RGB(red: 40, green: 44, blue: 52)
        let pale = RGB(red: 171, green: 178, blue: 191)
        #expect(
            Self.resolve(Self.report(foreground: pale, background: dark))
                == TerminalColors(foreground: pale, background: dark, prefersDark: true))
    }

    @Test("Only the foreground answered leaves the background, and prefersDark, unknown")
    func resolveForegroundOnly() {
        for foreground in [Self.black, RGB(red: 230, green: 230, blue: 230)] {
            #expect(Self.resolve(Self.report(foreground: foreground)) == TerminalColors(foreground: foreground))
        }
    }

    @Test(
        "Only the background answered leaves the foreground unknown; the background decides prefersDark",
        arguments: [
            (TerminalColors.RGB(red: 40, green: 44, blue: 52), true),
            (TerminalColors.RGB(red: 0, green: 0, blue: 0), true),
            (TerminalColors.RGB(red: 255, green: 255, blue: 255), false),
            // Either side of the luminance where black and white contrast
            // equally (about 0.179): grey 117 is dark, 118 light.
            (TerminalColors.RGB(red: 117, green: 117, blue: 117), true),
            (TerminalColors.RGB(red: 118, green: 118, blue: 118), false),
        ])
    func resolveBackgroundOnly(background: RGB, prefersDark: Bool) {
        #expect(
            Self.resolve(Self.report(background: background))
                == TerminalColors(background: background, prefersDark: prefersDark))
    }

    @Test("A 997 report alone decides prefersDark, and fills in no colour")
    func resolveAppearanceAlone() {
        #expect(Self.resolve(Self.report(appearance: .dark)) == TerminalColors(prefersDark: true))
        #expect(Self.resolve(Self.report(appearance: .light)) == TerminalColors(prefersDark: false))
    }

    /// Ghostty 1.3.1 answered OSC 11 with 40, 44, 52, and `997;2`, measured.
    @Test("The reported background outranks a 997 report that contradicts it")
    func resolveBackgroundOutranksAppearance() {
        let ghostty = Self.report(
            foreground: Self.white, background: RGB(red: 40, green: 44, blue: 52), appearance: .light)
        #expect(Self.resolve(ghostty).prefersDark == true)
        let lightPage = Self.report(background: Self.white, appearance: .dark)
        #expect(Self.resolve(lightPage).prefersDark == false)
    }

    @Test(
        "COLORFGBG alone decides prefersDark by its last field",
        arguments: [
            ("0;15", false), ("15;0", true), ("7;8", true), ("0;7", false), ("15;default;0", true),
            ("0;6", true), ("0;9", false),
        ])
    func resolveColorFgBg(value: String, prefersDark: Bool) {
        #expect(Self.resolve(Self.report(), environment: ["COLORFGBG": value]) == TerminalColors(prefersDark: prefersDark))
    }

    @Test(
        "A COLORFGBG whose last field is not a slot number says nothing",
        arguments: ["", "0", "0;", "0;default", "0;16", "0;-1", "0;x", "0;15;"])
    func resolveUnreadableColorFgBg(value: String) {
        #expect(Self.resolve(Self.report(), environment: ["COLORFGBG": value]) == .unknown)
    }

    @Test("A 997 report outranks COLORFGBG")
    func resolveAppearanceOutranksColorFgBg() {
        #expect(Self.resolve(Self.report(appearance: .dark), environment: ["COLORFGBG": "0;15"]).prefersDark == true)
        #expect(Self.resolve(Self.report(appearance: .light), environment: ["COLORFGBG": "15;0"]).prefersDark == false)
    }

    @Test("The reported background outranks COLORFGBG")
    func resolveBackgroundOutranksColorFgBg() {
        #expect(Self.resolve(Self.report(background: Self.black), environment: ["COLORFGBG": "0;15"]).prefersDark == true)
    }

    @Test(
        "COLORFGBG is ignored inside tmux or screen",
        arguments: [
            ["COLORFGBG": "0;15", "TMUX": "/private/tmp/tmux-501/default,1234,0"],
            ["COLORFGBG": "0;15", "TERM_PROGRAM": "tmux"],
            ["COLORFGBG": "0;15", "STY": "1234.ttys001.host"],
        ])
    func resolveColorFgBgIgnoredUnderMultiplexers(environment: [String: String]) {
        #expect(Self.resolve(Self.report(), environment: environment) == .unknown)
    }

    @Test("An empty TMUX or STY does not count as a multiplexer")
    func resolveEmptyMultiplexerVariables() {
        #expect(
            Self.resolve(Self.report(), environment: ["COLORFGBG": "0;15", "TMUX": "", "STY": ""])
                == TerminalColors(prefersDark: false))
    }

    @Test("All sixteen slots are kept")
    func resolveAllSlots() {
        let resolved = Self.resolve(Self.report(foreground: Self.black, background: Self.white, slots: 16))
        #expect(resolved.slots == TerminalColors.Slots(Self.appleTerminalSlots))
    }

    @Test("Fifteen of sixteen slots are no slots", arguments: [0, 1, 15])
    func resolvePartialSlots(missing: Int) {
        var report = Self.report(foreground: Self.black, background: Self.white, slots: 16)
        report.slots[missing] = nil
        let resolved = Self.resolve(report)
        #expect(resolved.slots == nil)
        #expect(resolved.foreground == Self.black && resolved.background == Self.white)
    }

    @Test("Slots answered without either colour are kept, and fill in neither colour")
    func resolveSlotsWithoutColours() {
        #expect(
            Self.resolve(Self.report(slots: 16))
                == TerminalColors(slots: TerminalColors.Slots(Self.appleTerminalSlots)))
    }

    @Test("Apple Terminal's whole native answer resolves to what it reported, light")
    func resolveAppleTerminal() {
        let answer =
            "\u{1B}]10;rgb:0000/0000/0000\u{07}\u{1B}]11;rgb:ffff/ffff/ffff\u{07}"
            + Self.slotReplies(0..<16) + Self.fence
        #expect(
            Self.resolve(Self.parse(answer))
                == TerminalColors(
                    foreground: Self.black, background: Self.white,
                    slots: TerminalColors.Slots(Self.appleTerminalSlots), prefersDark: false))
    }
}
