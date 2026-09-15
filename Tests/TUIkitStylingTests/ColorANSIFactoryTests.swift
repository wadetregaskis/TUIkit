//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorANSIFactoryTests.swift
//
//  `Color.ansi(_:)` names one of the terminal's sixteen colour slots. For every
//  slot it is the same colour as the named static, so it emits and measures
//  exactly as that static does (pinned in ANSISlotPinTests).
//
//  The statics are listed here, not taken from ANSISlotPinTests' table, which
//  names each slot as `Color.ansi(_:)`: compared with that, the factory would be
//  compared with itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Color.ansi(_:) names a terminal slot")
struct ColorANSIFactoryTests {

    private static let depths: [ColorDepth] = [.truecolor, .palette256, .basic16, .noColor]

    /// The sixteen named statics, in slot order.
    private static let namedStatics: [Color] = [
        .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
        .brightBlack, .brightRed, .brightGreen, .brightYellow,
        .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
    ]

    @Test("Every slot equals its named static and emits its bytes", arguments: ANSISlotPinTests.slots)
    func equalsTheNamedStatic(_ slot: ANSISlotPinTests.Slot) {
        guard let ansi = ANSIColor(rawValue: slot.index) else {
            Issue.record("the fixture: \(slot.index) is not a slot")
            return
        }
        let colour = Color.ansi(ansi)
        let named = Self.namedStatics[Int(slot.index)]
        #expect(colour == named)
        #expect(colour.value == Color.ColorValue.ansi(ansi))
        #expect(colour.isOpaque)
        for depth in Self.depths {
            #expect(colour.foregroundCodes(depth: depth) == named.foregroundCodes(depth: depth), "fg @\(depth)")
            #expect(colour.backgroundCodes(depth: depth) == named.backgroundCodes(depth: depth), "bg @\(depth)")
        }
        #expect(colour.foregroundCodes(depth: .truecolor) == [slot.foreground])
        #expect(colour.backgroundCodes(depth: .truecolor) == [slot.background])
        #expect(colour.rgbComponents.map { [$0.red, $0.green, $0.blue] } == slot.xterm)
        #expect(colour.isTerminalDefined)
    }

    @Test("Mapped over every slot, it gives the sixteen named statics in slot order")
    func allCasesAreTheStatics() {
        #expect(ANSIColor.allCases.map(Color.ansi) == Self.namedStatics)
    }

    /// Two spellings of one slot, as `.palette(1)` and `.red` already are: equal
    /// at sixteen colours, where the index becomes the name, and distinct values.
    @Test("A slot by name is not the 256-colour index of the same slot, until sixteen colours")
    func nameIsNotIndex() {
        for slot in ANSIColor.allCases {
            #expect(Color.ansi(slot) != Color.palette(slot.rawValue), "\(slot)")
            #expect(Color.palette(slot.rawValue).downsampledToANSI16() == Color.ansi(slot), "\(slot)")
        }
    }
}
