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

    /// 16 colours are not in the table yet: the slots depend on the table
    /// the terminal reports.
    @Test("At 16 colours no palette has fills")
    func sixteenColoursHaveNone() {
        #expect(shipped.allSatisfy { $0.rowFills(at: .basic16) == nil && $0.rowFills(at: .noColor) == nil })
    }

    @Test("An accent one channel off still finds the entry; a different accent does not")
    func matchingToleratesRoundingOnly() throws {
        let amber = try #require(shipped.first { $0.name == "Amber" })
        let (red, green, blue) = try #require(amber.accent.rgbComponents)
        let nudged = CopiedPalette(source: amber, accent: .rgb(red, green &+ 1, blue))
        #expect(nudged.rowFills(at: .truecolor) == amber.rowFills(at: .truecolor))
        // A `.tint(.orange)` subtree over Amber: the fills were not chosen for it.
        let tinted = CopiedPalette(source: amber, accent: .rgb(0xFF, 0x80, 0x00))
        #expect(tinted.rowFills(at: .truecolor) == nil)
    }
}
