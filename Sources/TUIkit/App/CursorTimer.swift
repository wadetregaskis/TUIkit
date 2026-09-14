//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// The app's one animation TIMER, and the two clocks it serves: the
/// focus-relative one the cursor's blink and every focus indicator's breath
/// read, and the monotonic one a spinner's or an indeterminate bar's run replays
/// on. A view draws its own frame from the frame clock, `frameNowNanos`, which
/// every render shows this timer before anything reads it, so the frame a view
/// draws and the frame a replay splices are one instant (§74 of
/// `Opacity as composition.md`).
///
/// **Both clocks are measured, not counted.** ``AnimationClock/content`` is
/// ``MonotonicClock`` itself, with no origin of its own, and
/// ``AnimationClock/cursor`` is the same reading less the moment the focus last
/// moved, floored to the 50 ms tick lattice. The timer keeps one snapshot of
/// that clock, taken whenever a frame renders (``observe(nowNanos:)``) or the
/// timer wakes (``creditWake(atNanos:)``), so every read inside one frame agrees.
///
/// It used to count instead: each wake added the sleep it had ASKED for. A wake
/// is late — a `Task.sleep` resumed on the main actor overshoots by a median of
/// 6–13 ms, whatever its length — and the lateness was never credited, so the
/// clock ran slow by `1 + N·L` for `N` wakes a simulated second. The Spinners
/// page wakes about 52 times a simulated second, and every spinner on it ran at
/// about two thirds of its speed, all by the same factor.
///
/// `CursorTimer` maintains two phase values for different animation styles:
/// - `blinkVisible`: Boolean for sharp on/off blinking
/// - `pulsePhase`: Smooth 0-1 cosine wave for pulsing, starting bright
///
/// There used to be a second clock — a `PulseTimer` for focus indicators — and
/// having two was a bug rather than a feature: they ran at different rates from
/// different formulas, so the same focus pulse breathed at 2 s on a section's
/// border and 0.8 s on the controls inside it, depending only on which route
/// the view took. One clock and one formula now serve both, with the animation
/// chosen per element by ``View/selectionIndicatorStyle(_:)`` and its speed by
/// ``View/indicatorAnimationSpeed(_:for:)``.
///
/// The timer is a single `@MainActor` `Task` that sleeps between ticks (the
/// same pattern as ``AutoRepeatTimer``). Staying on the main actor means the
/// snapshot is never mutated off-thread, so the phases read during render
/// are race-free.
///
/// ## Animation Speeds
///
/// A blink is two frames, visible then hidden, each shown for half the cycle. A
/// pulse is a cosine sampled once per 50 ms tick. See ``cycleLayout(of:speed:)``.
///
/// The caret and the focus emphasis each run at an ``IndicatorAnimationSpeed``,
/// the one set for ``IndicatorAnimations/textCursor`` or
/// ``IndicatorAnimations/focusEmphasis``: a 700 ms blink (``standardBlinkCycle``)
/// and an 800 ms pulse (``standardPulseCycle``) at the standard rate, each divided
/// by the rate.
///
/// ## Usage
///
/// ```swift
/// let cursor = CursorTimer(renderNotifier: appState)
/// cursor.start()
/// // In render code:
/// if cursor.blinkVisible(for: .automatic) {
///     // show cursor
/// }
/// let phase = cursor.pulsePhase(for: .automatic)
/// ```
@MainActor
final class CursorTimer {
    /// How often a view that reads the phase AS IT RENDERS is re-rendered.
    /// Taken from ``AnimationClock/tickInterval`` rather than written here so
    /// there is one number, not two that can disagree.
    private static let tickInterval = AnimationClock.cursor.tickInterval

    /// The same, in whole nanoseconds — the lattice the focus epoch is floored to.
    private static let tickNanos = UInt64(AnimationClock.nanoseconds(AnimationClock.cursor.tickInterval))

    /// Where a wake reads the time. The clock `FrameClock` reads too, which is
    /// what makes a wake's reading and a frame's comparable at all; injectable
    /// so a test can step it, as `MouseEventDispatcher.nowNanos` is.
    var nowNanos: () -> UInt64 = { MonotonicClock.nowNanoseconds }

    /// The latest instant this timer has been shown, in nanoseconds on
    /// ``MonotonicClock``: the source of truth for both clocks.
    ///
    /// Only ever raised, so a reading older than one already seen (a wake queued
    /// behind a render that stamped a later frame) cannot run the phases back.
    private(set) var snapshotNanos: UInt64 = 0

    /// Where ``AnimationClock/cursor``'s zero sits, on the tick lattice, or `nil`
    /// until the next ``observe(nowNanos:)`` sets it.
    ///
    /// Cleared whenever the focus moves, which is how the blink and the focus
    /// breath restart at their bright end without disturbing anything else. The
    /// clear used to zero the one elapsed time every animation in the app read:
    /// pressing Tab restarted every indeterminate progress bar, every spinner and
    /// every breathing label along with the cursor.
    ///
    /// Set lazily, at the frame after the change, not at the change. See
    /// ``restartFocusPhase()`` for what setting it early did. Floored to the
    /// lattice so a caret's and a breath's changes land on the same 50 ms grid as
    /// every other 50 ms run on the page, and the wakes coalesce — at the price of
    /// a first half that can be up to one tick short: 300–350 ms of a 350 ms blink.
    private var focusEpochNanos: UInt64?

    /// Shows the timer the time: a frame's `frameNow`, before anything in that
    /// frame reads a phase, or a wake's own reading.
    ///
    /// **One instant per frame, by convention rather than by construction.** A
    /// render observes the time it stamps on the frame, so a same-width spinner
    /// reading ``elapsed(for:)`` and a declined one reading `frameNowNanos` draw
    /// the same step. That holds because every reading comes from
    /// ``MonotonicClock`` — `FrameClock.nowNanos` and ``nowNanos`` both read it —
    /// and because the snapshot only rises: a caller that passes a frame time
    /// EARLIER than one the timer has already seen (a test, stamping its own
    /// frames) keeps the later snapshot, and the two then differ.
    func observe(nowNanos now: UInt64) {
        snapshotNanos = max(snapshotNanos, now)
        if focusEpochNanos == nil {
            focusEpochNanos = snapshotNanos - snapshotNanos % Self.tickNanos
        }
    }

    /// How far `clock` has run, at the last snapshot.
    ///
    /// The two clocks share one snapshot and differ only in where their zero is —
    /// see ``AnimationClock``. `.content` has no zero of its own: it is the
    /// monotonic reading, so every run on it is in phase with every other, and a
    /// spinner that appears starts where the shared clock is rather than at its
    /// first frame.
    ///
    /// In seconds, from whole nanoseconds. A `Double` holds those exactly for about
    /// 48 days of uptime (2^22 s); past that, a nanosecond here and there can be
    /// lost, but a render and a replay index the same `Double` and agree.
    func elapsed(for clock: AnimationClock) -> Double {
        switch clock {
        case .content: Double(snapshotNanos) / 1_000_000_000
        case .cursor: focusEpochNanos.map { Double(snapshotNanos - $0) / 1_000_000_000 } ?? 0
        }
    }

    /// Elapsed ticks, for the phase formulas that are still defined on a grid.
    ///
    /// Derived rather than counted, so a variable sleep keeps every phase's
    /// wall-clock meaning: a breath is a breath whether the loop woke six times
    /// or sixty on the way through it.
    ///
    /// Focus-relative: every formula that reads this is a
    /// ``AnimationClock/cursor`` one.
    var elapsedTicks: Int { ticks(for: .cursor) }

    /// ``elapsed(for:)`` on the tick grid the phase formulas are written in.
    func ticks(for clock: AnimationClock) -> Int {
        // Through the one conversion every step boundary shares, so the phase formulas
        // and the pre-rendered runs agree on which tick an instant is in — a floor in
        // seconds put a summed 0.35 s in tick 6, when this clock was a sum. Clamped
        // rather than narrowed: `Int` is 32 bits on wasm32.
        Int(clamping: AnimationClock.step(atElapsed: elapsed(for: clock), frameDuration: Self.tickInterval))
    }

    /// Whether the cursor clock was read during the current render frame.
    ///
    /// Reset by ``beginFrameReadTracking()`` before each render; set when
    /// ``blinkVisible(for:)`` or ``pulsePhase(for:)`` is consulted. The run loop
    /// reads it after the frame to decide whether the cursor is still animating
    /// (a text field is focused) and the timer should keep ticking.
    private(set) var didReadThisFrame = false

    /// Clears the per-frame read flag. Call before each render pass.
    func beginFrameReadTracking() {
        didReadThisFrame = false
    }

    /// The running animation task, or `nil` if stopped.
    private var task: Task<Void, Never>?

    /// How long the next wake-up is away.
    ///
    /// The clock's own interval by default — what a view that builds its
    /// appearance from the phase as it renders needs, because only that view
    /// knows what it would draw next. A frame whose animation is all
    /// pre-rendered runs can say exactly when the picture next changes
    /// (`RenderLoop.timeUntilNextChange(elapsed:)`), and the clock then sleeps
    /// precisely that long instead of waking to compare identical pictures —
    /// or, for a run asking for a rate finer than the interval, sooner than the
    /// interval.
    /// Readable rather than fully private so a test can assert that a served
    /// animation replay re-based the sleep — the value never leaves this class
    /// otherwise, and the run loop only ever writes it through ``advance(by:)``.
    private(set) var sleepSeconds = CursorTimer.tickInterval

    /// Sets how far the next wake-up is. Takes effect after the current sleep.
    ///
    /// For a RENDER, which has just replaced the runs and may be about to start the
    /// timer: `start()` reads this for its first sleep. A running timer replans at
    /// every wake through ``planner`` and does not depend on it.
    func advance(by seconds: Double) {
        sleepSeconds = max(AnimationClock.minimumFrameDuration, seconds)
    }

    /// How the NEXT sleep is chosen, asked at the moment the timer wakes.
    ///
    /// The run loop installs it once, as `RenderLoop.timeUntilNextChange(elapsed:)`.
    /// The plan used to arrive through ``advance(by:)``, called by the loop AFTER it had
    /// served the tick — but this task keeps the main actor straight from posting that
    /// tick back to the top of its loop, so by the time the loop ran the timer had
    /// already begun its next sleep, with the value planned one wake EARLIER. While every
    /// plan was the same length the lag could not be seen. Wherever plans vary — two runs
    /// at different rates on one page, a quantised pulse holding a shade — each sleep was
    /// the previous wake's: a change was slept through, and the next landed on top of it.
    /// It was half of the owner's "complex period" blink (the other half being the step
    /// floor fixed beside `AnimationClock.step(atElapsed:frameDuration:)`, which is what
    /// made a blink's plans vary at all).
    ///
    /// Asked here, after taking the time of the wake, the plan and the sleep are the
    /// same wake's, and no ordering between the task and the loop can come between them.
    /// `nil` leaves the sleep where ``advance(by:)`` last put it.
    var planner: (((AnimationClock) -> Double) -> Double)?

    /// The render notifier to trigger re-renders.
    private weak var renderNotifier: AppState?

    /// Creates a new cursor timer.
    ///
    /// - Parameter renderNotifier: The app state to notify when a re-render
    ///   is needed. Held weakly to avoid retain cycles.
    init(renderNotifier: AppState) {
        self.renderNotifier = renderNotifier
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - Phase Computation

extension CursorTimer {
    /// Returns whether a blink is in its visible half now.
    ///
    /// - Parameter speed: The speed of the indicator that blinks.
    /// - Returns: `true` if the blink is visible, `false` if hidden.
    func blinkVisible(for speed: IndicatorAnimationSpeed) -> Bool {
        didReadThisFrame = true
        return Self.blinkVisible(atFrame: Self.cycleLayout(of: .blink, speed: speed).timing.step(on: self))
    }

    /// A blink's cycle at the standard speed, visible then hidden: 700 ms, 350 ms
    /// each, a whole number of base ticks.
    ///
    /// Each half is one frame of the blink's run, so a replayed blink holds it
    /// exactly, whatever its length. A view that reads the blink as it renders is
    /// re-rendered on the 50 ms cursor lattice, though, so for that view a half that
    /// is not a whole number of ticks still flips up to a tick late. The standard
    /// blink was once 660 ms, and its live blink wobbled between a 600 ms and a
    /// 700 ms period.
    nonisolated static let standardBlinkCycle: TimeInterval = 0.7

    /// A breath's cycle at the standard speed, bright to dim to bright: 800 ms.
    nonisolated static let standardPulseCycle: TimeInterval = 0.8

    /// How a cycle of `animation` at `speed` is laid out: how many frames it has,
    /// and how long each is shown, on which clock.
    ///
    /// Two kinds of cycle, laid out differently on purpose:
    /// - **A blink is discrete.** Visible, then hidden: two frames, each shown for
    ///   ``standardBlinkCycle``'s half at the standard rate, and for
    ///   ``IndicatorAnimationSpeed/frameDuration(standard:)`` of it at `speed`. It
    ///   used to be one frame per 50 ms tick, seven visible and seven hidden. That
    ///   holds only while a half is a whole number of ticks, and it makes a slower
    ///   blink more frames rather than longer ones.
    /// - **A pulse is continuous.** ``standardPulseCycle`` divided by the rate,
    ///   sampled at its standard frame, one cursor tick: `max(2, round(cycle / tick))`
    ///   frames, at most `RampLayout.maximumFrameCount`, each `cycle / count` long,
    ///   so the cycle is exactly that length. A
    ///   slowed breath stays as smooth, and a quickened one wakes the loop no more
    ///   often. Within `speed`'s tolerance the cycle may move onto whole ticks
    ///   (``IndicatorAnimationSpeed/rampLayout(standardCycle:framesPerSecond:snapping:)``);
    ///   at the standard 800 ms it already is.
    /// - `.none` is one frame, a still picture.
    ///
    /// Both animate on the focus-relative clock. The whole cycle is built from this
    /// and from the two frame formulas below, and the live readers step through the
    /// same layout, so a replayed run and a render that reads the clock show the
    /// same frame at the same instant: one layout, not two that can drift apart.
    ///
    /// `nonisolated`: it is arithmetic on constants and reads no timer.
    nonisolated static func cycleLayout(
        of animation: TextCursorStyle.Animation, speed: IndicatorAnimationSpeed
    ) -> CycleLayout {
        switch animation {
        case .none:
            return CycleLayout(frameCount: 1, timing: .cursorTick)
        case .blink:
            return CycleLayout(
                frameCount: 2,
                timing: IndicatorCycleTiming(
                    frameDuration: speed.frameDuration(standard: standardBlinkCycle / 2), clock: .cursor))
        case .pulse:
            // The framework's own cycle, so the tolerance may move it: snapping.
            let ramp = speed.rampLayout(
                standardCycle: standardPulseCycle, framesPerSecond: 1 / AnimationClock.cursor.tickInterval,
                snapping: true)
            return CycleLayout(
                frameCount: ramp.frameCount,
                timing: IndicatorCycleTiming(frameDuration: ramp.frameDuration, clock: .cursor))
        }
    }

    /// A cycle's frame count and the timing its frames step on. See
    /// ``cycleLayout(of:speed:)``.
    struct CycleLayout: Equatable, Sendable {
        let frameCount: Int
        let timing: IndicatorCycleTiming
    }

    /// Whether the caret is visible at `frame` of a blink: the first of its two
    /// frames, and every other one after it.
    ///
    /// Static, and the instance method above defers to it, so a producer that
    /// pre-renders its whole cycle (see ``AnimatedCellRun``) computes exactly what
    /// a live render would. Reading it does NOT mark the frame as having consulted
    /// the clock, which is what lets such a producer be replayed rather than
    /// re-rendered.
    nonisolated static func blinkVisible(atFrame frame: Int) -> Bool {
        frame.isMultiple(of: 2)
    }

    /// Returns the pulse phase (0-1) for smooth cursor animation.
    ///
    /// The phase follows a cosine curve for smooth breathing, and it starts at
    /// its BRIGHTEST:
    /// - 0.0: Dimmest
    /// - 1.0: Brightest
    ///
    /// Starting bright is what makes `restartFocusPhase()` mean "show me now".
    /// The clock is reset whenever the focus moves, and a breath that began at
    /// its dim end left the newly focused control looking unfocused for a third
    /// of a second — the moment it most needs to be visible.
    ///
    /// - Parameter speed: The speed of the indicator that pulses.
    /// - Returns: Phase value between 0 and 1.
    func pulsePhase(for speed: IndicatorAnimationSpeed) -> Double {
        didReadThisFrame = true
        return pulsePhaseNow(speed: speed)
    }

    /// The breath phase right now, WITHOUT marking the clock as consumed.
    ///
    /// The phase seam `EnvironmentValues.pulsePhase` carries, so a view that
    /// reads the phase directly sees the same breath as one that resolves a
    /// ``SelectionEmphasis`` — there is one clock and one formula behind both.
    /// (Demand is tracked at the seam's own getter, which is why this one must
    /// not set `didReadThisFrame`.)
    ///
    /// At ``IndicatorAnimationSpeed/automatic``, the focus emphasis's speed where
    /// nothing sets one: the seam is one value for the whole frame, and cannot see
    /// a subtree's `indicatorAnimationSpeed(_:for:)`.
    var breathPhase: Double {
        pulsePhaseNow(speed: .automatic)
    }

    /// The pulse phase at the last snapshot, read through the pulse's own layout.
    private func pulsePhaseNow(speed: IndicatorAnimationSpeed) -> Double {
        let layout = Self.cycleLayout(of: .pulse, speed: speed)
        return Self.pulsePhase(atFrame: layout.timing.step(on: self), of: layout.frameCount)
    }

    /// The pulse phase at `frame` of a pulse of `count` frames. See
    /// ``blinkVisible(atFrame:)`` for why this is static and why reading it is not a
    /// volatile read.
    nonisolated static func pulsePhase(atFrame frame: Int, of count: Int) -> Double {
        guard count > 0 else { return 1 }
        let wrapped = frame % count
        let normalized = Double(wrapped < 0 ? wrapped + count : wrapped) / Double(count)
        // Cosine wave: 1 → 0 → 1 over the cycle, so frame 0 is the bright end.
        return (cos(normalized * 2 * .pi) + 1) / 2
    }
}

// MARK: - Timer Control

extension CursorTimer {
    /// Starts the cursor animation timer.
    ///
    /// If the timer is already running, this is a no-op.
    func start() {
        guard task == nil else { return }

        task = Task { [weak self] in
            while !Task.isCancelled {
                // Read per iteration: `creditWake(atNanos:)` planned it at the previous
                // wake — or, for the first pass, a render set it through `advance(by:)`.
                let seconds = self?.sleepSeconds ?? Self.tickInterval
                do {
                    try await Task.sleep(nanoseconds: Self.sleepNanoseconds(seconds))
                } catch {
                    return  // cancelled
                }
                // The sleep returning is NOT proof the task still wants this
                // wake: `Task.sleep` throws only when the cancel beats the
                // wake, so one whose deadline passed while the main actor was
                // busy resumes normally even though `cancel()` has since been
                // called. Taking it then would fix the cursor clock's new zero
                // at this stale wake instead of the render the restart left it
                // to, and would carry on looping beside the task that render
                // starts — two timers, twice the wakes.
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.creditWake(atNanos: self.nowNanos())
            }
        }
    }

    /// `seconds` as the nanoseconds a sleep asks for: ROUNDED, through the conversion
    /// every step boundary uses.
    ///
    /// `UInt64(seconds * 1_000_000_000)` truncated, and a plan of `n` nanoseconds that
    /// has been through `Double(n) / 1e9` comes back one short on about 2% of plans. A
    /// real wake is milliseconds late and hides that. A clock that advances by exactly
    /// what was slept wakes 1 ns before the boundary, finds the change still 1 ns away,
    /// and plans the 10 ms floor: a frame 10 ms late.
    static func sleepNanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(clamping: AnimationClock.nanoseconds(seconds))
    }

    /// Takes a wake at `now`, plans the sleep that follows it, and posts the ticks — in
    /// that order, which is the point.
    ///
    /// The body of the timer's loop, separate so a test can step it on a clock of its
    /// own without racing a real `Task.sleep`.
    func creditWake(atNanos now: UInt64) {
        // What the clock READS, not what the sleep asked for. A wake is late by a few
        // milliseconds, and crediting only the planned sleep lost that at every wake —
        // every animation on a page ran slow by one shared factor, 1.48× on the
        // Spinners page.
        observe(nowNanos: now)
        // Planned BEFORE the ticks go out: see `planner` for what planning after them
        // did.
        if let planner {
            advance(by: planner(elapsed(for:)))
        }
        // Both clocks, because both advance on this one timer: they differ in where
        // their zero sits, not in when they tick.
        for clock in AnimationClock.allCases {
            renderNotifier?.setNeedsAnimationTick(clock)
        }
    }

    /// Stops the cursor animation timer.
    ///
    /// ``AnimationClock/content`` is not reset, and cannot be: it is the monotonic
    /// clock. A spinner that appears after a still stretch starts where the shared
    /// clock is, in phase with every other spinner of its style, rather than at its
    /// first frame. ``AnimationClock/cursor`` restarts at its bright end at the next
    /// ``observe(nowNanos:)``.
    func stop() {
        task?.cancel()
        task = nil
        focusEpochNanos = nil
        sleepSeconds = Self.tickInterval
    }

    /// Restarts ``AnimationClock/cursor`` at its bright end, leaving
    /// ``AnimationClock/content`` running.
    ///
    /// Call this when the focus moves, so whatever has just taken it is visible at
    /// once. The run loop also calls it when the process resumes from Ctrl-Z or an
    /// external SIGSTOP: the monotonic clock ran on while it was stopped, and a caret
    /// would otherwise come back mid-blink.
    ///
    /// **It reads no clock.** The new zero is taken at the next ``observe(nowNanos:)``
    /// — the render that always follows — floored to the tick lattice, so that frame
    /// is tick 0 by construction. Read here, the zero would be floored at INPUT time
    /// and the render would come later (up to a frame at the pacer's cap, on top of up
    /// to a tick of floor), so the first frame could already be tick 1 and miss the
    /// bright start this exists to give; and the read would move `.content` between
    /// two frames.
    func restartFocusPhase() {
        focusEpochNanos = nil
        sleepSeconds = Self.tickInterval
        // The in-flight sleep was sized for the OLD cadence, and its wake would set
        // the new zero at the wake rather than at the render that follows the focus
        // change. Cancelling usually ends the sleep with a CancellationError the loop
        // returns on; when the wake got there first the loop's own `Task.isCancelled`
        // check catches it instead. The render that always follows a focus change
        // starts the timer again.
        task?.cancel()
        task = nil
    }
}
