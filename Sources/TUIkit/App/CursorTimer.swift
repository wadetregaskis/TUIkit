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
    /// Base tick interval in milliseconds.
    /// We use a fast tick (50ms) and derive phases from elapsed time.
    private static let tickIntervalMs = 50
    private var tickIntervalMs: Int { Self.tickIntervalMs }

    /// Elapsed ticks since timer started.
    /// Readable so a cell-run replay indexes a cycle by the same tick the blink
    /// state is computed from.
    private(set) var elapsedTicks = 0

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
        return (tick * tickIntervalMs) % cycleMs < (cycleMs / 2)
    }

    /// How many ticks a full cycle of `animation` takes at `speed` — the number
    /// of frames a pre-rendered run needs.
    static func cycleTicks(for speed: TextCursorStyle.Speed, animation: TextCursorStyle.Animation) -> Int {
        switch animation {
        case .none: return 1
        case .blink: return max(1, speed.blinkCycleMs / tickIntervalMs)
        case .pulse: return max(1, speed.pulseCycleMs / tickIntervalMs)
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
        let normalized = Double((tick * tickIntervalMs) % cycleMs) / Double(cycleMs)
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

        let tickNanos = UInt64(tickIntervalMs) * 1_000_000
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: tickNanos)
                } catch {
                    return  // cancelled
                }
                guard let self else { return }
                self.elapsedTicks += 1
                self.renderNotifier?.setNeedsAnimationTick(.cursor)
            }
        }
    }

    /// Stops the cursor animation timer.
    func stop() {
        task?.cancel()
        task = nil
        elapsedTicks = 0
    }

    /// Resets the cursor animation to the visible/bright state.
    ///
    /// Call this when a text field gains focus to ensure the cursor
    /// starts in a visible state.
    func reset() {
        elapsedTicks = 0
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
