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

    /// A date built in the *current* calendar and zone — for the render tests
    /// that install neither, where `_DatePickerCore` takes the environment's
    /// defaults (`.autoupdatingCurrent` for both). The tests that DO install
    /// them build their instant with `date(_:_:_:)` above, which is UTC.
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

    // MARK: - Mouse wheel

    /// Renders a date-only picker and returns the dispatcher plus the field's
    /// on-screen row, so a test can put the wheel over a chosen column.
    private func wheelHarness(
        _ sink: DateSink
    ) -> (dispatcher: MouseEventDispatcher, y: Int, x: (Int) -> Int)? {
        let context = makeRenderContext(width: 40, height: 1)
        guard let dispatcher = context.environment.mouseEventDispatcher else { return nil }
        dispatcher.setActiveSupport(.standard)
        let view = DatePicker(selection: sink.binding, displayedComponents: .date) { EmptyView() }
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = buffer.hitTestRegions.max(by: { $0.width < $1.width }) else { return nil }
        // "YYYY-MM-DD" — year at +0…3, month at +5…6, day at +8…9.
        return (dispatcher, region.offsetY, { region.offsetX + $0 })
    }

    /// The framework-wide wheel convention: up goes towards smaller/earlier,
    /// the same as Stepper, Slider and the scrollers. Rolling the wheel is
    /// scrolling THROUGH the values, not pressing the Up arrow.
    @Test("Wheel up steps the pointed field back, wheel down forward")
    func wheelStepsThePointedField() {
        // Mid-month, mid-year: stepping the month must not carry into the day,
        // and staying clear of a DST boundary keeps that assertion about the
        // field arithmetic rather than about the calendar.
        let sink = DateSink(date(2026, 6, 15))
        guard let (dispatcher, y, x) = wheelHarness(sink) else {
            Issue.record("expected a date-picker hit-test region"); return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: x(5), y: y))
        #expect(calendar.component(.month, from: sink.value) == 5, "wheel up over the month")
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: x(5), y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: x(5), y: y))
        #expect(calendar.component(.month, from: sink.value) == 7, "and forward past the start")
        #expect(calendar.component(.day, from: sink.value) == 15, "no other field moved")
    }

    /// Pointing at a field is enough — no click first. This is what makes the
    /// wheel worth having over Up/Down, which only reach the active field.
    @Test("The field under the pointer takes the step and becomes active")
    func wheelRetargetsTheActiveField() {
        let sink = DateSink(date(2026, 3, 5))
        guard let (dispatcher, y, x) = wheelHarness(sink) else {
            Issue.record("expected a date-picker hit-test region"); return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: x(0), y: y))
        #expect(calendar.component(.year, from: sink.value) == 2025, "the year, not the default field")

        let before = sink.value
        // Column 4 is the "-" separator: nobody owns it, so the field the
        // previous tick activated keeps the step.
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: x(4), y: y))
        #expect(calendar.component(.year, from: sink.value) == 2024)
        #expect(sink.value != before)
    }

    /// A value control swallows the wheel; otherwise a tick aimed at the month
    /// would also scroll the page out from under the pointer.
    @Test("A wheel tick is swallowed, not chained to the page")
    func wheelIsSwallowed() {
        let sink = DateSink(date(2026, 3, 5))
        guard let (dispatcher, y, x) = wheelHarness(sink) else {
            Issue.record("expected a date-picker hit-test region"); return
        }
        #expect(dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: x(5), y: y)))
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

    // MARK: - \.calendar and \.timeZone

    /// Renders a picker showing one fixed instant, in whatever calendar and zone
    /// the closure installs.
    private func rendered(
        _ instant: Date, configure: @escaping (inout EnvironmentValues) -> Void
    ) -> String {
        let sink = DateSink(instant)
        let context = makeRenderContext(width: 40, height: 3) { environment, _ in
            configure(&environment)
        }
        return renderToBuffer(DatePicker("When", selection: sink.binding), context: context)
            .lines.map { $0.stripped }.joined()
    }

    /// 2026-03-05 09:07 UTC — one instant, deliberately at an hour that reads as
    /// a different DAY in a far-enough-west zone, so a zone that failed to reach
    /// the field could not pass by accident on the hour alone.
    private var instant: Date { date(2026, 3, 5, 9, 7) }

    @Test("The field shows the subtree's time zone, not the machine's")
    func timeZoneReachesTheField() {
        let utc = rendered(instant) { $0.timeZone = TimeZone(identifier: "UTC")! }
        #expect(utc.contains("2026-03-05"), "\(utc)")
        #expect(utc.contains("09:07"), "\(utc)")

        // Tokyo is UTC+9 the year round, so the same instant is the evening of
        // the same day; Honolulu is UTC-10, which puts it on the day before.
        let tokyo = rendered(instant) { $0.timeZone = TimeZone(identifier: "Asia/Tokyo")! }
        #expect(tokyo.contains("18:07"), "\(tokyo)")
        let honolulu = rendered(instant) { $0.timeZone = TimeZone(identifier: "Pacific/Honolulu")! }
        #expect(honolulu.contains("2026-03-04"), "\(honolulu)")
        #expect(honolulu.contains("23:07"), "\(honolulu)")
    }

    @Test("The field counts in the subtree's calendar")
    func calendarReachesTheField() {
        // The same instant, in a calendar that numbers its years differently:
        // the Gregorian 2026 is 1447/1448 in the Islamic calendar, so a picker
        // still showing 2026 is one that never read `\.calendar`.
        let gregorian = rendered(instant) {
            $0.calendar = Calendar(identifier: .gregorian)
            $0.timeZone = TimeZone(identifier: "UTC")!
        }
        #expect(gregorian.contains("2026-03-05"), "\(gregorian)")

        let islamic = rendered(instant) {
            $0.calendar = Calendar(identifier: .islamic)
            $0.timeZone = TimeZone(identifier: "UTC")!
        }
        #expect(!islamic.contains("2026-03-05"), "\(islamic)")
        #expect(islamic.contains("1447-"), "\(islamic)")
    }

    @Test("The environment's zone wins over the calendar's own")
    func theEnvironmentZoneWins() {
        // A `Calendar` carries a zone, and this one carries the WRONG one on
        // purpose. `\.timeZone` is the value that says which zone the interface
        // is in, so it is the one that must be honoured — documented on
        // `EnvironmentValues.timeZone`, and easy to regress by simply reading
        // `\.calendar` and using it as it arrives.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let out = rendered(instant) {
            $0.calendar = calendar
            $0.timeZone = TimeZone(identifier: "UTC")!
        }
        #expect(out.contains("09:07"), "UTC won, not the calendar's Tokyo: \(out)")
    }

    // MARK: - Pulsing active-field highlight

    /// The focused component's highlight sits on three known bug classes at
    /// once — measure-pass side effects, the bare-SGR-7 inverted-highlight
    /// trap, and opacity-dims-toward-black — so all three contracts get
    /// pinned here.
    private func focusedBuffer(isMeasuring: Bool = false) -> FrameBuffer {
        let sink = DateSink(localDate(2026, 3, 5, 9, 7))
        var context = makeRenderContext(width: 40, height: 3)
        context.isMeasuring = isMeasuring
        // The first focusable auto-focuses under makeRenderContext, so the
        // picker's active component is highlighted.
        return renderToBuffer(DatePicker("When", selection: sink.binding), context: context)
    }

    private func renderFocused(isMeasuring: Bool = false) -> String {
        focusedBuffer(isMeasuring: isMeasuring).lines.joined(separator: "\n")
    }

    @Test("The focused field hands its pulsing block to the run loop")
    func pulseAnimates() {
        // Not "the output changes with the phase": the picker no longer reads
        // the phase as it renders — that read is what forced a full re-render
        // of the page per tick. It leaves a run instead, and the run is where
        // the breathing now lives.
        let buffer = focusedBuffer()
        #expect(buffer.animatedCells.count == 1, "the active component left no run")
        let run = buffer.animatedCells[0]
        #expect(run.isAnimating, "the run is a still picture")
        #expect(
            Set(run.frames.map(\.stripped)).count == 1,
            "the pulse is colour-only (no glyph change)")
        // The run has to sit on the cells that were drawn — replaying the step
        // it was rendered at must change nothing.
        let replayed = buffer.composited(
            with: FrameBuffer(lines: [run.frame(atIndex: 0)]), at: (x: run.offsetX, y: run.offsetY))
        #expect(replayed.lines.map(\.stripped) == buffer.lines.map(\.stripped),
            "the run does not sit on the highlighted component")
    }

    @Test("An unfocused field animates nothing")
    func unfocusedIsStill() {
        let sink = DateSink(localDate(2026, 3, 5, 9, 7))
        let context = makeRenderContext(width: 40, height: 3)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(DatePicker("When", selection: sink.binding), context: context)
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("The highlight uses explicit colours, never bare SGR 7 reverse-video")
    func highlightIsExplicitNotInverted() {
        // Bare `ESC[7m` inverts the terminal's DEFAULT colours, not the
        // palette's, collapsing to dark-on-dark on mid-tone themes (the
        // inverted-highlight trap). The highlight must carry explicit
        // foreground + background parameters instead.
        let out = renderFocused()
        #expect(!out.contains("\u{1B}[7m"), "no bare reverse-video")
        #expect(out.contains("38;2;"), "explicit foreground colour")
        // The background arrives in a combined SGR (e.g. ESC[4;38;…;48;…m).
        #expect(out.contains("48;2;"), "explicit background colour")
    }

    @Test("The measure pass neither pulses nor leaves a run")
    func measureIgnoresPulse() {
        // A measure that asked for an animating emphasis would keep the clock
        // alive from a pass that draws nothing, and a run left on a measure
        // buffer describes cells that were never on screen.
        let measured = focusedBuffer(isMeasuring: true)
        #expect(measured.animatedCells.isEmpty)
        #expect(!measured.lines.joined().contains("48;2;"), "no highlight while measuring")
    }
}
