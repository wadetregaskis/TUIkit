//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyStackZeroExtentGapTests.swift
//
//  The walks that place a stack's children one at a time — the lazy stacks'
//  measure and fit-checks, the row-slot walk behind placement, seek and the
//  viewport window, and the lazy ramp placement — charge `spacing` only
//  between children that occupy the axis, as `appendHorizontally` and
//  `appendVertically` draw them. Charged per index, a zero-extent child was
//  measured a gap no stack drew, and the render walk stopped a gap early.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Zero-extent children in the lazy stacks and slot walks")
struct LazyStackZeroExtentGapTests {
    private func trimmedRows(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - LazyHStack

    @Test("A LazyHStack measures only the gaps it draws around an EmptyView")
    func lazyHStackMeasuresDrawnGaps() {
        let stack = LazyHStack {
            Text("A")
            EmptyView()
            Text("B")
        }
        let context = makeBareRenderContext(width: 40, height: 5)
        let measured = measureChild(stack, proposal: .unspecified, context: context)
        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.lines.first?.stripped == "A B")
        #expect(buffer.width == 3)
        #expect(measured.width == 3)
    }

    @Test("A leading EmptyView indents neither a LazyHStack's measure nor its row")
    func lazyHStackLeadingEmptyChild() {
        let stack = LazyHStack(spacing: 2) {
            EmptyView()
            Text("Hi")
        }
        let context = makeBareRenderContext(width: 40, height: 5)
        let measured = measureChild(stack, proposal: .unspecified, context: context)
        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.lines.first?.stripped == "Hi")
        #expect(measured.width == 2)
    }

    @Test("A LazyHStack exactly as wide as the columns it draws still draws the last one")
    func lazyHStackFitsAtExactWidth() {
        // Three cells hold "A B". A gap charged to the EmptyView made the
        // fit-check think "B" needed four, and a lone spacing cell was drawn in
        // its place.
        let buffer = renderToBuffer(
            LazyHStack {
                Text("A")
                EmptyView()
                Text("B")
            }, context: makeBareRenderContext(width: 3, height: 5))
        #expect(buffer.lines.first?.stripped == "A B")
    }

    @Test("A Spacer beside an EmptyView pushes a LazyHStack's last column flush right")
    func lazyHStackSpacerBesideEmptyView() {
        let buffer = renderToBuffer(
            LazyHStack(spacing: 2) {
                Text("A")
                EmptyView()
                Spacer()
                Text("B")
            }, context: makeBareRenderContext(width: 20, height: 5))
        let expected = "A" + String(repeating: " ", count: 18) + "B"
        #expect(buffer.width == 20)
        #expect(buffer.lines.first?.stripped == expected)
    }

    @Test("A lazy row's ramp places each column where the row draws it")
    func lazyHStackRampPlacement() {
        let stack = _HStackCore(
            alignment: .top, spacing: 2, overflow: .window,
            content: TupleView(Text("A"), EmptyView(), Text("B")))
        var context = makeBareRenderContext(width: 20, height: 5)
        context.gradientFrame = GradientFrame(width: 20, height: 5, isProvisional: true)
        let children = resolveChildViews(from: stack.content, context: context)
        let placement = stack.windowGradientPlacement(children, context: context)
        let columns = placement.offsets.map(\.x)
        #expect(columns == [0, 1, 3])
        #expect(placement.frame?.width == 4)
    }

    // MARK: - LazyVStack and the row-slot walk

    @Test("A LazyVStack measures only the gaps it draws around an EmptyView")
    func lazyVStackMeasuresDrawnGaps() {
        let stack = LazyVStack(spacing: 1) {
            Text("A")
            EmptyView()
            Text("B")
        }
        let context = makeBareRenderContext(width: 20, height: 10)
        let measured = measureChild(stack, proposal: .unspecified, context: context)
        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.height == 3)
        #expect(measured.height == 3)
    }

    @Test("A LazyVStack exactly as tall as the rows it draws still draws the last one")
    func lazyVStackFitsAtExactHeight() {
        let rows = trimmedRows(
            renderToBuffer(
                LazyVStack(spacing: 1) {
                    Text("A")
                    EmptyView()
                    Text("B")
                }, context: makeBareRenderContext(width: 20, height: 3)))
        #expect(rows.count == 3)
        #expect(rows.last == "B")
    }

    @Test("A Spacer below an EmptyView pushes a LazyVStack's last row to the bottom edge")
    func lazyVStackSpacerBelowEmptyView() {
        let rows = trimmedRows(
            renderToBuffer(
                LazyVStack(spacing: 1) {
                    Text("A")
                    EmptyView()
                    Spacer()
                    Text("B")
                }, context: makeBareRenderContext(width: 20, height: 10)))
        #expect(rows.count == 10)
        #expect(rows.last == "B")
    }

    @Test("A LazyVStack in a scroll window paints no blank row for an EmptyView")
    func viewportWindowSkipsEmptyRowGap() {
        let stack = _VStackCore(
            alignment: .leading, spacing: 1, overflow: .window,
            content: TupleView(Text("A"), EmptyView(), Text("B")))
        var context = makeBareRenderContext(width: 20, height: 50)
        context.environment.scrollContentWindow = ScrollContentWindow(offset: 0, viewportHeight: 10)
        let rows = trimmedRows(renderToBuffer(stack, context: context))
        #expect(rows.count == 3)
        #expect(rows.last == "B")
    }

    @Test("An eager VStack places a row below an EmptyView where it draws it")
    func eagerPlacementSkipsEmptyRowGap() {
        let stack = _VStackCore(
            alignment: .leading, spacing: 1, overflow: .clip,
            content: TupleView(Text("A"), EmptyView(), Text("B")))
        let context = makeBareRenderContext(width: 20, height: 50)
        let placedY = stack.placement(at: 2, proposal: .unspecified, context: context)?.y
        let drawnY = trimmedRows(renderToBuffer(stack, context: context)).firstIndex(of: "B")
        #expect(drawnY == 2)
        #expect(placedY == 2)
    }

    @Test("A lazy column's ramp spans the rows it draws")
    func lazyVStackRampPlacement() {
        let stack = _VStackCore(
            alignment: .leading, spacing: 1, overflow: .window,
            content: TupleView(Text("A"), EmptyView(), Text("B")))
        var context = makeBareRenderContext(width: 20, height: 10)
        context.gradientFrame = GradientFrame(width: 20, height: 10, isProvisional: true)
        let children = resolveChildViews(from: stack.content, context: context)
        let placement = stack.windowGradientPlacement(children, context: context)
        let rows = placement.offsets.map(\.y)
        #expect(rows == [0, 2, 2])
        #expect(placement.frame?.height == 3)
    }
}
