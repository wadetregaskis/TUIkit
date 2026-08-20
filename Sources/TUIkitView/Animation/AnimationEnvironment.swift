//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The three facts about the frame being rendered that every animation is a
/// function of.
///
/// One value rather than three environment entries, and the reason is measured.
/// ``EnvironmentValues`` is a dictionary that is copied on every environment
/// modification — which is to say constantly, all the way down every tree — so
/// each entry added to it is paid for by every app on every frame whether or
/// not it animates anything. Three of them cost about 1% of a frame on `table`
/// and `deep`; folded into one they cost a third of that, and the grouping is
/// honest anyway: these are one thing, published once, read together.
public struct AnimationFrame: Sendable, Equatable {
    /// The frame's monotonic-clock timestamp, in nanoseconds.
    ///
    /// The *frame's*, not a live reading: one pass may walk the tree more than
    /// once (the app header's height-discovery re-render), and two walks of one
    /// frame must agree on where every animation has got to. It is also the
    /// anchor an animation grid registers against, so the loop's next-firing
    /// query and the grids agree exactly rather than by a clock read apart.
    public var nowNanos: Int64 = 0

    /// The replay clock's tick count for this frame.
    ///
    /// What an ``AnimatedCellRun``'s frames are indexed by, so a producer that
    /// pre-renders a cycle can lay its frames out to match what the run loop
    /// will replay. See ``AnimationCycle``.
    public var tick: Int = 0

    /// Whether this render can be followed by more of them on a timer.
    ///
    /// False outside the run loop — a one-off snapshot (`ViewRenderer`, a frame
    /// dump) renders once and is done. An animation started there would present
    /// its *old* value and never advance, which is strictly worse than not
    /// animating: the picture would be wrong and stay wrong. So changes snap
    /// when this is false.
    public var canAnimate: Bool = false

    /// Creates a frame description. The defaults describe a one-off render at
    /// the start of time, which is what a headless render is.
    public init(nowNanos: Int64 = 0, tick: Int = 0, canAnimate: Bool = false) {
        self.nowNanos = nowNanos
        self.tick = tick
        self.canAnimate = canAnimate
    }
}

private struct AnimationFrameKey: EnvironmentKey {
    static var defaultValue: AnimationFrame { AnimationFrame() }
}

extension EnvironmentValues {
    /// What this frame's animations are a function of. See ``AnimationFrame``.
    public var animationFrame: AnimationFrame {
        get { self[AnimationFrameKey.self] }
        set { self[AnimationFrameKey.self] = newValue }
    }

    /// The current frame's monotonic-clock timestamp (ns).
    /// See ``AnimationFrame/nowNanos``.
    public var frameNowNanos: Int64 {
        get { animationFrame.nowNanos }
        set { animationFrame.nowNanos = newValue }
    }

    /// The replay clock's tick count for this frame. See ``AnimationFrame/tick``.
    public var animationTick: Int {
        get { animationFrame.tick }
        set { animationFrame.tick = newValue }
    }

    /// Whether a change may animate at all. See ``AnimationFrame/canAnimate``.
    public var canAnimate: Bool {
        get { animationFrame.canAnimate }
        set { animationFrame.canAnimate = newValue }
    }
}
