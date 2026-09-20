//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionDisabledTests.swift
//
//  `.selectionDisabled()` on a `List`'s rows.
//
//  The flag used to only write an environment value nothing read: a row
//  marked `.selectionDisabled(true)` still selected on Enter and still took
//  the cursor on Down, and never dimmed. It now reports through
//  `RowEditRestrictions`, the same collector — and the same on-render, not
//  structural, reporting — `.deleteDisabled()` / `.moveDisabled()` use (see
//  `RowEditRestrictionTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("selectionDisabled")
struct SelectionDisabledModifierTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var name: String
        var locked: Bool
    }

    @MainActor
    private final class Fixture {
        var rows: [Row]
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

    /// The restriction written INSIDE an outer modifier — `.padding()` wraps
    /// it — so a structural read of the row's type would miss it, exactly as
    /// `RowEditRestrictionTests.lockedList` sets up for delete/move.
    private func lockedList(_ fixture: Fixture, selection: Binding<Int?>) -> some View {
        List(selection: selection) {
            ForEach(fixture.rows) { row in
                Text(row.name)
                    .selectionDisabled(row.locked)
                    .padding(.leading, 0)
            }
        }
        .frame(height: 8)
    }

    @Test("A locked row reports itself, through the padding")
    func reportsThroughPadding() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        var selection: Int?
        fixture.render(
            lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(
            handler.selectionDisabledRows == [1],
            "reported through the padding: \(handler.selectionDisabledRows)")
    }

    @Test("A row that disables nothing reports nothing")
    func unrestrictedRowsReportNothing() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "b", locked: false),
        ])
        var selection: Int?
        fixture.render(
            lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))
        #expect(fixture.handler?.selectionDisabledRows.isEmpty == true)
    }

    /// A refused row can be served from the row memo without re-rendering,
    /// and a memoized row never reaches `SelectionDisabledModifier.report(_:)`
    /// — so a refusal that stayed memo-eligible would be reported once and
    /// forgotten, and the row would quietly become selectable on frame two.
    @Test("A refusal survives the row memo across frames")
    func refusalSurvivesTheMemo() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        var selection: Int?
        for frame in 1...4 {
            fixture.render(
                lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))
            #expect(
                fixture.handler?.selectionDisabledRows == [1],
                "frame \(frame): \(String(describing: fixture.handler?.selectionDisabledRows))")
        }
    }

    @Test("Enter does not select a selection-disabled row")
    func enterRefusesADisabledRow() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        var selection: Int?
        fixture.render(
            lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }

        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true, "the key is still consumed")
        #expect(selection == nil, "a selection-disabled row must not become the selection")

        handler.focusedIndex = 0
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(selection == 0, "an ordinary row still selects")
    }

    @Test("A click does not select a selection-disabled row")
    func clickRefusesADisabledRow() {
        let fixture = Fixture([
            Row(id: 0, name: "free", locked: false),
            Row(id: 1, name: "locked", locked: true),
        ])
        var selection: Int?
        fixture.render(
            lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }

        handler.handleClickSelection(at: 1, event: MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))
        #expect(selection == nil, "the click landed on a locked row")
        #expect(handler.focusedIndex == 1, "a click still moves the cursor, matching deleteDisabled")
    }

    @Test("Down skips a selection-disabled row")
    func downArrowSkipsADisabledRow() {
        let fixture = Fixture([
            Row(id: 0, name: "a", locked: false),
            Row(id: 1, name: "locked", locked: true),
            Row(id: 2, name: "c", locked: false),
        ])
        var selection: Int?
        fixture.render(
            lockedList(fixture, selection: Binding(get: { selection }, set: { selection = $0 })))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 0

        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(handler.focusedIndex == 2, "row 1 is selection-disabled and should be skipped")
    }

    @Test("A selection-disabled row renders dimmed")
    func rendersDimmed() {
        let context = makeRenderContext(width: 24, height: 3)
        let plain = renderToBuffer(Text("Row"), context: context)
        let disabled = renderToBuffer(Text("Row").selectionDisabled(), context: context)
        #expect(plain.lines != disabled.lines, "a disabled row must draw differently from a plain one")
        #expect(
            disabled.lines.contains { $0.contains(ANSIRenderer.dim) },
            "expected the persistent-faint SGR code: \(disabled.lines)")
    }

    @Test("selectionDisabled(false) renders content unchanged")
    func falseRendersUnchanged() {
        let context = makeRenderContext(width: 24, height: 3)
        let originalBuffer = renderToBuffer(Text("Content"), context: context)
        let modifiedBuffer = renderToBuffer(Text("Content").selectionDisabled(false), context: context)
        #expect(originalBuffer.lines == modifiedBuffer.lines)
    }
}
