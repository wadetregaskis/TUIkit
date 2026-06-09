//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BorderRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Reusable building blocks for border rendering.
///
/// Each method produces a single rendered line (`String`) that callers
/// append to a `[String]` array for `FrameBuffer` construction.
/// This eliminates duplicated border-assembly code across Views and Modifiers.
///
/// Uses standard box-drawing characters (┌─┐│└─┘├─┤) with configurable
/// ``BorderStyle`` presets (line, rounded, doubleLine, heavy).
enum BorderRenderer {

    /// The total width consumed by left + right border characters (1 + 1 = 2).
    static let borderWidthOverhead = 2

    /// The breathing focus indicator character.
    static let focusIndicator: Character = "●"

    /// The width of the focus indicator prefix (indicator + space).
    static let focusIndicatorWidth = 2
}

// MARK: - Focus Indicator

extension BorderRenderer {
    /// Renders a pulsing focus indicator for inline focusable elements.
    ///
    /// Uses the same `●` character and color interpolation as Focus Sections,
    /// ensuring visual consistency across all focusable components.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the element is currently focused.
    ///   - pulsePhase: The current animation phase (0–1) from `context.pulsePhase`.
    ///   - palette: The active palette for color resolution.
    /// - Returns: A 2-character string: `"● "` (colored) when focused, `"  "` when not.
    static func focusIndicatorPrefix(
        isFocused: Bool,
        pulsePhase: Double,
        palette: any Palette
    ) -> String {
        guard isFocused else {
            return "  "  // 2 spaces for alignment (matches focusIndicatorWidth)
        }

        let accentColor = palette.accent
        let dimColor = accentColor.opacity(ViewConstants.focusBorderDim)
        let interpolatedColor = Color.lerp(dimColor, accentColor, phase: pulsePhase)

        return ANSIRenderer.colorize(String(focusIndicator), foreground: interpolatedColor) + " "
    }
}

// MARK: - Border Rendering

extension BorderRenderer {
    /// Renders a plain top border line.
    ///
    ///     ┌──────────────┐
    ///
    /// - Parameters:
    ///   - style: The border style providing corner and edge characters.
    ///   - innerWidth: The width of the content area (excluding borders).
    ///   - color: The foreground color for the border.
    ///   - focusIndicatorColor: If non-nil, renders a ● after the top-left corner
    ///     in this color. Used for the breathing focus section indicator.
    /// - Returns: A colorized top border string.
    static func standardTopBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color,
        focusIndicatorColor: Color? = nil
    ) -> String {
        if let indicatorColor = focusIndicatorColor, innerWidth > 1 {
            // ╭●──────────────╮
            let leftCorner = ANSIRenderer.colorize(String(style.topLeft), foreground: color)
            let indicator = ANSIRenderer.colorize(String(focusIndicator), foreground: indicatorColor)
            let remainingWidth = innerWidth - 1  // -1 for the ● character
            let rest = ANSIRenderer.colorize(
                String(repeating: style.horizontal, count: remainingWidth)
                    + String(style.topRight),
                foreground: color
            )
            return leftCorner + indicator + rest
        }

        let line =
            String(style.topLeft)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.topRight)
        return ANSIRenderer.colorize(line, foreground: color)
    }

    /// Renders a top border line with an inline title.
    ///
    ///     ┌─ Title ──────┐   (without focus indicator)
    ///     ┌● Title ──────┐   (with focus indicator)
    ///
    /// - Parameters:
    ///   - style: The border style.
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    ///   - title: The title text.
    ///   - titleColor: The title foreground color.
    ///   - focusIndicatorColor: If non-nil, renders a ● between the corner
    ///     and the title. Used for the breathing focus section indicator.
    /// - Returns: A colorized top border string with embedded title.
    static func standardTopBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color,
        title: String,
        titleColor: Color,
        focusIndicatorColor: Color? = nil
    ) -> String {
        // The decoration after the corner (─ or ●) occupies one inner cell
        // and the title display adds two spaces of padding. Truncate the title
        // so the whole top border fits exactly within `innerWidth`.
        let usedLeftWidth = 1
        let maxTitleWidth = max(0, innerWidth - usedLeftWidth - 2)
        let fittedTitle =
            title.strippedLength > maxTitleWidth
            ? title.ansiAwarePrefix(visibleCount: maxTitleWidth)
            : title
        let titleStyled = ANSIRenderer.colorize(" \(fittedTitle) ", foreground: titleColor, bold: true)

        let leftPart: String
        if let indicatorColor = focusIndicatorColor {
            // ╭● Title
            let corner = ANSIRenderer.colorize(String(style.topLeft), foreground: color)
            let indicator = ANSIRenderer.colorize(String(focusIndicator), foreground: indicatorColor)
            leftPart = corner + indicator
        } else {
            // ╭─ Title
            leftPart = ANSIRenderer.colorize(
                String(style.topLeft) + String(style.horizontal),
                foreground: color
            )
        }

        let rightPartLength = max(0, innerWidth - usedLeftWidth - fittedTitle.strippedLength - 2)
        let rightPart = ANSIRenderer.colorize(
            String(repeating: style.horizontal, count: rightPartLength) + String(style.topRight),
            foreground: color
        )
        return leftPart + titleStyled + rightPart
    }

    /// Renders a plain bottom border line.
    ///
    ///     └──────────────┘
    ///
    /// - Parameters:
    ///   - style: The border style.
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    /// - Returns: A colorized bottom border string.
    static func standardBottomBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color
    ) -> String {
        let line =
            String(style.bottomLeft)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.bottomRight)
        return ANSIRenderer.colorize(line, foreground: color)
    }

    /// Renders a horizontal divider with T-junctions.
    ///
    ///     ├──────────────┤
    ///
    /// - Parameters:
    ///   - style: The border style (uses leftT, horizontal, rightT).
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    /// - Returns: A colorized divider string.
    static func standardDivider(
        style: BorderStyle,
        innerWidth: Int,
        color: Color
    ) -> String {
        let line =
            String(style.leftT)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.rightT)
        return ANSIRenderer.colorize(line, foreground: color)
    }

    /// Wraps a single content line with vertical side borders.
    ///
    ///     │ padded content │
    ///
    /// If `backgroundColor` is provided, `applyPersistentBackground` is used
    /// so the background survives inner ANSI resets.
    ///
    /// - Parameters:
    ///   - content: The content string (will be padded to `innerWidth`).
    ///   - innerWidth: The target content width.
    ///   - style: The border style (for the vertical character).
    ///   - color: The border color.
    ///   - backgroundColor: Optional background applied to the content area.
    /// - Returns: The bordered content line.
    static func standardContentLine(
        content: String,
        innerWidth: Int,
        style: BorderStyle,
        color: Color,
        backgroundColor: Color? = nil
    ) -> String {
        contentLine(
            content: content,
            innerWidth: innerWidth,
            vertical: ANSIRenderer.colorize(String(style.vertical), foreground: color),
            backgroundColor: backgroundColor
        )
    }

    /// Builds a run of bordered content lines that share one border style and
    /// colour (a container's body or footer).
    ///
    /// Computes the coloured vertical border ONCE for the whole run instead of
    /// per line: the bar is identical for every line of a border, but the
    /// per-line ``standardContentLine`` re-ran `colorize(String(vertical))` —
    /// a String allocation — for each one. A container body of N lines paid N
    /// of those (plus N for the right bar's reuse) every frame; this pays one.
    ///
    /// - Parameters:
    ///   - contents: The content strings, one per line.
    ///   - innerWidth: The target content width (each line is fitted to it).
    ///   - style: The border style (for the vertical character).
    ///   - color: The border colour.
    ///   - backgroundColor: Optional background applied to the content area.
    /// - Returns: The bordered content lines, in order.
    static func standardContentLines(
        contents: [String],
        innerWidth: Int,
        style: BorderStyle,
        color: Color,
        backgroundColor: Color? = nil
    ) -> [String] {
        let vertical = ANSIRenderer.colorize(String(style.vertical), foreground: color)
        return contents.map {
            contentLine(
                content: $0,
                innerWidth: innerWidth,
                vertical: vertical,
                backgroundColor: backgroundColor
            )
        }
    }

    /// Fits one content string into a bordered line, given the already-coloured
    /// vertical bar. Measures the content's visible width ONCE and reuses it for
    /// both the truncate-vs-pad decision and the padding amount (the old code
    /// measured it twice: once for the width check, once inside
    /// `padToVisibleWidth`). For an already-styled line that second measure took
    /// the allocating ANSI path, so the dedup removes real churn per line.
    private static func contentLine(
        content: String,
        innerWidth: Int,
        vertical: String,
        backgroundColor: Color?
    ) -> String {
        // Fit the content to exactly `innerWidth`: truncate if it is wider
        // (ANSI-aware) so it cannot displace the right border, pad if narrower.
        let width = content.strippedLength
        let fittedLine: String
        if width > innerWidth {
            fittedLine = content.ansiAwarePrefix(visibleCount: innerWidth)
        } else if width == innerWidth {
            fittedLine = content
        } else {
            fittedLine = content + String(repeating: " ", count: innerWidth - width)
        }
        let styledContent = fittedLine.withPersistentBackground(backgroundColor)
        return vertical + styledContent + ANSIRenderer.reset + vertical
    }
}
