//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationCycleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

/// `AnimationCycle` pre-renders a repeating animation onto the clock so the
/// run loop can replay it without re-rendering. It assumes pure periodicity —
/// which a delay breaks.
@Suite("AnimationCycle")
struct AnimationCycleTests {

    private let clock = AnimationClock.cursor

    @Test("A delay-free repeating fade builds a cycle")
    func delayFreeBuildsACycle() {
        let animation = Animation.linear(duration: 0.4).repeatForever(autoreverses: true)
        let cycle = AnimationCycle<Double>(
            animation: animation, from: 0, to: 1,
            startNanos: 0, nowNanos: 0, tick: 0, clock: clock)
        #expect(cycle != nil, "a delay-free forever fade should pre-render")
        #expect(cycle?.values.contains { $0 > 0.5 } == true, "the cycle moves")
    }

    @Test("A delayed repeating fade refuses the cycle, falling back to per-frame")
    func delayedRefusesTheCycle() {
        // fraction(at:) pins to 0 through the delay, so sampling one period
        // from zero folds the delay's zeros into the cycle (replaying wrong
        // frames), and a delay >= the period samples ALL zeros — no runs
        // built while the caller already marked the fade served, a freeze.
        let animation = Animation.linear(duration: 0.4)
            .repeatForever(autoreverses: true)
            .delay(1.0)
        let cycle = AnimationCycle<Double>(
            animation: animation, from: 0, to: 1,
            startNanos: 0, nowNanos: 0, tick: 0, clock: clock)
        #expect(cycle == nil, "a delayed forever fade must not pre-render")
    }
}
