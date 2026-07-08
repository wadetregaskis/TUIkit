//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyPressMemoTests.swift
//
//  Regression tests for onKeyPress interacting with the render memos and
//  the measure pass. The key dispatcher clears its handlers every frame, so
//  an onKeyPress inside a value-memoized row went dead on the first
//  cache-hit frame; and a measure-pass render registered a second handler,
//  running the action twice per keypress.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("onKeyPress through the render memos")
struct KeyPressMemoTests {
    @Test("A memoized row's key handler stays registered across cache-hit frames")
    func handlerSurvivesRowMemo() {
        nonisolated(unsafe) var handled = 0
        let tuiContext = TUIContext()
        func frame() {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.keyEventDispatcher.clearHandlers()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let view = VStack {
                ForEach(["row"], id: \.self) { name in
                    Text(name).onKeyPress { _ in
                        handled += 1
                        return true
                    }
                }
            }
            _ = renderToBuffer(view, context: context)
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }

        for expected in 1...3 {
            frame()
            _ = tuiContext.keyEventDispatcher.dispatch(KeyEvent(character: "x"))
            #expect(handled == expected, "frame \(expected): the handler is live, got \(handled)")
        }
    }

    @Test("A measure-pass render does not register a duplicate handler")
    func measurePassDoesNotDuplicate() {
        nonisolated(unsafe) var count = 0
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        var context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)

        tuiContext.keyEventDispatcher.clearHandlers()
        let view = Text("x").onKeyPress { _ in
            count += 1
            return false
        }
        context.isMeasuring = true
        _ = renderToBuffer(view, context: context)  // a render-to-measure ancestor's render
        context.isMeasuring = false
        _ = renderToBuffer(view, context: context)  // the real render
        _ = tuiContext.keyEventDispatcher.dispatch(KeyEvent(character: "y"))

        #expect(count == 1, "one keypress runs the handler exactly once, got \(count)")
    }
}
