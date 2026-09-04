//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowEditRestrictionTests.swift
//
//  `.deleteDisabled()` and `.moveDisabled()` on a `List`'s rows.
//
//  The flag is stated INSIDE the row's subtree, so it is reported as the row
//  renders rather than read off its structure — which means the cases that
//  matter are the ones about that reporting: that a refusal survives modifiers
//  written outside it, that it survives the row memo, and that a row which
//  refuses nothing pays nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("deleteDisabled / moveDisabled")
struct RowEditRestrictionTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var name: String
        var locked: Bool
    }

    @MainActor
    private final class Fixture {
        var rows: [Row]
        var deletes: [IndexSet] = []
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(_ rows: [Row]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var handler: ItemListHandler<Int>? {
            env.focusManager?.currentFocused as? ItemListHandler<Int>
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 24, availableHeight: 10, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }
    }

    /// The row content, with the restriction written INSIDE an outer modifier —
    /// `.padding()` wraps it — so a structural read of the row's type would
    /// miss it. Reporting on render does not care about the order.
    private func lockedList(_ fixture: Fixture) -> some View {
        List(selection: .constant(Int?.none)) {
            ForEach(fixture.rows) { row in
                Text(row.name)
                    .deleteDisabled(row.locked)
                    .padding(.leading, 0)
            }
            .onDelete { fixture.deletes.append($0) }
        }
        .frame(height: 8)
    }

    @Test("A locked row refuses Delete; an unlocked one does not")
    func deleteIsRefused() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        fixture.render(lockedList(fixture))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.deleteDisabledRows == [1], "reported through the padding: \(handler.deleteDisabledRows)")

        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .delete)) == false, "the key falls through")
        #expect(fixture.deletes.isEmpty, "nothing was deleted")

        handler.focusedIndex = 0
        #expect(handler.handleKeyEvent(KeyEvent(key: .delete)) == true)
        #expect(fixture.deletes == [IndexSet(integer: 0)])
    }

    /// The row buffer can be served from the value memo without re-rendering,
    /// and a memoized row never reaches the reporting code — so a refusal that
    /// did not opt out of caching would be reported once and forgotten, and the
    /// row would quietly become deletable on frame two.
    @Test("A refusal survives the row memo across frames")
    func refusalSurvivesTheMemo() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        for frame in 1...4 {
            fixture.render(lockedList(fixture))
            #expect(
                fixture.handler?.deleteDisabledRows == [1],
                "frame \(frame): \(String(describing: fixture.handler?.deleteDisabledRows))")
        }
    }

    @Test("A row that refuses nothing reports nothing")
    func unrestrictedRowsReportNothing() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "b", locked: false),
        ])
        fixture.render(lockedList(fixture))
        #expect(fixture.handler?.deleteDisabledRows.isEmpty == true)
    }

    @Test("moveDisabled stops the row being picked up")
    func moveIsRefused() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "pinned", locked: true),
        ])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.rows) { row in
                    Text(row.name).moveDisabled(row.locked)
                }
                .onMove { source, destination in
                    fixture.rows.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.moveDisabledRows == [1])

        // A grab on the pinned row starts no gesture…
        handler.beginReorder(grabbing: 1)
        #expect(!handler.isReordering, "no drag started")
        #expect(handler.focusedIndex == 1, "but the press still selects it")

        // …while an ordinary row still picks up.
        handler.beginReorder(grabbing: 0)
        handler.dragReorder(toContentY: 1)
        #expect(handler.isReordering)
    }

    private func reorderableList(_ fixture: Fixture) -> some View {
        List(selection: .constant(Int?.none)) {
            ForEach(fixture.rows) { row in
                Text(row.name).moveDisabled(row.locked)
            }
            .onMove { source, destination in
                fixture.rows.move(fromOffsets: source, toOffset: destination)
            }
        }
        .frame(height: 8)
    }

    @Test("Keyboard move chords leave a pinned row where it is")
    func keyboardMoveRefused() {
        // The doc promise: "a keyboard row-move leaves it where it is". The
        // chords went straight to onMove without consulting the restriction —
        // a mouse drag on the same row correctly refused.
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "pinned", locked: true),
            Row(id: 2, name: "c", locked: false),
        ])
        fixture.render(reorderableList(fixture))
        guard let handler = fixture.handler else {
            Issue.record("no handler")
            return
        }
        handler.focusedIndex = 1

        #expect(handler.nudgeFocusedRow(by: 1) == false)
        #expect(handler.moveFocusedRow(to: 0) == false)
        #expect(fixture.rows.map(\.name) == ["a", "pinned", "c"], "the pinned row travelled")
    }

    @Test("Pick-up on a pinned row does not latch keyboard-move mode")
    func pickUpRefusedCleanly() {
        // The grab declines, but the mode used to latch anyway: arrows were
        // swallowed as held-row no-ops with nothing in hand and no visible
        // mode, until Enter/Escape happened to be pressed.
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "pinned", locked: true),
        ])
        fixture.render(reorderableList(fixture))
        guard let handler = fixture.handler else {
            Issue.record("no handler")
            return
        }
        handler.focusedIndex = 1

        #expect(handler.beginKeyboardMove() == false, "a refused pick-up falls through")
        #expect(!handler.isKeyboardMove, "no mode without a row in hand")
    }

    @Test("A mouse grab ends a keyboard move's mode")
    func mousePressClearsKeyboardMove() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "b", locked: false),
            Row(id: 2, name: "c", locked: false),
        ])
        fixture.render(reorderableList(fixture))
        guard let handler = fixture.handler else {
            Issue.record("no handler")
            return
        }
        handler.focusedIndex = 0
        _ = handler.beginKeyboardMove()
        #expect(handler.isKeyboardMove)

        // The click path's grab replaces the reorder; the mode must go with
        // it, or every navigation key is swallowed doing nothing.
        handler.beginReorder(grabbing: 2)
        #expect(!handler.isKeyboardMove)
    }

    @Test("A mouse grab on a pinned row ends a keyboard move entirely")
    func pinnedPressEndsKeyboardMove() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "b", locked: false),
            Row(id: 2, name: "pinned", locked: true),
        ])
        fixture.render(reorderableList(fixture))
        guard let handler = fixture.handler else {
            Issue.record("no handler")
            return
        }
        handler.focusedIndex = 0
        _ = handler.beginKeyboardMove()
        #expect(handler.isKeyboardMove)

        // The pinned row declines the grab. The refusal used to clear the mode
        // flag and leave the keyboard move's `reorder` armed — which reads as
        // a mouse drag in flight, so every navigation key after it scrolled
        // instead of moving the cursor.
        handler.beginReorder(grabbing: 2)
        #expect(!handler.isKeyboardMove)
        #expect(!handler.isReordering, "nothing is in hand")
        #expect(handler.handleReorderKey(KeyEvent(key: .down)) == nil, "navigation keys fall through")
    }

    @Test("A multi-row hold leaves pinned selection members behind")
    func heldRowsExcludePinned() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "pinned", locked: true),
            Row(id: 2, name: "c", locked: false),
        ])
        var selection: Set<Int> = [0, 1, 2]
        fixture.render(
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                ForEach(fixture.rows) { row in
                    Text(row.name).moveDisabled(row.locked)
                }
                .onMove { source, destination in
                    fixture.rows.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 8))
        guard let handler = fixture.handler else {
            Issue.record("no handler")
            return
        }

        // Grab an unlocked, selected row: the selection comes along — minus
        // the row the app said does not travel.
        handler.beginReorder(grabbing: 0)
        #expect(handler.reorder?.held == IndexSet([0, 2]), "\(String(describing: handler.reorder?.held))")
    }

    /// `moveDisabled` says this row does not travel, not that its position is
    /// fixed — SwiftUI's meaning, and the one that keeps a pinned row from
    /// freezing the rows around it.
    @Test("Other rows still move past a pinned one")
    func othersMovePastAPinnedRow() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "pinned", locked: true),
            Row(id: 2, name: "c", locked: false),
        ])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.rows) { row in
                    Text(row.name).moveDisabled(row.locked)
                }
                .onMove { source, destination in
                    fixture.rows.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 8))

        fixture.handler?.onMove?(IndexSet(integer: 0), 3)
        #expect(fixture.rows.map(\.name) == ["pinned", "c", "a"])
    }
}
