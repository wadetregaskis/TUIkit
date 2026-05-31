//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnsiAwareScannerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Regression tests for the ANSI-aware scanners when an SGR escape's
/// terminator is immediately followed by an **Extend** scalar (a lone
/// Fitzpatrick modifier, VS-16, …).
///
/// Swift's grapheme clustering fuses the terminator letter and the
/// Extend scalar into one `Character` (`"m" + 🏻`), so the old
/// `Character`-level "skip the final byte" step swallowed the modifier
/// as part of the escape and mis-measured everything after it. The
/// scanners now segment at the Unicode-scalar level, so an SGR prefix is
/// transparent to visible-content handling — these tests assert each
/// scanner produces the same visible result with and without the SGR.
@Suite("ANSI-aware scanners: Extend scalar after SGR")
struct AnsiAwareScannerTests {

    /// red SGR, then a lone Fitzpatrick modifier (width 2), then `X`.
    private let sgr = "\u{1B}[31m\u{1F3FB}X"
    /// The same visible content without the colour code (no fusion).
    private let bare = "\u{1F3FB}X"

    @Test("Root cause: an SGR terminator fuses with a following Extend scalar")
    func graphemeClusteringRootCause() {
        // Six characters: [ESC] [ '[' ] [ '3' ] [ '1' ] [ 'm'+🏻 ] [ 'X' ]
        #expect(Array(sgr).count == 6)
        let fused: Character = "m\u{1F3FB}"
        #expect(fused.unicodeScalars.count == 2)
        #expect(fused.isLetter)
    }

    @Test("ansiAwarePrefix stops at the modifier instead of over-including")
    func prefixDoesNotOverInclude() {
        let prefix = sgr.ansiAwarePrefix(visibleCount: 2)
        #expect(prefix.strippedLength == 2)
        #expect(!prefix.contains("X"))
        #expect(prefix.stripped == bare.ansiAwarePrefix(visibleCount: 2).stripped)
    }

    @Test("ansiAwarePrefixForTerminalApp stops at the modifier")
    func terminalAppPrefixDoesNotOverInclude() {
        let prefix = sgr.ansiAwarePrefixForTerminalApp(visibleCount: 2)
        #expect(prefix.strippedLength == 2)
        #expect(!prefix.contains("X"))
    }

    @Test("truncatedToWidth honours the requested width across the SGR boundary")
    func truncateHonoursWidth() {
        #expect(sgr.truncatedToWidth(2, mode: .tail).strippedLength <= 2)
    }

    @Test("ansiAwareSuffix drops the modifier's cells, not the whole string")
    func suffixDropsCorrectCells() {
        let suffix = sgr.ansiAwareSuffix(droppingVisible: 2)
        // 🏻 is 2 cells; dropping 2 leaves "X".
        #expect(suffix.stripped == "X")
        #expect(suffix.stripped == bare.ansiAwareSuffix(droppingVisible: 2).stripped)
    }

    @Test("ansiSGRContextAndCleanSuffix keeps the modifier and the colour")
    func sgrContextKeepsModifierAndColour() {
        let result = sgr.ansiSGRContextAndCleanSuffix(from: 0)
        #expect(result?.stripped == "\u{1F3FB}X")
        // Scalar-level check: the result's own trailing `m` fuses with the
        // modifier, so a Character-based `contains` wouldn't match even
        // though the colour scalars are present.
        #expect(result?.unicodeScalars.starts(with: "\u{1B}[31m".unicodeScalars) == true)
    }

    // The remaining two scanners share the same Character-level skip but
    // are NOT affected by this fusion: a lone Fitzpatrick has equal cell
    // width and Terminal.app cursor advance, so nothing is mis-handled.
    // These tests pin that down (prove the bug does not exist for them).

    @Test("containsTerminalAppCursorAdvanceQuirk is unaffected by an SGR before a lone modifier")
    func quirkDetectorUnaffected() {
        #expect(sgr.containsTerminalAppCursorAdvanceQuirk == bare.containsTerminalAppCursorAdvanceQuirk)
        #expect(!sgr.containsTerminalAppCursorAdvanceQuirk)  // lone 🏻 has advance == width
    }

    @Test("withTerminalAppCursorCompensation preserves content past an SGR")
    func compensationUnaffected() {
        #expect(sgr.withTerminalAppCursorCompensation().stripped == "\u{1F3FB}X")
    }

    // Control: a regional-indicator flag isn't Extend, so it never fused
    // and already worked — guards against a regression in the common path.
    @Test("A regional-indicator flag after an SGR is measured correctly")
    func regionalIndicatorIsCorrect() {
        let prefix = "\u{1B}[31m\u{1F1E6}\u{1F1E7}".ansiAwarePrefix(visibleCount: 2)
        #expect(prefix.strippedLength == 2)
    }

    @Test("Plain text after an SGR is prefixed at the correct width")
    func plainPrefixIsCorrect() {
        #expect("\u{1B}[31mABC".ansiAwarePrefix(visibleCount: 2).strippedLength == 2)
    }
}
