//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldScalingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A text field's render must not be quadratic in the length of its text.
///
/// `displayCharacter` used to take an INDEX, resolved as
/// `text[text.index(text.startIndex, offsetBy: index)]` — an O(index) grapheme
/// walk — and three loops call it once per character. So a field cost O(n²)
/// grapheme steps in its own text on every render, and again on every mouse
/// event, and so once per motion of a drag.
///
/// The shape of this file is `FrameBufferCombineScalingTests`': measure the
/// same work at two sizes and bound the RATIO, which is what distinguishes the
/// complexity class from the constant. A timing assertion cannot be tight, so
/// the bound sits far from both answers rather than close to the right one.
@MainActor
@Suite("A text field's render scales with its text")
struct TextFieldScalingTests {

    /// The width scan alone — the loop that is called for both the widths and
    /// the emit, and the one with no early exit.
    private func scanCost(characters: Int) -> TimeInterval {
        let text = String(repeating: "a", count: characters)
        return bestCPUSeconds {
            let widths = TextFieldContentRenderer.displayCellWidths(
                of: text, displayCharacter: { $0 })
            precondition(widths.count == characters)
        }
    }

    @Test("Measuring a field's cell widths stays sub-quadratic in its length")
    func widthScanIsNotQuadratic() {
        let small = scanCost(characters: 1_000)
        let large = scanCost(characters: 8_000)
        let ratio = large / small
        #expect(
            ratio < 20,
            """
            the width scan grew \(String(format: "%.1f", ratio))× for 8× the text \
            (linear ≈ 8×, quadratic ≈ 64×) — the display mapping is being resolved \
            by index again, which walks the string from the start for every character.
            """)
    }

    /// The mapping is the whole contract, so it is asserted rather than assumed:
    /// a field draws what was typed, a secure field draws bullets, and the
    /// prompt is never masked.
    @Test("The display mapping still maps")
    func displayMappingIsUnchanged() {
        let plain = TextFieldContentRenderer.displayCellWidths(
            of: "ab", displayCharacter: { $0 })
        #expect(plain == [1, 1])
        // A wide character still measures two cells through the mapping.
        let wide = TextFieldContentRenderer.displayCellWidths(
            of: "漢字", displayCharacter: { $0 })
        #expect(wide == [2, 2])
        // A secure field maps every character to a one-cell bullet, so a wide
        // one stops being wide — which is the point of masking.
        let masked = TextFieldContentRenderer.displayCellWidths(
            of: "漢字", displayCharacter: { _ in TerminalSymbols.maskBullet })
        #expect(masked == [1, 1])
    }
}
