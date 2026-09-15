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
    /// half, the focus pulse's frame and cycle, each indeterminate preset's bar
    /// frame and pass at two widths, the standard frame and the focus clock's floor, a
    /// toast fade's frame and longest sleep, and how often the run loop renders a view
    /// animation, a drag's lift and its walk home.
    static let durations: [StandardAnimationDuration] =
        spinnerDurations + cursorDurations + barDurations + clockDurations + notificationDurations
        + loopDurations

    /// The renders the run loop asks the scheduler for on its own behalf, each a lattice
    /// of whole ticks.
    private static let loopDurations: [StandardAnimationDuration] = [
        ("viewAnimationFrame", AnimationRequest.viewAnimations), ("dragLiftFrame", .dragLift),
        ("dragReturnFrame", .dragReturn),
    ].map { StandardAnimationDuration(name: $0.0, seconds: AnimationClock.seconds(forTicks: $0.1.frameTicks ?? 0)) }

    /// A toast fade's frame, as the wakes its animation task plans while a fade is
    /// drawing are spaced: thirty of them from a frame's instant, over their count.
    /// Thirty, so a gap's nanosecond rounding cannot move the mean off a whole tick. And
    /// the longest the task sleeps when nothing is due.
    private static let notificationDurations: [StandardAnimationDuration] = {
        let start = AnimationClock.nanoseconds(atTick: 600)
        var wakes = [NotificationTiming.nextWakeNanos(after: start, due: 0)]
        for _ in 0..<30 { wakes.append(NotificationTiming.nextWakeNanos(after: wakes[wakes.count - 1], due: 0)) }
        return [
            StandardAnimationDuration(
                name: "notificationFadeFrame", seconds: Double(wakes[30] - wakes[0]) / 30 / 1_000_000_000),
            StandardAnimationDuration(name: "notificationLongestSleep", seconds: NotificationTiming.longestSleep),
        ]
    }()

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
            StandardAnimationDuration(name: "blinkHalf", seconds: AnimationClock.seconds(forTicks: blink.timing.frameTicks)),
            StandardAnimationDuration(name: "pulseFrame", seconds: AnimationClock.seconds(forTicks: pulse.timing.frameTicks)),
            StandardAnimationDuration(
                name: "pulseCycle", seconds: AnimationClock.seconds(forTicks: pulse.frameCount * pulse.timing.frameTicks)),
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
                    StandardAnimationDuration(
                        name: "\(name)BarFrame(\(width))", seconds: AnimationClock.seconds(forTicks: cycle.frameTicks)),
                    StandardAnimationDuration(
                        name: "\(name)BarPass(\(width))",
                        seconds: AnimationClock.seconds(forTicks: cycle.frames.count * cycle.frameTicks)),
                ]
            }
        }
    }()

    /// The frame a view that reads the phase as it renders is re-rendered at, which is
    /// also every run's default frame, and the lattice the focus-relative clock's zero is
    /// floored to, so the caret's and the breath's steps land where other runs' do.
    private static let clockDurations: [StandardAnimationDuration] = [
        StandardAnimationDuration(
            name: "standardFrame", seconds: AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)),
        StandardAnimationDuration(
            name: "focusEpochFloor", seconds: Double(CursorTimer.standardFrameNanos) / 1_000_000_000),
    ]

    /// Within 1e-9 of a tick, because a duration is a binary `Double`: 0.1 s is
    /// 6.000000000000001 ticks.
    @Test("Every standard duration is a whole number of 1/60 s ticks, and at least two", arguments: durations)
    func isWholeTicks(_ duration: StandardAnimationDuration) {
        let ticks = duration.seconds * Double(AnimationClock.ticksPerSecond)
        let isWholeTicks = abs(ticks - ticks.rounded()) <= 1e-9 && ticks.rounded() >= 2
        #expect(isWholeTicks, "\(duration.name) is \(ticks) ticks")
    }
}
