//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// Elapsed ticks, for the phase formulas that are still defined on a grid.
    ///
    /// Derived rather than counted, so a variable sleep keeps every phase's
    /// wall-clock meaning: a breath is a breath whether the loop woke six times
    /// or sixty on the way through it.
    var elapsedTicks: Int { Int((elapsedSeconds / Self.tickInterval).rounded(.down)) }

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
                guard let self else { return }
                // Advanced by what was SLEPT, not by a grid step, which is what
                // keeps `elapsedSeconds` a real elapsed time under a variable
                // cadence — and therefore keeps every phase derived from it
                // honest.
                self.elapsedSeconds += seconds
                self.renderNotifier?.setNeedsAnimationTick(.cursor)
            }
        }
    }

    /// Stops the cursor animation timer.
    func stop() {
        task?.cancel()
        task = nil
        elapsedSeconds = 0
        sleepSeconds = Self.tickInterval
    }

    /// Resets the cursor animation to the visible/bright state.
    ///
    /// Call this when a text field gains focus to ensure the cursor
    /// starts in a visible state.
    func reset() {
        elapsedSeconds = 0
        sleepSeconds = Self.tickInterval
        // The in-flight sleep was sized for the OLD cadence: leaving it to
        // finish would add that whole stride to a counter that has just been
        // zeroed, so a focus change during a long sleep (the quantised pulse
        // holds a shade for several ticks) jumped the clock past the bright
        // start the reset exists to give it. Cancelling ends the sleep with a
        // CancellationError the loop already returns on; the render that
        // always follows a focus change starts the timer again.
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
