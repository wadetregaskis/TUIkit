//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationInstant.swift
//
//  One frame's reading of both animation clocks, and what a run shows there.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - One instant on both clocks

/// Where each ``AnimationClock`` stands at one frame: what the frame index of every
/// ``AnimatedCellRun`` drawn in that frame is a function of.
///
/// A buffer holds each of its runs at ONE frame — the one its clock stood at when
/// the buffer was rendered — and only the run loop moves the cells on from there.
/// So something that keeps a buffer to draw again later has to keep this beside
/// it, or it cannot tell whether the picture it holds is still the one its runs
/// would show. `RenderCache` keeps one on every entry whose buffer carries runs.
package struct AnimationInstant: Sendable, Equatable {
    /// How far ``AnimationClock/content`` has run, in seconds.
    package var content: Double

    /// How far ``AnimationClock/cursor`` has run, in seconds.
    package var cursor: Double

    /// Creates an instant from both clocks' elapsed seconds.
    package init(content: Double, cursor: Double) {
        self.content = content
        self.cursor = cursor
    }

    /// How far `clock` has run at this instant, in seconds.
    package func elapsed(on clock: AnimationClock) -> Double {
        switch clock {
        case .content: content
        case .cursor: cursor
        }
    }
}

extension AnimatedCellRun {
    /// Whether this run shows the same thing at `later` as it did at `earlier`: the
    /// same picture, owing the same alpha.
    ///
    /// Not whether the frame INDEX is the same. A pulse quantised to what a
    /// 256-colour terminal can paint holds a shade for several frames, and asking
    /// about the index would call every step through them a change. The (picture,
    /// alpha) pair, as ``timeUntilChange(afterElapsed:)`` compares it, because a
    /// frame that paints the same bytes but owes a different alpha shows something
    /// different once it has been composited.
    package func showsTheSame(at later: AnimationInstant, asAt earlier: AnimationInstant) -> Bool {
        let then = index(atElapsed: earlier.elapsed(on: clock))
        let now = index(atElapsed: later.elapsed(on: clock))
        guard then != now else { return true }
        return frames[then] == frames[now] && alpha?.spans(atFrame: then) == alpha?.spans(atFrame: now)
    }
}
