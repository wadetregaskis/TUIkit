//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationCycle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore

/// A repeating animation sampled onto the clock the run loop can replay.
///
/// A ``Animation/repeatForever(autoreverses:)`` animation is the one shape that
/// does not end, so serving it by re-rendering costs a render pass *for as long
/// as the view is on screen* — the exact pathology ``AnimatedCellRun`` exists to
/// remove. But a cycle is finite and small: at the animation clock's 50 ms step,
/// a 0.8 s breath is sixteen distinct values. Small enough to compute all of
/// them, draw all of them, and hand the loop the finished frames.
///
/// ``values`` is indexed **by clock tick**, not from the animation's start, so
/// `values[tick % count]` is what to draw at that tick — which is precisely how
/// ``AnimatedCellRun`` indexes its frames. The phase offset is baked in at
/// construction, so an animation that started at an arbitrary moment is not
/// snapped to a global grid: it keeps its own phase, and the array is simply
/// rotated to match.
public struct AnimationCycle<Value: VectorArithmetic>: Sendable where Value: Sendable {
    /// One value per tick of the cycle, indexed by `tick % count`.
    public let values: [Value]

    /// The index of the value to draw in the frame being rendered now.
    public let currentIndex: Int

    /// The value to draw now.
    public var current: Value { values[currentIndex] }

    /// The clock these are indexed against.
    public let clock: AnimationClock

    /// The longest cycle that is worth pre-rendering, in ticks.
    ///
    /// Six seconds. Past that the frames outweigh what they save — a run holds
    /// one finished string per tick per row — and an animation slow enough to
    /// need it is one whose re-renders are rare anyway.
    public static var maximumTicks: Int { 120 }

    /// Samples `animation` onto `clock`, or `nil` if it does not repeat forever
    /// or its cycle is too long to be worth holding.
    ///
    /// - Parameters:
    ///   - animation: The animation. Must repeat forever.
    ///   - from: The value the animation started at.
    ///   - to: The value it is heading for.
    ///   - startNanos: When it began, on the frame clock.
    ///   - nowNanos: This frame's timestamp.
    ///   - tick: The clock's tick count for this frame.
    ///   - clock: Which clock will replay it.
    public init?(
        animation: Animation,
        from: Value,
        to: Value,
        startNanos: Int64,
        nowNanos: Int64,
        tick: Int,
        clock: AnimationClock = .cursor
    ) {
        guard let period = animation.cyclePeriod, period > 0 else { return nil }
        let count = Int((period / clock.tickInterval).rounded())
        guard count >= 2, count <= Self.maximumTicks else { return nil }

        // Which tick the animation began on. The current tick is `tick` and the
        // animation has been running `nowNanos - startNanos`, so counting back
        // gives the start — and every value below is then a function of the
        // tick alone, which is what makes them replayable.
        let elapsed = Double(nowNanos - startNanos) / 1_000_000_000
        let startTick = tick - Int((elapsed / clock.tickInterval).rounded())

        var values: [Value] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            // The tick at or after `startTick` whose index is `index`, so the
            // array reads correctly under `tick % count` at every tick.
            let offset = (index - startTick).modulo(count)
            let fraction = animation.fraction(at: Double(offset) * clock.tickInterval)
            values.append(from.interpolated(towards: to, amount: fraction))
        }
        self.values = values
        self.currentIndex = tick.modulo(count)
        self.clock = clock
    }
}

extension Int {
    /// A non-negative remainder. `%` keeps the sign of the dividend, and a tick
    /// count that has been counted backwards past zero is negative.
    fileprivate func modulo(_ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let remainder = self % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}
