//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// height.
///
/// Below ``exactRowLimit`` rows every row is measured rather than sampled — a
/// table small enough to measure outright is simply measured — but the answer is
/// then KEPT while the layout that produced it holds (see
/// ``ScrollExtentProfile``), so editing the rows' content without changing their
/// number or their columns leaves the middle of the travel as approximate as
/// ``approximate`` would. That is the trade ``approximate`` already makes, taken
/// on a path where exactness was never asked for; ``exact`` itself is never
/// cached, and re-measures every row every frame as its own documentation says.
///
/// Single-line rows are unaffected: there the line count *is* the row count, so
/// the extent is already exact at no cost.
///
/// ```swift
/// Table(logEntries) { ... }
///     .scrollExtentPrecision(.exact)
/// ```
/// What a previous ``ScrollExtentEstimator/lineMetrics(visible:count:topClip:precision:cached:height:)``
/// worked out about a set of rows' heights, for a caller whose key still holds.
///
/// One type for both modes, because both are the same bargain in different
/// shapes: asking a row its height costs a wrap per column for a `Table` and a
/// row materialisation for a `List`, the answer does not change while the
/// layout that produced it does not, and the caller is the only thing that
/// knows when that is. Data edited under an unchanged signature goes stale,
/// which is the documented trade for the mean and holds identically for the
/// sums — both ends of the thumb's travel are pinned by construction
/// (``ScrollExtentPrecision``), so only the middle can drift.
enum ScrollExtentProfile: Sendable, Equatable {
    /// The mean height of the sample, under ``ScrollExtentPrecision/approximate``.
    case mean(Double)

    /// `sums[i]` is the total height of rows `0..<i`, so `sums` has one more
    /// entry than there are rows. Under ``ScrollExtentPrecision/exact`` or
    /// below ``ScrollExtentPrecision/exactRowLimit``.
    ///
    /// One `Int` per row is the cost of not re-wrapping every row every frame —
    /// 2 KB for the 250-row table that motivated it, and proportionally more
    /// for a large table someone put into `.exact`, which is a mode whose whole
    /// premise is already that exactness is worth paying for.
    case prefixSums([Int])
}

public enum ScrollExtentPrecision: Sendable, Hashable, CaseIterable {
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
    /// - Parameters:
    ///   - cachedMean: a mean this estimator previously RETURNED for the same
    ///     inputs, when the caller still holds one. The sample is the same 64
    ///     indices every frame for a given row count (see
    ///     ``ScrollExtentPrecision/sampleCount``), yet deriving it costs a
    ///     height — for a Table, a cell-string build and a fit per column; for
    ///     a List, MATERIALISING the row — per sampled off-screen row, per
    ///     frame. The caller keys its stash on whatever shapes the heights
    ///     (row count, column widths and limits, available width, precision)
    ///     and hands the mean back while the key holds, so steady-state frames
    ///     sample nothing. Data edits under an unchanged key can go stale —
    ///     accepted, because the mean only bends the MIDDLE of the thumb's
    ///     travel (both ends are pinned by construction, the property the type
    ///     doc calls out) and the estimate was already approximate.
    static func lineMetrics(
        visible: Range<Int>,
        count: Int,
        topClip: Int,
        precision: ScrollExtentPrecision,
        cached: ScrollExtentProfile? = nil,
        height: (Int) -> Int
    ) -> (extent: Int, offset: Int, profile: ScrollExtentProfile?) {
        guard count > 0 else { return (extent: 0, offset: 0, profile: nil) }
        let clamped = visible.clamped(to: 0..<count)
        var linesVisible = 0
        for index in clamped { linesVisible += height(index) }

        let linesAbove: Int
        let linesBelow: Int
        var profileUsed: ScrollExtentProfile?
        if precision == .exact {
            // Asked for, so measured — every row, every frame. `.exact` says in
            // its own documentation that it costs O(rows) per frame and is for
            // callers who want a thumb proportionally exact to the line, so a
            // cache here would quietly sell them the approximation they
            // declined. The cheap case below is the one worth keeping.
            var above = 0
            for index in 0..<clamped.lowerBound { above += height(index) }
            var below = 0
            for index in clamped.upperBound..<count { below += height(index) }
            (linesAbove, linesBelow) = (above, below)
        } else if count <= ScrollExtentPrecision.exactRowLimit {
            // Exact because it is CHEAP, not because anyone asked — and it was
            // not cheap. This was the one path with no stash of its own, which
            // made the small case the expensive one: a table above the row limit
            // samples 64 rows and keeps the answer, while one below it wrapped
            // every row on every frame and kept nothing. A wrapped table of 250
            // rows spent 45% of its frame here to draw twelve rows.
            //
            // The heights are kept as a PREFIX SUM rather than a total, because
            // the thumb needs the split as well as the sum: `linesAbove` is the
            // sum before the window and `linesBelow` the sum after it, and both
            // move every time the window does while the heights themselves do
            // not. One `Int` per row, under the signature the mean already uses.
            let sums: [Int]
            if case .prefixSums(let cachedSums) = cached, cachedSums.count == count + 1 {
                sums = cachedSums
            } else {
                var built = [Int](repeating: 0, count: count + 1)
                for index in 0..<count { built[index + 1] = built[index] + height(index) }
                sums = built
            }
            profileUsed = .prefixSums(sums)
            // The VISIBLE rows are measured live above and not taken from the
            // sums: those rows are laid out this frame anyway, so reading them
            // from a stash could only make the one part of the estimate that is
            // exact approximate.
            (linesAbove, linesBelow) = (sums[clamped.lowerBound], sums[count] - sums[clamped.upperBound])
        } else {
            // One mean, applied to both sides, so the two ends of the estimate
            // are drawn from the same sample and stay mutually consistent.
            let cachedMean: Double? = if case .mean(let value) = cached { value } else { nil }
            let mean = cachedMean ?? meanRowHeight(count: count, height: height)
            profileUsed = .mean(mean)
            linesAbove = Int((Double(clamped.lowerBound) * mean).rounded())
            linesBelow = Int((Double(count - clamped.upperBound) * mean).rounded())
        }

        return (
            extent: linesAbove + linesVisible + linesBelow,
            offset: linesAbove + topClip,
            profile: profileUsed
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
