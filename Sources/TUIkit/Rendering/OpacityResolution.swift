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
//    reveals what is behind it;
//  * **a colour with no RGB is not mixed**: the heavier side wins, and a glyph
//    whose ink ends up as the terminal's unreported page, on that page, draws
//    nothing, because the foreground slot would spell it as 39. So a fade over
//    such a page is a cut at ½ (§75 and §76).
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
        resolvingOpacity(
            over: destination, at: position, surface: surface, palette: palette, fillingStatedTerminalField: false,
            buildingRuns: true)
    }

    /// ``resolvingOpacity(over:at:surface:palette:)``, saying whether a stated
    /// `ESC[49m` is read as the field under it, and whether it builds the runs at all.
    ///
    /// `fillingStatedTerminalField` is a compositor's reading of the layer's stated 49:
    /// the composite that follows fills it with the field under its column, so a covered
    /// cell stating one is blended as that field where `destination` shows one (§95).
    /// A painter lets a stated 49 through, and a root has nothing under it.
    ///
    /// `buildingRuns: false` answers the LINES alone, every run it carried gone, for a
    /// caller that keeps nothing else — a breathing row spending its content against each
    /// colour of its breath (`ListRowContent`, `_MenuItemRowBar`). The lines take a run
    /// only through what its own alpha says about the frame they were drawn at, which is
    /// read here either way; fading every frame of every run and building a repeating
    /// fade's runs, for a buffer whose runs were then discarded, was work thrown away once
    /// per colour.
    func resolvingOpacity(
        over destination: Self, at position: (x: Int, y: Int), surface: Color, palette: any Palette,
        fillingStatedTerminalField: Bool, buildingRuns: Bool
    ) -> Self {
        // A run may be the only thing on the buffer with anything to say: a blinking
        // caret over a faded well claims nothing statically, because no one rectangle
        // is true of both its frames (see ``AnimatedRunAlpha``).
        let runAlphaMatters = animatedCells.contains { $0.alpha?.isTranslucent == true }
        guard !opacityRegions.isEmpty || runAlphaMatters else { return self }
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
        // TWO lists, and the split is load-bearing.
        //
        // `regionsForRuns` is what actually covers a run from OUTSIDE it — an enclosing
        // `.opacity(_:)`, a row's fill — and folds into every one of its frames.
        // `translucent` adds what each run's own payload says about the frame the LINES
        // were drawn at, because the render drew that frame into the lines and nothing
        // else claims those cells: without it the first paint would be at full strength
        // until the first replay tick, and every path that keeps the lines while
        // dropping the run would stay there.
        //
        // APPENDED, never prepended: `foldedAlphas` takes the LAYER from the first
        // region covering a cell and multiplies only ink and field across the rest, and
        // a run's payload has no layer to give (``AnimatedRunAlpha/Span``). Ahead of an
        // enclosing fade it would answer the glyph contest with a 1 that is not true.
        let regionsForRuns = opacityRegions.filter {
            $0.isTranslucent || $0.cycle != nil || opaqueMatters
        }
        let drawnClaims =
            runAlphaMatters
            ? animatedCells.flatMap {
                $0.alpha?.drawnRegions(forRunAt: $0.offsetX, offsetY: $0.offsetY) ?? []
            }
            : []
        let translucent = regionsForRuns + drawnClaims
        guard !translucent.isEmpty || runAlphaMatters else {
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
        // frame the loop splices at the tick just drawn is cut from the line the
        // render produced, because it came out of this call with the same
        // argument.
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
            let columns = start..<last
            let alphas = Self.foldedAlphas(
                of: covering, over: columns, row: row, substituting: substituting)
            let span = Self.blendedSpan(
                source: line,
                destination: behindLine,
                columns: columns,
                destinationShift: position.x,
                alpha: { alphas[$0 - start] },
                surface: resolvedSurface,
                defaultForeground: resolvedForeground,
                fillingStatedTerminalField: fillingStatedTerminalField)
            // Collapsed at the seam, where the seam is made: splicing leaves the
            // span's closing reset hard against the styling `insertOverlay`
            // restores for the suffix, and where the region reaches the end of
            // the row that restored styling has no cells left to colour. The
            // netting is exact — nothing printed between them observed the
            // intermediate state — and doing it here rather than leaving it to
            // `FrameDiffWriter` matches where the rest of it is done, at the
            // builder rather than downstream. It also keeps the assertion
            // "the faded colour appears nowhere in this row" meaningful.
            //
            // Exact only as a row the writer has yet to finish, which puts a
            // field back after every reset: there a reset and a stated 49 are two
            // fields, the one around the row and the terminal's own, and netted
            // as one state a reset came out as `ESC[49m` — a cell after a
            // coloured one drew the terminal's own field in place of the page
            // (§94, ``String/collapsingAdjacentSGR(resetRestoresAField:)``).
            return Self.splicing(span, into: line, atColumn: start)
                .collapsingAdjacentSGR(resetRestoresAField: true)
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
        // A run under a REPEATING fade is not faded here: the fade's own run
        // carries its cells, and folds its frames in where the two step together
        // (``cyclingRuns(of:over:folding:rebuilding:)``). Where they do not, their
        // product is not representable as one run, and the run's cells freeze at
        // the frame the lines were drawn with, inside a fade that itself keeps
        // animating — a bounded compromise where the alternative was a full
        // render per tick.
        guard buildingRuns else {
            result.animatedCells = []
            return result
        }
        result.animatedCells = animatedCells.compactMap { run in
            Self.faded(
                run, covering: regionsForRuns, destination: destination,
                position: position, surface: resolvedSurface,
                defaultForeground: resolvedForeground, fillingStatedTerminalField: fillingStatedTerminalField)
        }
        result.animatedCells += Self.cyclingRuns(
            of: translucent, over: lines, folding: animatedCells, rebuilding: rebuild)
        return result
    }

    /// The alpha every cell of one row owes, folded across every region covering
    /// it, indexed from `columns.lowerBound`.
    ///
    /// The LAYER comes from the first match, and the INK and FIELD are multiplied
    /// across every match. The asymmetry is not a compromise; the two kinds of
    /// claim arrive differently.
    ///
    /// A layer's alpha nests, and `OpacityFade.fading` has already done that
    /// arithmetic: it scales the factor into every region it carries up before
    /// appending its own rectangle, so the innermost region covering a cell
    /// already holds the product of every `.opacity` outside it. Multiplying those
    /// again here would count each one twice. It also could not be moved to this
    /// loop even if that were free, because a CYCLING region carries a list of
    /// phases and two cycles of different lengths have no common phase index to
    /// multiply at — pre-multiplying a scalar into the inner cycle is what makes a
    /// breathing badge inside a fading panel expressible.
    ///
    /// A colour's alpha does not nest and `fading` never touches it, so
    /// first-match-wins silently DROPPED one of two independent claims on the same
    /// cell. Reachable in one line:
    /// `Text("hi").foregroundStyle(.green.opacity(0.4)).background(.red.opacity(0.4))`
    /// stamps (ink 0.4) for the text and (field 0.4) for the background over the
    /// same cells, and the text's region won — so the background rendered at FULL
    /// strength under the letters and correctly past the end of the line, which on
    /// ragged wrapped text is a visible two-tone block.
    ///
    /// One function, called from both the line walk and the run-frame walk,
    /// because those are the two places the answer is needed and they had already
    /// drifted: the line multiplied and the run took the first match.
    ///
    /// ## Why the whole row at once
    ///
    /// This was asked once per COLUMN, walking every region each time: O(width ×
    /// regions), which is 4 comparisons and a call per region per cell. Fine while
    /// a row carried one or two claims, and the reason §34.3 declined a ramp whose
    /// alpha varies in both directions — 80 width-1 claims on an 80-column row is
    /// 6,400 containment tests, ~154,000 over a 24-row block, per resolve per
    /// frame.
    ///
    /// Written the other way round — walk each region once and fill the cells it
    /// covers — it is O(Σ widths + width), which for the same 80 claims is 80
    /// stores. The containment test disappears entirely: a region's rows are
    /// already known (`spans(row:)` is asked before this) and its columns become
    /// the bounds of the fill loop rather than a predicate. `substituting` is
    /// likewise called once per region instead of once per region per column, and
    /// for a cycling region that closure walks a phase array and compares clocks.
    ///
    /// The cost is one array per row, where the walk allocated nothing. That is
    /// the trade, and it is measured: see §36.
    ///
    /// - Parameters:
    ///   - regions: The regions already narrowed to this row.
    ///   - columns: The span being rebuilt, in the source buffer's own
    ///     coordinates. Cells outside it are not answered for — the caller
    ///     already trimmed the span to the covered columns and the line's own
    ///     length.
    ///   - row: The row, for narrowing each region.
    ///   - substituting: What a region's alpha is *right now* — its own
    ///     ``OpacityRegion/cellAlpha``, or a cycling region's phase at one tick.
    ///     `nil` drops that region from the fold.
    /// - Returns: One entry per column of `columns`, `nil` where no region
    ///   covers that cell.
    /// One run, with every alpha covering it spent into its frames.
    ///
    /// Extracted from ``resolvingOpacity(over:at:surface:palette:)`` because it grew a
    /// second arm — a run carrying its own per-frame alpha (``AnimatedRunAlpha``) — and
    /// the two together put that function past its length. The split is also the honest
    /// one: everything here is about a RUN, and nothing about it is about the lines.
    ///
    /// - Parameters:
    ///   - covering: What covers the run from OUTSIDE it, and only that. A run's own
    ///     per-frame statement must not be in this list or every frame would be folded
    ///     with the drawn frame's alpha as well as its own.
    private static func faded(
        _ run: AnimatedCellRun,
        covering regions: [OpacityRegion],
        destination: FrameBuffer,
        position: (x: Int, y: Int),
        surface resolvedSurface: Color,
        defaultForeground resolvedForeground: Color,
        fillingStatedTerminalField: Bool
    ) -> AnimatedCellRun? {
        // Cut to the buffer's own columns FIRST, because a run can name columns to
        // the LEFT of column 0. `OverlayLayer`'s leading cut moves every payload by
        // -dropX and leaves a run that straddles — or wholly precedes — the first
        // surviving cell; `OverlayLayer.cutting`'s own comment says such payload is
        // "already read as `max(0, …)` by the opacity resolution", and only the
        // `prefix` below ever was.
        //
        // The blend indexes its SOURCE array by absolute column, so a negative
        // `columns.lowerBound` reaches `sourceCells[-1]` and aborts the process —
        // in release as well as debug, an array subscript being a precondition.
        // The destination side of that same walk is bounds-checked, and says in as
        // many words that a negative shift is legal; the source side never was, and
        // the line path escapes only because `rebuild` clamps its start.
        //
        // A cut and not a clamp, because those cells genuinely are not here: the
        // frame's first `-offsetX` cells belong to columns this buffer does not
        // have. `clipped(toColumns:)` drops them from every frame and slices the
        // per-frame alpha payload to the same window in the same expression, so a
        // cut run's spans still describe the cells it kept. A run wholly left of
        // the edge comes back `nil` and takes nothing with it — there are no cells
        // left for it to have been the carrier of an alpha for.
        guard let run = run.clipped(toColumns: 0..<(run.offsetX + run.width)) else {
            return nil
        }
        let covering = regions.filter { region in
            region.spans(row: run.offsetY)
                && run.offsetX < region.offsetX + region.width
                && region.offsetX < run.offsetX + run.width
        }
        guard !covering.isEmpty || run.alpha?.isTranslucent == true else { return run }
        guard covering.allSatisfy({ $0.cycle == nil }) else { return nil }
        // No assertion that nothing else claims these cells, although there used to be
        // one. The rule it was guarding is real — a producer states a static claim for a
        // run's cells OR a per-frame payload, never both, or the fold below fades them
        // twice — but it is a rule about ONE producer, and this function sees only the
        // sum of every producer. An ancestor's `.background(Color.blue.opacity(0.5))` or
        // a `.listRowBackground` fill states an ink/field claim over a caret or an
        // animated border for an entirely legitimate reason, and the multiply below is
        // the right answer for it; the assertion could not tell that from a producer
        // double-stating, and trapped debug builds on a blend release got right. So the
        // rule is pinned where the producer is — each payload producer's own tests assert
        // it states no static claim of its own under its runs (§70.3).
        let destinationRow = run.offsetY + position.y
        let behindLine =
            destination.lines.indices.contains(destinationRow)
            ? destination.lines[destinationRow] : ""
        // Aligned into a pseudo-row so the frame's cells sit at the run's
        // own columns, where the per-column alpha and the destination line
        // expect them.
        let prefix = String(repeating: " ", count: max(0, run.offsetX))
        // A frame's cell that states no field inherits one from what the
        // containers inside this fade painted under it — a frame from
        // `colorize(glyph, foreground:)` states none, and the splice relies on
        // that field applying under it. Blended against what is behind the
        // layer alone, such a cell took the destination's field unblended (or
        // the bare surface) and then STATED it, so an indeterminate bar inside
        // `.background(.blue).opacity(0.5)` drew its tint once and replayed it
        // plain.
        //
        // From the run's GROUND, not from the line: the line under a cell is
        // whatever the render drew there, and where the drawn frame gave the
        // cell a field of its own the line shows that one. A `.plain` field's
        // block caret, drawn visible, put the caret's colour under its own off
        // frame, the two frames blended to one picture, and the run — not
        // animating any more — was dropped: under a fade the caret froze on.
        // See ``AnimatedCellRun/ground``.
        //
        // And a cell whose frame STATES the terminal's own field (`ESC[49m`) from
        // the second record, which holds what the painters made of a stated 49 —
        // the two records the splice draws a frame over, read the way it reads them
        // (`String.paintedOver(fields:)`). From the ground alone, a tab chip's label
        // on a `Color.default` palette inside `.background(.blue).opacity(0.6)` was
        // blended from blue and stated it, where the row shows the terminal's own:
        // the `.background` lets a stated 49 through. See
        // ``AnimatedCellRun/groundUnderStatedDefault``.
        let groundLine = run.ground.map { prefix + $0 }
        let statedDefaultLine = run.groundUnderStatedDefault.map { prefix + $0 }
        let columns = run.offsetX..<(run.offsetX + run.width)
        // The SAME fold the line took, not `covering.first`. A run is spliced
        // over cells the lines already answered for, so taking one region here
        // and multiplying there made the very same cell resolve two ways: a
        // `Spinner` inside `.foregroundStyle(.green.opacity(0.4))
        // .background(.red.opacity(0.4))` drew faded on both channels and then
        // replayed with the background back at full strength, once per tick,
        // forever. §13's bug, which the line path was fixed for and this one
        // was not — so the two now ask one function.
        //
        // Folded once for the whole run rather than once per frame: every
        // frame of a run occupies the same cells, so the answer cannot differ
        // between them, and an eight-frame spinner was computing it eight
        // times.
        let alphas = Self.foldedAlphas(
            of: covering, over: columns, row: run.offsetY, substituting: { $0.cellAlpha })
        /// The blend for one frame, at `perColumn` alphas indexed from the run's
        /// first cell — the one expression both arms below go through, so the frame
        /// a payload describes and the frame it does not are blended identically.
        func blend(_ frame: String, at perColumn: [FrameBuffer.CellAlpha?]) -> String {
            Self.blendedSpan(
                source: prefix + frame,
                destination: behindLine,
                columns: columns,
                destinationShift: position.x,
                fieldsFrom: groundLine,
                fieldsUnderStatedDefault: statedDefaultLine,
                alpha: { perColumn[$0 - columns.lowerBound] },
                surface: resolvedSurface,
                defaultForeground: resolvedForeground,
                fillingStatedTerminalField: fillingStatedTerminalField)
        }
        let fadedFrames: [String]
        if let perFrameAlpha = run.alpha, perFrameAlpha.isTranslucent {
            // The fold is still done ONCE for what covers the run from outside; only
            // the run's own spans are laid over it per frame, which is a handful of
            // cells rather than a re-walk of every region.
            fadedFrames = run.frames.indices.map { index in
                var perColumn = alphas
                for span in perFrameAlpha.spans(atFrame: index) {
                    let from = max(0, span.start)
                    let upTo = min(perColumn.count, span.start + span.cells)
                    guard from < upTo else { continue }
                    for column in from..<upTo {
                        // MULTIPLIED into what covers it, never replacing: an
                        // enclosing fade applies to a run's cells as it does to
                        // everything else, and the layer channel stays the outer
                        // region's because the payload has none.
                        let outer = perColumn[column]
                        perColumn[column] = Self.CellAlpha(
                            layer: outer?.layer ?? 1,
                            ink: (outer?.ink ?? 1) * span.ink,
                            field: (outer?.field ?? 1) * span.field)
                    }
                }
                return blend(run.frames[index], at: perColumn)
            }
        } else {
            fadedFrames = run.frames.map { blend($0, at: alphas) }
        }
        // The payload is SPENT: its alphas are in these bytes now, and carrying it
        // further would fade them a second time wherever the buffer is resolved
        // again (a floating surface resolves, then the root resolves what it landed
        // on). Same reason the regions themselves are cleared.
        return run.replacingFrames(fadedFrames, alpha: nil)
    }

    private static func foldedAlphas(
        of regions: [OpacityRegion], over columns: Range<Int>, row: Int,
        substituting: (OpacityRegion) -> FrameBuffer.CellAlpha?
    ) -> [FrameBuffer.CellAlpha?] {
        var result = [Self.CellAlpha?](repeating: nil, count: columns.count)
        for region in regions where region.spans(row: row) {
            guard let cell = substituting(region) else { continue }
            let from = max(columns.lowerBound, region.offsetX)
            let upTo = min(columns.upperBound, region.offsetX + region.width)
            guard from < upTo else { continue }
            for column in from..<upTo {
                let index = column - columns.lowerBound
                guard var accumulated = result[index] else {
                    result[index] = cell
                    continue
                }
                accumulated.ink *= cell.ink
                accumulated.field *= cell.field
                result[index] = accumulated
            }
        }
        return result
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
                over: self, at: position, surface: surface ?? palette.background, palette: palette,
                fillingStatedTerminalField: true, buildingRuns: true),
            at: position)
    }
}
