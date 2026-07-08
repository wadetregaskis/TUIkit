//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// Kept separate from ``animationRequests`` because the run loop derives
    /// its *pulse-timer* demand from this count alone; folding animation
    /// requests in would spin the pulse clock whenever any scheduler-driven
    /// animation (a Spinner, say) is on screen.
    public private(set) var reads: Int = 0

    /// Monotonic count of animation requests (`requestAnimation`) made during
    /// the scoped render. Like ``reads``, only ever compared as a delta.
    ///
    /// An animation request means "this subtree's output is a function of
    /// time": its next render differs from this one even though its inputs
    /// compare equal. A value-memoizing view must not cache such a subtree —
    /// serving the cached buffer would both freeze the visible frame *and*
    /// skip the request's per-frame re-declaration, so the scheduler would
    /// drop the animation's grid entirely (the demand-driven loop then stops
    /// ticking it: the nested-Spinner freeze of issue #1).
    public private(set) var animationRequests: Int = 0

    /// Monotonic count of preference writes (`.preference(key:value:)`) and
    /// preference-change registrations made during the scoped render. The
    /// preference stack is rebuilt from scratch every render pass, so a
    /// subtree that publishes (or observes) a preference must re-run each
    /// frame — serving a cached buffer would silently drop its value from
    /// the frame's collection.
    public private(set) var preferenceWrites: Int = 0

    /// The combined count a value-memoizing view snapshots around a scoped
    /// render: any delta means the subtree is unsafe to cache.
    public var cacheUnsafeCount: Int { reads &+ animationRequests &+ preferenceWrites }

    /// Creates a tracker with zero counts.
    public init() {}

    /// Records that a per-frame-volatile environment value was read.
    public func recordVolatileRead() {
        reads &+= 1
    }

    /// Records that the rendering view asked the scheduler to re-render it
    /// periodically (its output is time-varying).
    public func recordAnimationRequest() {
        animationRequests &+= 1
    }

    /// Records that the rendering view published a preference value (or
    /// registered a preference-change observer) — per-frame state that a
    /// cached buffer cannot reproduce.
    public func recordPreferenceWrite() {
        preferenceWrites &+= 1
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
