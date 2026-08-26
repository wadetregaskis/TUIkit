//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimelineScheduleTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The expected values here were measured against real SwiftUI on macOS 26
/// (`Tools/`-less one-off probe: build each schedule, print the first four
/// entries from a fixed reference instant), so the cases pin *observed* SwiftUI
/// behaviour rather than a reading of its documentation.
@Suite("TimelineSchedule")
struct TimelineScheduleTests {
    /// 57.25 s into a minute, so a minute-floor is visibly different from the
    /// instant itself — this is the instant the SwiftUI probe used.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_037.25)

    private func firstEntries<S: TimelineSchedule>(
        _ schedule: S, from: Date, mode: TimelineScheduleMode = .normal, count: Int
    ) -> [Double] {
        var out: [Double] = []
        for date in schedule.entries(from: from, mode: mode) {
            out.append(date.timeIntervalSinceReferenceDate)
            if out.count == count { break }
        }
        return out
    }

    // MARK: - Every minute

    @Test("everyMinute starts at the top of the minute the view is in")
    func everyMinuteFloors() {
        #expect(
            firstEntries(EveryMinuteTimelineSchedule(), from: base, count: 4)
                == [799_999_980, 800_000_040, 800_000_100, 800_000_160])
    }

    @Test("everyMinute ignores the mode")
    func everyMinuteIgnoresMode() {
        #expect(
            firstEntries(EveryMinuteTimelineSchedule(), from: base, mode: .lowFrequency, count: 4)
                == firstEntries(EveryMinuteTimelineSchedule(), from: base, count: 4))
    }

    @Test("An instant exactly on a minute boundary starts there, not a minute back")
    func everyMinuteOnTheBoundary() {
        let boundary = Date(timeIntervalSinceReferenceDate: 800_000_040)
        #expect(
            firstEntries(EveryMinuteTimelineSchedule(), from: boundary, count: 2)
                == [800_000_040, 800_000_100])
    }

    // MARK: - Periodic

    @Test("A past anchor starts at the lattice point at or before the instant asked about")
    func periodicPastAnchor() {
        let schedule = PeriodicTimelineSchedule(from: base.addingTimeInterval(-13), by: 5)
        #expect(
            firstEntries(schedule, from: base, count: 4).map { $0 - 800_000_037.25 }
                == [-3, 2, 7, 12])
    }

    @Test("A future anchor starts one interval below it, not at the lattice point below now")
    func periodicFutureAnchor() {
        // The truncation SwiftUI performs: anchored 7 s ahead with a 5 s
        // interval, asked from `base`, the sequence starts at base + 2 — not at
        // base − 3, which is where a floor would put it.
        let schedule = PeriodicTimelineSchedule(from: base.addingTimeInterval(7), by: 5)
        #expect(
            firstEntries(schedule, from: base, count: 4).map { $0 - 800_000_037.25 }
                == [2, 7, 12, 17])
    }

    @Test("Asking from the anchor itself starts at the anchor")
    func periodicFromTheAnchor() {
        let schedule = PeriodicTimelineSchedule(from: base, by: 1)
        #expect(
            firstEntries(schedule, from: base, count: 3).map { $0 - 800_000_037.25 } == [0, 1, 2])
    }

    @Test("periodic ignores the mode")
    func periodicIgnoresMode() {
        let schedule = PeriodicTimelineSchedule(from: base.addingTimeInterval(-13), by: 5)
        #expect(
            firstEntries(schedule, from: base, mode: .lowFrequency, count: 4)
                == firstEntries(schedule, from: base, count: 4))
    }

    // MARK: - Explicit

    @Test("explicit hands back exactly the dates it was given, past ones included")
    func explicitIsUnfiltered() {
        let dates = [-10.0, -3, 2, 9].map { base.addingTimeInterval($0) }
        let schedule = ExplicitTimelineSchedule(dates)
        #expect(
            firstEntries(schedule, from: base, count: 6).map { $0 - 800_000_037.25 }
                == [-10, -3, 2, 9])
    }

    @Test("explicit ignores the instant it is asked about")
    func explicitIgnoresStartDate() {
        let dates = [1.0, 2, 3].map { base.addingTimeInterval($0) }
        let schedule = ExplicitTimelineSchedule(dates)
        #expect(
            firstEntries(schedule, from: base.addingTimeInterval(1_000), count: 3)
                == firstEntries(schedule, from: base, count: 3))
    }

    @Test("An empty explicit schedule supplies nothing")
    func explicitEmpty() {
        #expect(firstEntries(ExplicitTimelineSchedule([Date]()), from: base, count: 3).isEmpty)
    }

    // MARK: - Animation

    @Test("animation starts at the instant asked about and steps by its interval")
    func animationSteps() {
        #expect(
            firstEntries(AnimationTimelineSchedule(minimumInterval: 0.5), from: base, count: 4)
                .map { $0 - 800_000_037.25 } == [0, 0.5, 1.0, 1.5])
    }

    @Test("A paused animation schedule supplies nothing")
    func animationPaused() {
        #expect(
            firstEntries(AnimationTimelineSchedule(minimumInterval: 0.5, paused: true),
                from: base, count: 3
            ).isEmpty)
    }

    @Test("A low-frequency display gets no animation entries")
    func animationLowFrequency() {
        #expect(
            firstEntries(AnimationTimelineSchedule(minimumInterval: 0.5),
                from: base, mode: .lowFrequency, count: 3
            ).isEmpty)
    }

    @Test("The default rate is the run loop's default frame rate")
    func animationDefaultRate() {
        // The tolerance is set by Double's resolution at this magnitude
        // (~2.4e-7 s at 8e8 s past the reference date), not by the schedule.
        let entries = firstEntries(AnimationTimelineSchedule(), from: base, count: 3)
        #expect(entries.count == 3)
        #expect(abs((entries[1] - entries[0]) - 1.0 / 60.0) < 1e-6)
        #expect(abs((entries[2] - entries[1]) - 1.0 / 60.0) < 1e-6)
    }

    @Test("A non-positive minimum interval means the default rate, not a stalled sequence")
    func animationZeroInterval() {
        let entries = firstEntries(AnimationTimelineSchedule(minimumInterval: 0), from: base, count: 3)
        #expect(abs((entries[1] - entries[0]) - 1.0 / 60.0) < 1e-6)
    }

    // MARK: - Factories

    @Test("The factories build the same schedules as the initialisers")
    func factories() {
        func entriesOf<S: TimelineSchedule>(_ s: S) -> [Double] {
            firstEntries(s, from: base, count: 3)
        }
        #expect(entriesOf(.everyMinute) == entriesOf(EveryMinuteTimelineSchedule()))
        #expect(
            entriesOf(.periodic(from: base, by: 5))
                == entriesOf(PeriodicTimelineSchedule(from: base, by: 5)))
        #expect(
            entriesOf(.explicit([base])) == entriesOf(ExplicitTimelineSchedule([base])))
        #expect(entriesOf(.animation) == entriesOf(AnimationTimelineSchedule()))
        #expect(
            entriesOf(.animation(minimumInterval: 0.25))
                == entriesOf(AnimationTimelineSchedule(minimumInterval: 0.25)))
    }
}
