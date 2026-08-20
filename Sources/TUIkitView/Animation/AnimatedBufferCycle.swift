//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedBufferCycle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Turns "here is what my content looks like at each point of the cycle" into
/// ``AnimatedCellRun``s the run loop can replay.
///
/// The narrow case that can be pre-rendered *soundly*, and it is the case that
/// matters: a modifier whose output is a pure re-styling of a buffer its content
/// already produced. `.opacity(_:)` is the archetype — it renders its content
/// once and then rewrites the colours the renderer named. So the whole cycle
/// costs one render of the content plus N re-stylings of the finished lines,
/// and none of the content's side effects (focus registration, hit-test regions,
/// `onAppear`, preference writes) happen more than once.
///
/// That restriction is the whole design. Re-rendering an arbitrary *subtree*
/// once per phase would multiply every one of those side effects by N — a view
/// would register its focus sixteen times and appear sixteen times — which is
/// why the general "diff N renders of anything" form is not this.
///
/// Rows rather than spans: a run covers a whole line of the modifier's own
/// buffer wherever any phase differs from the others. The buffer belongs to the
/// modifier, so it is only as wide as the thing being animated, and finding the
/// changed columns would mean splitting styled text into cells to save bytes
/// that a small view does not have.
public enum AnimatedBufferCycle {

    /// Runs covering every row that changes across `phases`.
    ///
    /// - Parameters:
    ///   - phases: The buffer's lines at each point of the cycle, indexed the
    ///     way ``AnimatedCellRun/frames`` is — by `tick % count`. Every phase
    ///     must have the same number of lines, and each row must have the same
    ///     visible width in every phase.
    ///   - clock: The clock that advances them.
    /// - Returns: One run per changing row, or `nil` if the phases disagree
    ///   about the shape of the picture — a run cannot change a buffer's shape,
    ///   and emitting one anyway would shift the rest of the row sideways on
    ///   some ticks and not others.
    public static func runs(
        phases: [[String]], clock: AnimationClock = .cursor
    ) -> [AnimatedCellRun]? {
        guard let first = phases.first, phases.count >= 2 else { return nil }
        guard phases.allSatisfy({ $0.count == first.count }) else { return nil }

        var runs: [AnimatedCellRun] = []
        for row in first.indices {
            let frames = phases.map { $0[row] }
            // A row that never changes is a still picture the ordinary render
            // already drew; a run for it would emit bytes every tick to no
            // effect. `AnimatedCellRun.isAnimating` would filter it out later,
            // but not building it is cheaper and says the intent.
            guard frames.contains(where: { $0 != frames[0] }) else { continue }
            let width = frames[0].strippedLength
            guard frames.allSatisfy({ $0.strippedLength == width }) else { return nil }
            runs.append(
                AnimatedCellRun(
                    offsetX: 0, offsetY: row, width: width, frames: frames, clock: clock))
        }
        return runs
    }
}
