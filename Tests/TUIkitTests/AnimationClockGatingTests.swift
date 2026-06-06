//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationClockGatingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Validates the primitives behind demand-driven animation: a render frame
/// reports whether it consumed the pulse clock (so the run loop keeps the pulse
/// timer ticking) or the cursor clock (cursor blink), and reports neither for a
/// static frame (so the loop idles at zero CPU). See `RenderLoop.RenderActivity`
/// and `App.run`'s `applyAnimationActivity`.

/// A non-interactive view that reads the per-frame-volatile pulse phase.
private struct PulseConsumer: View, Renderable {
    var body: Never { fatalError("PulseConsumer renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: "phase \(context.environment.pulsePhase)")
    }
}

@MainActor
@Suite("Animation clock gating")
struct AnimationClockGatingTests {

    private func context(_ tracker: VolatileReadTracker) -> RenderContext {
        var env = EnvironmentValues()
        env.pulsePhase = 0.5
        env.volatileReadTracker = tracker
        return RenderContext(availableWidth: 40, availableHeight: 10, environment: env)
    }

    @Test("A frame that consumes pulsePhase is detected (timer keeps ticking)")
    func pulseConsumptionDetected() {
        let tracker = VolatileReadTracker()
        _ = renderToBuffer(PulseConsumer(), context: context(tracker))
        // > 0 ⇒ RenderActivity.usesPulse would be true ⇒ pulse timer kept alive.
        #expect(tracker.reads > 0)
    }

    @Test("A static frame consumes no pulse (timer stops → idle)")
    func staticFrameConsumesNoPulse() {
        let tracker = VolatileReadTracker()
        _ = renderToBuffer(Text("static"), context: context(tracker))
        // 0 ⇒ usesPulse false ⇒ pulse timer stopped ⇒ no further frames.
        #expect(tracker.reads == 0)
    }

    @Test("CursorTimer records per-frame reads (cursor blink keeps ticking)")
    func cursorReadFlagTracksPerFrameConsumption() {
        let timer = CursorTimer(renderNotifier: AppState())

        timer.beginFrameReadTracking()
        #expect(!timer.didReadThisFrame)  // fresh frame: nothing read yet

        _ = timer.pulsePhase(for: .regular)
        #expect(timer.didReadThisFrame)  // a text field consulted the cursor clock

        timer.beginFrameReadTracking()
        #expect(!timer.didReadThisFrame)  // reset for the next frame

        _ = timer.blinkVisible(for: .regular)
        #expect(timer.didReadThisFrame)  // blink path also counts
    }
}
