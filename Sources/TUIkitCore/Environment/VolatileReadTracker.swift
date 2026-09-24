//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VolatileReadTracker.swift
//
//  Created by LAYERED.work
//  License: MIT

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
    /// modifier reports a change of — the enclosing `ScrollView`'s visible
    /// viewport, which an `Image` fitted to it sizes itself by. The keys see
    /// the extent a view is offered, and under a two-axis view whose content
    /// is wider than its viewport that extent does not move when the terminal
    /// is resized, so a size or a picture memoized against one viewport was
    /// served at another. Like ``reads``, only ever compared as a delta.
    ///
    /// Counted apart from ``reads``, which alone drives the pulse timer: a
    /// viewport is not a function of time, and a view that read one would
    /// otherwise keep the run loop ticking for as long as it was on screen.
    package private(set) var unkeyedReads: Int = 0

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
