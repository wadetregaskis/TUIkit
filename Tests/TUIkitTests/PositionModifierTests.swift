//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PositionModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Positioning a view")
struct PositionModifierTests {

    private func placed<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> OverlayLayer? {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .overlays.first
    }

    @Test("The point names the view's CENTRE, not its corner")
    func positionCentres() {
        // Four cells wide, centred on column 10, so it starts at 8.
        let layer = placed(Text("abcd").position(x: 10, y: 3))
        #expect(layer?.offsetX == 8)
        #expect(layer?.offsetY == 3, "one row tall, so its centre is its only row")
    }

    @Test("An even width rounds its centre down")
    func evenWidthRoundsDown() {
        // Two cells centred on column 10 occupy 9 and 10.
        #expect(placed(Text("ab").position(x: 10, y: 0))?.offsetX == 9)
    }

    @Test("A positioned view fills the space it is offered")
    func positionFills() {
        // The difference from `.offset`, and the reason for it: the
        // coordinates mean nothing unless the parent reserved the field they
        // are measured in.
        let size = measureChild(
            Text("ab").position(x: 3, y: 3),
            proposal: ProposedSize(width: 20, height: 6),
            context: makeRenderContext(width: 20, height: 6))
        #expect(size.width == 20)
        #expect(size.height == 6)
        #expect(size.isWidthFlexible)
        #expect(size.isHeightFlexible)
    }

    @Test("It paints nothing at its natural place")
    func positionDoesNotPaintInFlow() {
        // A terminal has no transparency, so an in-place blank field would
        // erase whatever is beneath it. The rows exist and are empty; the
        // drawing floats. Same shape as `.offset`.
        let buffer = renderToBuffer(
            Text("abcd").position(x: 10, y: 2), context: makeRenderContext(width: 20, height: 6))
        let painted = buffer.lines.filter { !$0.isEmpty }
        #expect(painted.isEmpty, "it painted at its natural place: \(painted)")
        #expect(buffer.overlays.count == 1)
    }

    @Test("The point spelled as a value is the same modifier")
    func pointSpelling() {
        #expect(
            placed(Text("abcd").position(CellSize(width: 10, height: 3)))?.offsetX
                == placed(Text("abcd").position(x: 10, y: 3))?.offsetX)
    }

    @Test("A change of position glides")
    func positionAnimates() {
        var context = makeRenderContext(width: 20, height: 6)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))

        func column(_ x: Int, atMillis millis: Int) -> Int? {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Text("ab").position(x: x, y: 2), context: context)
                .overlays.first?.offsetX
        }

        #expect(column(2, atMillis: 0) == 1)
        #expect(column(12, atMillis: 0) == 1, "the frame the change lands on has not moved")
        #expect(column(12, atMillis: 500) == 6)
        #expect(column(12, atMillis: 1000) == 11)
    }
}
