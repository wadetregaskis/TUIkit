//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+ClaimsOverNothing.swift
//
//  A compositor inside the tree — a `ZStack`, an `.overlay`, a custom `Layout` —
//  resolves a layer's fades against its base, because it is the last place the
//  base's cells and the layer's are both known. But where the base shows NOTHING
//  under a faded cell — a blank on no field, which is what a stack's canvas is
//  before anything lands on it — the base is not what is behind the fade:
//  whatever is behind the compositor is, and that is not known there. A painter
//  further out (`.background`, a list row's fill, a menu bar) or the page is.
//  Resolved there anyway, the cell was blended over the page and stated it, and
//  the painter's fill, restated after resets, could not put itself back: a
//  page-coloured hole under a faded label in a `.background`. So those claims
//  travel up with the layer, as a painter's content's travel to the painter, and
//  are spent where what is behind them is known (`Opacity as composition.md`
//  §108).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {

    /// This buffer — a layer about to be composited onto `base` at `position` — cut
    /// in two by what the base shows under its claims: `here`, the layer with the
    /// claims over cells where the base shows something of its own, which the
    /// compositor resolves against the base; and `carried`, the claims over cells
    /// where it shows nothing (``String/columnsShowingNothing(width:)``), which go on
    /// up unresolved, with the runs whose frames say their alpha themselves and sit
    /// over nothing (`setAside`), unspent.
    ///
    /// A run that crosses from one side to the other is cut there when its two sides
    /// are spent in two places. One whose frames say their alpha: its pieces over
    /// nothing go up whole, as a run wholly over nothing does, and resolved here with
    /// the rest, their fields were mixed over the page where a painter was behind
    /// them. And one under a repeating fade that the split cut: each side's run folds
    /// the runs inside its own columns (`cyclingRuns`), and whole, the run was inside
    /// neither — the fade here dropped it, as a fade drops every run it cannot fold,
    /// and between renders it froze. Every other run is spent by each side's claims in
    /// turn, the columns under neither passed through, and is left whole.
    ///
    /// A layer whose claims all lie over something — nearly every one, and every one
    /// with none — comes back as it is.
    ///
    /// - Parameters:
    ///   - base: What the layer is about to be composited onto.
    ///   - position: Where it lands in `base`.
    /// - Returns: The layer to resolve against the base, and what travels up.
    func splittingClaims(
        overNothingIn base: Self, at position: (x: Int, y: Int)
    ) -> (here: Self, carried: [OpacityRegion], setAside: [AnimatedCellRun]) {
        let spokenRuns = animatedCells.filter { $0.alpha?.isTranslucent == true }
        guard !opacityRegions.isEmpty || !spokenRuns.isEmpty else { return (self, [], []) }
        // As far as a claim, or a run it may cut, reaches.
        let reach = max(
            opacityRegions.map { $0.offsetX + $0.width }.max() ?? 0,
            animatedCells.map { $0.offsetX + $0.width }.max() ?? 0)
        // What the base shows nothing at, under each row of the layer, read once a row.
        var masks: [Int: [Bool]] = [:]
        func nothing(_ row: Int, _ column: Int) -> Bool {
            let baseRow = row + position.y
            guard base.lines.indices.contains(baseRow) else { return true }
            let mask: [Bool]
            if let known = masks[row] {
                mask = known
            } else {
                mask = base.lines[baseRow].columnsShowingNothing(width: max(0, position.x + reach))
                masks[row] = mask
            }
            let baseColumn = column + position.x
            return baseColumn < 0 || baseColumn >= mask.count || mask[baseColumn]
        }
        var here = self
        var carried: [OpacityRegion] = []
        var kept: [OpacityRegion] = []
        for claim in opacityRegions {
            let pieces = Self.cutting(claim) { row, column in nothing(row, column) }
            for (piece, overNothing) in pieces {
                if overNothing { carried.append(piece) } else { kept.append(piece) }
            }
        }
        // A run stating its alpha frame by frame goes up whole over nothing: its drawn
        // frame's claims are made from that alpha wherever it is resolved, and spent
        // here the lines would be faded here and again above.
        var setAside: [AnimatedCellRun] = []
        var runs: [AnimatedCellRun] = []
        var cutARun = false
        for run in animatedCells {
            let spoken = run.alpha?.isTranslucent == true
            let columns = run.offsetX..<(run.offsetX + run.width)
            // Under a repeating fade the split cut, on both sides of the cut.
            func underACutFade(_ pieces: [OpacityRegion]) -> Bool {
                pieces.contains { piece in
                    piece.cycle != nil && piece.spans(row: run.offsetY)
                        && piece.offsetX < columns.upperBound && columns.lowerBound < piece.offsetX + piece.width
                }
            }
            // Every other run stays whole, and is not read for it.
            guard spoken || (underACutFade(kept) && underACutFade(carried)) else {
                runs.append(run)
                continue
            }
            let overNothing = columns.map { nothing(run.offsetY, $0) }
            guard overNothing.contains(true), overNothing.contains(false) else {
                if spoken, overNothing.contains(true) { setAside.append(run) } else { runs.append(run) }
                continue
            }
            cutARun = true
            var start = 0
            while start < overNothing.count {
                var end = start + 1
                while end < overNothing.count, overNothing[end] == overNothing[start] { end += 1 }
                let segment = (columns.lowerBound + start)..<(columns.lowerBound + end)
                // A piece that no longer animates holds the clock open for nothing,
                // as a punched one does; one that says its alpha still has cells to
                // say it for.
                if let piece = run.clipped(toColumns: segment), spoken || piece.isAnimating {
                    if spoken, overNothing[start] { setAside.append(piece) } else { runs.append(piece) }
                }
                start = end
            }
        }
        guard !carried.isEmpty || !setAside.isEmpty || cutARun else { return (self, [], []) }
        here.opacityRegions = kept
        here.animatedCells = runs
        return (here, carried, setAside)
    }

    /// `overlay` composited onto this buffer by a compositor INSIDE the tree, its
    /// claims resolved against this buffer where it shows something under them and
    /// carried up where it shows nothing (``splittingClaims(overNothingIn:at:)``),
    /// and a covered cell the blend leaves with no field left unsaid. This buffer's
    /// own claims under the overlay — an earlier layer's, carried up over the canvas
    /// it landed on — are settled first (``settlingClaims(under:at:palette:)``).
    ///
    /// - Parameters:
    ///   - overlay: The layer to draw on top.
    ///   - position: Where it lands, in this buffer's cells.
    ///   - palette: Resolves SGR 39 and the terminal's own colours.
    /// - Returns: The composite, carrying what was not resolved here.
    func compositedCarryingClaimsOverNothing(
        with overlay: Self, at position: (x: Int, y: Int), palette: any Palette
    ) -> Self {
        let (base, layer, kept) = prepared(overlay, at: position, palette: palette)
        var result = base.composited(
            with: layer, at: position, overlayIsPainted: false,
            terminalForeground: { Self.reportedTerminalForegroundField })
        if !kept.isEmpty { result.opacityRegions = kept + result.opacityRegions }
        return result
    }

    /// ``compositedCarryingClaimsOverNothing(with:at:palette:)`` in place, for a
    /// canvas many layers are folded into (``composite(with:at:)``).
    mutating func compositeCarryingClaimsOverNothing(
        with overlay: Self, at position: (x: Int, y: Int), palette: any Palette
    ) {
        let (base, layer, kept) = prepared(overlay, at: position, palette: palette)
        self = base
        composite(with: layer, at: position, terminalForeground: { Self.reportedTerminalForegroundField })
        if !kept.isEmpty { opacityRegions = kept + opacityRegions }
    }

    /// What compositing `overlay` onto this buffer composites: this buffer with its
    /// own claims under the overlay settled, the overlay resolved against it where it
    /// shows something and carrying the rest, and the claims this buffer keeps under
    /// the overlay's cells, which the composite punches with the rest of its footprint
    /// and the caller puts back in front.
    private func prepared(
        _ overlay: Self, at position: (x: Int, y: Int), palette: any Palette
    ) -> (base: Self, layer: Self, kept: [OpacityRegion]) {
        let split = overlay.splittingClaims(overNothingIn: self, at: position)
        let settled = settlingClaims(under: split.here, at: position, palette: palette)
        var resolved = settled.layer.resolvingOpacity(
            over: settled.base, at: position, surface: palette.background, palette: palette,
            statingTheSurface: false, fillingStatedTerminalField: true, buildingRuns: true)
        resolved.opacityRegions = split.carried + settled.carried
        resolved.animatedCells += split.setAside
        return (settled.base, resolved, settled.kept)
    }
}
