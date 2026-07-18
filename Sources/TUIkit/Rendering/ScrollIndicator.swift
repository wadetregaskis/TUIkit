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

/// What a scroll indicator's count denominates — the label says which, so
/// "42 more rows below" (a `List`'s whole items) and "~200M more lines
/// below" (a `ScrollView`'s terminal lines) can't be conflated. Required at
/// every call site: a new caller must decide what it is actually counting.
enum ScrollIndicatorUnit {
    /// Whole rows/items — `List`, `Table`, menus. Exact counts.
    case rows
    /// Terminal lines — `ScrollView`, whose scroll space is line-based.
    case lines

    /// The label word for `count` of this unit.
    func word(for count: Int) -> String {
        switch self {
        case .rows: return count == 1 ? "row" : "rows"
        case .lines: return count == 1 ? "line" : "lines"
        }
    }
}

// MARK: - Scroll Indicator Rendering

/// Formats an estimated count compactly — "~897", "~5.4K", "~200M" — so an
/// indicator built on estimated geometry reads as approximate instead of
/// asserting false precision. (A 100M-row log's "200000897 more below" at
/// the top and "200000903 more above" at the bottom are the same estimate,
/// differing only by its refinement between the two frames; printing every
/// digit implies an exactness the number does not have.)
///
/// One decimal below ten of a unit ("~5.4K"), whole numbers above ("~54K",
/// "~200M"); a value that rounds up to a unit's ceiling promotes to the next
/// ("~1M", never "~1000K").
func approximateCountLabel(_ count: Int) -> String {
    guard count >= 1000 else { return "~\(count)" }
    let units: [(divisor: Double, suffix: String)] = [
        (1e3, "K"), (1e6, "M"), (1e9, "B"), (1e12, "T"),
    ]
    var index = units.lastIndex { Double(count) >= $0.divisor } ?? 0
    if index + 1 < units.count, (Double(count) / units[index].divisor).rounded() >= 1000 {
        index += 1
    }
    let value = Double(count) / units[index].divisor
    let text: String
    if value < 9.95 {
        let tenths = Int((value * 10).rounded())
        text = tenths.isMultiple(of: 10) ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    } else {
        text = "\(Int(value.rounded()))"
    }
    return "~\(text)\(units[index].suffix)"
}

/// Renders a centered scroll indicator line with an arrow, a row count and label.
///
/// Used by `_ListCore` and `_TableCore` to show "N more above" / "N more below"
/// indicators when content extends beyond the visible viewport.
///
/// - Parameters:
///   - direction: Whether the indicator points up or down.
///   - count: The number of rows/lines hidden in that direction. Omitted
///     from the label (along with the unit word) when zero — in normal use
///     the caller only renders the indicator when at least one is hidden.
///   - unit: What `count` denominates — the label spells it out
///     ("42 more rows below" vs "~200M more lines below").
///   - width: The total width available for the indicator line.
///   - palette: The color palette for styling.
///   - approximate: Whether `count` derives from ESTIMATED geometry (a
///     windowed stack's unmeasured remainder) — rendered as "~5.4K" so the
///     label doesn't assert precision the number doesn't have. Exact counts
///     (`List`/`Table` rows, fully measured content) keep full precision.
/// - Returns: A styled string with a centered scroll indicator.
@MainActor
func renderScrollIndicator(
    direction: ScrollIndicatorDirection,
    count: Int,
    unit: ScrollIndicatorUnit,
    width: Int,
    palette: any Palette,
    approximate: Bool = false
) -> String {
    let arrow = direction == .up ? "▲" : "▼"
    let countText = approximate ? approximateCountLabel(count) : "\(count)"
    let unitWord = unit.word(for: count)
    let directionWord = direction == .up ? "above" : "below"

    // The label degrades to fit a narrow viewport rather than clipping
    // mid-word: the count and its unit survive as long as possible, and
    // the arrow already carries the direction once the words must go.
    let bodies: [String] = count > 0
        ? [
            "\(countText) more \(unitWord) \(directionWord)",
            "\(countText) \(unitWord) \(directionWord)",
            "\(countText) \(unitWord)",
            countText,
        ]
        : ["more \(directionWord)"]
    let body = bodies.first { 1 + $0.count + 2 <= width } ?? ""
    let label = body.isEmpty ? " " : " \(body) "

    let styledArrow = ANSIRenderer.colorize(arrow, foreground: palette.foregroundTertiary)
    let styledLabel = ANSIRenderer.colorize(label, foreground: palette.foregroundTertiary)

    let indicatorWidth = 1 + label.count
    let padding = max(0, (width - indicatorWidth) / 2)

    return String(repeating: " ", count: padding) + styledArrow + styledLabel
}
