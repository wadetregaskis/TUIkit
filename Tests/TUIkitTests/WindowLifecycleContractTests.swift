//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WindowLifecycleContractTests.swift
//
//  The lifecycle contract for rows entering and leaving a windowed stack's
//  band, and its deliberate asymmetry with §5h state retention: @State
//  SURVIVES off-window (retainSubtree keeps the boxes), but lifecycle is
//  per-frame presence — leaving the band fires .onDisappear and cancels
//  .task; re-entering re-fires .onAppear and restarts .task. That matches
//  SwiftUI's lazy containers, and both halves are load-bearing: extending
//  retention to lifecycle tokens would leak every scrolled-past row's task;
//  extending lifecycle to state would reset scroll-through form fields.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Per-row lifecycle counters. @unchecked: driven on the main actor.
private final class LifecycleLog: @unchecked Sendable {
    var appears: [Int: Int] = [:]
    var disappears: [Int: Int] = [:]
}

@MainActor
@Suite("windowed band lifecycle contract")
struct WindowLifecycleContractTests {
    private static let rows = 40
    private static let viewport = 6

    /// One live-loop-shaped frame INCLUDING the lifecycle pass boundaries
    /// (they drive onAppear/onDisappear resolution).
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, offset: Int
    ) {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.rows * 2,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        tuiContext.lifecycle.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    private func makeView(log: LifecycleLog) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { i in
                Text("row \(i)")
                    .onAppear { log.appears[i, default: 0] += 1 }
                    .onDisappear { log.disappears[i, default: 0] += 1 }
            }
        }
    }

    @Test("Rows fire onAppear on band entry, onDisappear on exit, and re-fire on re-entry")
    func bandEntryAndExitDriveLifecycle() {
        let tuiContext = TUIContext()
        let log = LifecycleLog()
        let view = makeView(log: log)

        // Frame 1 at the top: the visible rows (plus margin) appear; deep
        // rows do not.
        renderFrame(view, tuiContext: tuiContext, offset: 0)
        #expect(log.appears[0] == 1, "top row appeared once: \(log.appears)")
        #expect(log.appears[20] == nil, "an off-window row must NOT appear: \(log.appears)")
        #expect(log.disappears.isEmpty, "nothing disappeared yet: \(log.disappears)")

        // Scroll deep: the top rows leave the band (onDisappear), the newly
        // visible rows appear.
        renderFrame(view, tuiContext: tuiContext, offset: 20)
        #expect(log.disappears[0] == 1, "row 0 left the band: \(log.disappears)")
        #expect(log.appears[20] == 1, "row 20 entered the band: \(log.appears)")

        // Scroll back: row 0 RE-fires onAppear (fresh appearance, SwiftUI
        // lazy-container semantics), row 20 disappears.
        renderFrame(view, tuiContext: tuiContext, offset: 0)
        #expect(log.appears[0] == 2, "re-entry re-fires onAppear: \(log.appears)")
        #expect(log.disappears[20] == 1, "row 20 left the band: \(log.disappears)")

        // Steady frames fire nothing.
        let appearsBefore = log.appears
        let disappearsBefore = log.disappears
        renderFrame(view, tuiContext: tuiContext, offset: 0)
        #expect(log.appears == appearsBefore, "steady frame: no appears")
        #expect(log.disappears == disappearsBefore, "steady frame: no disappears")
    }

    @Test("@State survives leaving the band while lifecycle does not (the §5h asymmetry)")
    func stateSurvivesWhereLifecycleResets() {
        // A row whose state was mutated, scrolled away, and scrolled back
        // must KEEP the mutation (retainSubtree) even though its lifecycle
        // re-fired. StatefulProbeRow bumps its own @State-backed box once
        // from onAppear-count 1 only — if state were reset on re-entry, the
        // second appearance would bump it again.
        let tuiContext = TUIContext()
        let log = LifecycleLog()
        let box = ValueBox()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { i in
                if i == 0 {
                    StatefulProbeRow(box: box)
                        .onAppear { log.appears[i, default: 0] += 1 }
                } else {
                    Text("row \(i)")
                }
            }
        }

        renderFrame(view, tuiContext: tuiContext, offset: 0)
        renderFrame(view, tuiContext: tuiContext, offset: 0)
        #expect(box.observedValues.contains(1), "the row's state was written: \(box.observedValues)")

        renderFrame(view, tuiContext: tuiContext, offset: 20)  // row 0 leaves
        renderFrame(view, tuiContext: tuiContext, offset: 0)  // …and returns
        renderFrame(view, tuiContext: tuiContext, offset: 0)
        #expect(log.appears[0] == 2, "row 0 re-appeared: \(log.appears)")
        #expect(
            box.observedValues.last == 1,
            "state survived the round trip (no reset to 0, no double bump): \(box.observedValues)")
    }
}

/// Records every value the probe row's @State held when rendered.
private final class ValueBox: @unchecked Sendable {
    var observedValues: [Int] = []
}

private struct StatefulProbeRow: View {
    let box: ValueBox
    @State private var value = 0

    var body: some View {
        box.observedValues.append(value)
        return Text("stateful \(value)")
            .onAppear { if value == 0 { value = 1 } }
    }
}
