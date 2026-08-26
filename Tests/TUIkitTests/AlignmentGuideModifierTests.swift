//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// The line a decimal point sits on — the Layout page's own custom alignment,
/// reproduced here because a `ForEach` over it is what regressed.
private enum DecimalPointID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    fileprivate static let decimalPoint = Self(DecimalPointID.self)
}

/// `.alignmentGuide` moves the line a container aligns a child on. The property
/// that makes it worth having — and the one every case here turns on — is that
/// a container can end up **wider (or taller) than its largest child**, because
/// a child hanging off the alignment line pushes its siblings across.
///
/// This has to work in every aligning container at once. A modifier that is live
/// in `VStack` and inert in `LazyVStack` is worse than one that does not exist:
/// `.anchorPosition` shipped that way and 3130 green tests missed it — running
/// the app caught it. So the suite walks eager stacks, lazy stacks, the viewport
/// window, `ZStack`, `.frame` and `.overlay`.
@MainActor
@Suite("alignmentGuide")
struct AlignmentGuideModifierTests {

    /// The leading edges of each line, which is what a guide actually moves.
    private func indents(_ buffer: FrameBuffer) -> [Int] {
        buffer.lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.drop(while: { $0 == " " }).count
        }
    }

    /// Numbers whose whole parts differ in width, so a decimal-point guide is
    /// visibly not the same as aligning on either edge. `Hashable` because that
    /// is what routes a `ForEach` row through the element-keyed memo.
    private struct Amount: Hashable {
        let whole: String
        let fraction: String
    }

    private static let amounts = [
        Amount(whole: "7", fraction: "50"),
        Amount(whole: "1240", fraction: "05"),
        Amount(whole: "96", fraction: "125"),
    ]

    // MARK: - The basic shape

    @Test("A hanging guide widens the column and indents its siblings")
    func hangingGuideWidensTheColumn() {
        // "•" declares its guide at its own TRAILING edge, so the leading
        // alignment line falls one cell to its right — and everything else has
        // to move over to meet it.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
        // Wider than "item" alone: the whole point of the mechanism.
        #expect(buffer.width == 5)
    }

    @Test("Without the guide the same stack is flush — the control")
    func withoutTheGuideNothingMoves() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•")
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 0])
        #expect(buffer.width == 4)
    }

    @Test("A guide on a lazy stack's row is not silently inert")
    func lazyStackHonoursTheGuide() {
        // The `.anchorPosition` trap, pinned: `LazyVStack` is a different render
        // path through the same core, and it would happily have ignored this.
        let buffer = renderToBuffer(
            LazyVStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
    }

    @Test("A ForEach row keeps its guide, Equatable element or not")
    func forEachRowsHonourTheGuide() {
        // `ForEach` wraps a row in the element-keyed value memo when the element
        // is `Equatable`, and the memo is `Renderable` — opaque to the stack's
        // guide query. Every row of the Layout page's decimal-point column read
        // back as unguided and the whole column drew flush left, under a caption
        // explaining that it lines up on the point.
        //
        // `Amount` is `Hashable` (so `Equatable`) on purpose: that is the branch
        // that broke. The `Int` control below takes the same branch and is here
        // to prove the assertion is about the guide, not the element type.
        let guided = renderToBuffer(
            VStack(alignment: .decimalPoint, spacing: 0) {
                ForEach(Self.amounts, id: \.self) { amount in
                    Text("\(amount.whole).\(amount.fraction)")
                        .alignmentGuide(.decimalPoint) { _ in Double(amount.whole.count) }
                }
            },
            context: makeRenderContext(width: 30, height: 4))

        // Widest whole part is 4 ("1240"), so each row is indented by the
        // difference — the point lands in one column for all three.
        #expect(indents(guided) == [3, 0, 2])

        let unguided = renderToBuffer(
            VStack(alignment: .decimalPoint, spacing: 0) {
                ForEach(Self.amounts, id: \.self) { amount in
                    Text("\(amount.whole).\(amount.fraction)")
                }
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(unguided) == [0, 0, 0], "the control: no guide, no movement")
    }

    @Test("A guide survives the scroll viewport window")
    func viewportWindowHonoursTheGuide() {
        // The third VStack render path: a lazy stack inside a ScrollView renders
        // only the rows meeting the viewport, into a full-height buffer.
        var context = makeRenderContext(width: 30, height: 4)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 0, viewportHeight: 4)
        let buffer = renderToBuffer(
            LazyVStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }
                Text("item")
            },
            context: context)

        #expect(indents(buffer).prefix(2) == [0, 1])
    }

    // MARK: - Vertical

    @Test("A vertical guide grows the row and offsets a column")
    func verticalGuideInAnHStack() {
        // The left column declares its guide on its SECOND row, so that row is
        // what lines up with the right column's first — and the row has to grow
        // to three to hold both.
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("a\nb").alignmentGuide(.top) { _ in 1 }
                Text("x\ny")
            },
            context: makeRenderContext(width: 20, height: 6))

        #expect(buffer.height == 3)
        #expect(buffer.lines[0].stripped.contains("a"))
        #expect(!buffer.lines[0].stripped.contains("x"))
        #expect(buffer.lines[1].stripped.contains("b"))
        #expect(buffer.lines[1].stripped.contains("x"))
        #expect(buffer.lines[2].stripped.contains("y"))
    }

    @Test("A guide above the view's own top drops the view")
    func negativeGuideDropsTheColumn() {
        // A guide of -1 sits one row ABOVE the view. Putting that on the row's
        // top line therefore puts the view itself one row below it.
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("x").alignmentGuide(.top) { _ in -1 }
                Text("a\nb")
            },
            context: makeRenderContext(width: 20, height: 6))

        #expect(buffer.height == 2)
        #expect(!buffer.lines[0].stripped.contains("x"))
        #expect(buffer.lines[1].stripped.contains("x"))
    }

    @Test("A ZStack reads guides on both axes")
    func zStackHonoursBothAxes() {
        let buffer = renderToBuffer(
            ZStack(alignment: .topLeading) {
                Text("####")
                Text("^").alignmentGuide(.leading) { $0[.trailing] }
            },
            context: makeRenderContext(width: 20, height: 4))

        // "^" hangs entirely to the LEFT of the leading line — its trailing edge
        // is the guide — so the fill starts one cell in and the frame grows by
        // that cell.
        #expect(buffer.width == 5)
        #expect(buffer.lines[0].stripped == "^####")
    }

    // MARK: - Single-child regions

    @Test("A frame places its content by the content's guide")
    func frameHonoursTheGuide() {
        let plain = renderToBuffer(
            Text("ab").frame(width: 10, alignment: .center),
            context: makeRenderContext(width: 20, height: 3))
        // Centred: (10 - 2) / 2 == 4.
        #expect(indents(plain) == [4])

        let guided = renderToBuffer(
            Text("ab").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
                .frame(width: 10, alignment: .center),
            context: makeRenderContext(width: 20, height: 3))
        // The guide is now the LEADING edge, so that edge meets the frame's
        // centre line instead of the text's middle doing so.
        #expect(indents(guided) == [5])
    }

    @Test("An overlay is placed by its own guide")
    func overlayHonoursTheGuide() {
        // A two-cell overlay, so the guided and unguided placements differ:
        // centred normally at (5 - 2) / 2 == 1, but guided on its own LEADING
        // edge that edge meets the base's centre line at 2.
        let plain = renderToBuffer(
            Text("#####").overlay(alignment: .center) { Text("^v") },
            context: makeRenderContext(width: 20, height: 3))
        #expect(plain.lines[0].stripped == "#^v##")

        let guided = renderToBuffer(
            Text("#####").overlay(alignment: .center) {
                Text("^v").alignmentGuide(HorizontalAlignment.center) { _ in 0 }
            },
            context: makeRenderContext(width: 20, height: 3))
        #expect(guided.lines[0].stripped == "##^v#")
    }

    // MARK: - Contract

    @Test("An unrelated guide is left alone")
    func onlyTheMatchingGuideApplies() {
        // A `.top` guide must not disturb a horizontal alignment, and vice
        // versa: guides are keyed by the AlignmentID that defines them.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.top) { _ in 5 }
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 0])
    }

    @Test("Chained guides both apply")
    func chainedGuidesBothApply() {
        // Nested wrappers: the outer must answer for its own guide AND forward
        // to the inner one for the other axis.
        let view = Text("•")
            .alignmentGuide(.leading) { $0[.trailing] }
            .alignmentGuide(.top) { _ in 0 }
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                view
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 1])
    }

    @Test("The outermost application of a repeated guide wins")
    func outermostRepeatedGuideWins() {
        let view = Text("••")
            .alignmentGuide(.leading) { _ in 0 }
            .alignmentGuide(.leading) { $0[.trailing] }
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                view
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        // The outer one (trailing edge, 2) is in force, not the inner `0`.
        #expect(indents(buffer) == [0, 2])
    }

    @Test("The measure reports the width the render produces")
    func measureAgreesWithRender() {
        // A guide grows the column; if only the render knew that, the parent
        // would reserve too little and clip it.
        let view = VStack(alignment: .leading) {
            Text("•").alignmentGuide(.leading) { $0[.trailing] }
            Text("item")
        }
        let context = makeRenderContext(width: 30, height: 4)
        let measured = measureChild(view, proposal: .unspecified, context: context)
        let rendered = renderToBuffer(view, context: context)

        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.height)
    }

    @Test("A guide buried under a later modifier does not apply")
    func aBuriedGuideIsNotRead() {
        // The documented limit, pinned so it cannot drift into a WRONG offset:
        // `.padding()` wraps the guide where the stack cannot see it, and
        // TUIkit's buffers carry no guide metadata for padding to translate.
        // Same rule as `.zIndex(_:)`. If this ever starts passing, the docs on
        // `alignmentGuide(_:computeValue:)` need updating with it.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("•").alignmentGuide(.leading) { $0[.trailing] }.padding(0)
                Text("item")
            },
            context: makeRenderContext(width: 30, height: 4))

        #expect(indents(buffer) == [0, 0])
    }

    @Test("Guides do not disturb a stack that has none")
    func unguidedStacksAreByteIdentical() {
        // The regression guard for the whole change: the guide path floors ONCE
        // PER RUN where the old path floors once per child, and the two disagree
        // in 190 of 820 centring combinations. Every container therefore keeps
        // its previous arithmetic verbatim unless a child actually set a guide.
        for width in [10, 11, 20, 41] {
            let buffer = renderToBuffer(
                VStack(alignment: .center) {
                    Text("a")
                    Text("bbb")
                    Text("ccccc")
                },
                context: makeRenderContext(width: width, height: 5))
            // Widths 1, 3, 5 centred in the column's own 5 cells: (5-1)/2,
            // (5-3)/2, 0 — regardless of how much room the stack was offered.
            #expect(indents(buffer) == [2, 1, 0])
        }
    }
}
