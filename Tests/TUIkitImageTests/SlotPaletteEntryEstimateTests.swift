//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SlotPaletteEntryEstimateTests.swift
//
//  An image palette matches pixels against its entries' RGB. A slot entry is
//  matched as the colour the terminal reported for that slot, and as xterm's
//  value while it has reported none. It is still drawn as the slot's own code.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("An image palette matches a slot entry as the colour the terminal reported for it")
struct SlotPaletteEntryEstimateTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported
    /// them on 2026-09-14, in slot order.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots([
            rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
            rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
            rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
            rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
        ]))

    /// (220, 0, 0) lies nearer xterm's red (205) than its bright red (255), and
    /// nearer Apple Terminal's bright red (230) than its red (153).
    ///
    /// Each palette is built inside its pin: entries are measured when a
    /// palette is made. `ASCIIPalette.ansi16` is read inside it, and measures
    /// its slots as the report in force when it is read.
    @Test("A pixel maps to the slot entry nearest by the report, else by xterm's value, and keeps the slot's code")
    func slotEntryMatchesByTheReport() {
        let pixel = RGBA(r: 220, g: 0, b: 0)
        TerminalColors.withCurrent(.unknown) {
            let palette = ASCIIPalette([.ansi(.red), .ansi(.brightRed)])
            #expect(palette.nearestIndex(to: pixel) == 0)
            let sixteen = ASCIIPalette.ansi16
            #expect(sixteen.sgrParameters(at: sixteen.nearestIndex(to: pixel), background: false) == "31")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            let palette = ASCIIPalette([.ansi(.red), .ansi(.brightRed)])
            #expect(palette.nearestIndex(to: pixel) == 1)
            #expect(palette.sgrParameters(at: 1, background: false) == "91")
            let byIndex = ASCIIPalette([.palette(1), .palette(9)])
            #expect(byIndex.nearestIndex(to: pixel) == 1)
            let sixteen = ASCIIPalette.ansi16
            #expect(sixteen.sgrParameters(at: sixteen.nearestIndex(to: pixel), background: false) == "91")
        }
    }
}
