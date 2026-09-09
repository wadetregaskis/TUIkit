//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewThatFitsRenderTests.swift
//
//  Buffer-level render audit for ViewThatFits. It measures each
//  candidate against unbounded space and renders the first whose ideal
//  size fits the available space along the configured axes, falling back
//  to the last candidate when none fit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ViewThatFits rendering")
struct ViewThatFitsRenderTests {

    private func ctx(width: Int, height: Int) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Picks the first fitting candidate

    @Test("When the first candidate fits, it is the one rendered")
    func firstCandidateFits() {
        let buffer = renderToBuffer(
            ViewThatFits {
                Text("Short")
                Text("X")
            },
            context: ctx(width: 30, height: 8)
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "Short", "First candidate fits, so it wins")
    }

    // MARK: - Falls back when the first does not fit

    @Test("When the first candidate is too wide, the next fitting one is rendered")
    func fallsBackToNarrower() {
        let buffer = renderToBuffer(
            ViewThatFits {
                Text("ThisIsAVeryLongCandidate")  // 24 wide, won't fit in 6
                Text("tiny")                       // 4 wide, fits
            },
            context: ctx(width: 6, height: 8)
        )
        #expect(buffer.lines[0].stripped == "tiny", "Wide candidate rejected, narrow one chosen")
    }

    @Test("When no candidate fits, the last candidate is used as the fallback")
    func fallsBackToLast() {
        let buffer = renderToBuffer(
            ViewThatFits {
                Text("WideCandidateOne")
                Text("WideCandidateTwo")
            },
            context: ctx(width: 4, height: 8)
        )
        // Neither fits in width 4; the LAST candidate is rendered (and the
        // leaf Text truncates it to the available width with an ellipsis).
        #expect(buffer.lines.count == 1)
        #expect(buffer.width <= 4)
        #expect(buffer.lines[0].stripped == "Wid…", "Last candidate is the fallback, truncated to width")
    }

    // MARK: - Row → column switch (the canonical use)

    @Test("A wide HStack candidate yields to a VStack fallback when too narrow")
    func rowToColumn() {
        let view = ViewThatFits {
            HStack(spacing: 1) { Text("Name"); Text("Size"); Text("Modified") }
            VStack(alignment: .leading) { Text("Name"); Text("Size"); Text("Modified") }
        }

        // Wide: the single-row HStack fits.
        let wide = renderToBuffer(view, context: ctx(width: 40, height: 8))
        #expect(wide.lines.count == 1, "Wide enough: the row layout is chosen")
        #expect(wide.lines[0].stripped == "Name Size Modified")

        // Narrow: the row cannot fit, so the column fallback is chosen.
        // The VStack pads shorter rows to the widest row's width ("Modified"),
        // so compare the trimmed content.
        let narrow = renderToBuffer(view, context: ctx(width: 10, height: 8))
        #expect(narrow.lines.count == 3, "Too narrow: the column layout is chosen")
        #expect(
            narrow.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                == ["Name", "Size", "Modified"]
        )
    }

    // MARK: - A candidate that fills the axis being tested

    @Test("A Spacer in a candidate row does not veto the row")
    func flexibleRowIsNotRejected() {
        let view = ViewThatFits {
            HStack(spacing: 1) { Text("Name"); Spacer(); Text("Size") }
            VStack(alignment: .leading, spacing: 0) { Text("Name"); Text("Size") }
        }
        // The row's rigid content is 10 cells (4 + 4 + two 1-cell gaps) and the
        // Spacer takes the other 30. Measured against the unbounded probe the
        // row reports the probe's own extent as its MINIMUM width — a number no
        // terminal can satisfy — so it used to lose at every width.
        let wide = renderToBuffer(view, context: ctx(width: 40, height: 8))
        #expect(wide.lines.count == 1, "The filling row wins, not the 2-line column")
        #expect(wide.width == 40)
        #expect(wide.lines[0].stripped == "Name" + String(repeating: " ", count: 32) + "Size")
    }

    @Test("A candidate that fills both axes is not rejected by either")
    func fillingCandidateIsAccepted() {
        // A GeometryReader reports `availableWidth` x `availableHeight` and flags
        // both axes flexible, so under the probe it over-reports both at once.
        let buffer = renderToBuffer(
            ViewThatFits {
                GeometryReader { _ in Text("reader") }
                Text("fallback")
            },
            context: ctx(width: 12, height: 3)
        )
        #expect(buffer.lines.count == 3, "The reader fills 12x3, so it fits it")
        #expect(buffer.lines[0].stripped == "reader" + String(repeating: " ", count: 6))
    }

    /// The cost of the rule, stated rather than discovered. `_SliderCore` names a
    /// real minimum for an unspecified proposal (`defaultTrackWidth + chrome`),
    /// but `Slider`'s BODY is an `HStack`, and a stack reports the budget it
    /// distributes — so a bare slider tracks the budget like everything else here
    /// and wins at four cells, clipped, where it used to lose to the `Text`.
    ///
    /// That is the SwiftUI deviation the type doc records, in the smallest form
    /// that shows it. It is here so the trade is pinned by a test and not only by
    /// a comment: if a later change makes a stack report a rigid ideal, this test
    /// says which behaviour changed back.
    @Test("A filling candidate wins even where its rigid content overflows")
    func fillingCandidateWinsAndClips() {
        let buffer = renderToBuffer(
            ViewThatFits(in: .horizontal) {
                Slider(value: .constant(0.5), in: 0...1)
                Text("v")
            },
            context: ctx(width: 4, height: 3)
        )
        #expect(buffer.lines[0].stripped != "v", "the filling candidate is taken, not the Text")
        #expect(buffer.width == 4, "…and clipped to the space there is")
    }

    /// The escape hatch the type doc points at, and the other half of the rule:
    /// bound the candidate and it is rigid again, so it can lose. `.frame(width:)`
    /// makes the reported width the frame's, at both probes, so the comparison
    /// against the real extent is the one it always was.
    ///
    /// Passes before the fix as well as after — it guards against a later
    /// simplification to "flexible implies fits", which would take the slider
    /// here and clip it into four cells.
    @Test("A bounded candidate is rigid again, and can still lose")
    func boundedCandidateStillLoses() {
        let buffer = renderToBuffer(
            ViewThatFits(in: .horizontal) {
                Slider(value: .constant(0.5), in: 0...1).frame(width: 20)
                Text("v")
            },
            context: ctx(width: 4, height: 3)
        )
        #expect(buffer.lines[0].stripped == "v", "20 cells do not fit 4")
    }

    // MARK: - Single-axis constraint

    @Test("ViewThatFits(in:.horizontal) ignores height when choosing")
    func horizontalAxisOnly() {
        // The first candidate is short in width (fits horizontally) but
        // tall; with a tiny height, a both-axes test would reject it, but
        // a horizontal-only test must accept it.
        let buffer = renderToBuffer(
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading) { Text("a"); Text("b"); Text("c") }
                Text("z")
            },
            context: ctx(width: 10, height: 1)
        )
        // Horizontal-only: the 1-wide column fits horizontally, so it is
        // chosen despite being 3 rows tall in a 1-row space (then clamped).
        #expect(buffer.lines.first?.stripped == "a", "First candidate chosen on horizontal fit alone")
    }

    @Test("A both-axes test rejects a candidate that is too tall")
    func bothAxesRejectsTall() {
        let buffer = renderToBuffer(
            ViewThatFits {
                VStack(alignment: .leading) { Text("a"); Text("b"); Text("c") }  // 3 rows
                Text("z")                                                         // 1 row
            },
            context: ctx(width: 10, height: 1)
        )
        // Default both-axes: the 3-row candidate does not fit height 1, so
        // the single-row fallback is chosen.
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "z")
    }

    // MARK: - Single candidate

    @Test("A single candidate is always rendered")
    func singleCandidate() {
        let buffer = renderToBuffer(
            ViewThatFits { Text("alone") },
            context: ctx(width: 20, height: 4)
        )
        #expect(buffer.lines[0].stripped == "alone")
    }

    // MARK: - Squeezed by a parent row

    @Test("A squeezed candidate is chosen from the proposed width, not the context's")
    func squeezedByAParentRow() {
        // Space-less strings on purpose: an over-long word stays on one line
        // (TextWrapping.wrapParagraph), so every height below is exact and a
        // re-wrap cannot be mistaken for the candidate switch under test.
        let fits = ViewThatFits {
            Text("EighteenCellsWide!")  // 18 x 1
            VStack(spacing: 0) { Text("a"); Text("b"); Text("c") }  // 1 x 3
        }

        // The measure a squeezing parent performs: the proposal says 9 cells,
        // the context still says 30 — `_HStackCore.resolvedLayout`'s re-measure
        // of a child narrower than its ideal.
        let squeezed = measureChild(
            fits, proposal: ProposedSize(width: 9, height: nil), context: ctx(width: 30, height: 8))
        #expect(squeezed.height == 3, "9 cells cannot hold the 18-cell row, so the 3-row fallback is measured")
        #expect(squeezed.width == 1)

        // …and the row that does the squeezing draws all three of its rows.
        // 30 - 20 (first column) - 1 (spacing) = 9 cells for the ViewThatFits.
        let row = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("LeftColumnIsTwenty!!")
                fits
            },
            context: ctx(width: 30, height: 8))
        let stripped = row.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(row.lines.count == 3, "the row height came from the candidate that renders, got \(stripped)")
        #expect(stripped == ["LeftColumnIsTwenty!! a", "b", "c"])
    }
}
