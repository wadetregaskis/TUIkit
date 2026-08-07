//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PageDistanceTests.swift
//
//  What one Page Down moves: a screenful, no overlap. The row that was one
//  past the bottom becomes the top.
//
//  `ItemListHandler.pageDistance` is a THIRD statement of the window rule,
//  after `_ListCore.resolveVisibleWindow` and `Table.reserveIndicatorLines`.
//  The first test here renders a real List at every offset and checks the
//  handler's answer against the rows actually drawn, so the three cannot drift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("What one page moves")
struct PageDistanceTests {

    @MainActor
    private final class Fixture {
        let names: [String]
        let height: Int
        let tui = TUIContext()
        var env = EnvironmentValues()
        var buffer = FrameBuffer(lines: [], width: 0)
        var handler: ItemListHandler<String>?

        init(rows: Int, height: Int) {
            names = (0..<rows).map { "r\($0)" }
            self.height = height
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        func render() {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let list = List {
                ForEach(names, id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { _, _ in }
            }
            .frame(height: height)
            var context = RenderContext(
                availableWidth: 24, availableHeight: height + 5, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            buffer = renderToBuffer(list, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            handler = tui.dragAndDropSession.scrollableUnderCursor() as? ItemListHandler<String>
        }

        /// Row labels drawn, in order. Matched exactly — an indicator line
        /// contains "r" too.
        var drawnRows: [String] {
            buffer.lines.compactMap { line in
                let text = String(line.stripped.filter { $0.isLetter || $0.isNumber })
                return names.contains(text) ? text : nil
            }
        }

        func hoverDrag() {
            render()
            let y = buffer.lines.firstIndex { $0.stripped.contains("r1") } ?? 2
            tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
                button: .left, phase: .dragged, x: 2, y: y)
            tui.dragAndDropSession.begin(payload: "z", preview: FrameBuffer(text: "z"))
            render()
        }

        func key(_ key: Key) {
            _ = tui.dragAndDropSession.handleDragNavigator(KeyEvent(key: key))
            render()
        }

        /// Keys delivered WITHOUT a render between them, as the app's input
        /// loop does for a held key: it drains up to 128 events per frame.
        func burst(_ keys: [Key]) {
            for key in keys {
                _ = tui.dragAndDropSession.handleDragNavigator(KeyEvent(key: key))
            }
            render()
        }
    }

    /// The reported case: six rows, five lines of room, a drag hovering. The
    /// top page draws three rows + slot + "▼ 3 more rows below"; ONE Page Down
    /// must land on the bottom three.
    @Test("One page crosses a six-row Backlog")
    func onePageReachesTheEnd() {
        let fixture = Fixture(rows: 6, height: 7)
        fixture.hoverDrag()
        #expect(fixture.drawnRows == ["r0", "r1", "r2"], "the top page: \(fixture.drawnRows)")
        fixture.key(.pageDown)
        #expect(fixture.drawnRows == ["r3", "r4", "r5"], "one page down: \(fixture.drawnRows)")
        fixture.key(.pageUp)
        #expect(fixture.drawnRows == ["r0", "r1", "r2"], "and back up: \(fixture.drawnRows)")
    }

    /// `pageDistance` must equal the rows actually drawn, at every offset a
    /// page can reach — the guard against the handler's copy of the window
    /// rule drifting from `_ListCore`'s.
    @Test("The page equals the rows on screen, at every offset")
    func pageMatchesWhatIsDrawn() {
        for (rows, height) in [(6, 7), (12, 8), (20, 5), (3, 9)] {
            let fixture = Fixture(rows: rows, height: height)
            fixture.hoverDrag()
            var offenders: [String] = []
            for step in 0..<rows {
                guard let handler = fixture.handler else { break }
                let claimed = handler.pageDistance
                let drawn = fixture.drawnRows.count
                if claimed != drawn {
                    offenders.append("\(rows)r/\(height)h step \(step): page=\(claimed) drawn=\(drawn)")
                }
                fixture.key(.down)
            }
            #expect(offenders.isEmpty, "page distance tracks the drawing: \(offenders)")
        }
    }

    /// A HELD Page Down. The app drains up to 128 events before rendering, so
    /// every repeat in the burst sees ONE `viewportHeight` — the value from
    /// before the first press. The visible row count is not constant (an
    /// "▲ N more" line appears the moment you leave the top edge, costing a
    /// row), so paging by that stale number travels further per press than a
    /// page, and the burst lands past where the same presses would land one at
    /// a time.
    ///
    /// Nothing is "skipped" that the user would otherwise have seen — holding a
    /// key never draws the intermediate frames either way. What must hold is
    /// that N presses go N pages, whether or not a frame happened in between.
    @Test("A held Page Down lands where the same presses land one at a time")
    func aBurstTravelsTheSameDistance() {
        var offenders: [String] = []
        for (rows, height) in [(12, 8), (20, 7), (9, 6), (30, 5)] {
            for presses in 2...3 {
                let keys = Array(repeating: Key.pageDown, count: presses)

                let oneAtATime = Fixture(rows: rows, height: height)
                oneAtATime.hoverDrag()
                for key in keys { oneAtATime.key(key) }

                let held = Fixture(rows: rows, height: height)
                held.hoverDrag()
                held.burst(keys)

                if held.drawnRows != oneAtATime.drawnRows {
                    offenders.append(
                        "\(rows) rows in \(height), ×\(presses): held \(held.drawnRows) "
                            + "vs stepped \(oneAtATime.drawnRows)")
                }
            }
        }
        #expect(offenders.isEmpty, "a burst goes the same distance: \(offenders)")
    }
}
