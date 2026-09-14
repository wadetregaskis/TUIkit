//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenePhaseTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// `\.scenePhase` — one source of truth, republished each frame from the run
/// loop, exactly as `\.locale` is.
///
/// The transition it exists for (suspend → resume) is a signal round-trip and
/// is not reachable from a unit test; what IS testable, and what would break
/// silently, is that the value the loop holds is the value a view reads.
@MainActor
@Suite("ScenePhase")
struct ScenePhaseTests {

    @Test("A view reads the phase the run loop is holding")
    func phaseFlowsFromTheContext() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()

        environment.applyRuntimeServices(from: tuiContext)
        #expect(environment.scenePhase == .active)

        // What the loop does on the way into a suspend.
        tuiContext.scenePhase = .background
        environment.applyRuntimeServices(from: tuiContext)
        #expect(environment.scenePhase == .background)

        // …and on the way back out.
        tuiContext.scenePhase = .active
        environment.applyRuntimeServices(from: tuiContext)
        #expect(environment.scenePhase == .active)
    }

    @Test("A subtree can override the phase, like any environment value")
    func subtreeOverride() {
        // Not a use anyone should need, but it is what "environment value"
        // means, and a preview or a test harness may want it.
        var environment = EnvironmentValues()
        environment.scenePhase = .background
        #expect(environment.scenePhase == .background)
    }

    @Test("Outside a running app the phase is active")
    func defaultIsActive() {
        // A view being rendered in a test or a snapshot IS being looked at.
        #expect(EnvironmentValues().scenePhase == .active)
    }

    @Test("The phases order the way SwiftUI's do")
    func comparableOrder() {
        // `Comparable`, and background < inactive < active — apps write
        // `if scenePhase >= .inactive`, so the order is API.
        #expect(ScenePhase.background < ScenePhase.inactive)
        #expect(ScenePhase.inactive < ScenePhase.active)
    }

    @Test("A view sees the phase through @Environment")
    func readableFromAView() {
        struct PhaseReader: View {
            @Environment(\.scenePhase) private var scenePhase
            var body: some View {
                Text(scenePhase == .background ? "asleep" : "awake")
            }
        }

        let tuiContext = TUIContext()
        tuiContext.scenePhase = .background
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 2,
            environment: environment, tuiContext: tuiContext)
        // `RenderContext(tuiContext:)` re-wires the core services; the phase
        // has to survive that, or a view would read a default the loop never
        // set.
        #expect(renderToBuffer(PhaseReader(), context: context).lines[0].stripped.contains("asleep"))
    }

    /// The phase changes between frames with no view value and no `@State`
    /// changing, so the render loop's snapshot is the only thing that can tell a
    /// memoized subtree to draw again — the same reason the locale is in it.
    @Test("A phase change changes the environment snapshot")
    func phaseChangeChangesSnapshot() {
        var environment = EnvironmentValues()
        let active = EnvironmentSnapshot(from: environment)
        environment.scenePhase = .background
        #expect(active != EnvironmentSnapshot(from: environment), "a suspend must clear the render cache")
        environment.scenePhase = .inactive
        #expect(active != EnvironmentSnapshot(from: environment))
        environment.scenePhase = .active
        #expect(active == EnvironmentSnapshot(from: environment), "an unchanged phase keeps the cache")
    }

    @Test("A memoized view draws the phase of the frame it is in")
    func memoizedViewFollowsPhase() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(PhaseProbeApp())

        loop.render()
        #expect(frameText(loop).contains("phase active"))

        // What the loop does on the way into a suspend: set the phase, render.
        harness.tuiContext.scenePhase = .background
        loop.render()
        #expect(
            frameText(loop).contains("phase background"),
            "the memoized probe kept the phase from before the suspend")

        harness.tuiContext.scenePhase = .active
        loop.render()
        #expect(frameText(loop).contains("phase active"))
    }

    private func frameText<A: App>(_ loop: RenderLoop<A>) -> String {
        (loop.replayable?.contentLines ?? []).map(\.stripped).joined(separator: "\n")
    }
}

/// Draws the phase it rendered under as text, so a buffer served from the memo
/// shows the OLD phase. Equatable with no stored properties: every frame's value
/// is equal to the last, so only a cleared cache can make it draw again.
private struct PhaseProbe: View, Equatable, Renderable {
    var body: Never { fatalError("PhaseProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "phase \(context.environment.scenePhase)")
    }
}

private struct PhaseProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            PhaseProbe().equatable()
        }
    }
}
