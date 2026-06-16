//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalFocusRestorationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Dismissing a modal must return the page to exactly where it was: the focus
//  it had, and (so a ScrollView doesn't snap-scroll to a reset focus) its
//  scroll position. Regression for "closing the colour picker scrolls the
//  Theme page back to the top".

import Testing

@testable import TUIkit

@MainActor
@Suite("Modal focus & scroll restoration")
struct ModalFocusRestorationTests {

    private final class BoolBox {
        var v = false
        var binding: Binding<Bool> { Binding(get: { self.v }, set: { self.v = $0 }) }
    }

    @Test("Dismissing a modal restores the page's focus and scroll position")
    func dismissRestoresFocusAndScroll() {
        let presented = BoolBox()
        let tui = TUIContext()
        let fm = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30) { i in Button("Row \(i)") {}.focusID("row-\(i)") }
            }
        }
        .modal(isPresented: presented.binding) { Text("THEMODAL") }

        func render() -> [String] {
            var env = EnvironmentValues()
            env.focusManager = fm
            let ctx = RenderContext(availableWidth: 24, availableHeight: 8, environment: env, tuiContext: tui)
            fm.beginRenderPass()
            let out = renderToBuffer(view, context: ctx).lines.map { $0.stripped }
            fm.endRenderPass()
            return out
        }

        _ = render()
        fm.focus(id: "row-20")           // focus a row well down the page
        let scrolled = render()          // ScrollView snaps to reveal it
        #expect(fm.currentFocusedID == "row-20")
        #expect(scrolled.first != "▐ Row 0 ▌".padding(toLength: 24, withPad: " ", startingAt: 0))

        presented.v = true
        _ = render()                     // modal up
        presented.v = false
        let closed = render()            // modal dismissed

        #expect(fm.currentFocusedID == "row-20", "page focus restored on dismiss")
        #expect(closed.first == scrolled.first, "scroll position unchanged on dismiss; got \(closed.first ?? "")")
    }
}

@MainActor
@Suite("FocusManager — section focus memory")
struct FocusManagerSectionMemoryTests {

    private final class Holder: Focusable {
        let focusID: String
        var canBeFocused = true
        init(_ id: String) { focusID = id }
        func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    }

    @Test("Activating then deactivating a section restores the prior section's focus")
    func sectionRoundTripRestoresFocus() {
        let fm = FocusManager()
        let a = Holder("a"), b = Holder("b")
        fm.registerSection(id: "page")
        fm.register(a, inSection: "page")
        fm.register(b, inSection: "page")
        fm.focus(id: "b")
        #expect(fm.currentFocusedID == "b")

        // A modal overlay activates its own (empty) section…
        fm.registerSection(id: "__modal__")
        fm.activateSection(id: "__modal__")
        // …then is dismissed.
        fm.deactivateSection(id: "__modal__")

        #expect(fm.currentFocusedID == "b", "focus returns to where it was, not the first element")
    }
}
