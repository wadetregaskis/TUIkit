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
    public private(set) var sideEffects: Int = 0

    /// The combined count a value-memoizing view snapshots around a scoped
    /// render: any delta means the subtree is unsafe to cache.
    public var cacheUnsafeCount: Int { reads &+ sideEffects }

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
