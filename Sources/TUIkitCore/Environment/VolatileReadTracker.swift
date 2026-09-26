//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VolatileReadTracker.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Volatile Read Tracker

/// Records reads of per-frame-volatile environment values (e.g. `pulsePhase`)
/// during a scoped render, so a value-memoizing view can refuse to cache a
/// subtree whose output depends on them.
///
/// The render cache deliberately does **not** invalidate on the pulse tick —
/// doing so would defeat memoization, since the pulse phase changes every
/// frame. A memoized subtree that *reads* the pulse phase would therefore
/// freeze its animation. ``VolatileReadTracker`` lets `_MemoizedRow` detect
/// that case: it installs a tracker, snapshots ``reads`` around a row's render,
/// and skips caching a row whose render touched a volatile value.
///
/// A single tracker is shared down a subtree (an inner memoizing view reuses
/// the one its ancestor installed), so a volatile read anywhere bubbles up to
/// every enclosing row's snapshot and nesting stays correct.
public final class VolatileReadTracker: @unchecked Sendable {
    /// Monotonic count of volatile-value reads. Only ever compared as a delta
    /// (before vs. after a scoped render), so the absolute value is irrelevant.
    ///
    /// Kept separate from `animationRequests` because the run loop derives
    /// its *pulse-timer* demand from this count alone; folding animation
    /// requests in would spin the pulse clock whenever any scheduler-driven
    /// animation (a Spinner, say) is on screen.
    public private(set) var reads: Int = 0

    /// Monotonic count of per-frame render side effects made during the
    /// scoped render — work that must re-run every frame, which a cached
    /// buffer cannot reproduce. Like ``reads``, only ever compared as a
    /// delta. Recorded by:
    /// - `requestAnimation` — the subtree's output is a function of time;
    ///   a cached buffer would freeze it AND skip the per-frame token
    ///   re-declaration, so the scheduler drops the animation (issue #1);
    /// - the preference modifiers — the preference stack is rebuilt every
    ///   render pass, so a cached publisher's value silently vanishes from
    ///   the frame's collection (and a cached observer stops firing);
    /// - `onChange(of:)` — the change detection is a per-frame comparison;
    ///   a cached row never compares, so changes go permanently unnoticed.
    /// - `.focusSection`, while its section is ACTIVE — an active section hands
    ///   its subtree a breathing indicator drawn from focus state the memo's key
    ///   never sees. While it is inactive the registration is replayed instead
    ///   (below).
    /// - a focus registration the buffer memo cannot make again: one by a
    ///   control that holds the focus, one against a backdrop's or a probe's
    ///   focus manager, and one by a control an offered declaration named. See
    ///   `FocusRegistration.register`.
    /// - a `Button`'s `.keyboardShortcut` whose carrier was planted ABOVE the
    ///   memo — the modifier offers its shortcut to the first control that
    ///   renders under it, and on a served frame none does, so the offer would
    ///   stand while a replay registered anyway. Planted inside the memo the
    ///   registration is replayed instead (below). See
    ///   `KeyboardShortcutRegistrar`.
    /// - `.defaultFocus`, under a backdrop's or a probe's focus manager — the
    ///   declaration is discarded with the throwaway, so a subtree stored from
    ///   that render would be served against the live manager having never
    ///   declared its default. Elsewhere it is replayed instead (below).
    /// - `NavigationSplitView`, with a focus manager — its column sections, its
    ///   dividers' and edge's focus registrations, and the hand-over of the
    ///   keyboard when a column hides.
    /// - `NavigationStack`, while a screen is pushed — that depth's focus
    ///   section, the Escape handler and its status-bar claim, and the
    ///   collections that read the root's and the screen's titles.
    /// - `.transition(_:)`, twice: the view carrying one, which re-declares
    ///   its parting picture every frame it is present, and the `nil` it
    ///   leaves behind, for every frame it spends drawing that picture
    ///   part-way gone. A buffer stored on the first frame of a removal was
    ///   served on every frame after it, the view frozen where it started
    ///   leaving until the row's value next changed.
    ///
    /// The pattern is the same each time: a **per-frame registry** the render
    /// loop empties and the view tree refills. Anything that writes to one
    /// belongs here, because nothing in the rendered buffer reveals the
    /// registration (unlike hit-test regions and overlays, which travel in the
    /// buffer and so are gated directly).
    public private(set) var sideEffects: Int = 0

    /// Monotonic count of per-frame registrations the buffer memo can make
    /// again on a cache hit, because the registrar also recorded them in the
    /// render cache's effect journal. Like ``sideEffects``, only ever compared
    /// as a delta. Recorded by:
    /// - `onKeyPress`, once per registration on a render pass;
    /// - `.refreshable`, once per Ctrl-R binding on a render pass;
    /// - `.statusBarItems`, once per registration with a status bar;
    /// - `FocusRegistration.register`, once per interactive control whose
    ///   registration a hit can make again — every control that does not fall
    ///   into one of the four cases listed under ``sideEffects``;
    /// - `.focusSection`, once per section registered while it is inactive;
    /// - `.defaultFocus`, once per declaration against a live focus manager;
    /// - `.focused(_:)` / `.focused(_:equals:)`, once per value↔id binding —
    ///   under a backdrop's manager too, where it binds nothing but is still
    ///   recorded, which scopes a stored subtree to the backdrop;
    /// - a `Button`'s `.keyboardShortcut`, once per registration whose carrier
    ///   was planted inside the memo now recording;
    /// - a hit-test handler, once per registration a render walk makes with a
    ///   mouse dispatcher — the handler table is emptied every walk, and the
    ///   region naming it travels in the buffer, so a served frame has to file
    ///   the closure again under the id its region already carries;
    /// - a mouse feature request, once per `.motion` / `.drag` / `.clicks` /
    ///   `.scrolling` a control asks for, which is per-frame state in the same
    ///   way and would otherwise lapse the first time the control was served;
    /// - each of the drag session's three per-frame registrations — a drop
    ///   destination, a drag auto-scroll zone, a row-reorder host — which
    ///   `DragAndDropSession.beginFrame()` empties exactly as the handler table
    ///   is emptied, and which nothing in the buffer reveals: a served
    ///   destination kept its region and its handler and accepted nothing;
    /// - the buffer memo itself, once per hit that replays a stored subtree's
    ///   registrations, so an enclosing gate sees the same delta whether the
    ///   subtree rendered or was served.
    ///
    /// Counted apart from ``sideEffects`` so that only a gate that replays can
    /// leave it out. Every other gate reads ``cacheUnsafeCount``, which
    /// includes it: the measure memo, `List`'s hug-width memo and the size
    /// half of the value memo replay nothing, so a registration has to stop
    /// them exactly as it did before it became replayable.
    public private(set) var replayableEffects: Int = 0

    /// Monotonic count of reads of a value that no memo KEYS on and that no
    /// modifier reports a change of. Recorded by:
    /// - the enclosing `ScrollView`'s visible viewport, which an `Image` fitted
    ///   to it sizes itself by. The keys see the extent a view is offered, and
    ///   under a two-axis view whose content is wider than its viewport that
    ///   extent does not move when the terminal is resized, so a size or a
    ///   picture memoized against one viewport was served at another;
    /// - a `TimelineView`'s MEASURE, while its schedule has an entry ahead —
    ///   asked for its size, or rendered under `isMeasuring` as a plain
    ///   button's label is: the clock moves the entry its content is sized for.
    ///   Its render declares a wake instead (a side effect), but a measure
    ///   declares none. Recorded through ``recordClockedRead(movingAt:)``,
    ///   which also says when the entry moves (``clockedReads``);
    /// - a notification host's read of its service's toasts, which a `post`
    ///   changes without writing anything the render cache sees.
    ///
    /// Like ``reads``, only ever compared as a delta.
    ///
    /// Counted apart from ``reads``, which alone drives the pulse timer: a
    /// viewport is not a function of time, and a view that read one would
    /// otherwise keep the run loop ticking for as long as it was on screen.
    package private(set) var unkeyedReads: Int = 0

    /// Of ``unkeyedReads``, those a live `TimelineView`'s measure made. The
    /// clock moves such a timeline's entry, and with it its size, but only at
    /// instants the timeline knows in advance. ``clockMovesAt`` is the earliest
    /// of those instants.
    ///
    /// Counted apart so that the two memos that keep ONE width for a whole
    /// collection of views — a windowed stack's widest row and a hugging
    /// `List`'s — can keep what a walk measured until the clock next moves.
    /// Refused, as every other memo refuses it, such a memo walks every row
    /// on every frame whenever each row holds a live timeline: a log of 400
    /// lines with a "5 min ago" on each rebuilt 824 rows a frame in a two-axis
    /// scroll view, and 800 in a hugging `List`. Kept until the next entry,
    /// 24 and 10: the rows on screen. See ``sizeHold(since:)``.
    /// (A `Table`'s `.fit` column is the third such memo, and needs nothing:
    /// it measures cell STRINGS, which no timeline can be read into.)
    package private(set) var clockedReads: Int = 0

    /// The earliest instant at which a read counted in ``clockedReads`` since
    /// the innermost open scope began (``beginScope()``) moves, or `nil` when
    /// there has been none.
    ///
    /// Per scope, not per tracker, because a tracker is shared: the frame's own
    /// is installed at the root and every walk measures under it. Kept for the
    /// tracker's life, a clock ticking each second in a header would lapse the
    /// width of a log whose rows move once a minute every second, and an
    /// `.animation` timeline anywhere would lapse it every frame. A tracker
    /// kept across frames (the Stress harness installs one per context) would
    /// hold an instant long past, and nothing it measured could be kept at all.
    package private(set) var clockMovesAt: Date?

    /// The combined count a value-memoizing view snapshots around a scoped
    /// render: any delta means the subtree is unsafe to cache.
    public var cacheUnsafeCount: Int { reads &+ sideEffects &+ replayableEffects &+ unkeyedReads }

    /// Everything in ``cacheUnsafeCount`` except ``replayableEffects``: the
    /// count the buffer memo's store gate reads, since that memo stores a
    /// subtree's replayable registrations with its buffer and makes them again
    /// on every hit.
    public var unreplayableCount: Int { reads &+ sideEffects &+ unkeyedReads }

    /// Creates a tracker with zero counts.
    public init() {}

    /// Records that a per-frame-volatile environment value was read.
    public func recordVolatileRead() {
        reads &+= 1
    }

    /// Records a per-frame render side effect (an animation request, a
    /// preference write/observation, an `onChange` comparison, …) — work a
    /// cached buffer cannot reproduce, so the value memos must decline to
    /// cache the subtree that performed it.
    public func recordRenderSideEffect() {
        sideEffects &+= 1
    }

    /// Records a per-frame registration the buffer memo can replay — see
    /// ``replayableEffects``.
    public func recordReplayableEffect() {
        replayableEffects &+= 1
    }

    /// Records a read of a value no memo keys on — see ``unkeyedReads``.
    package func recordUnkeyedRead() {
        unkeyedReads &+= 1
    }

    /// Records a read of the clock that moves at `instant` and not before — a
    /// live timeline's measure, and its next entry. It is an unkeyed read
    /// (``unkeyedReads``), so every memo that refuses one refuses this too; see
    /// ``clockedReads`` for the memos that need not.
    package func recordClockedRead(movingAt instant: Date) {
        unkeyedReads &+= 1
        clockedReads &+= 1
        clockMovesAt = SizeHold.earlier(clockMovesAt, instant)
    }

    /// Records that an answer kept until `instant` was served, as the clocked
    /// read it stands for; nothing when it does not lapse.
    ///
    /// The two memos that keep a width for a whole collection until a row's
    /// timeline moves answer from what they kept, with no timeline measured,
    /// so a served answer read no clock. Said nothing, the memo above it — a
    /// `ForEach` row or an `.equatable()` view around the stack or the list —
    /// stored it from the second frame on with no lapse, and kept it after the
    /// width it was taken from had lapsed: an answer over several parts must
    /// hold no longer than any part (``SizeHold/earlier(_:_:)``), and the
    /// served answer is one of the parts.
    package func recordServedHold(lapsingAt instant: Date?) {
        guard let instant else { return }
        recordClockedRead(movingAt: instant)
    }

    /// Where a scope whose answer a memo may keep across frames began: the
    /// counts then, and the enclosing scopes' ``clockMovesAt``, set aside while
    /// this one collects its own.
    package struct Mark {
        fileprivate let unsafe: Int
        fileprivate let clocked: Int
        fileprivate let enclosing: Date?
    }

    /// Begins a scope whose answer a memo may keep across frames, for
    /// ``sizeHold(since:)``. Pair it with ``endScope(_:)`` in a `defer`, so
    /// every way out of the scope ends it: a scope left open would hide the
    /// instants measured before it from the scopes enclosing it, and one of
    /// them could keep an answer past the instant it lapses at.
    package func beginScope() -> Mark {
        defer { clockMovesAt = nil }
        return Mark(unsafe: cacheUnsafeCount, clocked: clockedReads, enclosing: clockMovesAt)
    }

    /// Ends the scope `mark` began. What it collected joins what the scopes
    /// enclosing it collected, since they measured it too.
    package func endScope(_ mark: Mark) {
        clockMovesAt = SizeHold.earlier(mark.enclosing, clockMovesAt)
    }

    /// How long a size measured since `mark` holds, for a memo that keeps
    /// one answer for a whole collection across frames and lets it lapse:
    /// `nil` when it must not be kept at all, because the scope read something
    /// or did something that ``cacheUnsafeCount`` counts, and it was not only
    /// the clock.
    package func sizeHold(since mark: Mark) -> SizeHold? {
        let clocked = clockedReads &- mark.clocked
        guard cacheUnsafeCount &- mark.unsafe == clocked else { return nil }
        guard clocked > 0, let clockMovesAt else { return .indefinitely }
        return .until(clockMovesAt)
    }
}

/// How long a kept size holds — see ``VolatileReadTracker/sizeHold(since:)``.
package enum SizeHold: Equatable {
    /// Until something the memo's own invalidation sees moves.
    case indefinitely
    /// Until the frame drawn at this instant or later, when the clock moves
    /// a timeline that was measured for it.
    case until(Date)

    /// The instant it lapses, if it does.
    package var lapsesAt: Date? {
        switch self {
        case .indefinitely: nil
        case .until(let instant): instant
        }
    }

    /// The earlier of two lapses, where `nil` never lapses: an answer over
    /// several parts holds no longer than any part of it.
    package static func earlier(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return min(lhs, rhs)
    }
}

private struct VolatileReadTrackerKey: EnvironmentKey {
    static var defaultValue: VolatileReadTracker? { nil }
}

extension EnvironmentValues {
    /// The active volatile-read tracker, if a value-memoizing view installed
    /// one for its subtree.
    ///
    /// Getters of per-frame-volatile values (notably `pulsePhase`) call
    /// ``VolatileReadTracker/recordVolatileRead()`` on this when it is present.
    /// It is `nil` everywhere outside a memoized row's render, so the read path
    /// pays only a single optional check.
    public var volatileReadTracker: VolatileReadTracker? {
        get { self[VolatileReadTrackerKey.self] }
        set { self[VolatileReadTrackerKey.self] = newValue }
    }
}
