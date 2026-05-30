//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PulseTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// Drives the breathing animation for the active focus section indicator.
///
/// `PulseTimer` maintains a phase value (0–1) that oscillates smoothly
/// using a sine curve. On each step, it calls `setNeedsRender()` to
/// trigger a re-render with the updated phase.
///
/// The timer is a single `@MainActor` `Task` that sleeps between steps —
/// the same pattern as ``AutoRepeatTimer`` and the input-reader's
/// `StdinArrivalNotifier`. Keeping it on the main actor means the phase it
/// publishes (read during render, also on the main actor) is never touched
/// off-thread, so there's no cross-thread data race and no dispatch-queue
/// machinery to manage.
///
/// ## Breathing Cycle
///
/// - The phase follows `sin(step * π / totalSteps)`, producing a smooth
///   0 → 1 → 0 oscillation.
/// - Default: 10 steps at 100ms each = 2 second cycle.
/// - At phase 0: color is dimmed (20% of accent). At phase 1: full accent.
///
/// ## Usage
///
/// ```swift
/// let pulse = PulseTimer(renderNotifier: appState)
/// pulse.start()
/// // ... later
/// pulse.stop()
/// ```
@MainActor
final class PulseTimer {
    /// The number of discrete steps in a half-cycle (dim → bright).
    ///
    /// A full breathing cycle (dim → bright → dim) is `totalHalfSteps * 2` steps.
    /// At 100ms per step and 10 half-steps: full cycle = 20 × 100ms = 2 seconds.
    private let totalHalfSteps = 10

    /// The interval between steps in milliseconds.
    private let stepIntervalMs = 100

    /// The current step in the full cycle (0 ..< totalHalfSteps * 2).
    private var currentStep = 0

    /// The running animation task, or `nil` if stopped.
    private var task: Task<Void, Never>?

    /// The render notifier to trigger re-renders.
    private weak var renderNotifier: AppState?

    /// The current pulse phase (0–1), computed from the current step.
    ///
    /// Uses a sine curve mapped to 0–1 for smooth breathing:
    /// - Step 0: phase = 0 (dimmest)
    /// - Step totalHalfSteps: phase = 1 (brightest)
    /// - Step totalHalfSteps * 2: phase = 0 (dimmest, cycle repeats)
    var phase: Double {
        let fullCycle = totalHalfSteps * 2
        let normalized = Double(currentStep) / Double(fullCycle)
        // sin(0) = 0, sin(π) = 0, peak at sin(π/2) = 1
        return sin(normalized * .pi)
    }

    /// Creates a new pulse timer.
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

// MARK: - Internal API

extension PulseTimer {
    /// Starts the breathing animation.
    ///
    /// If the timer is already running, this is a no-op.
    func start() {
        guard task == nil else { return }

        let stepNanos = UInt64(stepIntervalMs) * 1_000_000
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: stepNanos)
                } catch {
                    return  // cancelled
                }
                guard let self else { return }
                self.currentStep = (self.currentStep + 1) % (self.totalHalfSteps * 2)
                self.renderNotifier?.setNeedsRender()
            }
        }
    }

    /// Stops the breathing animation.
    func stop() {
        task?.cancel()
        task = nil
        currentStep = 0
    }

    /// Resets the animation to the brightest point (phase = 1).
    ///
    /// Called when focus changes to make the indicator immediately visible
    /// on the newly focused element instead of continuing mid-cycle.
    func reset() {
        // Set to peak brightness (step = totalHalfSteps → phase = 1.0)
        currentStep = totalHalfSteps
    }
}
