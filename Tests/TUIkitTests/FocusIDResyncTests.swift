//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIDResyncTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A control that re-declares its `.focusID(_:)` must be filed under the NEW
/// name, not the one it happened to have on its first frame.
///
/// `.focusID(_:)` is an ordinary modifier and its argument may be computed from
/// state — `focusID("row-\(selectedID)")` is the shape this is for. But a
/// persisted handler is built ONCE, in a `storage(for:default:)` autoclosure,
/// from whatever id was in force the first time the control drew, and the focus
/// ring files a control under `handler.focusID` and nothing else. So from the
/// second frame the ring knew the control by its old name while the view drew
/// and queried focus under the new one, and the two could never agree again:
/// `.focused($field, equals:)` addressed something that had stopped answering.
@MainActor
@Suite("A re-declared focus ID reaches the ring")
struct FocusIDResyncTests {

    private func frame(_ view: some View, tui: TUIContext, focus: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
    }

    @Test("A TextField that changes its focusID is registered under the new one")
    func changedFocusIDReachesTheRing() {
        let tui = TUIContext()
        let focus = FocusManager()
        let text = Binding.constant("")

        frame(TextField("t", text: text).focusID("first"), tui: tui, focus: focus)
        #expect(focus.focusableIDs.contains("first"), "the first declaration registered")

        frame(TextField("t", text: text).focusID("second"), tui: tui, focus: focus)
        #expect(
            focus.focusableIDs.contains("second"),
            "the ring still knows it as \(focus.focusableIDs) after the id changed")
        #expect(!focus.focusableIDs.contains("first"), "and no longer by the old name")
    }

    /// The same for a control whose handler carries scroll state, so the fix is
    /// pinned on more than one of the thirteen persisted handlers.
    @Test("A List that changes its focusID is registered under the new one")
    func changedListFocusIDReachesTheRing() {
        let tui = TUIContext()
        let focus = FocusManager()
        func list(_ id: String) -> some View {
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
            }
            .focusID(id)
        }
        frame(list("listA"), tui: tui, focus: focus)
        #expect(focus.focusableIDs.contains("listA"))
        frame(list("listB"), tui: tui, focus: focus)
        #expect(
            focus.focusableIDs.contains("listB"),
            "the ring still knows it as \(focus.focusableIDs)")
    }
}
