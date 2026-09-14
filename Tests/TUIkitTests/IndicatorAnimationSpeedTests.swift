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

    /// A ramp is sampled at its frame rate until that would be more than a thousand
    /// frames. A longer cycle keeps a thousand, each longer, so it costs no more to
    /// build than a 33 s bar and still lasts exactly as long. Before, an hour was
    /// 108,000 frames, and a rate of 1e-9 asked for `Int32.max` of them.
    @Test("A ramp longer than a thousand frames is sampled at a thousand, and its cycle stays exact")
    func rampFrameCountIsBounded() {
        let cases: [(standardCycle: Double, speed: IndicatorAnimationSpeed, framesPerSecond: Double, frames: Int)] = [
            (20, 1, 30, 600),
            (1000.0 / 30, 1, 30, 1000),
            (40, 1, 30, 1000),
            (3600, 1, 30, 1000),
            (1.6, 0.001, 30, 1000),
            (0.8, 0.0001, 20, 1000),
            (1.6, IndicatorAnimationSpeed(1e-9), 30, 1000),
        ]
        for (standardCycle, speed, framesPerSecond, frames) in cases {
            for snapping in [false, true] {
                let layout = speed.rampLayout(
                    standardCycle: standardCycle, framesPerSecond: framesPerSecond, snapping: snapping)
                let label = "\(standardCycle) s at \(speed.rate), \(framesPerSecond) fps, snapping \(snapping)"
                #expect(layout.frameCount == frames, "\(label)")
                #expect(
                    AnimationClock.nanoseconds(Double(layout.frameCount) * layout.frameDuration)
                        == AnimationClock.nanoseconds(standardCycle / speed.rate), "\(label)")
            }
        }
        // A tolerance cannot lift the bound: 1,600 s at 0.001 ± 0.0005 has no whole
        // number of 1/30 s frames in its band that a thousand frames reach.
        let tolerant = IndicatorAnimationSpeed(0.001, tolerance: 0.0005)
            .rampLayout(standardCycle: 1.6, framesPerSecond: 30, snapping: true)
        #expect(tolerant.frameCount == 1000)
        #expect(AnimationClock.nanoseconds(tolerant.frameDuration) == 1_600_000_000)
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
    /// The frame duration of every run `view` leaves, in nanoseconds, in order.
    private func runNanos(_ view: some View) -> [Int64] {
        let context = RenderContext(availableWidth: 40, availableHeight: 4, tuiContext: TUIContext())
            .isolatingRenderCache()
        return renderToBuffer(view, context: context).animatedCells.map {
            AnimationClock.nanoseconds($0.frameDuration)
        }
    }

    /// `.automatic` is 1 ± 0.05, so 7 ticks (116.7 ms) accepts 111.1 ms to 122.8 ms,
    /// which holds no whole number of 25 ms base ticks.
    @Test("Unset, a .dots spinner shows each frame for its style's 7 ticks, 116,666,667 ns")
    func unsetIsTheStyleInterval() {
        #expect(runNanos(Spinner(style: .dots)) == [116_666_667])
    }

    /// `.pie` was 120 ms, which `.automatic` moved to 125 ms. It is 7 ticks now, which
    /// `.automatic` leaves alone, as it leaves every standard interval.
    @Test("Unset, a .pie spinner is its style's 116,666,667 ns at .automatic and at .standard")
    func automaticMovesNoStandardInterval() {
        #expect(IndicatorAnimationSpeed.automatic == IndicatorAnimationSpeed(1, tolerance: 0.05))
        #expect(runNanos(Spinner(style: .pie)) == [116_666_667])
        #expect(runNanos(Spinner(style: .pie).indicatorAnimationSpeed(.standard, for: .spinners)) == [116_666_667])
    }

    @Test("A .dots spinner at twice the speed shows each frame for 58,333,333 ns")
    func doubleSpeed() {
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)) == [58_333_333])
    }

    @Test("A .dots spinner at 1.1 shows each frame for exactly its interval divided by 1.1")
    func exactRate() {
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(1.1, for: .spinners)) == [106_060_606])
    }

    /// 1.05 ± 0.05 on 7 ticks accepts 106.1 ms to 116.7 ms, which holds no whole number
    /// of 25 ms base ticks, so the duration is the exact one.
    @Test("A .dots spinner at 1.05 ± 0.05 with no base tick in reach shows each frame for exactly 111,111,111 ns")
    func toleranceWithNothingInReachIsExact() {
        let speed = IndicatorAnimationSpeed(1.05, tolerance: 0.05)
        #expect(runNanos(Spinner(style: .dots).indicatorAnimationSpeed(speed, for: .spinners)) == [111_111_111])
    }

    @Test("The nearest setting for spinners wins, and replaces the one above rather than multiplying it")
    func nearestWins() {
        // Inner `.all` at 2 inside outer `.spinners` at 0.5.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(0.5, for: .spinners))
                == [58_333_333])
        // Inner `.spinners` at 0.5 inside outer `.all` at 2.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(0.5, for: .spinners).indicatorAnimationSpeed(2))
                == [233_333_333])
        // 2 inside 2 is 2, not 4.
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2).indicatorAnimationSpeed(2)) == [58_333_333])
        // A nearer setting for another kind leaves spinners at the one above.
        #expect(
            runNanos(
                Spinner(style: .dots).indicatorAnimationSpeed(2, for: .textCursor)
                    .indicatorAnimationSpeed(0.5, for: .spinners)) == [233_333_333])
    }

    @Test("A setting reaches only its own subtree, not a sibling")
    func siblingIsUnaffected() {
        let view = HStack(spacing: 1) {
            Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners)
            Spinner(style: .dots)
        }
        #expect(runNanos(view).sorted() == [58_333_333, 116_666_667])
    }

    /// At three and a half times the speed a `.custom` sequence's 7 ticks are 2, a
    /// frame of 33,333,333 ns, so at 1.037 s it is on step 31, its second frame, and
    /// its next step is 32 frames in. At the standard speed it would be on step 8, the
    /// first frame, until 1.05 s.
    @Test("A mixed-width spinner draws, and asks for its next render, at the speed it is set to")
    func fallbackFollowsTheSpeed() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FastMixedWidthSpinnerApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.nextFiring(after: now) == 1_066_666_656, "32 frames of 33,333,333 ns")
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
        func frame(_ speed: IndicatorAnimationSpeed) -> [Int64] {
            cache.beginRenderPass()
            let buffer = renderToBuffer(
                MemoizedSpinner().equatable().indicatorAnimationSpeed(speed, for: .spinners), context: context)
            cache.removeInactive()
            return buffer.animatedCells.map { AnimationClock.nanoseconds($0.frameDuration) }
        }

        #expect(frame(1) == [116_666_667])
        let before = cache.stats
        #expect(frame(1) == [116_666_667])
        #expect(
            cache.stats.delta(since: before).hits >= 1,
            "the spinner was not served from the memo, so this is not the case under test")
        #expect(frame(2) == [58_333_333])
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

    /// 1.6 s at twice the speed is 0.8 s, still sampled at 30 frames a second: 24
    /// frames of 1/30 s.
    @Test("A .sweep bar at twice the speed passes in 0.8 s, at the same frame rate")
    func sweepAtDoubleSpeed() throws {
        let standard = try #require(bar(ProgressView().indeterminateStyle(.sweep)).animatedCells.first)
        let doubled = try #require(
            bar(ProgressView().indeterminateStyle(.sweep).indicatorAnimationSpeed(2, for: .indeterminateProgress))
                .animatedCells.first)
        #expect(AnimationClock.nanoseconds(standard.cycleDuration) == 1_600_000_000)
        #expect(AnimationClock.nanoseconds(doubled.cycleDuration) == 800_000_000)
        #expect(doubled.frames.count == 24)
        #expect(
            AnimationClock.nanoseconds(doubled.frameDuration) == AnimationClock.nanoseconds(standard.frameDuration))
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
            #expect(AnimationClock.nanoseconds(run.cycleDuration) == 1_200_000_000)
            #expect(run.frames.count == 36)
        }
    }

    /// 1.6 s at 1.02 is 1.5686 s, which samples to 47 frames. 47 whole frames of
    /// 1/30 s is 1.5667 s, a rate of 1.0213, inside 1.02 ± 0.05. The preset's pass
    /// moves onto them; the same configuration set by the app does not.
    @Test("Within a tolerance a preset's pass moves onto whole frames, and the same pass set by the app stays exact")
    func toleranceMovesOnlyAPresetsPass() throws {
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
        #expect(AnimationClock.nanoseconds(preset.frameDuration) == AnimationClock.nanoseconds(1.0 / 30))
        #expect(AnimationClock.nanoseconds(custom.frameDuration) == AnimationClock.nanoseconds(1.6 / 1.02 / 47))
    }

    /// `.automatic` is 1 ± 0.05. 1.73 s samples to 52 frames, and 52 whole frames of
    /// 1/30 s is 1.7333 s, a rate of 0.998, well inside it: a preset's pass would move.
    @Test("A period the app sets passes in exactly that time at the default speed")
    func customPeriodStaysExact() throws {
        let run = try #require(
            bar(ProgressView().indeterminateStyle(.custom(IndeterminateConfiguration(motion: .sweep, period: 1.73))))
                .animatedCells.first)
        #expect(run.frames.count == 52)
        #expect(AnimationClock.nanoseconds(run.frameDuration) == AnimationClock.nanoseconds(1.73 / 52))
    }

    /// 1.6 s at 1.1 is 1.4545 s: 44 frames of 33,057,851 ns. At 1.037 s that is frame
    /// 31, which ends at 1,057,851,232 ns. At the standard speed the frame would end
    /// at 1,066,666,656 ns.
    @Test("A translucent bar asks for its next render at the frame its speed lays out")
    func fallbackWakesAtTheSpeedsFrame() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(QuickTranslucentSweepApp())
        let scheduler = AnimationScheduler()
        let now: Int64 = 1_037_000_000
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: now)
        scheduler.endFrame()
        #expect(scheduler.liveCount == 0, "a grid was registered for the declined run")
        #expect(scheduler.nextFiring(after: now) == 1_057_851_232)
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
        func cycleNanos(_ speed: IndicatorAnimationSpeed) throws -> Int64 {
            let run = try #require(
                bar(
                    ProgressView().indeterminateStyle(.sweep)
                        .indicatorAnimationSpeed(speed, for: .indeterminateProgress),
                    tui: tui
                ).animatedCells.first)
            return AnimationClock.nanoseconds(run.cycleDuration)
        }
        #expect(try cycleNanos(1) == 1_600_000_000)
        #expect(try cycleNanos(2) == 800_000_000)
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

    /// At 30 frames a second an hour is 108,000 frames, every one built at the first
    /// render and held for as long as the bar is on screen.
    @Test("An hour-long pass is a thousand frames of 3.6 s, and lasts exactly an hour")
    func hourLongPassIsBounded() throws {
        let run = try #require(
            bar(ProgressView().indeterminateStyle(.custom(IndeterminateConfiguration(motion: .sweep, period: 3600))))
                .animatedCells.first)
        #expect(run.frames.count == 1000)
        #expect(AnimationClock.nanoseconds(run.frameDuration) == 3_600_000_000)
        #expect(AnimationClock.nanoseconds(run.cycleDuration) == 3_600_000_000_000)
        // Sampled across the whole hour, not its first 33 s: the head of a 20-cell
        // sweep stands on every column.
        #expect(Set(run.frames).count == 20)
    }

    /// As pictures, each frame is also an image sent to the terminal: 1,800 of them
    /// for a minute at 30 frames a second.
    @Test("A minute-long .gradient pass is a thousand frames of 60 ms as pictures and as glyphs")
    func minuteLongGradientIsBoundedOnBothPaths() throws {
        let view = ProgressView().indeterminateStyle(
            .custom(IndeterminateConfiguration(motion: .gradient, period: 60)))
        let pictures = bar(view, pictures: true)
        let glyphs = bar(view)
        #expect(placeholders(pictures) == 20, "the picture path was not taken")
        #expect(placeholders(glyphs) == 0, "the glyph path drew pictures")
        for buffer in [pictures, glyphs] {
            let run = try #require(buffer.animatedCells.first)
            #expect(run.frames.count == 1000)
            #expect(AnimationClock.nanoseconds(run.frameDuration) == 60_000_000)
            #expect(AnimationClock.nanoseconds(run.cycleDuration) == 60_000_000_000)
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
