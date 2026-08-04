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
        environment.applyRuntimeServices(from: tuiContext)
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

    // MARK: - .task isolation

    /// `.task`'s action inherits the isolation of the context it is written in
    /// — the view body, which is `@MainActor` — so `@State` writes in it are
    /// safe without an `await`. That is the SwiftUI contract and the default.
    ///
    /// It is only the default. The parameter carries whatever isolation the
    /// closure actually has, so an app that does not want the main actor
    /// occupied says so. `{ @concurrent in … }` worked before this too (a
    /// concurrent closure converts to a `@MainActor` function type and still
    /// runs concurrently); the case a hard `@MainActor` parameter could NOT
    /// express is a custom global actor — `{ @Indexing in … }` was a compile
    /// error ("cannot convert value actor-isolated to 'Indexing' to expected
    /// argument type actor-isolated to 'MainActor'"), so this test does not
    /// build against the old signature at all.
    @Test("A .task written in a body runs on the main actor; other isolations are honoured")
    func taskIsolationIsInheritedAndChoosable() async {
        let inBody = Isolation(), opted = Isolation(), onActor = Isolation()
        struct IsolationView: View {
            let inBody: Isolation, opted: Isolation, onActor: Isolation
            var body: some View {
                VStack {
                    Text("a").task { inBody.record(runningOnMain()) }
                    Text("b").task { @concurrent in opted.record(runningOnMain()) }
                    Text("c").task { @Indexing in onActor.record(runningOnMain()) }
                }
            }
        }
        await renderFrames(
            IsolationView(inBody: inBody, opted: opted, onActor: onActor),
            frames: 4, context: makeContext())
        #expect(inBody.wasOnMain == true, "the default is the body's own isolation")
        #expect(opted.wasOnMain == false, "@concurrent must actually leave the main actor")
        #expect(onActor.wasOnMain == false, "a global-actor action runs on ITS actor")
    }

    /// The compile-time half of the same contract: a `@MainActor`-isolated
    /// value is readable and writable directly in the default closure. If the
    /// action ever stopped inheriting the body's isolation this would need an
    /// `await` and the file would not build.
    @Test("The default .task closure touches main-actor state without awaiting")
    func taskDefaultTouchesMainActorStateSynchronously() async {
        let counter = Counter()
        struct StateView: View {
            @State private var flag = false
            let counter: Counter
            var body: some View {
                Text(flag ? "on" : "off")
                    .task {
                        flag = true  // @State write, no await: main-actor isolated
                        counter.bump()
                    }
            }
        }
        await renderFrames(StateView(counter: counter), frames: 3, context: makeContext())
        #expect(counter.value == 1)
    }
}

/// Whether the caller is isolated to the main actor.
///
/// Asks about the *actor*, via `#isolation` as a default argument — which
/// resolves to the calling context's isolation — rather than about the thread.
/// `Thread.isMainThread` was the obvious reading and is the wrong one: it
/// answers a question the main actor does not promise. On Linux the main
/// actor is drained by a cooperative pool thread after the first suspension
/// point, so a `.task` that correctly inherited `@MainActor` still reported
/// `isMainThread == false` and failed this test. `#isolation` distinguishes
/// the three cases the test cares about exactly — inherited `@MainActor`,
/// `@concurrent` (nonisolated, so `nil`), and a custom global actor — on
/// every platform, because it is the isolation itself and not a proxy for it.
private func runningOnMain(isolation: (any Actor)? = #isolation) -> Bool {
    isolation === MainActor.shared
}

/// A custom global actor, standing in for an app's own — the isolation a
/// `@MainActor`-typed parameter could not accept.
@globalActor private actor Indexing {
    static let shared = Indexing()
}

private final class Isolation: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    var wasOnMain: Bool? { lock.withLock { value } }
    func record(_ onMain: Bool) { lock.withLock { if value == nil { value = onMain } } }
}

/// Lock-guarded counter callable from both sync (`onAppear`/`onDisappear`) and
/// async (`.task`) lifecycle closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
