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
        case .block:
            return renderSimpleStyle(
                fraction: fraction,
                width: width,
                filledChar: "█",
                emptyChar: "░",
                filledColor: filledColor,
                emptyColor: emptyColor
            )
        case .blockFine:
            return renderBlockFineStyle(
                fraction: fraction,
                width: width,
                filledColor: filledColor,
                emptyColor: emptyColor
            )
        case .shade:
            return renderSimpleStyle(
                fraction: fraction,
                width: width,
                filledChar: "▓",
                emptyChar: "░",
                filledColor: filledColor,
                emptyColor: emptyColor
            )
        case .bar:
            return renderSimpleStyle(
                fraction: fraction,
                width: width,
                filledChar: "▌",
                emptyChar: "─",
                filledColor: filledColor,
                emptyColor: emptyColor
            )
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
        case .braille:
            return renderBrailleStyle(
                fraction: fraction,
                width: width,
                filledColor: filledColor,
                emptyColor: emptyColor
            )
        case .shadeRamp(let gradient):
            return renderShadeRampStyle(
                fraction: fraction,
                width: width,
                filledColor: filledColor,
                emptyColor: emptyColor,
                gradient: gradient
            )
        case .threeSegment(let leading, let middle, let trailing, let emptyFill):
            return renderThreeSegmentStyle(
                fraction: fraction,
                width: width,
                leading: leading,
                middle: middle,
                trailing: trailing,
                emptyFill: emptyFill,
                filledColor: filledColor,
                emptyColor: emptyColor
            )
        }
    }
}

// MARK: - Private Rendering Methods

extension TrackRenderer {
    /// Renders a simple two-character style (filled + empty, no head indicator).
    private static func renderSimpleStyle(
        fraction: Double,
        width: Int,
        filledChar: Character,
        emptyChar: Character,
        filledColor: Color,
        emptyColor: Color
    ) -> String {
        let filledCount = Int((fraction * Double(width)).rounded())
        let emptyCount = width - filledCount

        var result = ""
        if filledCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: filledChar, count: filledCount),
                foreground: filledColor
            )
        }
        if emptyCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: emptyChar, count: emptyCount),
                foreground: emptyColor
            )
        }
        return result
    }

    /// Renders the `.blockFine` style with sub-character fractional precision.
    private static func renderBlockFineStyle(
        fraction: Double,
        width: Int,
        filledColor: Color,
        emptyColor: Color
    ) -> String {
        let totalEighths = fraction * Double(width) * 8.0
        let fullCells = Int(totalEighths) / 8
        let remainderEighths = Int(totalEighths) % 8

        let fractionalBlocks: [Character] = ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]

        var result = ""

        if fullCells > 0 {
            let filledBar = String(repeating: "█", count: fullCells)
            result += ANSIRenderer.colorize(filledBar, foreground: filledColor)
        }

        let cellsUsed: Int
        if remainderEighths > 0 && fullCells < width {
            let partialChar = fractionalBlocks[remainderEighths - 1]
            result += ANSIRenderer.colorize(String(partialChar), foreground: filledColor)
            cellsUsed = fullCells + 1
        } else {
            cellsUsed = fullCells
        }

        let emptyCount = width - cellsUsed
        if emptyCount > 0 {
            let emptyBar = String(repeating: "░", count: emptyCount)
            result += ANSIRenderer.colorize(emptyBar, foreground: emptyColor)
        }

        return result
    }

    /// Renders the `.braille` 8-step fill style.
    ///
    /// Each filled cell carries 8 steps of sub-cell precision via the
    /// braille dot-density ramp `⣀⣄⣤⣦⣶⣷⣿`, so the boundary cell visually
    /// communicates the fractional progress without needing
    /// sub-character-width support from the terminal.
    private static func renderBrailleStyle(
        fraction: Double,
        width: Int,
        filledColor: Color,
        emptyColor: Color
    ) -> String {
        let ramp: [Character] = ["⣀", "⣄", "⣤", "⣦", "⣶", "⣷", "⣿"]
        let totalSteps = Int((fraction * Double(width) * Double(ramp.count + 1)).rounded())
        let fullCells = totalSteps / (ramp.count + 1)
        let partialStep = totalSteps % (ramp.count + 1)

        var result = ""
        if fullCells > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: "⣿", count: fullCells),
                foreground: filledColor
            )
        }
        var cellsUsed = fullCells
        if partialStep > 0 && fullCells < width {
            let ch = ramp[partialStep - 1]
            result += ANSIRenderer.colorize(String(ch), foreground: filledColor)
            cellsUsed += 1
        }
        let emptyCount = width - cellsUsed
        if emptyCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: "⠀", count: emptyCount),
                foreground: emptyColor
            )
        }
        return result
    }

    /// Renders the `.shadeRamp` style.
    ///
    /// The four shade glyphs `░ ▒ ▓ █` give each cell two fractional
    /// sub-steps inside its own footprint, which softens the appearance
    /// of the boundary. When `gradient` is non-nil the filled portion
    /// fades between the stops cell by cell — a richer look than the
    /// flat `filledColor` of the other styles.
    private static func renderShadeRampStyle(
        fraction: Double,
        width: Int,
        filledColor: Color,
        emptyColor: Color,
        gradient: [Color]?
    ) -> String {
        let ramp: [Character] = ["░", "▒", "▓", "█"]
        let totalSteps = Int((fraction * Double(width) * Double(ramp.count)).rounded())
        let fullCells = totalSteps / ramp.count
        let partialStep = totalSteps % ramp.count

        var result = ""
        let litCellCount = min(width, fullCells + (partialStep > 0 ? 1 : 0))

        func colour(at index: Int) -> Color {
            guard let gradient, gradient.count >= 2, litCellCount > 1 else {
                return filledColor
            }
            let parameter = Double(index) / Double(litCellCount - 1)
            let segments = Double(gradient.count - 1)
            let scaled = max(0.0, min(segments, parameter * segments))
            let lowerIndex = min(Int(scaled), gradient.count - 2)
            let mix = scaled - Double(lowerIndex)
            return Color.lerp(gradient[lowerIndex], gradient[lowerIndex + 1], phase: mix)
        }

        for cellIndex in 0..<fullCells {
            result += ANSIRenderer.colorize(String(ramp.last!), foreground: colour(at: cellIndex))
        }
        if partialStep > 0 && fullCells < width {
            let ch = ramp[partialStep - 1]
            result += ANSIRenderer.colorize(String(ch), foreground: colour(at: fullCells))
        }
        let emptyCount = width - litCellCount
        if emptyCount > 0 {
            result += ANSIRenderer.colorize(
                String(repeating: "·", count: emptyCount),
                foreground: emptyColor
            )
        }
        return result
    }

    /// Renders the `.threeSegment` style.
    ///
    /// `[leading][middle × N][trailing]` covers the filled region, with
    /// `middle` repeated to span any gap. Each segment is coloured /
    /// emitted as-is, so callers can pass already-styled strings (ANSI
    /// codes embedded) and they'll render correctly.
    private static func renderThreeSegmentStyle(
        fraction: Double,
        width: Int,
        leading: String,
        middle: String,
        trailing: String,
        emptyFill: String,
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
            // from the leading edge.
            let truncated = leading + trailing
            result += ANSIRenderer.colorize(
                truncated.ansiAwarePrefix(visibleCount: filledCount),
                foreground: filledColor
            )
        } else {
            // Endpoints fit. Repeat `middle` to fill the gap, plus a
            // partial trailing slice if needed.
            let gap = filledCount - leadingWidth - trailingWidth
            let reps = gap / middleWidth
            let remainder = gap - reps * middleWidth
            var lit = leading
            if reps > 0 {
                lit += String(repeating: middle, count: reps)
            }
            if remainder > 0 {
                lit += middle.ansiAwarePrefix(visibleCount: remainder)
            }
            lit += trailing
            result += ANSIRenderer.colorize(lit, foreground: filledColor)
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
