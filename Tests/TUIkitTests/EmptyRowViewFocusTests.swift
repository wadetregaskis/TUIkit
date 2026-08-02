//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmptyRowViewFocusTests.swift
//
//  Empty is a state, not an absence: a List or Table with no rows is still on
//  screen, still occupies its frame, and is still a place the user can be.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("An empty row view is still a focus stop")
struct EmptyRowViewFocusTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String
    }

    private func focusIDAfterTabbing(into view: some View) -> String? {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)

        var context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        _ = renderToBuffer(view, context: context)
        let focus = environment.focusManager!
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        return focus.currentFocusedID
    }

    /// A `Table` has claimed its frame when empty since 96fe18b2 — "it could not
    /// be clicked, could not be Tab-focused, and an enclosing ScrollView could
    /// not find it to reveal it". Every word of that applied to `List` too; its
    /// own fix (68d50ce0) wired the hit-testing and even claimed focus among
    /// what it restored, but the empty branch never registered with the focus
    /// system, so the claim was only ever true of the populated one.
    @Test("An empty List can be Tab-focused, as an empty Table can")
    func emptyListTakesFocus() {
        let emptyList = List(selection: .constant(Set<Int>())) {
            ForEach([Row]()) { Text($0.name) }
        }
        .frame(height: 5)

        #expect(
            focusIDAfterTabbing(into: emptyList) != nil,
            "an empty list is still a control the user can reach")
    }

    @Test("An empty Table can be Tab-focused")
    func emptyTableTakesFocus() {
        let emptyTable = Table([Row](), selection: .constant(Set<Int>())) {
            TableColumn("Name", value: \Row.name).width(.flexible)
        }
        .frame(height: 5)

        #expect(
            focusIDAfterTabbing(into: emptyTable) != nil,
            "the twin, which has behaved this way since 96fe18b2")
    }

    /// The list that empties WHILE focused: the focus system must still be
    /// told about the handler each frame, or the control it is holding focus
    /// on stops existing as far as the ring is concerned.
    @Test("A focused List that loses its rows keeps its focus")
    func aFocusedListThatEmptiesKeepsFocus() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)

        var context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        let populated = List(selection: .constant(Set<Int>())) {
            ForEach([Row(id: 1, name: "one")]) { Text($0.name) }
        }
        .frame(height: 5)
        let focus = environment.focusManager!

        focus.beginRenderPass()
        _ = renderToBuffer(populated, context: context)
        focus.endRenderPass()
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        let focusedWhilePopulated = focus.currentFocusedID
        #expect(focusedWhilePopulated != nil, "the control case focuses, as it must")

        // The same list, now with no rows.
        let emptied = List(selection: .constant(Set<Int>())) {
            ForEach([Row]()) { Text($0.name) }
        }
        .frame(height: 5)
        focus.beginRenderPass()
        _ = renderToBuffer(emptied, context: context)
        focus.endRenderPass()

        #expect(
            focus.currentFocusedID == focusedWhilePopulated,
            """
            emptying a list is not the user leaving it: focus was \
            \(focusedWhilePopulated ?? "nil"), now \(focus.currentFocusedID ?? "nil")
            """)
    }
}
