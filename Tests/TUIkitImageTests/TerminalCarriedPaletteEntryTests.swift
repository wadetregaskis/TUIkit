//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCarriedPaletteEntryTests.swift
//
//  This module spells colours itself, in `ASCIIPalette.sgrParameters` and
//  `ANSIRowBuilder`, so `Color`'s emitter does not cover it. These pin that a
//  palette entry of `.terminalForeground` or `.terminalBackground` is SGR 39 or
//  49 in its own slot, and in the other slot the RGB the terminal reported or,
//  while it has said nothing, that slot's own default, in both spellings.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("An image palette entry that is the terminal's own colour")
struct TerminalCarriedPaletteEntryTests {

    private static let ink = Color(value: .terminalForeground)
    private static let paper = Color(value: .terminalBackground)

    /// One Dark's pair: ink #abb2bf on #282c34.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    @Test("Reported: the default in its own slot, the reported RGB in the other")
    func sgrParametersOnceReported() {
        TerminalColors.withCurrent(Self.reported) {
            let palette = ASCIIPalette([Self.ink, Self.paper])
            #expect(palette.sgrParameters(at: 0, background: false) == "39")
            #expect(palette.sgrParameters(at: 0, background: true) == "48;2;171;178;191")
            #expect(palette.sgrParameters(at: 1, background: true) == "49")
            #expect(palette.sgrParameters(at: 1, background: false) == "38;2;40;44;52")
        }
    }

    @Test("Unknown: the slot's own default, whichever colour is in it")
    func sgrParametersWhileUnknown() {
        TerminalColors.withCurrent(.unknown) {
            let palette = ASCIIPalette([Self.ink, Self.paper])
            #expect(palette.sgrParameters(at: 0, background: false) == "39")
            #expect(palette.sgrParameters(at: 0, background: true) == "49")
            #expect(palette.sgrParameters(at: 1, background: true) == "49")
            #expect(palette.sgrParameters(at: 1, background: false) == "39")
        }
    }

    @Test("The row builder writes the same escapes as bytes, reported or not")
    func rowBuilderEscapes() {
        TerminalColors.withCurrent(Self.reported) {
            var own = ANSIRowBuilder(capacity: 32)
            own.setColors(foreground: Self.ink, background: Self.paper)
            own.append(ascii: 0x20)
            #expect(own.finish() == "\u{1B}[39m\u{1B}[49m \u{1B}[0m")

            var swapped = ANSIRowBuilder(capacity: 32)
            swapped.setColors(foreground: Self.paper, background: Self.ink)
            swapped.append(ascii: 0x20)
            #expect(swapped.finish() == "\u{1B}[38;2;40;44;52m\u{1B}[48;2;171;178;191m \u{1B}[0m")
        }
        TerminalColors.withCurrent(.unknown) {
            var own = ANSIRowBuilder(capacity: 32)
            own.setColors(foreground: Self.ink, background: Self.paper)
            own.append(ascii: 0x20)
            #expect(own.finish() == "\u{1B}[39m\u{1B}[49m \u{1B}[0m")

            var swapped = ANSIRowBuilder(capacity: 32)
            swapped.setColors(foreground: Self.paper, background: Self.ink)
            swapped.append(ascii: 0x20)
            #expect(swapped.finish() == "\u{1B}[39m\u{1B}[49m \u{1B}[0m")
        }
    }

    /// SGR 39 is the foreground bold may brighten, as `.default` is. A carried
    /// background used as ink is spelled as a triple once reported, which bold
    /// leaves alone, and as 39 while unknown, which it may not.
    @Test("Bold safety: a carried foreground is never safe; a carried background as ink only once reported")
    func boldSafety() {
        TerminalColors.withCurrent(Self.reported) {
            #expect(!ASCIIPalette([.rgb(10, 20, 30), Self.ink]).foregroundSurvivesBold)
            #expect(ASCIIPalette([.rgb(10, 20, 30), Self.paper]).foregroundSurvivesBold)
        }
        TerminalColors.withCurrent(.unknown) {
            #expect(!ASCIIPalette([.rgb(10, 20, 30), Self.ink]).foregroundSurvivesBold)
            #expect(!ASCIIPalette([.rgb(10, 20, 30), Self.paper]).foregroundSurvivesBold)
        }
    }
}
