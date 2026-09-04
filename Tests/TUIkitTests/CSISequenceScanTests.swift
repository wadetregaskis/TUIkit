//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CSISequenceScanTests.swift
//
//  Every walk that skips an escape has to agree about where the escape ends.
//  The cursor-compensation file carried five copies of a rule that accepted
//  only digits and `;` between the `[` and the terminator — a rule this
//  codebase already documents as wrong, because it stops at the `?` of
//  `ESC[?25l` and hands the rest to whatever counts visible cells.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("CSI sequence scanning")
struct CSISequenceScanTests {

    private func end(of text: String) -> Int {
        let index = text.escapeSequenceEnd(from: text.startIndex)
        return text.distance(from: text.startIndex, to: index)
    }

    @Test("An ordinary SGR sequence ends after its terminator")
    func plainSGR() {
        #expect(end(of: "\u{1B}[0m") == 4)
        #expect(end(of: "\u{1B}[38;5;22mx") == 10)
        #expect(end(of: "\u{1B}[mx") == 3)
    }

    @Test("A private-parameter sequence is consumed whole")
    func privateParameters() {
        // The case the old rule leaked: `?` is a private marker (0x3F), not a
        // digit, so the scan stopped and "?25l" became visible text.
        #expect(end(of: "\u{1B}[?25l") == 6)
        #expect(end(of: "\u{1B}[?1049h") == 8)
        // An intermediate byte (the space of DECSCUSR) is a body byte too.
        #expect(end(of: "\u{1B}[2 q") == 5)
    }

    @Test("A lone escape, or one not introducing a CSI, consumes only itself")
    func notACSI() {
        #expect(end(of: "\u{1B}") == 1)
        #expect(end(of: "\u{1B}x") == 1)
    }

    /// `ESC ( B` is a charset designation: intermediates (0x20…0x2F), then
    /// one final. The measurers always consumed it as zero cells; this walker
    /// stopped after the ESC and left `(B` to be counted as two — a pin that
    /// used to read `== 1` here was pinning that disagreement.
    @Test("An nF escape — intermediates then a final — is consumed whole")
    func nFEscape() {
        #expect(end(of: "\u{1B}(B") == 3)
        #expect(end(of: "\u{1B}%G") == 3)
        #expect(end(of: "\u{1B} F") == 3)
        #expect(end(of: "\u{1B}(") == 2, "unterminated: stops at the end")
    }

    @Test("An unterminated sequence stops at the end rather than running off it")
    func unterminated() {
        #expect(end(of: "\u{1B}[38;5") == 6)
        #expect(end(of: "\u{1B}[") == 2)
    }

    // MARK: - What the callers do with it

    @Test("A cursor-hide sequence is not mistaken for visible text")
    func compensationSkipsPrivateSequences() {
        // `containsTerminalAppCursorAdvanceQuirk` walks the row looking for a
        // glyph whose cursor advance differs from its width. Under the old
        // rule the `?25l` of a cursor-hide arrived as four ordinary characters
        // — harmless for THIS predicate, since none of them is a wide glyph,
        // and not harmless for the rewriters that share the scan, which copied
        // the escape and then re-scanned its tail as content.
        let hidden = "\u{1B}[?25l\u{1B}[0mplain"
        #expect(!hidden.containsTerminalAppCursorAdvanceQuirk)
        // The rewriters must leave a row with no wide glyphs exactly as it was,
        // private sequences and all.
        #expect(hidden.withTerminalAppCursorCompensation() == hidden)
        #expect(hidden.withITerm2CursorCompensation() == hidden)
        #expect(hidden.withGhosttyCursorCompensation() == hidden)
    }

    @Test("A row mixing a private sequence with a wide glyph still compensates it")
    func compensationStillSeesWideGlyphs() {
        let row = "\u{1B}[?25l" + "漢" + "\u{1B}[0m"
        // The glyph is still found — skipping the escape correctly must not
        // mean skipping past the content after it.
        #expect(row.stripped == "漢")
    }
}
