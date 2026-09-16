//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorPalette256FactoryTests.swift
//
//  `Color.palette256(_:)` names one of the terminal's 256 colours by index: for
//  every index it is that index, and emits and measures as ANSISlotPinTests and
//  ColorTests pin it. It is the spelling `Color.palette(_:)` had, moved away from
//  the `Color.palette` semantic namespace it reads like.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Color.palette256(_:) names one of the terminal's 256 colours")
struct ColorPalette256FactoryTests {

    /// A sample across the three regions of the 256: the sixteen slots, the
    /// 6×6×6 cube and the twenty-four greys.
    static let sampleIndices: [UInt8] = [0, 1, 9, 15, 16, 67, 196, 231, 232, 244, 255]

    @Test("Every index is that index, opaque, and the colour the old spelling names")
    func everyIndexIsTheIndex() {
        for index in UInt8.min...UInt8.max {
            let colour = Color.palette256(index)
            #expect(colour.value == Color.ColorValue.palette256(index), "\(index)")
            #expect(colour == Color.palette(index), "\(index)")
            #expect(colour.isOpaque, "\(index)")
        }
    }

    @Test("It emits 38;5;n and 48;5;n where the terminal has 256 colours", arguments: sampleIndices)
    func emitsItsIndex(_ index: UInt8) {
        let colour = Color.palette256(index)
        for depth in [ColorDepth.truecolor, .palette256] {
            #expect(colour.foregroundCodes(depth: depth) == ["38", "5", "\(index)"], "fg @\(depth)")
            #expect(colour.backgroundCodes(depth: depth) == ["48", "5", "\(index)"], "bg @\(depth)")
        }
    }

    /// An index below sixteen is a NAME, so it is terminal-defined and measures as
    /// nothing until the terminal reports its slots; the cube and the greys are
    /// fixed colours that always measure.
    @Test("An index below sixteen is the terminal's slot", arguments: ANSISlotPinTests.slots)
    func indexBelowSixteenIsItsSlot(_ slot: ANSISlotPinTests.Slot) {
        let indexed = Color.palette256(slot.index)
        #expect(indexed.isTerminalDefined)
        #expect(indexed.downsampledToANSI16() == slot.color)
        #expect(indexed.foregroundCodes(depth: .basic16) == [slot.foreground])
        #expect(indexed.backgroundCodes(depth: .basic16) == [slot.background])
        TerminalColors.withCurrent(.unknown) {
            #expect(indexed.rgbComponents == nil)
            #expect(indexed.estimatedRGB.map { [$0.red, $0.green, $0.blue] } == slot.xterm)
        }
    }

    @Test("The cube and the greys are fixed colours, not the terminal's")
    func aboveSixteenIsAFixedColour() {
        TerminalColors.withCurrent(.unknown) {
            for index in Self.sampleIndices where index >= 16 {
                #expect(!Color.palette256(index).isTerminalDefined, "\(index)")
                #expect(Color.palette256(index).rgbComponents != nil, "\(index)")
            }
        }
    }
}
