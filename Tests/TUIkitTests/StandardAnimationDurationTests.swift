//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StandardAnimationDurationTests.swift
//
//  The spec the framework's own animation durations are meant to meet: every one
//  is a whole number of 1/60 s ticks, and at least two of them. A terminal's paint
//  is shown on a display that refreshes 60 times a second, so a frame of any other
//  length is held for an uneven number of refreshes, and two indicators whose
//  frames are not whole ticks change on different refreshes and wake the run loop
//  apart. Two ticks is the shortest default, so no default on its own asks for
//  every refresh.
//
//  Most spinner intervals do not meet it yet. They were chosen one style at a time,
//  and move onto whole ticks in a later commit. Until then those entries are on
//  `awaitingExperiment` and run as known issues. A known issue that stops failing
//  fails the test, so the commit that changes a duration has to take it off the
//  list, and the list cannot go stale.
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
    /// half, the focus pulse's frame and cycle, and each indeterminate preset's bar
    /// frame and pass at two widths.
    static let durations: [StandardAnimationDuration] =
        spinnerDurations + cursorDurations + barDurations

    private static let spinnerDurations: [StandardAnimationDuration] = [
        ("dots", SpinnerStyle.dots), ("line", .line), ("dancingLine", .dancingLine),
        ("bouncing", .bouncing), ("pie", .pie), ("beachball", .beachball), ("box", .box),
        ("curve", .curve), ("column", .column), ("bar", .bar), ("shade", .shade),
        ("blockWedge", .blockWedge), ("spinningTriangle", .spinningTriangle),
        ("moon", .moon), ("earth", .earth), ("clock", .clock), ("custom", .custom("ab")),
    ].map { StandardAnimationDuration(name: $0.0, seconds: $0.1.interval) }

    /// The standard blink's half, and the standard pulse's frame and cycle, as those
    /// cycles are laid out.
    private static let cursorDurations: [StandardAnimationDuration] = {
        let blink = CursorTimer.cycleLayout(of: .blink, speed: .standard)
        let pulse = CursorTimer.cycleLayout(of: .pulse, speed: .standard)
        return [
            StandardAnimationDuration(name: "blinkHalf", seconds: blink.timing.frameDuration),
            StandardAnimationDuration(name: "pulseFrame", seconds: pulse.timing.frameDuration),
            StandardAnimationDuration(
                name: "pulseCycle", seconds: Double(pulse.frameCount) * pulse.timing.frameDuration),
        ]
    }()

    /// Each preset's frame and whole pass, as the cycle a bar of 20 and of 36 cells
    /// is built with: how long a frame is shown, and its frame count times that. Both
    /// widths, because what a bar steps through can depend on how wide it is.
    private static let barDurations: [StandardAnimationDuration] = {
        let presets: [(String, IndeterminateStyle)] = [
            ("sweep", .sweep), ("barberPole", .barberPole), ("pulse", .pulse),
            ("knightRider", .knightRider), ("gradient", .gradient()),
        ]
        return presets.flatMap { name, style in
            [20, 36].flatMap { width in
                let cycle = IndeterminateRenderer.cycle(
                    width: width, style: style, fillColor: .green, backgroundColor: .blue,
                    accentColor: .red, palette: SystemPalette.green, speed: .standard)
                return [
                    StandardAnimationDuration(name: "\(name)BarFrame(\(width))", seconds: cycle.frameDuration),
                    StandardAnimationDuration(
                        name: "\(name)BarPass(\(width))",
                        seconds: Double(cycle.frames.count) * cycle.frameDuration),
                ]
            }
        }
    }()

    /// The entries whose durations are not yet whole ticks, and will not be until the
    /// spinner defaults move onto them.
    static let awaitingExperiment: Set<String> = [
        "dots", "line", "dancingLine", "pie", "beachball", "box", "curve", "column", "bar",
        "shade", "blockWedge", "spinningTriangle", "moon", "clock", "custom",
    ]

    /// Within 1e-9 of a tick, because a duration is a binary `Double`: 0.1 s is
    /// 6.000000000000001 ticks.
    @Test("Every standard duration is a whole number of 1/60 s ticks, and at least two", arguments: durations)
    func isWholeTicks(_ duration: StandardAnimationDuration) {
        let ticks = duration.seconds * Double(AnimationClock.ticksPerSecond)
        let isWholeTicks = abs(ticks - ticks.rounded()) <= 1e-9 && ticks.rounded() >= 2
        if Self.awaitingExperiment.contains(duration.name) {
            withKnownIssue("spinner defaults are not whole ticks yet") {
                #expect(isWholeTicks, "\(duration.name) is \(ticks) ticks")
            }
        } else {
            #expect(isWholeTicks, "\(duration.name) is \(ticks) ticks")
        }
    }

    @Test("Every name awaiting the experiment is a duration the spec checks")
    func awaitingListNamesRealEntries() {
        let names = Set(Self.durations.map(\.name))
        #expect(Self.awaitingExperiment.subtracting(names).isEmpty)
        #expect(names.count == Self.durations.count, "two durations share a name")
    }
}
