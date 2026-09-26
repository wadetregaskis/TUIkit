//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// The instant the schedule is resolved against: the FRAME's wall clock,
    /// stamped once beside its monotonic `frameNowNanos` (`RenderCache.frameDate`),
    /// and the clock itself only where nothing stamps frames.
    ///
    /// Not the clock at each read. The measure and the render each read it for
    /// themselves, and a frame that began just before an entry boundary measured
    /// the entry before it and drew the one after it: a timer laid out for "9s"
    /// drew "10s" into its two cells, "1…". And the wake was counted from the
    /// render's read but added to the frame's instant, so it fired early by
    /// however far into the frame the render had got, and the next frame began
    /// just short of the boundary it was woken for — ready to straddle it again.
    private func frameDate(_ context: RenderContext) -> Date {
        context.renderCache?.frameDate ?? Date()
    }

    /// Declares a MEASURE of a timeline with an entry still ahead, and the
    /// instant that entry moves
    /// (``VolatileReadTracker/recordClockedRead(movingAt:)``): its size is its
    /// current entry's, and the clock moves the entry without anything a memo
    /// keys on moving. The render declares itself through the wake it
    /// requests, but a measure requests nothing (`requestWake` is a no-op while
    /// measuring), so the cross-frame size memo above a `.equatable()` view or
    /// a `ForEach` row stored the first entry's size and served it at every
    /// later one — a timer counting from "9s" to "100s" was laid out two cells
    /// wide and drew "1…". A finished timeline declares nothing: its entry can
    /// no longer move, and its size is safe to keep.
    ///
    /// Both ways a timeline is measured declare: through ``sizeThatFits(proposal:context:)``,
    /// and by being rendered under `isMeasuring` — a plain `Button` measures
    /// its label that way, so a timer in one went undeclared.
    ///
    /// Not a volatile read, which would keep the pulse clock running for a
    /// timeline that wakes once a minute; and it costs the per-pass measure
    /// memo too, above a live timeline, since the two gates count the same
    /// reads — the price the viewport read already pays. The two memos that
    /// keep one width for a whole collection (a windowed stack's widest row, a
    /// hugging `List`'s) keep it until `next` instead, because refusing it
    /// walks every row on every frame.
    private func declareMeasure(next: Date?, context: RenderContext) {
        guard let next else { return }
        context.environment.volatileReadTracker?.recordClockedRead(movingAt: next)
    }

    /// The timeline is exactly its content, flexibility included — forwarded
    /// rather than measured by rendering, so a flexible child stays flexible.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let (timeline, next) = timelineContext(now: frameDate(context))
        declareMeasure(next: next, context: context)
        return measureChild(content(timeline), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let now = frameDate(context)
        let (timeline, next) = timelineContext(now: now)
        if context.isMeasuring { declareMeasure(next: next, context: context) }
        if let next {
            // One wake, for the next entry only. The frame it produces declares
            // the one after it, so an irregular schedule stays exact and a
            // finished one stops asking.
            let token = "timeline-\(context.identity.path)"
            if let frameTicks = (schedule as? AnimationTimelineSchedule)?.frameTicks {
                // An animation schedule's pace is the framework's frame rate, not
                // dates the app chose, so it wakes where the next frame of its
                // lattice begins, as every other animation of whole ticks does,
                // rather than a sixtieth after whenever this render landed. The
                // content still saw the frame's own date.
                context.requestWake(
                    token: token,
                    atNanos: AnimationClock.nanoseconds(
                        ofNextTickMultiple: frameTicks, after: context.environment.frameNowNanos))
            } else {
                context.requestWake(token: token, afterSeconds: next.timeIntervalSince(now))
            }
        }
        return TUIkitView.renderToBuffer(content(timeline), context: context)
    }
}
