//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientTests.swift
//
//  What a stop list means. Every expectation here was MEASURED against real
//  SwiftUI first (ImageRenderer, pixels read back — see
//  `Documentation/Gradients where a colour is accepted.md` §1), because all
//  three of these are behaviours a reasonable implementation gets wrong in a
//  reasonable-looking way: sorting the stops on the way in, clamping locations
//  to 0…1, or averaging a duplicate location instead of stepping at it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Gradient")
struct GradientTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)
    private let green = Color.rgb(0, 255, 0)

    private func rgb(_ colour: Color) -> (red: UInt8, green: UInt8, blue: UInt8) {
        colour.rgbComponents ?? (0, 0, 0)
    }

    // MARK: - Construction

    @Test("`colors:` spaces the stops evenly across 0…1")
    func evenSpacing() {
        let gradient = Gradient(colors: [red, green, blue])
        #expect(gradient.stops.map(\.location) == [0, 0.5, 1])
        #expect(gradient.stops.map(\.color) == [red, green, blue])
    }

    @Test("One colour is a flat ramp; none is black rather than a trap")
    func degenerateRamps() {
        #expect(Gradient(colors: [red]).color(at: 0.7) == red)
        #expect(Gradient(colors: []).color(at: 0.5) == .rgb(0, 0, 0))
        #expect(Gradient(stops: []).sampled(count: 3).count == 3)
    }

    @Test("The stops are kept as written — the order is not what a gradient means")
    func stopsAreNotRewritten() {
        let written = [
            Gradient.Stop(color: red, location: 0.8), Gradient.Stop(color: blue, location: 0.2),
        ]
        #expect(Gradient(stops: written).stops == written, "a round trip through the type is lossy")
    }

    // MARK: - The three measured semantics

    /// SwiftUI renders `red@0.8, blue@0.2` as a blue-to-red ramp.
    @Test("An unsorted stop list reads as if sorted")
    func unsortedReadsAsSorted() {
        let scrambled = Gradient(stops: [
            .init(color: red, location: 0.8), .init(color: blue, location: 0.2),
        ])
        let ordered = Gradient(stops: [
            .init(color: blue, location: 0.2), .init(color: red, location: 0.8),
        ])
        #expect(scrambled.color(at: 0) == blue)
        #expect(scrambled.color(at: 1) == red)
        for step in 0...20 {
            let phase = Double(step) / 20
            #expect(scrambled.color(at: phase) == ordered.color(at: phase), "at \(phase)")
        }
    }

    /// Two stops at one location step; they do not blend. This is how a stop
    /// list draws a stripe, and SwiftUI shows the step within one pixel.
    @Test("Two stops at one location make a hard edge, later stop winning")
    func duplicateLocationsStep() {
        let gradient = Gradient(stops: [
            .init(color: red, location: 0), .init(color: red, location: 0.5),
            .init(color: blue, location: 0.5), .init(color: blue, location: 1),
        ])
        #expect(gradient.color(at: 0.49) == red)
        #expect(gradient.color(at: 0.5) == blue, "the edge did not step at its own location")
        #expect(gradient.color(at: 0.51) == blue)
        // And nothing in between is a blend of the two.
        for step in 0...100 {
            let colour = rgb(gradient.color(at: Double(step) / 100))
            #expect(
                colour == (255, 0, 0) || colour == (0, 0, 255),
                "blended across a hard edge at \(Double(step) / 100): \(colour)")
        }
    }

    /// Locations outside 0…1 crop the ramp rather than being clamped: stops at
    /// −0.5 and 1.5 show its middle half across 0…1. Clamping would silently
    /// turn a deliberate crop into a different gradient.
    @Test("Locations outside 0…1 are evaluated through, not clamped")
    func outOfRangeLocationsCrop() {
        let cropped = Gradient(stops: [
            .init(color: red, location: -0.5), .init(color: blue, location: 1.5),
        ])
        let full = Gradient(colors: [red, blue])
        #expect(rgb(cropped.color(at: 0)) == rgb(full.color(at: 0.25)))
        #expect(rgb(cropped.color(at: 0.5)) == rgb(full.color(at: 0.5)))
        #expect(rgb(cropped.color(at: 1)) == rgb(full.color(at: 0.75)))
        // Which is to say: neither end of the visible range is an end colour.
        #expect(cropped.color(at: 0) != red)
        #expect(cropped.color(at: 1) != blue)
    }

    // MARK: - Evaluation

    @Test("Outside the stops' own range the end colours hold")
    func endsHold() {
        let gradient = Gradient(stops: [
            .init(color: red, location: 0.25), .init(color: blue, location: 0.75),
        ])
        #expect(gradient.color(at: 0) == red)
        #expect(gradient.color(at: 0.25) == red)
        #expect(gradient.color(at: 0.75) == blue)
        #expect(gradient.color(at: 1) == blue)
        #expect(gradient.color(at: -3) == red)
        #expect(gradient.color(at: 4) == blue)
    }

    /// The `[Color]` interpolation this replaces is still in the tree while the
    /// four gradient-taking sites are converted, so the two must not disagree
    /// visibly in the meantime.
    ///
    /// **To within one unit per channel**, and that is not slack for its own
    /// sake: the two compute the same quantity by different routes —
    /// `interpolate` scales the phase up by the segment count and subtracts the
    /// segment index, while a positioned ramp subtracts the segment's own
    /// location and divides by its span, which reintroduces the rounding the
    /// first route never made. Three of forty-one sample points differ by one
    /// in one channel. Below the 6×6×6 cube's resolution, and below a terminal
    /// cell's, so nothing on screen can tell them apart.
    @Test("An evenly-spaced gradient agrees with the interpolation it replaces")
    func agreesWithColorInterpolate() {
        let colours = [red, green, blue, .rgb(255, 200, 0)]
        let gradient = Gradient(colors: colours)
        for step in 0...40 {
            let phase = Double(step) / 40
            let mine = rgb(gradient.color(at: phase))
            let theirs = rgb(Color.interpolate(stops: colours, phase: phase))
            let apart = max(
                abs(Int(mine.red) - Int(theirs.red)),
                max(abs(Int(mine.green) - Int(theirs.green)), abs(Int(mine.blue) - Int(theirs.blue))))
            #expect(apart <= 1, "at \(phase): \(mine) vs \(theirs)")
        }
    }

    /// A gradient written in order must not pay for a sort — this is consulted
    /// once per painted cell.
    @Test("Stops already in order are not re-ordered")
    func sortedStopsAreNotCopied() {
        let gradient = Gradient(colors: [red, green, blue])
        #expect(gradient.ordered == gradient.stops)
        let scrambled = Gradient(stops: [
            .init(color: red, location: 1), .init(color: blue, location: 0),
        ])
        #expect(scrambled.ordered.map(\.location) == [0, 1])
    }

    @Test("`sampled(count:)` walks 0…1 inclusive")
    func sampling() {
        let gradient = Gradient(colors: [red, blue])
        let ramp = gradient.sampled(count: 5)
        #expect(ramp.count == 5)
        #expect(ramp.first == red)
        #expect(ramp.last == blue)
        #expect(gradient.sampled(count: 1) == [red], "one cell takes the start")
        #expect(gradient.sampled(count: 0).isEmpty)
    }

    // MARK: - Collapsing

    @Test("The representative is the midpoint, not an end")
    func representativeIsTheMiddle() {
        let gradient = Gradient(colors: [red, blue])
        #expect(gradient.representative == gradient.color(at: 0.5))
        #expect(gradient.representative != red)
        #expect(gradient.representative != blue)
    }

    /// The floor has to be applied to the stop that is hardest to read, not to
    /// the midpoint — flooring the midpoint leaves the ends below the floor.
    @Test("The least-contrasting stop is the one a floor must answer for")
    func leastContrastingPicksTheWorstStop() {
        let onBlack = Gradient(colors: [.rgb(255, 255, 255), .rgb(20, 20, 20)])
        #expect(onBlack.leastContrasting(against: .rgb(0, 0, 0)) == .rgb(20, 20, 20))
        let onWhite = Gradient(colors: [.rgb(255, 255, 255), .rgb(20, 20, 20)])
        #expect(onWhite.leastContrasting(against: .rgb(255, 255, 255)) == .rgb(255, 255, 255))
        #expect(Gradient(colors: []).leastContrasting(against: .rgb(0, 0, 0)) == .rgb(0, 0, 0))
    }
}
