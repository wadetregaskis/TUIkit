//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReportedSlotQuantisationTests.swift
//
//  On a terminal with sixteen colours, an RGB colour is drawn as the slot nearest to it.
//  Nearest by the colours the terminal reported for its slots (OSC 4), once it has
//  reported all sixteen, and by xterm's table until then: the slot is what the terminal
//  paints, so the search should measure what it paints when it can.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("RGB quantises to the nearest of the sixteen slots the terminal reported")
struct ReportedSlotQuantisationTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md), in slot order. Only slot 0 is xterm's.
    private static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// iTerm2 3.7.1's "Default" sixteen, as reported on 2026-09-14
    /// (Terminal-compatibility.md), in slot order.
    private static let iTerm2Default = [
        rgb(21, 25, 30), rgb(167, 69, 50), rgb(87, 191, 56), rgb(199, 196, 63),
        rgb(46, 67, 192), rgb(177, 73, 184), rgb(89, 194, 198), rgb(199, 199, 199),
        rgb(104, 104, 104), rgb(208, 126, 120), rgb(130, 228, 152), rgb(234, 226, 74),
        rgb(167, 171, 237), rgb(212, 131, 220), rgb(142, 250, 253), rgb(255, 255, 255),
    ]

    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))

    private static let iTerm2 = TerminalColors(
        foreground: rgb(16, 16, 16), background: rgb(250, 250, 250), slots: TerminalColors.Slots(iTerm2Default))

    /// A terminal that reported its default pair and no slots (Warp, measured).
    private static let pairOnly = TerminalColors(foreground: rgb(17, 17, 17), background: rgb(255, 255, 255))

    /// The rule, written out: the slot at the least squared RGB distance, the lower
    /// slot on a tie.
    private static func nearestSlot(to colour: (UInt8, UInt8, UInt8), among table: [TerminalColors.RGB]) -> ANSIColor {
        var best = 0
        var bestDistance = Int.max
        for (index, entry) in table.enumerated() {
            let red = Int(colour.0) - Int(entry.red)
            let green = Int(colour.1) - Int(entry.green)
            let blue = Int(colour.2) - Int(entry.blue)
            let distance = red * red + green * green + blue * blue
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return ANSIColor.allCases[best]
    }

    /// (220, 0, 0) is nearer xterm's red (205) than its bright red (255), and nearer
    /// Apple Terminal's bright red (230) than its red (153). (0, 0, 255) is nearer
    /// xterm's blue (0, 0, 238) and is exactly Apple Terminal's bright blue.
    @Test("Until the terminal reports its sixteen, RGB quantises by xterm's table")
    func unreportedQuantisesByXterm() {
        for terminal in [TerminalColors.unknown, Self.pairOnly] {
            TerminalColors.withCurrent(terminal) {
                for slot in ANSIColor.allCases {
                    let xterm = slot.xtermRGB
                    #expect(Color.rgb(xterm.red, xterm.green, xterm.blue).downsampledToANSI16() == .ansi(slot), "\(slot)")
                }
                #expect(Color.rgb(220, 0, 0).downsampledToANSI16() == .ansi(.red))
                #expect(Color.rgb(0, 0, 255).downsampledToANSI16() == .ansi(.blue))
                #expect(Color.rgb(0, 0, 255).foregroundCodes(depth: .basic16) == ["34"])
            }
        }
    }

    @Test("Once reported, RGB quantises to the nearest reported slot, spelled as the slot")
    func reportedQuantisesByTheReport() {
        TerminalColors.withCurrent(Self.appleTerminal) {
            for (index, slot) in ANSIColor.allCases.enumerated() {
                let reported = Self.appleBasic[index]
                let colour = Color.rgb(reported.red, reported.green, reported.blue)
                #expect(colour.downsampledToANSI16() == .ansi(slot), "\(slot)")
                #expect(colour.foregroundCodes(depth: .basic16) == ["\(slot.foregroundCode)"], "\(slot)")
                #expect(colour.backgroundCodes(depth: .basic16) == ["\(slot.backgroundCode)"], "\(slot)")
            }
            #expect(Color.rgb(220, 0, 0).downsampledToANSI16() == .ansi(.brightRed))
            #expect(Color.rgb(220, 0, 0).foregroundCodes(depth: .basic16) == ["91"])
            #expect(Color.rgb(0, 0, 255).downsampledToANSI16() == .ansi(.brightBlue))
            #expect(Color.rgb(0, 0, 255).backgroundCodes(depth: .basic16) == ["104"])
            // A 256-colour index above the sixteen goes through its RGB: 21 is (0, 0, 255).
            #expect(Color.palette(21).downsampledToANSI16() == .ansi(.brightBlue))
            // The slots below 16 are the slots themselves, whatever the report.
            #expect(Color.palette(4).downsampledToANSI16() == .ansi(.blue))
            // The colour's alpha is carried, as by every other derivation.
            var faded = Color.rgb(220, 0, 0)
            faded.alpha = 128
            var fadedSlot = Color.ansi(.brightRed)
            fadedSlot.alpha = 128
            #expect(faded.downsampledToANSI16() == fadedSlot)
        }
    }

    @Test("Across the RGB cube, the slot chosen is the nearest reported one, the lower on a tie")
    func nearestAcrossTheCube() {
        let levels = Array(stride(from: 0, through: 255, by: 17)).map(UInt8.init)
        for (terminal, table) in [(Self.appleTerminal, Self.appleBasic), (Self.iTerm2, Self.iTerm2Default)] {
            TerminalColors.withCurrent(terminal) {
                var mismatches: [String] = []
                for red in levels {
                    for green in levels {
                        for blue in levels {
                            let expected = Self.nearestSlot(to: (red, green, blue), among: table)
                            let actual = Color.rgb(red, green, blue).downsampledToANSI16()
                            if actual != .ansi(expected) {
                                mismatches.append("(\(red), \(green), \(blue)) -> \(actual), not \(expected)")
                            }
                        }
                    }
                }
                #expect(mismatches.isEmpty, "\(mismatches.count) of \(levels.count * levels.count * levels.count): \(mismatches.prefix(8))")
            }
        }
    }

    /// The example AppearanceAndColors.md and Terminal-compatibility.md give: `.red`,
    /// (255, 59, 48), is nearer xterm's and Apple Terminal's slot 9 than their slot 1, and
    /// nearer iTerm2's slot 1 (167, 69, 50) than its slot 9 (208, 126, 120).
    @Test("Color.red is SGR 91 by xterm's table and on Apple Terminal Basic, and 31 on iTerm2 Default")
    func namedRedFollowsTheReport() {
        TerminalColors.withCurrent(.unknown) {
            #expect(Color.red.foregroundCodes(depth: .basic16) == ["91"])
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(Color.red.foregroundCodes(depth: .basic16) == ["91"])
        }
        TerminalColors.withCurrent(Self.iTerm2) {
            #expect(Color.red.foregroundCodes(depth: .basic16) == ["31"])
        }
    }

    @Test("Slots the terminal reported as the same colour tie, and the lower slot wins")
    func tiesGoToTheLowerSlot() {
        let grey = Self.rgb(128, 128, 128)
        TerminalColors.withCurrent(TerminalColors(slots: TerminalColors.Slots(repeating: grey))) {
            for colour in [Color.rgb(255, 0, 0), .rgb(0, 0, 0), .rgb(255, 255, 255), .palette(196)] {
                #expect(colour.downsampledToANSI16() == .ansi(.black), "\(colour)")
            }
        }
    }
}
