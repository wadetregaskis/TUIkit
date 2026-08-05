//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollExtentPrecision.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollExtentPrecision

/// How precisely a scrollable measures the rows it is *not* showing.
///
/// A ``List`` or ``Table`` whose rows span multiple lines only knows a row's
/// height by wrapping its text into the column widths. The rows on screen have
/// to be wrapped anyway — they are about to be drawn — but the ones above and
/// below the viewport are needed for exactly one thing: the scroll indicator.
/// Either the scrollbar's thumb (where it sits in the track and how large it
/// is) or the count in "▲ N more above". Wrapping thousands of off-screen rows
/// every frame to place a thumb a cell or two more accurately is a poor trade,
/// so by default the off-screen rows are sampled rather than measured.
///
/// - ``approximate``: the visible rows are exact; the rest are estimated from a
///   fixed, evenly-spaced sample. O(1) in the row count. The default.
/// - ``exact``: every row is measured. O(rows) per frame, and every row's text
///   is wrapped. Opt into it when a thumb that is proportionally exact to the
///   line matters more than the cost.
///
/// Both ends are pinned in either mode: scrolled fully to the top the thumb is
/// at the top of its track, and at the furthest scroll it is at the bottom.
/// Only the middle of the travel can drift, and only when rows differ wildly in
/// height. Below ``exactRowLimit`` rows the two modes are identical — a table
/// small enough to measure outright is simply measured.
///
/// Single-line rows are unaffected: there the line count *is* the row count, so
/// the extent is already exact at no cost.
///
/// ```swift
/// Table(logEntries) { ... }
///     .scrollExtentPrecision(.exact)
/// ```
public enum ScrollExtentPrecision: Sendable, Equatable, CaseIterable {
    /// Measure the visible rows; estimate the rest from a sample. The default.
    case approximate

    /// Measure every row, on screen or not.
    case exact

    /// At or below this many rows both modes measure everything: the sampling
    /// only pays for itself once the walk it replaces is long, and a small
    /// table that reports an approximate extent would be all cost and no
    /// benefit. Matches the exact-walk rung of the lazy stacks' measure ladder.
    public static let exactRowLimit = 256

    /// How many rows ``approximate`` measures to derive its mean row height.
    ///
    /// Deliberately a fixed count rather than a fraction: the estimate must not
    /// change as the view scrolls, or the thumb would resize under the pointer.
    /// The sample is taken at evenly spaced indices over the whole collection,
    /// so it is the same sample every frame for a given row count.
    public static let sampleCount = 64
}

// MARK: - Environment

private struct ScrollExtentPrecisionKey: EnvironmentKey {
    static let defaultValue: ScrollExtentPrecision = .approximate
}

extension EnvironmentValues {
    /// How precisely scrollables in this subtree measure their off-screen rows
    /// — see ``ScrollExtentPrecision``. Defaults to
    /// ``ScrollExtentPrecision/approximate``.
    public var scrollExtentPrecision: ScrollExtentPrecision {
        get { self[ScrollExtentPrecisionKey.self] }
        set { self[ScrollExtentPrecisionKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Sets how precisely ``List`` and ``Table`` content in this subtree
    /// measures the rows outside its viewport.
    ///
    /// The off-screen rows feed only the scroll indicators, so they are
    /// ``ScrollExtentPrecision/approximate`` by default. Pass
    /// ``ScrollExtentPrecision/exact`` where a proportionally exact scrollbar
    /// thumb is worth wrapping every row's text on every frame.
    public func scrollExtentPrecision(_ precision: ScrollExtentPrecision) -> some View {
        environment(\.scrollExtentPrecision, precision)
    }
}

// MARK: - Shared estimator

/// The line-metered scrollbar arithmetic shared by ``List`` and ``Table``,
/// which meter their bars in *lines* whenever a row can span more than one.
///
/// Both views arrive here with the same three facts — the range of rows on
/// screen, a way to ask any row's height, and how many of the top row's lines
/// are clipped above the fold — and want the same two numbers back. Keeping the
/// arithmetic in one place is what stops the twins drifting apart yet again;
/// see the divergence history in `List`/`Table`'s scroll rules.
enum ScrollExtentEstimator {

    /// The scrollbar's `extent` (total content lines) and `offset` (lines above
    /// the viewport) for a run of variable-height rows.
    ///
    /// The two are computed together, from the same numbers, so they cannot
    /// disagree:
    ///
    ///     extent = linesAbove + linesVisible + linesBelow
    ///     offset = linesAbove + topClip
    ///
    /// which pins both ends of the travel regardless of how wrong the estimate
    /// is. At the top `linesAbove` is 0, so the thumb starts at the top of the
    /// track. At the furthest scroll `linesBelow` is 0 and the visible rows fill
    /// the viewport, so `offset + viewport == extent` and the thumb ends flush
    /// at the bottom. An estimate that only bends the middle of the travel is
    /// invisible; one that misses the ends looks broken.
    ///
    /// - Parameters:
    ///   - visible: the range of rows currently on screen.
    ///   - count: the total number of rows.
    ///   - topClip: lines of the first visible row hidden above the fold.
    ///   - precision: whether off-screen rows are sampled or measured.
    ///   - height: the height in lines of the row at an index. Called once per
    ///     visible row always, and for every other row only under
    ///     ``ScrollExtentPrecision/exact`` (or below its row limit).
    static func lineMetrics(
        visible: Range<Int>,
        count: Int,
        topClip: Int,
        precision: ScrollExtentPrecision,
        height: (Int) -> Int
    ) -> (extent: Int, offset: Int) {
        guard count > 0 else { return (extent: 0, offset: 0) }
        let clamped = visible.clamped(to: 0..<count)
        var linesVisible = 0
        for index in clamped { linesVisible += height(index) }

        let linesAbove: Int
        let linesBelow: Int
        if precision == .exact || count <= ScrollExtentPrecision.exactRowLimit {
            var above = 0
            for index in 0..<clamped.lowerBound { above += height(index) }
            var below = 0
            for index in clamped.upperBound..<count { below += height(index) }
            (linesAbove, linesBelow) = (above, below)
        } else {
            // One mean, applied to both sides, so the two ends of the estimate
            // are drawn from the same sample and stay mutually consistent.
            let mean = meanRowHeight(count: count, height: height)
            linesAbove = Int((Double(clamped.lowerBound) * mean).rounded())
            linesBelow = Int((Double(count - clamped.upperBound) * mean).rounded())
        }

        return (
            extent: linesAbove + linesVisible + linesBelow,
            offset: linesAbove + topClip
        )
    }

    /// The mean height of ``ScrollExtentPrecision/sampleCount`` rows spread
    /// evenly across the collection.
    ///
    /// Kept fractional: rounding a 2.4-line mean down to 2 understates a
    /// 10,000-row extent by 17%, which is a visibly wrong thumb size. The
    /// rounding happens once, on the product.
    private static func meanRowHeight(count: Int, height: (Int) -> Int) -> Double {
        let samples = min(count, ScrollExtentPrecision.sampleCount)
        guard samples > 0 else { return 1 }
        var total = 0
        for step in 0..<samples { total += height((step * count) / samples) }
        return Double(total) / Double(samples)
    }
}
