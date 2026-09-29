//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFillRuleTests.swift
//
//  The row-fill rule for runtime palettes gives, to the bit, the answers of its
//  reference (Tools/RowFillValues/rule.py) for every palette in
//  runtime_palettes.json.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A custom palette: a page, text and accent, and optionally a wash of its own.
private struct CustomRows: Palette {
    let background: Color
    let foreground: Color
    let accent: Color
    var wash: Color?
    var id: String { "custom-rows" }
    var name: String { "Custom rows" }
    var success: Color { .green }
    var warning: Color { .yellow }
    var error: Color { .red }
    var info: Color { .blue }
    var border: Color { foreground }
    var focusBackground: Color { wash ?? derivedFocusBackground() }
}

/// A palette as a `.tint` presents it: its base's colours, with another accent.
private struct Tinted: Palette {
    let base: any Palette
    let accent: Color
    var id: String { base.id }
    var name: String { base.name }
    var background: Color { base.background }
    var foreground: Color { base.foreground }
    var foregroundSecondary: Color { base.foregroundSecondary }
    var success: Color { base.success }
    var warning: Color { base.warning }
    var error: Color { base.error }
    var info: Color { base.info }
    var border: Color { base.border }
    var focusBackground: Color { base.focusBackground }
}

@Suite("Row-fill rule")
struct RowFillRuleTests {
    private static func colour(_ packed: UInt32) -> Color {
        .rgb(UInt8(packed >> 16 & 0xFF), UInt8(packed >> 8 & 0xFF), UInt8(packed & 0xFF))
    }

    private static func rule(for golden: RowFillGolden) -> RowFillRule {
        RowFillRule(
            page: colour(golden.page), text: colour(golden.text), secondary: colour(golden.secondary),
            accent: colour(golden.accent), live: golden.live)
    }

    private static func ends(_ look: RowFillRule.Look) -> [RowFillRule.Swatch] {
        [look.selection, look.focus.dim, look.focus.top, look.emphasis.dim, look.emphasis.top]
    }

    @Test("Truecolour fills match the reference", arguments: rowFillRuleGoldens)
    func truecolour(_ golden: RowFillGolden) {
        let look = Self.rule(for: golden).truecolour()
        let (selection, focusDim, focusTop, emphasisDim, emphasisTop) = golden.truecolour
        #expect(Self.ends(look).map(\.packed) == [selection, focusDim, focusTop, emphasisDim, emphasisTop])
    }

    @Test("256-colour fills match the reference", arguments: rowFillRuleGoldens)
    func cube(_ golden: RowFillGolden) {
        let rule = Self.rule(for: golden)
        let look = rule.cube(toward: rule.truecolour())
        let (selection, focusDim, focusTop, emphasisDim, emphasisTop) = golden.cube
        #expect(
            Self.ends(look).map { RowFillRule.cubeIndex[$0.packed] }
                == [selection, focusDim, focusTop, emphasisDim, emphasisTop])
    }

    @Test("16-colour fills match the reference, against the table the terminal reports", arguments: rowFillRuleGoldens)
    func sixteen(_ golden: RowFillGolden) {
        let rule = Self.rule(for: golden)
        let table = golden.table.map { $0.map { RowFillRule.Swatch(UInt8($0 >> 16 & 0xFF), UInt8($0 >> 8 & 0xFF), UInt8($0 & 0xFF)) } }
            ?? ANSIColor.allCases.map { RowFillRule.Swatch($0.xtermRGB.red, $0.xtermRGB.green, $0.xtermRGB.blue) }
        let slots = rule.sixteen(toward: rule.truecolour(), table: table)
        let (selection, focusDim, focusTop, emphasisDim, emphasisTop) = golden.sixteen
        func slot(_ index: Int?) -> Int { index ?? -1 }
        #expect(
            [slots.selection, slot(slots.focusDim), slot(slots.focusTop), slot(slots.emphasisDim), slot(slots.emphasisTop)]
                == [selection, focusDim, focusTop, emphasisDim, emphasisTop])
    }

    // MARK: - What a palette draws

    private static let dusk = CustomRows(
        background: .rgb(0x12, 0x14, 0x1C), foreground: .rgb(0xE6, 0xE6, 0xE6), accent: .rgb(0xF0, 0xAC, 0x4C))

    private static func look(_ palette: any Palette) -> RowFillRule.Look {
        RowFillRule(
            page: palette.background, text: palette.foreground, secondary: palette.foregroundSecondary,
            accent: palette.accent, live: false
        ).truecolour()
    }

    @Test("A custom palette's rows draw the rule's fills")
    func customPaletteDrawsTheRule() throws {
        let fills = try #require(Self.dusk.rowFills(at: .truecolor))
        let look = Self.look(Self.dusk)
        #expect(
            [fills.selection, fills.focusDim, fills.focusBright, fills.emphasisDim, fills.emphasisBright]
                == Self.ends(look).map(\.color))
        #expect(Self.dusk.selectedRowFill() == .fill(fills.selection))
    }

    @Test("A wash a palette states is drawn as stated at truecolour; S and B are still the rule's")
    func statedWashIsKept() throws {
        var palette = Self.dusk
        palette.wash = .rgb(0x30, 0x24, 0x40)
        let fills = try #require(palette.rowFills(at: .truecolor))
        #expect(fills.focusDim == .rgb(0x30, 0x24, 0x40))
        #expect(fills.focusBright == palette.washPulse(.rgb(0x30, 0x24, 0x40)).bright)
        let look = Self.look(palette)
        #expect(fills.selection == look.selection.color)
        #expect(fills.emphasisBright == look.emphasis.top.color)
    }

    @Test("On 256 colours a stated wash keeps its cube entries where they hold, and moves where they would sit on S")
    func statedWashOnTheCube() throws {
        var palette = Self.dusk
        palette.wash = .rgb(0x30, 0x24, 0x40)
        let kept = try #require(palette.rowFills(at: .palette256))
        let (dim, bright) = palette.washPulse(.rgb(0x30, 0x24, 0x40))
        #expect(kept.focusDim == dim.downsampledToPalette256())
        #expect(kept.focusBright == bright.downsampledToPalette256())

        // A wash on S's own entry cannot tell the cursor row from a selected one.
        let derived = try #require(Self.dusk.rowFills(at: .palette256))
        let (red, green, blue) = try #require(derived.selection.rgbComponents)
        palette.wash = .rgb(red, green, blue)
        let moved = try #require(palette.rowFills(at: .palette256))
        #expect(moved.focusDim == derived.focusDim)
        #expect(moved.focusBright == derived.focusBright)
    }

    @Test("A shipped palette under a tint breathes the rule's F, not the wash it chose for its own accent")
    func tintedShippedPaletteWash() throws {
        let base = PaletteRegistry.all[0]
        let tinted = Tinted(base: base, accent: .rgb(0x4C, 0x90, 0xF0))
        let fills = try #require(tinted.rowFills(at: .truecolor))
        let look = Self.look(tinted)
        #expect(fills.focusDim == look.focus.dim.color)
        #expect(fills.focusDim != base.focusBackground)
    }

    @Test("Over another surface the accent's fill breath is the rule's B, placed on that surface")
    func accentFillOverASurface() {
        let well = Color.rgb(0x2A, 0x2E, 0x3A)
        let look = RowFillRule(
            page: well, text: Self.dusk.foreground, secondary: Self.dusk.foregroundSecondary,
            accent: Self.dusk.accent, live: false
        ).truecolour()
        let ends = ColorDepth.withCurrent(.truecolor) { Self.dusk.accentFillPulse(over: well) }
        #expect(ends.dim == look.emphasis.dim.color && ends.bright == look.emphasis.top.color)
        #expect(ends.bright != ColorDepth.withCurrent(.truecolor) { Self.dusk.accentFillPulse() }.bright)
    }
}
