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
}
