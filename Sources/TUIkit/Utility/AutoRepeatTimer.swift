//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AutoRepeatTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Auto-Repeat Timer

/// Fires an action once immediately, then again periodically
/// after a short initial delay, until cancelled.
///
/// Used by ``Stepper`` (and other discrete-step controls) to
/// implement "press-and-hold to keep adjusting" — the user
/// holds down on the increment / decrement arrow and the
/// stepper keeps ticking up / down at a steady cadence,
/// matching the system-stepper behaviour every desktop and
/// mobile OS ships.
///
/// The cadence is two fixed constants:
///
/// - ``initialDelayMs`` — the time between the initial fire
///   and the start of the repeat loop. Long enough that a
///   normal short-tap press only fires once.
/// - ``repeatIntervalMs`` — the gap between successive
///   repeats once the loop is going. Short enough to feel
///   responsive but slow enough that the user can stop
///   precisely.
///
/// Internally a single `Task` runs on the main actor. Starting
/// a new run while one is already going cancels the previous.
/// Cancelling is idempotent.
@MainActor
public final class AutoRepeatTimer {
    /// Milliseconds between the initial action and the first
    /// repeat. Tuned to feel like a typical OS press-and-hold:
    /// short enough that a held press starts repeating without
    /// feeling stuck, long enough that a brief tap fires only
    /// once.
    public static let initialDelayMs: Int = 400

    /// Milliseconds between successive repeats once the
    /// initial delay has elapsed.
    public static let repeatIntervalMs: Int = 80

    /// The running task, or `nil` if not currently active.
    private var task: Task<Void, Never>?

    /// Creates a timer in the stopped state.
    public init() {}

    /// Whether the timer is currently scheduled.
    public var isRunning: Bool { task != nil }

    /// Starts the timer. Fires `action` once immediately, then
    /// — after ``initialDelayMs`` — keeps calling it every
    /// ``repeatIntervalMs`` until ``stop()`` is called (or
    /// another `start` cancels this one).
    ///
    /// `action` runs on the main actor.
    ///
    /// - Parameter action: The closure to invoke on each tick.
    public func start(action: @escaping @MainActor () -> Void) {
        stop()
        let initialDelayNanos = UInt64(Self.initialDelayMs) * 1_000_000
        let repeatIntervalNanos = UInt64(Self.repeatIntervalMs) * 1_000_000
        task = Task { @MainActor in
            // Fire once immediately so a normal click still
            // gets one action — same as the previous
            // non-auto-repeating behaviour.
            action()

            // Wait the initial delay before kicking off the
            // repeat loop. If the user released the press
            // during this window the task has already been
            // cancelled and the sleep throws; we swallow it
            // because cancellation is the expected path.
            do {
                try await Task.sleep(nanoseconds: initialDelayNanos)
            } catch {
                return
            }

            while !Task.isCancelled {
                action()
                do {
                    try await Task.sleep(nanoseconds: repeatIntervalNanos)
                } catch {
                    return
                }
            }
        }
    }

    /// Stops the timer. Idempotent — calling on an already-
    /// stopped timer is a no-op.
    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
