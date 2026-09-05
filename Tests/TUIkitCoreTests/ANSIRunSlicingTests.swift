//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIRunSlicingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// `ansiAwareSlices(runWidths:)` against the function it exists to amortise.
///
/// The one-pass cut has no rules of its own: every piece must be exactly what
/// `ansiAwareSlice(visibleStart:visibleCount:)` returns for that run. So the
/// test states that and nothing else, over rows chosen for the things a cut can
/// get wrong — an SGR run that spans a cut, a hyperlink opened before one and
/// closed after, a wide glyph straddling one, a row shorter than the cuts, and
/// a row that is nothing but escapes.
@Suite("ANSI run slicing")
struct ANSIRunSlicingTests {

    private let rows: [String] = [
        "plain ascii row of text",
        "\u{1B}[31mred\u{1B}[0m then \u{1B}[1;32mbold green\u{1B}[0m tail",
        "\u{1B}[38;2;10;20;30mtruecolor\u{1B}[39m rest",
        "wide 漢字 glyphs 日本語 here",
        "emoji 👍🏽 and ✂️ mixed",
        "\u{1B}]8;;https://example.com\u{1B}\\linked text\u{1B}]8;;\u{1B}\\ after",
        "\u{1B}]8;;https://example.com\u{1B}\\link never closed",
        "\u{1B}[1m\u{1B}[4m\u{1B}[7m",
        "",
        "x",
        "combining e\u{0301}clair and ZWJ 👩‍👩‍👧 family",
    ]

    /// Partitions of a row's width to cut at, including the degenerate ones.
    private func partitions(of width: Int) -> [[Int]] {
        guard width > 0 else { return [[0], [0, 0], [3]] }
        var out: [[Int]] = [
            [width],
            [Int](repeating: 1, count: width),  // one run per column: the gradient case
            [0, width],
            [width, 0],
        ]
        if width >= 2 { out.append([width / 2, width - width / 2]) }
        if width >= 3 { out.append([1, width - 2, 1]) }
        if width >= 4 { out.append([2, 1, width - 4, 1]) }
        // Past the end of the row, which a caller pads to avoid but the function
        // must still answer for.
        out.append([width, 3])
        out.append([width + 2])
        return out
    }

    @Test("every piece matches the single-run slice")
    func matchesSingleSlice() {
        for row in rows {
            let width = row.strippedLength
            for widths in partitions(of: width) {
                let batched = row.ansiAwareSlices(runWidths: widths)
                var start = 0
                var oneAtATime: [String] = []
                for runWidth in widths {
                    oneAtATime.append(
                        row.ansiAwareSlice(visibleStart: start, visibleCount: runWidth))
                    start += max(0, runWidth)
                }
                #expect(
                    batched == oneAtATime,
                    """
                    cutting \(row.debugDescription) at \(widths) disagrees with slicing it \
                    one run at a time:
                    batched: \(batched.map(\.debugDescription))
                    singly:  \(oneAtATime.map(\.debugDescription))
                    """)
            }
        }
    }

    /// The property the caller depends on: the pieces put the row back together
    /// at its full visible width, whatever the cuts.
    @Test("the pieces cover the row's visible width")
    func piecesCoverTheRow() {
        for row in rows where !row.isEmpty {
            let width = row.strippedLength
            guard width > 1 else { continue }
            for widths in partitions(of: width) where widths.reduce(0, +) == width {
                let pieces = row.ansiAwareSlices(runWidths: widths)
                let visible = pieces.map(\.strippedLength).reduce(0, +)
                #expect(
                    visible == width,
                    "cutting \(row.debugDescription) at \(widths) yields \(visible) cells, not \(width)")
            }
        }
    }
}
