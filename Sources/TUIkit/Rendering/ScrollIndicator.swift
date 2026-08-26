//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollIndicator.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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

/// The indicator's emphasis across a whole cycle, for a focused scrollable.
///
/// Reads no clock — it builds the cycle from the static formula — so the
/// indicator's cells can be handed to the run loop instead of the page being
/// re-rendered on every tick to recolour them.
@MainActor
func scrollIndicatorCycle(isFocused: Bool, context: RenderContext) -> SelectionEmphasisCycle? {
    guard isFocused else { return nil }
    return context.environment.selectionEmphasis.cycle(true)
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
/// ("~1M", never "~1000K"). The decimal separator follows `locale`, so a
/// German app reads "~5,4K".
func approximateCountLabel(_ count: Int, locale: Locale = .current) -> String {
    guard count >= 1000 else { return "~\(localizedInteger(count, locale: locale))" }
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
        text =
            tenths.isMultiple(of: 10)
            ? "\(tenths / 10)"
            : (Double(tenths) / 10).formatted(
                .number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    } else {
        text = "\(Int(value.rounded()))"
    }
    return "~\(text)\(units[index].suffix)"
}

/// A whole number with the grouping separator of `locale` — "12,000" (en),
/// "12.000" (de), "12 000" (fr) — for the counts rendered into scroll chrome.
func localizedInteger(_ value: Int, locale: Locale = .current) -> String {
    value.formatted(.number.grouping(.automatic).locale(locale))
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
///   - emphasis: When non-`nil`, the arrow and label are drawn in this colour
///     instead of the quiet `foregroundTertiary` — used to PULSE the
///     indicators (a scrollbar-less scrollable's focus cue). `nil` keeps the
///     resting appearance.
///   - locale: Formats the count's grouping / decimal separators — the app's
///     current language locale, so the number reads "12,000" (en) / "12.000"
///     (de) / "12 000" (fr). Defaults to `.current`.
/// - Returns: A styled string with a centered scroll indicator.
@MainActor
func renderScrollIndicator(
    direction: ScrollIndicatorDirection,
    count: Int,
    unit: ScrollIndicatorUnit,
    width: Int,
    palette: any Palette,
    approximate: Bool = false,
    locale: Locale = .current
) -> String {
    scrollIndicatorParts(
        direction: direction, count: count, unit: unit, width: width,
        approximate: approximate, locale: locale
    ).line(color: palette.foregroundTertiary)
}

/// The same indicator, drawn from a whole emphasis cycle — plus the
/// ``AnimatedCellRun`` that lets the run loop breathe those cells with no view
/// involved.
///
/// The overload above is the still one, for a caller that only wants the
/// indicator's WIDTH (the table measures its column against it) or has no
/// focus to show.
///
/// The run covers the arrow and its label and nothing else: the leading blanks
/// that centre the indicator are not part of the animation, and repainting them
/// on a clock would be bytes spent to redraw spaces. Its `offsetY` is 0 — the
/// caller knows which row it landed on and shifts it there.
@MainActor
func renderScrollIndicator(
    direction: ScrollIndicatorDirection,
    count: Int,
    unit: ScrollIndicatorUnit,
    width: Int,
    palette: any Palette,
    approximate: Bool = false,
    cycle: SelectionEmphasisCycle?,
    locale: Locale = .current
) -> (text: String, animation: AnimatedCellRun?) {
    let parts = scrollIndicatorParts(
        direction: direction, count: count, unit: unit, width: width,
        approximate: approximate, locale: locale)
    guard let cycle, cycle.isFocused else {
        return (parts.line(color: palette.foregroundTertiary), nil)
    }
    let dim = palette.foregroundTertiary
    let bright = palette.accent
    return (
        parts.line(color: cycle.colorNow(dim: dim, bright: bright)),
        cycle.run(dim: dim, bright: bright, offsetX: parts.padding, offsetY: 0) {
            parts.styled(color: $0)
        }
    )
}

/// An indicator's text and geometry, before any colour is chosen — so the
/// static render and every frame of the animated one are laid out by the same
/// arithmetic and cannot drift apart.
private struct ScrollIndicatorParts {
    let arrow: String
    let label: String
    let padding: Int

    /// Just the animated cells: the arrow and its label.
    func styled(color: Color) -> String {
        ANSIRenderer.colorize(arrow, foreground: color)
            + ANSIRenderer.colorize(label, foreground: color)
    }

    /// The whole row: the centring blanks, then the animated cells.
    func line(color: Color) -> String {
        String(repeating: " ", count: padding) + styled(color: color)
    }
}

private func scrollIndicatorParts(
    direction: ScrollIndicatorDirection,
    count: Int,
    unit: ScrollIndicatorUnit,
    width: Int,
    approximate: Bool,
    locale: Locale
) -> ScrollIndicatorParts {
    let arrow = direction == .up ? "\u{25B2}" : "\u{25BC}"
    let countText =
        approximate
        ? approximateCountLabel(count, locale: locale)
        : localizedInteger(count, locale: locale)
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

    let indicatorWidth = 1 + label.count
    return ScrollIndicatorParts(
        arrow: arrow, label: label, padding: max(0, (width - indicatorWidth) / 2))
}
