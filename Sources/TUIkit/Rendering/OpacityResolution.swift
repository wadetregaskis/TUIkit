//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityResolution.swift
//
//  Turns an ``OpacityRegion`` into cells, at the one moment what is behind the
//  faded layer is known.
//
//  A terminal cell holds one character in one foreground colour on one
//  background colour: there is no alpha to write and no sub-pixel coverage. So
//  alpha is honoured exactly for COLOURS and becomes a DECISION for glyphs —
//  two characters cannot occupy one cell at half strength each. The rule, and
//  the reasoning behind picking it, is in `Documentation/Opacity as
//  composition.md` §6a; in short:
//
//  * **each channel blends with its own counterpart, independently**: the
//    source's ink toward what the destination shows where a glyph draws, and
//    the source's background toward what it shows where none does. The two
//    channels never mix, so nothing has to estimate how much of a cell a
//    glyph inks;
//  * **both channels are read the same way on both sides**, so a space is not
//    a case of its own: a cell shows its ink where its glyph draws and its
//    FIELD where none does. A label thinning out over an empty page fades
//    into that page; a veil's blank cell covers the text under it exactly as
//    much as the field around it, so both channels move toward the veil by
//    the same alpha; over a `█`-drawn swatch the ink channel blends toward the
//    swatch's own colour;
//  * **a channel the source states nothing in is left exactly as it was.**
//    That is emptiness rather than blankness — a layer with no background of
//    its own tints no field, and a cell that paints nothing at all composites
//    nothing at all, which is what keeps a faded `VStack`'s padding
//    transparent instead of a rectangle punched through the page;
//  * **the ½ threshold decides a glyph CONTEST, and only applies where there
//    is one**: over a blank destination cell the source's character draws at
//    any alpha; a source space is not a contest either, so the destination
//    keeps its character at every alpha; where both sides paint ink, at or
//    above ½ the source's character is drawn and below ½ the destination's is.
//    At 0 the source contributes nothing at all, so `opacity(0)` genuinely
//    reveals what is behind it.
//
//  Created by Wade Tregaskis
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension FrameBuffer {

    /// This buffer with its ``opacityRegions`` resolved against `destination`,
    /// and the regions cleared.
    ///
    /// Call this immediately before compositing, so the result can be
    /// composited opaquely as usual: the resolution BAKES the destination into
    /// the source wherever the source yields, which is what lets a cell be
    /// "skipped" at all in a compositor that has no notion of transparency.
    ///
    /// - Parameters:
    ///   - destination: What is behind this buffer. Pass an empty buffer at a
    ///     root, where the answer is `surface` everywhere.
    ///   - position: Where this buffer lands in `destination`, in its cells.
    ///   - surface: The ambient background — what a cell that paints no
    ///     background of its own actually shows. Not one colour for the whole
    ///     frame: the content area, the app header and the status bar each
    ///     have their own (see `RenderBackgroundCodes`).
    ///   - palette: Resolves `surface` and SGR 39, and is asked for nothing
    ///     else. Taken rather than assumed because a semantic colour reaching
    ///     the arithmetic is a silent no-op in one direction and a trap in the
    ///     other — see ``Color/compositing(_:over:)`` and `ANSIRenderer`.
    /// - Returns: A buffer with no opacity regions, ready to composite.
    public func resolvingOpacity(
        over destination: Self = Self(),
        at position: (x: Int, y: Int) = (x: 0, y: 0),
        surface: Color,
        palette: any Palette
    ) -> Self {
        guard !opacityRegions.isEmpty else { return self }
        // A fully opaque region is the identity ONLY where there is nothing
        // behind it, and that is the test rather than the alpha alone.
        //
        // What a fully opaque composite still does is let a cell that names no
        // background show the one behind it — the blend keeps the destination's
        // background at every alpha, a colour that is not there being nothing to
        // blend. Over an empty destination there is no such colour either way,
        // so the walk would arrive back at the same picture and the layer is
        // better left byte-for-byte untouched: that is the root, and it is what
        // nearly every `.opacity(1)` in an app is drawn over. Over something —
        // a `ZStack` sibling, an `.overlay`, a list row's fill — dropping it
        // punched the cells out to the ambient surface, which is the black (or,
        // on a light terminal, white) rectangle that appeared under text at
        // exactly 100% and nowhere below it.
        //
        // A CYCLING region is always kept: opaque is merely where its fade
        // happens to be this instant — usually its very first frame — and
        // dropping it there would mean the fade never produced any frames at
        // all and never ran.
        let opaqueMatters = !destination.isEmpty
        let translucent = opacityRegions.filter {
            $0.isTranslucent || $0.cycle != nil || opaqueMatters
        }
        guard !translucent.isEmpty else {
            var resolved = self
            resolved.opacityRegions = []
            return resolved
        }
        // Resolved once, not per cell: the arithmetic behind a semantic colour
        // is not free, and unresolved it does not happen at all.
        let resolvedSurface = surface.resolve(with: palette)
        let resolvedForeground = palette.foreground.resolve(with: palette)

        // One row at a time, and each row rebuilt by the SAME function whatever
        // it is being rebuilt for — the current picture, or a phase of a
        // repeating fade. That is what makes the pre-rendered cycle sound: the
        // frame the loop splices at the tick just drawn is byte-identical to
        // the line the render produced, because it came out of this call with
        // the same argument.
        func rebuild(
            _ row: Int, _ line: String, substituting: (OpacityRegion) -> FrameBuffer.CellAlpha?
        ) -> String? {
            let covering = translucent.filter { $0.spans(row: row) }
            guard !covering.isEmpty else { return nil }
            // A row drawing an image is left alone. Its FOREGROUND is not a
            // colour, it is the image's id (see
            // `KittyGraphics`), and blending it toward a surface
            // produces a number naming no image — so a faded picture would not
            // dim, it would vanish. Left unblended it stays at full strength
            // inside a fade, which is wrong in a way anyone can see and
            // describe, rather than wrong in a way that looks like the image
            // failed to load.
            //
            // Fading a real picture is possible — the alpha would go into the
            // pixels before they are transmitted — but that is the store's
            // business and it cannot be done from here, where all that is left
            // of the image is cells.
            guard !line.unicodeScalars.contains(.terminalImagePlaceholder) else { return nil }
            let first = covering.map(\.offsetX).min() ?? 0
            // No further than the LINE reaches. A region is stamped as wide as
            // its buffer — the longest line — over lines that may be shorter,
            // and `blendedSpan` cannot tell "past the end of the line" from
            // "the continuation of a wide glyph": it manufactured cells there
            // wearing the last real cell's field, and the row grew to the
            // region's edge. There is nothing of the source to fade past its
            // end; what is behind shows through, as it does for any cell the
            // source does not have.
            let last = min(covering.map { $0.offsetX + $0.width }.max() ?? 0, line.strippedLength)
            let start = max(0, first)
            guard last > start else { return nil }

            let destinationRow = row + position.y
            let behindLine =
                destination.lines.indices.contains(destinationRow)
                ? destination.lines[destinationRow] : ""
            let span = Self.blendedSpan(
                source: line,
                destination: behindLine,
                columns: start..<last,
                destinationShift: position.x,
                alpha: { column in
                    // First match wins, and the regions arrive innermost-first
                    // — a nested `.opacity` stamps its own product before the
                    // outer one appends its rectangle — so the inner alpha is
                    // the one that applies to a cell both cover.
                    covering.first { $0.contains(column: column, row: row) }
                        .flatMap(substituting)
                },
                surface: resolvedSurface,
                defaultForeground: resolvedForeground)
            // Collapsed at the seam, where the seam is made: splicing leaves the
            // span's closing reset hard against the styling `insertOverlay`
            // restores for the suffix, and where the region reaches the end of
            // the row that restored styling has no cells left to colour. The
            // netting is exact — nothing printed between them observed the
            // intermediate state — and doing it here rather than leaving it to
            // `FrameDiffWriter` matches where the rest of it is done, at the
            // builder rather than downstream. It also keeps the assertion
            // "the faded colour appears nowhere in this row" meaningful.
            return Self.splicing(span, into: line, atColumn: start).collapsingAdjacentSGR()
        }

        var rewritten = lines
        for row in rewritten.indices {
            if let rebuilt = rebuild(row, rewritten[row], substituting: { $0.cellAlpha }) {
                rewritten[row] = rebuilt
            }
        }

        var result = replacingLines(rewritten)
        result.opacityRegions = []
        // A run emitted by some OTHER view inside the faded subtree — a focused
        // button's breathing caps, a spinner — carries frames coloured at full
        // strength, because the view that built them never saw the fade. Left
        // in place, the render would draw the faded picture and the very next
        // replay tick would paint the unfaded frames back over it.
        //
        // So the frames pass through the SAME blend the lines did, and the run
        // replays faded. Dropping the run instead — the first design — froze
        // every run-only animator under `.opacity`: a `Spinner` and an
        // indeterminate `ProgressView` emit their run and request no fallback
        // animation, so with the run gone nothing kept the clock alive and
        // they sat motionless at one faded frame.
        //
        // The one case that still yields is a run under a REPEATING fade: the
        // fade's phases and the run's frames tick independently, and their
        // product is not representable as one run. The run's cells freeze at
        // the frame the lines were drawn with, inside a fade that itself
        // keeps animating — a bounded compromise where the alternative was a
        // full render per tick.
        result.animatedCells = result.animatedCells.compactMap { run in
            let covering = translucent.filter { region in
                region.spans(row: run.offsetY)
                    && run.offsetX < region.offsetX + region.width
                    && region.offsetX < run.offsetX + run.width
            }
            guard !covering.isEmpty else { return run }
            guard covering.allSatisfy({ $0.cycle == nil }) else { return nil }
            let destinationRow = run.offsetY + position.y
            let behindLine =
                destination.lines.indices.contains(destinationRow)
                ? destination.lines[destinationRow] : ""
            // Aligned into a pseudo-row so the frame's cells sit at the run's
            // own columns, where the per-column alpha and the destination line
            // expect them.
            let prefix = String(repeating: " ", count: max(0, run.offsetX))
            // The frame's cells inherit their FIELD from the line they replace
            // — a frame from `colorize(glyph, foreground:)` states none, and
            // the splice relies on the line's background applying under it.
            // Blended against what is behind the layer alone, such a cell took
            // the destination's field unblended (or the bare surface) and then
            // STATED it, so an indeterminate bar inside `.background(.blue)
            // .opacity(0.5)` drew its tint once and replayed it plain.
            let ownLine = lines.indices.contains(run.offsetY) ? lines[run.offsetY] : ""
            let fadedFrames = run.frames.map { frame in
                Self.blendedSpan(
                    source: prefix + frame,
                    destination: behindLine,
                    columns: run.offsetX..<(run.offsetX + run.width),
                    destinationShift: position.x,
                    fieldsFrom: ownLine,
                    alpha: { column in
                        covering.first { $0.contains(column: column, row: run.offsetY) }?
                            .cellAlpha
                    },
                    surface: resolvedSurface,
                    defaultForeground: resolvedForeground)
            }
            return AnimatedCellRun(
                offsetX: run.offsetX, offsetY: run.offsetY, width: run.width,
                frames: fadedFrames, frameDuration: run.frameDuration, clock: run.clock)
        }
        result.animatedCells += Self.cyclingRuns(
            of: translucent, over: lines, rebuilding: rebuild)
        return result
    }

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
    private static func cyclingRuns(
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
            let merged = Self.combinedTicks(of: onClock)
            let ticks = merged ?? cycle.phases.count
            var phases: [[String]] = []
            phases.reserveCapacity(ticks)
            for tick in 0..<ticks {
                let rebuilt = rebuild(
                    row, lines[row],
                    { region in
                        // Asked of the region itself rather than by searching the
                        // merged list: `rebuild` already narrowed `covering` to
                        // this row, so "has a cycle, on this clock" IS membership
                        // — and this closure runs once per COLUMN per tick, where
                        // an `OpacityRegion ==` costs a phase-array walk.
                        guard let values = region.cycle?.phases, values.count >= 2,
                            region.cycle?.clock == cycle.clock,
                            merged != nil || region == innermost
                        else { return region.cellAlpha }
                        // Its OWN phase at this one tick. Pinning the others at
                        // `opacity` — which is what a per-region run did — is
                        // exactly what let the run applied second revert the
                        // first's cells.
                        //
                        // The LAYER channel is the one that cycles; a colour's
                        // alpha does not animate itself (an animated one is a
                        // fresh region per frame through the ordinary render
                        // path), so the other two ride along unchanged.
                        return FrameBuffer.CellAlpha(
                            layer: values[tick % values.count],
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

    /// The smallest number of ticks every cycle in `regions` divides into, so one
    /// run can hold all of them: at tick `t` each region reads
    /// `phases[t % phases.count]`, and a common multiple is what keeps that the
    /// index the render drew with — `(t % N) % n == t % n` exactly when `n`
    /// divides `N`.
    ///
    /// `nil` past ``AnimationCycle/maximumTicks``, the budget one cycle is
    /// already held to, for the same reason: a run holds one finished string per
    /// tick per row.
    ///
    /// Walked up in steps of the longest cycle rather than through a GCD: at most
    /// `maximumTicks / longest` remainders, no second copy of
    /// `GradientRaster.greatestCommonDivisor`, and it stops AT the budget instead
    /// of first computing a product that overshoots it by orders of magnitude.
    private static func combinedTicks(of regions: [OpacityRegion]) -> Int? {
        let counts = regions.compactMap { $0.cycle?.phases.count }
        guard let longest = counts.max(), longest > 0 else { return nil }
        var ticks = longest
        while ticks <= AnimationCycle<Double>.maximumTicks {
            if counts.allSatisfy({ ticks.isMultiple(of: $0) }) { return ticks }
            ticks += longest
        }
        return nil
    }
}

extension FrameBuffer {

    /// `overlay` composited onto this buffer, with its opacity resolved against
    /// this buffer first.
    ///
    /// The pairing every compositing site wants: resolution has to happen HERE,
    /// because here is the first and only moment both sides exist. Resolve too
    /// early and the blend is a guess about what is behind the layer, which is
    /// the fault the whole design exists to remove; resolve too late — at the
    /// root, say — and the source's cells have already replaced the
    /// destination's, so what was behind them is gone.
    ///
    /// - Parameters:
    ///   - overlay: The layer to draw on top.
    ///   - position: Where it lands, in this buffer's cells.
    ///   - palette: Resolves the surface and SGR 39.
    ///   - surface: The ambient background, when it is not the content area's
    ///     — the app header and the status bar have their own.
    func compositedResolvingOpacity(
        with overlay: Self,
        at position: (x: Int, y: Int),
        palette: any Palette,
        surface: Color? = nil
    ) -> Self {
        composited(
            with: overlay.resolvingOpacity(
                over: self, at: position,
                surface: surface ?? palette.background, palette: palette),
            at: position)
    }
}
