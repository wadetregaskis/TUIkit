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
    public private(set) var reads: Int = 0

    /// Creates a tracker with a zero read count.
    public init() {}

    /// Records that a per-frame-volatile environment value was read.
    public func recordVolatileRead() {
        reads &+= 1
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
