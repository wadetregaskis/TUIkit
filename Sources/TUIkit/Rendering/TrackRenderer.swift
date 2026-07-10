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
    /// purely data: the full-cell glyph, the (optional) sub-cell boundary ramp,
    /// how the empty region is drawn, and an optional fill gradient.
    private static func renderConfigured(
        fraction: Double,
        width: Int,
        config: TrackConfiguration,
        filledColor: Color,
        emptyColor: Color
    ) -> String {
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
        let paintsBackground: Bool
        if case .background = config.emptyStyle {
            paintsBackground = true
        } else {
            paintsBackground = false
        }
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
                String(config.fullGlyph), foreground: cellColour,
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
            switch config.emptyStyle {
            case .glyph(let glyph):
                result += ANSIRenderer.colorize(
                    String(repeating: glyph, count: emptyCount), foreground: emptyColor)
            case .background:
                // Spaces on the empty colour → a solid unfilled remainder.
                result += ANSIRenderer.colorize(
                    String(repeating: " ", count: emptyCount), foreground: emptyColor,
                    background: emptyColor)
            }
        }
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
        let filledCount = Int((fraction * Double(width)).rounded())

        var result = ""

        let trackCount = max(0, filledCount - 1)
        if trackCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: filledChar, count: trackCount),
                foreground: filledColor
            )
        }

        if filledCount > 0 && filledCount <= width {
            result += ANSIRenderer.colorize(String(headChar), foreground: headColor)
        }

        let emptyCount = width - max(filledCount, 0)
        if emptyCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: emptyChar, count: emptyCount),
                foreground: emptyColor
            )
        }

        return result
    }
}
