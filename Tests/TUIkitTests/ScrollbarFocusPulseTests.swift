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
    private func rawLines(pulsePhase: Double, focused: Bool) -> [String] {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { i in Text("line \(i)") }
            }
        }
        .scrollbarVisibility(.visible)
        .frame(height: 6)

        func frame() -> [String] {
            var environment = EnvironmentValues()
            // Without a focus manager the ScrollView renders unfocused; with
            // one, the overflowing ScrollView auto-focuses itself.
            if focused { environment.focusManager = focusManager }
            environment.applyRuntimeServices(from: tuiContext)
            environment.pulsePhase = pulsePhase
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
            return buffer.lines
        }
        _ = frame()
        return frame()
    }

    @Test("A focused ScrollView's scrollbar animates with the pulse phase")
    func focusedBarPulses() {
        let dim = rawLines(pulsePhase: 0.0, focused: true)
        let bright = rawLines(pulsePhase: 1.0, focused: true)
        #expect(dim != bright, "the focused bar's bytes track the phase")
    }

    @Test("An unfocused scrollbar is steady across phases")
    func unfocusedBarSteady() {
        let a = rawLines(pulsePhase: 0.0, focused: false)
        let b = rawLines(pulsePhase: 1.0, focused: false)
        #expect(a == b, "unfocused bars must not animate")
    }

    /// Renders a ScrollView with NO scrollbar (so it shows "N more" text
    /// indicators) at a given pulse phase; returns the raw lines.
    private func rawIndicatorLines(pulsePhase: Double, focused: Bool) -> [String] {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { i in Text("line \(i)") }
            }
        }
        // .automatic (default) with a short frame → no bar, just indicators.
        .frame(height: 6)

        func frame() -> [String] {
            var environment = EnvironmentValues()
            if focused { environment.focusManager = focusManager }
            environment.applyRuntimeServices(from: tuiContext)
            environment.pulsePhase = pulsePhase
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
            return buffer.lines
        }
        _ = frame()
        // Scroll to the middle so BOTH indicators show.
        focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first?.scrollOffset = 12
        return frame()
    }

    @Test("A focused scrollbar-less ScrollView pulses its N-more indicators")
    func focusedIndicatorsPulse() {
        let dim = rawIndicatorLines(pulsePhase: 0.0, focused: true)
        let bright = rawIndicatorLines(pulsePhase: 1.0, focused: true)
        #expect(
            dim.contains { $0.contains("▲") } || dim.contains { $0.contains("▼") },
            "an indicator is present: \(dim.map { $0.stripped })")
        #expect(dim != bright, "the focused indicators animate with the phase")

        // Unfocused: steady.
        let a = rawIndicatorLines(pulsePhase: 0.0, focused: false)
        let b = rawIndicatorLines(pulsePhase: 1.0, focused: false)
        #expect(a == b, "unfocused indicators must not animate")
    }
}
