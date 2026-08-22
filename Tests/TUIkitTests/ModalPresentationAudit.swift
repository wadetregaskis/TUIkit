//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationAudit.swift
//
//  A presented modal takes the keyboard: while it is up, nothing behind it is
//  reachable by Tab. That is a property of the whole tree rather than of the
//  modifier — the modal claims the active focus section as it renders, so
//  anything rendered AFTER it that does not name a section of its own resolves
//  to the modal's, and stays live.
//
//  Which makes where the modal hangs the thing to audit. `.modal` is documented
//  as attachable anywhere, so a control self-presenting a dialog is a supported
//  shape, not a misuse — and it is the shape `Example` never demonstrates,
//  because every page there wraps the whole page in its presentation.
//
//  (Whether the overlay reaches the root at all is `ContainerPayloadAudit`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Modal focus isolation by attachment point")
struct ModalPresentationAudit {

    private func harness() -> (TUIContext, RenderContext, FocusManager) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.terminalHeight = 20
        environment.overlayContentHeight = 18
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 20,
                environment: environment, tuiContext: tui),
            focusManager
        )
    }

    /// Two full passes, driven the way `RenderLoop` drives them — the focus
    /// validation that decides what is reachable happens in `endRenderPass`, so
    /// a bare `renderToBuffer` cannot answer this at all.
    private func reachableBehind(_ place: (AnyView) -> AnyView) -> [String] {
        let (tui, context, focusManager) = harness()
        let trigger = AnyView(
            Text("trigger").modal(isPresented: .constant(true)) {
                Dialog(title: "D") { Button("ok") {} }
            })
        let view = place(trigger)
        for _ in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        // A focus id is built from the identity PATH, never from a label — so
        // "is this the dialog's own control" is a question about the path, and
        // anything whose path does not run through the Dialog is behind it.
        return focusManager.registeredFocusIDsInActiveSection()
            .filter { !$0.contains("Dialog<") }
    }

    @Test("Nothing behind the modal is reachable, wherever the modal hangs")
    func pageIsExcludedFromFocus() {
        func check(_ what: String, _ place: (AnyView) -> AnyView) {
            let strays = reachableBehind(place)
            #expect(strays.isEmpty, "\(what): still reachable behind the modal: \(strays)")
        }
        // The shape every Example page uses: the presentation wraps the page.
        check("the modal wraps the page") { trigger in
            AnyView(VStack { trigger })
        }
        // The shapes it does not, all of them supported.
        check("a sibling before the modal") { trigger in
            AnyView(
                VStack {
                    Button("page") {}
                    trigger
                })
        }
        check("a sibling after the modal") { trigger in
            AnyView(
                VStack {
                    trigger
                    Button("page") {}
                })
        }
        check("siblings both sides") { trigger in
            AnyView(
                VStack {
                    Button("before") {}
                    trigger
                    Button("after") {}
                })
        }
        check("a sibling in another branch") { trigger in
            AnyView(
                HStack {
                    Box { trigger }
                    Box { Button("page") {} }
                })
        }
        check("a sibling inside a ScrollView") { trigger in
            AnyView(
                VStack {
                    trigger
                    ScrollView { Button("page") {} }
                })
        }
        check("a sibling in a Section") { trigger in
            AnyView(
                VStack {
                    trigger
                    Section("s") { Button("page") {} }
                })
        }
    }
}
