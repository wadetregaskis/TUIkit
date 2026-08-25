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
//  * **the ½ threshold decides a glyph CONTEST, and only applies where there
//    is one**: over a blank destination cell the source's character draws at
//    any alpha, fading continuously toward what is behind it; where the
//    destination has a character of its own, at or above ½ the source's
//    character is drawn and below ½ the destination keeps its own. At 0 the
//    source contributes nothing at all, so `opacity(0)` genuinely reveals what
//    is behind it rather than painting a near-black smudge over it;
//  * **a drawn source character blends both channels** — foreground AND
//    background — toward the background colour of what is behind it;
//  * **a source SPACE is not a glyph**: it composites its background — at
//    EVERY alpha, because colours blend at any strength and only glyphs need
//    the threshold — and keeps the destination's character. Without this,
//    fading a `VStack` would blank the whole rectangle it occupies, because
//    most of what a layer contributes is spaces;
//  * **the destination's foreground is left alone.** A translucent pane over
//    text does not tint that text; the text keeps its colour and the surface
//    behind it changes. That is the deliberate simplification — tinting reads
//    prettily in a GUI and illegibly in a cell grid.
//
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
    ///     other — see ``Color/opacity(_:over:)`` and `ANSIRenderer`.
    /// - Returns: A buffer with no opacity regions, ready to composite.
    public func resolvingOpacity(
        over destination: Self = Self(),
        at position: (x: Int, y: Int) = (x: 0, y: 0),
        surface: Color,
        palette: any Palette
    ) -> Self {
        guard !opacityRegions.isEmpty else { return self }
        // A fully opaque region is the identity, and taking that here means an
        // untouched layer comes out byte-for-byte untouched rather than
        // round-tripping through the cell walk to arrive at the same picture.
        //
        // Unless it is CYCLING, in which case opaque is merely where the fade
        // happens to be this instant — usually its very first frame — and
        // dropping it there would mean the fade never produced any frames at
        // all and never ran.
        let translucent = opacityRegions.filter { $0.opacity < 1 || $0.cycle != nil }
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
        func rebuild(_ row: Int, _ line: String, substituting: (OpacityRegion) -> Double?)
            -> String?
        {
            let covering = translucent.filter { $0.spans(row: row) }
            guard !covering.isEmpty else { return nil }
            let first = covering.map(\.offsetX).min() ?? 0
            let last = covering.map { $0.offsetX + $0.width }.max() ?? 0
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
            if let rebuilt = rebuild(row, rewritten[row], substituting: { $0.opacity }) {
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
        // So they go. A dropped run is a missed saving rather than a frozen
        // animation: `noteServedByRuns` is the only thing that stops the loop
        // rendering for an animation, and `.opacity` is its only caller — every
        // other producer keeps asking for frames and simply pays for them. Same
        // reasoning, and the same trade, as the runs `_ListCore` declines to
        // carry out of a badged row.
        result.animatedCells = result.animatedCells.filter { run in
            !translucent.contains { region in
                region.spans(row: run.offsetY)
                    && run.offsetX < region.offsetX + region.width
                    && region.offsetX < run.offsetX + run.width
            }
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
    private static func cyclingRuns(
        of regions: [OpacityRegion],
        over lines: [String],
        rebuilding rebuild: (Int, String, (OpacityRegion) -> Double?) -> String?
    ) -> [AnimatedCellRun] {
        var runs: [AnimatedCellRun] = []
        for region in regions {
            guard let cycle = region.cycle, cycle.phases.count >= 2 else { continue }
            let rows = max(0, region.offsetY)..<min(lines.count, region.offsetY + region.height)
            guard !rows.isEmpty else { continue }
            var phases: [[String]] = []
            phases.reserveCapacity(cycle.phases.count)
            for phase in cycle.phases {
                phases.append(
                    rows.map { row in
                        rebuild(row, lines[row], { $0 == region ? phase : $0.opacity })
                            ?? lines[row]
                    })
            }
            // `nil` where the phases disagree about the shape of the picture: a
            // run cannot change a row's width, and one that tried would shift
            // the rest of the row sideways on some ticks and not others.
            guard
                let built = AnimatedBufferCycle.runs(
                    phases: phases, offsetY: rows.lowerBound, clock: cycle.clock)
            else { continue }
            runs += built
        }
        return runs
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

// MARK: - The span

extension FrameBuffer {

    /// One cell of a rendered row, taken apart far enough to blend it.
    ///
    /// `style` carries everything SGR says that is NOT colour — bold, dim,
    /// underline, inverse — so a faded bold label stays bold. The two colours
    /// are pulled out separately because they are the only part the blend
    /// touches, and `SGRState` deliberately keeps them as parameter lists
    /// rather than as `Color`s (it lives a module below `Color`).
    fileprivate struct RowCell {
        var character: Character
        var style: SGRState
        var foreground: Color?
        var background: Color?
    }

    /// The blended replacement for `columns` of `source`, as a self-contained
    /// string that starts and ends at the terminal's default state.
    ///
    /// `alpha` returns `nil` for a column no region covers, which passes the
    /// source cell through untouched — a row can be covered in part, and a span
    /// that runs from the leftmost to the rightmost covered column is one
    /// splice instead of one per region.
    fileprivate static func blendedSpan(
        source: String,
        destination: String,
        columns: Range<Int>,
        destinationShift: Int,
        alpha: (Int) -> Double?,
        surface: Color,
        defaultForeground: Color
    ) -> String {
        let sourceCells = cells(in: source, through: columns.upperBound)
        let behindCells = cells(
            in: destination, through: columns.upperBound + destinationShift)

        var span = ""
        var emitted = SGRState()
        var column = columns.lowerBound
        while column < columns.upperBound {
            guard let cell = sourceCells[column] else {
                // A continuation column of a wide source character: the
                // character was emitted at its start column and claims this one
                // too, so nothing is due here.
                column += 1
                continue
            }
            // Bounds-checked rather than trusted: a negative shift is legal —
            // `composited` accepts one — and would index before the start.
            let behindColumn = column + destinationShift
            let behind =
                behindCells.indices.contains(behindColumn) ? behindCells[behindColumn] : nil
            let blended = blend(
                source: cell, destination: behind, alpha: alpha(column),
                surface: surface, defaultForeground: defaultForeground)
            span += blended.style.rendered(changingFrom: emitted)
            span.append(blended.character)
            emitted = blended.style
            column += max(1, blended.character.terminalWidth)
        }
        // Close the span rather than leaving its styling open: `splicing`
        // restores the line's own state where the span ends, and an open
        // background would otherwise reach the cell after it.
        span += SGRState().rendered(changingFrom: emitted)
        return span
    }

    /// One cell's answer.
    private static func blend(
        source: RowCell, destination: RowCell?, alpha: Double?,
        surface: Color, defaultForeground: Color
    ) -> RowCell {
        // Uncovered, or fully opaque: the source stands as it is.
        guard let alpha, alpha < 1 else { return source }
        // At zero the source contributes nothing at all, and the destination
        // is not merely approximated, it is UNTOUCHED: character, colours and
        // attributes, byte for byte. Every blend below converges here as
        // alpha does, so this is a shortcut, not a discontinuity.
        guard alpha > 0 else {
            return destination ?? RowCell(character: " ", style: SGRState())
        }
        // What the destination actually shows where it paints nothing of its
        // own. A cell with no background is not transparent to the terminal —
        // it is the surface.
        let behind = destination?.background ?? surface
        // A space carries no ink, so it yields the character and composites only
        // its background — and where it has none, it changes nothing at all.
        // That last part is what makes a faded `VStack`'s padding transparent
        // instead of a rectangle of blanks punched through the page.
        //
        // At EVERY alpha, not only above the glyph threshold: colours can blend
        // at any strength — the threshold exists because two characters cannot
        // share a cell, and a space is not a character contest. Gating this on
        // ½ made a translucent panel vanish whole at the midpoint instead of
        // fading smoothly to nothing.
        if source.character == " " {
            let fadedBackground = source.background.map { $0.opacity(alpha, over: behind) }
            guard let fadedBackground else {
                return destination ?? RowCell(character: " ", style: SGRState())
            }
            var kept = destination ?? RowCell(character: " ", style: SGRState())
            kept.background = fadedBackground
            kept.style = kept.style.settingBackground(fadedBackground)
            return kept
        }
        // The threshold decides a CONTEST — two glyphs wanting one cell — and
        // only applies where there is one. Where the destination is blank, the
        // source's character draws at any alpha, fading toward what is behind
        // it and reaching invisibility at 0 with nothing to pop: gating it on ½
        // made text over a plain panel vanish at the midpoint of a fade when
        // there was never anything to reveal underneath it.
        //
        // Where the destination DOES have a character, below ½ the source's
        // glyph is not drawn and the destination keeps its own.
        if alpha < 0.5, let destination, destination.character != " " {
            return destination
        }
        let fadedBackground = source.background.map { $0.opacity(alpha, over: behind) }
        var result = source
        let foreground = (source.foreground ?? defaultForeground).opacity(alpha, over: behind)
        // Where neither side paints a background, the cell keeps naming none —
        // which is the surface, and is what it named before.
        let background = fadedBackground ?? destination?.background
        result.foreground = foreground
        result.background = background
        result.style = source.style.settingForeground(foreground).settingBackground(background)
        return result
    }

    /// `line` taken apart into one entry per COLUMN, up to `width`.
    ///
    /// `nil` where a wide character claims a column it did not start, and where
    /// the line ran out. Indexed by column so the two sides line up without
    /// either having to be walked twice.
    private static func cells(in line: String, through width: Int) -> [RowCell?] {
        var result = [RowCell?](repeating: nil, count: max(0, width))
        guard width > 0, !line.isEmpty else { return result }
        var state = SGRState()
        var foreground: Color?
        var background: Color?
        var column = 0
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                state.apply(sequence)
                guard isSGR else { continue }
                SGRColorRewrite.readingColors(sequence) { which, color in
                    switch which {
                    case .foreground: foreground = color
                    case .background: background = color
                    case .reset: foreground = nil; background = nil
                    }
                }
            case .visible(let character):
                guard column < width else { return result }
                result[column] = RowCell(
                    character: character, style: state,
                    foreground: foreground, background: background)
                column += max(1, character.terminalWidth)
            }
        }
        return result
    }
}

// MARK: - Setting a colour on a parsed state

extension SGRState {
    /// This state with its foreground replaced. `nil` is the terminal's
    /// default (SGR 39) — what a cell that named no colour of its own had.
    ///
    /// Written as an `apply` of the sequence that would set it rather than as a
    /// stored property, because `SGRState` deliberately keeps its colours as
    /// SGR parameter lists: it lives a module below ``Color`` and cannot hold
    /// one. Folding in the sequence is the same operation the parse performs,
    /// so there is one code path for "what colour is in force".
    fileprivate func settingForeground(_ color: Color?) -> Self {
        var result = self
        result.apply(Self.sgr(color.map { ANSIRenderer.foregroundCodes(for: $0) } ?? ["39"]))
        return result
    }

    /// This state with its background replaced. `nil` is SGR 49.
    fileprivate func settingBackground(_ color: Color?) -> Self {
        var result = self
        result.apply(Self.sgr(color.map { ANSIRenderer.backgroundCodes(for: $0) } ?? ["49"]))
        return result
    }

    private static func sgr(_ codes: [String]) -> String {
        "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}
