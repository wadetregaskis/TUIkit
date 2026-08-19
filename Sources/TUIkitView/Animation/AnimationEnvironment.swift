//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// EnvironmentKey for the current frame's monotonic-clock timestamp, in
/// nanoseconds.
private struct FrameNowNanosKey: EnvironmentKey {
    static let defaultValue: Int64 = 0
}

/// EnvironmentKey for whether the frame can actually be re-rendered on a timer.
private struct CanAnimateKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// The current frame's monotonic-clock timestamp (ns).
    ///
    /// The *frame's*, not a live reading: one pass may walk the tree more than
    /// once (the app header's height-discovery re-render), and two walks of one
    /// frame must agree on where every animation has got to. It is also the
    /// anchor an animation grid registers against, so the loop's next-firing
    /// query and the grids agree exactly rather than by a clock read apart.
    public var frameNowNanos: Int64 {
        get { self[FrameNowNanosKey.self] }
        set { self[FrameNowNanosKey.self] = newValue }
    }

    /// Whether this render can be followed by more of them on a timer.
    ///
    /// False outside the run loop — a one-off snapshot (`ViewRenderer`, a frame
    /// dump) renders once and is done. An animation started there would present
    /// its *old* value and never advance, which is strictly worse than not
    /// animating: the picture would be wrong and stay wrong. So changes snap
    /// when this is false.
    public var canAnimate: Bool {
        get { self[CanAnimateKey.self] }
        set { self[CanAnimateKey.self] = newValue }
    }
}
