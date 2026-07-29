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

    /// Page Up/Down is Up/Down's coarse sibling: a decade, a quarter, a week —
    /// and it wraps within its own field exactly as the fine step does, so Page
    /// Up from December lands on March rather than rolling the year over.
    @Test(
        "Page Up/Down moves the active component by its coarse step",
        arguments: [
            (1, Calendar.Component.month, 3, 6, 12),  // month: ±a quarter
            // The day wraps like every other component: two weeks back from the
            // 12th is the 29th of the same 31-day month, not the previous month.
            (2, .day, 7, 12, 29),
            (0, .year, 10, 2036, 2016),  // year: ±a decade
        ])
    func pageStep(index: Int, component: Calendar.Component, step: Int, up: Int, down: Int) {
        let sink = DateSink(date(2026, 3, 5))
        let handler = handler(sink, .date)
        handler.activeIndex = index

        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))
        #expect(calendar.component(component, from: sink.value) == up)
        _ = handler.handleKeyEvent(KeyEvent(key: .pageDown))
        _ = handler.handleKeyEvent(KeyEvent(key: .pageDown))
        #expect(calendar.component(component, from: sink.value) == down)
    }

    @Test("Page Up wraps within the field, without carrying into the next one")
    func pageStepWrapsInField() {
        let sink = DateSink(date(2026, 12, 5))
        let handler = handler(sink, .date)
        handler.activeIndex = 1  // month

        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))
        #expect(calendar.component(.month, from: sink.value) == 3, "12 + 3 wrapped to March")
        #expect(calendar.component(.year, from: sink.value) == 2026, "and the year is untouched")
    }

    /// Home/End send the component to the ends of its OWN range — the same move
    /// `Slider` and `Stepper` make for those keys. The day's range depends on the
    /// month it is in, so End in February is the 28th (or 29th).
    @Test("Home/End jump the active component to its own limits")
    func homeAndEnd() {
        let sink = DateSink(date(2026, 2, 10, 9, 30))
        let handler = handler(sink, [.date, .hourAndMinute])

        handler.activeIndex = 2  // day
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(calendar.component(.day, from: sink.value) == 28, "February 2026 ends on the 28th")
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(calendar.component(.day, from: sink.value) == 1)

        handler.activeIndex = 3  // hour
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(calendar.component(.hour, from: sink.value) == 23)
        handler.activeIndex = 4  // minute
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(calendar.component(.minute, from: sink.value) == 0)
    }

    /// A bounded picker's End cannot leave the range: the component goes to its
    /// own maximum and the whole date is then clamped, so it lands on the range's
    /// edge rather than on the year 9999.
    @Test("End inside an `in:` range stops at the range, not at the field's limit")
    func homeAndEndRespectTheRange() {
        let sink = DateSink(date(2026, 6, 15))
        let model = DateFieldModel(
            calendar: calendar, components: .date, range: date(2026, 1, 1)...date(2026, 8, 20))
        let handler = DatePickerHandler(focusID: "d", selection: sink.binding, model: model)

        handler.activeIndex = 0  // year
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(calendar.component(.year, from: sink.value) == 2026)
        #expect(calendar.component(.month, from: sink.value) == 8)
        #expect(calendar.component(.day, from: sink.value) == 20)

        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(sink.value == self.date(2026, 1, 1), "and Home lands on the lower bound")
    }

    /// A half-typed component is abandoned by any navigation or adjustment key —
    /// otherwise the next digit would append to a buffer the user has moved on
    /// from. Up/Down and Left/Right already did; the new keys must too.
    @Test("Page/Home/End clear the half-typed digit buffer")
    func coarseKeysClearTheDigitBuffer() {
        let sink = DateSink(date(2026, 3, 5))
        let handler = handler(sink, .date)
        handler.activeIndex = 1  // month

        _ = handler.handleKeyEvent(KeyEvent(key: .character("1")))  // month := 01, buffer "1"
        _ = handler.handleKeyEvent(KeyEvent(key: .pageUp))  // 1 + 3 = April
        _ = handler.handleKeyEvent(KeyEvent(key: .character("2")))
        #expect(
            calendar.component(.month, from: sink.value) == 2,
            "the 2 started a fresh number — it did not extend the abandoned 1 into 12")
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

    // MARK: - Pulsing active-field highlight

    /// The focused component's highlight sits on three known bug classes at
    /// once — measure-pass side effects, the bare-SGR-7 inverted-highlight
    /// trap, and opacity-dims-toward-black — so all three contracts get
    /// pinned here.
    private func renderFocused(pulsePhase: Double, isMeasuring: Bool = false) -> String {
        let sink = DateSink(localDate(2026, 3, 5, 9, 7))
        var context = makeRenderContext(width: 40, height: 3) { env, _ in
            env.pulsePhase = pulsePhase
        }
        context.isMeasuring = isMeasuring
        // The first focusable auto-focuses under makeRenderContext, so the
        // picker's active component is highlighted.
        return renderToBuffer(DatePicker("When", selection: sink.binding), context: context)
            .lines.joined(separator: "\n")
    }

    @Test("The focused field's pulse animates (different phases → different colours)")
    func pulseAnimates() {
        let low = renderFocused(pulsePhase: 0.0)
        let high = renderFocused(pulsePhase: 1.0)
        #expect(low != high, "the highlight breathes with the pulse phase")
        #expect(low.stripped == high.stripped, "the pulse is colour-only (no glyph change)")
    }

    @Test("The highlight uses explicit colours, never bare SGR 7 reverse-video")
    func highlightIsExplicitNotInverted() {
        // Bare `ESC[7m` inverts the terminal's DEFAULT colours, not the
        // palette's, collapsing to dark-on-dark on mid-tone themes (the
        // inverted-highlight trap). The highlight must carry explicit
        // foreground + background parameters instead.
        let out = renderFocused(pulsePhase: 0.5)
        #expect(!out.contains("\u{1B}[7m"), "no bare reverse-video")
        #expect(out.contains("38;2;"), "explicit foreground colour")
        // The background arrives in a combined SGR (e.g. ESC[4;38;…;48;…m).
        #expect(out.contains("48;2;"), "explicit background colour")
    }

    @Test("The measure pass is pulse-independent (no phase read while measuring)")
    func measureIgnoresPulse() {
        let a = renderFocused(pulsePhase: 0.0, isMeasuring: true)
        let b = renderFocused(pulsePhase: 1.0, isMeasuring: true)
        #expect(a == b, "measure output is byte-identical across pulse phases")
    }
}
