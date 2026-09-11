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

/// One "N more" line as drawn: its bytes, the claims its colours owe, and the run
/// that breathes it.
///
/// A type rather than a `(text:animation:)` tuple for the reason ``ClaimingColumn``
/// is one (§43.1): `List`, both of `Table`'s paths and both of `ScrollView`'s put the
/// line on a row of their own, and a claim in the line's own coordinates lets each
/// place it with the shift it already gives the run.
struct ScrollIndicatorLine {
    /// The centring blanks, then the arrow and its label. Its claims are in the
    /// line's own coordinates: column 0 is the first blank, row 0 the line.
    let drawn: ClaimingRow
    /// Breathes the arrow and its label at row 0, column `padding`; `nil` when still.
    let animation: AnimatedCellRun?

    var text: String { drawn.text }

    /// The line's claims, moved to the row its host drew it on.
    func claims(atRow row: Int) -> [OpacityRegion] {
        drawn.claims.map { $0.shifted(byX: 0, y: row) }
    }
}

/// The two ends a focused scrollable's indicator breathes between — its resting
/// tertiary and the accent — BOTH spending a translucent alpha against `surface`.
///
/// Spent, not carried as the scrollbar's are (§44). Those are two re-spellings of one
/// accent, which can share its alpha; these are two palette slots with alphas of their
/// own, and a faded `.tint` alone put 255 at one end and 128 at the other — a run
/// whose alpha moved with its phase (§29). A navigation crumb's breath is the exact
/// twin: a resting rung and the accent, both spent (§47.2).
func scrollIndicatorBreath(palette: any Palette, over surface: Color) -> (dim: Color, bright: Color) {
    (dim: palette.foregroundTertiary.spendingAlpha(over: surface),
     bright: palette.accent.spendingAlpha(over: surface))
}

/// The width an indicator line draws, without drawing it — for `Table`'s measure,
/// which used to render the whole line to read its `strippedLength`: a colour
/// chosen, and spelled for the emitter, in a pass that draws nothing.
func scrollIndicatorWidth(
    direction: ScrollIndicatorDirection, count: Int, unit: ScrollIndicatorUnit,
    width: Int, approximate: Bool = false, locale: Locale = .current
) -> Int {
    scrollIndicatorParts(
        direction: direction, count: count, unit: unit, width: width,
        approximate: approximate, locale: locale
    ).width
}

/// Renders a centred scroll indicator line: an arrow, a count, and its unit.
///
/// Used by `_ListCore`, `Table` and `ScrollView` to show "N more above" / "N more
/// below" lines when content extends beyond the visible viewport.
///
/// - Parameters:
///   - direction: Whether the indicator points up or down.
///   - count: The number of rows/lines hidden in that direction. Zero is a real
///     value and reads as one ("0 more rows above"): with
///     ``EnvironmentValues/alwaysShowsVerticalTextIndicators`` the line is drawn
///     at the edges, where nothing is hidden.
///   - unit: What `count` denominates — the label spells it out
///     ("42 more rows below" vs "~200M more lines below").
///   - width: The total width available for the indicator line.
///   - palette: The resting tertiary the line is drawn in, and the accent a
///     focused one breathes to.
///   - approximate: Whether `count` derives from ESTIMATED geometry (a
///     windowed stack's unmeasured remainder) — rendered as "~5.4K" so the
///     label doesn't assert precision the number doesn't have. Exact counts
///     (`List`/`Table` rows, fully measured content) keep full precision.
///   - cycle: The whole emphasis cycle of a focused scrollable. It does both jobs
///     at once: its current phase colours the line drawn now, and the cycle itself
///     becomes the ``AnimatedCellRun`` the run loop replays, so the pulse costs no
///     further render passes. `nil`, or an unfocused cycle, draws the resting line
///     and yields no run.
///   - surface: What the line sits on: the ground a focused line spends its two
///     ends' alphas against (``scrollIndicatorBreath(palette:over:)``) — even when
///     `.selectionIndicatorStyle(.none)` leaves it still, one frame and no run, so
///     focus shows one colour whether it breathes or not. An unfocused line carries
///     its colour's alpha and claims it instead.
///   - locale: Formats the count's grouping / decimal separators — the app's
///     current language locale, so the number reads "12,000" (en) / "12.000"
///     (de) / "12 000" (fr). Defaults to `.current`.
/// - Returns: The line and its claims, and a focused line's run. The run covers the
///   arrow and its label and nothing else: the leading blanks that centre the
///   indicator are not part of the animation, and repainting them on a clock would
///   be bytes spent to redraw spaces. Its `offsetY` is 0 — the caller knows which
///   row the line landed on, and shifts the run there as it places the claims.
@MainActor
func renderScrollIndicator(
    direction: ScrollIndicatorDirection,
    count: Int,
    unit: ScrollIndicatorUnit,
    width: Int,
    palette: any Palette,
    approximate: Bool = false,
    cycle: SelectionEmphasisCycle?,
    over surface: Color,
    locale: Locale = .current
) -> ScrollIndicatorLine {
    let parts = scrollIndicatorParts(
        direction: direction, count: count, unit: unit, width: width,
        approximate: approximate, locale: locale)
    // Unfocused: nothing replays these cells, so the resting colour CARRIES its
    // alpha, and the line claims it (§29.2). A focused line spends below, breathing
    // or not.
    guard let cycle, cycle.isFocused else {
        return ScrollIndicatorLine(drawn: parts.line(ink: palette.foregroundTertiary), animation: nil)
    }
    let ends = scrollIndicatorBreath(palette: palette, over: surface)
    // The cycle's colours once, spent twice — the frame drawn now is one of them and
    // the run is all of them — where `colorNow` and `run(dim:bright:…)` would each
    // build the ramp for themselves. `ButtonCapCycle`'s shape.
    let colors = cycle.colors(dim: ends.dim, bright: ends.bright)
    let drawn = parts.line(ink: colors[cycle.step % colors.count])
    // Every frame through the same funnel, claims kept: a run is right only if each
    // frame owes what the drawn line does (§29.2) — which, with both ends spent, is
    // nothing.
    var owed = [drawn.claims.map { $0.shifted(byX: -parts.padding, y: 0) }]
    // One allocation for bookkeeping only the debug assertion below reads.
    owed.reserveCapacity(colors.count + 1)
    let run = cycle.run(colors: colors, offsetX: parts.padding, offsetY: 0) {
        let body = parts.body(ink: $0)
        owed.append(body.claims)
        return body.text
    }
    assertFramesOweOneClaim(owed, "a scroll indicator's breath")
    return ScrollIndicatorLine(drawn: drawn, animation: run)
}

/// An indicator's text and geometry, before any colour is chosen — so the still
/// line and every frame of the breathing one are laid out by the same arithmetic,
/// and cannot drift apart.
private struct ScrollIndicatorParts {
    let arrow: String
    let label: String
    let padding: Int

    /// The cells the line draws, measured the way its claim and its run are: by
    /// what is drawn (`strippedLength`).
    var width: Int { padding + arrow.strippedLength + label.strippedLength }

    /// The breathing cells alone: the arrow and its label.
    func body(ink: Color) -> ClaimingRow {
        var row = ClaimingRow()
        paint(into: &row, ink: ink)
        return row
    }

    /// The whole line: the centring blanks, then the arrow and its label. The blanks
    /// are a gap (`skip`): no colour, so no claim.
    func line(ink: Color) -> ClaimingRow {
        var row = ClaimingRow()
        row.skip(cells: padding)
        paint(into: &row, ink: ink)
        return row
    }

    private func paint(into row: inout ClaimingRow, ink: Color) {
        row.append(arrow, cells: arrow.strippedLength, ink: ink)
        row.append(label, cells: label.strippedLength, ink: ink)
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
    // Zero is a real count, not a missing one: under
    // `EnvironmentValues.alwaysShowsVerticalTextIndicators` the line is drawn at
    // the very top and the very bottom, where nothing is hidden, and it should
    // say "0 more rows above" like every other value says its own. It used to
    // fall to a countless "more above", which at zero is simply false.
    let bodies: [String] = [
        "\(countText) more \(unitWord) \(directionWord)",
        "\(countText) \(unitWord) \(directionWord)",
        "\(countText) \(unitWord)",
        countText,
    ]
    let body = bodies.first { 1 + $0.count + 2 <= width } ?? ""
    let label = body.isEmpty ? " " : " \(body) "

    let indicatorWidth = 1 + label.count
    return ScrollIndicatorParts(
        arrow: arrow, label: label, padding: max(0, (width - indicatorWidth) / 2))
}
