//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocaleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

//  The three values SwiftUI keeps apart for formatting — locale, calendar,
//  time zone — live together here because they are one family and are almost
//  always reasoned about together, not because any of them derives from the
//  others. A `Locale` carries a calendar and a `Calendar` carries a zone, and
//  SwiftUI still gives each its own key: they are three separate questions, and
//  an app that wants an Islamic calendar in a French UI showing UTC times has
//  to be able to say all three.

/// EnvironmentKey for the current locale.
private struct LocaleKey: EnvironmentKey {
    static let defaultValue = Locale.autoupdatingCurrent
}

/// EnvironmentKey for the current calendar.
private struct CalendarKey: EnvironmentKey {
    static let defaultValue = Calendar.autoupdatingCurrent
}

/// EnvironmentKey for the current time zone.
private struct TimeZoneKey: EnvironmentKey {
    static let defaultValue = TimeZone.autoupdatingCurrent
}

extension EnvironmentValues {
    /// The locale for the view subtree.
    ///
    /// Matches SwiftUI's `\.locale`. It is populated each frame from the app's
    /// localization service (`applyRuntimeServices(from:)`), so by default it
    /// tracks the app language — but because it's a stored, settable key, a
    /// subtree can override it with `.environment(\.locale, _)` to format its
    /// numbers and dates in a different locale than the surrounding UI.
    ///
    /// `Table`, `List`, and `ScrollView`'s number chrome read it, so an override
    /// re-locales their formatted output.
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }

    /// The calendar for the view subtree — SwiftUI's `\.calendar`.
    ///
    /// The *calendrical system* date arithmetic happens in: which months a year
    /// has, how many days are in this one, when a year rolls over.
    /// ``DatePicker`` does all of its stepping and clamping through it, so
    /// overriding it changes what the field can hold, not merely how it reads.
    ///
    /// ```swift
    /// DatePicker("Date", selection: $date)
    ///     .environment(\.calendar, Calendar(identifier: .hebrew))
    /// ```
    ///
    /// Which ZONE that arithmetic happens in is ``EnvironmentValues/timeZone``,
    /// separately — see there for why the two are not one value.
    public var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }

    /// The time zone for the view subtree — SwiftUI's `\.timeZone`.
    ///
    /// A `Date` is an instant, not a date: which day and hour it *reads* as
    /// depends entirely on the zone. ``DatePicker`` shows and edits the
    /// components in this one, so an override moves the whole field — a value
    /// shown as 09:00 in Los Angeles is the same instant shown as 17:00 in UTC.
    ///
    /// ```swift
    /// DatePicker("UTC", selection: $timestamp)
    ///     .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    /// ```
    ///
    /// - Important: A `Calendar` carries a zone of its own, and where the two
    ///   disagree **this one wins**: `\.timeZone` is a statement *about* the
    ///   zone, while a calendar's is incidental to having chosen a calendrical
    ///   system. So set this one to change zones — building a `Calendar` with a
    ///   zone on it and setting only ``EnvironmentValues/calendar`` will not do
    ///   it.
    public var timeZone: TimeZone {
        get { self[TimeZoneKey.self] }
        set { self[TimeZoneKey.self] = newValue }
    }
}
