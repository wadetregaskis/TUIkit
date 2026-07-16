//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandlerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Item List Handler Navigation Tests

@MainActor
@Suite("ItemListHandler Navigation Tests")
struct ItemListHandlerNavigationTests {

    @Test(
        "A movement key moves focus to the expected index",
        arguments: [
            // (key, itemCount, viewportHeight, startIndex, expectedHandled, expectedIndex)
            (Key.down, 5, 3, 0, true, 1),  // down moves forward
            (.up, 5, 3, 2, true, 1),  // up moves backward
            (.down, 3, 3, 2, true, 0),  // down wraps to start at the end
            (.up, 3, 3, 0, true, 2),  // up wraps to the end at the start
            (.home, 10, 5, 7, true, 0),  // home jumps to first
            (.end, 10, 5, 2, true, 9),  // end jumps to last
            (.pageDown, 20, 5, 2, true, 7),  // pageDown moves by viewport height
            (.pageUp, 20, 5, 10, true, 5),  // pageUp moves by viewport height
            (.pageDown, 10, 5, 8, true, 9),  // pageDown clamps at the end (no wrap)
            (.pageUp, 10, 5, 2, true, 0),  // pageUp clamps at the start (no wrap)
            (.down, 0, 5, 0, false, 0),  // empty list: unhandled, index pinned
        ])
    func movementKey(
        key: Key, itemCount: Int, viewportHeight: Int,
        startIndex: Int, expectedHandled: Bool, expectedIndex: Int
    ) {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: itemCount,
            viewportHeight: viewportHeight,
            selectionMode: .single
        )
        handler.focusedIndex = startIndex

        let handled = handler.handleKeyEvent(KeyEvent(key: key))

        #expect(handled == expectedHandled)
        #expect(handler.focusedIndex == expectedIndex)
    }

    @Test("Shift+Down moves by the step multiplier and clamps at the end")
    func shiftDownAccelerates() {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 20, viewportHeight: 5, selectionMode: .single)
        handler.shiftStepMultiplier = 5

        _ = handler.handleKeyEvent(KeyEvent(key: .down, ctrl: false, alt: false, shift: true))
        #expect(handler.focusedIndex == 5, "Shift+Down jumps 5: \(handler.focusedIndex)")

        handler.focusedIndex = 18
        _ = handler.handleKeyEvent(KeyEvent(key: .down, ctrl: false, alt: false, shift: true))
        #expect(handler.focusedIndex == 19, "clamps at the last row instead of wrapping: \(handler.focusedIndex)")
    }

    @Test("Shift+Up moves by the step multiplier and clamps at the top")
    func shiftUpAccelerates() {
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 20, viewportHeight: 5, selectionMode: .single)
        handler.shiftStepMultiplier = 5
        handler.focusedIndex = 12

        _ = handler.handleKeyEvent(KeyEvent(key: .up, ctrl: false, alt: false, shift: true))
        #expect(handler.focusedIndex == 7, "Shift+Up jumps 5 back: \(handler.focusedIndex)")

        handler.focusedIndex = 2
        _ = handler.handleKeyEvent(KeyEvent(key: .up, ctrl: false, alt: false, shift: true))
        #expect(handler.focusedIndex == 0, "clamps at the top instead of wrapping: \(handler.focusedIndex)")
    }

    @Test("PageDown with selectableIndices lands on nearest selectable index")
    func pageDownWithSelectableIndices() {
        // 10 items: indices 0,2,3,5,6,8,9 are selectable; 1,4,7 are headers
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.selectableIndices = [0, 2, 3, 5, 6, 8, 9]
        handler.focusedIndex = 0

        // PageDown by 3: target is index 3, which is selectable
        let event = KeyEvent(key: .pageDown)
        _ = handler.handleKeyEvent(event)
        #expect(handler.focusedIndex == 3)

        // Now at 3, PageDown by 3: target is index 6, which is selectable
        _ = handler.handleKeyEvent(event)
        #expect(handler.focusedIndex == 6)
    }

    @Test("PageDown landing on header finds nearest selectable")
    func pageDownLandingOnHeader() {
        // 10 items: indices 1,4,7 are headers (non-selectable)
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 4,
            selectionMode: .single
        )
        handler.selectableIndices = [0, 2, 3, 5, 6, 8, 9]
        handler.focusedIndex = 0

        // PageDown by 4: target is index 4, which is a header
        // Should land on index 5 (next selectable), not skip to index 8
        let event = KeyEvent(key: .pageDown)
        _ = handler.handleKeyEvent(event)
        #expect(handler.focusedIndex == 5)
    }

    @Test("PageUp landing on header finds nearest selectable")
    func pageUpLandingOnHeader() {
        // 10 items: indices 1,4,7 are headers (non-selectable)
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.selectableIndices = [0, 2, 3, 5, 6, 8, 9]
        handler.focusedIndex = 8

        // PageUp by 3: target is index 5, which is selectable
        let event = KeyEvent(key: .pageUp)
        _ = handler.handleKeyEvent(event)
        #expect(handler.focusedIndex == 5)

        // Now at 5, PageUp by 3: target is index 2, which is selectable
        _ = handler.handleKeyEvent(event)
        #expect(handler.focusedIndex == 2)
    }

    @Test("PageUp within one page of the top reaches the first item (overshoot clamps, not stalls)")
    func pageUpOvershootReachesTop() {
        // All rows selectable, but selectableIndices is *populated* — exactly
        // how a normal selectable list (e.g. the emoji corpus) is set up, and
        // the path the boundary bug lived in. Previously PageUp here refused
        // to move because the target (5 - 10 = -5) was out of bounds.
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.selectableIndices = Set(0..<100)
        handler.focusedIndex = 5  // within one page of the top

        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))
        #expect(handler.focusedIndex == 0)
    }

    @Test("PageDown within one page of the bottom reaches the last item")
    func pageDownOvershootReachesBottom() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.selectableIndices = Set(0..<100)
        handler.focusedIndex = 95  // within one page of the bottom

        _ = handler.handleKeyEvent(KeyEvent(key: .pageDown))
        #expect(handler.focusedIndex == 99)
    }

    @Test("Page jumps overshooting a boundary land on the nearest selectable item")
    func pageOvershootWithHeadersLandsOnBoundarySelectable() {
        // 1, 4, 7 are headers; first selectable is 0, last is 9.
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.selectableIndices = [0, 2, 3, 5, 6, 8, 9]

        handler.focusedIndex = 2
        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))  // target -1 → first selectable
        #expect(handler.focusedIndex == 0)

        handler.focusedIndex = 8
        _ = handler.handleKeyEvent(KeyEvent(key: .pageDown))  // target 11 → last selectable
        #expect(handler.focusedIndex == 9)
    }
}

// MARK: - Item List Handler Selection Tests

@MainActor
@Suite("ItemListHandler Selection Tests")
struct ItemListHandlerSelectionTests {

    @Test("Enter toggles single selection")
    func enterTogglesSingle() {
        var selectedID: String?
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = Binding(
            get: { selectedID },
            set: { selectedID = $0 }
        )
        handler.focusedIndex = 1

        let event = KeyEvent(key: .enter)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(selectedID == "b")
    }

    @Test("Space toggles single selection")
    func spaceTogglesSingle() {
        var selectedID: String?
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = Binding(
            get: { selectedID },
            set: { selectedID = $0 }
        )
        handler.focusedIndex = 2

        let event = KeyEvent(key: .space)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(selectedID == "c")
    }

    @Test("Single selection can be deselected by selecting again")
    func singleDeselect() {
        var selectedID: String? = "a"
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = Binding(
            get: { selectedID },
            set: { selectedID = $0 }
        )
        handler.focusedIndex = 0  // Already selected

        let event = KeyEvent(key: .enter)
        _ = handler.handleKeyEvent(event)

        #expect(selectedID == nil)  // Deselected
    }

    @Test("Multi selection adds to set")
    func multiSelectionAdds() {
        var selected: Set<String> = []
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .multi
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.multiSelection = Binding(
            get: { selected },
            set: { selected = $0 }
        )
        handler.focusedIndex = 1

        let event = KeyEvent(key: .enter)
        _ = handler.handleKeyEvent(event)

        #expect(selected.contains("b"))
        #expect(selected.count == 1)
    }

    @Test("Multi selection toggles items")
    func multiSelectionToggles() {
        var selected: Set<String> = ["b"]
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .multi
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.multiSelection = Binding(
            get: { selected },
            set: { selected = $0 }
        )
        handler.focusedIndex = 1  // Already selected

        let event = KeyEvent(key: .enter)
        _ = handler.handleKeyEvent(event)

        #expect(!selected.contains("b"))  // Removed
        #expect(selected.isEmpty)
    }

    @Test("isSelected returns correct state")
    func isSelectedReturnsCorrectState() {
        var selectedID: String? = "b"
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = Binding(
            get: { selectedID },
            set: { selectedID = $0 }
        )

        #expect(handler.isSelected(at: 0) == false)
        #expect(handler.isSelected(at: 1) == true)
        #expect(handler.isSelected(at: 2) == false)
    }

    @Test("isFocused returns correct state")
    func isFocusedReturnsCorrectState() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.focusedIndex = 1

        #expect(handler.isFocused(at: 0) == false)
        #expect(handler.isFocused(at: 1) == true)
        #expect(handler.isFocused(at: 2) == false)
    }
}

// MARK: - Item List Handler Scroll Tests

@MainActor
@Suite("ItemListHandler Scroll Tests")
struct ItemListHandlerScrollTests {

    @Test("Scroll offset adjusts when focus moves below viewport")
    func scrollDownOnFocusBelowViewport() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.focusedIndex = 5
        handler.ensureFocusedItemVisible()

        #expect(handler.scrollOffset == 3)  // 5 - 3 + 1 = 3
    }

    @Test("Scroll offset adjusts when focus moves above viewport")
    func scrollUpOnFocusAboveViewport() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.scrollOffset = 5
        handler.focusedIndex = 2
        handler.ensureFocusedItemVisible()

        #expect(handler.scrollOffset == 2)
    }

    @Test("Height-aware reveal scrolls a tall tail into view (clamped to the bottom)")
    func heightAwareScrollReveal() {
        // 5 rows of heights [1, 3, 1, 3, 1] in a 5-line content area. A
        // multi-line table sets viewportHeight so the handler's maxOffset equals
        // the height-aware furthest scroll (3 here), and supplies a rowHeight
        // closure so the reveal accumulates real heights rather than assuming one
        // line per row.
        let rowHeights = [1, 3, 1, 3, 1]
        let handler = ItemListHandler<String>(
            focusID: "test", itemCount: 5, viewportHeight: 2, selectionMode: .single)
        handler.contentHeight = 5
        handler.rowHeight = { rowHeights[$0] }

        handler.focusedIndex = 4
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset == 3, "tall tail reveal clamps to the bottom, got \(handler.scrollOffset)")

        handler.focusedIndex = 0
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset == 0, "focusing the first row scrolls fully up")
    }

    @Test("hasContentAbove returns correct state")
    func hasContentAboveState() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )

        handler.scrollOffset = 0
        #expect(handler.hasContentAbove == false)

        handler.scrollOffset = 3
        #expect(handler.hasContentAbove == true)
    }

    @Test("hasContentBelow returns correct state")
    func hasContentBelowState() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )

        handler.scrollOffset = 0
        #expect(handler.hasContentBelow == true)

        handler.scrollOffset = 7  // 7 + 3 = 10 = itemCount
        #expect(handler.hasContentBelow == false)
    }

    @Test("visibleRange returns correct range")
    func visibleRangeCorrect() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.scrollOffset = 4

        let range = handler.visibleRange
        #expect(range == 4..<7)
    }

    @Test("visibleRange clamps to item count")
    func visibleRangeClampsToItemCount() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 5,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.scrollOffset = 0

        let range = handler.visibleRange
        #expect(range == 0..<5)
    }

    // MARK: - scroll(by:) — wheel scrolling, independent of focus

    @Test("scroll(by:) moves scrollOffset but not focusedIndex")
    func scrollDoesNotChangeFocus() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 7
        handler.scrollOffset = 5

        handler.scroll(by: 3)

        #expect(handler.scrollOffset == 8)
        #expect(handler.focusedIndex == 7, "scroll must not move focus")
    }

    @Test("scroll(by:) can scroll the focused item out of view")
    func scrollCanMoveFocusOutOfViewport() {
        // The whole point: arrow keys and the wheel are separate
        // axes. If the wheel happens to scroll past the focused
        // row, that's fine — pressing an arrow key will scroll back
        // to it via ensureFocusedItemVisible().
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 2
        handler.scrollOffset = 0

        handler.scroll(by: 10)

        #expect(handler.scrollOffset == 10)
        #expect(handler.focusedIndex == 2, "wheel scroll must not pull focus along with it")
        #expect(!handler.visibleRange.contains(handler.focusedIndex),
            "focus should now be outside the visible range — that's the expected, documented behaviour")
    }

    @Test(
        "scroll(by:) clamps to the scrollable bounds",
        arguments: [
            // (itemCount, viewportHeight, initialOffset, delta, expectedOffset)
            (20, 5, 2, -10, 0),  // clamps to top
            (20, 5, 10, 20, 15),  // clamps to bottom (maxOffset = 20 − 5)
            (3, 10, 0, 5, 0),  // no-op when content fits in the viewport
        ])
    func scrollClamps(
        itemCount: Int, viewportHeight: Int, initialOffset: Int, delta: Int, expectedOffset: Int
    ) {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: itemCount,
            viewportHeight: viewportHeight,
            selectionMode: .single
        )
        handler.scrollOffset = initialOffset

        handler.scroll(by: delta)

        #expect(handler.scrollOffset == expectedOffset)
    }

    // MARK: - clampScrollOffset() — bounds check after data changes

    @Test(
        "clampScrollOffset() snaps to the new maxOffset after itemCount changes",
        arguments: [
            // (initialOffset, newItemCount, expectedOffset) — itemCount 100, viewport 10
            (50, 5, 0),  // filter narrows to fewer than a viewport: everything fits
            (80, 30, 20),  // still overflows: snaps to max(0, 30 − 10)
            (5, 100, 5),  // still-valid offset left alone
        ])
    func clampScrollOffset(initialOffset: Int, newItemCount: Int, expectedOffset: Int) {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.scrollOffset = initialOffset

        handler.itemCount = newItemCount
        handler.clampScrollOffset()

        #expect(handler.scrollOffset == expectedOffset)
    }

    @Test("clampScrollOffset() does NOT change focusedIndex")
    func clampScrollOffsetDoesNotChangeFocus() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.focusedIndex = 42
        handler.scrollOffset = 80
        handler.itemCount = 30  // shrinks below focusedIndex

        handler.clampScrollOffset()

        #expect(handler.scrollOffset == 20, "scrollOffset clamps")
        #expect(handler.focusedIndex == 42,
            "clampScrollOffset must NOT touch focusedIndex — that's ensureFocusedItemVisible's job")
    }

    // MARK: - Indicator-aware scroll-into-view (contentHeight set)

    /// With ``contentHeight`` set, the scroll-into-view logic reserves
    /// room for the scroll indicators. Scrolling into the middle must
    /// leave the focused row within the rows actually shown
    /// (contentHeight − 2 when both indicators are present) — never on
    /// the "N more below" indicator line; and focusing the last item
    /// must reach the true bottom (only the "more above" indicator
    /// shows there, so one extra row fits).
    @Test("Indicator-aware scroll keeps the focused row visible and reaches the true bottom")
    func indicatorAwareScrollIntoView() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,  // bottom-case viewport (contentHeight − 1)
            selectionMode: .single
        )
        handler.contentHeight = 6

        // Middle: both indicators show → 4 rows visible. The focused
        // row must fall within [scrollOffset, scrollOffset + 3].
        handler.focusedIndex = 6
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset <= 6)
        #expect(
            6 <= handler.scrollOffset + 3,
            "focused row must be within the 4 visible middle rows; scrollOffset=\(handler.scrollOffset)")

        // Bottom: "above" indicator + 5 rows (15…19) → offset 20 − 5.
        handler.focusedIndex = 19
        handler.ensureFocusedItemVisible()
        #expect(
            handler.scrollOffset == 15,
            "last item should sit at the true bottom (offset 15); got \(handler.scrollOffset)")
    }
}
