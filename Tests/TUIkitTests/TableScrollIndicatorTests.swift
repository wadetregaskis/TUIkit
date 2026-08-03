//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableScrollIndicatorTests.swift
//
//  A "▲ N more" indicator spends a content line to report that content is
//  hidden. Where it hides no more lines than it costs, drawing it is pure
//  loss: the line reads "1 more row above" in the very place that row would
//  have been. These tests pin the rule that the window absorbs such an
//  offset and shows the content itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct Note: Identifiable, Sendable {
    let id: Int
    var name: String { "row \(id)" }
    /// A two-line cell value, for the line-granularity cases where a row is
    /// taller than the clip being absorbed.
    var twoLine: String { "row \(id)\ndetail \(id)" }
}

@MainActor
@Suite("Table scroll indicators")
struct TableScrollIndicatorTests {
    /// Top border + column header + bottom border leave `height - 3` lines of
    /// content, so 14 gives 11 — and the reveal budgets rows against 9 of them
    /// (it reserves a line for each of the two indicators).
    private static let height = 14

    /// A table whose rows are all one line tall, taking the MULTI-LINE layout
    /// path (any column with a line limit above 1 does that) — the path the
    /// fixed-height demo uses.
    private func renderFrame(
        tui: TUIContext, fm: FocusManager,
        twoLineRows: Bool = false,
        granularity: ScrollGranularity = .row,
        scrollbar: ScrollbarVisibility = .hidden
    ) -> [String] {
        renderBuffer(
            tui: tui, fm: fm, twoLineRows: twoLineRows, granularity: granularity,
            scrollbar: scrollbar
        ).lines.map { $0.stripped }
    }

    private func renderBuffer(
        tui: TUIContext, fm: FocusManager,
        twoLineRows: Bool = false,
        granularity: ScrollGranularity = .row,
        scrollbar: ScrollbarVisibility = .hidden
    ) -> FrameBuffer {
        let rows = (0..<20).map(Note.init(id:))
        let table = Table(rows, selection: .constant(Int?.none)) {
            twoLineRows
                ? TableColumn("Name", value: \Note.twoLine).lineLimit(2)
                : TableColumn("Name", value: \Note.name).lineLimit(2)
        }
        .frame(height: Self.height)

        var env = EnvironmentValues()
        env.focusManager = fm
        env.scrollGranularity = granularity
        env.scrollbarVisibility = scrollbar
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.height, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(table, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// Walking the cursor down lands the reveal on an offset of exactly one
    /// row. That row is a single line, and the indicator that would announce
    /// it costs a single line — so the row itself must be drawn instead.
    @Test("An above-indicator that would hide one line shows that line instead")
    func aboveIndicatorMustEarnItsLine() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm)  // registers + auto-focuses the table

        var lines: [String] = []
        for _ in 0..<9 {
            _ = fm.dispatchKeyEvent(KeyEvent(key: .down))
            lines = renderFrame(tui: tui, fm: fm)
        }

        #expect(
            !lines.contains { $0.contains("1 more row above") },
            "the indicator hid a single line, which it also costs: \(lines)")
        #expect(
            lines.contains { $0.contains("row 0") },
            "row 0 fits in the line the indicator wanted: \(lines)")
        // The cursor's row stays visible — absorbing the offset must not cost
        // the reveal its target.
        #expect(lines.contains { $0.contains("row 9") }, "cursor row scrolled off: \(lines)")
    }

    /// The converse: an indicator that hides more than its own line is worth
    /// drawing, and still is.
    @Test("An above-indicator that hides more than a line is still drawn")
    func aboveIndicatorSurvivesWhenItEarnsItsLine() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm)

        var lines: [String] = []
        for _ in 0..<12 {
            _ = fm.dispatchKeyEvent(KeyEvent(key: .down))
            lines = renderFrame(tui: tui, fm: fm)
        }

        #expect(
            lines.contains { $0.contains("more rows above") },
            "several rows are hidden; the indicator earns its line: \(lines)")
        #expect(!lines.contains { $0.contains("row 0") }, "row 0 should be scrolled away: \(lines)")
    }

    /// Line granularity, one fine step into two-line rows: the window absorbs
    /// the single clipped line (offset 0, clip 1 — the indicator would cost
    /// exactly what it hides), so the renderer must draw that line. It used to
    /// clip by the handler's RAW `scrollTopClipLines` instead of the window's
    /// absorbed origin: the absorbed line silently vanished — no row, no
    /// indicator — and every rendered row sat one line above its hit band.
    @Test("An absorbed line-granularity clip draws the absorbed line")
    func absorbedLineClipRendersTheAbsorbedLine() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)

        let handler = fm.currentFocused as? ItemListHandler<Int>
        #expect(handler != nil, "the table auto-focuses; its handler is the focused element")
        #expect(handler?.scrollFine(by: 1) == true)
        #expect(handler?.scrollOffset == 0)
        #expect(handler?.scrollTopClipLines == 1, "one line clipped off the two-line top row")

        let lines = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)
        #expect(
            !lines.contains { $0.contains("more row above") },
            "one hidden line is absorbed, not announced: \(lines)")
        #expect(
            lines.contains { $0.contains("row 0") },
            "the absorbed line must actually be drawn: \(lines)")
        // And it is drawn at the window's origin — the first content line
        // (border, header, then rows), with its second line right below,
        // exactly where the hit bands expect the row.
        #expect(lines.count > 3 && lines[2].contains("row 0") && lines[3].contains("detail 0"),
            "the absorbed row starts at the window origin: \(lines)")
    }

    /// The converse under line granularity: a two-line clip hides more than
    /// the indicator costs, so the indicator shows and the window's clip and
    /// the renderer's agree (no absorption to diverge on).
    @Test("A two-line clip keeps the indicator and clips exactly that much")
    func unabsorbedLineClipKeepsIndicator() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)

        let handler = fm.currentFocused as? ItemListHandler<Int>
        // Three fine lines through two-line rows: offset 1, clip 1 —
        // three lines hidden above, more than the indicator's one-line cost.
        #expect(handler?.scrollFine(by: 3) == true)
        #expect(handler?.scrollOffset == 1)
        #expect(handler?.scrollTopClipLines == 1)

        let lines = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)
        // The count reads whole hidden rows (row 0) — the partially-clipped
        // top row isn't counted, but its clip still earns the indicator.
        #expect(
            lines.contains { $0.contains("1 more row above") },
            "three hidden lines earn the indicator: \(lines)")
        #expect(
            !lines.contains { $0.contains("row 0") } && !lines.contains { $0.contains("row 1 ") },
            "row 0 and row 1's first line are scrolled away: \(lines)")
        #expect(
            lines.count > 3 && lines[3].contains("detail 1"),
            "the clipped top row enters at its second line, under the indicator: \(lines)")
    }

    /// The multi-line path shares `settleRestingOffset` with the single-line
    /// path and _ListCore: a viewport at rest on offset 1 (row granularity,
    /// no scrollbar) snaps to 0 — the "▲ 1 more row above" line shows the
    /// row's first line instead of announcing it.
    @Test("A multi-line table resting at offset 1 settles to 0")
    func multiLineRestingOffsetSettles() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true)

        let handler = fm.currentFocused as? ItemListHandler<Int>
        #expect(handler != nil)
        handler?.scrollOffset = 1

        let lines = renderFrame(tui: tui, fm: fm, twoLineRows: true)
        #expect(handler?.scrollOffset == 0, "the shared resting rule snaps off offset 1")
        #expect(
            lines.contains { $0.contains("row 0") },
            "row 0 shows in place of the indicator: \(lines)")
        #expect(
            !lines.contains { $0.contains("1 more row above") },
            "no indicator for the settled offset: \(lines)")
    }

    /// …but never off a legitimate line-granularity rest: a fine wheel tick
    /// through tall rows lands on offset 1 with no clip, and snapping that
    /// back would make the table unscrollable at the top.
    @Test("A line-granularity mid-row rest at offset 1 is not settled")
    func lineGranularityRestSurvivesSettling() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)

        let handler = fm.currentFocused as? ItemListHandler<Int>
        #expect(handler?.scrollFine(by: 2) == true)
        #expect(handler?.scrollOffset == 1 && handler?.scrollTopClipLines == 0)

        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true, granularity: .line)
        #expect(
            handler?.scrollOffset == 1,
            "a tall first row makes offset 1 a legitimate fine-scroll rest")
    }

    /// The multi-line resolve must re-sync the scrollbar/indicator flags every
    /// frame: it draws indicator lines and never a bar, and stale values from
    /// a single-line frame (rows can switch paths as data changes) mis-budget
    /// the focus-reveal arithmetic.
    @Test("The multi-line resolve syncs the scrollbar/indicator flags")
    func multiLineResolveSyncsChromeFlags() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true)

        let handler = fm.currentFocused as? ItemListHandler<Int>
        #expect(handler != nil)
        // As if left behind by a single-line frame that showed a scrollbar.
        handler?.showsScrollbar = true
        handler?.drawsScrollIndicators = false

        _ = renderFrame(tui: tui, fm: fm, twoLineRows: true)
        #expect(handler?.showsScrollbar == false, "this path never draws a bar")
        #expect(handler?.drawsScrollIndicators == true, "overflow marks rows with indicator lines")
    }

    // MARK: - Scrollbars (multi-line path)

    /// The multi-line layout path used to draw no scrollbar at all — it marked
    /// hidden rows with "N more" lines and nothing else, so `.scrollbarVisibility`
    /// was silently inert on any table with a multi-line column, and a table
    /// whose columns merely ALLOW two lines (this one: every row is one line)
    /// lost the bar a single-line table would have drawn.
    @Test("A multi-line table honours .scrollbarVisibility(.visible)")
    func multiLineTableDrawsAScrollbar() {
        let tui = TUIContext()
        let fm = FocusManager()
        let lines = renderFrame(tui: tui, fm: fm, scrollbar: .visible)
        let body = lines.joined(separator: "\n")
        #expect(
            !body.contains("more rows below"),
            "the bar supersedes the text indicators:\n\(body)")
        #expect(
            lines.contains { $0.contains("█") || $0.contains("▓") || $0.contains("▲") },
            "a bar (thumb or arrow) is drawn:\n\(body)")
    }

    /// A bar takes a column, not a line, so the rows get the WHOLE content area
    /// — one more row than the indicator layout leaves.
    @Test("A scrollbar costs a column, not a content line")
    func scrollbarFreesTheIndicatorLine() {
        let withBar = renderFrame(tui: TUIContext(), fm: FocusManager(), scrollbar: .visible)
        let withIndicators = renderFrame(tui: TUIContext(), fm: FocusManager())
        #expect(withBar.count == withIndicators.count, "the frame height is unchanged")
        func rowCount(_ lines: [String]) -> Int { lines.filter { $0.contains("row ") }.count }
        #expect(
            rowCount(withBar) == rowCount(withIndicators) + 1,
            "the freed indicator line shows another row: \(rowCount(withBar)) vs \(rowCount(withIndicators))")
    }

    /// Hidden is the default, and stays the default: nothing about the bar
    /// support may make an un-asked-for one appear.
    @Test("Without an opt-in a multi-line table still draws indicators")
    func hiddenVisibilityKeepsIndicators() {
        let body = renderFrame(tui: TUIContext(), fm: FocusManager()).joined(separator: "\n")
        #expect(body.contains("more rows below"), "the default chrome is unchanged:\n\(body)")
    }

    /// The bar is a real control: it publishes a hit region in its own column,
    /// so clicks and drags on it reach the scrollbar handler (the same wiring
    /// the single-line path and the `List` use).
    @Test("The multi-line scrollbar is clickable")
    func multiLineScrollbarHasAHitRegion() {
        let tui = TUIContext()
        let fm = FocusManager()
        let buffer = renderBuffer(tui: tui, fm: fm, scrollbar: .visible)
        #expect(
            buffer.hitTestRegions.contains { $0.width == 1 && $0.height > 1 },
            "the bar's single-column region is published: \(buffer.hitTestRegions)")
    }

    /// With no indicator line to reserve, the furthest scroll is the true last
    /// screenful — the "list ends one row short / blank line at the bottom"
    /// class the `List` hit in `ListMultiLineScrollTests`.
    @Test("A scrollbar table scrolls to a flush bottom")
    func scrollbarTableReachesTheBottom() {
        let tui = TUIContext()
        let fm = FocusManager()
        _ = renderFrame(tui: tui, fm: fm, scrollbar: .visible)
        let handler = fm.currentFocused as? ItemListHandler<Int>
        #expect(handler != nil)
        handler?.scrollOffset = 1000
        let lines = renderFrame(tui: tui, fm: fm, scrollbar: .visible)
        let body = lines.joined(separator: "\n")
        #expect(lines.contains { $0.contains("row 19") }, "the last row is reachable:\n\(body)")
        #expect(
            lines.filter { $0.contains("row ") }.count == 11,
            "all 11 content lines carry rows — no reserved indicator line, no blank remainder:\n\(body)")
    }
}
