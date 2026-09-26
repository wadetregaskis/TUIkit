//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimelineViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("TimelineView")
struct TimelineViewTests {
    private let second: Int64 = 1_000_000_000

    /// A render context whose frame clock reads `frameNowNanos`: zero unless given,
    /// so a declared wake's firing instant IS the delay that was asked for.
    private func harness(width: Int = 40, height: Int = 8, frameNowNanos: Int64 = 0) -> (
        TUIContext, RenderContext, AnimationScheduler
    ) {
        let tui = TUIContext()
        let scheduler = AnimationScheduler()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.animationScheduler = scheduler
        environment.frameNowNanos = frameNowNanos
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui),
            scheduler
        )
    }

    /// One frame, fenced as the loop fences it — its wall-clock date stamped
    /// once, beside its monotonic instant, as `RenderLoop` stamps it.
    private func render(
        _ view: some View, tui: TUIContext, context: RenderContext, scheduler: AnimationScheduler
    ) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = Date()
        context.environment.focusManager?.beginRenderPass()
        scheduler.beginFrame()
        let buffer = renderToBuffer(view, context: context)
        scheduler.endFrame()
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    /// The date the content was handed, recorded out of the render.
    private final class Seen {
        var date: Date?
        var cadence: TimelineViewDefaultContext.Cadence?
    }

    /// Records what the content was handed and renders something identifiable.
    ///
    /// A function rather than a side effect inside the builder: a bare `_ = ...`
    /// is an expression statement of type `()`, which `@ViewBuilder` tries to
    /// build a view out of.
    private func tick(_ context: TimelineViewDefaultContext, into seen: Seen) -> Text {
        seen.date = context.date
        seen.cadence = context.cadence
        return Text("tick")
    }

    private func timeline<S: TimelineSchedule>(_ schedule: S, into seen: Seen) -> some View {
        TimelineView(schedule) { context in tick(context, into: seen) }
    }

    // MARK: - The date the content sees

    @Test("The content is rendered for the schedule's entry, not the instant of the render")
    func rendersForTheEntry() throws {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        let before = Date()
        _ = render(timeline(.everyMinute, into: seen), tui: tui, context: context, scheduler: scheduler)
        let date = try #require(seen.date)
        // The top of the minute the render happened in: a whole number of
        // minutes, at or before now, less than a minute ago.
        #expect(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) == 0)
        #expect(date <= before)
        #expect(before.timeIntervalSince(date) < 60)
    }

    @Test("An entirely past schedule shows its first entry and never moves off it")
    func pastScheduleShowsItsFirstEntry() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        let now = Date()
        let first = now.addingTimeInterval(-600)
        _ = render(
            timeline(.explicit([first, now.addingTimeInterval(-300)]), into: seen),
            tui: tui, context: context, scheduler: scheduler)
        #expect(seen.date == first)
    }

    @Test("A schedule that has not started yet shows its first entry")
    func futureScheduleShowsItsFirstEntry() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        let first = Date().addingTimeInterval(300)
        _ = render(
            timeline(.explicit([first]), into: seen), tui: tui, context: context,
            scheduler: scheduler)
        #expect(seen.date == first)
    }

    @Test("The cadence in a terminal is always live")
    func cadenceIsLive() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(
            timeline(.animation(minimumInterval: 1), into: seen), tui: tui, context: context,
            scheduler: scheduler)
        #expect(seen.cadence == .live)
    }

    @Test("The content is rendered")
    func contentReaches() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        let buffer = render(
            timeline(.everyMinute, into: seen), tui: tui, context: context, scheduler: scheduler)
        #expect(buffer.lines.first?.contains("tick") == true)
    }

    // MARK: - What it asks the run loop for

    @Test("One wake is declared, for the next entry")
    func declaresTheNextEntry() throws {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(
            timeline(.explicit([Date().addingTimeInterval(10)]), into: seen),
            tui: tui, context: context, scheduler: scheduler)
        #expect(scheduler.liveWakeCount == 1)
        let firing = try #require(scheduler.nextFiring(after: 0))
        // Ten seconds out, less however long the render itself took.
        #expect(firing > 9 * second && firing <= 10 * second)
    }

    @Test("everyMinute asks to be woken within the minute, not sooner")
    func everyMinuteWakesAtTheBoundary() throws {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(timeline(.everyMinute, into: seen), tui: tui, context: context, scheduler: scheduler)
        let firing = try #require(scheduler.nextFiring(after: 0))
        #expect(firing > 0 && firing <= 60 * second)
    }

    @Test("A schedule with nothing left to show asks for nothing, and the screen goes idle")
    func exhaustedScheduleIsIdle() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(
            timeline(.explicit([Date().addingTimeInterval(-5)]), into: seen),
            tui: tui, context: context, scheduler: scheduler)
        #expect(scheduler.liveWakeCount == 0)
        #expect(scheduler.isIdle)
        #expect(scheduler.nextFiring(after: 0) == nil)
    }

    @Test("An animation schedule wakes at the next 1/60 s tick's instant, not a sixtieth after the render")
    func animationWakesOnTheNextTick() {
        // 1.037 s is 2.3 ms into tick 62; tick 63 begins at 1.05 s.
        let (tui, context, scheduler) = harness(frameNowNanos: 1_037_000_000)
        let seen = Seen()
        _ = render(timeline(.animation, into: seen), tui: tui, context: context, scheduler: scheduler)
        #expect(scheduler.liveWakeCount == 1)
        #expect(scheduler.nextFiring(after: 1_037_000_000) == AnimationClock.nanoseconds(atTick: 63))
    }

    @Test(
        "An animation schedule with a minimum interval wakes on the lattice of that many ticks",
        arguments: [(0.1, 66), (0.05, 63), (0.12, 64)] as [(Double, Int64)])
    func animationMinimumIntervalWakesOnItsLattice(_ interval: Double, _ tick: Int64) {
        // From tick 62: 0.1 s is 6 ticks, whose next multiple is 66; 0.05 s is 3 (63);
        // 0.12 s is 7.2, and no fewer than that many ticks apart is 8 (64).
        let (tui, context, scheduler) = harness(frameNowNanos: 1_037_000_000)
        let seen = Seen()
        _ = render(
            timeline(.animation(minimumInterval: interval), into: seen), tui: tui, context: context,
            scheduler: scheduler)
        #expect(scheduler.nextFiring(after: 1_037_000_000) == AnimationClock.nanoseconds(atTick: tick))
    }

    @Test("An animation schedule's content still sees the date of the render")
    func animationEntryIsTheRenderDate() throws {
        let (tui, context, scheduler) = harness(frameNowNanos: 1_037_000_000)
        let seen = Seen()
        let before = Date()
        _ = render(timeline(.animation, into: seen), tui: tui, context: context, scheduler: scheduler)
        let after = Date()
        let date = try #require(seen.date)
        #expect(date >= before && date <= after)
    }

    @Test("A paused animation schedule asks for nothing")
    func pausedAsksForNothing() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(
            timeline(.animation(minimumInterval: 0.5, paused: true), into: seen),
            tui: tui, context: context, scheduler: scheduler)
        #expect(scheduler.isIdle)
    }

    @Test("A wake that stops being re-declared is dropped")
    func staleWakeIsDropped() {
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        _ = render(
            timeline(.animation(minimumInterval: 0.5), into: seen), tui: tui, context: context,
            scheduler: scheduler)
        #expect(scheduler.liveWakeCount == 1)
        // The next frame does not contain the timeline at all.
        scheduler.beginFrame()
        scheduler.endFrame()
        #expect(scheduler.isIdle)
    }

    @Test("A measure pass declares nothing, even when it measures by rendering")
    func measureDeclaresNothing() {
        let (_, context, scheduler) = harness()
        var measuring = context
        measuring.isMeasuring = true
        let seen = Seen()
        // Straight through `renderToBuffer`, which is how a parent that measures
        // by rendering reaches the core — the path the `isMeasuring` guard is
        // there for. Measuring via `sizeThatFits` never touches it.
        scheduler.beginFrame()
        _ = renderToBuffer(timeline(.animation(minimumInterval: 0.5), into: seen), context: measuring)
        scheduler.endFrame()
        #expect(seen.date != nil, "the content was built, so a wake could have been declared")
        #expect(scheduler.isIdle)
    }

    @Test("A timeline whose content is time-varying opts its subtree out of value memoization")
    func marksTheSubtreeVolatile() {
        let (tui, context, scheduler) = harness()
        var tracked = context
        let tracker = VolatileReadTracker()
        tracked.environment.volatileReadTracker = tracker
        let seen = Seen()
        #expect(tracker.cacheUnsafeCount == 0)
        _ = render(
            timeline(.animation(minimumInterval: 0.5), into: seen), tui: tui, context: tracked,
            scheduler: scheduler)
        #expect(tracker.cacheUnsafeCount > 0)
    }

    // MARK: - Layout

    @Test("The timeline measures as its content does")
    func measuresAsItsContent() {
        let (_, context, _) = harness()
        let seen = Seen()
        let proposal = ProposedSize(width: 40, height: 8)
        let bare = measureChild(Text("tick"), proposal: proposal, context: context)
        let wrapped = measureChild(
            timeline(.everyMinute, into: seen), proposal: proposal, context: context)
        #expect(wrapped.width == bare.width)
        #expect(wrapped.height == bare.height)
    }

    @Test("A flexible content stays flexible through the timeline")
    func flexibilityIsForwarded() {
        // The measurement is forwarded rather than taken by rendering: rendering
        // yields a fixed size, which would pin a content that wanted to grow.
        let (tui, context, scheduler) = harness()
        let seen = Seen()
        let proposal = ProposedSize(width: 40, height: 8)
        let flexible = TimelineView(.everyMinute) { timelineContext in
            tick(timelineContext, into: seen).frame(maxWidth: .infinity)
        }
        let bare = measureChild(
            Text("tick").frame(maxWidth: .infinity), proposal: proposal, context: context)
        #expect(bare.isWidthFlexible, "the fixture must be flexible or this proves nothing")
        let wrapped = measureChild(flexible, proposal: proposal, context: context)
        #expect(wrapped.isWidthFlexible == bare.isWidthFlexible)
        #expect(wrapped.isHeightFlexible == bare.isHeightFlexible)
        #expect(wrapped.width == bare.width)
        // And it renders at the width its flexibility asked for.
        let buffer = render(flexible, tui: tui, context: context, scheduler: scheduler)
        #expect(buffer.width == 40)
    }

    // MARK: - One date a frame

    /// A timer beside a bar, whose clock crosses a second between two reads.
    private func straddledTimer(_ clock: StraddlingClock) -> some View {
        HStack(spacing: 0) {
            TimelineView(StraddlingSchedule(clock: clock)) { timeline in
                Text(verbatim: "\(Int(timeline.date.timeIntervalSinceReferenceDate))s")
            }
            Text("|")
        }
    }

    /// The measure and the render each read the clock, a walk apart, so a frame
    /// that began just short of an entry boundary measured the entry before it
    /// and drew the one after it: a timer laid out for "9s" drew "10s" into its
    /// two cells. Nothing memoized — the frame disagreed with itself.
    @Test("A frame lays its timeline out for the entry it draws, however the clock moves between its walks")
    func oneEntryPerFrame() {
        let (tui, context, scheduler) = harness()
        let clock = StraddlingClock(seconds: 9)
        let line = render(straddledTimer(clock), tui: tui, context: context, scheduler: scheduler)
            .lines[0].stripped
        #expect(line == "9s|", "measured for one entry and drawn for another")
        #expect(Set(clock.handed).count == 1, "the schedule was asked about \(Set(clock.handed).count) instants in one frame")
    }

    /// The loop stamps the frame's date beside its monotonic instant, and the
    /// wake is the distance from that date to the next entry, counted from that
    /// instant — so it lands on the entry. Counted from a second read of the
    /// clock, taken however far into the frame the render had got, it fired
    /// that much early, and the frame it woke began short of the boundary.
    @Test("The loop resolves a timeline against the frame's date, and wakes it exactly at the next entry")
    func wakeIsCountedFromTheFrameDate() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(WakeApp())
        let scheduler = AnimationScheduler()
        let nanos = 5 * second
        scheduler.beginFrame()
        loop.render(animationScheduler: scheduler, frameNowNanos: nanos, frameDate: WakeApp.date)
        scheduler.endFrame()
        #expect(scheduler.nextFiring(after: nanos) == nanos + second, "the wake missed the entry it was counted to")
    }

    // MARK: - The size, across frames

    /// A timer beside a bar, memoized by a title that never changes: the shape
    /// of a `ForEach` row over a timer that counts up. The timer's text grows
    /// from "9s" to "100s" with the clock, and nothing else about the row does.
    private func timerRow(_ clock: SteppedClock) -> some View {
        HStack(spacing: 0) {
            TitledTimer(title: "t", schedule: SteppedSchedule(clock: clock)).equatable()
            Text("|")
        }
    }

    /// The same, with the timer as a plain button's label — which the button
    /// measures by RENDERING it, under `isMeasuring`, rather than by asking its
    /// size.
    private func buttonedTimerRow(_ clock: SteppedClock) -> some View {
        HStack(spacing: 0) {
            ButtonedTimer(title: "t", schedule: SteppedSchedule(clock: clock)).equatable()
            Text("|")
        }
    }

    /// The picture was never kept for a timeline with an entry ahead — the wake
    /// it declares is a side effect no memo can replay — but its SIZE was: the
    /// measure declared nothing, so the cross-frame size memo stored the width
    /// the first entry measured and served it at every later one.
    @Test("A timeline with an entry ahead is measured again on every frame, not served its first size")
    func liveTimelineSizeIsNotServed() {
        let (tui, context, scheduler) = harness()
        let clock = SteppedClock(seconds: 9)
        let row = timerRow(clock)
        #expect(render(row, tui: tui, context: context, scheduler: scheduler).lines[0].stripped == "9s|")
        _ = render(row, tui: tui, context: context, scheduler: scheduler)
        clock.seconds = 100
        let later = render(row, tui: tui, context: context, scheduler: scheduler).lines[0].stripped
        #expect(later == "100s|", "the row was laid out at the width of the entry before")
    }

    /// A measure that renders asks for no wake — `requestWake` is a no-op while
    /// measuring — so a timeline measured that way declared nothing at all, and
    /// the size memo above the button kept the first entry's width.
    @Test("A timeline measured by being rendered, as a plain button's label is, is not served its first size")
    func liveTimelineMeasuredByRenderingIsNotServed() {
        let (tui, context, scheduler) = harness()
        let clock = SteppedClock(seconds: 9)
        let row = buttonedTimerRow(clock)
        // After the focus mark, which the one button on the page wears.
        #expect(render(row, tui: tui, context: context, scheduler: scheduler).lines[0].stripped.hasSuffix(" 9s|"))
        _ = render(row, tui: tui, context: context, scheduler: scheduler)
        clock.seconds = 100
        let later = render(row, tui: tui, context: context, scheduler: scheduler).lines[0].stripped
        #expect(later.hasSuffix(" 100s|"), "the button was laid out at the width of the entry before: \(later)")
    }

    /// The other direction from the timer above: rows BELOW the timeline that
    /// read its date — a list of "5 min ago" stamps under `.everyMinute`. Each
    /// `ForEach` row is memoized by its element, which the clock does not move,
    /// and the clock is not a write the cache sees, so every row was served as
    /// the first entry drew it, for as long as the list was on screen.
    @Test("Rows that read the timeline's date are drawn for the current entry")
    func rowsReadingTheDateFollowIt() {
        let (tui, context, scheduler) = harness()
        let clock = SteppedClock(seconds: 1)
        let list = TimelineView(SteppedSchedule(clock: clock)) { timeline in
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Text(verbatim: "row \(index) at \(Int(timeline.date.timeIntervalSinceReferenceDate))")
                }
            }
        }
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        clock.seconds = 7
        let lines = render(list, tui: tui, context: context, scheduler: scheduler).lines.map(\.stripped)
        #expect(lines.prefix(3) == ["row 0 at 7", "row 1 at 7", "row 2 at 7"], "the rows kept the entry before")
    }

    /// And a timeline whose entry did NOT move leaves the rows below it
    /// alone — the clear is on a change of entry, not on every frame.
    ///
    /// Asked of the subtree clears rather than of the rows served: a suite
    /// running beside this one that moves a process-wide answer (a colour
    /// depth, the terminal's colours) clears every cache in the process, and
    /// that is not this view clearing anything.
    @Test("A timeline whose entry did not move clears nothing below it")
    func stillEntryClearsNothing() {
        let (tui, context, scheduler) = harness()
        let clock = SteppedClock(seconds: 1)
        let list = TimelineView(SteppedSchedule(clock: clock)) { timeline in
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Text(verbatim: "row \(index) at \(Int(timeline.date.timeIntervalSinceReferenceDate))")
                }
            }
        }
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        let before = tui.renderCache.stats.subtreeClears
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        #expect(tui.renderCache.stats.subtreeClears == before, "a still entry cleared the rows below it")
        clock.seconds = 2
        _ = render(list, tui: tui, context: context, scheduler: scheduler)
        #expect(tui.renderCache.stats.subtreeClears == before + 1, "a moved entry clears once, on one walk")
    }

    /// The rows above, in the frame that straddles an entry boundary. The
    /// timeline notes its entry once a pass, on whichever walk sees it first,
    /// so when the measure saw the entry before the boundary and the render the
    /// one after it, the render's entry was never noted and nothing cleared the
    /// rows: they were served what the entry before drew, under a timeline
    /// drawing the entry after — and, with the wake counted from the render's
    /// read, for a whole period of the schedule.
    @Test("Rows that read the timeline's date agree with it in the frame that straddles a boundary")
    func rowsAgreeInAStraddledFrame() {
        let (tui, context, scheduler) = harness()
        let clock = StraddlingClock(seconds: 1)
        // Beside a bar, so the timeline is laid out — measured — before it is
        // drawn, as it is anywhere but at the root.
        let list = HStack(alignment: .top, spacing: 0) {
            TimelineView(StraddlingSchedule(clock: clock)) { timeline in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "entry \(Int(timeline.date.timeIntervalSinceReferenceDate))")
                    ForEach(0..<3, id: \.self) { index in
                        Text(verbatim: "row \(index) at \(Int(timeline.date.timeIntervalSinceReferenceDate))")
                    }
                }
            }
            Text("|")
        }
        for _ in 0..<2 {
            clock.beginFrame(straddling: false)
            _ = render(list, tui: tui, context: context, scheduler: scheduler)
        }
        clock.beginFrame(straddling: true)
        let lines = render(list, tui: tui, context: context, scheduler: scheduler).lines.map {
            String($0.stripped.reversed().drop { $0 == " " }.reversed())
        }
        let entry = lines[0].dropFirst("entry ".count).prefix { $0.isNumber }
        #expect(
            Array(lines[1...3]) == (0..<3).map { "row \($0) at \(entry)" },
            "the rows and the timeline drew different entries: \(lines.prefix(4))")
    }

    /// What the fix declares, asked of the tracker: a timeline with an entry
    /// ahead reads the clock when it measures — either way it is measured — and
    /// says so; one that has run out of entries is finished changing, and stays
    /// memoizable.
    @Test("Only a timeline with an entry ahead declares its measure unkeyed, however it is measured")
    func onlyALiveTimelineDeclaresItsMeasure() {
        let (_, context, _) = harness()
        func declares(_ view: some View, byRendering: Bool) -> Bool {
            var tracked = context
            let tracker = VolatileReadTracker()
            tracked.environment.volatileReadTracker = tracker
            if byRendering {
                tracked.isMeasuring = true
                _ = renderToBuffer(view, context: tracked)
            } else {
                _ = measureChild(view, proposal: ProposedSize(width: 40, height: 8), context: tracked)
            }
            return tracker.cacheUnsafeCount > 0
        }
        let seen = Seen()
        let past = Date().addingTimeInterval(-600)
        for byRendering in [false, true] {
            #expect(declares(timeline(SteppedSchedule(clock: SteppedClock(seconds: 9)), into: seen), byRendering: byRendering))
            #expect(
                !declares(timeline(.explicit([past]), into: seen), byRendering: byRendering),
                "a finished timeline declared a read")
        }
    }
}

// MARK: - A clock that crosses a boundary mid-frame

/// A clock whose entry boundary falls between two reads of it in one frame:
/// handed the first date it sees, it is at entry `seconds`; handed any LATER
/// date, it has crossed into the next second.
///
/// What the real clock does to a frame that begins just short of a boundary,
/// made certain: two reads of the clock a walk apart are two different dates,
/// and this turns "later" into "the other side".
private final class StraddlingClock {
    let seconds: Double
    /// Whether this frame straddles the boundary; a frame that does not reads
    /// `seconds` however late it asks.
    private var straddles = true
    /// Every date the schedule was handed this frame, in order.
    private(set) var handed: [Date] = []

    init(seconds: Double) { self.seconds = seconds }

    /// A new frame: the next date handed over is its first.
    func beginFrame(straddling: Bool) {
        handed = []
        straddles = straddling
    }

    func entry(for date: Date) -> Date {
        let first = handed.first ?? date
        handed.append(date)
        return Date(timeIntervalSinceReferenceDate: straddles && date > first ? seconds + 1 : seconds)
    }
}

/// A schedule over a ``StraddlingClock``, with one entry always ahead.
private struct StraddlingSchedule: TimelineSchedule {
    let clock: StraddlingClock

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        [clock.entry(for: startDate), .distantFuture]
    }
}

/// A timeline whose next entry is one second after the frame date it is drawn at.
private struct WakeApp: App {
    static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var body: some Scene {
        WindowGroup {
            TimelineView(.explicit([Self.date.addingTimeInterval(-5), Self.date.addingTimeInterval(1)])) { _ in
                Text("tick")
            }
        }
    }
}

// MARK: - A clock a test can step

/// The instant a ``SteppedSchedule`` puts its current entry at — a stand-in for
/// the clock, which a test cannot step.
private final class SteppedClock {
    var seconds: Double

    init(seconds: Double) { self.seconds = seconds }
}

/// A schedule whose current entry is wherever its clock says, with one more
/// always ahead: to the view, a `.periodic` schedule the clock has moved
/// along, wake and all.
private struct SteppedSchedule: TimelineSchedule {
    let clock: SteppedClock

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        [Date(timeIntervalSinceReferenceDate: clock.seconds), .distantFuture]
    }
}

/// A timer memoized by a title that ignores it, so only the clock moves it.
private struct TitledTimer: View, @preconcurrency Equatable {
    let title: String
    let schedule: SteppedSchedule

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        TimelineView(schedule) { context in
            Text(verbatim: "\(Int(context.date.timeIntervalSinceReferenceDate))s")
        }
    }
}

/// The same timer as a plain button's label, memoized the same way.
private struct ButtonedTimer: View, @preconcurrency Equatable {
    let title: String
    let schedule: SteppedSchedule

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Button {
        } label: {
            TimelineView(schedule) { context in
                Text(verbatim: "\(Int(context.date.timeIntervalSinceReferenceDate))s")
            }
        }
        .buttonStyle(.plain)
    }
}
