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
    private func renderFrame(tui: TUIContext, fm: FocusManager) -> [String] {
        let rows = (0..<20).map(Note.init(id:))
        let table = Table(rows, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Note.name).lineLimit(2)
        }
        .frame(height: Self.height)

        var env = EnvironmentValues()
        env.focusManager = fm
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
        return buffer.lines.map { $0.stripped }
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
}
