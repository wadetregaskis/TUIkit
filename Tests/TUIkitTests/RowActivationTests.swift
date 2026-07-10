//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowActivationTests.swift
//
//  `.onRowActivate(_:)` on List and Table: Return/Enter on the focused row
//  (or a double-click) fires the activation action — the file-browser "open"
//  convention — while Space keeps toggling selection. Without an activation
//  action, Enter retains its original select behaviour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Row activation (Enter / double-click)")
struct RowActivationTests {

    // MARK: - Handler semantics

    private func makeHandler(selection: Binding<String?>) -> ItemListHandler<String> {
        let handler = ItemListHandler<String>(
            focusID: "t", itemCount: 3, viewportHeight: 5,
            selectionMode: .single, canBeFocused: true)
        handler.itemIDs = ["a", "b", "c"]
        handler.singleSelection = selection
        return handler
    }

    @Test("With an activation action, Enter opens and does NOT select")
    func enterActivates() {
        var selection: String?
        var opened: [String] = []
        let handler = makeHandler(
            selection: Binding(get: { selection }, set: { selection = $0 }))
        handler.primaryAction = { opened.append($0) }
        handler.focusedIndex = 1

        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(opened == ["b"], "Enter activates the focused row")
        #expect(selection == nil, "Enter must not also toggle selection")
    }

    @Test("Space still toggles selection when an activation action is set")
    func spaceSelects() {
        var selection: String?
        var opened: [String] = []
        let handler = makeHandler(
            selection: Binding(get: { selection }, set: { selection = $0 }))
        handler.primaryAction = { opened.append($0) }
        handler.focusedIndex = 2

        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection == "c", "Space selects")
        #expect(opened.isEmpty, "Space must not activate")
    }

    @Test("Without an activation action, Enter keeps its select behaviour")
    func enterSelectsWithoutAction() {
        var selection: String?
        let handler = makeHandler(
            selection: Binding(get: { selection }, set: { selection = $0 }))
        handler.focusedIndex = 0

        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(selection == "a")
    }

    // MARK: - List integration

    @Test("List.onRowActivate: Enter opens the focused row; double-click opens a clicked row")
    func listActivation() {
        var opened: [String] = []
        var now: UInt64 = 0
        let items = ["Folder-A", "Folder-B", "Folder-C"]
        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .onRowActivate { opened.append($0) }
        .frame(height: 8)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.nowNanos = { now }
        dispatcher.setActiveSupport(.full)
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        let focusManager = FocusManager()
        env.focusManager = focusManager

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let context = RenderContext(
                availableWidth: 28, availableHeight: 10, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        var buffer = frame()

        // Keyboard: Down to row 1, then Enter → opens Folder-B.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(opened == ["Folder-B"], "Enter activates the focused row")

        // Space on the same row selects rather than activating.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .space))
        #expect(opened == ["Folder-B"], "Space must not activate")

        // Mouse: double-click row 0 (two quick clicks through the container).
        buffer = frame()
        guard let rowY = buffer.lines.firstIndex(where: { $0.stripped.contains("Folder-A") }) else {
            Issue.record("Folder-A not rendered")
            return
        }
        for _ in 0..<2 {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: rowY))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: rowY))
            now += 100_000_000
        }
        #expect(opened == ["Folder-B", "Folder-A"], "double-click activates the clicked row")
    }

    // MARK: - Table integration

    @Test("Table.onRowActivate: Enter opens the focused row")
    func tableEnterActivation() {
        struct Row: Identifiable, Sendable {
            let id: String
            let name: String
        }
        var opened: [String] = []
        let rows = [Row(id: "a", name: "Alpha"), Row(id: "b", name: "Beta")]
        let view = Table(rows, selection: .constant(String?.none)) {
            TableColumn("Name", value: \Row.name)
        }
        .onRowActivate { opened.append($0) }
        .frame(height: 6)

        let context = makeRenderContext(width: 30, height: 8)
        _ = renderToBuffer(view, context: context)
        let focusManager = context.environment.focusManager!
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(opened == ["b"], "Enter activates the focused table row")
    }
}
