//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OffsetAlignmentTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Offset inside an aligning container")
struct OffsetAlignmentTests {
    private func context(width: Int = 40, height: Int = 6) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// Where an offset child's floated content ends up, in the coordinates of
    /// the buffer the container returned.
    private func floatedX(_ view: some View) -> Int? {
        let buffer = renderToBuffer(view, context: context())
        return buffer.overlays.first?.offsetX
    }

    private static let band = String(repeating: "▒", count: 28)

    @Test("An offset of zero leaves an aligned child exactly where alignment put it")
    func zeroOffsetDoesNotMove() {
        // Without the offset the label is centred by hand-checkable arithmetic:
        // 8 cells inside 28 leaves 10 either side.
        let placed = floatedX(
            ZStack(alignment: .center) {
                Text(verbatim: Self.band)
                Text(verbatim: " on top ").offset(x: 0)
            })
        #expect(placed == 10)
    }

    @Test("An offset displaces the child from where alignment put it, not from the frame's edge")
    func offsetIsRelativeToTheAlignedPosition() {
        let placed = floatedX(
            ZStack(alignment: .center) {
                Text(verbatim: Self.band)
                Text(verbatim: " on top ").offset(x: 3)
            })
        #expect(placed == 13)
    }

    @Test("Trailing alignment places an offset child by its own width too")
    func trailingAlignment() {
        let placed = floatedX(
            ZStack(alignment: .trailing) {
                Text(verbatim: Self.band)
                Text(verbatim: " on top ").offset(x: 0)
            })
        #expect(placed == 20)
    }

    @Test("Nothing is painted at the natural position")
    func naturalPositionStaysUnpainted() {
        // The promise the zero-width placeholder was there to keep: the layer
        // underneath is untouched where the offset child would have been.
        let buffer = renderToBuffer(
            ZStack(alignment: .center) {
                Text(verbatim: Self.band)
                Text(verbatim: " on top ").offset(x: 4)
            },
            context: context())
        #expect(buffer.lines.first?.stripped == Self.band)
    }

    @Test("A positioned child is placed by the size it claimed, which is all of it")
    func positionedChildFillsAndAligns() {
        // `.position` fills what it is offered, so inside a centred ZStack it
        // has nothing to be centred BY — the frame is its own size. A placeholder
        // that declared no width made the stack think otherwise.
        let buffer = renderToBuffer(
            ZStack(alignment: .center) {
                Text(verbatim: Self.band)
                Text(verbatim: "X").position(x: 5, y: 0)
            },
            context: context(width: 28, height: 1))
        // x − width/2 for a one-cell view: 5. Anything else means the stack
        // shifted the whole positioned layer as well.
        #expect(buffer.overlays.first?.offsetX == 5)
    }

    @Test("The offset child still claims no space in a vertical stack")
    func verticalStackHeightIsUnchanged() {
        // Layout is unaffected by the offset, but the row is still reserved:
        // a stack that dropped the child would pull the sibling below it up.
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "first").offset(x: 5)
                Text(verbatim: "second")
            },
            context: context())
        #expect(buffer.height == 2)
        #expect(buffer.lines.last?.stripped == "second")
    }
}
