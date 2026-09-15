//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSISlotPaletteEntryTests.swift
//
//  This module spells colours itself, in `ASCIIPalette.sgrParameters` and
//  `ANSIRowBuilder`, so `Color`'s emitter does not cover it. These pin that a
//  palette entry that is one of the sixteen slots is that slot's own code in
//  both spellings, that `.default` is 39 or 49, that neither survives bold, and
//  what `ASCIIPalette.ansi16` holds. Changing how a slot is stored must leave
//  every one of these alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("An image palette entry that is one of the sixteen slots or the default")
struct ANSISlotPaletteEntryTests {

    private typealias Slot = (name: String, color: Color, foreground: Int, background: Int, xterm: [UInt8])

    /// In slot order, 0 through 15.
    private static let slots: [Slot] = [
        ("black", .black, 30, 40, [0, 0, 0]),
        ("red", .red, 31, 41, [205, 0, 0]),
        ("green", .green, 32, 42, [0, 205, 0]),
        ("yellow", .yellow, 33, 43, [205, 205, 0]),
        ("blue", .blue, 34, 44, [0, 0, 238]),
        ("magenta", .magenta, 35, 45, [205, 0, 205]),
        ("cyan", .cyan, 36, 46, [0, 205, 205]),
        ("white", .white, 37, 47, [229, 229, 229]),
        ("brightBlack", .brightBlack, 90, 100, [127, 127, 127]),
        ("brightRed", .brightRed, 91, 101, [255, 0, 0]),
        ("brightGreen", .brightGreen, 92, 102, [0, 255, 0]),
        ("brightYellow", .brightYellow, 93, 103, [255, 255, 0]),
        ("brightBlue", .brightBlue, 94, 104, [92, 92, 255]),
        ("brightMagenta", .brightMagenta, 95, 105, [255, 0, 255]),
        ("brightCyan", .brightCyan, 96, 106, [0, 255, 255]),
        ("brightWhite", .brightWhite, 97, 107, [255, 255, 255]),
    ]

    @Test("sgrParameters spells each slot as its own code, and the default as 39 or 49")
    func sgrParameters() {
        let palette = ASCIIPalette(Self.slots.map(\.color) + [Color.default])
        for (index, slot) in Self.slots.enumerated() {
            #expect(palette.sgrParameters(at: index, background: false) == "\(slot.foreground)", "\(slot.name) fg")
            #expect(palette.sgrParameters(at: index, background: true) == "\(slot.background)", "\(slot.name) bg")
        }
        #expect(palette.sgrParameters(at: 16, background: false) == "39")
        #expect(palette.sgrParameters(at: 16, background: true) == "49")
    }

    @Test("The row builder writes each slot's codes, and the default's, as bytes")
    func rowBuilderEscapes() {
        let rows = Self.slots.map { ($0.name, $0.color, $0.foreground, $0.background) }
            + [("default", Color.default, 39, 49)]
        for (name, color, foreground, background) in rows {
            var builder = ANSIRowBuilder(capacity: 32)
            builder.setColors(foreground: color, background: color)
            builder.append(ascii: 0x20)
            #expect(builder.finish() == "\u{1B}[\(foreground)m\u{1B}[\(background)m \u{1B}[0m", "\(name)")
        }
    }

    /// A slot's ink is a name bold may repaint in its bright twin, and 39 is the
    /// foreground bold may brighten, so a palette holding either is not safe.
    @Test("No slot and not the default survives bold as ink, by name or by index")
    func boldSafety() {
        #expect(ASCIIPalette([.rgb(10, 20, 30)]).foregroundSurvivesBold, "the fixture")
        for (index, slot) in Self.slots.enumerated() {
            #expect(!ASCIIPalette([.rgb(10, 20, 30), slot.color]).foregroundSurvivesBold, "\(slot.name)")
            #expect(
                !ASCIIPalette([.rgb(10, 20, 30), .palette(UInt8(index))]).foregroundSurvivesBold,
                "palette \(index)")
        }
        #expect(!ASCIIPalette([.rgb(10, 20, 30), Color.default]).foregroundSurvivesBold)
    }

    @Test("ansi16 is the sixteen slots in slot order, measured as xterm's values, at every depth")
    func ansi16() {
        let expected = Self.slots.map(\.color)
        #expect(ASCIIPalette.ansi16.colors == expected)
        #expect(ASCIIPalette.ansi16.entries.map { [$0.rgba.r, $0.rgba.g, $0.rgba.b] } == Self.slots.map(\.xterm))
        for depth in [ColorDepth.truecolor, .palette256, .basic16, .noColor] {
            #expect(ASCIIPalette.ansi16.downsampled(to: depth).colors == expected, "@\(depth)")
        }
        for (index, slot) in Self.slots.enumerated() {
            #expect(ASCIIPalette.ansi16.sgrParameters(at: index, background: false) == "\(slot.foreground)")
        }
    }
}
