//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListHugMeasureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A hugging `List` — `.fixedSize(horizontal:)`, or the sidebar a
/// `NavigationSplitView` sizes — has to know how wide every row is, and it
/// used to find out by rendering every row, every frame, in a measure pass
/// the row memo could not serve: 93% of a split-view frame over a
/// 2,000-row list. It measures instead, and the second frame is served
/// from the size memo.
@MainActor
@Suite("A hugging list measures its rows rather than rendering them")
struct ListHugMeasureTests {

    /// A leaf that counts how it was asked. Fixed-size, so a row's width is
    /// its own and the hug has something to compare.
    private struct CountingCell: View, Renderable, Layoutable {
        let width: Int
        var body: Never { fatalError("CountingCell renders via Renderable") }
        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            Counters.measures += 1
            return ViewSize.fixed(width, 1)
        }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            Counters.renders += 1
            return FrameBuffer(text: String(repeating: "x", count: width))
        }
    }

    private enum Counters {
        nonisolated(unsafe) static var measures = 0
        nonisolated(unsafe) static var renders = 0
        static func reset() {
            measures = 0
            renders = 0
        }
    }

    private struct Item: Identifiable, Equatable {
        let id: Int
        let width: Int
    }

    private static func context(width: Int = 60, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("Hugging 200 rows renders none of them off-screen, and the width is still the widest row's")
    func hugMeasuresEveryRowAndRendersOnlyTheVisibleOnes() {
        let items = (0..<200).map { Item(id: $0, width: 5 + $0 % 17) }
        let list = List(items) { item in CountingCell(width: item.width) }
            .fixedSize(horizontal: true)
        let tui = TUIContext()
        let context = RenderContext(availableWidth: 60, availableHeight: 8, tuiContext: tui)
        Counters.reset()
        tui.stateStorage.beginRenderPass()
        let buffer = renderToBuffer(list, context: context)
        tui.stateStorage.endRenderPass()
        // The widest row is 5 + 16 = 21 cells, plus the gutters and the border.
        #expect(buffer.width < 60, "hugged, not filled")
        #expect(buffer.width >= 21)
        #expect(Counters.renders <= 8 + 2, "only the rows on screen render: \(Counters.renders)")
        // The rows on screen render before the hug walks, and answer it from
        // that render; every other row answers with a measure. So the two
        // together cover every row, and neither covers one twice over.
        #expect(
            Counters.measures + Counters.renders >= 200,
            "every row was measured or drawn for the hug: \(Counters.measures) + \(Counters.renders)")
        #expect(Counters.measures >= 200 - 10, "the off-screen rows measured: \(Counters.measures)")
    }

    @Test("The second frame's hug is answered by the size memo, not by measuring again")
    func secondFrameIsServedFromTheSizeMemo() {
        let items = (0..<120).map { Item(id: $0, width: 4 + $0 % 9) }
        let list = List(items) { item in CountingCell(width: item.width) }
            .fixedSize(horizontal: true)
        let tui = TUIContext()
        let context = RenderContext(availableWidth: 60, availableHeight: 8, tuiContext: tui)
        for _ in 0..<2 {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(list, context: context)
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
        }
        Counters.reset()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        _ = renderToBuffer(list, context: context)
        tui.stateStorage.endRenderPass()
        #expect(Counters.measures < 120, "the hug measured rows that the memo should have answered: \(Counters.measures)")
    }

    @Test("Unchanged data: the third frame's hug walks no rows at all; changed data walks them again")
    func hugIsMemoisedOnTheData() {
        let items = (0..<150).map { Item(id: $0, width: 4 + $0 % 9) }
        let tui = TUIContext()
        let context = RenderContext(availableWidth: 60, availableHeight: 8, tuiContext: tui)
        func frame(_ items: [Item]) -> FrameBuffer {
            let list = List(items) { item in CountingCell(width: item.width) }.fixedSize(horizontal: true)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = renderToBuffer(list, context: context)
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return buffer
        }
        _ = frame(items)
        _ = frame(items)
        Counters.reset()
        let steady = frame(items)
        // The rows on screen still draw (and measure by drawing); every row
        // beyond them is answered by the list's own memo, not by a walk.
        #expect(Counters.measures <= 10, "the hug was served from the list memo: \(Counters.measures)")
        #expect(steady.width >= 12 && steady.width < 60)

        var wider = items
        wider[100] = Item(id: 100, width: 30)
        Counters.reset()
        let changed = frame(wider)
        #expect(changed.width > steady.width, "a wider row widened the hug: \(changed.width) vs \(steady.width)")
        #expect(Counters.measures >= 100, "changed data walked the rows again: \(Counters.measures)")
    }
}
