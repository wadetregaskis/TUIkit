//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutSizingTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Verifies the layout system's size invariants: a view's rendered
//  FrameBuffer must never exceed the width/height it was allocated, and
//  views should degrade gracefully when the terminal is smaller than the
//  space they would like to occupy.

import Testing

@testable import TUIkit

// MARK: - Test Support

/// A view that deliberately renders a buffer of a fixed size, ignoring the
/// space it is given. Used to prove the layout system clamps a misbehaving
/// child rather than letting it corrupt siblings or overflow the terminal.
private struct OversizedView: View, Renderable {
    let renderWidth: Int
    let renderHeight: Int

    var body: Never { fatalError("OversizedView renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let line = String(repeating: "X", count: renderWidth)
        return FrameBuffer(lines: Array(repeating: line, count: renderHeight))
    }
}

// MARK: - FrameBuffer.clamped

@Suite("FrameBuffer clamped")
struct FrameBufferClampedTests {

    @Test("A buffer already within bounds is returned unchanged")
    func withinBoundsUnchanged() {
        let buffer = FrameBuffer(lines: ["abc", "de"])
        #expect(buffer.clamped(toWidth: 10, height: 10) == buffer)
    }

    @Test("Over-wide lines are truncated to the width")
    func truncatesWidth() {
        let buffer = FrameBuffer(lines: ["0123456789", "ab"])
        let clamped = buffer.clamped(toWidth: 4, height: 10)
        #expect(clamped.width == 4)
        #expect(clamped.lines == ["0123", "ab"])
    }

    @Test("Excess lines are dropped to the height")
    func truncatesHeight() {
        let buffer = FrameBuffer(lines: ["a", "b", "c", "d"])
        let clamped = buffer.clamped(toWidth: 10, height: 2)
        #expect(clamped.height == 2)
        #expect(clamped.lines == ["a", "b"])
    }

    @Test("Width and height are clamped together")
    func truncatesBoth() {
        let buffer = FrameBuffer(lines: Array(repeating: "wide content", count: 8))
        let clamped = buffer.clamped(toWidth: 5, height: 3)
        #expect(clamped.width <= 5)
        #expect(clamped.height == 3)
    }

    @Test("Clamping to zero yields an empty buffer")
    func clampToZero() {
        let buffer = FrameBuffer(lines: ["content", "more"])
        let clamped = buffer.clamped(toWidth: 0, height: 0)
        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
    }

    @Test("Negative bounds are treated as zero")
    func negativeBounds() {
        let clamped = FrameBuffer(lines: ["content"]).clamped(toWidth: -5, height: -5)
        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
    }

    @Test("ANSI codes do not count toward the clamped width")
    func ansiAwareWidth() {
        let styled = "\u{1B}[31m0123456789\u{1B}[0m"  // 10 visible cells
        let clamped = FrameBuffer(lines: [styled]).clamped(toWidth: 4, height: 1)
        #expect(clamped.width == 4)
        #expect(clamped.lines[0].stripped == "0123")
    }

    @Test("A wide character is dropped rather than split at the boundary")
    func wideCharacterBoundary() {
        let buffer = FrameBuffer(lines: ["あい"])  // two 2-cell characters == 4 cells
        let clamped = buffer.clamped(toWidth: 3, height: 1)
        #expect(clamped.width <= 3)
    }
}

// MARK: - renderChild clamps to its allocation

@MainActor
@Suite("Stack child clamping")
struct StackChildClampingTests {

    private func context(width: Int, height: Int) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("renderChild truncates a child that over-renders its width")
    func childWidthClamped() {
        let buffer = renderChild(
            OversizedView(renderWidth: 200, renderHeight: 3),
            width: 10, height: 5, context: context(width: 80, height: 24)
        )
        #expect(buffer.width <= 10, "child rendered \(buffer.width) wide, allocation was 10")
    }

    @Test("renderChild truncates a child that over-renders its height")
    func childHeightClamped() {
        let buffer = renderChild(
            OversizedView(renderWidth: 4, renderHeight: 99),
            width: 10, height: 5, context: context(width: 80, height: 24)
        )
        #expect(buffer.height <= 5, "child rendered \(buffer.height) tall, allocation was 5")
    }

    @Test("renderChild leaves a well-behaved child untouched")
    func wellBehavedChildUntouched() {
        let buffer = renderChild(
            Text("hello"),
            width: 40, height: 10, context: context(width: 80, height: 24)
        )
        #expect(buffer.width == 5)
        #expect(buffer.height == 1)
    }
}
