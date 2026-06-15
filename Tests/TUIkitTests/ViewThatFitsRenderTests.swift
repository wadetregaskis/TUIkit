//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewThatFitsRenderTests.swift
//
//  Buffer-level render audit for ViewThatFits. It measures each
//  candidate against unbounded space and renders the first whose ideal
//  size fits the available space along the configured axes, falling back
//  to the last candidate when none fit.
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
}
