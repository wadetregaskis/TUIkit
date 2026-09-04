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
///     filledColor: palette.foregroundSecondary,
///     emptyColor: palette.foregroundTertiary,
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
    ///   - filledColor: The color for filled portions.
    ///   - emptyColor: The color for empty portions.
    ///   - accentColor: The color for accent elements (e.g., dot head).
    ///   - gradientScaling: What a fill gradient is measured across — the whole
    ///     bar (the default) or only the lit part. See ``TrackGradientScaling``.
    ///   - palette: The palette the style's own colours are resolved against.
    ///     The three colours above arrive resolved; a style read from the
    ///     environment does not, and a palette role has no channels to emit.
    /// - Returns: An ANSI-styled string representing the track.
    static func render(
        fraction: Double,
        width: Int,
        style: TrackStyle,
        filledColor: Color,
        emptyColor: Color,
        accentColor: Color,
        gradientScaling: TrackGradientScaling = .track,
        palette: any Palette
    ) -> String {
        let style = style.resolvingColours(with: palette)
        // Read once per render, not once per cell. A gradient can only be
        // quantised as a ramp if it knows what the terminal will do to it; at
        // truecolor every helper below falls through to the plain interpolation.
        let depth = ColorDepth.current
        guard width > 0 else { return "" }

        // Clamp fraction to [0, 1] to prevent track overflow
        let fraction = min(1.0, max(0.0, fraction))

        switch style {
        // The "fill" family — a run of full cells, an optional fractional
        // boundary cell, then the unfilled remainder — is one parameterized
        // renderer driven by a `TrackConfiguration`. The named cases are just
        // presets; `.custom` carries a caller-supplied recipe.
        case .block:
            return renderConfigured(
                fraction: fraction, width: width, config: .block,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .blockFine:
            return renderConfigured(
                fraction: fraction, width: width, config: .blockFine,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .shade:
            return renderConfigured(
                fraction: fraction, width: width, config: .shade,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .bar:
            return renderConfigured(
                fraction: fraction, width: width, config: .bar,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .braille:
            return renderConfigured(
                fraction: fraction, width: width, config: .braille,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .shadeRamp(let gradient):
            return renderConfigured(
                fraction: fraction, width: width, config: .shadeRamp(gradient: gradient),
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)
        case .custom(let config):
            return renderConfigured(
                fraction: fraction, width: width, config: config,
                filledColor: filledColor, emptyColor: emptyColor,
                gradientScaling: gradientScaling, depth: depth)

        // The head / marker / segment families are structurally distinct
        // (single indicator, no fractional fill ramp) and keep their own paths.
        case .dot:
            return renderHeadStyle(
                fraction: fraction,
                width: width,
                filledChar: "▬",
                headChar: "●",
                emptyChar: "─",
                filledColor: filledColor,
                headColor: accentColor,
                emptyColor: emptyColor
            )
        case .knob:
            return renderHeadStyle(
                fraction: fraction,
                width: width,
                filledChar: "━",
                headChar: "●",
                emptyChar: "─",
                filledColor: accentColor,
                headColor: accentColor,
                emptyColor: emptyColor
            )
        case .marker:
            return renderMarkerStyle(
                fraction: fraction,
                width: width,
                lineChar: "─",
                markerChar: "●",
                lineColor: emptyColor,
                markerColor: accentColor
            )
        case .threeSegment(let leading, let middle, let trailing, let emptyFill, let coloring):
            return renderThreeSegmentStyle(
                fraction: fraction,
                width: width,
                leading: leading,
                middle: middle,
                trailing: trailing,
                emptyFill: emptyFill,
                coloring: coloring,
                filledColor: filledColor,
                emptyColor: emptyColor,
                gradientScaling: gradientScaling,
                depth: depth
            )
        }
    }

    /// The colour `gradient` shows at `parameter` (0…1). Shared by every
    /// gradient consumer — the configured fill tracks, `.threeSegment`'s
    /// ``SegmentColoring/gradient(_:)``, and (via its own cyclic wrapper) the
    /// indeterminate sweep — so "a gradient" always means the same
    /// interpolation. Fewer than two stops yield `fallback`.
    static func gradientColor(_ gradient: Gradient, parameter: Double, fallback: Color) -> Color {
        // ONE stop is a solid colour, not a broken gradient: the editor can
        // collapse a ramp to a single stop, and what that has to mean
        // everywhere downstream is "this colour". Only an EMPTY gradient has
        // nothing to say, and that is what the fallback is for.
        guard !gradient.stops.isEmpty else { return fallback }
        return gradient.color(at: parameter)
    }

    /// The colour a gradient shows at cell `index` of a `span`-cell ramp.
    ///
    /// Not `gradientColor(parameter:)` per cell, because a per-cell nearest
    /// match has no memory of its neighbours and a gradient's smoothness is a
    /// property of the SEQUENCE — see ``Color/quantisedRamp(stops:count:depth:)``,
    /// which is where the whole ramp is quantised at once and repaired into a
    /// monotone one. At truecolor depth it returns the same interpolation this
    /// always produced, so no caller has to branch on the terminal.
    ///
    /// The ramp is memoised on `(gradient, span, depth)`, so asking cell by
    /// cell costs one dictionary hit each after the first.
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
        filledColor: Color,
        emptyColor: Color,
        gradientScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> String {
        let fillChars = Array(config.fill.isEmpty ? "█" : config.fill)
        let emptyChars: [Character]
        let paintsBackground: Bool
        switch config.emptyStyle {
        case .pattern(let pattern):
            emptyChars = Array(pattern.isEmpty ? " " : pattern)
            paintsBackground = false
        case .background:
            emptyChars = []
            paintsBackground = true
        }

        // Any multi-cell character forces the coarse quantized mode. (The
        // solid `.background` unfilled region is spaces, so only a patterned
        // unfill constrains the quantum.)
        let quantum = max(
            fillChars.map(\.terminalWidth).max() ?? 1,
            emptyChars.map(\.terminalWidth).max() ?? 1)
        if quantum > 1 {
            return renderCoarsePattern(
                fraction: fraction, width: width, quantum: quantum,
                fillChars: fillChars, emptyChars: emptyChars,
                config: config, filledColor: filledColor, emptyColor: emptyColor,
                paintsBackground: paintsBackground, gradientScaling: gradientScaling,
                depth: depth)
        }

        // A ramp of n glyphs gives n+1 sub-cell steps; no ramp means whole-cell
        // quantization (stepsPerCell == 1, so this reduces to a plain fill).
        let ramp = config.partialRamp
        let stepsPerCell = (ramp?.count ?? 0) + 1
        let totalSteps = Int((fraction * Double(width) * Double(stepsPerCell)).rounded())
        let fullCells = totalSteps / stepsPerCell
        let partialStep = ramp == nil ? 0 : totalSteps % stepsPerCell
        let fullCount = min(fullCells, width)
        let hasPartial = ramp != nil && partialStep > 0 && fullCells < width
        let litCellCount = min(width, fullCount + (hasPartial ? 1 : 0))

        // `.background` paints backgrounds across the whole track. The empty
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
        let emptyColor = config.emptyColor ?? emptyColor

        // Optional per-cell colour fade. What it is measured across is the
        // caller's choice (``TrackGradientScaling``): the whole bar, so a
        // colour always marks the same value, or the lit part, so the ramp
        // follows the fill. Compressing into the lit part is what this always
        // did, and it makes a gradient meant as a SCALE ("red past 80%") lie —
        // at 10% the bar's one lit cell is the last colour.
        let gradientSpan = gradientScaling == .track ? width : litCellCount
        func fillColour(at index: Int) -> Color {
            guard let gradient = config.fillGradient, gradientSpan > 1 else {
                return filledColor
            }
            return gradientColor(
                gradient, index: index, span: gradientSpan,
                fallback: filledColor, depth: depth)
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
        let emptyRegionStart = fullCount
        let emptySpan = gradientScaling == .track ? width : width - emptyRegionStart
        func emptyColour(at cell: Int) -> Color {
            guard let gradient = config.emptyGradient, emptySpan > 1 else { return emptyColor }
            return gradientColor(
                gradient, index: gradientScaling == .track ? cell : cell - emptyRegionStart,
                span: emptySpan, fallback: emptyColor, depth: depth)
        }

        var result = ""
        for index in 0..<fullCount {
            let cellColour = fillColour(at: index)
            result += ANSIRenderer.colorize(
                String(fillChars[index % fillChars.count]), foreground: cellColour,
                background: paintsBackground ? cellColour : nil)
        }
        if hasPartial, let ramp {
            // The boundary cell is genuinely part-empty: the glyph covers the
            // filled fraction and the empty colour correctly shows behind the
            // rest of the cell.
            result += ANSIRenderer.colorize(
                String(ramp[partialStep - 1]), foreground: fillColour(at: fullCount),
                background: paintsBackground ? emptyColour(at: fullCount) : nil)
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
            if config.emptyGradient != nil, emptySpan > 1 {
                for cell in litCellCount..<width {
                    let colour = emptyColour(at: cell)
                    result += ANSIRenderer.colorize(
                        paintsBackground ? " " : String(emptyChars[cell % emptyChars.count]),
                        foreground: colour,
                        background: paintsBackground ? colour : nil)
                }
            } else if paintsBackground {
                // One run, one escape: a flat unfilled remainder is what almost
                // every bar draws, and it must not cost a colour change a cell.
                result += ANSIRenderer.colorize(
                    String(repeating: " ", count: emptyCount), foreground: emptyColor,
                    background: emptyColor)
            } else {
                result += ANSIRenderer.colorize(emptyGlyphs(), foreground: emptyColor)
            }
        }
        return result
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
        filledColor: Color,
        emptyColor: Color,
        paintsBackground: Bool,
        gradientScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> String {
        // The style's own unfilled colour, if it named one — see the fine path.
        let emptyColor = config.emptyColor ?? emptyColor
        let effectiveWidth = (width / quantum) * quantum
        guard effectiveWidth > 0 else { return "" }
        let steps = effectiveWidth / quantum

        // With a ramp of n glyphs each block has n+1 sub-steps — the same
        // arithmetic the fine path applies per cell, at block granularity.
        // Without one this reduces to whole-block quantization (the previous
        // behaviour exactly).
        let ramp = config.partialRamp
        let stepsPerBlock = (ramp?.count ?? 0) + 1
        let totalSteps = Int((fraction * Double(steps) * Double(stepsPerBlock)).rounded())
        let litSteps = min(totalSteps / stepsPerBlock, steps)
        let partialStep = ramp == nil ? 0 : totalSteps % stepsPerBlock
        let hasPartial = ramp != nil && partialStep > 0 && totalSteps / stepsPerBlock < steps
        let targetCells = litSteps * quantum

        // As in `renderConfigured`: the ramp spans the bar or the lit part.
        let gradientSpan = gradientScaling == .track ? steps * quantum : targetCells
        func fillColour(atCell cell: Int) -> Color {
            guard let gradient = config.fillGradient, gradientSpan > 1 else {
                return filledColor
            }
            return gradientColor(
                gradient, index: cell, span: gradientSpan,
                fallback: filledColor, depth: depth)
        }

        // The fill: walk the cyclic pattern up to the step boundary.
        var result = ""
        var cell = 0
        var index = 0
        while cell < targetCells {
            let character = fillChars[index % fillChars.count]
            let charWidth = max(1, character.terminalWidth)
            guard cell + charWidth <= targetCells else { break }
            let colour = fillColour(atCell: cell)
            result += ANSIRenderer.colorize(
                String(character), foreground: colour,
                background: paintsBackground ? colour : nil)
            cell += charWidth
            index += 1
        }
        if cell < targetCells {
            // A mixed-width pattern that can't land on the boundary: pad the
            // shortfall so the unfilled region still starts on its cell.
            result += ANSIRenderer.colorize(
                String(repeating: " ", count: targetCells - cell),
                foreground: emptyColor,
                background: paintsBackground ? emptyColor : nil)
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
            result += ANSIRenderer.colorize(
                block, foreground: rampColour,
                background: paintsBackground ? emptyColor : nil)
        }

        // The unfilled remainder: spaces on the empty colour for
        // `.background`, else the cyclic unfilled pattern truncated at its
        // own character boundaries and space-padded to the track edge.
        let remaining = effectiveWidth - targetCells - rampCells
        guard remaining > 0 else { return result }
        if paintsBackground {
            result += ANSIRenderer.colorize(
                String(repeating: " ", count: remaining), foreground: emptyColor,
                background: emptyColor)
            return result
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
        result += ANSIRenderer.colorize(empty, foreground: emptyColor)
        return result
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
        emptyFill: String,
        coloring: SegmentColoring,
        filledColor: Color,
        emptyColor: Color,
        gradientScaling: TrackGradientScaling,
        depth: ColorDepth
    ) -> String {
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
        let gradientSpan = gradientScaling == .track ? width : filledCount

        var result = ""

        if filledCount <= 0 {
            // Nothing lit at all.
        } else if filledCount < leadingWidth + trailingWidth {
            // Not enough room for both endpoints; render whichever fits
            // from the leading edge (per-segment colouring uses the leading
            // colour for the truncated composite).
            let truncated = (leading + trailing).ansiAwarePrefix(visibleCount: filledCount)
            result += renderLitRegion(
                leading: truncated, middleRun: "", trailing: "",
                coloring: coloring, filledColor: filledColor, gradientSpan: gradientSpan,
                depth: depth)
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
            result += renderLitRegion(
                leading: leading, middleRun: middleRun, trailing: trailing,
                coloring: coloring, filledColor: filledColor, gradientSpan: gradientSpan,
                depth: depth)
        }

        let emptyCellCount = max(0, width - filledCount)
        if emptyCellCount > 0 {
            let emptyFillWidth = max(1, emptyFill.strippedLength)
            let emptyReps = emptyCellCount / emptyFillWidth
            let emptyRemainder = emptyCellCount - emptyReps * emptyFillWidth
            var empty = ""
            if emptyReps > 0 {
                empty += String(repeating: emptyFill, count: emptyReps)
            }
            if emptyRemainder > 0 {
                empty += emptyFill.ansiAwarePrefix(visibleCount: emptyRemainder)
            }
            result += ANSIRenderer.colorize(empty, foreground: emptyColor)
        }
        return result
    }

    /// Colours the assembled lit region of a `.threeSegment` track.
    ///
    /// With `.automatic` / `.solid` / `.perSegment` each part is emitted
    /// as-is, so callers can pass already-styled strings (ANSI codes
    /// embedded); `.gradient` re-colours cell by cell and expects plain text.
    private static func renderLitRegion(
        leading: String, middleRun: String, trailing: String,
        coloring: SegmentColoring, filledColor: Color, gradientSpan: Int, depth: ColorDepth
    ) -> String {
        switch coloring {
        case .automatic:
            return ANSIRenderer.colorize(leading + middleRun + trailing, foreground: filledColor)
        case .solid(let color):
            return ANSIRenderer.colorize(leading + middleRun + trailing, foreground: color)
        case .perSegment(let leadingColor, let middleColor, let trailingColor):
            var result = ANSIRenderer.colorize(leading, foreground: leadingColor)
            if !middleRun.isEmpty {
                result += ANSIRenderer.colorize(middleRun, foreground: middleColor)
            }
            if !trailing.isEmpty {
                result += ANSIRenderer.colorize(trailing, foreground: trailingColor)
            }
            return result
        case .gradient(let stops):
            return gradientCells(
                (leading + middleRun + trailing).stripped, gradient: stops, fallback: filledColor,
                span: gradientSpan, depth: depth)
        }
    }

    /// Colours `text` cell by cell across gradient `stops`.
    ///
    /// `span` is how many cells the gradient is measured across — the whole
    /// track, or just the lit part (see ``TrackGradientScaling``). The text may
    /// be shorter than the span, in which case it uses the first part of the
    /// ramp and the rest is simply not reached; that is what makes a gradient
    /// read as a scale rather than as a fade.
    private static func gradientCells(
        _ text: String, gradient: Gradient, fallback: Color, span: Int, depth: ColorDepth
    ) -> String {
        let cells = Array(text)
        guard cells.count > 1, span > 1 else {
            return ANSIRenderer.colorize(text, foreground: gradient.stops.first?.color ?? fallback)
        }
        var result = ""
        // Indexed by the CELL column, not the character: `span` counts cells,
        // and a wide glyph — a segment can be any string — covers two. Stepping
        // the ramp per character traversed it at half rate and never drew its
        // last stops.
        var column = 0
        for cell in cells {
            let color = gradientColor(
                gradient, index: column, span: span, fallback: fallback, depth: depth)
            result += ANSIRenderer.colorize(String(cell), foreground: color)
            column += max(1, cell.terminalWidth)
        }
        return result
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
    ) -> String {
        guard width > 1 else {
            return ANSIRenderer.colorize(String(markerChar), foreground: markerColor)
        }
        let position = Int((fraction * Double(width - 1)).rounded())
        var result = ""
        if position > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: lineChar, count: position), foreground: lineColor)
        }
        result += ANSIRenderer.colorize(String(markerChar), foreground: markerColor)
        let trailing = width - 1 - position
        if trailing > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: lineChar, count: trailing), foreground: lineColor)
        }
        return result
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
        filledColor: Color,
        headColor: Color,
        emptyColor: Color
    ) -> String {
        guard width > 1 else {
            return ANSIRenderer.colorize(String(headChar), foreground: headColor)
        }
        let position = Int((fraction * Double(width - 1)).rounded())

        var result = ""
        if position > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: filledChar, count: position),
                foreground: filledColor
            )
        }
        result += ANSIRenderer.colorize(String(headChar), foreground: headColor)
        let trailing = width - 1 - position
        if trailing > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: emptyChar, count: trailing),
                foreground: emptyColor
            )
        }
        return result
    }
}
