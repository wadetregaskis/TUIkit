//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineSpacingTests.swift
//
//  `.lineSpacing(_:)` — blank rows between the wrapped lines of a `Text`.
//
//  The whole hazard here is measure/render parity. The measure adds the gap
//  rows to the height it reports; the render both draws them and subtracts them
//  from the lines it may lay out. If those disagree, spacing either reserves
//  rows nothing fills or pushes the last line past the space the parent gave —
//  which is exactly how the LazyVGrid bug behaved.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Line spacing")
struct LineSpacingTests {

    private func lines(_ view: some View, width: Int = 12, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map {
                $0.stripped.replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression)
            }
    }

    private func size(_ view: some View, width: Int = 12, height: Int = 20) -> ViewSize {
        measureChild(
            view, proposal: ProposedSize(width: width, height: height),
            context: makeBareRenderContext(width: width, height: height))
    }

    /// Wraps to THREE lines at width 12: "alpha beta" / "gamma delta" /
    /// "epsilon". Three matters — with only two, a budget test cannot tell a
    /// row budget from a line budget, because both admit the whole text.
    private let prose = "alpha beta gamma delta epsilon"

    // MARK: - Row arithmetic

    /// Gaps go BETWEEN lines — the same n/n−1 rule the grid tracks use, and the
    /// same place it is easy to be off by one.
    @Test("n lines occupy n + (n-1) x spacing rows")
    func displayRows() {
        #expect(LineSpacingRows.displayRows(forLines: 0, spacing: 1) == 0)
        #expect(LineSpacingRows.displayRows(forLines: 1, spacing: 5) == 1, "no gap after the last")
        #expect(LineSpacingRows.displayRows(forLines: 3, spacing: 0) == 3)
        #expect(LineSpacingRows.displayRows(forLines: 3, spacing: 1) == 5)
        #expect(LineSpacingRows.displayRows(forLines: 3, spacing: 2) == 7)
    }

    @Test("the inverse agrees with it at every size")
    func rowArithmeticRoundTrips() {
        for spacing in 0...3 {
            for lineCount in 1...12 {
                let rows = LineSpacingRows.displayRows(forLines: lineCount, spacing: spacing)
                #expect(
                    LineSpacingRows.lines(fittingRows: rows, spacing: spacing) == lineCount,
                    "\(lineCount) lines at spacing \(spacing) occupy \(rows) rows")
                // …and one row short is one line short (or still one line).
                let fewer = LineSpacingRows.lines(fittingRows: rows - 1, spacing: spacing)
                #expect(fewer <= lineCount)
            }
        }
    }

    @Test("a positive budget always fits at least one line")
    func neverZeroLines() {
        #expect(LineSpacingRows.lines(fittingRows: 1, spacing: 9) == 1)
        #expect(LineSpacingRows.lines(fittingRows: 0, spacing: 1) == 0)
    }

    // MARK: - Rendering

    @Test("spacing puts blank rows between lines and not after the last")
    func rendersGaps() {
        let drawn = lines(Text(verbatim: prose).lineSpacing(1))
        #expect(drawn[0] == "alpha beta", "\(drawn)")
        #expect(drawn[1].isEmpty)
        #expect(drawn[2] == "gamma delta", "\(drawn)")
        #expect(drawn[3].isEmpty)
        #expect(drawn[4] == "epsilon", "\(drawn)")
        // Nothing after the final line: the height stops at the text.
        #expect(drawn.count == 5 || drawn[5].isEmpty)
    }

    @Test("a single line is unaffected however large the spacing")
    func singleLineUnaffected() {
        let drawn = lines(Text(verbatim: "solo").lineSpacing(4))
        #expect(drawn[0] == "solo")
        #expect(size(Text(verbatim: "solo").lineSpacing(4)).height == 1)
    }

    @Test("no spacing renders exactly as before")
    func zeroIsUnchanged() {
        #expect(lines(Text(verbatim: prose)) == lines(Text(verbatim: prose).lineSpacing(0)))
    }

    @Test("negative spacing clamps to none")
    func negativeClamps() {
        #expect(lines(Text(verbatim: prose).lineSpacing(-3)) == lines(Text(verbatim: prose)))
    }

    // MARK: - Parity

    /// Parity, in the two halves that are actually true.
    ///
    /// `Text.sizeThatFits` reports the height it WANTS and has always ignored
    /// the height proposal — visible at spacing 0, where it measures 3 into a
    /// 2-row budget. The parent decides what it gets. So the equality only
    /// holds with room to spare.
    @Test("with room to spare, the measure is the rows drawn")
    func measureMatchesRenderWhenUnconstrained() {
        for spacing in 0...3 {
            let view = Text(verbatim: prose).lineSpacing(spacing)
            let context = makeBareRenderContext(width: 12, height: 40)
            let measured = measureChild(
                view, proposal: ProposedSize(width: 12, height: 40), context: context)
            let drawn = renderToBuffer(view, context: context)
            #expect(
                measured.height == drawn.height,
                "spacing \(spacing): measured \(measured.height), drew \(drawn.height)")
        }
    }

    /// The half that bites when the budget does: a spaced block ENDS at its
    /// last line, never on a trailing gap. That is what goes wrong if the
    /// render treats the row budget as a line budget — it lays out one line too
    /// many, the overflow is clipped, and what survives is a blank row hanging
    /// off the bottom.
    @Test("a clipped block never ends on a spacing gap")
    func neverEndsOnAGap() {
        for spacing in 0...3 {
            for height in 1...8 {
                let view = Text(verbatim: prose).lineSpacing(spacing)
                let drawn = renderToBuffer(
                    view, context: makeBareRenderContext(width: 12, height: height))
                let painted = drawn.lines.filter {
                    !$0.stripped.trimmingCharacters(in: .whitespaces).isEmpty
                }
                #expect(drawn.height <= height, "spacing \(spacing): drew past \(height) rows")
                #expect(
                    drawn.height
                        == LineSpacingRows.displayRows(
                            forLines: painted.count, spacing: spacing),
                    "spacing \(spacing) in \(height) rows: \(painted.count) lines, drew \(drawn.height)")
            }
        }
    }

    // MARK: - Interaction with lineLimit

    /// A limit counts LINES, as in SwiftUI — not rows on screen. Two lines at
    /// spacing 1 are two lines and three rows.
    @Test("lineLimit counts lines, and spacing expands what survives it")
    func limitCountsLines() {
        let view = Text(verbatim: prose).lineLimit(2).lineSpacing(1)
        let drawn = lines(view)
        let painted = drawn.filter { !$0.isEmpty }
        #expect(painted.count == 2, "two lines survive the limit: \(drawn)")
        #expect(size(view).height == 3, "…occupying three rows")
        #expect(drawn[1].isEmpty, "with the gap between them: \(drawn)")
    }

    // MARK: - Cascade

    @Test("spacing set on a container reaches the text inside")
    func cascades() {
        let drawn = lines(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: prose)
            }
            .lineSpacing(1))
        #expect(drawn[0] == "alpha beta", "\(drawn)")
        #expect(drawn[1].isEmpty, "\(drawn)")
    }

    @Test("the innermost spacing wins")
    func innermostWins() {
        let drawn = lines(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: prose).lineSpacing(0)
            }
            .lineSpacing(2))
        #expect(drawn[0] == "alpha beta", "\(drawn)")
        #expect(drawn[1] == "gamma delta", "the inner zero won: \(drawn)")
    }
}
