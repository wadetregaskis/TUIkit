//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DatePickerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// A mutable date backing a test `Binding`.
private final class DateSink: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
    var binding: Binding<Date> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

/// Coverage for ``DatePickerHandler`` (component navigation, adjustment, digit
/// entry, focus keys) and the ``DatePicker`` field render.
@MainActor
@Suite("DatePicker")
struct DatePickerTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func handler(_ sink: DateSink, _ components: DatePickerComponents) -> DatePickerHandler {
        let model = DateFieldModel(calendar: calendar, components: components, range: nil)
        return DatePickerHandler(focusID: "d", selection: sink.binding, model: model)
    }

    /// A date built in the *current* calendar — used by the render tests, since
    /// `_DatePickerCore` formats with `Calendar.current`.
    private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Left/Right move the active component")
    func navigation() {
        let handler = handler(DateSink(localDate(2026, 3, 5, 9, 7)), [.date, .hourAndMinute])
        #expect(handler.activeIndex == 0)
        _ = handler.handleKeyEvent(KeyEvent(key: .right))
        #expect(handler.activeIndex == 1)
        _ = handler.handleKeyEvent(KeyEvent(key: .right))
        #expect(handler.activeIndex == 2)
        _ = handler.handleKeyEvent(KeyEvent(key: .left))
        #expect(handler.activeIndex == 1)
    }

    @Test("Up/Down adjust the active component")
    func adjust() {
        let sink = DateSink(date(2026, 3, 5))
        let handler = handler(sink, .date)
        handler.activeIndex = 1  // month
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(calendar.component(.month, from: sink.value) == 4)
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(calendar.component(.month, from: sink.value) == 3)
    }

    @Test("Typing digits edits the active component and auto-advances")
    func digitEntry() {
        let sink = DateSink(date(2026, 3, 5))
        let handler = handler(sink, .date)
        handler.activeIndex = 1  // month
        _ = handler.handleKeyEvent(KeyEvent(key: .character("1")))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("2")))
        #expect(calendar.component(.month, from: sink.value) == 12)
        #expect(handler.activeIndex == 2)  // advanced to the day after two digits
    }

    @Test("Tab and Enter are not consumed (focus can leave)")
    func focusKeysPropagate() {
        let handler = handler(DateSink(date(2026, 3, 5)), .date)
        #expect(handler.handleKeyEvent(KeyEvent(key: .tab)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .escape)) == false)
    }

    @Test("Renders the label and the date/time field")
    func rendersField() {
        let sink = DateSink(localDate(2026, 3, 5, 9, 7))
        let text = renderToBuffer(
            DatePicker("When", selection: sink.binding), context: makeRenderContext(width: 40, height: 3)
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains("When"))
        #expect(text.contains("2026-03-05"))
        #expect(text.contains("09:07"))
    }

    @Test("A date-only picker shows just the date components")
    func dateOnly() {
        let sink = DateSink(localDate(2026, 3, 5, 9, 7))
        let text = renderToBuffer(
            DatePicker("Day", selection: sink.binding, displayedComponents: .date),
            context: makeRenderContext(width: 30, height: 3)
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains("2026-03-05"))
        #expect(!text.contains("09:07"))
    }
}
