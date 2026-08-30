//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChannelCurveTests.swift
//
//  A recolouring that answers each channel on its own terms — the shape a tone
//  curve cannot take, and the one `.inverted` was a Bool for want of.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("Per-channel curves")
struct ChannelCurveTests {

    private typealias Ramp = ASCIIToneCurve.Ramp

    @Test("A ramp interpolates between its points and holds flat outside them")
    func rampInterpolatesAndHolds() {
        let ramp: Ramp = [(0.25, 0.5), (0.75, 1.0)]
        #expect(ramp.value(at: 0) == 0.5, "below the first point it holds")
        #expect(ramp.value(at: 0.25) == 0.5)
        #expect(abs(ramp.value(at: 0.5) - 0.75) < 1e-12)
        #expect(ramp.value(at: 1) == 1.0, "above the last point it holds")
    }

    @Test("Points sort themselves, however they were written")
    func pointsSort() {
        let ramp: Ramp = [(1, 0), (0, 1), (0.5, 0.5)]
        #expect(ramp.points.map(\.input) == [0, 0.5, 1])
    }

    @Test("A ramp of fewer than two points changes nothing")
    func shortRampIsInert() {
        // Spelled out: a bare `Ramp([])` is ambiguous between the two
        // initializers, exactly as `ASCIIToneCurve([])` is — `.identity` is
        // the spelling for "changes nothing" on both.
        #expect(Ramp([(Double, Double)]()).isIdentity)
        #expect(Ramp([(0.5, 0.9)]).isIdentity)
        #expect(Ramp.identity.isIdentity)
        #expect(!Ramp.inverted.isIdentity)
    }

    @Test("`.inverted` is three descending ramps, exact on every one of 256 levels")
    func invertedIsExact() {
        // The reason to check all 256 rather than a sample: the old
        // implementation was integer arithmetic (`255 &- v`) and the new one is
        // a linear interpolation through Doubles. If those disagree anywhere,
        // a negative stops being its own inverse — which is a property the
        // suite next door asserts and this is the arithmetic behind it.
        for value in UInt8.min...UInt8.max {
            let pixel = RGBA(r: value, g: value, b: value, a: 255)
            let out = ASCIIToneCurve.inverted.apply(to: pixel)
            #expect(out.r == 255 &- value, "level \(value) came back \(out.r)")
        }
    }

    @Test("A channel curve leaves the channels it does not name alone")
    func untouchedChannelsSurvive() {
        // The whole difference from a tone curve: this cannot be said as a
        // function of luminance, because two pixels of the SAME tone and
        // different hue must come out differently.
        let curve = ASCIIToneCurve.channels(
            red: [(0, 0.5), (1, 1)], green: .identity, blue: .identity)
        let pixel = RGBA(r: 0, g: 120, b: 240, a: 255)
        let out = curve.apply(to: pixel)
        #expect(out.r == 128, "red lifted: \(out)")
        #expect(out.g == 120, "green untouched: \(out)")
        #expect(out.b == 240, "blue untouched: \(out)")
        #expect(out.a == 255)
    }

    @Test("Two pixels of the same tone can come out different colours")
    func toneIsNotTheOnlyInput() {
        // A tone curve gives these two the same answer by construction. That is
        // the property being escaped, so it is worth asserting rather than
        // assuming.
        let curve = ASCIIToneCurve.channels(red: .inverted, green: .identity, blue: .identity)
        let left = RGBA(r: 200, g: 10, b: 10, a: 255)
        let right = RGBA(r: 10, g: 200, b: 10, a: 255)
        #expect(curve.apply(to: left) != curve.apply(to: right))
    }

    @Test("An all-identity channel curve is inert, so the converter skips it")
    func identityChannelsAreInert() {
        #expect(ASCIIToneCurve(ASCIIToneCurve.Channels.identity).isIdentity)
        #expect(!ASCIIToneCurve.inverted.isIdentity)
    }

    @Test("The two shapes are not equal to each other")
    func shapesAreDistinct() {
        #expect(ASCIIToneCurve.inverted != ASCIIToneCurve.identity)
        #expect(ASCIIToneCurve([(Color.rgb(0, 0, 0), Color.rgb(255, 255, 255))]) != .inverted)
    }

    @Test("`color(atTone:)` reads a channel curve as it reads a tone one")
    func toneProbeWorksForChannels() {
        // The editors draw with this, so it has to answer for both shapes.
        let curve = ASCIIToneCurve.inverted
        #expect(curve.color(atTone: 0).rgbComponents! == (red: 255, green: 255, blue: 255))
        #expect(curve.color(atTone: 1).rgbComponents! == (red: 0, green: 0, blue: 0))
    }
}
