//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFillTableTests.swift
//
//  The shipped palettes' row fills are constants chosen at coding time
//  (Tools/RowFillValues). These pin that each shipped palette finds its own,
//  at the depths the table covers, and that nothing else does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A palette with a shipped palette's colours, and an accent of its own.
private struct CopiedPalette: Palette {
    let source: any Palette
    let accent: Color
    var id: String { "copied-\(source.id)" }
    var name: String { "Copied \(source.name)" }
    var background: Color { source.background }
    var foreground: Color { source.foreground }
    var foregroundSecondary: Color { source.foregroundSecondary }
    var success: Color { source.success }
    var warning: Color { source.warning }
    var error: Color { source.error }
    var info: Color { source.info }
    var border: Color { source.border }
}

@Suite("Shipped row fills")
struct RowFillTableTests {

    private let shipped = PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles

    @Test("Every shipped palette finds its own entry, and no two share one")
    func everyShippedPaletteHits() {
        #expect(RowFills.shipped.count == shipped.count)
        let fills = shipped.map { $0.rowFills(at: .truecolor) }
        #expect(fills.allSatisfy { $0 != nil }, "missing: \(zip(shipped, fills).filter { $1 == nil }.map { $0.0.name })")
        #expect(Set(fills.compactMap { $0?.selection }).count == shipped.count)
    }

    /// The fields' order, (S, F dim, F top, B dim, B top), spot-checked on one
    /// palette's generated row: Amber.
    @Test("A shipped palette's fills are its constants, at truecolour and at 256 colours")
    func amberReadsItsConstants() throws {
        let amber = try #require(shipped.first { $0.name == "Amber" })
        #expect(
            amber.rowFills(at: .truecolor)
                == RowFills(
                    selection: .rgb(0x47, 0x39, 0x11), focusDim: .rgb(0x35, 0x24, 0x01),
                    focusBright: .rgb(0x70, 0x4A, 0x00), emphasisDim: .rgb(0x56, 0x45, 0x13),
                    emphasisBright: .rgb(0x85, 0x6A, 0x1C)))
        #expect(
            amber.rowFills(at: .palette256)
                == RowFills(
                    selection: .palette256(58), focusDim: .palette256(236), focusBright: .palette256(94),
                    emphasisDim: .palette256(94), emphasisBright: .palette256(101)))
    }

    @Test("Without colour no palette has fills")
    func noColourHasNone() {
        #expect(shipped.allSatisfy { $0.rowFills(at: .noColor) == nil })
    }

    /// At 16 colours the table carries picks for xterm's slots and Apple Terminal's:
    /// Violet's on Apple's F tops out in reverse video, and its top holds F's dim slot
    /// for a site that cannot draw one.
    @Test("At 16 colours a shipped palette reads its picks for the table the terminal reports")
    func sixteenColourPicks() throws {
        let violet = try #require(shipped.first { $0.name == "Violet" })
        let onXterm = try #require(TerminalColors.withCurrent(.unknown) { violet.rowFills(at: .basic16) })
        // xterm: (10, 2, 7, 3, 6).
        #expect(onXterm.selection == .ansi(.brightGreen))
        #expect(onXterm.focusDim == .ansi(.green) && onXterm.focusBright == .ansi(.white))
        #expect(onXterm.reversedFocusEnd == nil && onXterm.reversedEmphasisEnd == nil)

        let apple = TerminalColors(
            foreground: .init(red: 0, green: 0, blue: 0), background: .init(red: 255, green: 255, blue: 255),
            slots: TerminalColors.Slots(
                RowFills.appleTable.map {
                    TerminalColors.RGB(red: UInt8($0 >> 16 & 0xFF), green: UInt8($0 >> 8 & 0xFF), blue: UInt8($0 & 0xFF))
                }))
        let onApple = try #require(TerminalColors.withCurrent(apple) { violet.rowFills(at: .basic16) })
        // Apple: (1, 4, -1, 13, 4).
        #expect(onApple.selection == .ansi(.red))
        #expect(onApple.reversedFocusEnd == .top)
        #expect(onApple.focusDim == .ansi(.blue) && onApple.focusBright == .ansi(.blue))
        #expect(onApple.emphasisDim == .ansi(.brightMagenta) && onApple.emphasisBright == .ansi(.blue))
    }

    @Test("An accent one channel off still finds the entry; a different accent does not")
    func matchingToleratesRoundingOnly() throws {
        let amber = try #require(shipped.first { $0.name == "Amber" })
        let (red, green, blue) = try #require(amber.accent.rgbComponents)
        let nudged = CopiedPalette(source: amber, accent: .rgb(red, green &+ 1, blue))
        #expect(nudged.rowFills(at: .truecolor) == amber.rowFills(at: .truecolor))
        // A `.tint(.orange)` subtree over Amber: the fills were not chosen for it, so
        // the rule places them (`RowFillRuleTests`).
        func packed(_ colour: Color) throws -> UInt32 {
            let (red, green, blue) = try #require(colour.rgbComponents)
            return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        }
        let entry = RowFills.entry(
            page: try packed(amber.background), text: try packed(amber.foreground),
            secondary: try packed(amber.foregroundSecondary), accent: 0xFF8000)
        #expect(entry == nil)
        let tinted = CopiedPalette(source: amber, accent: .rgb(0xFF, 0x80, 0x00))
        #expect(tinted.rowFills(at: .truecolor) != amber.rowFills(at: .truecolor))
    }
}
