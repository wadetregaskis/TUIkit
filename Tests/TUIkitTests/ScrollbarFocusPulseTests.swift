//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarFocusPulseTests.swift
//
//  A scrollbar that doubles as its container's focus indicator must PULSE
//  the accent while focused (the shared SelectionIndicator convention) —
//  the previous steady accent was too subtle a cue. Unfocused bars stay
//  steady and quiet.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("scrollbar focus pulse")
struct ScrollbarFocusPulseTests {

    /// Renders a focused, scrollbar-bearing ScrollView at a given pulse
    /// phase and returns the RAW lines (SGR bytes included).
    private func barBuffer(focused: Bool) -> FrameBuffer {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { i in Text("line \(i)") }
            }
        }
        .scrollIndicators(.visible)
        .frame(height: 6)

        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            // Without a focus manager the ScrollView renders unfocused; with
            // one, the overflowing ScrollView auto-focuses itself.
            if focused { environment.focusManager = focusManager }
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: 6,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        _ = frame()
        return frame()
    }

    @Test("A focused ScrollView's scrollbar animates with the pulse phase")
    func focusedBarPulses() {
        // The bar breathes through the run loop now: one run per row whose cell
        // actually changes across the cycle. The arrows and the thumb change;
        // the empty track cells do not, and must earn no run — repainting them
        // on a clock would be bytes spent to redraw an unchanged colour.
        let buffer = barBuffer(focused: true)
        let runs = buffer.animatedCells
        #expect(!runs.isEmpty, "a focused bar hands over its animated rows")
        #expect(runs.allSatisfy { $0.isAnimating }, "every run is more than one picture")
        #expect(
            runs.count < buffer.lines.count,
            "the static track rows earn no run: \(runs.count) of \(buffer.lines.count)")

        let barColumn = buffer.width - 1
        for run in runs {
            #expect(run.offsetX == barColumn, "runs sit in the bar's column: \(run)")
            #expect(run.width == 1, "a vertical bar is one cell wide: \(run)")
            #expect(
                run.frames.allSatisfy { $0.strippedLength == 1 },
                "every frame is one cell: \(run)")
            // Replaying this tick's frame changes nothing — which is what
            // proves the run describes the cells that were drawn.
            let before = buffer.lines.map { $0.stripped }
            let replayed = buffer.composited(
                with: FrameBuffer(lines: [run.frame(at: 0)]),
                at: (x: run.offsetX, y: run.offsetY))
            #expect(replayed.lines.map { $0.stripped } == before, "the run moved cells: \(run)")
        }
    }

    @Test("An unfocused scrollbar animates nothing")
    func unfocusedBarSteady() {
        #expect(barBuffer(focused: false).animatedCells.isEmpty)
    }

    /// Renders a ScrollView with NO scrollbar (so it shows "N more" text
    /// indicators) at a given pulse phase; returns the raw lines.
    private func indicatorBuffer(focused: Bool) -> FrameBuffer {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { i in Text("line \(i)") }
            }
        }
        // .automatic (default) with a short frame → no bar, just indicators.
        .frame(height: 6)

        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            if focused { environment.focusManager = focusManager }
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 24, availableHeight: 6,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        _ = frame()
        // Scroll to the middle so BOTH indicators show.
        focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first?.scrollOffset = 12
        return frame()
    }

    @Test("A focused scrollbar-less ScrollView hands over its N-more indicators")
    func focusedIndicatorsPulse() {
        // The indicators breathe through the run loop now, not by being
        // recoloured from the live phase — so what proves it is the runs they
        // leave behind, one per indicator, describing the cells drawn.
        let buffer = indicatorBuffer(focused: true)
        let lines = buffer.lines.map { $0.stripped }
        #expect(
            lines.contains { $0.contains("▲") } && lines.contains { $0.contains("▼") },
            "scrolled to the middle, so both indicators show: \(lines)")

        #expect(buffer.animatedCells.count == 2, "one run per indicator")
        #expect(buffer.animatedCells.allSatisfy { $0.isAnimating }, "both breathe")
        // Top indicator on the first row, bottom on the last.
        #expect(
            buffer.animatedCells.map(\.offsetY).sorted() == [0, buffer.lines.count - 1],
            "the runs sit on the rows the indicators were drawn on")
        for run in buffer.animatedCells {
            #expect(Set(run.frames).count > 1, "more than one picture: \(run)")
            #expect(
                run.frames.allSatisfy { $0.strippedLength == run.width },
                "every frame is the same width: \(run)")
            // The run must describe the cells that were drawn: replaying this
            // tick's frame changes nothing. This is what catches an offset that
            // forgot the centring padding.
            let replayed = buffer.composited(
                with: FrameBuffer(lines: [run.frame(at: 0)]),
                at: (x: run.offsetX, y: run.offsetY))
            #expect(replayed.lines.map { $0.stripped } == lines, "the run moved the cells")
        }
    }

    @Test("An unfocused ScrollView's indicators animate nothing")
    func unfocusedIndicatorsSteady() {
        #expect(indicatorBuffer(focused: false).animatedCells.isEmpty)
    }
}
