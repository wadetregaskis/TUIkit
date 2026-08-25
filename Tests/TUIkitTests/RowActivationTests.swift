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

    // MARK: - One gesture, one activation

    /// Clicks `clicks` times on the same row, 100 ms apart, and reports how
    /// many times the row opened.
    ///
    /// A generic over the view because this is the rule two twins have to keep
    /// (see the `List`/`Table` divergence the drop and reorder code fights):
    /// the caller supplies its own view and the row's y, and the burst is one
    /// shared piece of code.
    private func opens<V: View>(
        clicks: Int, width: Int, height: Int,
        make: (@escaping (String) -> Void) -> V,
        rowY: (FrameBuffer) -> Int?
    ) -> Int {
        var opened = 0
        var now: UInt64 = 0
        let view = make { _ in opened += 1 }

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.nowNanos = { now }
        dispatcher.setActiveSupport(.full)
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let context = RenderContext(
                availableWidth: width, availableHeight: height, environment: env,
                tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        guard let y = rowY(frame()) else {
            Issue.record("the row to click was not rendered")
            return -1
        }
        for _ in 0..<clicks {
            // A frame between clicks, as a live app renders one: the count is
            // the dispatcher's, and must survive the regions being republished.
            _ = frame()
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y))
            now += 100_000_000  // well inside the 400 ms multi-click window
        }
        return opened
    }

    /// The reported bug: a file browser dug two or three levels from what the
    /// user made as one double-click.
    ///
    /// The count is cumulative while the clicks keep coming — every press
    /// extends the window from itself — and "was this a double-click?" is asked
    /// as *two or more*, so every click from the second on opened another row.
    /// Activating is what makes it visible rather than merely redundant: each
    /// open puts a different row under a pointer that never moved.
    ///
    /// One open per PAIR of clicks is the rule now, which is also what a user
    /// drumming double-clicks to climb out of a directory tree means.
    @Test("A burst of clicks opens once per pair — List")
    func listBurstOpensOncePerPair() {
        let items = ["Folder-A", "Folder-B", "Folder-C"]
        for (clicks, expected) in [(1, 0), (2, 1), (3, 1), (4, 2), (5, 2), (6, 3)] {
            let count = opens(
                clicks: clicks, width: 28, height: 10,
                make: { open in
                    List(selection: .constant(String?.none)) {
                        ForEach(items, id: \.self) { Text($0) }
                    }
                    .onRowActivate(open)
                    .frame(height: 8)
                },
                rowY: { buffer in
                    buffer.lines.firstIndex { $0.stripped.contains("Folder-A") }
                })
            #expect(count == expected, "\(clicks) clicks opened \(count) rows, want \(expected)")
        }
    }

    @Test("Two quick clicks on ADJACENT rows open nothing")
    func adjacentRowClicksDoNotOpen() {
        // The dispatcher's multi-click proximity is one cell — a jitter
        // allowance — and rows are one cell tall, so a click on row A
        // followed quickly by row B arrived stamped clickCount 2: row B
        // opened from two clicks that each landed once.
        var opened: [String] = []
        let context = makeRenderContext(width: 28, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.focusManager = FocusManager()
        }
        let view = List(selection: .constant(String?.none)) {
            ForEach(["Folder-A", "Folder-B"], id: \.self) { Text($0) }
        }
        .onRowActivate { opened.append($0) }
        .frame(height: 8)

        let buffer = renderToBuffer(view, context: context)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let rowA = buffer.lines.firstIndex(where: { $0.stripped.contains("Folder-A") })
        else {
            Issue.record("row not found")
            return
        }

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: rowA))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: rowA))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: rowA + 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: rowA + 1))
        #expect(opened.isEmpty, "adjacent single clicks opened a row: \(opened)")

        // A real double on the second row still opens it.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: rowA + 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: rowA + 1))
        #expect(opened == ["Folder-B"], "\(opened)")
    }

    /// The `Table` twin of ``listBurstOpensOncePerPair()``. Both had the bug,
    /// in their own copy of the release path.
    @Test("A burst of clicks opens once per pair — Table")
    func tableBurstOpensOncePerPair() {
        struct Row: Identifiable, Sendable {
            let id: String
            let name: String
        }
        let rows = [Row(id: "a", name: "Alpha"), Row(id: "b", name: "Beta")]
        for (clicks, expected) in [(1, 0), (2, 1), (3, 1), (4, 2), (5, 2), (6, 3)] {
            let count = opens(
                clicks: clicks, width: 30, height: 10,
                make: { open in
                    Table(rows, selection: .constant(String?.none)) {
                        TableColumn("Name", value: \Row.name)
                    }
                    .onRowActivate(open)
                    .frame(height: 8)
                },
                rowY: { buffer in
                    buffer.lines.firstIndex { $0.stripped.contains("Alpha") }
                })
            #expect(count == expected, "\(clicks) clicks opened \(count) rows, want \(expected)")
        }
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
