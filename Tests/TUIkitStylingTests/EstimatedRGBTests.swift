//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EstimatedRGBTests.swift
//
//  `Color.estimatedRGB`: a colour's RGB as best known, for code that reads a
//  colour as a value. A slot is the colour the terminal reported for it, else
//  xterm's; every other colour is exactly its `rgbComponents`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("A colour's RGB as best known, for code that reads a colour as a value")
struct EstimatedRGBTests {

    private typealias Triple = (red: UInt8, green: UInt8, blue: UInt8)

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported
    /// them on 2026-09-14, in slot order. None of them is xterm's value.
    private static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// Apple Terminal "Basic" as it reports itself: black on white, and its
    /// sixteen slots.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))

    /// A terminal that reported its default pair and no slots (Warp, measured).
    private static let pairOnly = TerminalColors(foreground: rgb(17, 17, 17), background: rgb(255, 255, 255))

    private static func channels(_ triple: Triple?) -> [UInt8]? {
        triple.map { [$0.red, $0.green, $0.blue] }
    }

    private static func channels(_ reported: TerminalColors.RGB) -> [UInt8] {
        [reported.red, reported.green, reported.blue]
    }

    @Test("A slot the terminal has not reported is xterm's value, by name and by index")
    func unreportedSlotIsXterm() {
        for terminal in [TerminalColors.unknown, Self.pairOnly] {
            TerminalColors.withCurrent(terminal) {
                for slot in ANSIColor.allCases {
                    let xterm = Self.channels(slot.xtermRGB)
                    #expect(Self.channels(Color.ansi(slot).estimatedRGB) == xterm, "\(slot)")
                    #expect(Self.channels(Color.palette(slot.rawValue).estimatedRGB) == xterm, "palette \(slot.rawValue)")
                }
            }
        }
    }

    @Test("A slot the terminal has reported is the reported colour, by name and by index")
    func reportedSlotIsTheReport() {
        TerminalColors.withCurrent(Self.appleTerminal) {
            for slot in ANSIColor.allCases {
                let reported = Self.channels(Self.appleBasic[Int(slot.rawValue)])
                #expect(Self.channels(Color.ansi(slot).estimatedRGB) == reported, "\(slot)")
                #expect(
                    Self.channels(Color.palette(slot.rawValue).estimatedRGB) == reported, "palette \(slot.rawValue)")
            }
        }
    }

    @Test("Every colour that is not a slot is exactly its rgbComponents, whatever the terminal reported")
    func everythingElseIsItsComponents() {
        let colours: [Color] = [
            .rgb(1, 2, 3), .palette(16), .palette(231), .palette(232), .palette(255),
            Color(value: .terminalForeground), Color(value: .terminalBackground), .default, Color.palette.accent,
        ]
        for terminal in [TerminalColors.unknown, Self.pairOnly, Self.appleTerminal] {
            TerminalColors.withCurrent(terminal) {
                for colour in colours {
                    #expect(Self.channels(colour.estimatedRGB) == Self.channels(colour.rgbComponents), "\(colour)")
                }
            }
        }
    }

    @Test("The default pair is the reported pair or nothing; Color.default and a semantic colour are nothing")
    func colourWithoutAnEstimate() {
        TerminalColors.withCurrent(.unknown) {
            #expect(Color(value: .terminalForeground).estimatedRGB == nil)
            #expect(Color(value: .terminalBackground).estimatedRGB == nil)
            #expect(Color.default.estimatedRGB == nil)
            #expect(Color.palette.accent.estimatedRGB == nil)
        }
        TerminalColors.withCurrent(Self.pairOnly) {
            #expect(Self.channels(Color(value: .terminalForeground).estimatedRGB) == [17, 17, 17])
            #expect(Self.channels(Color(value: .terminalBackground).estimatedRGB) == [255, 255, 255])
            #expect(Color.default.estimatedRGB == nil, "39 as ink and 49 as a fill: no one colour")
        }
    }
}
