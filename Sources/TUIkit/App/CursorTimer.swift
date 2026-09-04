//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// The app's one animation clock: the cursor's blink, and every focus
/// indicator's breath.
///
/// `CursorTimer` maintains two phase values for different animation styles:
/// - `blinkVisible`: Boolean for sharp on/off blinking
/// - `pulsePhase`: Smooth 0-1 cosine wave for pulsing, starting bright
///
/// There used to be a second clock — a `PulseTimer` for focus indicators — and
/// having two was a bug rather than a feature: they ran at different rates from
/// different formulas, so the same focus pulse breathed at 2 s on a section's
/// border and 0.8 s on the controls inside it, depending only on which route
/// the view took. One clock and one formula now serve both, with the cadence
/// chosen per element by ``SelectionIndicatorStyle``.
///
/// The timer is a single `@MainActor` `Task` that sleeps between ticks (the
/// same pattern as ``AutoRepeatTimer``). Staying on the main actor means the
/// tick counter is never mutated off-thread, so the phases read during render
/// are race-free.
///
/// ## Animation Speeds
///
/// The speed is controlled by ``TextCursorStyle/Speed``:
/// - `.slow`: 800ms cycle (visible 400ms, hidden 400ms)
/// - `.regular`: 530ms cycle (visible 265ms, hidden 265ms)
/// - `.fast`: 300ms cycle (visible 150ms, hidden 150ms)
///
/// ## Usage
///
/// ```swift
/// let cursor = CursorTimer(renderNotifier: appState)
/// cursor.start()
/// // In render code:
/// if cursor.blinkVisible(for: .regular) {
///     // show cursor
/// }
/// let phase = cursor.pulsePhase(for: .regular)
/// ```
@MainActor
final class CursorTimer {
    /// How often a view that reads the phase AS IT RENDERS is re-rendered.
    /// Taken from ``AnimationClock/tickInterval`` rather than written here so
    /// there is one number, not two that can disagree.
    private static let tickInterval = AnimationClock.cursor.tickInterval

    /// The same, in whole milliseconds — what the blink and pulse formulas are
    /// written in.
    private static let tickIntervalMs = Int(AnimationClock.cursor.tickInterval * 1000)

    /// Seconds of animation elapsed since the timer started.
    ///
    /// The source of truth, and in SECONDS rather than ticks because the sleeps
    /// are no longer a fixed length: each is however long the frame on screen
    /// says nothing can change for, so a run animating at 1/30 s and one at
    /// 0.11 s each get exactly their own cadence. See
    /// ``RenderLoop/timeUntilNextChange(from:)``.
    private(set) var elapsedSeconds: Double = 0

    /// Where ``AnimationClock/cursor``'s zero currently sits, in
    /// ``elapsedSeconds``.
    ///
    /// Moved forward to "now" whenever the focus moves, which is how the blink
    /// and the focus breath restart at their bright end without disturbing
    /// anything else. This used to be done by zeroing `elapsedSeconds` itself,
    /// and every animation in the app read that one number: pressing Tab
    /// restarted every indeterminate progress bar, every spinner and every
    /// breathing label along with the cursor.
    private var focusEpoch: Double = 0

    /// How far `clock` has run.
    ///
    /// The two clocks share one timer and differ only in where their zero is —
    /// see ``AnimationClock``.
    func elapsed(for clock: AnimationClock) -> Double {
        switch clock {
        case .cursor: max(0, elapsedSeconds - focusEpoch)
        case .content: elapsedSeconds
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
        Int((elapsed(for: clock) / Self.tickInterval).rounded(.down))
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
    /// (`RenderLoop.timeUntilNextChange(from:)`), and the clock then sleeps
    /// precisely that long instead of waking to compare identical pictures —
    /// or, for a run asking for a rate finer than the interval, sooner than the
    /// interval.
    private var sleepSeconds = CursorTimer.tickInterval

    /// Sets how far the next wake-up is. Takes effect after the current sleep.
    func advance(by seconds: Double) {
        sleepSeconds = max(AnimationClock.minimumFrameDuration, seconds)
    }

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
    /// Returns whether the cursor should be visible for blink animation.
    ///
    /// - Parameter speed: The cursor speed setting.
    /// - Returns: `true` if cursor should be visible, `false` if hidden.
    func blinkVisible(for speed: TextCursorStyle.Speed) -> Bool {
        didReadThisFrame = true
        return Self.blinkVisible(atTick: elapsedTicks, speed: speed)
    }

    /// The blink state at an arbitrary tick.
    ///
    /// Static, and the instance method above defers to it, so a producer that
    /// pre-renders its whole cycle (see ``AnimatedCellRun``) computes exactly
    /// what a live render would — one formula, not two that can drift apart.
    /// Reading it does NOT mark the frame as having consulted the clock, which
    /// is what lets such a producer be replayed rather than re-rendered.
    static func blinkVisible(atTick tick: Int, speed: TextCursorStyle.Speed) -> Bool {
        let cycleMs = speed.blinkCycleMs
        // Visible for the first half of the cycle.
        return (tick * Self.tickIntervalMs) % cycleMs < (cycleMs / 2)
    }

    /// How many ticks a full cycle of `animation` takes at `speed` — the number
    /// of frames a pre-rendered run needs.
    static func cycleTicks(for speed: TextCursorStyle.Speed, animation: TextCursorStyle.Animation) -> Int {
        switch animation {
        case .none: return 1
        case .blink: return max(1, speed.blinkCycleMs / Self.tickIntervalMs)
        case .pulse: return max(1, speed.pulseCycleMs / Self.tickIntervalMs)
        }
    }

    /// Returns the pulse phase (0-1) for smooth cursor animation.
    ///
    /// The phase follows a cosine curve for smooth breathing, and it starts at
    /// its BRIGHTEST:
    /// - 0.0: Dimmest
    /// - 1.0: Brightest
    ///
    /// Starting bright is what makes ``reset()`` mean "show me now". The clock
    /// is reset whenever the focus moves, and a breath that began at its dim
    /// end left the newly focused control looking unfocused for a third of a
    /// second — the moment it most needs to be visible.
    ///
    /// - Parameter speed: The cursor speed setting.
    /// - Returns: Phase value between 0 and 1.
    func pulsePhase(for speed: TextCursorStyle.Speed) -> Double {
        didReadThisFrame = true
        return Self.pulsePhase(atTick: elapsedTicks, speed: speed)
    }

    /// The breath phase right now, WITHOUT marking the clock as consumed.
    ///
    /// The phase seam `EnvironmentValues.pulsePhase` carries, so a view that
    /// reads the phase directly sees the same breath as one that resolves a
    /// ``SelectionEmphasis`` — there is one clock and one formula behind both.
    /// (Demand is tracked at the seam's own getter, which is why this one must
    /// not set `didReadThisFrame`.)
    var breathPhase: Double {
        Self.pulsePhase(atTick: elapsedTicks, speed: .regular)
    }

    /// The pulse phase at an arbitrary tick. See ``blinkVisible(atTick:speed:)``
    /// for why this is static and why reading it is not a volatile read.
    static func pulsePhase(atTick tick: Int, speed: TextCursorStyle.Speed) -> Double {
        let cycleMs = speed.pulseCycleMs
        let normalized = Double((tick * Self.tickIntervalMs) % cycleMs) / Double(cycleMs)
        // Cosine wave: 1 → 0 → 1 over the cycle, so tick 0 is the bright end.
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
                // Read per iteration: `advance(by:)` is called after each wake,
                // so the NEXT sleep is the one the frame just served asked for.
                let seconds = self?.sleepSeconds ?? Self.tickInterval
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    return  // cancelled
                }
                // The sleep returning is NOT proof the task still wants this
                // stride: `Task.sleep` throws only when the cancel beats the
                // wake, so one whose deadline passed while the main actor was
                // busy resumes normally even though `cancel()` has since been
                // called. Crediting it then lands a whole stride on a clock
                // `restartFocusPhase()` or `stop()` has already re-zeroed —
                // precisely the jump those cancels exist to prevent.
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // Advanced by what was SLEPT, not by a grid step, which is what
                // keeps `elapsedSeconds` a real elapsed time under a variable
                // cadence — and therefore keeps every phase derived from it
                // honest.
                self.elapsedSeconds += seconds
                // Both clocks, because both advance on this one timer: they
                // differ in where their zero sits, not in when they tick.
                for clock in AnimationClock.allCases {
                    self.renderNotifier?.setNeedsAnimationTick(clock)
                }
            }
        }
    }

    /// Stops the cursor animation timer.
    func stop() {
        task?.cancel()
        task = nil
        elapsedSeconds = 0
        focusEpoch = 0
        sleepSeconds = Self.tickInterval
    }

    /// Restarts ``AnimationClock/cursor`` at its bright end, leaving
    /// ``AnimationClock/content`` running.
    ///
    /// Call this when the focus moves, so whatever has just taken it is
    /// visible at once. It does NOT touch `elapsedSeconds`: a progress bar's
    /// sweep and a breathing label are not about the focus and must not jump
    /// when it changes.
    func restartFocusPhase() {
        focusEpoch = elapsedSeconds
        sleepSeconds = Self.tickInterval
        // The in-flight sleep was sized for the OLD cadence: leaving it to
        // finish would add that whole stride to a phase that has just been
        // re-zeroed, so a focus change during a long sleep (the quantised
        // pulse holds a shade for several ticks) jumped the clock past the
        // bright start this exists to give it. Cancelling usually ends the
        // sleep with a CancellationError the loop returns on; when the wake
        // got there first the loop's own `Task.isCancelled` check catches it
        // instead. The render that always follows a focus change starts the
        // timer again.
        task?.cancel()
        task = nil
    }
}

// MARK: - Speed Cycle Durations

extension TextCursorStyle.Speed {
    /// The blink cycle duration in milliseconds (on + off).
    var blinkCycleMs: Int {
        switch self {
        case .slow: 1000  // 500ms on, 500ms off
        case .regular: 660  // 330ms on, 330ms off
        case .fast: 400  // 200ms on, 200ms off
        }
    }

    /// The pulse cycle duration in milliseconds (dim → bright → dim).
    var pulseCycleMs: Int {
        switch self {
        case .slow: 1200  // 1.2 second breathing cycle
        case .regular: 800  // 0.8 second breathing cycle
        case .fast: 500  // 0.5 second breathing cycle
        }
    }
}
