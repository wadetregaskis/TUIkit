//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DateFieldModelTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Coverage for ``DateFieldModel`` — the pure calendar math behind
/// ``DatePicker``: component layout, zero-padded formatting, in-field wrapping
/// without carry, day clamping across months (leap years), and range clamping.
@MainActor
@Suite("DateFieldModel")
struct DateFieldModelTests {

    /// A fixed Gregorian/UTC calendar so the tests are deterministic regardless
    /// of the machine's locale/timezone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func model(_ components: DatePickerComponents, range: ClosedRange<Date>? = nil) -> DateFieldModel {
        DateFieldModel(calendar: calendar, components: components, range: range)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Ordered kinds follow the component set (empty falls back to date)")
    func orderedKinds() {
        #expect(model(.date).orderedKinds() == [.year, .month, .day])
        #expect(model(.hourAndMinute).orderedKinds() == [.hour, .minute])
        #expect(model([.date, .hourAndMinute]).orderedKinds() == [.year, .month, .day, .hour, .minute])
        #expect(model([]).orderedKinds() == [.year, .month, .day])
    }

    @Test("Component text is zero-padded (year 4 digits, others 2)")
    func formatting() {
        let model = model([.date, .hourAndMinute])
        let date = date(2026, 3, 5, 9, 7)
        #expect(model.text(.year, of: date) == "2026")
        #expect(model.text(.month, of: date) == "03")
        #expect(model.text(.day, of: date) == "05")
        #expect(model.text(.hour, of: date) == "09")
        #expect(model.text(.minute, of: date) == "07")
    }

    @Test("Cells lay the field out with correct column ranges")
    func cellLayout() {
        let model = model(.date)
        let cells = model.cells(date: date(2026, 3, 5), activeIndex: 0)
        #expect(cells.map(\.text).joined() == "2026-03-05")
        let editable = cells.filter { $0.kind != nil }
        #expect(editable.count == 3)
        #expect(editable[0].columns == 0..<4)  // year
        #expect(editable[1].columns == 5..<7)  // month (after the "-")
        #expect(editable[2].columns == 8..<10)  // day
    }

    @Test("Adjusting a component wraps within its field, never carrying")
    func wrapWithoutCarry() {
        let model = model([.date, .hourAndMinute])
        let december = model.adjusted(date: date(2026, 12, 15), kind: .month, by: 1)
        #expect(model.value(.month, of: december) == 1)  // Dec + 1 → Jan
        #expect(model.value(.year, of: december) == 2026)  // no carry into the year

        let minute = model.adjusted(date: date(2026, 1, 1, 10, 59), kind: .minute, by: 1)
        #expect(model.value(.minute, of: minute) == 0)  // 59 + 1 → 00
        #expect(model.value(.hour, of: minute) == 10)  // no carry into the hour
    }

    @Test("Day clamps to the target month (Jan 31 → Feb 28/29)")
    func dayClampsToMonth() {
        let model = model(.date)
        let feb2026 = model.adjusted(date: date(2026, 1, 31), kind: .month, by: 1)  // non-leap
        #expect(model.value(.month, of: feb2026) == 2)
        #expect(model.value(.day, of: feb2026) == 28)
        let feb2024 = model.adjusted(date: date(2024, 1, 31), kind: .month, by: 1)  // leap
        #expect(model.value(.day, of: feb2024) == 29)
    }

    @Test("The whole date is clamped to the allowed range")
    func rangeClamp() {
        let lower = date(2026, 1, 10)
        let upper = date(2026, 1, 20)
        let model = model(.date, range: lower...upper)
        #expect(model.adjusted(date: lower, kind: .day, by: -1) == lower)  // pins at lower
        #expect(model.adjusted(date: upper, kind: .day, by: 1) == upper)  // pins at upper
    }

    @Test("Typing a value sets the component, clamped to its range")
    func settingClamps() {
        let model = model(.date)
        let date = date(2026, 3, 15)
        #expect(model.value(.month, of: model.setting(date: date, kind: .month, to: 6)) == 6)
        #expect(model.value(.month, of: model.setting(date: date, kind: .month, to: 99)) == 12)
        #expect(model.value(.day, of: model.setting(date: date, kind: .day, to: 99)) == 31)  // March
    }
}
