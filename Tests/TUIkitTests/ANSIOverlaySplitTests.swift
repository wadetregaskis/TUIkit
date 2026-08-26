//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIOverlaySplitTests.swift
//
//  `ansiOverlaySplit` fuses four separate ANSI-aware scans into one so that
//  compositing a child into a row stops rescanning the whole row four times.
//  A fused implementation is only worth having if it is INDISTINGUISHABLE from
//  the four it replaces, so that is what these check — differentially, over the
//  awkward cases (wide characters straddling either split point, escapes either
//  side of both boundaries, empty and past-the-end columns) rather than a
//  handful of hand-picked strings.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("ANSI overlay split")
struct ANSIOverlaySplitTests {

    /// Every field must equal the helper it replaces, for every split point.
    private func assertMatchesHelpers(_ line: String, _ label: String) {
        let width = line.strippedLength
        // Past the ends as well as inside: an overlay can be placed at 0, and
        // can extend beyond the line it is drawn into.
        for prefixColumns in -1...(width + 2) {
            for dropColumns in -1...(width + 2) {
                let fused = line.ansiOverlaySplit(
                    prefixColumns: prefixColumns, suffixDropColumns: dropColumns)
                let (expectedPrefix, expectedPrefixWidth) =
                    line.ansiAwarePrefixWithWidth(visibleCount: prefixColumns)
                let expectedSuffix = line.ansiAwareSuffix(droppingVisible: dropColumns)

                #expect(
                    fused.prefix == expectedPrefix,
                    """
                    \(label) prefix at \(prefixColumns): \
                    \(fused.prefix.debugDescription) != \(expectedPrefix.debugDescription)
                    """)
                #expect(
                    fused.prefixWidth == expectedPrefixWidth,
                    "\(label) prefixWidth at \(prefixColumns)")
                #expect(
                    fused.suffix == expectedSuffix,
                    """
                    \(label) suffix dropping \(dropColumns): \
                    \(fused.suffix.debugDescription) != \(expectedSuffix.debugDescription)
                    """)
                #expect(
                    fused.suffixWidth == expectedSuffix.strippedLength,
                    "\(label) suffixWidth dropping \(dropColumns)")
                #expect(
                    fused.styleBeforeSuffix == line.ansiStateBefore(visibleColumn: dropColumns),
                    "\(label) styleBeforeSuffix at \(dropColumns)")
                #expect(fused.totalWidth == width, "\(label) totalWidth")
            }
        }
    }

    @Test("Plain text matches the helpers at every split point")
    func plainText() {
        assertMatchesHelpers("hello world", "plain")
        assertMatchesHelpers("", "empty")
        assertMatchesHelpers("x", "single")
    }

    @Test("Styled text matches, including escapes either side of both splits")
    func styledText() {
        assertMatchesHelpers("\u{1B}[31mred\u{1B}[0m plain", "leading style")
        assertMatchesHelpers("plain \u{1B}[1mbold\u{1B}[0m", "trailing style")
        assertMatchesHelpers("\u{1B}[44ma\u{1B}[31mb\u{1B}[0mc\u{1B}[4md", "interleaved")
        assertMatchesHelpers("\u{1B}[0m\u{1B}[7m inverted \u{1B}[0m", "inverted chip")
    }

    /// The case the doc comments on `insertOverlay` single out: a wide glyph
    /// straddling a split point cannot be shown whole, so the splitters drop it
    /// and the caller pads the shortfall. The fused scan has to drop it in
    /// exactly the same place.
    @Test("Wide characters straddling either split match")
    func wideCharacters() {
        assertMatchesHelpers("ab😀cd", "emoji mid")
        assertMatchesHelpers("😀😀😀", "all wide")
        assertMatchesHelpers("日本語テキスト", "CJK")
        assertMatchesHelpers("\u{1B}[32m日\u{1B}[0m本x😀", "styled wide mix")
        assertMatchesHelpers("a\u{FE0F}b", "variation selector")
    }

    /// A seeded sweep, so the equivalence is pinned over shapes nobody thought
    /// to hand-write.
    @Test("Randomised lines match the helpers")
    func randomisedSweep() {
        let pieces = [
            "a", "bb", "😀", "日", "\u{1B}[31m", "\u{1B}[0m", "\u{1B}[1m", " ", "\u{1B}[44m",
        ]
        var seed: UInt64 = 0x5715_2025
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(pieces.count))
        }
        for sample in 0..<40 {
            var line = ""
            for _ in 0..<(3 + sample % 7) { line += pieces[next()] }
            assertMatchesHelpers(line, "random #\(sample)")
        }
    }
}
