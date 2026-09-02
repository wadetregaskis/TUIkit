//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImagePlaceholderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// U+10EFFF sits inside the Plane-16 Private Use Area, which this framework
/// treats as SF Symbols — painted two cells, advanced one, compensated with
/// `ECH` + glyph + `CUF`. The placeholder is not a glyph and must escape all
/// of that.
///
/// The failure this pins is deliberately unlike a crash: an image drawn one
/// cell further right on every column looks like a picture in a slightly wrong
/// place, which is why every arm is asserted separately rather than through
/// one end-to-end render.
@Suite("The image placeholder is one ordinary cell")
struct TerminalImagePlaceholderWidthTests {

    /// The codepoint, spelled once so a typo in the tests cannot agree with a
    /// typo in the source.
    static let placeholder: Character = "\u{10EFFF}"

    /// An SF Symbol, for the arm that must NOT change.
    static let symbol: Character = "\u{100001}"

    @Test("One cell, where an SF Symbol claims two")
    func widthIsOne() {
        #expect(Self.placeholder.terminalWidth == 1)
        #expect(Self.symbol.terminalWidth == 2, "the general Plane-16 rule still stands")
    }

    /// Row and column ride in combining diacritics, so a real placeholder cell
    /// is never a lone scalar — and a cluster is measured by its own path.
    @Test("Still one cell carrying its row and column")
    func clusterWithDiacriticsIsOne() {
        let cell = "\u{10EFFF}\u{0305}\u{030D}"
        #expect(cell.strippedLength == 1)
        // A whole row of them measures its cell count, which is what every
        // layout, pad and clip decision in the framework will ask.
        let row = String(repeating: cell, count: 12)
        #expect(row.strippedLength == 12)
    }

    @Test("Every host advances it by one, so nothing is owed")
    func noHostOwesCompensation() {
        let placeholder = Self.placeholder
        #expect(placeholder.terminalAppCursorAdvance == 1)
        #expect(placeholder.iTerm2CursorAdvance == 1)
        #expect(placeholder.ghosttyCursorAdvance == 1)
        #expect(placeholder.warpCursorAdvance == 1)
        #expect(placeholder.tmuxCursorAdvance == 1)
        // Each equals the claim, which is the property that matters: a
        // compensation is emitted for the DIFFERENCE, so agreeing means the
        // walks leave these cells alone.
        for advance in [
            placeholder.terminalAppCursorAdvance, placeholder.iTerm2CursorAdvance,
            placeholder.ghosttyCursorAdvance, placeholder.warpCursorAdvance,
            placeholder.tmuxCursorAdvance,
        ] {
            #expect(advance == placeholder.terminalWidth)
        }
    }

    @Test("The SF Symbol under-advance is untouched")
    func symbolStillUnderAdvances() {
        let symbol = Self.symbol
        #expect(symbol.terminalAppCursorAdvance == 1)
        #expect(symbol.iTerm2CursorAdvance == 1)
        #expect(symbol.ghosttyCursorAdvance == 1)
        #expect(symbol.warpCursorAdvance == 1)
        #expect(symbol.tmuxCursorAdvance == 1)
        #expect(symbol.terminalWidth == 2, "…against a claim of two, which is the defect")
    }

    /// The switch-driven model an unmeasured terminal is explored with has to
    /// agree with the five measured ones, or a custom quirk set would
    /// compensate a cell the real hosts do not.
    @Test("The quirk switch exempts it too")
    func quirkSwitchExemptsIt() {
        let quirks = TerminalQuirks(planeSixteenPUA: true)
        #expect(quirks.cursorAdvance(of: Self.placeholder) == 1)
        #expect(quirks.cursorAdvance(of: Self.symbol) == 1)
        #expect(TerminalQuirks().cursorAdvance(of: Self.placeholder) == 1)
    }

    /// The end-to-end arm: what the writer actually emits. A compensated
    /// Plane-16 glyph comes out as `ECH` + glyph + `CUF`; a placeholder row
    /// must come out unchanged.
    @Test("The compensation walks pass a placeholder row through")
    func walksLeaveTheRowAlone() {
        let row = String(repeating: "\u{10EFFF}\u{0305}\u{030D}", count: 4)
        #expect(row.withTerminalAppCursorCompensation() == row)
        #expect(row.withITerm2CursorCompensation() == row)
        #expect(row.withGhosttyCursorCompensation() == row)
        #expect(row.withWarpCursorCompensation() == row)
        #expect(row.withTmuxCursorCompensation() == row)
        // The same walk over an SF Symbol still rewrites it, so the test above
        // is measuring the exemption rather than a walk that does nothing.
        #expect(String(Self.symbol).withTerminalAppCursorCompensation() != String(Self.symbol))
    }

    /// Hazard 2 of `Documentation/Terminal graphics protocols.md`, pinned as a
    /// decision rather than left as an accident: a row carrying an image
    /// declines the cell-span diff and is rewritten whole.
    ///
    /// A span diff would be free to rewrite four cells out of the middle of an
    /// image row, and a placeholder written out of sequence — after a cursor
    /// jump, with the run-length elision in play — no longer names the part of
    /// the picture it stands for.
    @Test("An image row declines the cell-span diff")
    func imageRowDeclinesSpanDiff() {
        let row = String(repeating: "\u{10EFFF}\u{0305}\u{030D}", count: 4)
        #expect(ANSIRowCells(decomposing: row, width: 4) == nil)
        // Bare placeholders — the run-length form — decline for the same
        // reason, and this is the arm that would silently pass if the
        // exemption lived only in the width table.
        #expect(ANSIRowCells(decomposing: String(repeating: "\u{10EFFF}", count: 4), width: 4) == nil)
        // A plain row still decomposes, so the assertions above are measuring
        // the placeholder rather than a differ that declines everything.
        #expect(ANSIRowCells(decomposing: "abcd", width: 4) != nil)
    }
}
