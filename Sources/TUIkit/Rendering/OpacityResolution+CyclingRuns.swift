//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityResolution+CyclingRuns.swift
//
//  The runs a repeating fade replays as: each phase of the fade blended once,
//  when what is behind it is known, and handed to the run loop as frames.
//  Split from `OpacityResolution.swift`, which was past the file-length warning.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension FrameBuffer {

    /// The runs that let a repeating fade replay instead of re-render.
    ///
    /// Each phase is the same rows rebuilt at a different alpha, against the
    /// same destination — so the whole cycle costs one render of the content
    /// plus N re-colourings of finished lines, and the loop then never asks the
    /// view again. What made this hard to keep is that the colouring can only
    /// happen once the destination is known, which is here and not at the
    /// modifier; see `Documentation/Opacity as composition.md` §6b.
    ///
    /// A run covers the whole ROW rather than the region's columns, which is
    /// what makes the frame the loop splices byte-identical to the line the
    /// render drew rather than merely equivalent to it.
    ///
    /// Which is also why this emits at most ONE run per row, holding every fade
    /// on that row at once. `FrameBuffer.patchingAnimatedCells` REPLACES the span
    /// a run claims rather than merging into it, so two whole-row runs on one row
    /// means the one the replay applies second overwrites the first — and since
    /// each was built with the other region pinned at the static opacity it was
    /// drawn at, the loser's cells snap back to that value on every tick and its
    /// fade never moves. So the phases are walked in a COMBINED tick space
    /// instead: the smallest number of ticks every cycle on the row divides into,
    /// with each region reading its own phase at each of them.
    ///
    /// One run per row *from here*, which is not yet one run per row on the
    /// screen: a run some other view left OUTSIDE every region's columns is kept
    /// by the drop above (its `covering` is empty), and a whole-row run still
    /// replaces its cells. `HStack { Text(…).opacity(breathing); Spinner() }` is
    /// that shape, and the spinner still freezes. Same cause, separate fix.
    static func cyclingRuns(
        of regions: [OpacityRegion],
        over lines: [String],
        rebuilding rebuild: (Int, String, (OpacityRegion) -> FrameBuffer.CellAlpha?) -> String?
    ) -> [AnimatedCellRun] {
        let cycling = regions.filter { ($0.cycle?.phases.count ?? 0) >= 2 }
        guard !cycling.isEmpty else { return [] }
        var runs: [AnimatedCellRun] = []
        // By ROW, not by region: a run claims a whole row, so a row's fades have
        // to be answered together or the second answer erases the first.
        for row in lines.indices {
            let onRow = cycling.filter { $0.spans(row: row) }
            guard let innermost = onRow.first, let cycle = innermost.cycle else { continue }
            // One run carries one clock, so only the cycles sharing the innermost
            // one's clock can join the merge. Every `.opacity` cycle is on
            // `.content`, so this is a guard against a future producer rather
            // than a case that runs today.
            let onClock = onRow.filter { $0.cycle?.clock == cycle.clock }
            // `nil` past the budget, where the merged frames would outweigh the
            // renders they save — two coprime cycles near the cap are ten
            // thousand finished lines. Then the innermost fade animates alone and
            // the rest hold at the value they were drawn at: frozen, but frozen
            // identically on every tick, which is the whole difference from two
            // runs fighting over one row.
            let merged = Self.combinedSteps(of: onClock)
            let steps = merged ?? cycle.phases.count
            var phases: [[String]] = []
            phases.reserveCapacity(steps)
            for step in 0..<steps {
                let rebuilt = rebuild(
                    row, lines[row],
                    { region in
                        // Asked of the region itself rather than by searching the
                        // merged list: `rebuild` already narrowed `covering` to
                        // this row, so "has a cycle, on this clock" IS membership
                        // — and this closure runs once per COLUMN per step, where
                        // an `OpacityRegion ==` costs a phase-array walk.
                        guard let values = region.cycle?.phases, values.count >= 2,
                            region.cycle?.clock == cycle.clock,
                            merged != nil || region == innermost
                        else { return region.cellAlpha }
                        // Its OWN phase at this one step. Pinning the others at
                        // `opacity` — which is what a per-region run did — is
                        // exactly what let the run applied second revert the
                        // first's cells.
                        //
                        // The LAYER channel is the one that cycles; a colour's
                        // alpha does not animate itself (an animated one is a
                        // fresh region per frame through the ordinary render
                        // path), so the other two ride along unchanged.
                        return FrameBuffer.CellAlpha(
                            layer: values[step % values.count],
                            ink: region.inkOpacity, field: region.fieldOpacity)
                    })
                phases.append([rebuilt ?? lines[row]])
            }
            // `nil` where the phases disagree about the shape of the picture: a
            // run cannot change a row's width, and one that tried would shift
            // the rest of the row sideways on some ticks and not others.
            guard
                let built = AnimatedBufferCycle.runs(
                    phases: phases, offsetY: row, clock: cycle.clock)
            else { continue }
            runs += built
        }
        return runs
    }

    /// The smallest number of steps every cycle in `regions` divides into, so one
    /// run can hold all of them: at step `t` each region reads
    /// `phases[t % phases.count]`, and a common multiple is what keeps that the
    /// index the render drew with — `(t % N) % n == t % n` exactly when `n`
    /// divides `N`.
    ///
    /// `nil` past ``AnimationCycle/maximumSteps``, the budget one cycle is
    /// already held to, for the same reason: a run holds one finished string per
    /// step per row.
    ///
    /// Walked up in strides of the longest cycle rather than through a GCD: at most
    /// `maximumSteps / longest` remainders, no second copy of
    /// `GradientRaster.greatestCommonDivisor`, and it stops AT the budget instead
    /// of first computing a product that overshoots it by orders of magnitude.
    private static func combinedSteps(of regions: [OpacityRegion]) -> Int? {
        let counts = regions.compactMap { $0.cycle?.phases.count }
        guard let longest = counts.max(), longest > 0 else { return nil }
        var steps = longest
        while steps <= AnimationCycle<Double>.maximumSteps {
            if counts.allSatisfy({ steps.isMultiple(of: $0) }) { return steps }
            steps += longest
        }
        return nil
    }
}
