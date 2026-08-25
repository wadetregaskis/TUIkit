//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InkCoverageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// `Character.inkCoverage` — the fraction of a cell a character's ink covers.
///
/// The geometric glyphs are exact by construction and pinned as such; text and
/// box drawing are estimates and pinned only so a retuning is a deliberate act.
@Suite("Ink coverage")
struct InkCoverageTests {

    @Test("Block elements are exact by construction")
    func blockElements() {
        #expect(Character("█").inkCoverage == 1)
        #expect(Character("▀").inkCoverage == 0.5)
        #expect(Character("▐").inkCoverage == 0.5)
        #expect(Character("▁").inkCoverage == 0.125)
        #expect(Character("▇").inkCoverage == 0.875)
        #expect(Character("▉").inkCoverage == 0.875)
        #expect(Character("▏").inkCoverage == 0.125)
        #expect(Character("▔").inkCoverage == 0.125)
    }

    @Test("The shades are their names")
    func shades() {
        #expect(Character("░").inkCoverage == 0.25)
        #expect(Character("▒").inkCoverage == 0.5)
        #expect(Character("▓").inkCoverage == 0.75)
    }

    @Test("Quadrants count their quarters")
    func quadrants() {
        #expect(Character("▖").inkCoverage == 0.25)
        #expect(Character("▚").inkCoverage == 0.5)
        #expect(Character("▙").inkCoverage == 0.75)
        #expect(Character("▟").inkCoverage == 0.75)
    }

    @Test("Braille counts its dots")
    func braille() {
        #expect(Character("⠁").inkCoverage == 0.0625)
        #expect(Character("⣿").inkCoverage == 0.5)
        #expect(Character("⠀").inkCoverage == 0)  // U+2800: no dots raised
    }

    @Test("Blanks cover nothing; text and lines are estimates")
    func estimates() {
        #expect(Character(" ").inkCoverage == 0)
        #expect(Character("\u{A0}").inkCoverage == 0)
        #expect(Character("A").inkCoverage == 0.15)
        #expect(Character("日").inkCoverage == 0.15)
        #expect(Character("─").inkCoverage == 0.1)
        #expect(Character("╬").inkCoverage == 0.1)
    }
}
