//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSISlotSGRStateTests.swift
//
//  The sixteen terminal slots and `Color.default` where this module reads them:
//  stated on an `SGRState` through the blend's setters (`sgrForeground` and
//  `sgrBackground`), and read back out of rendered escapes by the colour rewrite
//  that `.opacity()` and the colour effects use. Changing how a slot is stored
//  must leave every one of these alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@Suite("The sixteen slots and the default through SGRState and the colour rewrite")
struct ANSISlotSGRStateTests {

    private typealias Slot = (name: String, color: Color, index: UInt8, foreground: Int, background: Int)

    /// In slot order, 0 through 15.
    private static let slots: [Slot] = [
        ("black", .black, 0, 30, 40),
        ("red", .red, 1, 31, 41),
        ("green", .green, 2, 32, 42),
        ("yellow", .yellow, 3, 33, 43),
        ("blue", .blue, 4, 34, 44),
        ("magenta", .magenta, 5, 35, 45),
        ("cyan", .cyan, 6, 36, 46),
        ("white", .white, 7, 37, 47),
        ("brightBlack", .brightBlack, 8, 90, 100),
        ("brightRed", .brightRed, 9, 91, 101),
        ("brightGreen", .brightGreen, 10, 92, 102),
        ("brightYellow", .brightYellow, 11, 93, 103),
        ("brightBlue", .brightBlue, 12, 94, 104),
        ("brightMagenta", .brightMagenta, 13, 95, 105),
        ("brightCyan", .brightCyan, 14, 96, 106),
        ("brightWhite", .brightWhite, 15, 97, 107),
    ]

    private static func applying(_ code: Int) -> SGRState {
        var state = SGRState()
        state.apply("\u{1B}[\(code)m")
        return state
    }

    @Test("Stating a slot on an SGR state is its own code, at every depth that has colour")
    func slotsStateTheirCodes() {
        for depth in [ColorDepth.truecolor, .palette256, .basic16] {
            for slot in Self.slots {
                let foreground = SGRState().settingForeground(slot.color, depth: depth)
                #expect(foreground == Self.applying(slot.foreground), "\(slot.name) fg @\(depth)")
                #expect(
                    foreground.rendered(changingFrom: SGRState()) == "\u{1B}[\(slot.foreground)m",
                    "\(slot.name) fg bytes @\(depth)")
                let background = SGRState().settingBackground(slot.color, depth: depth)
                #expect(background == Self.applying(slot.background), "\(slot.name) bg @\(depth)")
                #expect(
                    background.rendered(changingFrom: SGRState()) == "\u{1B}[\(slot.background)m",
                    "\(slot.name) bg bytes @\(depth)")
            }
        }
    }

    @Test("A 256-colour index below 16 states its slot's code at sixteen colours")
    func indexStatesItsSlotAtSixteen() {
        for slot in Self.slots {
            #expect(
                SGRState().settingForeground(.palette(slot.index), depth: .basic16) == Self.applying(slot.foreground),
                "\(slot.name) fg")
            #expect(
                SGRState().settingBackground(.palette(slot.index), depth: .basic16) == Self.applying(slot.background),
                "\(slot.name) bg")
        }
    }

    /// The default is STATED as 39 or 49, which is not the same state as a
    /// cleared slot even though both render as those bytes from a plain state.
    @Test("Stating the default is 39 or 49, at every depth that has colour")
    func defaultStatesThirtyNineAndFortyNine() {
        for depth in [ColorDepth.truecolor, .palette256, .basic16] {
            let foreground = SGRState().settingForeground(.default, depth: depth)
            #expect(foreground.rendered(changingFrom: SGRState()) == "\u{1B}[39m", "fg @\(depth)")
            #expect(foreground != SGRState(), "fg @\(depth)")
            let background = SGRState().settingBackground(.default, depth: depth)
            #expect(background.rendered(changingFrom: SGRState()) == "\u{1B}[49m", "bg @\(depth)")
            #expect(background != SGRState(), "bg @\(depth)")
        }
    }

    /// The rewrite behind `.opacity()` and the colour effects reads 30-37, 40-47,
    /// 90-97 and 100-107 as the sixteen slots and hands each to the effect as
    /// that slot's colour. Unchanged by the effect, it writes the same code back;
    /// faded, it writes the fade of the slot's measured value.
    @Test("The colour rewrite reads every basic code as its slot, and writes it back")
    func rewriteReadsEverySlot() {
        let black = Color.rgb(0, 0, 0)
        let foregroundSlot = SGRColorRewrite.ColorSlot.foreground
        let backgroundSlot = SGRColorRewrite.ColorSlot.background
        ColorDepth.withCurrent(.truecolor) {
            for slot in Self.slots {
                for (code, isBackground) in [(slot.foreground, false), (slot.background, true)] {
                    let sequence = "\u{1B}[\(code)m"
                    var seen: [Color] = []
                    let unchanged = SGRColorRewrite.rewriting(
                        sequence, defaultForeground: .rgb(1, 2, 3), defaultBackground: .rgb(4, 5, 6)
                    ) { colour in
                        seen.append(colour)
                        return colour
                    }
                    #expect(unchanged == sequence, "\(slot.name) \(code)")
                    #expect(seen == [slot.color], "\(slot.name) \(code)")

                    let faded = SGRColorRewrite.rewriting(
                        sequence, defaultForeground: .rgb(1, 2, 3), defaultBackground: .rgb(4, 5, 6)
                    ) { $0.opacity(0.5, over: black) }
                    let expected = slot.color.opacity(0.5, over: black)
                    let expectedCodes = isBackground
                        ? expected.backgroundCodes(depth: .truecolor) : expected.foregroundCodes(depth: .truecolor)
                    #expect(faded == "\u{1B}[" + expectedCodes.joined(separator: ";") + "m", "\(slot.name) \(code)")

                    var reported: [(slot: SGRColorRewrite.ColorSlot, colour: Color?)] = []
                    SGRColorRewrite.readingColors(sequence) { reported.append(($0, $1)) }
                    let expectedSlot = isBackground ? backgroundSlot : foregroundSlot
                    #expect(reported.count == 1, "\(slot.name) \(code)")
                    #expect(reported.first?.slot == expectedSlot, "\(slot.name) \(code)")
                    #expect(reported.first?.colour == slot.color, "\(slot.name) \(code)")
                }
            }
        }
    }
}
