//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// - Returns: An ANSI-styled string representing the track.
    static func render(
        fraction: Double,
        width: Int,
        style: TrackStyle,
        filledColor: Color,
        emptyColor: Color,
        accentColor: Color
    ) -> String {
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
                filledColor: filledColor, emptyColor: emptyColor)
        case .blockFine:
            return renderConfigured(
                fraction: fraction, width: width, config: .blockFine,
                filledColor: filledColor, emptyColor: emptyColor)
        case .shade:
            return renderConfigured(
                fraction: fraction, width: width, config: .shade,
                filledColor: filledColor, emptyColor: emptyColor)
        case .bar:
            return renderConfigured(
                fraction: fraction, width: width, config: .bar,
                filledColor: filledColor, emptyColor: emptyColor)
        case .braille:
            return renderConfigured(
                fraction: fraction, width: width, config: .braille,
                filledColor: filledColor, emptyColor: emptyColor)
        case .shadeRamp(let gradient):
            return renderConfigured(
                fraction: fraction, width: width, config: .shadeRamp(gradient: gradient),
                filledColor: filledColor, emptyColor: emptyColor)
        case .custom(let config):
            return renderConfigured(
                fraction: fraction, width: width, config: config,
                filledColor: filledColor, emptyColor: emptyColor)

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
                emptyColor: emptyColor
            )
        }
    }

    /// Piecewise-linear interpolation into gradient `stops` at `parameter`
    /// (0…1). Shared by every gradient consumer — the configured fill tracks,
    /// `.threeSegment`'s ``SegmentColoring/gradient(_:)``, and (via its own
    /// cyclic wrapper) the indeterminate sweep — so "a gradient" always means
    /// the same interpolation. Fewer than two stops yield `fallback`.
    static func gradientColor(stops: [Color], parameter: Double, fallback: Color) -> Color {
        guard stops.count >= 2 else { return fallback }
        let segments = Double(stops.count - 1)
        let scaled = max(0.0, min(segments, parameter * segments))
        let lowerIndex = min(Int(scaled), stops.count - 2)
        let mix = scaled - Double(lowerIndex)
        return Color.lerp(stops[lowerIndex], stops[lowerIndex + 1], phase: mix)
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
    /// character's cell width and the track permanently shrinks to a neat
    /// multiple of it (see ``renderCoarsePattern``).
    private static func renderConfigured(
        fraction: Double,
        width: Int,
        config: TrackConfiguration,
        filledColor: Color,
        emptyColor: Color
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
                paintsBackground: paintsBackground)
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
        let trackBackground: Color? = paintsBackground ? emptyColor : nil

        // Optional per-cell colour fade across the lit cells.
        func fillColour(at index: Int) -> Color {
            guard let gradient = config.fillGradient, litCellCount > 1 else {
                return filledColor
            }
            return gradientColor(
                stops: gradient,
                parameter: Double(index) / Double(litCellCount - 1),
                fallback: filledColor)
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
                background: trackBackground)
        }
        let emptyCount = width - litCellCount
        if emptyCount > 0 {
            if paintsBackground {
                // Spaces on the empty colour → a solid unfilled remainder.
                result += ANSIRenderer.colorize(
                    String(repeating: " ", count: emptyCount), foreground: emptyColor,
                    background: emptyColor)
            } else {
                // The unfilled pattern is anchored to the TRACK (cell j always
                // shows the same character), so the texture stays put while
                // the fill sweeps across it.
                var empty = ""
                for cell in litCellCount..<width {
                    empty.append(emptyChars[cell % emptyChars.count])
                }
                result += ANSIRenderer.colorize(empty, foreground: emptyColor)
            }
        }
        return result
    }

    // The coarse pattern mode: some fill/unfilled character is wider than
    // one cell, so the fill can only advance in steps of the widest
    // character's width (`quantum`), and the track PERMANENTLY shrinks to
    // the largest multiple of the quantum that fits — its width must not
    // vary with the fill:unfilled ratio. The sub-cell ramp is meaningless
    // at this resolution and is skipped. Mixed-width patterns that cannot
    // land exactly on a step boundary are padded with spaces.
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
        paintsBackground: Bool
    ) -> String {
        let effectiveWidth = (width / quantum) * quantum
        guard effectiveWidth > 0 else { return "" }
        let steps = effectiveWidth / quantum
        let litSteps = Int((fraction * Double(steps)).rounded())
        let targetCells = litSteps * quantum

        func fillColour(atCell cell: Int) -> Color {
            guard let gradient = config.fillGradient, targetCells > 1 else {
                return filledColor
            }
            return gradientColor(
                stops: gradient,
                parameter: Double(cell) / Double(targetCells - 1),
                fallback: filledColor)
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

        // The unfilled remainder: spaces on the empty colour for
        // `.background`, else the cyclic unfilled pattern truncated at its
        // own character boundaries and space-padded to the track edge.
        let remaining = effectiveWidth - targetCells
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
        emptyColor: Color
    ) -> String {
        let leadingWidth = leading.strippedLength
        let trailingWidth = trailing.strippedLength
        let middleWidth = max(1, middle.strippedLength)
        let filledCount = Int((fraction * Double(width)).rounded())

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
                coloring: coloring, filledColor: filledColor)
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
                coloring: coloring, filledColor: filledColor)
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
        coloring: SegmentColoring, filledColor: Color
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
                (leading + middleRun + trailing).stripped, stops: stops, fallback: filledColor)
        }
    }

    /// Colours `text` cell by cell across gradient `stops` (the whole string
    /// spans parameter 0…1). Used by `.threeSegment`'s gradient colouring.
    private static func gradientCells(_ text: String, stops: [Color], fallback: Color) -> String {
        let cells = Array(text)
        guard cells.count > 1 else {
            return ANSIRenderer.colorize(text, foreground: stops.first ?? fallback)
        }
        var result = ""
        for (index, cell) in cells.enumerated() {
            let color = gradientColor(
                stops: stops,
                parameter: Double(index) / Double(cells.count - 1),
                fallback: fallback)
            result += ANSIRenderer.colorize(String(cell), foreground: color)
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
