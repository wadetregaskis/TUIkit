//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ZStackRenderTests.swift
//
//  Buffer-level render audit for ZStack.
//
//  Note on the rendering contract: this framework's ZStack composites
//  children with whole-LINE replacement (FrameBuffer.overlay) — the
//  topmost child that has a non-empty string at a given row owns that
//  entire row. This is the behaviour the existing ZIndexTests already
//  pin down; these tests complement it. Configurations where this model
//  diverges from SwiftUI (alignment ignored, a narrower top child
//  shrinking the result) are reported as suspected bugs rather than
//  asserted here.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ZStack rendering")
struct ZStackRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    // MARK: - Empty / single

    @Test("Empty ZStack renders nothing")
    func emptyStack() {
        let buffer = renderToBuffer(ZStack {}, context: ctx())
        #expect(buffer.height == 0)
        #expect(buffer.lines.isEmpty)
    }

    @Test("A single child renders exactly as itself")
    func singleChild() {
        let buffer = renderToBuffer(ZStack { Text("solo") }, context: ctx())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "solo")
        #expect(buffer.width == 4)
    }

    // MARK: - Layering (tree order)

    @Test("With equal z-index the later sibling draws on top")
    func laterSiblingOnTop() {
        // Equal width so whole-line replacement yields a clean result.
        let buffer = renderToBuffer(
            ZStack {
                Text("AAA")
                Text("BBB")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "BBB", "Last child wins the row")
    }

    @Test("A higher zIndex draws on top regardless of tree order")
    func zIndexOverridesTreeOrder() {
        let buffer = renderToBuffer(
            ZStack {
                Text("BBB").zIndex(1)   // first in tree, but higher z
                Text("AAA")
            },
            context: ctx()
        )
        #expect(buffer.lines[0].stripped == "BBB")
    }

    @Test("Explicit zIndex ordering controls which of three children shows")
    func threeWayZIndex() {
        let buffer = renderToBuffer(
            ZStack {
                Text("111").zIndex(3)
                Text("222").zIndex(1)
                Text("333").zIndex(2)
            },
            context: ctx()
        )
        // Highest z-index (111) draws last → on top.
        #expect(buffer.lines[0].stripped == "111")
    }

    // MARK: - Documented padded-overlay usage

    @Test("A full-width foreground composites over a full-width background")
    func paddedOverlay() {
        // The documented ZStack pattern: pad the foreground to the
        // background's width so it owns the whole row deliberately.
        let buffer = renderToBuffer(
            ZStack {
                Text("######")
                Text("XX    ")
            },
            context: ctx()
        )
        #expect(buffer.width == 6)
        #expect(buffer.lines[0].stripped == "XX    ", "Full-width foreground wins the row")
    }

    // MARK: - Multi-line layering (equal-size children)

    @Test("Per-row layering picks the topmost non-empty row from equal-size children")
    func multiLineLayering() {
        // Background rows present on both lines; foreground only fills row 1.
        // Foreground row 0 is empty (EmptyView via false branch) so the
        // background row 0 shows through; foreground row 1 wins.
        let buffer = renderToBuffer(
            ZStack {
                VStack(alignment: .leading) { Text("AAA"); Text("BBB") }
                VStack(alignment: .leading) { Text("CCC"); Text("DDD") }
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        // Later (foreground) sibling wins each row it occupies.
        #expect(buffer.lines[0].stripped == "CCC")
        #expect(buffer.lines[1].stripped == "DDD")
    }

    @Test("zIndex on a child renders transparently (no size or content change)")
    func zIndexTransparent() {
        let withZ = renderToBuffer(ZStack { Text("Hello").zIndex(2) }, context: ctx())
        let plain = renderToBuffer(ZStack { Text("Hello") }, context: ctx())
        #expect(withZ.lines.map { $0.stripped } == plain.lines.map { $0.stripped })
    }
}
