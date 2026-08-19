//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationCurveTests.swift
//
//  What an animation's timing has to get right before anything is drawn with
//  it. The curves are the one part of the animation machinery with a
//  closed-form answer to check against, so they are checked against it — the
//  rest of the system can only be tested by what it renders.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Animation curves")
struct AnimationCurveTests {

    // MARK: - Bézier

    @Test("Every curve starts at 0 and ends at 1")
    func endpointsArePinned() {
        for animation in [Animation.linear, .easeIn, .easeOut, .easeInOut, .default] {
            #expect(animation.fraction(at: 0) == 0)
            #expect(animation.fraction(at: animation.passDuration) == 1)
            // And past the end it STAYS there — a finished animation that
            // wrapped back to 0 would flash the old value at the last frame.
            #expect(animation.fraction(at: animation.passDuration * 10) == 1)
        }
    }

    @Test("A linear curve is its own fraction, EXACTLY")
    func linearIsIdentity() {
        // Exactly, not nearly. A curve solved numerically lands a rounding
        // error either side of its answer, and that is enough to put a value
        // sitting on a cell boundary on the wrong side of it: a bar animating
        // linearly to full width came out one cell short at three-quarters,
        // because 0.7499999 rounds to 7 cells and 0.75 rounds to 8.
        let animation = Animation.linear(duration: 1)
        for step in 0...100 {
            let t = Double(step) / 100
            #expect(animation.fraction(at: t) == t, "at \(t)")
        }
        // Any curve whose control points sit on the diagonal is the identity,
        // however it was spelled.
        #expect(Animation.timingCurve(0.25, 0.25, 0.9, 0.9, duration: 1).fraction(at: 0.4) == 0.4)
    }

    @Test("Ease-in starts slower than linear; ease-out starts faster")
    func easingLeansTheRightWay() {
        let quarter = 0.25
        let linear = Animation.linear(duration: 1).fraction(at: quarter)
        #expect(Animation.easeIn(duration: 1).fraction(at: quarter) < linear)
        #expect(Animation.easeOut(duration: 1).fraction(at: quarter) > linear)
        // Ease-in-out is symmetric about its midpoint.
        let easeInOut = Animation.easeInOut(duration: 1)
        #expect(abs(easeInOut.fraction(at: 0.5) - 0.5) < 1e-6)
        for step in 1...9 {
            let t = Double(step) / 10
            let mirrored = 1 - easeInOut.fraction(at: 1 - t)
            #expect(abs(easeInOut.fraction(at: t) - mirrored) < 1e-6, "at \(t)")
        }
    }

    @Test("Every curve is monotonic between its endpoints")
    func bezierCurvesDoNotBackUp() {
        // Not true of springs, which is the point of them; true of every
        // timing curve, and a curve that went backwards would show a value
        // move away from its target mid-animation.
        for animation in [Animation.linear, .easeIn, .easeOut, .easeInOut] {
            var previous = -1.0
            for step in 0...100 {
                let value = animation.fraction(
                    at: animation.passDuration * Double(step) / 100)
                #expect(value >= previous, "\(animation) went backwards at \(step)")
                previous = value
            }
        }
    }

    @Test("A custom timing curve solves for y at x, not at the parameter")
    func timingCurveSolvesForX() {
        // A cubic Bézier is parametric: at x = 0.5 the PARAMETER is not 0.5
        // unless the x control points are symmetric. This one's are not, so a
        // naive `bezier(0.5)` would answer 0.5 and the real answer is not.
        let animation = Animation.timingCurve(0.9, 0.0, 1.0, 0.1, duration: 1)
        let midpoint = animation.fraction(at: 0.5)
        #expect(midpoint > 0 && midpoint < 0.5, "got \(midpoint)")
        // Whatever it is, it must be reproducible and monotonic.
        #expect(animation.fraction(at: 0.4) < midpoint)
        #expect(animation.fraction(at: 0.6) > midpoint)
    }

    @Test("A degenerate timing curve does not diverge")
    func degenerateCurveIsBounded() {
        // Control points at the ends flatten the slope, which is where
        // Newton–Raphson steps to infinity and the bisection fallback earns
        // its place.
        let animation = Animation.timingCurve(0, 1, 1, 0, duration: 1)
        for step in 0...20 {
            let value = animation.fraction(at: Double(step) / 20)
            #expect(value.isFinite && value >= 0 && value <= 1, "at \(step): \(value)")
        }
    }

    // MARK: - Springs

    @Test("A bouncy spring overshoots; a smooth one does not")
    func bounceOvershoots() {
        let bouncy = Animation.spring(duration: 0.5, bounce: 0.5)
        let smooth = Animation.spring(duration: 0.5, bounce: 0)
        var bouncyPeak = 0.0
        var smoothPeak = 0.0
        for step in 0...200 {
            let t = Double(step) / 200 * 2
            bouncyPeak = max(bouncyPeak, bouncy.fraction(at: t))
            smoothPeak = max(smoothPeak, smooth.fraction(at: t))
        }
        #expect(bouncyPeak > 1.02, "a bouncy spring must pass its target: \(bouncyPeak)")
        #expect(smoothPeak <= 1.0001, "a smooth spring must not: \(smoothPeak)")
    }

    @Test("Every spring settles, and settles at its target")
    func springsSettle() {
        for bounce in [-0.9, -0.5, 0, 0.3, 0.6, 0.9] {
            let animation = Animation.spring(duration: 0.5, bounce: bounce)
            let settled = animation.passDuration
            #expect(settled > 0 && settled < 10, "bounce \(bounce) settles at \(settled)")
            // At the settling time the value is at the target, and it does not
            // leave again — the envelope only decays.
            for multiple in [1.0, 1.5, 2.0] {
                let value = AnimationCurve.springValue(
                    at: settled * multiple,
                    omega: springParameters(animation).omega,
                    zeta: springParameters(animation).zeta)
                #expect(abs(value - 1) < 0.005, "bounce \(bounce) at ×\(multiple): \(value)")
            }
        }
    }

    @Test("A critically damped spring is the fastest with no overshoot")
    func criticalDampingIsTheBoundary() {
        // `bounce: 0` maps to ζ = 1 exactly, which is the analytic boundary
        // where both neighbouring formulas divide by a vanishing √|1 − ζ²|.
        let critical = Animation.spring(duration: 0.5, bounce: 0)
        for step in 0...100 {
            let value = critical.fraction(at: Double(step) / 100 * critical.passDuration)
            #expect(value.isFinite, "step \(step) produced \(value)")
            #expect(value <= 1.0001, "overshot at step \(step): \(value)")
        }
        // Just either side of the boundary must agree with it closely — a
        // discontinuity there is the bug the band exists to prevent.
        let below = Animation.spring(duration: 0.5, bounce: 0.0005)
        let above = Animation.spring(duration: 0.5, bounce: -0.0005)
        for step in 1...20 {
            let t = Double(step) / 20 * 0.5
            #expect(abs(below.fraction(at: t) - critical.fraction(at: t)) < 0.01, "at \(t)")
            #expect(abs(above.fraction(at: t) - critical.fraction(at: t)) < 0.01, "at \(t)")
        }
    }

    /// Recovers a spring's parameters for tests that need to evaluate it past
    /// the settling point the public `fraction(at:)` clamps to.
    private func springParameters(_ animation: Animation) -> (omega: Double, zeta: Double) {
        guard case .spring(let omega, let zeta) = animation.curve else {
            Issue.record("not a spring")
            return (0, 0)
        }
        return (omega, zeta)
    }
}
