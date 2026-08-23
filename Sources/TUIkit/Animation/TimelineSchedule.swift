//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TimelineSchedule.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Mode

/// How often a ``TimelineSchedule`` is being asked to supply entries.
///
/// SwiftUI uses `.lowFrequency` for a display that is showing the view in a
/// reduced-power always-on state, where an animation rate would be wasted. A
/// terminal has no such state — the run loop is either running and rendering on
/// demand, or suspended (Ctrl-Z) and rendering nothing at all — so ``TimelineView``
/// always asks for ``normal``. The mode is still honoured by every schedule
/// here, because a schedule is a value anyone may query directly.
public enum TimelineScheduleMode: Sendable {
    /// The schedule's ordinary rate.
    case normal

    /// A reduced rate for a low-power display. Schedules that exist only to
    /// drive an animation (``AnimationTimelineSchedule``) supply no entries at
    /// all in this mode.
    case lowFrequency
}

// MARK: - Protocol

/// A sequence of dates at which a ``TimelineView`` updates.
///
/// Conform your own type to schedule updates on any rule you like; the built-in
/// schedules cover the common ones (``TimelineSchedule/everyMinute``,
/// ``TimelineSchedule/periodic(from:by:)``, ``TimelineSchedule/explicit(_:)``,
/// ``TimelineSchedule/animation``).
///
/// ## Writing a schedule
///
/// ``entries(from:mode:)`` returns the dates **at and after** the moment the
/// view is asking about, in ascending order. The first entry is the one the
/// view displays *now*, so a schedule normally starts it at or before
/// `startDate` — ``EveryMinuteTimelineSchedule`` starts at the top of the
/// minute containing `startDate`, which is the minute a clock should be showing.
/// Each later entry becomes the moment the view next re-renders.
///
/// The sequence may be infinite: only the first entry and the first entry after
/// `startDate` are ever read, so an unbounded generator costs nothing.
public protocol TimelineSchedule {
    /// The sequence of dates this schedule produces.
    associatedtype Entries: Sequence where Entries.Element == Date

    /// A convenience so conformers can spell the mode as `Self.Mode`.
    typealias Mode = TimelineScheduleMode

    /// The dates at and after `startDate` at which a view following this
    /// schedule should update, in ascending order.
    func entries(from startDate: Date, mode: Self.Mode) -> Entries
}

// MARK: - Periodic

/// A schedule that fires at a fixed interval, on a lattice anchored at a date.
///
/// Create one with ``TimelineSchedule/periodic(from:by:)``.
public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
    /// The dates of a ``PeriodicTimelineSchedule``: an unbounded arithmetic
    /// sequence of instants one `interval` apart.
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        private var upcoming: Date
        private let interval: TimeInterval

        init(first: Date, interval: TimeInterval) {
            self.upcoming = first
            self.interval = interval
        }

        public mutating func next() -> Date? {
            defer { upcoming = upcoming.addingTimeInterval(interval) }
            return upcoming
        }
    }

    private let anchor: Date
    private let interval: TimeInterval

    /// Creates a schedule that fires at `startDate` and every `interval`
    /// seconds either side of it.
    ///
    /// - Parameters:
    ///   - startDate: The instant the lattice is anchored to. The lattice
    ///     extends backwards from it too, so a schedule anchored in the past
    ///     still has an entry to show right now.
    ///   - interval: The seconds between entries. Must be greater than zero — a
    ///     schedule that never advances would be asked for its next entry
    ///     forever, which in a terminal app is an unrecoverable hang rather
    ///     than a spinning beachball.
    public init(from startDate: Date, by interval: TimeInterval) {
        precondition(interval > 0, "PeriodicTimelineSchedule interval must be > 0")
        self.anchor = startDate
        self.interval = interval
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        // The lattice point nearest `startDate` from below — or, when the anchor
        // is still in the future, the one below the anchor. That second case is
        // the truncation SwiftUI performs (measured), rather than a floor: with
        // an anchor 7 s away and a 5 s interval, the sequence starts 2 s away and
        // not 3 s ago.
        let steps = (startDate.timeIntervalSince(anchor) / interval).rounded(.towardZero)
        return Entries(first: anchor.addingTimeInterval(steps * interval), interval: interval)
    }
}

// MARK: - Every minute

/// A schedule that fires at the top of every minute.
///
/// Create one with ``TimelineSchedule/everyMinute``. The entry a view starts on
/// is the top of the minute it is *in*, so a clock renders the current minute
/// immediately rather than showing the previous one until the boundary.
public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
    /// The dates of an ``EveryMinuteTimelineSchedule``: every minute boundary
    /// from the one containing the start date onwards.
    public typealias Entries = PeriodicTimelineSchedule.Entries

    private static let minute: TimeInterval = 60

    /// Creates the schedule.
    public init() {}

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        // Floored in reference-date seconds, whose zero is itself a minute
        // boundary — so this is the top of the wall-clock minute in any time
        // zone offset by a whole number of minutes.
        let seconds = startDate.timeIntervalSinceReferenceDate
        let floored = (seconds / Self.minute).rounded(.down) * Self.minute
        return Entries(
            first: Date(timeIntervalSinceReferenceDate: floored), interval: Self.minute)
    }
}

// MARK: - Explicit

/// A schedule of dates you supply.
///
/// Create one with ``TimelineSchedule/explicit(_:)``. The dates must be in
/// ascending order. They are handed to the view exactly as given — including
/// any that have already passed, of which the first is the entry the view
/// starts on — and once the last one is behind it, the view stops updating.
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule
where Entries.Element == Date {
    private let dates: Entries

    /// Creates a schedule from a sequence of dates in ascending order.
    public init(_ dates: Entries) {
        self.dates = dates
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        dates
    }
}

// MARK: - Animation

/// A schedule that fires as fast as the app draws, for driving an animation
/// from the current time.
///
/// Create one with ``TimelineSchedule/animation`` or
/// ``TimelineSchedule/animation(minimumInterval:paused:)``.
///
/// SwiftUI paces this from the display's refresh rate. A terminal has no
/// equivalent to ask, so the default here is 60 Hz — the default of
/// `App.maxFrameRate`, which is also the ceiling the run loop would coalesce a
/// faster request down to. Give `minimumInterval` explicitly to ask for less.
public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
    /// The dates of an ``AnimationTimelineSchedule``: instants one interval
    /// apart from the start date, or none at all when the schedule is paused or
    /// the display is running at a reduced rate.
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        private var upcoming: Date?
        private let interval: TimeInterval

        init(first: Date?, interval: TimeInterval) {
            self.upcoming = first
            self.interval = interval
        }

        public mutating func next() -> Date? {
            guard let date = upcoming else { return nil }
            upcoming = date.addingTimeInterval(interval)
            return date
        }
    }

    /// The rate used when no `minimumInterval` is given: `App.maxFrameRate`'s
    /// default of 60 FPS.
    private static let defaultInterval: TimeInterval = 1.0 / 60.0

    private let minimumInterval: Double?
    private let paused: Bool

    /// Creates a schedule that fires at the app's frame rate, or no faster than
    /// `minimumInterval` when one is given.
    ///
    /// - Parameters:
    ///   - minimumInterval: The shortest interval between entries, in seconds.
    ///     `nil` (the default) and any non-positive value mean the app's frame
    ///     rate.
    ///   - paused: Whether the schedule is stopped. A paused schedule supplies
    ///     no entries, so a view following it renders once and then sits still
    ///     until something else changes.
    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        self.minimumInterval = minimumInterval
        self.paused = paused
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let interval =
            (minimumInterval.map { $0 > 0 ? $0 : Self.defaultInterval }) ?? Self.defaultInterval
        // Paused, or a display too slow to be worth animating on: no entries at
        // all. The view still renders once, at the date it asked about.
        let stopped = paused || mode == .lowFrequency
        return Entries(first: stopped ? nil : startDate, interval: interval)
    }
}

// MARK: - Factories

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// A schedule that fires every `interval` seconds, on a lattice anchored at
    /// `startDate`.
    public static func periodic(
        from startDate: Date, by interval: TimeInterval
    ) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: startDate, by: interval)
    }
}

extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    /// A schedule that fires at the top of every minute.
    public static var everyMinute: EveryMinuteTimelineSchedule {
        EveryMinuteTimelineSchedule()
    }
}

extension TimelineSchedule {
    /// A schedule of the dates you supply, in ascending order.
    public static func explicit<S>(_ dates: S) -> ExplicitTimelineSchedule<S>
    where Self == ExplicitTimelineSchedule<S>, S: Sequence, S.Element == Date {
        ExplicitTimelineSchedule(dates)
    }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    /// A schedule that fires at the app's frame rate.
    public static var animation: AnimationTimelineSchedule {
        AnimationTimelineSchedule()
    }

    /// A schedule that fires at the app's frame rate, no faster than
    /// `minimumInterval`, and not at all while `paused`.
    public static func animation(
        minimumInterval: Double? = nil, paused: Bool = false
    ) -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
    }
}
