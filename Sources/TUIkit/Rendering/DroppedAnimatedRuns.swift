//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DroppedAnimatedRuns.swift
//
//  What a container owes the runs it drops.
//
//  A container that keeps a view's lines and discards the runs its content left
//  on them — because they do not fit, because it rebuilds the lines from a copy,
//  or because it repaints those cells whole every tick itself — owes the runs two
//  things they would otherwise have done: what they said about their cells'
//  ALPHA (`Documentation/Opacity as composition.md` §69.4), and, where it drops
//  runs that are still on screen, the renders that would have moved them. A
//  producer that leaves a run behind stops asking to be re-rendered — that is
//  the whole point of leaving one — so nothing else will ask.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The alpha a dropped run leaves

extension AnimatedCellRun {
    /// What this run said about its cells' ALPHA at the frame its lines were drawn
    /// at, as ordinary regions in its own buffer's coordinates — for a site that
    /// keeps those lines and discards the run (§69.4). Right at that frame, frozen
    /// after. Empty for a run that is not animating, which no container carries
    /// either, and for one with no payload.
    var alphaLeftBehind: [OpacityRegion] {
        guard isAnimating, let alpha else { return [] }
        return alpha.drawnRegions(forRunAt: offsetX, offsetY: offsetY)
    }
}

// MARK: - The render a dropped run is owed

extension RenderContext {
    /// Asks the run loop for one render at the soonest next step of runs this view
    /// dropped while their cells stay on screen, each asked on the clock it would
    /// have advanced on — the render those runs are owed. The frame that render
    /// produces asks for the step after, so a spinner under a breathing row costs a
    /// render per step it takes, and only while the row breathes.
    ///
    /// Nothing for no runs, and nothing while measuring.
    ///
    /// - Parameters:
    ///   - token: A stable per-view key, from the structural identity.
    ///   - runs: The rate and clock of each run dropped.
    @MainActor
    func requestWake(token: String, forNextStepOf runs: [(clock: AnimationClock, frameTicks: Int)]) {
        guard !runs.isEmpty, !isMeasuring else { return }
        requestWake(token: token, atNanos: nextStepNanos(of: runs))
    }

    /// When the soonest of `runs` next steps, as an instant on the frame clock.
    ///
    /// Each run is asked on its own clock. ``AnimationClock/content`` is the frame
    /// clock itself. ``AnimationClock/cursor`` counts from the focus epoch the cursor
    /// timer keeps, or from zero without one, which is where a row's breath is
    /// drawn from too. Counted in whole nanoseconds through
    /// `AnimationClock.stepEndNanos`, so the wake is never a nanosecond before the
    /// step it is for.
    @MainActor
    func nextStepNanos(of runs: [(clock: AnimationClock, frameTicks: Int)]) -> Int64 {
        let now = environment.frameNowNanos
        let content = Double(now) / 1_000_000_000
        let cursor = environment.cursorTimer?.elapsed(for: .cursor) ?? 0
        let untilSoonest: Int64 =
            runs.lazy.map { run -> Int64 in
                let elapsed =
                    switch run.clock {
                    case .content: content
                    case .cursor: cursor
                    }
                return AnimationClock.stepEndNanos(atElapsed: elapsed, frameTicks: run.frameTicks)
                    - AnimationClock.nanoseconds(elapsed)
            }.min() ?? 0
        return now &+ untilSoonest
    }
}
