//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIColorTests.swift
//
//  `ANSIColor` is the terminal's sixteen slots. Its members are what every
//  emitter reads for a slot, so they are checked against the same table that
//  pins what those emitters produce (ANSISlotPinTests).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("ANSIColor: the sixteen slots")
struct ANSIColorTests {

    @Test("The cases are slots 0 through 15, in order")
    func casesAreTheSixteenSlots() {
        #expect(ANSIColor.allCases.map(\.rawValue) == Array(0...15))
        #expect(ANSIColor(rawValue: 16) == nil)
    }

    @Test("Each slot's half, bright twin, codes and xterm value")
    func members() {
        for slot in ANSIColor.allCases {
            let pin = ANSISlotPinTests.slots[Int(slot.rawValue)]
            #expect(slot.isBright == (slot.rawValue >= 8), "\(slot)")
            #expect(slot.brightTwin.rawValue == slot.rawValue | 8, "\(slot)")
            #expect("\(slot.foregroundCode)" == pin.foreground, "\(slot)")
            #expect("\(slot.backgroundCode)" == pin.background, "\(slot)")
            let rgb = slot.xtermRGB
            #expect([rgb.red, rgb.green, rgb.blue] == pin.xterm, "\(slot)")
            #expect(Color(value: .ansi(slot)) == pin.color, "\(slot)")
        }
        #expect(ANSIColor.red.brightTwin == ANSIColor.brightRed)
        #expect(ANSIColor.brightRed.brightTwin == ANSIColor.brightRed, "a bright slot is its own twin")
    }

    /// 39 and 49 belong to no slot, which is why the default is a `ColorValue`
    /// case of its own rather than a seventeenth slot.
    @Test("The default's codes are 39 and 49, which no slot has")
    func defaultCodesBelongToNoSlot() {
        #expect(ANSIColor.defaultForegroundCode == 39)
        #expect(ANSIColor.defaultBackgroundCode == 49)
        #expect(!ANSIColor.allCases.contains { $0.foregroundCode == ANSIColor.defaultForegroundCode })
        #expect(!ANSIColor.allCases.contains { $0.backgroundCode == ANSIColor.defaultBackgroundCode })
        #expect(Color(value: .terminalDefault) == Color.default)
    }
}
