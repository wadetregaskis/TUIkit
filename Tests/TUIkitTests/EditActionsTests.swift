//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditActionsTests.swift
//
//  `ForEach($items, editActions:)` — the ForEach editing its own collection.
//
//  Driven through a real `List` and the real mouse/key dispatchers rather than
//  by calling the synthesised closures: the point of naming an action is that
//  the LIST arms a gesture for it, and a set that filled in the closures while
//  the list never offered the gesture would pass any test that called them
//  directly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("EditActions")
struct EditActionsTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var name: String
    }

    @MainActor
    private final class Fixture {
        var rows: [Row]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(_ rows: [Row]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        var binding: Binding<[Row]> {
            Binding(get: { self.rows }, set: { self.rows = $0 })
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let context = RenderContext(
                availableWidth: 24, availableHeight: 10, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The list's handler, reachable once the list has registered focus.
        var handler: ItemListHandler<Int>? {
            env.focusManager?.currentFocused as? ItemListHandler<Int>
        }
    }

    private func names(_ fixture: Fixture) -> [String] {
        fixture.rows.map(\.name)
    }

    @Test(".move fills in the reorder, and the list arms the gesture")
    func moveEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .move) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove != nil, "the list was told the rows can move")
        #expect(handler.onDelete == nil, ".move alone does not arm deletion")

        handler.onMove?(IndexSet(integer: 0), 3)
        #expect(names(fixture) == ["b", "c", "a"])
    }

    @Test(".delete fills in the removal")
    func deleteEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .delete) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onDelete != nil)
        #expect(handler.onMove == nil, ".delete alone does not arm reordering")

        handler.onDelete?(IndexSet(integer: 1))
        #expect(names(fixture) == ["a", "c"])
    }

    @Test(".all arms both")
    func allEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .all) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove != nil)
        #expect(handler.onDelete != nil)
    }

    @Test("An empty set arms nothing")
    func noEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: []) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove == nil, "no gesture is armed for an action nobody named")
        #expect(handler.onDelete == nil)
    }

    @Test("The rows are still bindings, so a row can edit its own element")
    func rowsAreStillBindings() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        var captured: [Binding<Row>] = []
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .all) { row in
                    // Captured from inside the builder, which is where the
                    // per-row binding actually exists.
                    Text(row.wrappedValue.name)
                        .onGeometryChange(for: Int.self) { _ in 0 } action: { _ in
                            captured.append(row)
                        }
                }
            }
            .frame(height: 8))

        #expect(captured.count == 2)
        captured.first?.name.wrappedValue = "edited"
        #expect(names(fixture) == ["edited", "b"])
    }

    @Test("The id: form takes edit actions too")
    func keyPathIdentifiedForm() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(String?.none)) {
                ForEach(fixture.binding, id: \.name, editActions: .all) { $row in
                    Text(row.name)
                }
            }
            .frame(height: 8))

        let handler = fixture.env.focusManager?.currentFocused as? ItemListHandler<String>
        #expect(handler?.onMove != nil)
        #expect(handler?.onDelete != nil)
    }
}
