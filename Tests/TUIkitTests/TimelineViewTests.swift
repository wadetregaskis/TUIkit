//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// A render context whose frame clock reads zero, so a declared wake's
    /// firing instant IS the delay that was asked for.
    private func harness(width: Int = 40, height: Int = 8) -> (
        TUIContext, RenderContext, AnimationScheduler
    ) {
        let tui = TUIContext()
        let scheduler = AnimationScheduler()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.animationScheduler = scheduler
        environment.frameNowNanos = 0
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui),
            scheduler
        )
    }

    private func render(
        _ view: some View, tui: TUIContext, context: RenderContext, scheduler: AnimationScheduler
    ) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
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
}
