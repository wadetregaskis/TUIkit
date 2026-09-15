//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorANSIFactoryTests.swift
//
//  `Color.ansi(_:)` names one of the terminal's sixteen colour slots: for every
//  slot it is that slot, and emits and measures as ANSISlotPinTests pins it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Color.ansi(_:) names a terminal slot")
struct ColorANSIFactoryTests {

    @Test("Every slot is that slot, and emits and measures as one", arguments: ANSISlotPinTests.slots)
    func isTheSlot(_ slot: ANSISlotPinTests.Slot) {
        guard let ansi = ANSIColor(rawValue: slot.index) else {
            Issue.record("the fixture: \(slot.index) is not a slot")
            return
        }
        let colour = Color.ansi(ansi)
        #expect(colour.value == Color.ColorValue.ansi(ansi))
        #expect(colour.isOpaque)
        #expect(colour.foregroundCodes(depth: .truecolor) == [slot.foreground])
        #expect(colour.backgroundCodes(depth: .truecolor) == [slot.background])
        TerminalColors.withCurrent(.unknown) {
            #expect(colour.rgbComponents == nil)
            #expect(colour.estimatedRGB.map { [$0.red, $0.green, $0.blue] } == slot.xterm)
        }
        #expect(colour.isTerminalDefined)
    }

    /// Two spellings of one slot: equal at sixteen colours, where the index
    /// becomes the name, and distinct values.
    @Test("A slot by name is not the 256-colour index of the same slot, until sixteen colours")
    func nameIsNotIndex() {
        for slot in ANSIColor.allCases {
            #expect(Color.ansi(slot) != Color.palette(slot.rawValue), "\(slot)")
            #expect(Color.palette(slot.rawValue).downsampledToANSI16() == Color.ansi(slot), "\(slot)")
        }
    }
}
