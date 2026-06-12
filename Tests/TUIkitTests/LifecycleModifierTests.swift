//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LifecycleModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Lifecycle Modifier Identity Tests

/// Render-level tests for `.task` / `.onAppear` / `.onDisappear`.
///
/// Regression coverage for the lifecycle-token bug (phranck/TUIkit issue #1,
/// ".task does not fire"): the modifiers used to key the `LifecycleManager` on a
/// `UUID()` minted at construction time. Because a modifier value is rebuilt on
/// every `body` evaluation (every frame), that token changed every frame, so the
/// manager treated each frame as a fresh first-appearance: `.task` restarted
/// every frame (and, when its closure mutates `@State`, spun the render loop
/// forever), `.onAppear` re-fired every frame, and `.onDisappear` fired
/// spuriously for views that never left. The fix keys on the view's structural
/// identity path instead, which is stable across frames.
@MainActor
@Suite("Lifecycle Modifier Identity")
struct LifecycleModifierTests {

    /// A render context whose state/lifecycle persist across frames, like the
    /// real run loop (same `TUIContext` reused each frame).
    private func makeContext(width: Int = 40, height: Int = 12) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = tuiContext.stateStorage
        environment.lifecycle = tuiContext.lifecycle
        environment.keyEventDispatcher = tuiContext.keyEventDispatcher
        environment.mouseEventDispatcher = tuiContext.mouseEventDispatcher
        environment.renderCache = tuiContext.renderCache
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tuiContext
        )
    }

    /// Renders `view` for `frames` frames, mimicking the run loop's per-frame
    /// `beginRenderPass` / `endRenderPass` bracket, sleeping briefly between
    /// frames so spawned `.task`s can run.
    private func renderFrames<V: View>(_ view: V, frames: Int, context: RenderContext) async {
        for _ in 0..<frames {
            context.environment.lifecycle?.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            context.environment.lifecycle?.endRenderPass()
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    // MARK: - .task

    @Test("a single .task fires exactly once across many frames")
    func taskFiresOnce() async {
        let counter = Counter()
        struct CounterView: View {
            let counter: Counter
            var body: some View { Text("x").task { counter.bump() } }
        }
        await renderFrames(CounterView(counter: counter), frames: 5, context: makeContext())
        #expect(counter.value == 1, "expected 1 fire across 5 frames, got \(counter.value)")
    }

    @Test("distinct sibling .tasks each fire once")
    func siblingTasksFireOnce() async {
        let a = Counter(), b = Counter()
        struct TwoTasks: View {
            let a: Counter, b: Counter
            var body: some View {
                VStack {
                    Text("a").task { a.bump() }
                    Text("b").task { b.bump() }
                }
            }
        }
        await renderFrames(TwoTasks(a: a, b: b), frames: 4, context: makeContext())
        #expect(a.value == 1, "task A fired \(a.value)x")
        #expect(b.value == 1, "task B fired \(b.value)x")
    }

    /// The end-to-end shape from the upstream issue: a `.task` that flips a
    /// `@State` flag must update what is rendered on the next frame.
    @Test("a .task that mutates @State updates the rendered output")
    func taskMutatingStateUpdatesRender() async {
        let ctx = makeContext()
        struct ContentView: View {
            @State var taskHasRun = false
            var body: some View {
                VStack {
                    Text(".task has \(taskHasRun ? "indeed" : "not") run")
                        .task { await flag() }
                }
                .padding()
            }
            func flag() async { taskHasRun = true }
        }
        let view = ContentView()

        let frame1 = renderToBuffer(view, context: ctx).lines.joined(separator: "\n")
        #expect(frame1.contains("not run"), "frame 1 should show 'not run'")

        try? await Task.sleep(for: .milliseconds(60))

        ctx.environment.lifecycle?.beginRenderPass()
        let frame2 = renderToBuffer(view, context: ctx).lines.joined(separator: "\n")
        ctx.environment.lifecycle?.endRenderPass()
        #expect(frame2.contains("indeed"), "frame 2 should show 'indeed' — got:\n\(frame2)")
    }

    // MARK: - .onAppear

    @Test("a single .onAppear fires exactly once across many frames")
    func onAppearFiresOnce() async {
        let counter = Counter()
        struct AppearView: View {
            let counter: Counter
            var body: some View { Text("x").onAppear { counter.bump() } }
        }
        await renderFrames(AppearView(counter: counter), frames: 5, context: makeContext())
        #expect(counter.value == 1, "onAppear fired \(counter.value)x")
    }

    // MARK: - .onDisappear

    @Test("onDisappear does not fire while the view stays present")
    func onDisappearStableWhilePresent() async {
        let counter = Counter()
        struct DisappearView: View {
            let counter: Counter
            var body: some View { Text("x").onDisappear { counter.bump() } }
        }
        await renderFrames(DisappearView(counter: counter), frames: 4, context: makeContext())
        #expect(counter.value == 0, "onDisappear fired \(counter.value)x while present")
    }

    @Test("onDisappear fires once when the view is removed")
    func onDisappearFiresOnRemoval() async {
        let ctx = makeContext()
        let counter = Counter()
        struct ConditionalView: View {
            let show: Bool
            let counter: Counter
            var body: some View {
                VStack {
                    if show { Text("here").onDisappear { counter.bump() } }
                }
            }
        }
        // Two frames present, then removed.
        await renderFrames(ConditionalView(show: true, counter: counter), frames: 2, context: ctx)
        #expect(counter.value == 0, "should not fire while present")
        await renderFrames(ConditionalView(show: false, counter: counter), frames: 1, context: ctx)
        #expect(counter.value == 1, "onDisappear should fire once on removal, got \(counter.value)")
    }
}

/// Lock-guarded counter callable from both sync (`onAppear`/`onDisappear`) and
/// async (`.task`) lifecycle closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
