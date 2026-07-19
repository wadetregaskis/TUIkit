//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SelectionFollowInScrollViewTests.swift
//
//  An enclosing ScrollView must follow a List/Table's keyboard CURSOR, not
//  just the container's top edge: the container region alone top-aligns a
//  taller-than-viewport list once and then never moves, so walking the
//  selection down disappears below the fold (the Table Demo short-window
//  sighting), and a selection walked to the viewport's top row can rest
//  hidden under the "▲ N more above" indicator (the Lists .plain sighting).
//  Both are fixed by the cursor-row marker region (a one-row region carrying
//  the container's focusID, ahead of the whole-container region) plus the
//  snap's indicator-aware fire condition.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("outer ScrollView follows the List/Table cursor")
struct SelectionFollowInScrollViewTests {
    private struct Item: Identifiable {
        let id: Int
        var label: String { "item-\(id)-end" }
    }

    private static func items(_ count: Int) -> [Item] {
        (0..<count).map { Item(id: $0) }
    }

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager,
        height: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Focuses the container, then walks the cursor `presses` times with
    /// `key`, re-rendering after every press (interaction-test discipline)
    /// and asserting the expected item is on screen each time.
    private func walkAssertingVisibility<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager,
        height: Int, key: Key, presses: Int, expectedIndex: (Int) -> Int
    ) {
        for press in 0..<presses {
            #expect(focusManager.dispatchKeyEvent(KeyEvent(key: key)), "press \(press) consumed")
            let lines = renderFrame(
                view, tuiContext: tuiContext, focusManager: focusManager, height: height)
            let label = "item-\(expectedIndex(press))-end"
            #expect(
                lines.contains { $0.contains(label) },
                "after \(key) press \(press), \(label) is visible: \(lines)")
        }
    }

    @Test("A fully-expanded List's cursor stays visible while walking down and back up")
    func expandedListCursorFollowed() {
        // The list fits all 15 rows in its own 20-line frame (no internal
        // scrolling) but is taller than the 8-line viewport — every cursor
        // move must move the OUTER ScrollView once the cursor passes the fold.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                List(Self.items(15), selection: Binding<Int?>.constant(nil)) { item in
                    Text(item.label)
                }
                .frame(height: 20)
            }
        }
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        guard
            let listID = focusManager.registeredFocusIDsInActiveSection()
                .first(where: { $0.hasPrefix("list-") })
        else {
            Issue.record("no list registered")
            return
        }
        focusManager.focus(id: listID)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)

        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .down, presses: 14, expectedIndex: { $0 + 1 })
        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .up, presses: 14, expectedIndex: { 13 - $0 })
    }

    @Test("A fully-expanded Table's cursor stays visible while walking down and back up")
    func expandedTableCursorFollowed() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Table(Self.items(15), selection: Binding<Int?>.constant(nil)) {
                    TableColumn("Label") { (row: Item) in row.label }
                }
            }
        }
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        guard
            let tableID = focusManager.registeredFocusIDsInActiveSection()
                .first(where: { $0.hasPrefix("table-") })
        else {
            Issue.record("no table registered")
            return
        }
        focusManager.focus(id: tableID)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)

        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .down, presses: 14, expectedIndex: { $0 + 1 })
        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .up, presses: 14, expectedIndex: { 13 - $0 })
    }

    @Test("An internally-scrolling Table in a short ScrollView keeps its cursor visible")
    func windowedTableCursorFollowed() {
        // The Table Demo shape: a fixed-height table that scrolls internally,
        // inside a page ScrollView shorter than the table. The table moves its
        // own window as far as it can; the outer ScrollView must cover the
        // rest so the cursor row is ALWAYS on screen.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Table(Self.items(30), selection: Binding<Int?>.constant(nil)) {
                    TableColumn("Label") { (row: Item) in row.label }
                }
                .frame(height: 12)
            }
        }
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        guard
            let tableID = focusManager.registeredFocusIDsInActiveSection()
                .first(where: { $0.hasPrefix("table-") })
        else {
            Issue.record("no table registered")
            return
        }
        focusManager.focus(id: tableID)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)

        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .down, presses: 29, expectedIndex: { $0 + 1 })
        walkAssertingVisibility(
            view, tuiContext: tuiContext, focusManager: focusManager,
            height: 8, key: .up, presses: 29, expectedIndex: { 28 - $0 })
    }
}
