//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DateFieldModel.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Date Field Model

/// The pure calendar math behind ``DatePicker`` — no state, no rendering, fully
/// unit-testable.
///
/// It lays a `Date` out as an ordered list of editable components (year, month,
/// day, hour, minute) plus inert separators, and adjusts a single component with
/// in-field wrapping (no carry between fields — macOS spinner behaviour) followed
/// by a clamp to the optional allowed range.
///
/// A fixed zero-padded numeric format is used deliberately (not a locale
/// `DateFormatter`) so component column widths stay stable and typing is
/// deterministic — the caret model depends on it. (SwiftUI reads the environment
/// calendar/locale; honouring `\.calendar`/`\.locale` is a possible follow-up.)
struct DateFieldModel {
    /// An editable date/time component.
    enum Kind: Equatable {
        case year, month, day, hour, minute
    }

    /// One laid-out piece of the field: an editable component (`kind != nil`) or
    /// an inert separator, with its absolute column span.
    struct Cell: Equatable {
        let text: String
        let kind: Kind?
        let columns: Range<Int>
    }

    let calendar: Calendar
    let components: DatePickerComponents
    let range: ClosedRange<Date>?

    init(calendar: Calendar = .current, components: DatePickerComponents, range: ClosedRange<Date>?) {
        self.calendar = calendar
        self.components = components
        self.range = range
    }

    /// The editable components in display order. An empty component set falls
    /// back to the date components so the field is never empty.
    func orderedKinds() -> [Kind] {
        let resolved = components.isEmpty ? DatePickerComponents.date : components
        var kinds: [Kind] = []
        if resolved.contains(.date) { kinds += [.year, .month, .day] }
        if resolved.contains(.hourAndMinute) { kinds += [.hour, .minute] }
        return kinds.isEmpty ? [.year, .month, .day] : kinds
    }

    /// The number of digit columns a component occupies (year is 4, the rest 2).
    func width(_ kind: Kind) -> Int { kind == .year ? 4 : 2 }

    /// The integer value of a component within `date`.
    func value(_ kind: Kind, of date: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        switch kind {
        case .year: return parts.year ?? 2000
        case .month: return parts.month ?? 1
        case .day: return parts.day ?? 1
        case .hour: return parts.hour ?? 0
        case .minute: return parts.minute ?? 0
        }
    }

    /// The zero-padded text of a component within `date`.
    func text(_ kind: Kind, of date: Date) -> String {
        String(format: kind == .year ? "%04d" : "%02d", value(kind, of: date))
    }

    /// The laid-out cells of the field, with absolute column ranges.
    func cells(date: Date, activeIndex: Int) -> [Cell] {
        let kinds = orderedKinds()
        var cells: [Cell] = []
        var column = 0
        for (index, kind) in kinds.enumerated() {
            let text = text(kind, of: date)
            cells.append(Cell(text: text, kind: kind, columns: column..<(column + text.count)))
            column += text.count
            if index < kinds.count - 1 {
                let separator = self.separator(after: kind, before: kinds[index + 1])
                cells.append(Cell(text: separator, kind: nil, columns: column..<(column + separator.count)))
                column += separator.count
            }
        }
        return cells
    }

    private func separator(after kind: Kind, before next: Kind) -> String {
        switch (kind, next) {
        case (.year, .month), (.month, .day): return "-"
        case (.hour, .minute): return ":"
        default: return " "  // between the date group and the time group
        }
    }

    // MARK: - Editing

    /// Adjusts one component by `delta`, wrapping within the field (no carry),
    /// re-clamping the day to the resulting month, then clamping the whole date
    /// to the allowed range.
    func adjusted(date: Date, kind: Kind, by delta: Int) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        switch kind {
        case .year: parts.year = min(9999, max(1, (parts.year ?? 2000) + delta))
        case .month: parts.month = wrap((parts.month ?? 1) + delta, 1, 12)
        case .day:
            let days = daysInMonth(year: parts.year ?? 2000, month: parts.month ?? 1)
            parts.day = wrap((parts.day ?? 1) + delta, 1, days)
        case .hour: parts.hour = wrap((parts.hour ?? 0) + delta, 0, 23)
        case .minute: parts.minute = wrap((parts.minute ?? 0) + delta, 0, 59)
        }
        return rebuild(parts, fallback: date)
    }

    /// Sets one component to an explicit value (from typed digits), clamping the
    /// value into its field range and the date into the allowed range.
    func setting(date: Date, kind: Kind, to raw: Int) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        switch kind {
        case .year: parts.year = min(9999, max(1, raw))
        case .month: parts.month = min(12, max(1, raw))
        case .day:
            let days = daysInMonth(year: parts.year ?? 2000, month: parts.month ?? 1)
            parts.day = min(days, max(1, raw))
        case .hour: parts.hour = min(23, max(0, raw))
        case .minute: parts.minute = min(59, max(0, raw))
        }
        return rebuild(parts, fallback: date)
    }

    /// Clamps a date into the allowed range (a no-op when unbounded).
    func clamp(_ date: Date) -> Date {
        guard let range else { return date }
        return min(max(date, range.lowerBound), range.upperBound)
    }

    // MARK: - Helpers

    /// Re-derives the day for its (possibly changed) month, rebuilds the date,
    /// and clamps to the range.
    private func rebuild(_ parts: DateComponents, fallback: Date) -> Date {
        var parts = parts
        let days = daysInMonth(year: parts.year ?? 2000, month: parts.month ?? 1)
        parts.day = min(parts.day ?? 1, days)
        return clamp(calendar.date(from: parts) ?? fallback)
    }

    /// Wraps `value` into `low...high` inclusive.
    private func wrap(_ value: Int, _ low: Int, _ high: Int) -> Int {
        let span = high - low + 1
        return low + (((value - low) % span) + span) % span
    }

    /// The number of days in the given month.
    private func daysInMonth(year: Int, month: Int) -> Int {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = 1
        guard let date = calendar.date(from: parts),
            let range = calendar.range(of: .day, in: .month, for: date)
        else { return 31 }
        return range.count
    }
}
