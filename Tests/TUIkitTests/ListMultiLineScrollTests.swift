//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListMultiLineScrollTests.swift
//
//  A List/Table that draws a scrollbar reserves NO "N more rows above/below" text
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

        // Without a scrollbar the "N more rows above" indicator genuinely eats a line,
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

    // MARK: - Mixed (non-uniform) row heights

    private func makeMixedHandler(
        heights: [Int], contentHeight: Int, showsScrollbar: Bool
    ) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: heights.count, viewportHeight: 1, selectionMode: .single)
        handler.contentHeight = contentHeight
        handler.rowHeight = { heights[$0] }
        handler.showsScrollbar = showsScrollbar
        return handler
    }

    @Test(
        "Mixed row heights: maxOffset is the smallest top whose tail fits the budget",
        arguments: [
            // (heights, contentHeight, showsScrollbar, expected)
            // Slack tail: rows 4,5 (1+4 = 5) leave one spare line in 6; row 3
            // (3 more) would overflow. Same answer either way here — the walk
            // breaks before the indicator reservation matters.
            ([1, 3, 2, 3, 1, 4], 6, true, 4),
            ([1, 3, 2, 3, 1, 4], 6, false, 4),
            // Exact fill vs indicator reservation: rows 2,3 (2+2) fill 4
            // exactly with a scrollbar, but only row 3 fits the reserved
            // 3-line budget of a text-indicator list.
            ([1, 1, 2, 2], 4, true, 2),
            ([1, 1, 2, 2], 4, false, 3),
            // Mid-walk budget growth: when row 0 comes into reach there is no
            // "above" indicator, so the budget grows to the full height and
            // everything (2+1+1 = 4) fits from the very top.
            ([2, 1, 1], 4, true, 0),
            ([2, 1, 1], 4, false, 0),
        ])
    func mixedHeightsMaxOffset(
        heights: [Int], contentHeight: Int, showsScrollbar: Bool, expected: Int
    ) {
        let handler = makeMixedHandler(
            heights: heights, contentHeight: contentHeight, showsScrollbar: showsScrollbar)
        handler.scrollOffset = heights.count  // past the tail: force the exact walk
        #expect(handler.maxOffset == expected, "got \(handler.maxOffset)")
    }

    @Test("Mixed row heights: focus-reveal of the last row lands flush with the bottom")
    func mixedHeightsFocusRevealFlushBottom() {
        let heights = [1, 3, 2, 3, 1, 4]
        let handler = makeMixedHandler(heights: heights, contentHeight: 6, showsScrollbar: true)
        handler.focusedIndex = heights.count - 1
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset == 4, "flush bottom, got \(handler.scrollOffset)")
        #expect(handler.scrollTopClipLines == 0, "no clip at a row-aligned bottom")
    }

    @Test("The cheap floor never exceeds the exact walk-back answer")
    func floorShortCircuitConsistency() {
        // 100 three-line rows in a 6-line scrollbar area: floor = 100 - 6 = 94,
        // exact walk = 98 (two rows of height 3 fill the budget). Far from the
        // tail the floor short-circuit answers; within reach the walk answers.
        // The floor is always <= the walk (every row is >= 1 line), so the
        // clamp can never bite on the way down.
        let handler = makeMixedHandler(
            heights: Array(repeating: 3, count: 100), contentHeight: 6, showsScrollbar: true)
        handler.scrollOffset = 0
        let floorAnswer = handler.maxOffset
        #expect(floorAnswer == 94, "far from the tail: the floor, got \(floorAnswer)")

        handler.scrollOffset = floorAnswer
        let walkAnswer = handler.maxOffset
        #expect(walkAnswer == 98, "within reach: the exact walk, got \(walkAnswer)")
        #expect(floorAnswer <= walkAnswer, "the floor is an under-estimate")

        // The clamp keeps an offset the floor allowed (94 <= 98).
        handler.clampScrollOffset()
        #expect(handler.scrollOffset == floorAnswer, "clamp does not scrub a floor-legal offset")
    }

    @Test("Seeded storm: mixed-height maxOffset + line-granular scroll invariants")
    func mixedHeightsSeededStorm() {
        var seed: UInt64 = 0x5EED_1157
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        func random(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }

        for trial in 0..<200 {
            let count = random(in: 1...30)
            let contentHeight = random(in: 2...10)
            let heights = (0..<count).map { _ in random(in: 1...4) }
            let showsScrollbar = next().isMultiple(of: 2)
            let handler = makeMixedHandler(
                heights: heights, contentHeight: contentHeight, showsScrollbar: showsScrollbar)
            handler.scrollOffset = count  // past the tail: force the exact walk
            let max = handler.maxOffset

            // Invariant 1: the tail from `max` fits its budget.
            func budget(top: Int) -> Int {
                (showsScrollbar || top == 0) ? contentHeight : contentHeight - 1
            }
            let tail = heights[max...].reduce(0, +)
            #expect(
                tail <= budget(top: max),
                "trial \(trial): tail \(tail) from \(max) exceeds budget \(budget(top: max)) — heights \(heights), h \(contentHeight), bar \(showsScrollbar)")
            // Invariant 2: `max` is the SMALLEST such top.
            if max > 0 {
                let widerTail = heights[(max - 1)...].reduce(0, +)
                #expect(
                    widerTail > budget(top: max - 1),
                    "trial \(trial): top \(max - 1) would also fit — heights \(heights), h \(contentHeight), bar \(showsScrollbar)")
            }

            // Line-granularity: scroll to both extremes and check the clip
            // never escapes the top row.
            handler.scrollOffset = 0
            handler.scrollTopClipLines = 0
            let totalLines = heights.reduce(0, +)
            for _ in 0..<(totalLines + 4) {
                handler.scrollFine(by: 1)
                #expect(handler.scrollTopClipLines >= 0)
                if handler.scrollOffset < count {
                    #expect(
                        handler.scrollTopClipLines < Swift.max(1, heights[handler.scrollOffset]),
                        "trial \(trial): clip \(handler.scrollTopClipLines) escapes row height")
                }
            }
            #expect(handler.scrollOffset == max, "trial \(trial): lands at the bottom")
            #expect(handler.scrollTopClipLines == 0, "trial \(trial): no clip at the bottom")

            for _ in 0..<(totalLines + 4) {
                handler.scrollFine(by: -1)
            }
            #expect(handler.scrollOffset == 0, "trial \(trial): lands at the top")
            #expect(handler.scrollTopClipLines == 0, "trial \(trial): no clip at the top")
        }
    }
}
