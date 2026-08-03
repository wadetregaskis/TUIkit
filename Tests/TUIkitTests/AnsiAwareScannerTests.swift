//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnsiAwareScannerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

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

    /// The same fused-cluster hazard in the leading-state extractor: a
    /// combining mark opening the visible text fuses with the terminator
    /// (`…m` + U+0308 is one `Character`), and the character-level scan
    /// consumed the mark into the "styling" prefix — vanishing it from the
    /// text on the reassembly path (OverlayLayer's left-edge clip pad).
    @Test("leadingANSISequences stops at the terminator scalar, not the cluster")
    func leadingSequencesStopAtTerminatorScalar() {
        let fused = "\u{1B}[31m\u{0308}x"
        let (prefix, remainder) = fused.leadingANSISplit()
        #expect(prefix == "\u{1B}[31m", "the combining mark is TEXT, not styling")
        #expect(remainder.unicodeScalars.first == "\u{0308}", "the mark stays with the text")
        #expect(fused.leadingANSISequences() == "\u{1B}[31m")

        // The common cases are unchanged: multiple sequences, then text.
        let plain = "\u{1B}[31m\u{1B}[1mAbc"
        #expect(plain.leadingANSISequences() == "\u{1B}[31m\u{1B}[1m")
        #expect(plain.leadingANSISplit().remainder == "Abc")
        #expect("Abc".leadingANSISequences().isEmpty)
    }

    @Test("Tail truncation closes the style run it cuts")
    func tailTruncationClosesTheRunItCuts() {
        let reset = "\u{1B}[0m"
        let styled = "\u{1B}[4mSupercalifragilistic\(reset)"
        let cut = styled.truncatedToWidth(10)
        // The cut discards every later segment, the run's own reset included —
        // and callers append PLAIN padding after this string, which the still
        // open underline then painted across.
        #expect(cut.hasSuffix(reset))
        #expect(cut.stripped == "Supercali…", "content and width are unchanged")
        #expect(cut.strippedLength == 10)

        // Conditional, both ways: plain text gains nothing…
        #expect("Supercalifragilistic".truncatedToWidth(10) == "Supercali…")
        // …and neither does a cut that lands after the run already closed.
        let mixed = "\u{1B}[4mAB\(reset) plain tail text"
        #expect(!mixed.truncatedToWidth(8).hasSuffix(reset))
    }
}
