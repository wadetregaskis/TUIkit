//  🖥️ TUIKit — Terminal UI Kit for Swift
//  HStackRenderTests.swift
//
//  Buffer-level render audit for HStack.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("HStack rendering")
struct HStackRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Default arrangement

    @Test("Arranges children left-to-right on one row with default spacing 1")
    func defaultArrangement() {
        let buffer = renderToBuffer(
            HStack {
                Text("A")
                Text("B")
                Text("C")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 1, "Single-line children stay on one row")
        // Default spacing is 1 character between each pair: "A B C".
        #expect(buffer.lines[0].stripped == "A B C")
        #expect(buffer.width == 5)
    }

    @Test("Zero spacing places children flush together")
    func zeroSpacing() {
        let buffer = renderToBuffer(
            HStack(spacing: 0) {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        #expect(buffer.lines[0].stripped == "AB")
        #expect(buffer.width == 2)
    }

    @Test("Explicit spacing widens the gaps")
    func explicitSpacing() {
        let buffer = renderToBuffer(
            HStack(spacing: 3) {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        #expect(buffer.lines[0].stripped == "A   B")
    }

    // MARK: - Empty

    @Test("Empty HStack renders nothing")
    func emptyStack() {
        let buffer = renderToBuffer(HStack {}, context: ctx())
        #expect(buffer.height == 0)
        #expect(buffer.lines.isEmpty)
    }

    @Test("A single child renders as itself")
    func singleChild() {
        let buffer = renderToBuffer(HStack { Text("solo") }, context: ctx())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "solo")
    }

    // MARK: - Spacer

    @Test("Spacer pushes siblings to the left and right edges")
    func spacerExpands() {
        let buffer = renderToBuffer(
            HStack {
                Text("L")
                Spacer()
                Text("R")
            },
            context: ctx(width: 20, height: 3)
        )
        #expect(buffer.lines.count == 1)
        let line = buffer.lines[0].stripped
        #expect(line.hasPrefix("L"), "Left item flush left")
        #expect(line.hasSuffix("R"), "Right item flush right")
        #expect(line.strippedLength == 20, "Row fills the full available width")
        // The interior between L and R is all spaces.
        let interior = String(line.dropFirst().dropLast())
        #expect(interior.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Vertical alignment

    @Test("Top alignment puts a short child on the first row of a taller row")
    func topAlignment() {
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                VStack { Text("a"); Text("b") }
                Text("X")
            },
            context: ctx(width: 10, height: 3)
        )
        #expect(buffer.lines.count == 2, "Row is as tall as the tallest child (2 lines)")
        #expect(buffer.lines[0].stripped == "a X", "X sits on the top row")
        #expect(buffer.lines[1].stripped.hasPrefix("b"))
        // The X column on the second row is blank (no second line for X).
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces) == "b")
    }

    @Test("Center and bottom alignment position a short child within a taller row")
    func centerAndBottomAlignment() {
        // A 3-row sibling next to a 1-row Text. The single "X" should sit on the
        // top / middle / bottom row per the alignment. (Previously every
        // alignment top-pinned the X — `.center` and `.bottom` were ignored.)
        func rows(_ a: VerticalAlignment) -> [String] {
            renderToBuffer(
                HStack(alignment: a, spacing: 1) {
                    VStack(alignment: .leading) { Text("a"); Text("b"); Text("c") }
                    Text("X")
                },
                context: ctx(width: 10, height: 4)
            ).lines.map { $0.stripped }
        }
        // The X column occupies its cell on every row (blank where X is absent),
        // so non-X rows carry trailing spaces — pin them exactly.
        #expect(rows(.top) == ["a X", "b  ", "c  "], "top: X on the first row")
        #expect(rows(.center) == ["a  ", "b X", "c  "], "center: X on the middle row")
        #expect(rows(.bottom) == ["a  ", "b  ", "c X"], "bottom: X on the last row")
    }

    // MARK: - Narrow width (truncation, no overflow)

    @Test("Children squeezed past the width truncate instead of overflowing")
    func narrowTruncation() {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                Text("AAAA")
                Text("BBBB")
                Text("CCCC")
            },
            context: ctx(width: 8, height: 2)
        )
        #expect(buffer.width <= 8, "Assembled row must not exceed the available width")
        for line in buffer.lines {
            #expect(line.strippedLength <= 8, "No line overflows the width")
        }
    }

    // MARK: - Multi-item

    @Test("All items render in order across the row")
    func manyItems() {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                ForEach(0..<4) { Text("\($0)") }
            },
            context: ctx(width: 30, height: 2)
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "0 1 2 3")
    }

    // MARK: - Overflow degrades gracefully (regression)

    @Test("A spaced row wider than its space clips trailing columns, never blanks")
    func overflowingSpacedRowClipsNotBlanks() {
        // 12 single-cell columns with spacing 1 want 23 cells. In a 4-cell width
        // the inter-column gaps alone exceed it — reserving every gap first would
        // starve all columns to zero and render blank. The leading columns must
        // stay visible instead.
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                ForEach(0..<12) { Text("\($0 % 10)") }
            },
            context: ctx(width: 4, height: 2)
        )
        #expect(!buffer.lines.allSatisfy { $0.stripped.trimmingCharacters(in: .whitespaces).isEmpty },
                "Overflowing spaced row must not render blank")
        #expect(buffer.lines.first?.stripped.hasPrefix("0") == true, "Leading column stays visible")
        #expect(buffer.width <= 4, "Never overflows the width it was given")
    }
}
