//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalEscapeRouteTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// The modal presenter's layer-2 ESC route and the presenters' drag-state
/// survival — the two counts on which they trailed their siblings.
@MainActor
@Suite("Dialog presenter parity")
struct ModalEscapeRouteTests {

    @Test("ESC dismisses a modal through the key dispatcher, not only the bar")
    func escapeDismissesThroughLayer2() {
        // From a pushed NavigationStack screen the status-bar item is
        // unreachable: the screen's bar claims the ESC label every frame and
        // the bar skips every escape item while a claim stands. The layer-2
        // handler is the route that still works there.
        var presented = true
        var dispatcher: KeyEventDispatcher?
        let context = makeRenderContext(width: 40, height: 12) { environment, tui in
            environment.focusManager = FocusManager()
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            dispatcher = tui.keyEventDispatcher
        }
        let view = Text("page").modal(
            isPresented: Binding(get: { presented }, set: { presented = $0 })
        ) {
            Dialog(title: "D") { Text("body") }
        }
        _ = renderToBuffer(view, context: context)

        let consumed = dispatcher?.dispatch(KeyEvent(key: .escape))
        #expect(consumed == true, "the modal's own section carries the handler")
        #expect(!presented, "ESC must flip the presentation binding")
    }
}
