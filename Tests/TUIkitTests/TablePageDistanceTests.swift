//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TablePageDistanceTests.swift
//
//  The Table twin of `PageDistanceTests`: what one Page Down moves while a
//  drag from elsewhere hovers, which is the state where the content area and
//  the row area differ by the drop slot's line.
//
//  The same rule lives in three places on each side — the view's window
//  arithmetic, `ItemListHandler.pageDistance`, and the indicator reservation —
//  and the two sides keep drifting (see the note atop TableReorderDragTests).
//  So the check is the same one the List gets: render a REAL Table at every
//  offset a page can reach and hold the handler's answer against the rows
//  actually on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("What one page moves in a Table")
struct TablePageDistanceTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        /// Wide enough to wrap when the fixture asks for more than one line.
        var name: String { "\(id) wraps onto two" }
    }

    @MainActor
    private final class Fixture {
        let names: [String]
        let height: Int
        /// Above 1 puts the table on its MULTI-LINE render path, which is the
        /// only one that budgets a hovering drop slot's line for itself.
        let lineLimit: Int
        let tui = TUIContext()
        var env = EnvironmentValues()
        var buffer = FrameBuffer(lines: [], width: 0)
        var handler: ItemListHandler<String>?

        init(rows: Int, height: Int, lineLimit: Int = 1) {
            names = (0..<rows).map { "r\($0)" }
            self.height = height
            self.lineLimit = lineLimit
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            // The "▲/▼ N more" style: these cases read row geometry off the
            // screen, and a bar would append a cell to every line.
            env.scrollIndicatorStyle = .text
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        func render() {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let table = Table(names.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name).lineLimit(lineLimit)
            }
            .dropDestination(for: String.self) { _, _ in }
            .frame(width: 22, height: height)
            var context = RenderContext(
                availableWidth: 22, availableHeight: height + 4, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            buffer = renderToBuffer(table, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            // Kept across renders: the handler is only reachable through the
            // session while a drag hovers, and it is the same persisted object
            // before and after one.
            handler =
                tui.dragAndDropSession.scrollableUnderCursor() as? ItemListHandler<String>
                ?? handler
        }

        /// Row labels drawn, in order. Matched exactly: the column header and
        /// an indicator line both contain "r" too.
        var drawnRows: [String] {
            // The row's FIRST line carries its id; the wrapped remainder does
            // not, so a row counts once however many lines it took.
            buffer.lines.compactMap { line in
                let text = String(
                    line.stripped
                        .drop { !$0.isLetter && !$0.isNumber }
                        .prefix { $0.isLetter || $0.isNumber })
                return names.contains(text) ? text : nil
            }
        }

        func hoverDrag() {
            render()
            let y = buffer.lines.firstIndex { $0.stripped.contains("r1") } ?? 3
            tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
                button: .left, phase: .dragged, x: 2, y: y)
            tui.dragAndDropSession.begin(payload: "z", preview: FrameBuffer(text: "z"))
            render()
        }

        func key(_ key: Key) {
            _ = tui.dragAndDropSession.handleDragNavigator(KeyEvent(key: key))
            render()
        }
    }

    /// `pageDistance` must equal the rows actually drawn, at every offset a
    /// page can reach — the List's guard, held against a Table's geometry so
    /// the handler's copy of the window rule cannot drift from either view's.
    ///
    /// Single-line rows only. With a `lineLimit` above 1 a row can be clipped
    /// part-way down the viewport, so "rows drawn" counts something a page
    /// never claimed to move by; the invariant there is stated separately
    /// below, against the content height itself.
    @Test("The page equals the rows on screen, at every offset")
    func pageMatchesWhatIsDrawn() {
        for (rows, height) in [(6, 8), (12, 9), (20, 6), (9, 7)] {
            let fixture = Fixture(rows: rows, height: height)
            fixture.hoverDrag()
            var offenders: [String] = []
            for step in 0..<rows {
                guard let handler = fixture.handler else { break }
                let claimed = handler.pageDistance
                let drawn = fixture.drawnRows.count
                // A page cannot travel further than the end, so the two are
                // only comparable while there is somewhere left to go.
                if drawn < rows, claimed != drawn {
                    offenders.append(
                        "\(rows)r/\(height)h step \(step): page=\(claimed) drawn=\(drawn)")
                }
                fixture.key(.down)
            }
            #expect(offenders.isEmpty, "page distance tracks the drawing: \(offenders)")
        }
    }

    /// The content height the handler is given is the WHOLE content area — the
    /// slot is a separate fact it already holds, and every reader inside the
    /// handler that must account for it subtracts it there.
    ///
    /// The bug this was written against: the multi-line render passed the
    /// figure ALREADY reduced by the hovering slot's line, so it came off
    /// twice. A page moved one row short of a screenful for as long as a drag
    /// hovered, and so did the scroll bounds, the row-line budget and
    /// focus-reveal.
    @Test("A hovering drop does not shrink the content height it reports")
    func contentHeightIsNotReducedByTheSlot() {
        let fixture = Fixture(rows: 12, height: 9, lineLimit: 2)
        fixture.hoverDrag()
        #expect(fixture.handler?.externalDropSlot != nil, "the drag is hovering")
        let hovering = fixture.handler?.contentHeight
        // The drag ends where it started, changing nothing but the slot.
        fixture.tui.dragAndDropSession.cancelReturningToOrigin()
        fixture.tui.dragAndDropSession.end()
        fixture.render()
        #expect(fixture.handler?.externalDropSlot == nil, "the drag is over")
        #expect(hovering == fixture.handler?.contentHeight, "same content area either way")
        #expect(hovering != nil, "the fixture found the handler at all")
    }
}
