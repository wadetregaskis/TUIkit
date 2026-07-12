//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollShrinkRaceTests.swift
//
//  A scroller's persistent `scrollOffset` outlives the data it was clamped
//  against: rows can be added or removed (an async reload, a filter) between
//  the render pass that clamped the offset and the next pass that reads it.
//  The next pass to observe the new, smaller extent is typically a MEASURE
//  pass — which deliberately skips `clampScrollOffset()` (a measure-time
//  clamp against the measure pass's larger offered viewport pulls the offset
//  back every frame, making the last rows unreachable) — so range math must
//  never assume `scrollOffset < extent`. Before the fix,
//  `ScrollableOffsetState.visibleRange` (and Table's open-coded scrollbar
//  variant) built `scrollOffset..<min(extent, …)` = e.g. `1300..<2`, which
//  traps.
//
//  These are exit tests: the scenario runs in a child process, so a trap is
//  reported as a test failure instead of killing the test run.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct RowItem: Identifiable, Sendable {
    let id: Int
    var name: String { "row-\(id)" }
}

@MainActor
@Suite("Scrolled state vs shrinking data")
struct ScrollShrinkRaceTests {

    @Test("visibleRange must not trap when the extent shrinks under a scrolled offset")
    func handlerVisibleRangeSurvivesShrink() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let handler = ItemListHandler<Int>(
                    focusID: "table", itemCount: 2_000, viewportHeight: 10,
                    selectionMode: .single)
                handler.scrollOffset = 1_300  // legitimately scrolled near the end
                handler.itemCount = 2  // rows removed out from under it

                // Before the fix this was `1300..<2` — a Range trap.
                let range = handler.visibleRange
                precondition(range.isEmpty || range.upperBound <= 2, "range addresses real rows")
            }
        }
    }

    @Test("A Table measure pass right after its data shrinks must not trap")
    func tableMeasurePassAfterShrink() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                var context = makeRenderContext(width: 30, height: 8)
                context.hasExplicitWidth = true
                context.hasExplicitHeight = true
                let dispatcher = context.environment.mouseEventDispatcher!
                dispatcher.setActiveSupport(.standard)

                // Render a big table and wheel-scroll it to the bottom — the
                // per-tick clamp runs against the CURRENT 2000-row extent, so
                // the persisted offset legitimately ends up near 2000.
                let big = (0..<2_000).map { RowItem(id: $0) }
                let bigTable = Table(big, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \RowItem.name)
                }
                let buffer = renderToBuffer(bigTable, context: context)
                dispatcher.setRegions(buffer.hitTestRegions)
                for _ in 0..<800 {
                    _ = dispatcher.dispatch(
                        MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 3))
                }

                // Rows vanish (async reload) — the next pass to see the new
                // data is a measure pass, which skips the scroll clamp.
                let small = Array(big.prefix(2))
                let smallTable = Table(small, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \RowItem.name)
                }
                var measureContext = context
                measureContext.isMeasuring = true
                _ = renderToBuffer(smallTable, context: measureContext)

                // And the render pass that follows must also survive + clamp.
                let rendered = renderToBuffer(smallTable, context: context)
                precondition(
                    rendered.lines.map(\.stripped).joined().contains("row-0"),
                    "the shrunk table renders its remaining rows")
            }
        }
    }

    @Test("Storm: random wheel/measure/render/resize interleavings never trap")
    func scrollResizeStorm() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                // Seeded LCG so a failure reproduces exactly.
                var seed: UInt64 = 0x5EED_CAFE
                func random(_ bound: Int) -> Int {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return Int(seed >> 33) % bound
                }

                var context = makeRenderContext(width: 30, height: 8)
                context.hasExplicitWidth = true
                context.hasExplicitHeight = true
                var measureContext = context
                measureContext.isMeasuring = true
                let dispatcher = context.environment.mouseEventDispatcher!
                dispatcher.setActiveSupport(.standard)

                var count = 500
                // Named nested functions don't inherit the closure's actor
                // isolation, so this must be explicit.
                @MainActor func table() -> some View {
                    Table((0..<count).map { RowItem(id: $0) }, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \RowItem.name)
                    }
                }

                for _ in 0..<400 {
                    switch random(6) {
                    case 0:  // render pass (also refreshes hit regions)
                        dispatcher.setRegions(renderToBuffer(table(), context: context).hitTestRegions)
                    case 1:  // measure pass (clamp deliberately skipped)
                        _ = renderToBuffer(table(), context: measureContext)
                    case 2:  // wheel down, hard
                        for _ in 0..<random(80) {
                            _ = dispatcher.dispatch(
                                MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 3))
                        }
                    case 3:  // wheel up
                        for _ in 0..<random(20) {
                            _ = dispatcher.dispatch(
                                MouseEvent(button: .scrollUp, phase: .scrolled, x: 5, y: 3))
                        }
                    case 4:  // rows removed (sometimes drastically)
                        count = max(0, count - random(400))
                    default:  // rows added
                        count = min(2_000, count + random(300))
                    }
                }
            }
        }
    }

    @Test("A List measure pass right after its data shrinks must not trap")
    func listMeasurePassAfterShrink() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                var context = makeRenderContext(width: 30, height: 8)
                context.hasExplicitWidth = true
                context.hasExplicitHeight = true
                let dispatcher = context.environment.mouseEventDispatcher!
                dispatcher.setActiveSupport(.standard)

                let big = (0..<2_000).map { RowItem(id: $0) }
                let bigList = List(big, selection: .constant(Int?.none)) { item in
                    Text(item.name)
                }
                let buffer = renderToBuffer(bigList, context: context)
                dispatcher.setRegions(buffer.hitTestRegions)
                for _ in 0..<800 {
                    _ = dispatcher.dispatch(
                        MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 3))
                }

                let small = Array(big.prefix(2))
                let smallList = List(small, selection: .constant(Int?.none)) { item in
                    Text(item.name)
                }
                var measureContext = context
                measureContext.isMeasuring = true
                _ = renderToBuffer(smallList, context: measureContext)
                _ = renderToBuffer(smallList, context: context)
            }
        }
    }
}
