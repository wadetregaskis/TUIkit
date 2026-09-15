//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Track Renderer

/// Utility for rendering track-based visual indicators.
///
/// `TrackRenderer` provides shared rendering logic for controls that display
/// a visual track, such as `ProgressView` and `Slider`. It supports multiple
/// styles via ``TrackStyle``.
///
/// ## Usage
///
/// ```swift
/// let track = TrackRenderer.render(
///     fraction: 0.5,
///     width: 20,
///     style: .block,
///     fillColor: palette.foregroundSecondary,
///     backgroundColor: palette.foregroundTertiary,
///     accentColor: palette.accent
/// )
/// ```
enum TrackRenderer {
    /// Renders a track with the specified style and colors.
    ///
    /// - Parameters:
    ///   - fraction: The completed fraction (0.0 to 1.0).
    ///   - width: The width in characters.
    ///   - style: The visual style to use.
    ///   - fillColor: The color for the fill.
    ///   - backgroundColor: The color for the background.
    ///   - accentColor: The color for accent elements (e.g., dot head).
    ///   - fillScaling: What the fill's gradient is measured across — the whole
    ///     bar (the default) or only the lit part. See ``TrackGradientScaling``.
    ///   - backgroundScaling: The same question for the background's
    ///     gradient — the bar, or only the cells the fill has not reached.
    ///   - palette: The palette the style's own colours are resolved against.
    ///     The three colours above arrive resolved; a style read from the
    ///     environment does not, and a palette role has no channels to emit.
    ///   - graphics: Where to keep the track as a PICTURE, for a style whose
    ///     cells are colour and nothing else (`TrackConfiguration.isColourField`)
    ///     on a terminal that draws pictures — `nil` draws cells, which every
    ///     other style does regardless. See ``TrackRaster``.
    /// - Returns: The track's bytes, the cells that owe a blend, and how many
    ///   cells were drawn.
    static func render(
        fraction: Double,
        width: Int,
        style: TrackStyle,
        fillColor: Color,
        backgroundColor: Color,
        accentColor: Color,
        fillScaling: TrackGradientScaling = .track,
        backgroundScaling: TrackGradientScaling = .track,
        palette: any Palette,
        graphics: GradientGraphicsContext? = nil
    ) -> ClaimingRow {
        let style = style.resolvingColours(with: palette)
        // Read once per render, not once per cell. A gradient can only be
        // quantised as a ramp if it knows what the terminal will do to it; at
        // truecolor every helper below falls through to the plain interpolation.
        let depth = ColorDepth.current
        guard width > 0 else { return ClaimingRow() }

        // Clamp fraction to [0, 1] to prevent track overflow
        let fraction = min(1.0, max(0.0, fraction))

        // The "fill" family — a run of full cells, an optional fractional
        // boundary cell, then the unfilled remainder — is one parameterized
        // renderer driven by a `TrackConfiguration`; as a picture where the
        // cells would all be plain colour and the terminal draws pictures.
        // The named cases are just presets; `.custom` carries a caller-supplied
        // recipe.
        func configured(_ config: TrackConfiguration) -> ClaimingRow {
            // A PICTURE has no alpha channel to send — `GradientRaster.Picture.format`
            // is `.rgb`, and a terminal would in any case composite it against its own
            // background rather than against what TUIkit drew behind the cell. So a
            // translucent track declines this path and takes the cell one, which
            // claims correctly. `BackgroundModifier` declines a translucent ramp for
            // the same reason (§15.1), and it matters more here: `.block` is
            // `ProgressView`'s default, so without this the gap would be
            // terminal-distributed — right on Apple Terminal, wrong on kitty.
            let opaqueThroughout =
                fillColor.isOpaque && backgroundColor.isOpaque
                && config.backgroundColor?.isOpaque != false
                && config.fillGradient?.isOpaqueThroughout != false
                && config.backgroundGradient?.isOpaqueThroughout != false
            if let graphics, config.isColourField, opaqueThroughout,
                let row = renderPicture(
                    fraction: fraction, width: width, config: config,
                    fillColor: fillColor, backgroundColor: backgroundColor,
                    fillScaling: fillScaling, backgroundScaling: backgroundScaling, graphics: graphics)
            {
                var drawn = ClaimingRow()
                drawn.appendFinished(row, cells: width)
                return drawn
            }
            return renderConfigured(
                fraction: fraction, width: width, config: config,
                fillColor: fillColor, backgroundColor: backgroundColor,
                fillScaling: fillScaling, backgroundScaling: backgroundScaling, depth: depth)
        }

        switch style {
        case .block: return configured(.block)
        case .blockFine: return configured(.blockFine)
        case .shade: return configured(.shade)
        case .bar: return configured(.bar)
        case .braille: return configured(.braille)
        case .shadeRamp(let gradient): return configured(.shadeRamp(gradient: gradient))
        case .custom(let config): return configured(config)

        // The head / marker / segment families are structurally distinct
        // (single indicator, no fractional fill ramp) and keep their own paths.
        case .dot:
            return renderHeadStyle(
                fraction: fraction,
                width: width,
                filledChar: "▬",
                headChar: "●",
                emptyChar: "─",
                fillColor: fillColor,
                headColor: accentColor,
                backgroundColor: backgroundColor
            )
        case .knob:
            return renderHeadStyle(
                fraction: fraction,
                width: width,
                filledChar: "━",
                headChar: "●",
                emptyChar: "─",
                fillColor: accentColor,
                headColor: accentColor,
                backgroundColor: backgroundColor
            )
        case .marker:
            return renderMarkerStyle(
                fraction: fraction,
                width: width,
                lineChar: "─",
                markerChar: "●",
                lineColor: backgroundColor,
                markerColor: accentColor
            )
        case .threeSegment(let leading, let middle, let trailing, let backgroundPattern, let coloring):
            return renderThreeSegmentStyle(
                fraction: fraction,
                width: width,
                leading: leading,
                middle: middle,
                trailing: trailing,
                backgroundPattern: backgroundPattern,
                coloring: coloring,
                fillColor: fillColor,
                backgroundColor: backgroundColor,
                fillScaling: fillScaling,
                depth: depth
            )
        }
    }

    /// The colour a gradient shows at cell `index` of a `span`-cell ramp — the
    /// one interpolation every track consumer uses: the configured fill
    /// tracks, the stepped fill and `.threeSegment`'s
    /// ``SegmentColoring/gradient(_:)``. (The indeterminate sweep samples
    /// `Gradient.color(at:)` per intensity; it is not a run of cells.) ONE
    /// stop is a solid colour, not a broken gradient — the editor can collapse
    /// a ramp to a single stop — and only an EMPTY gradient yields `fallback`.
    ///
    /// Not `Gradient.color(at:)` per cell, because a per-cell nearest
    /// match has no memory of its neighbours and a gradient's smoothness is a
    /// property of the SEQUENCE — see ``Color/quantisedRamp(_:count:depth:)``,
    /// which is where the whole ramp is quantised at once and repaired into a
    /// monotone one. At truecolor depth it returns the same interpolation this
    /// always produced, so no caller has to branch on the terminal.
    ///
    /// The ramp is memoised on `(gradient, span, depth)`, so asking cell by
    /// cell costs one dictionary hit each after the first.
    /// The track as one row of placeholder cells naming a picture of it — or
    /// `nil` when the protocol declines the box, or a colour of the track has no
    /// RGB (`TrackRaster.picture`), at which point the cells are drawn as they
    /// always were.
    ///
    /// The picture changes with the VALUE: every distinct boundary pixel is a
    /// new image, and a slider being dragged transmits one per frame. That is
    /// a row of pixels, deflated where the terminal takes it — about a
    /// kilobyte — against the SGR-per-cell row it replaces, and the previous
    /// one is freed as each arrives (`TerminalImageStore` reuses the id).
    private static func renderPicture(
        fraction: Double, width: Int, config: TrackConfiguration,
        fillColor: Color, backgroundColor: Color,
        fillScaling: TrackGradientScaling, backgroundScaling: TrackGradientScaling,
        graphics: GradientGraphicsContext
    ) -> String? {
        guard
            let picture = TrackRaster.picture(
                fraction: fraction, width: width, config: config,
                fillColor: fillColor, backgroundColor: backgroundColor,
                fillScaling: fillScaling, backgroundScaling: backgroundScaling,
                cellPixels: graphics.cellPixels)
        else { return nil }
        let signature = TrackImageSignature(
            config: config, fillColor: fillColor, backgroundColor: backgroundColor,
            fillScaling: fillScaling, backgroundScaling: backgroundScaling,
            width: picture.width, height: picture.height,
            lit: Int((fraction * Double(picture.width)).rounded()))
        return graphics.store.placeholderRows(
            token: graphics.token, signature: signature, columns: width, rows: 1,
            pixels: { (picture.bytes, picture.format, picture.width, picture.height) }
        )?.first
    }

    static func gradientColor(
        _ gradient: Gradient, index: Int, span: Int, fallback: Color, depth: ColorDepth
    ) -> Color {
        guard !gradient.stops.isEmpty, span > 0 else { return fallback }
        let ramp = Color.quantisedRamp(gradient, count: span, depth: depth)
        guard !ramp.isEmpty else { return fallback }
        return ramp[max(0, min(ramp.count - 1, index))]
    }
}

// MARK: - Private Rendering Methods

extension TrackRenderer {
    /// Renders any "fill" track — a run of full cells, an optional fractional
    /// boundary cell, then the unfilled remainder — from a ``TrackConfiguration``.
    ///
    /// This single routine backs `.block`, `.shade`, `.bar`, `.blockFine`,
    /// `.braille`, `.shadeRamp`, and `.custom`. What varies between them is
    /// purely data: the fill pattern, the (optional) sub-cell boundary ramp,
    /// how the empty region is drawn, and an optional fill gradient.
    ///
    /// Fill and unfilled patterns repeat cyclically and truncate at their
    /// boundaries; multi-cell characters (emoji, CJK) can't be truncated, so
    /// they switch to a coarse mode: the resolution drops to the widest
    /// character's cell width, the track permanently shrinks to a neat
    /// multiple of it, and the boundary ramp subdivides the quantum *block*
    /// rather than a single cell (see ``renderCoarsePattern``).
    private static func renderConfigured(
        fraction: Double,
        width: Int,
        config: TrackConfiguration,
        fillColor: Color,
        backgroundColor: Color,
        fillScaling: TrackGradientScaling,
        backgroundScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> ClaimingRow {
        let fillChars = Array(config.fill.isEmpty ? "█" : config.fill)
        let emptyChars: [Character]
        let paintsBackground: Bool
        switch config.background {
        case .pattern(let pattern):
            emptyChars = Array(pattern.isEmpty ? " " : pattern)
            paintsBackground = false
        case .solid:
            emptyChars = []
            paintsBackground = true
        }

        // Any multi-cell character forces the coarse quantized mode. (The
        // `.solid` background is spaces, so only a patterned background
        // constrains the quantum.) The ramp counts too: its glyph is
        // drawn INTO the boundary cell, so a two-cell ramp glyph over a
        // one-cell fill made the track a cell longer whenever a boundary cell
        // was drawn — and the bar's length then followed its value.
        let quantum = max(
            fillChars.map(\.terminalWidth).max() ?? 1,
            emptyChars.map(\.terminalWidth).max() ?? 1,
            config.leadingEdge?.map(\.terminalWidth).max() ?? 1)
        if quantum > 1 {
            return renderCoarsePattern(
                fraction: fraction, width: width, quantum: quantum,
                fillChars: fillChars, emptyChars: emptyChars,
                config: config, fillColor: fillColor, backgroundColor: backgroundColor,
                paintsBackground: paintsBackground, fillScaling: fillScaling,
                depth: depth)
        }

        // A ramp of n glyphs gives n+1 sub-cell steps; no ramp means whole-cell
        // quantization (stepsPerCell == 1, so this reduces to a plain fill).
        let ramp = config.leadingEdge
        let stepsPerCell = (ramp?.count ?? 0) + 1
        let totalSteps = Int((fraction * Double(width) * Double(stepsPerCell)).rounded())
        let fullCells = totalSteps / stepsPerCell
        let partialStep = ramp == nil ? 0 : totalSteps % stepsPerCell
        let fullCount = min(fullCells, width)
        let hasPartial = ramp != nil && partialStep > 0 && fullCells < width
        let litCellCount = min(width, fullCount + (hasPartial ? 1 : 0))

        // `.solid` paints backgrounds across the whole track. The empty
        // region and the partial boundary cell sit on the EMPTY colour (a flat
        // unfilled remainder). Full cells paint their own FILL colour as the
        // background: terminals don't reliably cover the whole cell with a
        // glyph — Terminal.app leaves a few pixel rows above U+2588 and
        // hairline seams between cells, which used to show the empty colour
        // as a bleed above/through the fill (verified visually in
        // Terminal.app). With glyph colour == background colour those
        // unpainted pixels vanish, while the real glyph is kept so a
        // plain-text copy (no styling) still shows where the progress was.
        // A style that has chosen a fill also gets a say in what the fill is
        // drawn AGAINST — the unfilled half of a bar is half of what it looks
        // like. `nil` keeps the control's own recessive colour, which is what
        // every built-in preset does.
        let backgroundColor = config.backgroundColor ?? backgroundColor

        // Optional per-cell colour fade. What it is measured across is the
        // caller's choice (``TrackGradientScaling``): the whole bar, so a
        // colour always marks the same value, or the lit part, so the ramp
        // follows the fill. Compressing into the lit part is what this always
        // did, and it makes a gradient meant as a SCALE ("red past 80%") lie —
        // at 10% the bar's one lit cell is the last colour.
        let gradientSpan = fillScaling == .track ? width : litCellCount
        func fillColour(at index: Int) -> Color {
            guard let gradient = config.fillGradient, gradientSpan > 1 else {
                return fillColor
            }
            return gradientColor(
                gradient, index: index, span: gradientSpan,
                fallback: fillColor, depth: depth)
        }

        // For COLOUR, the unfilled region starts AT the boundary cell rather
        // than after it. That cell is genuinely part-empty — the ramp glyph
        // covers the filled fraction and the unfilled colour shows through the
        // rest — so it is the unfilled ramp's first cell, not a cell the
        // unfilled ramp skips. How much of it shows is a property of the
        // terminal's font, which nothing here can ask about, so assume some
        // always does: painting it the colour the ramp reaches there is wrong
        // by at most a fraction of one cell, and painting it a colour from
        // somewhere else entirely is wrong by however far apart the stops are.
        //
        // With no boundary cell `fullCount == litCellCount` and this is the
        // run that was always drawn.
        // Its own question, not the fill's: the two ramps are measured across
        // what each paints, and a scale on one side says nothing about a
        // decoration on the other.
        let emptyRegionStart = fullCount
        let emptySpan = backgroundScaling == .track ? width : width - emptyRegionStart
        func emptyColour(at cell: Int) -> Color {
            guard let gradient = config.backgroundGradient, emptySpan > 1 else { return backgroundColor }
            return gradientColor(
                gradient, index: backgroundScaling == .track ? cell : cell - emptyRegionStart,
                span: emptySpan, fallback: backgroundColor, depth: depth)
        }

        var row = ClaimingRow()
        for index in 0..<fullCount {
            let cellColour = fillColour(at: index)
            row.append(
                String(fillChars[index % fillChars.count]), cells: 1, ink: cellColour,
                field: paintsBackground ? cellColour : nil)
        }
        if hasPartial, let ramp {
            // The boundary cell is genuinely part-empty: the glyph covers the
            // filled fraction and the empty colour correctly shows behind the
            // rest of the cell.
            //
            // It is also the one cell in the framework whose INK and FIELD come from
            // different sources, which is what makes the two channels earn their
            // keep: an opaque `█` fill with a translucent
            // `TrackConfiguration.backgroundColor` must resolve `inkOpacity == 1,
            // fieldOpacity < 1` — the ramp glyph solid, the rest of the cell faded.
            // One alpha per cell gets this cell wrong in both directions.
            row.append(
                String(ramp[partialStep - 1]), cells: 1, ink: fillColour(at: fullCount),
                field: paintsBackground ? emptyColour(at: fullCount) : nil)
        }
        let emptyCount = width - litCellCount
        if emptyCount > 0 {
            // Anchored to the TRACK (cell j always shows the same character),
            // so the texture stays put while the fill sweeps across it.
            func emptyGlyphs() -> String {
                var glyphs = ""
                for cell in litCellCount..<width {
                    glyphs.append(emptyChars[cell % emptyChars.count])
                }
                return glyphs
            }
            if config.backgroundGradient != nil, emptySpan > 1 {
                for cell in litCellCount..<width {
                    let colour = emptyColour(at: cell)
                    row.append(
                        paintsBackground ? " " : String(emptyChars[cell % emptyChars.count]),
                        cells: 1, ink: colour, field: paintsBackground ? colour : nil)
                }
            } else if paintsBackground {
                // One run, one escape: a flat unfilled remainder is what almost
                // every bar draws, and it must not cost a colour change a cell.
                // One CLAIM as well, for the same reason.
                row.append(
                    String(repeating: " ", count: emptyCount), cells: emptyCount,
                    ink: backgroundColor, field: backgroundColor)
            } else {
                row.append(emptyGlyphs(), cells: emptyCount, ink: backgroundColor)
            }
        }
        return row
    }

    // The coarse pattern mode: some fill/unfilled character is wider than
    // one cell, so the fill can only advance in steps of the widest
    // character's width (`quantum`), and the track PERMANENTLY shrinks to
    // the largest multiple of the quantum that fits — its width must not
    // vary with the fill:unfilled ratio. The boundary ramp keeps working at
    // this resolution, one level coarser: it subdivides the quantum BLOCK
    // instead of a single cell — the partially-filled block renders as the
    // ramp glyph for its sub-block fraction, repeated across the block (an
    // emoji fill with a shade ramp reads "😃😃▒▒····"). Mixed-width patterns
    // that cannot land exactly on a step boundary are padded with spaces.
    // The inputs are the decomposed configuration plus the two colours;
    // bundling them into a struct would obscure the 1:1 relationship with
    // renderConfigured's locals.
    // swiftlint:disable:next function_parameter_count
    private static func renderCoarsePattern(
        fraction: Double,
        width: Int,
        quantum: Int,
        fillChars: [Character],
        emptyChars: [Character],
        config: TrackConfiguration,
        fillColor: Color,
        backgroundColor: Color,
        paintsBackground: Bool,
        fillScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> ClaimingRow {
        // The style's own unfilled colour, if it named one — see the fine path.
        let backgroundColor = config.backgroundColor ?? backgroundColor
        let effectiveWidth = (width / quantum) * quantum
        guard effectiveWidth > 0 else { return ClaimingRow() }
        let steps = effectiveWidth / quantum

        // With a ramp of n glyphs each block has n+1 sub-steps — the same
        // arithmetic the fine path applies per cell, at block granularity.
        // Without one this reduces to whole-block quantization (the previous
        // behaviour exactly).
        let ramp = config.leadingEdge
        let stepsPerBlock = (ramp?.count ?? 0) + 1
        let totalSteps = Int((fraction * Double(steps) * Double(stepsPerBlock)).rounded())
        let litSteps = min(totalSteps / stepsPerBlock, steps)
        let partialStep = ramp == nil ? 0 : totalSteps % stepsPerBlock
        let hasPartial = ramp != nil && partialStep > 0 && totalSteps / stepsPerBlock < steps
        let targetCells = litSteps * quantum

        // As in `renderConfigured`: the ramp spans the bar or the lit part.
        let gradientSpan = fillScaling == .track ? steps * quantum : targetCells
        func fillColour(atCell cell: Int) -> Color {
            guard let gradient = config.fillGradient, gradientSpan > 1 else {
                return fillColor
            }
            return gradientColor(
                gradient, index: cell, span: gradientSpan,
                fallback: fillColor, depth: depth)
        }

        // The fill: walk the cyclic pattern up to the step boundary.
        //
        // Claimed per GLYPH at its real cell width, which is the whole point of this
        // path: a character-counted rectangle would be wrong by up to `quantum − 1`
        // cells per glyph here, where an emoji fill is two cells wide.
        var row = ClaimingRow()
        var cell = 0
        var index = 0
        while cell < targetCells {
            let character = fillChars[index % fillChars.count]
            let charWidth = max(1, character.terminalWidth)
            guard cell + charWidth <= targetCells else { break }
            let colour = fillColour(atCell: cell)
            row.append(
                String(character), cells: charWidth, ink: colour,
                field: paintsBackground ? colour : nil)
            cell += charWidth
            index += 1
        }
        if cell < targetCells {
            // A mixed-width pattern that can't land on the boundary: pad the
            // shortfall so the unfilled region still starts on its cell.
            row.append(
                String(repeating: " ", count: targetCells - cell), cells: targetCells - cell,
                ink: backgroundColor, field: paintsBackground ? backgroundColor : nil)
        }

        // The partially-filled block: its ramp glyph (chosen by the sub-block
        // fraction) repeated across the whole quantum, so the block reads as
        // "this much of the next step". The glyph sits on the empty colour,
        // exactly like the fine path's boundary cell — the block is genuinely
        // part-empty.
        var rampCells = 0
        if hasPartial, let ramp {
            let glyph = ramp[partialStep - 1]
            let glyphWidth = max(1, glyph.terminalWidth)
            let rampColour = fillColour(atCell: targetCells)
            var block = ""
            while rampCells + glyphWidth <= quantum {
                block.append(glyph)
                rampCells += glyphWidth
            }
            if rampCells < quantum {
                block += String(repeating: " ", count: quantum - rampCells)
                rampCells = quantum
            }
            row.append(
                block, cells: rampCells, ink: rampColour,
                field: paintsBackground ? backgroundColor : nil)
        }

        // The unfilled remainder: spaces on the empty colour for
        // `.background`, else the cyclic unfilled pattern truncated at its
        // own character boundaries and space-padded to the track edge.
        let remaining = effectiveWidth - targetCells - rampCells
        guard remaining > 0 else { return row }
        if paintsBackground {
            row.append(
                String(repeating: " ", count: remaining), cells: remaining, ink: backgroundColor,
                field: backgroundColor)
            return row
        }
        var empty = ""
        var emptyCell = 0
        var emptyIndex = 0
        while emptyCell < remaining {
            let character = emptyChars[emptyIndex % emptyChars.count]
            let charWidth = max(1, character.terminalWidth)
            guard emptyCell + charWidth <= remaining else { break }
            empty.append(character)
            emptyCell += charWidth
            emptyIndex += 1
        }
        if emptyCell < remaining {
            empty += String(repeating: " ", count: remaining - emptyCell)
        }
        row.append(empty, cells: remaining, ink: backgroundColor)
        return row
    }

    // Renders the `.threeSegment` style: `[leading][middle × N][trailing]`
    // covers the filled region, with `middle` repeated to span any gap; the
    // lit region's colouring is delegated to `renderLitRegion`. (The inputs
    // are the case's own associated values plus the two track colours —
    // bundling them to satisfy the parameter ceiling would obscure the 1:1
    // mapping to the style.)
    // swiftlint:disable:next function_parameter_count
    private static func renderThreeSegmentStyle(
        fraction: Double,
        width: Int,
        leading: String,
        middle: String,
        trailing: String,
        backgroundPattern: String,
        coloring: SegmentColoring,
        fillColor: Color,
        backgroundColor: Color,
        fillScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> ClaimingRow {
        let leadingWidth = leading.strippedLength
        let trailingWidth = trailing.strippedLength
        let middleWidth = max(1, middle.strippedLength)
        let filledCount = Int((fraction * Double(width)).rounded())
        // What a gradient is measured across, exactly as every other style
        // reads it: the whole bar, so a colour always marks the same value, or
        // the lit part, so the ramp follows the fill. This style used to ignore
        // the setting entirely and always compress into the lit part, which
        // made a gradient meant as a SCALE lie — at 10% its one lit cell is the
        // last colour.
        let gradientSpan = fillScaling == .track ? width : filledCount

        var row = ClaimingRow()

        if filledCount <= 0 {
            // Nothing lit at all.
        } else if filledCount < leadingWidth + trailingWidth {
            // Not enough room for both endpoints; render whichever fits
            // from the leading edge (per-segment colouring uses the leading
            // colour for the truncated composite).
            let truncated = (leading + trailing).ansiAwarePrefix(visibleCount: filledCount)
            renderLitRegion(
                leading: truncated, middleRun: "", trailing: "",
                coloring: coloring, fillColor: fillColor, gradientSpan: gradientSpan,
                depth: depth, into: &row)
        } else {
            // Endpoints fit. Repeat `middle` to fill the gap, plus a
            // partial trailing slice if needed.
            let gap = filledCount - leadingWidth - trailingWidth
            let reps = gap / middleWidth
            let remainder = gap - reps * middleWidth
            var middleRun = ""
            if reps > 0 {
                middleRun += String(repeating: middle, count: reps)
            }
            if remainder > 0 {
                middleRun += middle.ansiAwarePrefix(visibleCount: remainder)
            }
            renderLitRegion(
                leading: leading, middleRun: middleRun, trailing: trailing,
                coloring: coloring, fillColor: fillColor, gradientSpan: gradientSpan,
                depth: depth, into: &row)
        }

        let emptyCellCount = max(0, width - filledCount)
        if emptyCellCount > 0 {
            let backgroundPatternWidth = max(1, backgroundPattern.strippedLength)
            let emptyReps = emptyCellCount / backgroundPatternWidth
            let emptyRemainder = emptyCellCount - emptyReps * backgroundPatternWidth
            var empty = ""
            if emptyReps > 0 {
                empty += String(repeating: backgroundPattern, count: emptyReps)
            }
            if emptyRemainder > 0 {
                empty += backgroundPattern.ansiAwarePrefix(visibleCount: emptyRemainder)
            }
            row.append(empty, cells: emptyCellCount, ink: backgroundColor)
        }
        return row
    }

    /// Colours the assembled lit region of a `.threeSegment` track.
    ///
    /// With `.automatic` / `.solid` / `.perSegment` each part is emitted
    /// as-is, so callers can pass already-styled strings (ANSI codes
    /// embedded); `.gradient` re-colours cell by cell and expects plain text.
    ///
    /// Widths are measured in CELLS (`strippedLength` sums terminal widths), never in
    /// characters: a segment can be any string, and the existing wide-glyph tests use
    /// 🌑/🌕/🌖. A character count would put every claim after the first in the wrong
    /// column.
    ///
    /// - Note: `.automatic` / `.solid` / `.perSegment` accept segments that already
    ///   carry the caller's own ANSI, and where they do, some cells' effective ink is
    ///   not the colour the claim is about. The run *was* painted at that alpha, so
    ///   the claim is not wrong so much as approximate, and there is no way to ask a
    ///   pre-styled string what it is going to look like. `.gradient` re-colours cell
    ///   by cell and expects plain text, so it has no such gap.
    private static func renderLitRegion(
        leading: String, middleRun: String, trailing: String,
        coloring: SegmentColoring, fillColor: Color, gradientSpan: Int, depth: ColorDepth,
        into row: inout ClaimingRow
    ) {
        let whole = leading + middleRun + trailing
        switch coloring {
        case .automatic:
            row.append(whole, cells: whole.strippedLength, ink: fillColor)
        case .solid(let color):
            row.append(whole, cells: whole.strippedLength, ink: color)
        case .perSegment(let leadingColor, let middleColor, let trailingColor):
            row.append(leading, cells: leading.strippedLength, ink: leadingColor)
            if !middleRun.isEmpty {
                row.append(middleRun, cells: middleRun.strippedLength, ink: middleColor)
            }
            if !trailing.isEmpty {
                row.append(trailing, cells: trailing.strippedLength, ink: trailingColor)
            }
        case .gradient(let stops):
            gradientCells(
                whole.stripped, gradient: stops, fallback: fillColor,
                span: gradientSpan, depth: depth, into: &row)
        }
    }

    /// Colours `text` cell by cell across gradient `stops`.
    ///
    /// `span` is how many cells the gradient is measured across — the whole
    /// track, or just the lit part (see ``TrackGradientScaling``). The text may
    /// be shorter than the span, in which case it uses the first part of the
    /// ramp and the rest is simply not reached; that is what makes a gradient
    /// read as a scale rather than as a fade.
    ///
    /// A translucent gradient stop is honourable here for the reason §36 later made
    /// the 2-D ramps honourable too, arriving a row early: a track is ONE row, so a
    /// per-cell alpha is a run of one-cell rectangles rather than a grid, and the
    /// resolver folds them the same way it folds any other claim.
    private static func gradientCells(
        _ text: String, gradient: Gradient, fallback: Color, span: Int, depth: ColorDepth,
        into row: inout ClaimingRow
    ) {
        let cells = Array(text)
        guard cells.count > 1, span > 1 else {
            row.append(
                text, cells: text.strippedLength, ink: gradient.stops.first?.color ?? fallback)
            return
        }
        // Indexed by the CELL column, not the character: `span` counts cells,
        // and a wide glyph — a segment can be any string — covers two. Stepping
        // the ramp per character traversed it at half rate and never drew its
        // last stops.
        var column = 0
        for cell in cells {
            let color = gradientColor(
                gradient, index: column, span: span, fallback: fallback, depth: depth)
            let cellWidth = max(1, cell.terminalWidth)
            row.append(String(cell), cells: cellWidth, ink: color)
            column += cellWidth
        }
    }

    /// Renders a position-marker style: a plain line with a single marker at
    /// the value, and NO fill — `─────●─────`. Marks *where* the value sits
    /// rather than a filled range.
    private static func renderMarkerStyle(
        fraction: Double,
        width: Int,
        lineChar: Character,
        markerChar: Character,
        lineColor: Color,
        markerColor: Color
    ) -> ClaimingRow {
        var row = ClaimingRow()
        guard width > 1 else {
            row.append(String(markerChar), cells: 1, ink: markerColor)
            return row
        }
        let position = Int((fraction * Double(width - 1)).rounded())
        if position > 0 {
            row.append(
                String(repeating: lineChar, count: position), cells: position, ink: lineColor)
        }
        // Its own claim, separate from the rail's: an opaque rail with a faded marker
        // must fade only the dot, and that is `.tint(…opacity(…))` on a `Gauge`.
        row.append(String(markerChar), cells: 1, ink: markerColor)
        let trailing = width - 1 - position
        if trailing > 0 {
            row.append(
                String(repeating: lineChar, count: trailing), cells: trailing, ink: lineColor)
        }
        return row
    }

    /// Renders a head-indicator style (filled track + head + empty track).
    ///
    /// The head is ALWAYS visible: at fraction 0 it sits on the first cell
    /// with no fill behind it, at 1 on the last cell with the fill all the
    /// way up — the same position quantisation as ``renderMarkerStyle``. A
    /// knob-style slider must never lose its grab handle at the ends.
    private static func renderHeadStyle(
        fraction: Double,
        width: Int,
        filledChar: Character,
        headChar: Character,
        emptyChar: Character,
        fillColor: Color,
        headColor: Color,
        backgroundColor: Color
    ) -> ClaimingRow {
        var row = ClaimingRow()
        guard width > 1 else {
            row.append(String(headChar), cells: 1, ink: headColor)
            return row
        }
        let position = Int((fraction * Double(width - 1)).rounded())

        if position > 0 {
            row.append(
                String(repeating: filledChar, count: position), cells: position, ink: fillColor)
        }
        // `.knob` — a `Slider`'s default — takes BOTH `fillColor` and `headColor`
        // from the accent, so `.tint(.red.opacity(0.5))` fades the lit rail and the
        // knob together. That is the shortest route from a public modifier to this
        // renderer, and it is what used to reach the emitter's assertion.
        row.append(String(headChar), cells: 1, ink: headColor)
        let trailing = width - 1 - position
        if trailing > 0 {
            row.append(
                String(repeating: emptyChar, count: trailing), cells: trailing, ink: backgroundColor)
        }
        return row
    }
}

// MARK: - What decides whether a track picture has changed

/// Everything about a track picture that, if it changed, means the terminal
/// is holding the wrong one. The value enters as `lit` — the boundary pixel —
/// so two fractions that land on the same pixel are the same picture and cost
/// nothing.
struct TrackImageSignature: Equatable {
    var config: TrackConfiguration
    var fillColor: Color
    var backgroundColor: Color
    var fillScaling: TrackGradientScaling
    var backgroundScaling: TrackGradientScaling
    var width: Int
    var height: Int
    var lit: Int
}

extension TrackImageSignature: ImageStoreSignature {
    /// The boundary pixel and the picture's size: each step of a slider being
    /// dragged is a bucket of its own.
    var storeBucket: [Int] { [lit, width, height] }
}
