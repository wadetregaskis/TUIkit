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

        _ = timer.pulsePhase(for: .standard)
        #expect(timer.didReadThisFrame)  // a text field consulted the cursor clock

        timer.beginFrameReadTracking()
        #expect(!timer.didReadThisFrame)  // reset for the next frame

        _ = timer.blinkVisible(for: .standard)
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
        // The clock is reset whenever the focus moves, so frame 0 is what a
        // newly focused control shows. A breath that began dim left it looking
        // unfocused for a third of a second — at the moment it most needs to
        // be seen.
        for speed in speeds {
            let count = CursorTimer.cycleLayout(of: .pulse, speed: speed).frameCount
            #expect(CursorTimer.pulsePhase(atFrame: 0, of: count) == 1)
        }
    }

    @Test("A breath is a round trip: bright → dim → bright")
    func breathIsARoundTrip() {
        for speed in speeds {
            let count = CursorTimer.cycleLayout(of: .pulse, speed: speed).frameCount
            let phases = (0...count).map { CursorTimer.pulsePhase(atFrame: $0, of: count) }
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

    /// Waits for the timer to actually tick, rather than sleeping a fixed
    /// span and hoping.
    ///
    /// The clock advances on a `Task` that sleeps 50 ms between ticks, and
    /// under a full test run the main actor is contended enough that a fixed
    /// 150 ms wait sometimes saw zero of them — these passed alone and failed
    /// in the suite, which is the worst way for a test to be wrong.
    private func awaitFirstTick(_ timer: CursorTimer) async {
        for _ in 0..<200 where timer.elapsed(for: .content) == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 100,000 s of uptime, on the 50 ms lattice: far past any real reading of the
    /// monotonic clock in a test process, so the times a test shows the timer are
    /// the ones it keeps.
    private let base: UInt64 = 100_000 * 1_000_000_000

    @Test("A late wake credits the time that passed, not the sleep it asked for")
    func aLateWakeCreditsWhatPassed() async {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.start()
        await awaitFirstTick(timer)
        let before = timer.elapsed(for: .content)

        // Hold the main actor far past the 50 ms sleep, busy rather than asleep, the
        // shape of `expiredSleepDoesNotCreditAfterRestart`: the wake is due and
        // cannot run until this lets go.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        while ContinuousClock.now < deadline {}
        for _ in 0..<2000 where timer.elapsed(for: .content) == before {
            try? await Task.sleep(for: .milliseconds(1))
        }

        // The clock added the sleep it had ASKED for — 0.05 s, however late the wake
        // was — so every wake lost its lateness, and every animation ran slow.
        let credited = timer.elapsed(for: .content) - before
        #expect(credited >= 0.2, "a 250 ms stall credited \(credited) s")
        timer.stop()
    }

    @Test("The content clock is the monotonic clock, and the cursor clock starts at the first observe")
    func cursorClockStartsAtTheFirstObserve() {
        let timer = CursorTimer(renderNotifier: AppState())
        let now = base + 1_234_000_000
        timer.observe(nowNanos: now)
        #expect(timer.elapsed(for: .content) == Double(now) / 1_000_000_000)
        // Bright at once, on the tick lattice: 1.234 s is 34 ms past the 1.200 s tick.
        #expect(timer.ticks(for: .cursor) == 0)
        #expect(abs(timer.elapsed(for: .cursor) - 0.034) < 1e-9)
        // The two used to share a zero until the first focus change. `.content` no
        // longer has one of its own.
        #expect(timer.elapsed(for: .cursor) != timer.elapsed(for: .content))
    }

    @Test("A focus change restarts the cursor clock at the next frame and leaves the content clock alone")
    func focusRestartLeavesTheContentClockAlone() {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.observe(nowNanos: base + 1_234_000_000)
        timer.observe(nowNanos: base + 4_234_000_000)
        let content = timer.elapsed(for: .content)
        #expect(timer.ticks(for: .cursor) == 60, "three seconds of blink, 34 ms past a tick")

        timer.restartFocusPhase()

        // It reads no clock. Everything that is not about the focus stays where it
        // was: pressing Tab used to zero the one elapsed time every indeterminate bar,
        // spinner and breathing label derives its phase from, so they all jumped back
        // to the start of their cycle.
        #expect(timer.elapsed(for: .content) == content)
        #expect(timer.elapsed(for: .cursor) == 0)

        // The frame that follows comes 56 ms later, more than a tick. It is still tick
        // 0 — the zero is taken HERE, floored to 4.250 s — where a zero floored when the
        // focus moved (4.234 s → 4.200 s) would already have been tick 1, and the newly
        // focused control would have missed its bright start.
        timer.observe(nowNanos: base + 4_290_000_000)
        #expect(timer.ticks(for: .cursor) == 0)
        timer.observe(nowNanos: base + 4_340_000_000)
        #expect(timer.ticks(for: .cursor) == 1)
    }

    @Test("A sleep that expired before the focus moved does not credit the re-zeroed clock")
    func expiredSleepDoesNotCreditAfterRestart() async {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.advance(by: 0.2)  // the long stride a quantised pulse asks for
        timer.start()
        // The yield is load-bearing: `start()` only ENQUEUES the task, and the
        // block below holds the main actor, so without it the task would never
        // reach its sleep and the race under test could not happen.
        await Task.yield()

        // Hold the main actor past the sleep's deadline. Busy, not `Task.sleep`:
        // the point is that the wake resumes the task's continuation and queues
        // it HERE, where it cannot run — and can no longer be cancelled.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(350))
        while ContinuousClock.now < deadline {}

        // The focus moves, in that same synchronous stretch. The app's own
        // re-arm (the render that follows every focus change calls `start()`)
        // is deliberately NOT done here: a live task's legitimate 50 ms ticks
        // would race the assertion below, and the stale credit is the same
        // either way — in the app it simply lands on top of that cadence.
        timer.restartFocusPhase()
        for _ in 0..<4 { await Task.yield() }

        // The stale task's cancel lost the race with its own wake, so it woke
        // "successfully". When the clock was a sum of sleeps, that credited its
        // whole 0.2 s stride to a clock whose zero had just been moved to now — the
        // breath jumped from its bright end to mid-cycle, one tick after taking the
        // focus. Measured, the same wake would fix the new zero at the stale wake
        // rather than at the render that follows the focus change.
        #expect(
            timer.elapsed(for: .cursor) == 0,
            "credited \(timer.elapsed(for: .cursor))s to a clock just re-zeroed")
        timer.stop()
    }

    @Test("Stopping restarts the cursor clock and leaves the content clock on the monotonic clock")
    func stopRestartsOnlyTheCursorClock() {
        let timer = CursorTimer(renderNotifier: AppState())
        timer.observe(nowNanos: base + 1_234_000_000)
        timer.observe(nowNanos: base + 5_000_000_000)
        #expect(timer.ticks(for: .cursor) == 76)

        timer.stop()
        let later = base + 9_876_000_000
        timer.observe(nowNanos: later)

        // Not zeroed, and not frozen where it stopped: a spinner that appears on a
        // page that has been still starts where the shared clock is.
        #expect(timer.elapsed(for: .content) == Double(later) / 1_000_000_000)
        #expect(timer.ticks(for: .cursor) == 0, "the cursor clock restarts at its bright end")
    }
}
