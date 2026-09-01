//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationClockGatingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Validates the primitives behind demand-driven animation: a render frame
/// reports whether it consumed the animation clock — through the `pulsePhase`
/// seam or by resolving a focused `SelectionEmphasis` — so the run loop keeps
/// the clock ticking, and reports neither for a static frame (so the loop idles
/// at zero CPU). See `RenderLoop.RenderActivity` and `App.renderFrame`.

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

// MARK: - One clock

@MainActor
@Suite("One focus clock")
struct FocusClockUnityTests {

    /// Every speed the style offers.
    private var speeds: [TextCursorStyle.Speed] { [.slow, .regular, .fast] }

    @Test("A breath starts at its BRIGHT end")
    func breathStartsBright() {
        // The clock is reset whenever the focus moves, so tick 0 is what a
        // newly focused control shows. A breath that began dim left it looking
        // unfocused for a third of a second — at the moment it most needs to
        // be seen.
        for speed in speeds {
            #expect(CursorTimer.pulsePhase(atTick: 0, speed: speed) == 1)
        }
    }

    @Test("A breath is a round trip: bright → dim → bright")
    func breathIsARoundTrip() {
        for speed in speeds {
            let ticks = CursorTimer.cycleTicks(for: speed, animation: .pulse)
            let phases = (0...ticks).map { CursorTimer.pulsePhase(atTick: $0, speed: speed) }
            #expect(phases.min()! < 0.02, "\(speed): never reached the dim end")
            #expect(phases.last! > 0.98, "\(speed): did not come back bright")
        }
    }

    @Test("The phase seam and the emphasis clock are the same breath")
    func oneFormulaBehindBoth() {
        // The bug this pins: there were two clocks, at 2 s and 0.8 s, and which
        // one a focus indicator breathed on depended purely on which route its
        // view happened to take — a section's border against the controls
        // inside it. Both now come from `CursorTimer`.
        let timer = CursorTimer(renderNotifier: AppState())
        var env = EnvironmentValues()
        env.cursorTimer = timer
        let seam = timer.breathPhase
        let emphasis = SelectionIndicator.resolve(isFocused: true, environment: env)
        #expect(emphasis.phase == seam)
    }

    @Test("The clock roster is two, and deliberately so")
    func theClockRoster() {
        // This used to assert `[.cursor]`, and the assertion was doing its
        // job: a second clock should be a decision, not a drift. The decision
        // was made — `.cursor` is focus-relative and `.content` is monotonic,
        // and they differ ONLY in where their zero sits (one timer drives
        // both, see `CursorTimer.elapsed(for:)`). A third still needs a reason
        // and a producer, and this still fails until someone gives it both.
        #expect(Set(AnimationClock.allCases) == [.cursor, .content])
    }

    // MARK: - The two clocks

    @Test("Both clocks start together")
    func clocksAgreeBeforeAnyFocusChange() async {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.start()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(timer.elapsed(for: .content) > 0, "the timer ran at all")
        #expect(timer.elapsed(for: .cursor) == timer.elapsed(for: .content))
        timer.stop()
    }

    @Test("A focus change restarts the cursor clock and leaves the content clock running")
    func focusRestartLeavesTheContentClockAlone() async {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.start()
        try? await Task.sleep(for: .milliseconds(150))
        // Read before restarting, and with no `await` between: this is the
        // main actor, so the timer's task cannot advance the clock in here.
        let content = timer.elapsed(for: .content)
        #expect(content > 0, "the timer ran at all")

        timer.restartFocusPhase()

        // The blink and the focus breath start over, so whatever just took the
        // focus is at its bright end.
        #expect(timer.elapsed(for: .cursor) == 0)
        // Everything else does not. This is the whole point: pressing Tab used
        // to zero `elapsedSeconds`, which is the number every indeterminate
        // bar, spinner and breathing label derives its phase from, so they all
        // jumped back to the start of their cycle.
        #expect(timer.elapsed(for: .content) == content)
        timer.stop()
    }

    @Test("Stopping puts both clocks back to zero")
    func stopZeroesBoth() async {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.start()
        try? await Task.sleep(for: .milliseconds(150))
        timer.restartFocusPhase()
        timer.stop()
        #expect(timer.elapsed(for: .content) == 0)
        #expect(timer.elapsed(for: .cursor) == 0)
    }
}
