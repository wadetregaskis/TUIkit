//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

@MainActor
private func createTestContext(width: Int = 80, height: Int = 24) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

// MARK: - List Rendering Tests

@MainActor
@Suite("List Rendering Tests")
struct ListRenderingTests {

    @Test("Empty list shows placeholder")
    func emptyListPlaceholder() {
        let context = createTestContext()

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("No items"))
    }

    @Test("Empty list with explicit width fills the available width")
    func emptyListFillsExplicitWidth() {
        // SwiftUI's List is greedy on both axes. With a fixed frame width, an
        // empty list should expand to that width instead of collapsing to the
        // placeholder's natural size.
        var context = createTestContext(width: 50, height: 10)
        context.hasExplicitWidth = true

        var selection: String?
        let list = List(
            "My short title",
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }

        let buffer = renderToBuffer(list, context: context)
        // The border lines should be the full 50 cells wide, not collapsed to
        // the title (~18 cells) or the placeholder (~8 cells).
        #expect(buffer.width == 50, "expected width 50, got \(buffer.width)")
    }

    @Test("Custom empty placeholder is shown")
    func customEmptyPlaceholder() {
        let context = createTestContext()

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }
        .listEmptyPlaceholder("Nothing here")

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("Nothing here"))
    }

    @Test("List renders ForEach items")
    func listRendersForEachItems() {
        let context = createTestContext()

        struct Item: Identifiable {
            let id: String
            let name: String
        }
        let items = [
            Item(id: "1", name: "First"),
            Item(id: "2", name: "Second"),
            Item(id: "3", name: "Third"),
        ]

        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        #expect(content.contains("First"))
        #expect(content.contains("Second"))
        #expect(content.contains("Third"))
    }

    @Test("Selected item has accent indicator")
    func selectedItemIndicator() {
        let context = createTestContext()

        struct Item: Identifiable {
            let id: String
            let name: String
        }
        let items = [
            Item(id: "1", name: "First"),
            Item(id: "2", name: "Second"),
        ]

        var selection: String? = "2"
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        // Selected item should have a background color.
        // The exact format depends on ColorDepth: 48;2;r;g;b (truecolor),
        // 48;5;n (256-color), or 4x (16-color).
        let hasBackgroundColor =
            content.contains("[48;2;")
            || content.contains("[48;5;")
            || content.contains("[4")  // standard background codes 40-47, 100-107
        #expect(hasBackgroundColor)
    }

    @Test("Scroll indicators appear when needed")
    func scrollIndicatorsAppear() {
        struct Item: Identifiable {
            let id: Int
            let name: String
        }
        // Create list with more items than will fit in available height
        let items = (0..<20).map { Item(id: $0, name: "Item \($0)") }

        var selection: Int?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(items) { item in
                Text(item.name)
            }
        }

        // Use a small height context so scrolling is triggered
        let context = createTestContext(width: 40, height: 8)
        let buffer = renderToBuffer(list, context: context)
        let content = buffer.lines.joined()

        // Should have "more below" indicator since we have 20 items in height 8
        #expect(content.contains("▼") || content.contains("more below"))
    }

    @Test("Disabled list modifier works")
    func disabledListModifier() {
        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            EmptyView()
        }.disabled()

        #expect(list.isDisabled == true)
    }

    @Test("Multi-selection list can be created")
    func multiSelectionListCreation() {
        var selection: Set<String> = []
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            Text("Item")
        }

        #expect(list.selectionMode == .multi)
    }

    @Test("Single-selection list can be created")
    func singleSelectionListCreation() {
        var selection: String?
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            Text("Item")
        }

        #expect(list.selectionMode == .single)
    }

    @Test("List respects frame width constraint")
    func listRespectsFrameWidth() {
        let context = createTestContext(width: 80)

        var selection: String?
        let list = List(
            "Items",
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { item in
                Text(item)
            }
        }
        .frame(width: 20)

        let buffer = renderToBuffer(list, context: context)

        // The list should be constrained to 20 characters width
        #expect(buffer.width == 20, "Expected width 20, got \(buffer.width)")

        // The border should also be 20 characters wide (not just padded)
        let firstLine = buffer.lines.first ?? ""
        #expect(firstLine.strippedLength == 20, "Border should be 20 chars wide")
    }

    @Test("Two Lists in HStack both render")
    func twoListsInHStack() {
        // Use wider terminal to match real usage, with explicit width like WindowGroup
        var context = createTestContext(width: 160, height: 40)
        context.hasExplicitWidth = true

        var sel1: String?
        var sel2: Set<String> = []

        let items: [(String, String, String)] = [
            ("1", "README.md", "📄"), ("2", "Package.swift", "📦"),
            ("3", "Sources", "📁"), ("4", "Tests", "📁"),
            ("5", ".gitignore", "📄"), ("6", "LICENSE", "📄"),
            ("7", "docs", "📁"), ("8", "plans", "📁"),
            ("9", ".swiftlint.yml", "⚙️"), ("10", ".github", "📁"),
            ("11", "Makefile", "📄"), ("12", ".claude", "📁"),
        ]

        let view = HStack(spacing: 2) {
            List("Single Selection", selection: Binding(get: { sel1 }, set: { sel1 = $0 })) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 1) {
                        Text(item.2)
                        Text(item.1)
                    }
                }
            }
            List("Multi Selection", selection: Binding(get: { sel2 }, set: { sel2 = $0 })) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 1) {
                        Text(item.2)
                        Text(item.1)
                    }
                }
            }
        }

        let buffer = renderToBuffer(view, context: context)
        let allContent = buffer.lines.map { $0.stripped }.joined()

        #expect(allContent.contains("Single Selection"), "Should contain first list title")
        #expect(allContent.contains("Multi Selection"), "Should contain second list title, got buffer width \(buffer.width)")
        #expect(buffer.width <= 160, "Buffer should not exceed available width 160, got \(buffer.width)")

        // All lines should have the same visible width (consistent borders)
        let lineWidths = buffer.lines.map { $0.strippedLength }
        let maxLineWidth = lineWidths.max() ?? 0
        let minLineWidth = lineWidths.filter { $0 > 0 }.min() ?? 0
        #expect(
            minLineWidth == maxLineWidth,
            "All lines should have same width but min=\(minLineWidth) max=\(maxLineWidth)"
        )
    }

    // MARK: - Selectionless List inits

    @Test("Selectionless List with title and ForEach renders rows")
    func selectionlessListWithForEachRenders() {
        let context = createTestContext()
        let items = ["alpha", "beta", "gamma"]

        let view = List("Read-only") {
            ForEach(items, id: \.self) { Text($0) }
        }
        .frame(width: 30, height: 8)

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.map(\.stripped).joined(separator: "\n")

        #expect(content.contains("Read-only"), "title should render")
        for item in items {
            #expect(content.contains(item), "selectionless List should render row '\(item)'")
        }
    }

    @Test("Selectionless List with no title and bare content type-checks")
    func selectionlessListWithBareContentTypeChecks() {
        // Compile-time test: the Int-defaulted convenience init
        // should let `List { Text(...) }` type-check without the
        // caller having to spell out SelectionValue.
        let context = createTestContext()
        let view = List {
            Text("just a row")
        }
        .frame(width: 20, height: 5)

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(content.contains("just a row"))
    }

    @Test("Selectionless List with title and bare content type-checks")
    func selectionlessListWithTitleAndBareContentTypeChecks() {
        let context = createTestContext()
        let view = List("My Title") {
            Text("row body")
        }
        .frame(width: 20, height: 5)

        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(content.contains("My Title"))
        #expect(content.contains("row body"))
    }

    // MARK: - Wheel scrolling vs. selection visibility

    @Test("Wheel scroll can move the focused row out of view (not clamped each render)")
    func wheelScrollSurvivesRender() {
        // Regression test for the bug where _ListCore.renderToBuffer
        // called handler.ensureFocusedItemVisible() on every render
        // — so the wheel-driven scrollOffset got scrubbed back to
        // whatever kept the focused row visible. The interaction
        // model is "wheel scrolls the viewport independently of
        // the focused row" (matching Finder / Explorer / VS Code);
        // this test guards against the clamp coming back.
        let context = createTestContext(width: 30, height: 10)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // 100 rows, 5-tall viewport — content easily overflows.
        let items = (0..<100).map { "Row \($0)" }
        let view = List("Long", selection: .constant("Row 0")) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .frame(height: 5)

        // Initial render — scrollOffset is 0, focusedIndex is 0.
        let initial = renderToBuffer(view, context: context)
        dispatcher.setRegions(initial.hitTestRegions)
        let initialText = initial.lines.map(\.stripped).joined(separator: "\n")
        #expect(initialText.contains("Row 0"))

        // Dispatch a wheel-down event inside the list. With the
        // bug present, the next render would call
        // ensureFocusedItemVisible and scrub scrollOffset back
        // to 0 because focusedIndex is still 0.
        guard let region = initial.hitTestRegions.last else {
            Issue.record("expected at least one hit-test region from List")
            return
        }
        for _ in 0..<5 {
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown,
                    phase: .scrolled,
                    x: region.offsetX + region.width / 2,
                    y: region.offsetY + region.height / 2
                )
            )
        }

        // Re-render — the bug would surface here, scrolling back
        // to row 0. With the fix, Row 0 is off-screen and the
        // viewport now shows rows further down.
        let afterScroll = renderToBuffer(view, context: context)
        let afterText = afterScroll.lines.map(\.stripped).joined(separator: "\n")
        #expect(
            !afterText.contains("Row 0"),
            "After wheel scrolling, Row 0 should be off-screen; got:\n\(afterText)"
        )
    }

    @Test("Filtering content under a deep scrollOffset snaps the viewport back to the data")
    func filterUnderScrollSnapsViewport() {
        // Regression test for the bug where a List that had been
        // scrolled deep (e.g. emoji-list at row 1500) and was then
        // filtered down to a handful of items rendered as a tiny
        // strip showing only the 'N more above' indicator — the
        // viewport was pointing past the end of the filtered data
        // because scrollOffset wasn't bounds-clamped against the
        // new itemCount. The fix: _ListCore now calls
        // handler.clampScrollOffset() each render after updating
        // itemCount.
        let context = createTestContext(width: 30, height: 12)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let allItems = (0..<200).map { "Row \($0)" }
        let filteredItems = ["Row 5", "Row 6", "Row 7"]

        // The same view shape both times — only the captured
        // items array differs. Identity is derived from position
        // in the parent body, so the same StateStorage slot
        // (and therefore the same ItemListHandler with its
        // existing scrollOffset) is reused across renders.
        func makeView(_ items: [String]) -> some View {
            List("Filterable", selection: .constant("Row 0")) {
                ForEach(items, id: \.self) { Text($0) }
            }
            .frame(height: 6)
        }

        // First render: full set. Scroll deep so scrollOffset is
        // way past the eventual filtered count.
        let big = renderToBuffer(makeView(allItems), context: context)
        dispatcher.setRegions(big.hitTestRegions)
        guard let region = big.hitTestRegions.last else {
            Issue.record("expected at least one hit-test region from List")
            return
        }
        for _ in 0..<30 {
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown,
                    phase: .scrolled,
                    x: region.offsetX + region.width / 2,
                    y: region.offsetY + region.height / 2
                )
            )
        }

        // Now re-render with the filtered data. With the bug
        // present, scrollOffset is unchanged (≥ 90) but the new
        // itemCount is 3, so the viewport renders nothing but the
        // 'N more above' indicator. With the fix, scrollOffset is
        // clamped to max(0, 3 - viewportHeight) and the filtered
        // rows render normally.
        let small = renderToBuffer(makeView(filteredItems), context: context)
        let text = small.lines.map(\.stripped).joined(separator: "\n")

        #expect(
            text.contains("Row 5"),
            "After filter, Row 5 should be visible; got:\n\(text)"
        )
        #expect(
            text.contains("Row 7"),
            "After filter, Row 7 should be visible; got:\n\(text)"
        )
    }

    // MARK: - Scroll-indicator placement

    /// Regression test for the "spurious / misplaced scroll
    /// indicator" bug: at the top of an overflowing list the
    /// viewport reserved space for *both* indicators even though
    /// only "▼ N more below" was showing, leaving a wasted blank
    /// line at the bottom and bumping the indicator one row too
    /// high. The fix reserves a line only for an indicator that is
    /// actually present, so the rows + indicator fill the content
    /// area exactly.
    @Test("Overflowing list shows 'more below' on the last content row at the top — no blank line")
    func scrollIndicatorOnLastRowAtTop() {
        let context = createTestContext(width: 24, height: 8)
        let items = (0..<20).map { "item-\($0)" }
        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
        }
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        let joined = lines.joined(separator: "\n")

        // The bottom border is the last line; the indicator must be
        // the content row immediately above it (was a blank line,
        // with the indicator one row higher, under the bug).
        #expect(
            lines[lines.count - 2].contains("more below"),
            "'more below' must sit on the last content row; got:\n\(joined)")
        #expect(
            !lines[lines.count - 2].contains("item-"),
            "the last content row is the indicator, not an item; got:\n\(joined)")
        // The row directly above the indicator must be a real item,
        // proving there is no wasted blank line.
        #expect(
            lines[lines.count - 3].contains("item-"),
            "a real item must sit directly above the indicator; got:\n\(joined)")
        #expect(
            !joined.contains("more above"),
            "no 'more above' at the very top; got:\n\(joined)")
    }

    /// At the bottom only the "▲ N more above" indicator shows, the
    /// last item is visible, and it sits on the last content row
    /// (no wasted blank line at the bottom end either).
    @Test("Overflowing list shows the last item on the last content row at the bottom")
    func scrollIndicatorAtBottom() {
        let context = createTestContext(width: 24, height: 8)
        let items = (0..<20).map { "item-\($0)" }
        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
        }
        _ = renderToBuffer(view, context: context)  // register + focus the list
        _ = context.environment.focusManager.dispatchKeyEvent(KeyEvent(key: .end))
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        let joined = lines.joined(separator: "\n")

        #expect(
            lines[1].contains("more above"),
            "top content row must be the 'more above' indicator; got:\n\(joined)")
        #expect(
            !joined.contains("more below"),
            "no 'more below' at the bottom; got:\n\(joined)")
        #expect(
            lines[lines.count - 2].contains("item-19"),
            "the last item must sit on the last content row; got:\n\(joined)")
    }

    /// In the middle both indicators show and the rows between them
    /// fill the content area exactly — no overlap, no blank line.
    @Test("Overflowing list shows both indicators with the focused row visible in the middle")
    func scrollIndicatorsInMiddle() {
        let context = createTestContext(width: 24, height: 8)
        let items = (0..<20).map { "item-\($0)" }
        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
        }
        _ = renderToBuffer(view, context: context)
        for _ in 0..<6 {
            _ = context.environment.focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        }
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        let joined = lines.joined(separator: "\n")

        #expect(
            lines[1].contains("more above"),
            "'more above' on the first content row; got:\n\(joined)")
        #expect(
            lines[lines.count - 2].contains("more below"),
            "'more below' on the last content row; got:\n\(joined)")
        // The focused row (item-6) must be a real, visible row — not
        // hidden behind the below indicator at the transition.
        #expect(
            joined.contains("item-6"),
            "the focused row must stay visible at the top→middle transition; got:\n\(joined)")
    }

    /// The scroll offset must never rest at 1: an "▲ 1 more above"
    /// indicator hides a single row using a line that could simply
    /// show that row, so offset 0 (first row visible, no indicator)
    /// strictly dominates it. Walking the selection down must take
    /// the above indicator straight from absent to "2 more above".
    @Test("Overflowing list never shows '1 more above' (offset never rests at 1)")
    func neverShowsSingleRowAboveIndicator() {
        let context = createTestContext(width: 24, height: 8)
        let items = (0..<20).map { "item-\($0)" }
        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
        }
        _ = renderToBuffer(view, context: context)  // register + focus

        for _ in 0..<20 {
            _ = context.environment.focusManager.dispatchKeyEvent(KeyEvent(key: .down))
            let joined = renderToBuffer(view, context: context)
                .lines.map(\.stripped).joined(separator: "\n")
            #expect(
                !joined.contains("▲ 1 more above"),
                "offset 1 is dominated by offset 0 — never show '1 more above'; got:\n\(joined)")
        }
    }

    /// Regression test for "the emoji list won't scroll the last screenful to
    /// its bottom". A `List` with no explicit height that shares vertical space
    /// with a flexible sibling (here a trailing `Spacer`) is *measured* with the
    /// full available height — much taller than the height it actually renders
    /// into. A measure-pass `clampScrollOffset()` therefore clamped the
    /// persistent `scrollOffset` against a viewport (and `maxOffset`) far larger
    /// than the real one, yanking the offset back every frame so the bottom rows
    /// were unreachable by wheel / arrows / Page Down / End. The fix skips
    /// persistent scroll mutation while measuring.
    @Test("A list sharing space with a flexible sibling scrolls fully to the bottom")
    func listWithFlexibleSiblingScrollsToBottom() {
        var context = createTestContext(width: 30, height: 24)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let items = (0..<100).map { String(format: "row-%03d", $0) }
        // A fixed block on top + a trailing Spacer force the List to render into
        // only part of the content area, so its measured height (the full area)
        // exceeds its rendered height — the condition that triggered the bug.
        let view = VStack(spacing: 1) {
            Text("header").border()
            List(selection: .constant(String?.none)) {
                ForEach(items, id: \.self) { Text($0) }
            }
            Spacer()
        }

        let initial = renderToBuffer(view, context: context)
        dispatcher.setRegions(initial.hitTestRegions)
        guard let listRegion = initial.hitTestRegions.max(by: { $0.height < $1.height }) else {
            Issue.record("expected a List hit-test region"); return
        }
        // Precondition: the List really is shorter than the content area (else
        // the bug wouldn't reproduce and the test would be vacuous).
        #expect(listRegion.height < context.availableHeight - 2,
            "List should render into a sub-region for this test to be meaningful")

        let cx = listRegion.offsetX + listRegion.width / 2
        let cy = listRegion.offsetY + listRegion.height / 2
        var joined = ""
        for _ in 0..<80 {  // 80 wheel ticks * 3 lines >> 100 rows: reaches the end
            _ = dispatcher.dispatch(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: cx, y: cy))
            let b = renderToBuffer(view, context: context)
            dispatcher.setRegions(b.hitTestRegions)
            joined = b.lines.map(\.stripped).joined(separator: "\n")
        }

        #expect(joined.contains("row-099"), "wheel-scrolling to the end must reveal the last row")
        #expect(!joined.contains("more below"), "nothing should remain below once at the bottom")
    }

    @Test("A large List builds only ~viewport rows, not every row")
    func largeListIsWindowed() {
        // A 1,000-row List in a ~12-line viewport must build (and render) only the
        // rows in / probed around the visible window. The windowed extraction keeps
        // per-frame cost O(visible), not O(total): a regression that materialised
        // every row would push this count toward 1,000.
        final class BuildCounter { var built = 0 }
        let counter = BuildCounter()
        let context = createTestContext(width: 40, height: 14)

        let view = List(selection: .constant(Int?.none)) {
            ForEach(0..<1000, id: \.self) { i in
                counter.built += 1  // runs when this row's content is actually built
                return Text("row \(i)")
            }
        }

        _ = renderToBuffer(view, context: context)

        #expect(
            counter.built < 60,
            "built \(counter.built) of 1000 rows; a windowed List renders only ~viewport")
    }
}
