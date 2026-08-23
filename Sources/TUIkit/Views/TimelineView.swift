//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TimelineView.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitView

// MARK: - TimelineView

/// A view that updates its content on a schedule.
///
/// The content closure receives the date it is being rendered for, and the view
/// re-renders itself at each of its schedule's later entries — asking the run
/// loop to wake exactly then, and nothing in between.
///
/// ```swift
/// TimelineView(.everyMinute) { context in
///     Text(context.date, style: .time)
/// }
/// ```
///
/// The date is the schedule's *entry*, not the instant of the render: with
/// ``TimelineSchedule/everyMinute`` it is the top of the current minute however
/// late in that minute the frame lands, so a clock never shows a time that
/// disagrees with the boundary it was drawn for.
///
/// A ``TimelineView`` costs nothing between entries. It declares one wake — the
/// next entry — and the run loop sleeps until then, so a clock ticking once a
/// minute renders once a minute rather than joining a poll. A schedule that
/// runs out of entries (an exhausted ``TimelineSchedule/explicit(_:)``, or a
/// paused ``TimelineSchedule/animation``) declares no wake at all, and the
/// screen goes fully idle.
public struct TimelineView<Schedule, Content> where Schedule: TimelineSchedule {
    /// What the content is being rendered for.
    public struct Context {
        /// How often the view is being updated.
        ///
        /// SwiftUI reports a reduced cadence on a display in an always-on
        /// low-power state, so that content can drop its seconds hand. A
        /// terminal has no such state — measured on macOS, SwiftUI itself
        /// reports ``live`` for every schedule — so this is always ``live``
        /// here. It exists so content written against SwiftUI compiles and
        /// reads the same.
        public enum Cadence: Comparable, Hashable, Sendable {
            /// Updating as often as the schedule asks.
            case live
            /// Updating about once a second.
            case seconds
            /// Updating about once a minute.
            case minutes
        }

        /// The schedule entry this render is for.
        public let date: Date

        /// The rate at which the view is being updated.
        public let cadence: Cadence
    }

    let schedule: Schedule
    let content: (TimelineViewDefaultContext) -> Content
}

/// The context type a ``TimelineView``'s content closure receives.
///
/// One concrete type rather than one per schedule, so a closure written for a
/// timeline can be handed to any of them.
public typealias TimelineViewDefaultContext = TimelineView<
    EveryMinuteTimelineSchedule, Never
>.Context

extension TimelineView where Content: View {
    /// Creates a view that updates on the given schedule.
    ///
    /// - Parameters:
    ///   - schedule: When to update — ``TimelineSchedule/everyMinute``,
    ///     ``TimelineSchedule/periodic(from:by:)``,
    ///     ``TimelineSchedule/explicit(_:)``, ``TimelineSchedule/animation``,
    ///     or your own ``TimelineSchedule``.
    ///   - content: Builds the content for the entry being rendered.
    public init(
        _ schedule: Schedule,
        @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }
}

extension TimelineView: View where Content: View {
    public var body: some View {
        _TimelineViewCore(schedule: schedule, content: content)
    }
}

// MARK: - Core

/// Resolves the schedule against the clock, declares the next wake, and renders
/// the content the schedule's current entry produces.
private struct _TimelineViewCore<Schedule: TimelineSchedule, Content: View>: View, Renderable,
    Layoutable
{
    let schedule: Schedule
    let content: (TimelineViewDefaultContext) -> Content

    var body: Never { fatalError("_TimelineViewCore renders via Renderable") }

    /// The entry to render for, and the instant to wake at next.
    ///
    /// The entry is the schedule's *first* — a schedule is responsible for
    /// starting its sequence at the entry a view should be showing, which is
    /// how `everyMinute` puts a clock in the right minute on its first frame.
    /// (Measured against SwiftUI, which shows the first entry even when the
    /// whole schedule is in the past or the future.) The wake is the first
    /// entry strictly after `now`; there may be none, and then the view is
    /// finished changing.
    private func resolve(now: Date) -> (entry: Date, next: Date?) {
        var entry: Date?
        for date in schedule.entries(from: now, mode: .normal) {
            if entry == nil { entry = date }
            if date > now { return (entry ?? date, date) }
        }
        return (entry ?? now, nil)
    }

    private func timelineContext(now: Date) -> (TimelineViewDefaultContext, next: Date?) {
        let (entry, next) = resolve(now: now)
        return (TimelineViewDefaultContext(date: entry, cadence: .live), next)
    }

    /// The timeline is exactly its content, flexibility included — forwarded
    /// rather than measured by rendering, so a flexible child stays flexible.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let (timeline, _) = timelineContext(now: Date())
        return measureChild(content(timeline), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let now = Date()
        let (timeline, next) = timelineContext(now: now)
        if let next {
            // One wake, for the next entry only. The frame it produces declares
            // the one after it, so an irregular schedule stays exact and a
            // finished one stops asking.
            context.requestWake(
                token: "timeline-\(context.identity.path)",
                afterSeconds: next.timeIntervalSince(now))
        }
        return TUIkitView.renderToBuffer(content(timeline), context: context)
    }
}
