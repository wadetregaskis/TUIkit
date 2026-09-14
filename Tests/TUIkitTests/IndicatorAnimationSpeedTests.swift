//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorAnimationSpeedTests.swift
//
//  `IndicatorAnimationSpeed` and the environment value and modifier that carry
//  it, checked through the one indicator that reads it so far: `Spinner`.
//  Durations are compared in whole nanoseconds, the unit a run's steps are
//  counted in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - The value

@Suite("Indicator animation speed values")
struct IndicatorAnimationSpeedValueTests {
    @Test("At tolerance 0 a frame lasts the standard duration divided by the rate, bit for bit")
    func exactDuration() {
        for (rate, standard) in [(2.0, 0.11), (1.1, 0.11), (0.5, 0.12), (3.0, 1.0 / 30), (1.5, 0.13)] {
            let duration = IndicatorAnimationSpeed(rate).frameDuration(standard: standard)
            #expect(duration.bitPattern == (standard / rate).bitPattern, "rate \(rate), standard \(standard)")
        }
    }

    /// 110 ms at 1.05 ± 0.05 accepts 100 ms to 110 ms, and 100 ms is the tick multiple in it.
    @Test("A tolerance, in the rate's own units, lets a duration move onto a tick multiple")
    func toleranceIsInRateUnits() {
        let speed = IndicatorAnimationSpeed(1.05, tolerance: 0.05)
        #expect(AnimationClock.nanoseconds(speed.frameDuration(standard: 0.11)) == 100_000_000)
        // 2 ± 0.1 is 1.9 to 2.1, so 110 ms goes to 52.4 ms to 57.9 ms, which holds
        // no 25 ms multiple. As a fraction of the rate (2 ± 0.2) it would reach 50 ms.
        let two = IndicatorAnimationSpeed(2, tolerance: 0.1)
        #expect(AnimationClock.nanoseconds(two.frameDuration(standard: 0.11)) == 55_000_000)
    }

    @Test(
        "A rate that is not finite and greater than zero is rejected, reported, and replaced by 1",
        arguments: [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity])
    func rejectsRate(_ rate: Double) {
        var reports: [String] = []
        let speed = IndicatorAnimationSpeed(rate, tolerance: 0.05, onRejection: { reports.append($0) })
        #expect(speed.rate == 1)
        #expect(speed.tolerance == 0)
        #expect(reports.count == 1)
        #expect(reports.first?.contains("rate must be finite and greater than zero") == true, "\(reports)")
    }

    @Test(
        "A tolerance below zero, not finite, or not less than the rate is rejected, reported, and replaced by 0",
        arguments: [-0.1, Double.nan, Double.infinity, 2.0, 3.0])
    func rejectsTolerance(_ tolerance: Double) {
        var reports: [String] = []
        let speed = IndicatorAnimationSpeed(2, tolerance: tolerance, onRejection: { reports.append($0) })
        #expect(speed.rate == 2)
        #expect(speed.tolerance == 0)
        #expect(reports.count == 1)
        #expect(reports.first?.contains("tolerance must be at least zero and less than") == true, "\(reports)")
    }

    @Test("A usable rate and tolerance are kept as given, unreported")
    func keepsUsableValues() {
        for (rate, tolerance) in [(1.0, 0.0), (2.0, 0.1), (0.5, 0.49), (1.05, 0.05), (400.0, 0.0)] {
            var reports: [String] = []
            let speed = IndicatorAnimationSpeed(rate, tolerance: tolerance, onRejection: { reports.append($0) })
            #expect(speed.rate == rate && speed.tolerance == tolerance)
            #expect(reports.isEmpty, "\(reports)")
        }
    }

    @Test("The presets and literals are the rates they name, exact")
    func presets() {
        #expect(IndicatorAnimationSpeed.standard == IndicatorAnimationSpeed(1))
        #expect(IndicatorAnimationSpeed.halfSpeed == IndicatorAnimationSpeed(0.5))
        #expect(IndicatorAnimationSpeed.doubleSpeed == IndicatorAnimationSpeed(2))
        let literal: IndicatorAnimationSpeed = 1.5
        #expect(literal.rate == 1.5 && literal.tolerance == 0)
        #expect(IndicatorAnimationSpeed.automatic.rate == 1)
    }

    @Test(".all is the union of every kind, and each kind is set on its own")
    func kindsAreSetIndependently() {
        #expect(IndicatorAnimations.all == [.textCursor, .focusEmphasis, .spinners, .indeterminateProgress])
        var speeds = IndicatorAnimationSpeeds()
        #expect(speeds == EnvironmentValues().indicatorAnimationSpeeds)
        #expect(speeds.speed(for: .spinners) == .automatic)
        speeds.set(2, for: .all)
        for kind in [IndicatorAnimations.textCursor, .focusEmphasis, .spinners, .indeterminateProgress] {
            #expect(speeds.speed(for: kind) == 2)
        }
        speeds.set(0.5, for: .spinners)
        #expect(speeds.speed(for: .spinners) == 0.5)
        #expect(speeds.speed(for: .textCursor) == 2)
    }

    #if DEBUG
        /// The default report is a soft trap, so a debug build stops. In a child
        /// process, because a stop in this one would end the test run.
        @Test("A zero rate stops a debug build")
        func zeroRateStopsADebugBuild() async {
            await #expect(processExitsWith: .failure) {
                _ = IndicatorAnimationSpeed(0)
            }
        }

        @Test("A tolerance as large as the rate stops a debug build")
        func wholeRateToleranceStopsADebugBuild() async {
            await #expect(processExitsWith: .failure) {
                _ = IndicatorAnimationSpeed(1, tolerance: 1)
            }
        }
    #endif
}

// MARK: - Spinners

/// A spinner whose two frames are one cell and two wide, so no run can hold it,
/// at three times the speed.
private struct FastMixedWidthSpinnerApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Spinner(style: .custom("-你")).indicatorAnimationSpeed(3, for: .spinners)
        }
    }
}

/// An `Equatable` view that never changes, wrapping a spinner, so its buffer
/// can be served from the memo.
private struct MemoizedSpinner: View, Equatable {
    var body: some View {
        Spinner(style: .dots)
    }
}

@MainActor
@Suite("Indicator animation speed on spinners")
struct IndicatorAnimationSpeedSpinnerTests {
    /// The frame duration of every run `view` leaves, in nanoseconds, in order.
    private func runNanos(_ view: some View) -> [Int64] {
        let context = RenderContext(availableWidth: 40, availableHeight: 4, tuiContext: TUIContext())
            .isolatingRenderCache()
        return renderToBuffer(view, context: context).animatedCells.map {
            AnimationClock.nanoseconds($0.frameDuration)
        }
    }

    /// `.automatic` is 1 ± 0.05, so 110 ms accepts 104.8 ms to 115.8 ms, which holds
    /// no whole number of 25 ms ticks.
    @Test("Unset, a .dots spinner shows each frame for its style's 110 ms")
    func unsetIsTheStyleInterval() {
        #expect(runNanos(Spinner(style: .dots)) == [110_000_000])
    }

    /// 120 ms at 1 ± 0.05 accepts 114.3 ms to 126.3 ms, and 125 ms, five base
    /// ticks, is in it. `.standard` is exact.
    @Test("Unset, a .pie spinner shows each frame for 125 ms, and at .standard for its style's 120 ms")
    func automaticMovesOntoTheLattice() {
        #expect(IndicatorAnimationSpeed.automatic == IndicatorAnimationSpeed(1, tolerance: 0.05))
        #expect(runNanos(Spinner(style: .pie)) == [125_000_000])
        #expect(runNanos(Spinner(style: .pie).indicatorAnimationSpeed(.standard, for: .spinners)) == [120_000_000])
    }

    @Test("A .dots spinner at twice the speed shows each frame for 55 ms")
    func doubleSpeed() {
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)) == [55_000_000])
    }

    @Test("A .dots spinner at 1.1 shows each frame for exactly 100 ms")
    func exactRate() {
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(1.1, for: .spinners)) == [100_000_000])
    }

    @Test("A .dots spinner at 1.05 ± 0.05 shows each frame for 100 ms, not 104.8 ms")
    func toleranceMovesOntoTheLattice() {
        let speed = IndicatorAnimationSpeed(1.05, tolerance: 0.05)
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(speed, for: .spinners)) == [100_000_000])
    }

    @Test("The nearest setting for spinners wins, and replaces the one above rather than multiplying it")
    func nearestWins() {
        // Inner `.all` at 2 inside outer `.spinners` at 0.5.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(0.5, for: .spinners))
                == [55_000_000])
        // Inner `.spinners` at 0.5 inside outer `.all` at 2.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(0.5, for: .spinners).indicatorAnimationSpeed(2))
                == [220_000_000])
        // 2 inside 2 is 2, not 4.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(2)) == [55_000_000])
        // A nearer setting for another kind leaves spinners at the one above.
        #expect(
            runNanos(
                Spinner(style: .dots).indicatorAnimationSpeed(2, for: .textCursor)
                    .indicatorAnimationSpeed(0.5, for: .spinners)) == [220_000_000])
    }

    @Test("A setting reaches only its own subtree, not a sibling")
    func siblingIsUnaffected() {
        let view = HStack(spacing: 1) {
            Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)
            Spinner(style: .dots)
        }
        #expect(runNanos(view).sorted() == [55_000_000, 110_000_000])
    }

    /// At three times the speed a `.custom` sequence steps every 40 ms, so at
    /// 1.037 s it shows its second frame and its next step is at 1.040 s. At the
    /// standard speed (120 ms) it would show the first frame until 1.080 s.
    @Test("A mixed-width spinner draws, and asks for its next render, at the speed it is set to")
    func fallbackFollowsTheSpeed() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FastMixedWidthSpinnerApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.nextFiring(after: now) == 1_040_000_000)
        let picture = (loop.replayable?.contentLines ?? []).map(\.stripped).joined()
        #expect(picture.contains("你"), "step 25 of a two-frame cycle is its second frame: \(picture.debugDescription)")
    }

    @Test("A change of speed alone reaches a spinner inside an .equatable() view")
    func speedChangeReachesAMemoizedSubtree() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let cache = RenderCache()
        environment.renderCache = cache
        environment.preferenceStorage = tuiContext.preferences
        let context = RenderContext(
            availableWidth: 20, availableHeight: 2, environment: environment,
            identity: ViewIdentity(path: "Root"))
        func frame(_ speed: IndicatorAnimationSpeed) -> [Int64] {
            cache.beginRenderPass()
            let buffer = renderToBuffer(
                MemoizedSpinner().equatable().indicatorAnimationSpeed(speed, for: .spinners), context: context)
            cache.removeInactive()
            return buffer.animatedCells.map { AnimationClock.nanoseconds($0.frameDuration) }
        }

        #expect(frame(1) == [110_000_000])
        let before = cache.stats
        #expect(frame(1) == [110_000_000])
        #expect(
            cache.stats.delta(since: before).hits >= 1,
            "the spinner was not served from the memo, so this is not the case under test")
        #expect(frame(2) == [55_000_000])
    }
}
