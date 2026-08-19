//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationTimingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Animation timing")
struct AnimationTimingTests {

    @Test("A delay holds the value at its start, then runs the full curve")
    func delayShiftsWithoutShortening() {
        let animation = Animation.linear(duration: 1).delay(0.5)
        #expect(animation.fraction(at: 0) == 0)
        #expect(animation.fraction(at: 0.4) == 0)
        #expect(abs(animation.fraction(at: 1.0) - 0.5) < 1e-6)
        #expect(animation.fraction(at: 1.5) == 1)
        #expect(animation.totalDuration == 1.5)
    }

    @Test("Speed scales the delay too")
    func speedScalesEverything() {
        // SwiftUI's `speed(_:)` is a rate multiplier on the whole animation,
        // delay included — otherwise `.speed(2)` on a delayed animation would
        // change the gap between the trigger and the movement.
        let animation = Animation.linear(duration: 1).delay(1).speed(2)
        #expect(animation.effectiveDelay == 0.5)
        #expect(animation.effectivePassDuration == 0.5)
        #expect(animation.totalDuration == 1.0)
        #expect(abs(animation.fraction(at: 0.75) - 0.5) < 1e-6)
    }

    @Test("Speeds compose by multiplying")
    func speedsCompose() {
        #expect(Animation.linear(duration: 1).speed(2).speed(3).effectivePassDuration == 1.0 / 6)
    }

    @Test("An autoreversing repeat counts one-way passes")
    func repeatCountsPasses() {
        let animation = Animation.linear(duration: 1).repeatCount(2, autoreverses: true)
        #expect(animation.totalDuration == 2)
        #expect(abs(animation.fraction(at: 0.5) - 0.5) < 1e-6)  // out
        #expect(abs(animation.fraction(at: 1.0) - 1.0) < 1e-6)  // turn
        #expect(abs(animation.fraction(at: 1.5) - 0.5) < 1e-6)  // back
        // Two passes out-and-back land back at the start, and STAY there.
        #expect(animation.fraction(at: 2.0) == 0)
        #expect(animation.fraction(at: 99) == 0)
    }

    @Test("An odd autoreversing repeat ends on the target")
    func oddRepeatEndsAtTheTarget() {
        let animation = Animation.linear(duration: 1).repeatCount(3, autoreverses: true)
        #expect(animation.fraction(at: 3) == 1)
        #expect(animation.fraction(at: 99) == 1)
    }

    @Test("Without autoreverse a repeat snaps back and runs again")
    func repeatWithoutAutoreverse() {
        let animation = Animation.linear(duration: 1).repeatCount(3, autoreverses: false)
        #expect(abs(animation.fraction(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(animation.fraction(at: 1.5) - 0.5) < 1e-6)
        #expect(animation.fraction(at: 3) == 1)
    }

    @Test("A reversed pass runs the curve backwards in time")
    func reversalIsInTime() {
        // Not a mirror of the output: `curve(1 − t)`, not `1 − curve(t)`. For an
        // asymmetric curve those differ, and time reversal is what "plays in
        // reverse" means.
        let easeOut = Animation.easeOut(duration: 1)
        let repeated = easeOut.repeatCount(2, autoreverses: true)
        for step in 1...9 {
            let t = Double(step) / 10
            #expect(abs(repeated.fraction(at: 1 + t) - easeOut.fraction(at: 1 - t)) < 1e-6)
        }
    }

    @Test("A forever animation never finishes and has a cycle")
    func foreverHasAPeriod() {
        let out = Animation.linear(duration: 0.4).repeatForever(autoreverses: false)
        #expect(out.repeatsForever)
        #expect(out.totalDuration == nil)
        #expect(out.cyclePeriod == 0.4)
        #expect(!out.isFinished(at: 1_000_000))

        let there = Animation.linear(duration: 0.4).repeatForever(autoreverses: true)
        #expect(there.cyclePeriod == 0.8)
        // And it really is periodic — the whole basis for pre-rendering it.
        for step in 0...16 {
            let t = Double(step) / 20
            #expect(abs(there.fraction(at: t) - there.fraction(at: t + 0.8)) < 1e-9, "at \(t)")
        }
    }

    @Test("A finishing animation has no cycle to pre-render")
    func finiteAnimationsHaveNoPeriod() {
        #expect(Animation.easeInOut.cyclePeriod == nil)
        #expect(Animation.linear(duration: 1).repeatCount(9).cyclePeriod == nil)
        #expect(Animation.easeInOut.isFinished(at: Animation.defaultDuration))
        #expect(!Animation.easeInOut.isFinished(at: Animation.defaultDuration - 0.001))
    }

    @Test("A zero-duration animation is instant, not divided by zero")
    func zeroDurationIsInstant() {
        let animation = Animation.linear(duration: 0)
        #expect(animation.fraction(at: 0) == 0)
        #expect(animation.fraction(at: 0.001) == 1)
        #expect(animation.totalDuration == 0)
    }

    @Test("Nonsense arguments are clamped rather than trapped")
    func degenerateArgumentsAreClamped() {
        // An animation is decoration: taking the app down because a duration
        // came out of a calculation as -1 is never the right answer.
        #expect(Animation.linear(duration: -1).totalDuration == 0)
        #expect(Animation.linear(duration: 1).speed(0).effectivePassDuration == 1)
        #expect(Animation.linear(duration: 1).speed(-2).effectivePassDuration == 1)
        #expect(Animation.linear(duration: 1).delay(-5).effectiveDelay == 0)
        #expect(Animation.linear(duration: 1).repeatCount(0).totalDuration == 1)
        #expect(Animation.spring(duration: 0.5, bounce: 9).totalDuration != nil)
        #expect(Animation.spring(duration: 0, bounce: 0).fraction(at: 1) == 1)
    }

    @Test("Animations compare and hash by what they describe")
    func equatableAndHashable() {
        #expect(Animation.easeInOut == Animation.easeInOut(duration: Animation.defaultDuration))
        #expect(Animation.easeInOut != Animation.easeIn)
        #expect(Animation.linear(duration: 1) != Animation.linear(duration: 2))
        #expect(Animation.linear.delay(1) != Animation.linear)
        #expect(
            Set([Animation.easeInOut, .easeInOut, .linear]).count == 2,
            "equal animations must hash together")
    }
}
