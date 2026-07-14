//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListMultiLineScrollTests.swift
//
//  A List/Table that draws a scrollbar reserves NO "N more above/below" text
//  indicator line, so its rows fill the whole content area. `maxOffset` (and the
//  focus-reveal arithmetic) must therefore not reserve an indicator line when
//  `showsScrollbar` is set — otherwise the bottom over-scrolls by one row and a
//  blank row-height remainder appears below the last row (the multi-line-cells
//  demo's "double-height blank row"; clicking it focused the list and snapped it
//  to the top). When the list draws text indicators instead, the reservation is
//  correct and must stay.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scrollbar list scroll bounds (no trailing blank)")
struct ListMultiLineScrollTests {

    private func makeHandler(
        count: Int, rowHeight: Int, contentHeight: Int, showsScrollbar: Bool
    ) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: count, viewportHeight: 1, selectionMode: .single)
        handler.contentHeight = contentHeight
        handler.rowHeight = { _ in rowHeight }
        handler.showsScrollbar = showsScrollbar
        return handler
    }

    @Test("Multi-line scrollbar list: maxOffset fills the content area (no reserved indicator line)")
    func multiLineScrollbarMaxOffset() {
        // The demo shape: 12 rows of height 2 in a 6-line content area, scrollbar
        // shown. Rows 9,10,11 (heights 2+2+2 = 6) fill the area EXACTLY, so the
        // furthest offset is 9. Reserving an indicator line (contentHeight-1 = 5)
        // only fits rows 10,11 (4 lines) at offset 10 → a blank double-row.
        let bar = makeHandler(count: 12, rowHeight: 2, contentHeight: 6, showsScrollbar: true)
        bar.scrollOffset = 100  // force past the tail so maxOffset is exercised
        #expect(bar.maxOffset == 9, "scrollbar list fills the area, got \(bar.maxOffset)")

        // Without a scrollbar the "N more above" indicator genuinely eats a line,
        // so reserving it is correct: only rows 10,11 fit below the indicator.
        let text = makeHandler(count: 12, rowHeight: 2, contentHeight: 6, showsScrollbar: false)
        text.scrollOffset = 100
        #expect(text.maxOffset == 10, "text-indicator list reserves its line, got \(text.maxOffset)")
    }

    @Test("Single-line scrollbar list: maxOffset reaches the true last screenful")
    func singleLineScrollbarMaxOffset() {
        // 100 single-line rows, 6-line area, scrollbar. Offsets 94…99 fill the
        // area; furthest is 94. The reserved-indicator arithmetic returned 95 —
        // the "list ends one row short / a blank line at the bottom" report.
        let bar = makeHandler(count: 100, rowHeight: 1, contentHeight: 6, showsScrollbar: true)
        bar.scrollOffset = 1000
        #expect(bar.maxOffset == 94, "single-line scrollbar list reaches the bottom, got \(bar.maxOffset)")
    }

    @Test("Focus-reveal at the tail lands the last row flush with the bottom (scrollbar)")
    func focusRevealScrollbarBottom() {
        // Focusing the last of 12 two-line rows in a 6-line scrollbar list must
        // scroll to offset 9 (last three rows fill the area), not 10 (a blank
        // remainder). The reveal budget must claim the full height when a
        // scrollbar is shown.
        let bar = makeHandler(count: 12, rowHeight: 2, contentHeight: 6, showsScrollbar: true)
        bar.focusedIndex = 11
        bar.ensureFocusedItemVisible()
        #expect(bar.scrollOffset == 9, "reveal lands flush with the bottom, got \(bar.scrollOffset)")
    }
}
