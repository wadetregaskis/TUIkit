//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollableEnvironmentWiringTests.swift
//
//  Every scrollable row view captures the same environment into its handler at
//  render, because that is where events read it from — a mouse wheel or a key
//  arrives long after the environment is out of reach. There are four places
//  that capture (List, single-line Table, multi-line Table, ScrollView) and
//  nothing but review has ever kept them in step, which is how `.scrollDisabled`
//  reached only one Table path when it shipped, and how the two values asserted
//  here reached three of the four.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scrollables capture the same environment")
struct ScrollableEnvironmentWiringTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String
        var note: String
    }

    private static let rows = (1...12).map {
        Row(id: $0, name: "row \($0)", note: "note \($0) with several words to wrap")
    }

    /// Renders `view` with a drag session and a zero chaining delay in scope,
    /// Tabs to focus it, and hands back whichever `ItemListHandler` that is —
    /// the one the view's own events will consult.
    private func focusedRowHandler(
        _ view: some View, session: DragAndDropSession, height: Int = 8
    ) -> ItemListHandler<Int>? {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.dragAndDropSession = session

        var context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        _ = renderToBuffer(view.scrollChainingDelay(.zero), context: context)
        let focus = environment.focusManager!
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        return focus.currentFocused as? ItemListHandler<Int>
    }

    private func singleLineTable() -> some View {
        Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Name", value: \Row.name).width(.flexible)
        }
        .frame(height: 6)
    }

    private func multiLineTable() -> some View {
        Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Note", value: \Row.note).width(.flexible).lineLimit(3)
        }
        .frame(height: 6)
    }

    private func list() -> some View {
        List(selection: .constant(Set<Int>())) {
            ForEach(Self.rows) { Text($0.name) }
        }
        .frame(height: 6)
    }

    /// `.scrollChainingDelay(_:)` documents itself as reaching "List, Table,
    /// ScrollView, both axes". A view that misses it keeps the 500 ms default
    /// forever: an app asking for immediate chaining (or a longer hold) is
    /// simply not answered, and nothing says so.
    @Test(
        "The chaining delay reaches every row view",
        arguments: [("single-line Table", 0), ("multi-line Table", 1), ("List", 2)])
    func chainingDelayReachesEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        let handler: ItemListHandler<Int>? =
            switch which {
            case 0: focusedRowHandler(singleLineTable(), session: session)
            case 1: focusedRowHandler(multiLineTable(), session: session)
            default: focusedRowHandler(list(), session: session)
            }
        guard let handler else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(
            handler.wheelEdgeHold.delayNanos == 0,
            "\(name): the modifier is what decides the grace period, not the default")
    }

    /// The session is how a handler reaches anything outside itself mid-gesture:
    /// the view under the pointer for the navigators, and the floating preview
    /// to take it down on a cancel. Without it a handler can only ever answer
    /// with itself.
    @Test(
        "The drag session reaches every row view",
        arguments: [("single-line Table", 0), ("multi-line Table", 1), ("List", 2)])
    func dragSessionReachesEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        let handler: ItemListHandler<Int>? =
            switch which {
            case 0: focusedRowHandler(singleLineTable(), session: session)
            case 1: focusedRowHandler(multiLineTable(), session: session)
            default: focusedRowHandler(list(), session: session)
            }
        guard let handler else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(
            handler.dragSession === session,
            "\(name): the handler holds the session its gestures run in")
    }
}
