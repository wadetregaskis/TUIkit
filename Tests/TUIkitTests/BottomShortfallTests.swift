//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BottomShortfallTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The last screenful fills the content area, even when no whole number of rows
/// can.
///
/// Nothing forces a suffix of the row heights to sum to the budget. Three-line
/// rows in a seventeen-line content area, one line of which the "▲ N more rows
/// above" indicator takes, leave sixteen for the rows — and five rows is fifteen.
/// The sixteenth line was blank, which on screen reads as the view having scrolled
/// one line too far: the step that arrived there revealed nothing and opened a gap
/// above the bottom border.
@MainActor
@Suite("The last screenful fills the content area")
struct BottomShortfallTests {

    /// A handler with uniform three-line rows and a seventeen-line content area:
    /// the budget is sixteen and the suffixes are 15, 18, 21 — never 16.
    private func handler(
        granularity: ScrollGranularity = .line, rows: Int = 300, rowLines: Int = 3,
        contentHeight: Int = 17
    ) -> ItemListHandler<Int> {
        let handler = ItemListHandler<Int>(
            focusID: "table", itemCount: rows, viewportHeight: 5,
            selectionMode: .single, canBeFocused: true)
        handler.contentHeight = contentHeight
        handler.rowHeight = { _ in rowLines }
        handler.scrollGranularity = granularity
        // The "N more" lines are this view's indicator, and it overflows.
        handler.drawsScrollIndicators = true
        handler.showsScrollbar = false
        return handler
    }

    private func settle(_ handler: ItemListHandler<Int>) {
        handler.settleScrollPosition(
            measuring: false, overflowing: true, drawsTextIndicators: true, firstRowHeight: 3)
    }

    @Test("The whole-row bottom really does leave a line over")
    func theShortfallIsReal() throws {
        let handler = handler()
        let walk = try #require(handler.bottomWalk())
        #expect(walk.shortfall == 1, "16 lines of budget, 15 of rows: \(walk)")
        #expect(walk.straddlingHeight == 3, "the row that would not fit is three lines")
    }

    @Test("Line granularity: the bottom backs up a row and clips its head")
    func lineGranularityFillsTheBottom() throws {
        let handler = handler()
        let walk = try #require(handler.bottomWalk())
        handler.scrollOffset = walk.top  // the whole-row bottom
        settle(handler)
        #expect(handler.scrollOffset == walk.top - 1, "one row further back")
        #expect(
            handler.scrollTopClipLines == 2,
            "…with two of its three lines clipped away, so its tail fills the line")
    }

    /// Idempotent: the settle runs every frame, so a position it produced must be
    /// one it leaves alone. Otherwise the viewport walks up the list one row per
    /// frame for as long as it is on screen.
    @Test("Line granularity: settling twice changes nothing the second time")
    func fillingTheBottomIsStable() throws {
        let handler = handler()
        handler.scrollOffset = try #require(handler.bottomWalk()).top
        settle(handler)
        let once = (handler.scrollOffset, handler.scrollTopClipLines)
        settle(handler)
        #expect((handler.scrollOffset, handler.scrollTopClipLines) == once, "\(once)")
    }

    /// The control. A partial top row is exactly what row granularity forbids, so
    /// the blank line is the cost of whole rows there and must stay.
    @Test("Row granularity: the bottom stays whole-row, blank line and all")
    func rowGranularityIsUntouched() throws {
        let handler = handler(granularity: .row)
        let walk = try #require(handler.bottomWalk())
        handler.scrollOffset = walk.top
        settle(handler)
        #expect(handler.scrollOffset == walk.top)
        #expect(handler.scrollTopClipLines == 0)
    }

    /// Anywhere above the bottom the rows already fill the budget, and the clip
    /// belongs to whoever put it there — a wheel tick, a centred anchor, a reveal.
    @Test("Above the bottom, nothing is touched")
    func onlyTheBottomIsFilled() throws {
        let handler = handler()
        let walk = try #require(handler.bottomWalk())
        handler.scrollOffset = walk.top - 4
        handler.scrollTopClipLines = 1
        settle(handler)
        #expect(handler.scrollOffset == walk.top - 4)
        #expect(handler.scrollTopClipLines == 1)
    }

    /// A viewport whose rows DO sum to the budget has no shortfall to spend, and
    /// must be left on its row boundary.
    @Test("No shortfall, no change")
    func exactFitIsUntouched() throws {
        // Two-line rows in a 17-line area: the budget is 16 and eight rows fit it
        // exactly.
        let handler = handler(rowLines: 2)
        let walk = try #require(handler.bottomWalk())
        #expect(walk.shortfall == 0, "the fixture really does fit: \(walk)")
        handler.scrollOffset = walk.top
        settle(handler)
        #expect(handler.scrollOffset == walk.top)
        #expect(handler.scrollTopClipLines == 0)
    }
}

/// The same rule from the outside: the rendered box has no blank line in it.
///
/// This is the shape the bug was reported in — "the Fixed height table demo
/// scrolls one line too far when it gets to the end, when Scrollbar is off". The
/// handler-level suite above pins the arithmetic; this pins the picture, which is
/// what anyone actually looks at.
@MainActor
@Suite("The bottom of a table has no blank line")
struct TableBottomBlankLineTests {

    private struct Note: Identifiable {
        let id: Int
        /// Wraps to exactly three lines in the fixture's column, so no suffix of
        /// the rows can sum to the sixteen-line budget.
        var note: String {
            "row \(id) alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima"
        }
    }

    /// A live-ish host: one `TUIContext` and one `FocusManager` across frames,
    /// because the handler's scroll offset is `@State` and the settle runs per
    /// frame.
    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let focus = FocusManager()
        let granularity: ScrollGranularity

        init(granularity: ScrollGranularity) { self.granularity = granularity }

        func frame() -> [String] {
            let rows = (1...300).map(Note.init(id:))
            let table = Table(rows, selection: .constant(Int?.none)) {
                TableColumn("Note", value: \Note.note).width(.flexible).lineLimit(3)
            }
            .frame(height: 20)

            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.scrollGranularity = granularity
            environment.scrollIndicatorStyle = .text
            environment.verticalScrollIndicatorVisibility = .automatic
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 46, availableHeight: 24, environment: environment,
                tuiContext: tui)

            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            let buffer = renderToBuffer(table, context: context)
            focus.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped }
        }

        /// Focus the table (it takes focus on Tab even with selection off) and
        /// drive it to the last row. Twice, because the reveal budgets against
        /// the frame it can see and the frame after it is the one that settles.
        func scrollToTheEnd() -> [String] {
            _ = frame()
            _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
            _ = frame()
            for _ in 0..<2 {
                _ = focus.dispatchKeyEvent(KeyEvent(key: .end))
                _ = frame()
            }
            return frame()
        }
    }

    /// Where the box's content lines are: past the header, short of the bottom
    /// border.
    private func contentLines(_ lines: [String]) throws -> [String] {
        let top = try #require(lines.firstIndex { $0.contains("╭") }, "no box: \(lines)")
        let bottom = try #require(lines.firstIndex { $0.contains("╰") }, "no box: \(lines)")
        // +2: the top border and the column header.
        return lines[(top + 2)..<bottom].map { line in
            String(line.drop(while: { $0 != "│" }).dropFirst().dropLast())
        }
    }

    @Test("Scrolled to the end, every line inside the box has content on it")
    func theEndOfTheTableIsFull() throws {
        let lines = Harness(granularity: .line).scrollToTheEnd()
        let content = try contentLines(lines)
        #expect(content.count == 17, "20 lines less two borders and a header: \(content.count)")
        #expect(
            !content.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
            "a blank line inside the box:\n\(lines.joined(separator: "\n"))")
        // The last row is on screen and nothing is announced below it, so this
        // really is the bottom — the fill has not scrolled the view short of it.
        // Its own last line is "…lima", three lines below the "row 300" one.
        #expect(
            content.contains { $0.contains("row 300") },
            "the last row is not on screen:\n\(lines.joined(separator: "\n"))")
        #expect(
            !content.contains { $0.contains("more rows below") },
            "not at the bottom after all:\n\(lines.joined(separator: "\n"))")
    }

    /// The control at the other end of the list: nothing to fill, nothing to fix.
    @Test("At the top of the table every line inside the box has content too")
    func theTopOfTheTableIsFull() throws {
        let harness = Harness(granularity: .line)
        _ = harness.frame()
        let content = try contentLines(harness.frame())
        #expect(
            !content.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
            "a blank line inside the box: \(content)")
    }
}
