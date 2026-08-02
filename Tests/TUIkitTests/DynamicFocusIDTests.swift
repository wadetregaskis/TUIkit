//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DynamicFocusIDTests.swift
//
//  `.focusID(_:)` names a control for everything that addresses controls by
//  name — `.focused($field, equals:)`, `ScrollViewProxy.scrollTo`, a test
//  driving the focus system. A name computed from state has to keep up with
//  the state.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A declared focusID follows its declaration")
struct DynamicFocusIDTests {

    private func render(_ view: some View, into context: RenderContext) {
        let focus = context.environment.focusManager!
        focus.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focus.endRenderPass()
    }

    private func makeContext() -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        var context = RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        return context
    }

    /// The bug: the id was persisted on first render and returned from storage
    /// thereafter, so an id derived from state — the whole point of computing
    /// one — was frozen at whatever it was the first time the view drew.
    @Test("A focusID computed from state changes with the state")
    func computedFocusIDUpdates() {
        let context = makeContext()
        let focus = context.environment.focusManager!

        render(Button("Edit") {}.focusID("editor-1"), into: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(focus.currentFocusedID == "editor-1", "the control case")

        // Same view, same identity — a new name.
        render(Button("Edit") {}.focusID("editor-2"), into: context)
        #expect(
            focus.focusableIDsInActiveSection().contains("editor-2"),
            "the ring knows the control by its new name: \(focus.focusableIDsInActiveSection())")
        #expect(
            !focus.focusableIDsInActiveSection().contains("editor-1"),
            "and not by the old one: \(focus.focusableIDsInActiveSection())")
    }

    /// Without a declaration the id is derived from the view's path and must
    /// stay put — that stability is what the persistence box is for, and this
    /// pins that the fix did not trade it away.
    @Test("An undeclared focusID is still stable across renders")
    func generatedFocusIDIsStable() {
        let context = makeContext()
        let focus = context.environment.focusManager!

        render(Button("Edit") {}, into: context)
        let first = focus.focusableIDsInActiveSection()
        render(Button("Edit") {}, into: context)
        #expect(focus.focusableIDsInActiveSection() == first, "\(first) then \(focus.focusableIDsInActiveSection())")
    }
}
