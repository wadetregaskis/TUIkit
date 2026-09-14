//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCarriedPaletteEntryTests.swift
//
//  This module spells colours itself, in `ASCIIPalette.sgrParameters` and
//  `ANSIRowBuilder`, so `Color`'s emitter does not cover it. These pin that a
//  palette entry of `.terminalForeground` or `.terminalBackground` is SGR 39 or
//  49 in its own slot and its carried RGB in the other, in both spellings.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("An image palette entry that carries the terminal's own colour")
struct TerminalCarriedPaletteEntryTests {

    private static let ink = Color(value: .terminalForeground(red: 171, green: 178, blue: 191))
    private static let paper = Color(value: .terminalBackground(red: 40, green: 44, blue: 52))

    @Test("The palette's SGR parameters: the default in its own slot, the RGB in the other")
    func sgrParameters() {
        let palette = ASCIIPalette([Self.ink, Self.paper])
        #expect(palette.sgrParameters(at: 0, background: false) == "39")
        #expect(palette.sgrParameters(at: 0, background: true) == "48;2;171;178;191")
        #expect(palette.sgrParameters(at: 1, background: true) == "49")
        #expect(palette.sgrParameters(at: 1, background: false) == "38;2;40;44;52")
    }

    @Test("The row builder writes the same escapes as bytes")
    func rowBuilderEscapes() {
        var own = ANSIRowBuilder(capacity: 32)
        own.setColors(foreground: Self.ink, background: Self.paper)
        own.append(ascii: 0x20)
        #expect(own.finish() == "\u{1B}[39m\u{1B}[49m \u{1B}[0m")

        var swapped = ANSIRowBuilder(capacity: 32)
        swapped.setColors(foreground: Self.paper, background: Self.ink)
        swapped.append(ascii: 0x20)
        #expect(swapped.finish() == "\u{1B}[38;2;40;44;52m\u{1B}[48;2;171;178;191m \u{1B}[0m")
    }

    /// SGR 39 is the foreground bold may brighten, as `.default` is; a carried
    /// background used as ink is spelled as a triple, which bold leaves alone.
    @Test("Bold safety: a carried foreground is not safe, a carried background as ink is")
    func boldSafety() {
        #expect(!ASCIIPalette([.rgb(10, 20, 30), Self.ink]).foregroundSurvivesBold)
        #expect(ASCIIPalette([.rgb(10, 20, 30), Self.paper]).foregroundSurvivesBold)
    }
}
