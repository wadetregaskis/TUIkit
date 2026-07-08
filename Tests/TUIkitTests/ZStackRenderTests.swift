//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ZStackRenderTests.swift
//
//  Buffer-level render audit for ZStack.
//
//  Rendering contract: ZStack is as wide/tall as its largest child and
//  composites children character-by-character at their `alignment` offset
//  (FrameBuffer.composited). A child paints its full bounding box — so a
//  full-width or coloured-fill child owns its cells — but a *narrower* child
//  only paints its own cells, leaving the larger layer beneath it visible
//  around the edges. Alignment positions each child within the frame.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ZStack rendering")
struct ZStackRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
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

    // MARK: - A child paints its full bounding box

    @Test("A full-width foreground (including its spaces) owns its row")
    func fullWidthForegroundOwnsRow() {
        // A child paints its whole box, so a full-width foreground — spaces and
        // all — covers the background beneath it. (This is what preserves
        // coloured fills: a fill is "blank" cells that must stay opaque.)
        let buffer = renderToBuffer(
            ZStack {
                Text("######")
                Text("XX    ")
            },
            context: ctx()
        )
        #expect(buffer.width == 6)
        #expect(buffer.lines[0].stripped == "XX    ", "Full-width foreground wins the whole row")
    }

    // MARK: - A narrower child leaves the background showing (was a bug)

    @Test("A narrower top child no longer truncates the wider background")
    func narrowerTopChildPreservesBackground() {
        // Previously whole-line overlay replaced the entire row, so the wide
        // "######" vanished and only "X" remained. Now the uncovered sides show.
        let buffer = renderToBuffer(
            ZStack {                       // default .center
                Text("######")
                Text("X")
            },
            context: ctx()
        )
        #expect(buffer.width == 6, "frame is as wide as the widest child")
        #expect(buffer.lines[0].stripped == "##X###", "X centred over the preserved background")
    }

    @Test("Horizontal alignment positions the smaller child (was ignored)")
    func horizontalAlignmentPositionsChild() {
        func row(_ a: Alignment) -> String {
            renderToBuffer(
                ZStack(alignment: a) { Text("######"); Text("X") }, context: ctx()
            ).lines[0].stripped
        }
        #expect(row(.leading) == "X#####", "leading: flush left")
        #expect(row(.center) == "##X###", "center: middle")
        #expect(row(.trailing) == "#####X", "trailing: flush right")
    }

    @Test("An unpadded label centres over a fill without manual padding")
    func unpaddedLabelCentresOverFill() {
        // The documented idiom: rely on alignment, don't pad the string.
        let buffer = renderToBuffer(
            ZStack { Text("████████"); Text("Hi") }, context: ctx()
        )
        let row = buffer.lines[0].stripped
        #expect(buffer.width == 8)
        #expect(row == "███Hi███", "Hi centred over the preserved fill: \(row)")
    }

    @Test("Vertical alignment positions the shorter child (was top-pinned)")
    func verticalAlignmentPositionsChild() {
        func rows(_ a: Alignment) -> [String] {
            renderToBuffer(
                ZStack(alignment: a) {
                    VStack(alignment: .leading) { Text("a"); Text("b"); Text("c") }
                    Text("X")
                },
                context: ctx()
            ).lines.map { $0.stripped }
        }
        #expect(rows(.topLeading) == ["X", "b", "c"], "top: X on the first row")
        #expect(rows(.leading) == ["a", "X", "c"], "center: X on the middle row")
        #expect(rows(.bottomLeading) == ["a", "b", "X"], "bottom: X on the last row")
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

// MARK: - ForEach Expansion (issue #8)

/// The ZStack face of issue #8: its render path used the legacy single-pass
/// child resolution, which cannot expand a `ForEach`, so `ZStack { ForEach }`
/// rendered nothing (and a ForEach mixed into a tuple was silently dropped).
@MainActor
@Suite("ZStack expands ForEach (issue #8)")
struct ZStackForEachTests {
    @Test("ZStack renders ForEach content")
    func zStackForEach() {
        let stack = ZStack {
            ForEach(0..<3) { Text("Layer \($0)") }
        }
        let context = makeBareRenderContext(width: 40, height: 5)
        let joined = renderToBuffer(stack, context: context)
            .lines.map { $0.stripped }.joined(separator: "\n")
        // All layers composite into the union frame; the last draws on top.
        #expect(joined.contains("Layer"), "ForEach layers render: '\(joined)'")
        #expect(joined.contains("Layer 2"), "the topmost (last) layer wins ties")
    }

    @Test("A ForEach mixed with other layers keeps them all")
    func zStackMixedTuple() {
        let stack = ZStack(alignment: .topLeading) {
            Text("Underneath and wide")
            ForEach(0..<1) { Text("Top \($0)") }
        }
        let context = makeBareRenderContext(width: 40, height: 5)
        let line = renderToBuffer(stack, context: context).lines.first?.stripped ?? ""
        #expect(line.hasPrefix("Top 0"), "the ForEach layer draws on top: '\(line)'")
        #expect(line.contains("wide"), "the base layer shows where the top one ends")
    }

    @Test("zIndex ordering still applies through the two-pass path")
    func zStackZIndexOrdering() {
        let stack = ZStack(alignment: .topLeading) {
            Text("AAAA").zIndex(1)
            Text("BB")
        }
        let context = makeBareRenderContext(width: 20, height: 3)
        let line = renderToBuffer(stack, context: context).lines.first?.stripped ?? ""
        // "AAAA" has the higher z-index so it draws over "BB" despite being
        // first in the tree.
        #expect(line.hasPrefix("AAAA"), "explicit zIndex wins draw order: '\(line)'")
    }
}
