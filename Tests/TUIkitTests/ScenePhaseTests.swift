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
}
