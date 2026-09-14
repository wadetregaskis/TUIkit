//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StandardAnimationDurationTests.swift
//
//  The spec the framework's own indicator durations are meant to meet: every one
//  is a whole number of `AnimationClock.baseTick`s, so indicators on one screen
//  step together and the run loop wakes once for all of them.
//
//  Most of today's durations do not meet it. They were chosen one style at a
//  time, before there was a base tick, and the new ones wait on the owner's
//  experiment with the Spinners page's speed control. Until then those entries
//  are on `awaitingExperiment` and run as known issues. A known issue that stops
//  failing fails the test, so the commit that changes a duration has to take it
//  off the list, and the list cannot go stale.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// One duration the framework picks on its own, by the name the spec tracks it by.
struct StandardAnimationDuration: Sendable, CustomTestStringConvertible {
    let name: String
    let seconds: Double

    var testDescription: String { name }
}

@Suite("Standard animation durations")
struct StandardAnimationDurationTests {
    /// Every standard duration: each spinner style's interval, the caret blink's
    /// half, the focus pulse's frame and cycle, and each indeterminate preset's
    /// bar frame.
    static let durations: [StandardAnimationDuration] =
        spinnerDurations + cursorDurations + barFrameDurations

    private static let spinnerDurations: [StandardAnimationDuration] = [
        ("dots", SpinnerStyle.dots), ("line", .line), ("dancingLine", .dancingLine),
        ("bouncing", .bouncing), ("pie", .pie), ("beachball", .beachball), ("box", .box),
        ("curve", .curve), ("column", .column), ("bar", .bar), ("shade", .shade),
        ("blockWedge", .blockWedge), ("spinningTriangle", .spinningTriangle),
        ("moon", .moon), ("earth", .earth), ("clock", .clock), ("custom", .custom("ab")),
    ].map { StandardAnimationDuration(name: $0.0, seconds: $0.1.interval) }

    /// The caret's standard blink, its pulse's frame (one cursor tick), and its
    /// pulse's cycle.
    private static let cursorDurations: [StandardAnimationDuration] = [
        StandardAnimationDuration(
            name: "blinkHalf", seconds: Double(TextCursorStyle.Speed.regular.blinkCycleMs) / 2 / 1000),
        StandardAnimationDuration(name: "pulseFrame", seconds: AnimationClock.cursor.tickInterval),
        StandardAnimationDuration(
            name: "pulseCycle", seconds: Double(TextCursorStyle.Speed.regular.pulseCycleMs) / 1000),
    ]

    private static let barFrameDurations: [StandardAnimationDuration] = [
        ("sweep", IndeterminateStyle.sweep), ("barberPole", .barberPole), ("pulse", .pulse),
        ("knightRider", .knightRider), ("gradient", .gradient()),
    ].map {
        StandardAnimationDuration(
            name: "\($0.0)BarFrame",
            seconds: IndeterminateRenderer.period(of: $0.1)
                / Double(IndeterminateRenderer.frameCount(of: $0.1)))
    }

    /// The entries whose durations are not yet on the lattice, and will not be
    /// until the owner picks new defaults.
    static let awaitingExperiment: Set<String> = [
        "dots", "line", "dancingLine", "pie", "beachball", "curve", "column", "bar", "shade",
        "blockWedge", "spinningTriangle", "moon", "clock", "custom",
        "sweepBarFrame", "barberPoleBarFrame", "pulseBarFrame", "knightRiderBarFrame",
        "gradientBarFrame",
    ]

    @Test("Every standard duration is a whole number of base ticks", arguments: durations)
    func isWholeBaseTicks(_ duration: StandardAnimationDuration) {
        let tick = AnimationClock.nanoseconds(AnimationClock.baseTick)
        let nanos = AnimationClock.nanoseconds(duration.seconds)
        if Self.awaitingExperiment.contains(duration.name) {
            withKnownIssue("defaults await the Spinners-page experiment") {
                #expect(nanos.isMultiple(of: tick), "\(duration.name) is \(nanos) ns")
            }
        } else {
            #expect(nanos.isMultiple(of: tick), "\(duration.name) is \(nanos) ns")
        }
    }

    @Test("Every name awaiting the experiment is a duration the spec checks")
    func awaitingListNamesRealEntries() {
        let names = Set(Self.durations.map(\.name))
        #expect(Self.awaitingExperiment.subtracting(names).isEmpty)
        #expect(names.count == Self.durations.count, "two durations share a name")
    }
}
