//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalQuirksLiteralTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The quirks explorer writes a session up as the Swift value that produced
/// it. A hand-written list in the explorer covered eleven of the fourteen
/// properties and reported a session that needed only one of the other three
/// as "nothing needed"; the literal is derived beside the properties now.
@Suite("TerminalQuirks as a literal")
struct TerminalQuirksLiteralTests {

    @Test("Every property that is set is named")
    func everyPropertyIsNamed() {
        let all = TerminalQuirks(
            vs16Pictographs: true, barePictographs: true, vs15ChromeGlyphs: true,
            loneRegionalIndicators: true, flagPairs: true, keycaps: .underAdvances,
            planeSixteenPUA: true, preUnicode16WidthTable: true,
            zwjSequences: true, tagFlags: true, storesWideComposites: true,
            skinTones: .separate, mergesTonesOnTextBases: true, erasesUnderGlyphs: true)
        let literal = all.swiftLiteral
        for name in [
            "vs16Pictographs", "barePictographs", "vs15ChromeGlyphs", "loneRegionalIndicators",
            "flagPairs", "keycaps", "planeSixteenPUA", "preUnicode16WidthTable", "zwjSequences",
            "tagFlags", "storesWideComposites", "skinTones", "mergesTonesOnTextBases", "erasesUnderGlyphs",
        ] {
            #expect(literal.contains(name + ":"), "\(name) is missing from \(literal)")
        }
        #expect(literal.hasPrefix("TerminalQuirks("))
    }

    @Test("Nothing needed is said only when nothing is set")
    func nothingNeededOnlyWhenEmpty() {
        #expect(TerminalQuirks().swiftLiteral.contains("nothing needed"))
        var one = TerminalQuirks()
        one.zwjSequences = true
        #expect(one.swiftLiteral == "TerminalQuirks(zwjSequences: true)")
        one = TerminalQuirks()
        one.storesWideComposites = true
        #expect(!one.swiftLiteral.contains("nothing needed"))
    }
}
