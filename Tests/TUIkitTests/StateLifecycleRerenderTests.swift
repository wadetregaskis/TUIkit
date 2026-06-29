//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StateLifecycleRerenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - @State + Lifecycle Re-render Tests

/// Regression coverage for in-place **collection** `@State` mutation inside a
/// lifecycle hook (`.onAppear` / `.task`).
///
/// The reported symptom was that a `@State` array appended to in `.onAppear` /
/// `.task` (e.g. `@State var log: [String] = []` with `log.append(…)`) failed to
/// re-render reliably, while a scalar `@State` (an `Int` counter) mutated the
/// same way did. The two must behave identically, and this suite locks that in.
///
/// **Why it works (and the mechanism this guards):** `@State` binds to its
/// persistent `StateBox` at render time, keyed by the view's own structural
/// identity (`bindStateProperties(of:identity:storage:)`). A lifecycle closure
/// captures the view value, whose `StateBacking` (a reference type) points at
/// that same box; the box outlives view reconstruction in `StateStorage`. An
/// in-place `append` is a get-modify-writeback through `State.wrappedValue`'s
/// `nonmutating set`, which assigns `StateBox.value` and so fires its `didSet` —
/// exactly as a scalar reassignment does — clearing the affected render-cache
/// subtree and calling `AppState.shared.setNeedsRender()`. The next frame
/// re-evaluates `body`, reads the grown array from the same box, and renders it.
/// There is no value-equality gate on the write path, so a collection mutation
/// can never be coalesced away the way an unchanged scalar might be.
///
/// These tests mirror the run loop's per-frame `beginRenderPass` / `endRenderPass`
/// bracket over a `TUIContext` reused across frames (the same shape as
/// `LifecycleModifierTests`), so `@State` persistence and lifecycle-token
/// bookkeeping behave as they do live.
@MainActor
@Suite("State Lifecycle Re-render")
struct StateLifecycleRerenderTests {

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

    /// Renders one frame inside the run loop's `beginRenderPass` / `endRenderPass`
    /// bracket and returns the flattened text, the way the loop drives a frame.
    private func renderFrame<V: View>(_ view: V, context: RenderContext) -> String {
        context.environment.lifecycle?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        context.environment.lifecycle?.endRenderPass()
        return buffer.lines.joined(separator: "\n")
    }

    // MARK: - .onAppear

    @Test("array @State appended in .onAppear renders on the next frame")
    func arrayAppendInOnAppearRenders() {
        let ctx = makeContext()
        struct ContentView: View {
            @State var log: [String] = []
            var body: some View {
                VStack {
                    Text("LOG[\(log.joined(separator: ","))]")
                        .onAppear { log.append("alpha") }
                }
                .padding()
            }
        }
        let view = ContentView()

        let frame1 = renderFrame(view, context: ctx)
        let frame2 = renderFrame(view, context: ctx)

        // The `Text` is built while `body` is evaluated — *before* `.onAppear`'s
        // closure runs (the closure fires later, inside the modifier's own
        // `renderToBuffer`). So frame 1 still shows the empty array; the append
        // landed in the box and flagged a re-render, which frame 2 reflects.
        // (The exact frame the value first appears is timing, not the bug — the
        // bug would be the value *never* appearing.)
        #expect(!frame1.contains("alpha"), "frame 1 renders pre-append (empty) — got:\n\(frame1)")
        #expect(frame2.contains("alpha"), "frame 2 must show the appended 'alpha' — got:\n\(frame2)")
    }

    @Test("multiple appends in .onAppear all render")
    func multipleAppendsInOnAppearRender() {
        let ctx = makeContext(width: 50)
        struct ContentView: View {
            @State var log: [String] = []
            var body: some View {
                VStack {
                    Text("N=\(log.count) LOG[\(log.joined(separator: ","))]")
                        .onAppear {
                            log.append("one")
                            log.append("two")
                            log.append("three")
                        }
                }
                .padding()
            }
        }
        let view = ContentView()

        _ = renderFrame(view, context: ctx)
        let frame2 = renderFrame(view, context: ctx)

        #expect(frame2.contains("N=3"), "expected count 3 — got:\n\(frame2)")
        #expect(frame2.contains("one"), "expected 'one' — got:\n\(frame2)")
        #expect(frame2.contains("two"), "expected 'two' — got:\n\(frame2)")
        #expect(frame2.contains("three"), "expected 'three' — got:\n\(frame2)")
    }

    // MARK: - .task

    @Test("array @State appended in .task renders after the task runs")
    func arrayAppendInTaskRenders() async {
        let ctx = makeContext()
        struct ContentView: View {
            @State var log: [String] = []
            var body: some View {
                VStack {
                    Text("LOG[\(log.joined(separator: ","))]")
                        .task { await append() }
                }
                .padding()
            }
            func append() async { log.append("beta") }
        }
        let view = ContentView()

        // Frame 1 starts the task; the append lands asynchronously afterward.
        _ = renderFrame(view, context: ctx)
        try? await Task.sleep(for: .milliseconds(80))
        let frame2 = renderFrame(view, context: ctx)

        #expect(frame2.contains("beta"), "frame 2 should show 'beta' after the task ran — got:\n\(frame2)")
    }

    // MARK: - Parity with a scalar, and the needsRender signal

    @Test("array append and scalar increment both flag needsRender from .onAppear")
    func arrayAndScalarBothFlagNeedsRender() {
        struct ArrayView: View {
            @State var log: [String] = []
            var body: some View {
                Text("LOG[\(log.joined(separator: ","))]")
                    .onAppear { log.append("x") }
            }
        }
        struct IntView: View {
            @State var count = 0
            var body: some View {
                Text("COUNT=\(count)")
                    .onAppear { count += 1 }
            }
        }

        // Scalar: mutating @State in onAppear marks the shared AppState dirty.
        let intCtx = makeContext()
        AppState.shared.didRender()
        _ = renderFrame(IntView(), context: intCtx)
        let scalarFlagged = AppState.shared.needsRender
        AppState.shared.didRender()

        // Array: the in-place append must mark it dirty the very same way.
        let arrayCtx = makeContext()
        AppState.shared.didRender()
        _ = renderFrame(ArrayView(), context: arrayCtx)
        let arrayFlagged = AppState.shared.needsRender
        AppState.shared.didRender()

        #expect(scalarFlagged, "scalar @State increment should set needsRender")
        #expect(arrayFlagged, "array @State append should set needsRender, exactly like the scalar")
    }

    // MARK: - Rendered through a ForEach (the realistic "log view" shape)

    @Test("array @State driving a ForEach grows on .onAppear append")
    func arrayDrivingForEachGrowsOnAppend() {
        let ctx = makeContext(width: 30, height: 16)
        struct ContentView: View {
            @State var log: [String] = []
            var body: some View {
                VStack(alignment: .leading) {
                    Text("count=\(log.count)")
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text("- \(line)")
                    }
                }
                .padding()
                .onAppear {
                    log.append("first")
                    log.append("second")
                }
            }
        }
        let view = ContentView()

        _ = renderFrame(view, context: ctx)
        let frame2 = renderFrame(view, context: ctx)

        #expect(frame2.contains("count=2"), "ForEach parent should report 2 — got:\n\(frame2)")
        #expect(frame2.contains("first"), "ForEach should render 'first' — got:\n\(frame2)")
        #expect(frame2.contains("second"), "ForEach should render 'second' — got:\n\(frame2)")
    }
}
