//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollRowWindow.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Which rows are on screen

/// The rows visible at a scroll offset, and what is hidden either side of them.
///
/// One rule, asked three ways. `_ListCore` needs the rows themselves and its
/// rows are any height; a multi-line `Table` needs the range and its heights
/// come from wrapping; a single-line `Table` needs a count and every row is one
/// line. All three were written out separately, and the project's own note on
/// `List` and `Table` is that they "implement the same rules twice and drift".
///
/// They had not drifted here — each of the four suspected divergences was chased
/// down and proved equivalent, which is why this extraction can be inert — but
/// three copies of a rule that nothing forces to agree is the state the drift
/// comes out of, not the drift itself.
///
/// The rule: put the top row's hidden lines outside the viewport, take a line for
/// an "above" indicator if one will be drawn, fill, and — if rows remain past
/// that window — take another for the "below" indicator and fill again.
struct ScrollRowWindow {
    /// The rows on screen.
    let range: Range<Int>
    /// Whether anything is hidden above the window. A line-granularity top clip
    /// counts: the first row is partially hidden, which is content above even
    /// though no whole row is.
    ///
    /// NOT gated on whether indicators are drawn — a scrollbar wants to know
    /// this too. What the gate decides is the RESERVATION, which is already
    /// applied to ``range``.
    let showsAbove: Bool
    /// Whether anything is hidden below it.
    let showsBelow: Bool
    /// Lines of the top row hidden above the viewport, after any absorb.
    let topClip: Int

    /// Resolves the window.
    ///
    /// - Parameters:
    ///   - scrollOffset: The first row the viewport wants. Clamped into the row
    ///     range here; every caller's handler already holds it there
    ///     (``ItemListHandler/itemCount``'s `didSet` clamps it to `count - 1`),
    ///     so the clamp is a belt on a path that has braces — but it is what
    ///     makes ``range`` safe to build unconditionally.
    ///   - count: How many rows there are.
    ///   - contentHeight: The lines the rows and their indicators share.
    ///   - topClip: Lines of the top row already scrolled past.
    ///   - drawsTextIndicators: Whether "N more above/below" lines are what this
    ///     view marks hidden rows with. `false` for a scrollbar (which spends a
    ///     column, not a line) and for hidden indicators (which spend nothing) —
    ///     in both cases the whole content area is viewport, nothing is
    ///     reserved, and there is no clip worth absorbing.
    ///
    ///     `ItemListHandler.drawsScrollIndicators` is exactly this question, on
    ///     all three callers — including "does the view overflow", since a view
    ///     whose rows all fit has nothing hidden to announce.
    ///   - height: A row's height in lines. Called at most once per row that
    ///     enters the window, plus once for the row that straddles its end —
    ///     never for a row beyond it. That bound is load-bearing rather than
    ///     tidy: `_ListCore` answers it by MATERIALISING the row, which renders
    ///     it, so a loop that peeked one row further would render one row more
    ///     per frame than the old code did.
    ///
    /// `@inline(__always)` because this replaced three PRIVATE methods, which the
    /// optimiser was free to inline into their one call site each. Left out of
    /// line it cost `kitchensink` +1.3% (`+0.4% … +3.0%`) and `megalist` +0.7%,
    /// with the same closure-per-row shape as the value memo's; inlined, every
    /// list and table shape measures indistinguishable.
    @inline(__always)
    static func resolve(
        scrollOffset: Int,
        count: Int,
        contentHeight: Int,
        topClip: Int = 0,
        drawsTextIndicators: Bool,
        height: (Int) -> Int
    ) -> Self {
        guard count > 0 else {
            return Self(range: 0..<0, showsAbove: false, showsBelow: false, topClip: 0)
        }
        let clamped = min(max(0, scrollOffset), count - 1)
        // Absorb a top clip an indicator would cost more to announce than it
        // hides — the shared rule, so the two cannot drift from it again. A view
        // drawing no indicator line spends none, so it has nothing to absorb.
        let (offset, resolvedClip) =
            drawsTextIndicators
            ? ScrollWindowOrigin.absorbing(
                offset: clamped, topClip: topClip, firstRowHeight: height(0))
            : (clamped, topClip)
        let showsAbove = offset > 0 || resolvedClip > 0

        func fill(budget: Int) -> Int {
            // The clipped lines of the top row don't occupy the viewport.
            var used = -resolvedClip
            var end = offset
            while end < count {
                // Budget first, height second. The height of a row that cannot
                // fit is not needed, and asking for it is what would make
                // `_ListCore` render one row more than it draws.
                if used >= budget && end > offset { break }
                let rowHeight = height(end)
                if used + rowHeight > budget && end > offset {
                    // The row that straddles the remaining budget enters the
                    // window under EITHER granularity, and the renderer clips
                    // its tail: the viewport fills exactly. What granularity
                    // decides is the size of a scroll STEP and where the TOP may
                    // rest — held to whole rows at the bottom too, the viewport
                    // underfilled whenever the visible rows didn't sum to the
                    // budget, and the blank lines that left read as the view
                    // truncating itself.
                    //
                    // The clip is what makes that safe: without it the
                    // over-emitted row met the container's blind bottom clamp,
                    // which ate whatever came last — the "▼ N more below" line,
                    // or the tail of the bottom row on the scrollbar path.
                    end += 1
                    break
                }
                used += rowHeight
                end += 1
            }
            // Always at least one row: a viewport too short for its first row
            // shows that row clipped rather than nothing at all.
            return max(offset + 1, end)
        }

        // A bar marks the hidden rows itself and hidden indicators mark nothing,
        // so in both cases the whole content area is viewport.
        let aboveReserve = (showsAbove && drawsTextIndicators) ? 1 : 0
        // The budget is floored at one line, which is `_ListCore`'s spelling and
        // not the two `Table` paths'. It is the only place the three copies did
        // NOT agree, and the disagreement sits in a region none of them can
        // reach: an indicator line is only reserved when text indicators are
        // drawn, and `ResolvedScrollIndicators.fitting(contentHeight:)` withholds
        // those below three lines — so `contentHeight - aboveReserve` is at least
        // 2 wherever `aboveReserve` is 1. Below that the two spellings differ (an
        // unfloored budget of 0 admits one row, a floored 1 admits as many
        // single-line rows as fit), and the floored one is chosen because a
        // budget that can go negative is the sharper edge to leave lying around.
        var end = fill(budget: max(1, contentHeight - aboveReserve))
        if end < count, drawsTextIndicators {
            end = fill(budget: max(1, contentHeight - aboveReserve - 1))
        }
        return Self(
            range: offset..<min(count, end),
            showsAbove: showsAbove,
            showsBelow: end < count,
            topClip: resolvedClip)
    }
}
