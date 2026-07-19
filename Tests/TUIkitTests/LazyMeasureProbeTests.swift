//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyMeasureProbeTests.swift
//
//  The measure-laziness contract for a windowed LazyVStack in a ScrollView:
//  after the first frame's one-time seed, the measure pass touches EXACTLY
//  the rows the render draws (the visible band) — no off-band row is
//  measured, even when the render cache is cold (any `@State` write clears
//  it, so cold caches are the app's steady state, not a corner). Before the
//  width hypothesis, every cache-cold measure re-sampled up to 64 rows for
//  width/flexibility — the WHOLE stack for ≤64 rows, every frame, which is
//  what the Layout demo's "Measured: 0–39" read-out was faithfully showing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
private final class PassSink {
    var measured: Set<Int> = []
    var rendered: Set<Int> = []
    func reset() {
        measured.removeAll()
        rendered.removeAll()
    }
}

@MainActor
@Suite("windowed stack measure laziness")
struct LazyMeasureProbeTests {

    private func makeHarness(rowCount: Int) -> (
        view: any View, tuiContext: TUIContext, focusManager: FocusManager, sink: PassSink
    ) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let sink = PassSink()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { i in
                    Text("row \(i)")
                        .onRenderPass { pass in
                            if pass == .measure {
                                sink.measured.insert(i)
                            } else {
                                sink.rendered.insert(i)
                            }
                        }
                }
            }
        }
        .frame(height: 8)
        return (view, tuiContext, focusManager, sink)
    }

    private func frame(
        _ view: any View, tuiContext: TUIContext, focusManager: FocusManager, sink: PassSink
    ) {
        sink.reset()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 8,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    @Test("Steady state: measured == rendered == the visible band, cache-cold")
    func steadyStateMeasuresOnlyTheBand() {
        let (view, tuiContext, focusManager, sink) = makeHarness(rowCount: 100)

        // Frame 1: the one-time seed legitimately walks every row (the exact
        // measure walk before the render seeds the hypotheses).
        frame(view, tuiContext: tuiContext, focusManager: focusManager, sink: sink)
        #expect(sink.rendered.count < 15, "only the band renders on frame 1: \(sink.rendered)")

        // Steady frames with the render cache CLEARED each time — the state
        // any real app is in after a @State write. The measure pass must
        // still touch only the band (the hypothesis answers from persisted
        // state, not the memo).
        for pass in 0..<3 {
            tuiContext.renderCache.clearAll()
            frame(view, tuiContext: tuiContext, focusManager: focusManager, sink: sink)
            #expect(
                sink.measured == sink.rendered,
                "pass \(pass): measured \(sink.measured.sorted()) == rendered \(sink.rendered.sorted())")
            #expect(
                sink.measured.count <= 12,
                "pass \(pass): no off-band measures: \(sink.measured.sorted())")
            #expect(sink.rendered.contains(0), "pass \(pass): the band starts at the top")
        }

        // Scrolled mid-way: the band — and ONLY the band — moves with it.
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil, "the ScrollView registered its handler")
        handler?.scrollOffset = 50
        tuiContext.renderCache.clearAll()
        frame(view, tuiContext: tuiContext, focusManager: focusManager, sink: sink)
        #expect(
            sink.measured == sink.rendered,
            "scrolled: measured \(sink.measured.sorted()) == rendered \(sink.rendered.sorted())")
        #expect(
            sink.measured.allSatisfy { $0 >= 48 && $0 <= 60 },
            "scrolled: the measured band tracks the offset: \(sink.measured.sorted())")
        #expect(!sink.measured.contains(0), "scrolled: the top rows are not touched")
    }

    @Test("The scroll extent stays exact under the arithmetic (hypothesis) path")
    func hypothesisHeightIsExact() {
        let (view, tuiContext, focusManager, sink) = makeHarness(rowCount: 100)
        frame(view, tuiContext: tuiContext, focusManager: focusManager, sink: sink)
        frame(view, tuiContext: tuiContext, focusManager: focusManager, sink: sink)
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler?.contentHeight == 100, "100 one-line rows: \(handler?.contentHeight ?? -1)")
    }
}
