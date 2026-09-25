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
    /// A run covers the columns its fades cover and no more: a group of fades
    /// that overlap on a row, from its first covered column to its last. Its
    /// frames are cut from the rows rebuilt by the SAME function that rebuilt
    /// the lines, so the frame the loop splices at the tick the render drew
    /// shows exactly the cells the render drew. It used to cover the WHOLE row,
    /// and the tick replaces the span a run claims rather than merging into it:
    /// a run beside the fade on the same row — a spinner — was put back at the
    /// frame it was drawn with on every tick, and froze where a render at the
    /// same instant moves it on (`Opacity as composition.md` §6b.1).
    ///
    /// Fades that DO overlap are one run, walked in a COMBINED tick space: the
    /// smallest number of ticks every cycle in the group divides into, each
    /// region reading its own phase at each of them. Two runs over one cell
    /// fight — the one the replay applies second reverts the first's cells to
    /// the phase it was drawn at, on every tick — which is why a whole-row run
    /// had held every fade on its row.
    ///
    /// And a run the fades cover (`folding`) that steps on the same clock at the
    /// same frame length as they do joins the same space: its frame at each step
    /// is spliced into the row before the row is rebuilt. That is what a fade a
    /// painter has already spent into a run of its own is — a `.listRowBackground`
    /// spends its content's — under an outer repeating fade: dropped, as every run
    /// under a repeating fade was, it froze at the phase it was drawn at. A run
    /// that steps at a speed of its own — a spinner — has no product one run can
    /// hold within the budget: it yields, its cells frozen at the frame the lines
    /// were drawn with, inside a fade that keeps animating.
    ///
    /// - Parameters:
    ///   - regions: Every claim the resolution folds, in its order.
    ///   - lines: The buffer's lines, unresolved.
    ///   - runs: The buffer's runs, unresolved: the candidates to fold in.
    ///   - rebuild: The resolution's rebuild of a row's `line` at the alphas a
    ///     closure answers per region, or `nil` where it leaves the row alone.
    /// - Returns: One run per group of overlapping repeating fades on each row.
    static func cyclingRuns(
        of regions: [OpacityRegion],
        over lines: [String],
        folding runs: [AnimatedCellRun],
        rebuilding rebuild: (Int, String, (OpacityRegion) -> FrameBuffer.CellAlpha?) -> String?
    ) -> [AnimatedCellRun] {
        let cycling = regions.filter { ($0.cycle?.phases.count ?? 0) >= 2 }
        guard !cycling.isEmpty else { return [] }
        var built: [AnimatedCellRun] = []
        for row in lines.indices {
            let onRow = cycling.filter { $0.spans(row: row) }
            guard !onRow.isEmpty else { continue }
            for group in overlapping(onRow) {
                if let run = cyclingRun(of: group, on: row, line: lines[row], folding: runs, rebuilding: rebuild) {
                    built.append(run)
                }
            }
        }
        return built
    }

    /// `regions` — the repeating fades on one row, in the resolution's order — in
    /// groups whose columns overlap, each group in that order.
    private static func overlapping(_ regions: [OpacityRegion]) -> [[OpacityRegion]] {
        let byStart = regions.indices.sorted { regions[$0].offsetX < regions[$1].offsetX }
        var groups: [[Int]] = []
        var end = Int.min
        for index in byStart {
            let region = regions[index]
            if groups.isEmpty || region.offsetX >= end {
                groups.append([index])
                end = region.offsetX + region.width
            } else {
                groups[groups.count - 1].append(index)
                end = max(end, region.offsetX + region.width)
            }
        }
        return groups.map { $0.sorted().map { regions[$0] } }
    }

    /// The run for one group of overlapping repeating fades on `row`, or `nil`
    /// where it would not animate or cannot be built.
    private static func cyclingRun(
        of group: [OpacityRegion], on row: Int, line: String, folding runs: [AnimatedCellRun],
        rebuilding rebuild: (Int, String, (OpacityRegion) -> FrameBuffer.CellAlpha?) -> String?
    ) -> AnimatedCellRun? {
        guard let innermost = group.first, let cycle = innermost.cycle else { return nil }
        // No further than the LINE reaches, as the rebuild: there is nothing of the
        // source to fade past its end.
        let start = max(0, group.map(\.offsetX).min() ?? 0)
        let end = min(line.strippedLength, group.map { $0.offsetX + $0.width }.max() ?? 0)
        guard end > start else { return nil }
        // One run carries one clock, so only the cycles sharing the innermost one's
        // clock can join the merge. Every `.opacity` cycle is on `.content`, so this
        // is a guard against a future producer rather than a case that runs today.
        let onClock = group.filter { $0.cycle?.clock == cycle.clock }
        // The runs under these fades that step with them: inside their columns, on
        // their clock, at the standard frame a cycle steps at, and saying nothing
        // about alpha frame by frame — the row is rebuilt at the alpha the drawn
        // frame's payload says, and another frame would owe its own.
        let folded = runs.filter { run in
            run.offsetY == row && run.width > 0 && run.offsetX >= start
                && run.offsetX + run.width <= end && run.clock == cycle.clock
                && run.frameTicks == AnimationClock.standardFrameTicks
                && run.alpha?.isTranslucent != true && run.isAnimating
        }
        // `nil` past the budget, where the merged frames would outweigh the renders
        // they save — two coprime cycles near the cap are ten thousand finished
        // rows. Then the innermost fade animates alone and the rest hold at the
        // value they were drawn at: frozen, but frozen identically on every tick,
        // which is the whole difference from two runs fighting over one cell.
        let merged = combinedSteps(
            of: onClock.compactMap { $0.cycle?.phases.count } + folded.map(\.frames.count))
        let steps = merged ?? cycle.phases.count
        // Each folded run's frames go into the row before it is built, over the fields
        // its painters left there as such a row reads them: a stated 49 the terminal's
        // own, and a cell no painter reached on none, for the page. Read on a page, as
        // the tick reads a row on screen, the two were one field: a ground's stated 49
        // came out on the page and a bare cell on the terminal's own. Read once: they
        // are the same at every step.
        let fields = merged == nil ? [] : folded.map { $0.fieldsInAnUnbuiltRow() }
        var frames: [String] = []
        frames.reserveCapacity(steps)
        for step in 0..<steps {
            var source = line
            for (run, fields) in zip(folded, fields) {
                source = patchingAnimatedCells(
                    in: source, with: run.frame(atIndex: step), atColumn: run.offsetX, width: run.width,
                    fields: fields, absentFieldIsUnstated: true)
            }
            let rebuilt = rebuild(row, source) { region in
                // Asked of the region itself rather than by searching the group:
                // the frame is cut to the group's columns, which every repeating fade
                // there overlaps, so "has a cycle, on this clock" IS membership — and
                // this closure runs once per region per step, where an
                // `OpacityRegion ==` costs a phase-array walk.
                guard let values = region.cycle?.phases, values.count >= 2,
                    region.cycle?.clock == cycle.clock,
                    merged != nil || region == innermost
                else { return region.cellAlpha }
                // Its OWN phase at this one step. Pinning the others at `opacity` —
                // which is what a per-region run did — is exactly what let the run
                // applied second revert the first's cells.
                //
                // The LAYER channel is the one that cycles; a colour's alpha does not
                // animate itself (an animated one is a fresh region per frame through
                // the ordinary render path), so the other two ride along unchanged.
                return Self.CellAlpha(
                    layer: values[step % values.count], ink: region.inkOpacity,
                    field: region.fieldOpacity)
            }
            // The group's columns of the row as rebuilt, with the styling in force
            // where they begin carried in front: what the line shows there.
            frames.append(
                (rebuilt ?? source).ansiAwareSlice(visibleStart: start, visibleCount: end - start))
        }
        // A group that never changes is a still picture the ordinary render already
        // drew; a run for it would emit bytes every tick to no effect. And a run
        // cannot change a row's width.
        guard let first = frames.first, frames.contains(where: { $0 != first }),
            frames.allSatisfy({ $0.strippedLength == end - start })
        else { return nil }
        return AnimatedCellRun(
            offsetX: start, offsetY: row, width: end - start, frames: frames, clock: cycle.clock)
    }

    /// The smallest number of steps every one of `counts` divides into, so one
    /// run can hold all of them: at step `t` each reads `t % count`, and a common
    /// multiple is what keeps that the index the render drew with —
    /// `(t % N) % n == t % n` exactly when `n` divides `N`.
    ///
    /// `nil` past ``AnimationCycle/maximumSteps``, the budget one cycle is
    /// already held to, for the same reason: a run holds one finished string per
    /// step per row.
    ///
    /// Walked up in strides of the longest rather than through a GCD: at most
    /// `maximumSteps / longest` remainders, no second copy of
    /// `GradientRaster.greatestCommonDivisor`, and it stops AT the budget instead
    /// of first computing a product that overshoots it by orders of magnitude.
    private static func combinedSteps(of counts: [Int]) -> Int? {
        guard let longest = counts.max(), longest > 0 else { return nil }
        var steps = longest
        while steps <= AnimationCycle<Double>.maximumSteps {
            if counts.allSatisfy({ steps.isMultiple(of: $0) }) { return steps }
            steps += longest
        }
        return nil
    }
}
