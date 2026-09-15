//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorAnimationSpeedTests.swift
//
//  `IndicatorAnimationSpeed` and the environment value and modifier that carry
//  it, checked through the indicators that read it so far: `Spinner` and an
//  indeterminate `ProgressView`.
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
    /// A standard of `ticks` ticks, in seconds.
    private static func standard(_ ticks: Int) -> Double {
        AnimationClock.seconds(forTicks: ticks)
    }

    /// A sequence's frame is its standard duration divided by the rate, as the
    /// nearest whole number of 1/60 s ticks, and at least one. Halves round up: 7
    /// ticks at 2 is 3.5, and 21 ticks at 2 is 10.5.
    @Test("At tolerance 0 a frame is the whole number of ticks nearest the standard divided by the rate")
    func exactIsTheNearestTick() {
        let cases: [(standard: Int, rate: Double, ticks: Int)] = [
            (7, 2, 4), (7, 1.1, 6), (7, 0.5, 14),
            (21, 2, 11), (21, 1.1, 19), (21, 0.5, 42),
            (7, 400, 1),
        ]
        for (standard, rate, ticks) in cases {
            #expect(
                IndicatorAnimationSpeed(rate).frameTicks(standard: Self.standard(standard)) == ticks,
                "\(standard) ticks at \(rate)")
        }
    }

    /// 7 ticks at 1 ± 0.2 accepts 5.83 to 8.75 ticks. Of 6 (a rate of 1.167) and 8
    /// (0.875), 8 is nearer in rate. 5 ticks at 1 ± 0.25 accepts 4 to 6.67, and 6
    /// (0.833) is nearer than 4 (1.25).
    @Test("Within a tolerance, in the rate's own units, a frame moves onto the nearest ticks divisible by 2 or 3")
    func toleranceMovesOntoTwosAndThrees() {
        #expect(IndicatorAnimationSpeed(1, tolerance: 0.2).frameTicks(standard: Self.standard(7)) == 8)
        #expect(IndicatorAnimationSpeed(1, tolerance: 0.25).frameTicks(standard: Self.standard(5)) == 6)
        // 7 ticks at 2 is 3.5, whose nearest, 4, is divisible by 2 already.
        #expect(IndicatorAnimationSpeed(2, tolerance: 0.1).frameTicks(standard: Self.standard(7)) == 4)
        // 7 ticks at 1.05 ± 0.05 accepts 6.36 to 7 ticks, which holds nothing divisible
        // by 2 or 3, so the frame is the nearest.
        #expect(IndicatorAnimationSpeed(1.05, tolerance: 0.05).frameTicks(standard: Self.standard(7)) == 7)
        // In the rate's units, not a fraction of it: 7 ticks at 1.4 is 5, and 1.4 ± 0.2
        // accepts 4.38 to 5.83 ticks, which holds nothing divisible by 2 or 3. As a
        // fraction of the rate (1.4 ± 0.28) it would reach 6 ticks, a rate of 1.167.
        #expect(IndicatorAnimationSpeed(1.4, tolerance: 0.2).frameTicks(standard: Self.standard(7)) == 5)
    }

    /// `.automatic` is 1 ± 0.05. A 5-tick frame accepts 4.76 to 5.26 ticks and a 7-tick
    /// one 6.67 to 7.37, which hold nothing divisible by 2 or 3, and the others already
    /// are divisible.
    @Test(".automatic moves no standard duration: every spinner interval and the blink half keep their ticks")
    func automaticMovesNoStandardDuration() {
        let styles: [SpinnerStyle] = [
            .dots, .line, .dancingLine, .bouncing, .pie, .beachball, .box, .curve, .column, .bar,
            .shade, .blockWedge, .spinningTriangle, .moon, .earth, .clock, .custom("ab"),
        ]
        for style in styles {
            #expect(
                IndicatorAnimationSpeed.automatic.frameTicks(standard: style.interval)
                    == AnimationClock.frameTicks(forSeconds: style.interval), "\(style)")
        }
        #expect(IndicatorAnimationSpeed.automatic.frameTicks(standard: CursorTimer.standardBlinkCycle / 2) == 21)
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

    /// A ramp is laid out in frames of its lattice, 2 ticks for a bar and 3 for a
    /// breath, as many as come nearest its pass, until that would be more than a
    /// thousand frames. Past that each frame is as many lattice frames as bring the
    /// count back to a thousand or fewer, so a very slow ramp costs no more to build
    /// than a thousand frames, and its pass is the nearest those frames allow. Before,
    /// an hour was 108,000 frames, and a rate of 1e-9 asked for `Int32.max` of them.
    @Test("A ramp is whole frames of its lattice, and past a thousand of them each frame is several")
    func rampIsWholeLatticeFrames() {
        let cases: [(standardCycle: Double, speed: IndicatorAnimationSpeed, lattice: Int, frames: Int, ticks: Int)] = [
            (1.73, 1, 2, 52, 2),
            (0.8, 1.5, 3, 11, 3),
            (20, 1, 2, 600, 2),
            (1000.0 / 30, 1, 2, 1000, 2),
            (40, 1, 2, 600, 4),
            (60, 1, 2, 900, 4),
            (3600, 1, 2, 1000, 216),
            (1.6, 0.001, 2, 1000, 96),
            (0.8, 0.0001, 3, 1000, 480),
        ]
        for (standardCycle, speed, lattice, frames, ticks) in cases {
            let layout = speed.rampLayout(standardCycle: standardCycle, frameTicks: lattice)
            let label = "\(standardCycle) s at \(speed.rate) on \(lattice) ticks"
            #expect(layout.frameCount == frames && layout.frameTicks == ticks, "\(label): \(layout)")
        }
        // No trap, however slow: a thousand frames of whole lattice frames.
        for rate in [1e-9, 1e-300] {
            let slowest = IndicatorAnimationSpeed(rate).rampLayout(standardCycle: 1.6, frameTicks: 2)
            #expect(slowest.frameCount >= 2 && slowest.frameCount <= 1000, "\(rate): \(slowest)")
            #expect(slowest.frameTicks >= 2 && slowest.frameTicks <= Int(Int32.max), "\(rate): \(slowest)")
        }
        #expect(IndicatorAnimationSpeed(1e-9).rampLayout(standardCycle: 1.6, frameTicks: 2).frameCount == 1000)
        // A tolerance is for sequences, and leaves a ramp's layout alone.
        #expect(
            IndicatorAnimationSpeed(0.001, tolerance: 0.0005).rampLayout(standardCycle: 1.6, frameTicks: 2)
                == IndicatorAnimationSpeed(0.001).rampLayout(standardCycle: 1.6, frameTicks: 2))
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
/// at three and a half times the speed.
private struct FastMixedWidthSpinnerApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Spinner(style: .custom("-你")).indicatorAnimationSpeed(3.5, for: .spinners)
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
    /// The frame length of every run `view` leaves, in ticks of 1/60 s, in order.
    private func runTicks(_ view: some View) -> [Int] {
        let context = RenderContext(availableWidth: 40, availableHeight: 4, tuiContext: TUIContext())
            .isolatingRenderCache()
        return renderToBuffer(view, context: context).animatedCells.map(\.frameTicks)
    }

    /// `.automatic` is 1 ± 0.05, so 7 ticks accepts 6.67 to 7.37 ticks, which holds
    /// nothing divisible by 2 or 3.
    @Test("Unset, a .dots spinner shows each frame for its style's 7 ticks, 116,666,667 ns")
    func unsetIsTheStyleInterval() {
        #expect(runTicks(Spinner(style: .dots)) == [7])
    }

    /// `.pie` was 120 ms, which `.automatic` moved to 125 ms. It is 7 ticks now, which
    /// `.automatic` leaves alone, as it leaves every standard interval.
    @Test("Unset, a .pie spinner is its style's 116,666,667 ns at .automatic and at .standard")
    func automaticMovesNoStandardInterval() {
        #expect(IndicatorAnimationSpeed.automatic == IndicatorAnimationSpeed(1, tolerance: 0.05))
        #expect(runTicks(Spinner(style: .pie)) == [7])
        #expect(runTicks(Spinner(style: .pie).indicatorAnimationSpeed(.standard, for: .spinners)) == [7])
    }

    /// 7 ticks at twice the speed are 3.5, and a half rounds up.
    @Test("A .dots spinner at twice the speed shows each frame for 4 ticks, 66,666,667 ns")
    func doubleSpeed() {
        #expect(runTicks(Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)) == [4])
    }

    /// 7 ticks at 1.1 are 6.36. It was exactly 106,060,606 ns, which no display can hold.
    @Test("A .dots spinner at 1.1 shows each frame for the nearest whole ticks to its interval divided by 1.1, 6")
    func exactRate() {
        #expect(runTicks(Spinner(style: .dots).indicatorAnimationSpeed(1.1, for: .spinners)) == [6])
    }

    /// 1.05 ± 0.05 on 7 ticks accepts 6.36 to 7 ticks, which holds nothing divisible by
    /// 2 or 3, so the frame is the nearest. It was exactly 111,111,111 ns.
    @Test("A .dots spinner at 1.05 ± 0.05 with nothing divisible by 2 or 3 in reach shows the nearest ticks, 7")
    func toleranceWithNothingInReachIsTheNearest() {
        let speed = IndicatorAnimationSpeed(1.05, tolerance: 0.05)
        #expect(runTicks(Spinner(style: .dots).indicatorAnimationSpeed(speed, for: .spinners)) == [7])
    }

    /// 1 ± 0.2 on 7 ticks accepts 5.83 to 8.75 ticks, and 8 (a rate of 0.875) is nearer
    /// than 6 (1.167). On 25 ms base ticks it was 125 ms.
    @Test("A .dots spinner at 1 ± 0.2 shows each frame for 8 ticks, 133,333,333 ns")
    func toleranceMovesOntoTwosAndThrees() {
        let speed = IndicatorAnimationSpeed(1, tolerance: 0.2)
        #expect(runTicks(Spinner(style: .dots).indicatorAnimationSpeed(speed, for: .spinners)) == [8])
    }

    @Test("The nearest setting for spinners wins, and replaces the one above rather than multiplying it")
    func nearestWins() {
        // Inner `.all` at 2 inside outer `.spinners` at 0.5.
        #expect(
            runTicks(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(0.5, for: .spinners))
                == [4])
        // Inner `.spinners` at 0.5 inside outer `.all` at 2.
        #expect(
            runTicks(Spinner(style: .dots).indicatorAnimationSpeed(0.5, for: .spinners).indicatorAnimationSpeed(2))
                == [14])
        // 2 inside 2 is 2, not 4.
        #expect(
            runTicks(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(2)) == [4])
        // A nearer setting for another kind leaves spinners at the one above.
        #expect(
            runTicks(
                Spinner(style: .dots).indicatorAnimationSpeed(2, for: .textCursor)
                    .indicatorAnimationSpeed(0.5, for: .spinners)) == [14])
    }

    @Test("A setting reaches only its own subtree, not a sibling")
    func siblingIsUnaffected() {
        let view = HStack(spacing: 1) {
            Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)
            Spinner(style: .dots)
        }
        #expect(runTicks(view).sorted() == [4, 7])
    }

    /// At three and a half times the speed a `.custom` sequence's 7 ticks are 2, so at
    /// 1.037 s, tick 62, it is on step 31, its second frame, and its next step begins
    /// with tick 64. At the standard speed it would be on step 8, the first frame, until
    /// 1.05 s.
    @Test("A mixed-width spinner draws, and asks for its next render, at the speed it is set to")
    func fallbackFollowsTheSpeed() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FastMixedWidthSpinnerApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.nextFiring(after: now) == 1_066_666_667, "when tick 64 begins")
        let picture = (loop.replayable?.contentLines ?? []).map(\.stripped).joined()
        #expect(picture.contains("你"), "step 31 of a two-frame cycle is its second frame: \(picture.debugDescription)")
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
        func frame(_ speed: IndicatorAnimationSpeed) -> [Int] {
            cache.beginRenderPass()
            let buffer = renderToBuffer(
                MemoizedSpinner().equatable().indicatorAnimationSpeed(speed, for: .spinners), context: context)
            cache.removeInactive()
            return buffer.animatedCells.map(\.frameTicks)
        }

        #expect(frame(1) == [7])
        let before = cache.stats
        #expect(frame(1) == [7])
        #expect(
            cache.stats.delta(since: before).hits >= 1,
            "the spinner was not served from the memo, so this is not the case under test")
        #expect(frame(2) == [4])
    }
}

// MARK: - Indeterminate bars

/// A translucent `.sweep` bar, which no run can carry, at the standard speed.
private struct StandardTranslucentSweepApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ProgressView().indeterminateStyle(.sweep).tint(Color.red.opacity(0.5))
                .indicatorAnimationSpeed(.standard, for: .indeterminateProgress)
        }
    }
}

/// The same bar at twice the speed.
private struct DoubleSpeedTranslucentSweepApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ProgressView().indeterminateStyle(.sweep).tint(Color.red.opacity(0.5))
                .indicatorAnimationSpeed(2, for: .indeterminateProgress)
        }
    }
}

/// The same bar at 1.1 times the speed.
private struct QuickTranslucentSweepApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ProgressView().indeterminateStyle(.sweep).tint(Color.red.opacity(0.5))
                .indicatorAnimationSpeed(1.1, for: .indeterminateProgress)
        }
    }
}

/// A translucent `.sweep` bar whose pass the app set to an hour.
private struct HourLongTranslucentSweepApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ProgressView().indeterminateStyle(.custom(IndeterminateConfiguration(motion: .sweep, period: 3600)))
                .tint(Color.red.opacity(0.5))
        }
    }
}

@MainActor
@Suite("Indicator animation speed on indeterminate bars")
struct IndicatorAnimationSpeedBarTests {
    private static func freshContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
    }

    /// `view` as a one-line bar 20 cells wide, drawn as pictures where `pictures`
    /// says the terminal can, keeping its state in `tui`.
    private func bar(_ view: some View, pictures: Bool = false, tui: TUIContext? = nil) -> FrameBuffer {
        let tui = tui ?? Self.freshContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 16, height: 34)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 1, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        guard pictures else { return renderToBuffer(view, context: context) }
        return KittyGraphics.withSupport(true) { renderToBuffer(view, context: context) }
    }

    private func placeholders(_ buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { $0 + $1.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count }
    }

    /// 1.6 s at twice the speed is 0.8 s, still in frames of 2 ticks: 24 of them.
    @Test("A .sweep bar at twice the speed passes in 0.8 s, at the same frame rate")
    func sweepAtDoubleSpeed() throws {
        let standard = try #require(bar(ProgressView().indeterminateStyle(.sweep)).animatedCells.first)
        let doubled = try #require(
            bar(ProgressView().indeterminateStyle(.sweep).indicatorAnimationSpeed(2, for: .indeterminateProgress))
                .animatedCells.first)
        #expect(standard.cycleTicks == 96)
        #expect(doubled.cycleTicks == 48)
        #expect(doubled.frames.count == 24)
        #expect(doubled.frameTicks == standard.frameTicks)
    }

    /// `.gradient()`'s 2.4 s at twice the speed is 1.2 s, 36 frames, whichever path
    /// draws it.
    @Test("A .gradient bar at twice the speed passes in 1.2 s as pictures and as glyphs")
    func gradientAtDoubleSpeedOnBothPaths() throws {
        let view = ProgressView().indeterminateStyle(.gradient())
            .indicatorAnimationSpeed(2, for: .indeterminateProgress)
        let pictures = bar(view, pictures: true)
        let glyphs = bar(view)
        #expect(placeholders(pictures) == 20, "the picture path was not taken")
        #expect(placeholders(glyphs) == 0, "the glyph path drew pictures")
        for buffer in [pictures, glyphs] {
            let run = try #require(buffer.animatedCells.first)
            #expect(run.cycleTicks == 72)
            #expect(run.frames.count == 36)
        }
    }

    /// 1.6 s at 1.02 is 1.5686 s, 94.1 ticks, which is 47 frames of 2 ticks. The
    /// tolerance is for sequences and moves nothing here, and a preset's pass and the
    /// same pass set by the app are laid out alike. The app's used to stay exact, in
    /// frames of 33,375,052 ns.
    @Test("A preset's pass and the same pass set by the app are both 47 frames of 2 ticks at 1.02 ± 0.05")
    func presetAndCustomPassAreLaidOutAlike() throws {
        let speed = IndicatorAnimationSpeed(1.02, tolerance: 0.05)
        let preset = try #require(
            bar(ProgressView().indeterminateStyle(.sweep).indicatorAnimationSpeed(speed, for: .indeterminateProgress))
                .animatedCells.first)
        let custom = try #require(
            bar(
                ProgressView().indeterminateStyle(.custom(.sweep))
                    .indicatorAnimationSpeed(speed, for: .indeterminateProgress)
            ).animatedCells.first)
        #expect(preset.frames.count == 47)
        #expect(custom.frames.count == 47)
        #expect(preset.frameTicks == 2)
        #expect(custom.frameTicks == 2)
    }

    /// 1.73 s is 103.8 ticks, which is 51.9 frames of 2 ticks and rounds to 52: a pass
    /// of 1.7333 s. It used to be exactly 1.73 s, in frames of 33,269,231 ns.
    @Test("A period the app sets is the nearest whole number of 2-tick frames: 1.73 s is 52 of them")
    func customPeriodIsWholeFrames() throws {
        let run = try #require(
            bar(ProgressView().indeterminateStyle(.custom(IndeterminateConfiguration(motion: .sweep, period: 1.73))))
                .animatedCells.first)
        #expect(run.frames.count == 52)
        #expect(run.frameTicks == 2)
    }

    /// 1.6 s at 1.1 is 1.4545 s, 87.3 ticks, which is 43.6 frames of 2 ticks and rounds
    /// to 44. A frame is 2 ticks at any speed, so at 1.037 s, tick 62, it is step 31,
    /// which ends when tick 64 begins, at 1,066,666,667 ns. It used to be 44 frames of
    /// 33,057,851 ns, ending at 1,057,851,232 ns.
    @Test("A translucent bar asks for its next render at the end of its 2-tick frame, at any speed")
    func fallbackWakesAtTheSpeedsFrame() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(QuickTranslucentSweepApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.liveCount == 0, "a grid was registered for the declined run")
        #expect(scheduler.nextFiring(after: now) == 1_066_666_667)
    }

    /// A declined bar draws one frame per render, at an instant rather than from its
    /// frames, so it has to draw in the motion's own time as the run's frames are
    /// sampled: at twice the speed, 1.2 s in is what the standard bar shows 2.4 s in.
    @Test("A translucent bar at twice the speed draws at twice the elapsed time")
    func fallbackDrawsInTheMotionsTime() {
        func picture<A: App>(_ app: A, at now: Int64) -> [String] {
            let harness = RenderLoopHarness()
            let loop = harness.loop(app)
            let scheduler = AnimationScheduler()
            scheduler.beginFrame()
            loop.render(animationScheduler: scheduler, frameNowNanos: now)
            scheduler.endFrame()
            return loop.replayable?.contentLines ?? []
        }
        let doubled = picture(DoubleSpeedTranslucentSweepApp(), at: 1_200_000_000)
        #expect(doubled == picture(StandardTranslucentSweepApp(), at: 2_400_000_000))
        #expect(
            doubled != picture(StandardTranslucentSweepApp(), at: 1_200_000_000),
            "the standard bar draws the same at 1.2 s and 2.4 s, so this shows nothing")
    }

    /// A bar builds its cycle once and keeps it in state, keyed on what its frames
    /// depend on. A speed change alone has to rebuild it.
    @Test("A change of speed alone rebuilds a bar's kept cycle")
    func speedChangeRebuildsTheCycle() throws {
        let tui = Self.freshContext()
        func cycleTicks(_ speed: IndicatorAnimationSpeed) throws -> Int64 {
            let run = try #require(
                bar(
                    ProgressView().indeterminateStyle(.sweep)
                        .indicatorAnimationSpeed(speed, for: .indeterminateProgress),
                    tui: tui
                ).animatedCells.first)
            return run.cycleTicks
        }
        #expect(try cycleTicks(1) == 96)
        #expect(try cycleTicks(2) == 48)
    }

    /// Each frame of a picture bar is an image in the terminal under its own token. The
    /// bar's disappear handler is replaced at every render and knows only the newest
    /// frame count, so a rebuild with fewer frames has to give back the tokens past it
    /// itself: nothing else ever will.
    @Test("A picture bar rebuilt with fewer frames gives the terminal back the pictures it no longer names")
    func rebuildWithFewerPicturesReleasesTheRest() throws {
        let tui = Self.freshContext()
        func frameCount(_ speed: IndicatorAnimationSpeed) throws -> Int {
            let buffer = bar(
                ProgressView().indeterminateStyle(.gradient())
                    .indicatorAnimationSpeed(speed, for: .indeterminateProgress),
                pictures: true, tui: tui)
            #expect(placeholders(buffer) == 20, "the picture path was not taken")
            return try #require(buffer.animatedCells.first).frames.count
        }
        #expect(try frameCount(1) == 72)
        #expect(tui.terminalImageStore.imageCount == 72)
        #expect(try frameCount(2) == 36)
        #expect(tui.terminalImageStore.imageCount == 36)
    }

    /// A 2-cell picture bar at a 16×34-pixel cell is 16 pixels wide, so its ramp slides
    /// through 16 whole-pixel shifts, and its pass of 72 frames shows each of them four
    /// or five times. Each distinct picture is sent once, and every frame showing it
    /// names it. The bar used to send a picture for every frame, 72 of them, 56 of
    /// them the same as another.
    @Test("A 2-cell picture bar holds one picture for each of its 16 shifts, not one for each of its 72 frames")
    func narrowPictureBarHoldsEachShiftOnce() throws {
        let tui = Self.freshContext()
        let buffer = bar(
            ProgressView().indeterminateStyle(.gradient()).frame(width: 2), pictures: true, tui: tui)
        #expect(placeholders(buffer) == 2, "the picture path was not taken")
        let run = try #require(buffer.animatedCells.first)
        #expect(run.frames.count == 72)
        #expect(Set(run.frames).count == 16)
        #expect(tui.terminalImageStore.imageCount == 16)
    }

    /// In frames of 2 ticks an hour is 108,000 frames, every one built at the first
    /// render and held for as long as the bar is on screen. A thousand frames of 216
    /// ticks (3.6 s) is exactly an hour.
    @Test("An hour-long pass is a thousand frames of 216 ticks, 3.6 s, and lasts exactly an hour")
    func hourLongPassIsBounded() throws {
        let run = try #require(
            bar(ProgressView().indeterminateStyle(.custom(IndeterminateConfiguration(motion: .sweep, period: 3600))))
                .animatedCells.first)
        #expect(run.frames.count == 1000)
        #expect(run.frameTicks == 216)
        #expect(run.cycleTicks == 216_000)
        // Sampled across the whole hour, not its first 33 s: the head of a 20-cell
        // sweep stands on every column.
        #expect(Set(run.frames).count == 20)
    }

    /// As pictures, each frame is also an image sent to the terminal: 1,800 of them
    /// for a minute in frames of 2 ticks. Past a thousand, a frame is whole 2-tick
    /// frames, as few as bring the count to a thousand or fewer: 4 ticks, 900 frames. It
    /// used to be a thousand frames of 60 ms, which is not a whole number of ticks.
    @Test("A minute-long .gradient pass is 900 frames of 4 ticks as pictures and as glyphs")
    func minuteLongGradientIsBoundedOnBothPaths() throws {
        let view = ProgressView().indeterminateStyle(
            .custom(IndeterminateConfiguration(motion: .gradient, period: 60)))
        let pictures = bar(view, pictures: true)
        let glyphs = bar(view)
        #expect(placeholders(pictures) == 20, "the picture path was not taken")
        #expect(placeholders(glyphs) == 0, "the glyph path drew pictures")
        for buffer in [pictures, glyphs] {
            let run = try #require(buffer.animatedCells.first)
            #expect(run.frames.count == 900)
            #expect(run.frameTicks == 4)
            #expect(run.cycleTicks == 3_600)
        }
    }

    /// A declined bar wakes at the frames its pass is laid out in, so an hour-long
    /// bar asks for a render every 3.6 s, as its run would change, not every 1/30 s.
    @Test("A translucent hour-long bar asks for its next render at the end of its 3.6 s frame")
    func hourLongFallbackWakesAtItsFrame() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(HourLongTranslucentSweepApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.liveCount == 0, "a grid was registered for the declined run")
        #expect(scheduler.nextFiring(after: now) == 3_600_000_000)
    }
}
