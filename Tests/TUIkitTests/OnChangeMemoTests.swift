//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnChangeMemoTests.swift
//
//  Regression tests for onChange(of:) interacting with the render memos and
//  the measure pass. The change detection is a per-frame comparison, so an
//  onChange inside a value-memoized row went permanently blind once the row
//  cached (the observed value changed 1 → 2 → 3, the action never fired).
//  And a measure-pass render used to fire the action a second time within
//  the frame while advancing the per-identity index counter, mis-slotting
//  the render pass's tracked values.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("onChange through the render memos")
struct OnChangeMemoTests {
    @Test("onChange inside a memoized row observes every change")
    func onChangeSurvivesRowMemo() {
        nonisolated(unsafe) var fires: [(Int, Int)] = []
        let tuiContext = TUIContext()
        func frame(observed: Int) {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let view = VStack {
                ForEach(["row"], id: \.self) { name in
                    Text(name).onChange(of: observed) { old, new in fires.append((old, new)) }
                }
            }
            _ = renderToBuffer(view, context: context)
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }

        frame(observed: 1)
        frame(observed: 2)
        frame(observed: 2)
        frame(observed: 3)

        #expect(fires.count == 2, "every change fires exactly once: \(fires)")
        #expect(fires.first ?? (0, 0) == (1, 2))
        #expect(fires.last ?? (0, 0) == (2, 3))
    }

    @Test("A measure-pass render neither fires nor claims an index")
    func measurePassIsSideEffectFree() {
        nonisolated(unsafe) var fires = 0
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        var context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)

        tuiContext.stateStorage.beginRenderPass()
        let view = Text("x").onChange(of: 42, initial: true) { _, _ in fires += 1 }
        context.isMeasuring = true
        _ = renderToBuffer(view, context: context)  // a render-to-measure ancestor's render
        context.isMeasuring = false
        _ = renderToBuffer(view, context: context)  // the real render
        tuiContext.stateStorage.endRenderPass()

        #expect(fires == 1, "initial fires exactly once, on the render pass")
    }
}
