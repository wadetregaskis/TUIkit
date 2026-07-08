//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LifecycleMemoTests.swift
//
//  Regression tests for the lifecycle modifiers interacting with the render
//  memos. Appearance records are per-frame presence: a value-memoized row
//  serving a cached buffer skipped recordAppear, so its lifecycle tokens
//  vanished from the frame's visible set — endRenderPass then fired
//  onDisappear (and cancelled .tasks) for rows still visibly on screen,
//  with a spurious re-appear on the next cache miss.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Lifecycle through the render memos")
struct LifecycleMemoTests {
    private let tuiContext = TUIContext()

    private func frame<V: View>(_ view: V) {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    @Test("A memoized row's onAppear/onDisappear fire only on real transitions")
    func lifecycleStableWhileCached() {
        nonisolated(unsafe) var appears = 0
        nonisolated(unsafe) var disappears = 0
        let row = { (items: [String]) in
            VStack {
                ForEach(items, id: \.self) { name in
                    Text(name)
                        .onAppear { appears += 1 }
                        .onDisappear { disappears += 1 }
                }
            }
        }

        for _ in 1...4 { frame(row(["row"])) }
        #expect(appears == 1, "one real appearance")
        #expect(disappears == 0, "the row never left the screen, got \(disappears) disappears")

        frame(row([]))  // now it really leaves
        #expect(disappears == 1, "the real removal fires exactly once")
    }

    @Test("A memoized row's .task stays alive across cache-hit frames")
    func taskSurvivesCachedFrames() {
        nonisolated(unsafe) var starts = 0
        let row = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).task { starts += 1 }
            }
        }

        for _ in 1...4 { frame(row) }
        // One start, and — critically — no cancel/restart churn: the token
        // stayed recorded on every frame, so the disappear machinery never
        // cancelled a visible row's task.
        #expect(starts == 1, "the task starts once and is never spuriously restarted, got \(starts)")
    }
}
