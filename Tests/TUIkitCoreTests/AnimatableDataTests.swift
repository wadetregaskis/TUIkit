//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableDataTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Animatable data")
struct AnimatableDataTests {

    @Test("Interpolation is start + (end − start) × amount")
    func interpolationIsLinear() {
        #expect(0.0.interpolated(towards: 10, amount: 0) == 0)
        #expect(0.0.interpolated(towards: 10, amount: 0.25) == 2.5)
        #expect(0.0.interpolated(towards: 10, amount: 1) == 10)
        #expect((-4.0).interpolated(towards: 4, amount: 0.5) == 0)
    }

    @Test("Interpolation is not clamped, because a spring overshoots")
    func interpolationPassesTheTarget() {
        // A spring's fraction goes above 1 while it is past its target and on
        // the way back. Clamping here would flatten every overshoot into a
        // stop, which is the whole visible difference between a spring and an
        // ease.
        #expect(0.0.interpolated(towards: 10, amount: 1.1) == 11)
        #expect(0.0.interpolated(towards: 10, amount: -0.1) == -1)
    }

    @Test("A pair interpolates componentwise")
    func pairsInterpolate() {
        let start = AnimatablePair(0.0, 100.0)
        let end = AnimatablePair(10.0, 0.0)
        let middle = start.interpolated(towards: end, amount: 0.5)
        #expect(middle.first == 5)
        #expect(middle.second == 50)
    }

    @Test("A pair's arithmetic is componentwise and its zero is both zeros")
    func pairArithmetic() {
        let a = AnimatablePair(1.0, 2.0)
        let b = AnimatablePair(10.0, 20.0)
        #expect(a + b == AnimatablePair(11.0, 22.0))
        #expect(b - a == AnimatablePair(9.0, 18.0))
        #expect(a.scaled(by: 3) == AnimatablePair(3.0, 6.0))
        #expect(AnimatablePair<Double, Double>.zero == AnimatablePair(0.0, 0.0))
        var accumulated = a
        accumulated += b
        accumulated -= a
        #expect(accumulated == b)
    }

    @Test("Magnitude is the squared length, so a spring can ask if it arrived")
    func magnitudeIsSquared() {
        #expect(3.0.magnitudeSquared == 9)
        #expect((-3.0).magnitudeSquared == 9)
        #expect(AnimatablePair(3.0, 4.0).magnitudeSquared == 25)
        #expect(AnimatablePair(AnimatablePair(1.0, 2.0), 2.0).magnitudeSquared == 9)
        #expect(EmptyAnimatableData().magnitudeSquared == 0)
    }

    @Test("Floats animate too, at their own precision")
    func floatConforms() {
        var value: Float = 0
        value.interpolate(towards: 8, amount: 0.25)
        #expect(value == 2)
        #expect(Float(3).magnitudeSquared == 9)
    }

    @Test("Empty animatable data absorbs everything and never moves")
    func emptyIsInert() {
        var empty = EmptyAnimatableData()
        empty += EmptyAnimatableData()
        empty.scale(by: 99)
        empty.interpolate(towards: EmptyAnimatableData(), amount: 0.5)
        #expect(empty == EmptyAnimatableData.zero)
    }

    /// A view that nominates one continuous thing about itself.
    private struct Bar: Animatable {
        var fraction: Double
        var animatableData: Double {
            get { fraction }
            set { fraction = newValue }
        }
    }

    /// A type that wants to know an animation is running but has nothing to
    /// interpolate — the `EmptyAnimatableData` default is what makes this
    /// declaration a one-liner.
    private struct Flash: Animatable {
        typealias AnimatableData = EmptyAnimatableData
    }

    // `Animatable` is `@MainActor` — everything that conforms is a view, and
    // views are — so the two tests that touch a conformance say so.
    @MainActor
    @Test("Animatable is a two-way window onto the view's own property")
    func animatableDataWritesBack() {
        var bar = Bar(fraction: 0)
        bar.animatableData = 0.5
        #expect(bar.fraction == 0.5)
        #expect(bar.animatableData == 0.5)
    }

    @MainActor
    @Test("A type with nothing to animate still conforms, in one line")
    func emptyConformanceNeedsNoBody() {
        var flash = Flash()
        flash.animatableData = EmptyAnimatableData()
        #expect(flash.animatableData == EmptyAnimatableData())
    }
}
