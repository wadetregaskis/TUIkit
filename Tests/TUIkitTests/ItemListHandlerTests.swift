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

    @Test("Down arrow moves focus forward")
    func moveDownSimple() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 5,
            viewportHeight: 3,
            selectionMode: .single
        )

        let event = KeyEvent(key: .down)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 1)
    }

    @Test("Up arrow moves focus backward")
    func moveUpSimple() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 5,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.focusedIndex = 2

        let event = KeyEvent(key: .up)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 1)
    }

    @Test("Down arrow wraps to start at end")
    func wrapDownToStart() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.focusedIndex = 2  // Last item

        let event = KeyEvent(key: .down)
        _ = handler.handleKeyEvent(event)

        #expect(handler.focusedIndex == 0)  // Wrapped to first
    }

    @Test("Up arrow wraps to end at start")
    func wrapUpToEnd() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 3,
            selectionMode: .single
        )
        handler.focusedIndex = 0  // First item

        let event = KeyEvent(key: .up)
        _ = handler.handleKeyEvent(event)

        #expect(handler.focusedIndex == 2)  // Wrapped to last
    }

    @Test("Home key jumps to first item")
    func homeJumpsToFirst() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 7

        let event = KeyEvent(key: .home)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 0)
    }

    @Test("End key jumps to last item")
    func endJumpsToLast() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 2

        let event = KeyEvent(key: .end)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 9)
    }

    @Test("PageDown moves by viewport height")
    func pageDownMovesViewport() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 2

        let event = KeyEvent(key: .pageDown)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 7)  // 2 + 5
    }

    @Test("PageUp moves by viewport height")
    func pageUpMovesViewport() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 10

        let event = KeyEvent(key: .pageUp)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(handler.focusedIndex == 5)  // 10 - 5
    }

    @Test("PageDown clamps at end without wrapping")
    func pageDownClampsAtEnd() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 8

        let event = KeyEvent(key: .pageDown)
        _ = handler.handleKeyEvent(event)

        #expect(handler.focusedIndex == 9)  // Clamped to last
    }

    @Test("PageUp clamps at start without wrapping")
    func pageUpClampsAtStart() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 10,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.focusedIndex = 2

        let event = KeyEvent(key: .pageUp)
        _ = handler.handleKeyEvent(event)

        #expect(handler.focusedIndex == 0)  // Clamped to first
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

    @Test("Empty list handles navigation gracefully")
    func emptyListNavigation() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 0,
            viewportHeight: 5,
            selectionMode: .single
        )

        let event = KeyEvent(key: .down)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == false)
        #expect(handler.focusedIndex == 0)
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

    @Test("scroll(by:) clamps to top")
    func scrollClampsToTop() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        handler.scrollOffset = 2

        handler.scroll(by: -10)

        #expect(handler.scrollOffset == 0)
    }

    @Test("scroll(by:) clamps to bottom")
    func scrollClampsToBottom() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 20,
            viewportHeight: 5,
            selectionMode: .single
        )
        // maxOffset = 20 - 5 = 15
        handler.scrollOffset = 10

        handler.scroll(by: 20)

        #expect(handler.scrollOffset == 15)
    }

    @Test("scroll(by:) is a no-op when content fits in viewport")
    func scrollNoOpWhenAllContentVisible() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 3,
            viewportHeight: 10,
            selectionMode: .single
        )

        handler.scroll(by: 5)

        #expect(handler.scrollOffset == 0, "nothing to scroll when content fits")
    }

    // MARK: - clampScrollOffset() — bounds check after data changes

    @Test("clampScrollOffset() snaps to maxOffset when itemCount drops")
    func clampScrollOffsetSnapsWhenItemCountDrops() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.scrollOffset = 50

        // Simulate a filter narrowing the list to 5 items.
        // maxOffset becomes max(0, 5 - 10) = 0 — everything fits.
        handler.itemCount = 5
        handler.clampScrollOffset()

        #expect(handler.scrollOffset == 0)
    }

    @Test("clampScrollOffset() snaps to new maxOffset when content still overflows")
    func clampScrollOffsetSnapsToNewMax() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.scrollOffset = 80

        // Filter narrows to 30 — still overflows, but the max is
        // lower than the existing offset. Clamp should bring it to
        // max(0, 30 - 10) = 20.
        handler.itemCount = 30
        handler.clampScrollOffset()

        #expect(handler.scrollOffset == 20)
    }

    @Test("clampScrollOffset() leaves a still-valid scrollOffset alone")
    func clampScrollOffsetLeavesValidOffsetAlone() {
        let handler = ItemListHandler<String>(
            focusID: "test",
            itemCount: 100,
            viewportHeight: 10,
            selectionMode: .single
        )
        handler.scrollOffset = 5

        handler.clampScrollOffset()

        #expect(handler.scrollOffset == 5)
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
