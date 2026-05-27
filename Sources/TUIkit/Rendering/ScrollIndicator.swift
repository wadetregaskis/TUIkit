//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollIndicator.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Scroll Direction

/// The direction of a scroll indicator arrow.
enum ScrollIndicatorDirection {
    case up, down
}

// MARK: - Scroll Indicator Rendering

/// Renders a centered scroll indicator line with an arrow, a row count and label.
///
/// Used by `_ListCore` and `_TableCore` to show "N more above" / "N more below"
/// indicators when content extends beyond the visible viewport.
///
/// - Parameters:
///   - direction: Whether the indicator points up or down.
///   - count: The number of rows hidden in that direction. Omitted from the
///     label when zero (in normal use the caller only renders the indicator
///     when at least one row is hidden).
///   - width: The total width available for the indicator line.
///   - palette: The color palette for styling.
/// - Returns: A styled string with a centered scroll indicator.
@MainActor
func renderScrollIndicator(
    direction: ScrollIndicatorDirection,
    count: Int,
    width: Int,
    palette: any Palette
) -> String {
    let arrow = direction == .up ? "▲" : "▼"
    let countPrefix = count > 0 ? "\(count) " : ""
    let label = direction == .up
        ? " \(countPrefix)more above "
        : " \(countPrefix)more below "

    let styledArrow = ANSIRenderer.colorize(arrow, foreground: palette.foregroundTertiary)
    let styledLabel = ANSIRenderer.colorize(label, foreground: palette.foregroundTertiary)

    let indicatorWidth = 1 + label.count
    let padding = max(0, (width - indicatorWidth) / 2)

    return String(repeating: " ", count: padding) + styledArrow + styledLabel
}
