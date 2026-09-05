//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeOverhangTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The mechanism for a chrome glyph that paints wider than it advances.
///
/// The table it drives is EMPTY — no host's ink has been measured yet, and
/// `Tools/TerminalProbes/overhang_card.py` is what will fill it. So this suite
/// is deliberately in two halves: the rules a filled table must obey (vacuous
/// today, and the reason a mistaken row cannot ship), and the arithmetic that
/// can be wrong *right now* — the gate mask's derivation, which is the one
/// piece here that a reader cannot check by eye and that no empty table would
/// exercise. A constant transcribed once and asserted nowhere is how this
/// project shipped seventeen passing tests against the wrong codepoint.
@Suite("Chrome overhang")
struct ChromeOverhangTests {

    private static let chromeRows = TerminalWidthCorpus.all.filter {
        $0.category == "chrome_key" || $0.category == "chrome_glyph"
    }

    // MARK: - The rules a filled table must obey

    @Test("Every listed codepoint is inside the window the hot paths test for")
    func theTableFitsTheWindow() {
        // `loneTerminalWidth` and `Character.isOverhangingChromeGlyph` spell
        // the window as literals rather than reading the globals, because both
        // are per-scalar paths. This is what stops that duplication drifting.
        // OUTSIDE the loop deliberately: the table ships empty, so a check
        // written inside it never runs — and the drift it guards against
        // (someone moving these globals while the two hot paths keep the old
        // literals) is at its most likely precisely while there is no row to
        // iterate.
        #expect(
            chromeOverhangFloor == 0x2190 && chromeOverhangCeiling == 0x25EF,
            "the window moved: update the literals in `loneTerminalWidth` and in `Character.isOverhangingChromeGlyph`")
        for value in chromeOverhangCodepoints {
            #expect(
                value >= chromeOverhangFloor && value <= chromeOverhangCeiling,
                "U+\(String(value, radix: 16, uppercase: true)) is outside the overhang window")
        }
    }

    @Test("An unidentified host's row comes back byte-identical while the table is empty")
    func theUnidentifiedWalkChangesNothing() {
        // The walk this borrows normalizes as well as compensates, and its own
        // gate admits any line carrying an emoji — so "no row is listed" is not
        // by itself enough to make the unidentified path a no-op. A tone
        // cluster with a redundant VS-16 is the case that proved it: the shared
        // walk strips the selector, which is a rewrite no unmeasured terminal
        // asked for.
        // These two must survive whatever the table holds: no listed codepoint
        // appears in them, so nothing about them is this walk's business.
        for row in ["\u{261D}\u{FE0F}\u{1F3FD}", "\u{1F469}\u{200D}\u{1F680}"] {
            #expect(row.withChromeOverhangCompensation() == row, "the walk rewrote content")
        }
        // And while nothing is listed, so must a row of chrome.
        if chromeOverhangCodepoints.isEmpty {
            for row in ["↵ select", "│ ─ ▶ ●"] {
                #expect(row.withChromeOverhangCompensation() == row)
            }
        }
    }

    @Test("Box Drawing and Block Elements are refused however the table is edited")
    func bordersCanNeverBeWidened() {
        // A two-cell border is not a fix but a second defect — every row inside
        // it loses a column. Refused by the predicate, so a mistaken row is
        // inert rather than catastrophic.
        for value: UInt32 in [0x2500, 0x2502, 0x2588, 0x258C, 0x2590, 0x2592, 0x259F] {
            #expect(!isChromeOverhangCodepoint(value))
            #expect(Character(Unicode.Scalar(value)!).terminalWidth == 1)
        }
    }

    @Test("Every listed codepoint is a glyph the framework actually draws")
    func theTableOnlyNamesChrome() {
        let corpus = Set(Self.chromeRows.compactMap { $0.text.unicodeScalars.first?.value })
        for value in chromeOverhangCodepoints {
            let spelled = String(value, radix: 16, uppercase: true)
            #expect(
                corpus.contains(value),
                "U+\(spelled) is not a chrome corpus row, and the card only shows the corpus")
        }
    }

    @Test("A listed codepoint claims two cells and every host model advances one")
    func theClaimAndTheModelsDisagreeByExactlyOne() {
        for value in chromeOverhangCodepoints {
            let character = Character(Unicode.Scalar(value)!)
            #expect(character.terminalWidth == 2)
            #expect(character.isOverhangingChromeGlyph)
            #expect(character.terminalAppCursorAdvance == 1)
            #expect(character.iTerm2CursorAdvance == 1)
            #expect(character.ghosttyCursorAdvance == 1)
            #expect(character.warpCursorAdvance == 1)
            #expect(character.tmuxCursorAdvance == 1)
            // No switch turns it off: the shortfall is the claim's, not a
            // terminal's, so an explored host cannot opt out and shear.
            #expect(TerminalQuirks().cursorAdvance(of: character) == 1)
        }
    }

    @Test("A listed codepoint reaches the walk and comes out erased and pushed")
    func theWalkClosesTheShortfall() {
        for value in chromeOverhangCodepoints {
            let row = String(Unicode.Scalar(value)!) + " x"
            #expect(row.utf8MayNeedCompensation, "the gate mask does not admit this glyph")
            #expect(
                row.withChromeOverhangCompensation()
                    == "\u{1B}[2X" + String(Unicode.Scalar(value)!) + "\u{1B}[1C" + " x")
        }
    }

    // MARK: - The arithmetic, which an empty table would leave untested

    @Test("The gate mask's bit is the glyph's own second UTF-8 byte")
    func theGateMaskFormulaFindsTheGlyph() {
        // `chromeOverhangGateMask` sets bit `(value >> 6) & 0x3F` and the gate
        // tests bit `secondByte & 0x3F`. Those are the same bit only because a
        // three-byte UTF-8 scalar's second byte is `0x80 | ((value >> 6) &
        // 0x3F)` — asserted here on the glyphs the card is about, whether or
        // not the table has any of them yet.
        for value: UInt32 in [0x2190, 0x21B5, 0x2318, 0x23CE, 0x2423, 0x25B2, 0x25CF, 0x25EF] {
            let bytes = Array(String(Unicode.Scalar(value)!).utf8)
            #expect(bytes.count == 3 && bytes[0] == 0xE2)
            let bit: UInt64 = 1 << UInt64((value >> 6) & 0x3F)
            let spelled = String(value, radix: 16, uppercase: true)
            #expect(
                bit & (1 << UInt64(bytes[1] & 0x3F)) != 0,
                "U+\(spelled): the mask's bit and the gate's bit are not the same bit")
        }
    }

    @Test("The mask is derived from the table and is zero while it is empty")
    func theMaskTracksTheTable() {
        var expected: UInt64 = 0
        for value in chromeOverhangCodepoints { expected |= 1 << UInt64((value >> 6) & 0x3F) }
        #expect(chromeOverhangGateMask == expected)
        #expect(chromeOverhangCodepoints.isEmpty == (chromeOverhangGateMask == 0))
    }

    // MARK: - Nothing has been measured, so nothing is claimed wide

    @Test("Until a card is read, every chrome glyph still claims one cell")
    func nothingIsWidenedByAccident() {
        // The pin that makes filling the table a deliberate act: when a row is
        // added this fails, and whoever adds it says which host, which font and
        // which date in the same commit. Delete the rows here that the card
        // showed overhanging — never the assertion.
        #expect(
            chromeOverhangCodepoints.isEmpty,
            "the overhang table has entries: update this test and Terminal-compatibility.md")
        for row in Self.chromeRows {
            #expect(Character(row.text).terminalWidth == 1, "\(row.id) \(row.text)")
        }
    }
}
