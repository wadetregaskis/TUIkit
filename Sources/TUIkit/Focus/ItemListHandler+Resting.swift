//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Resting.swift
//
//  Where a `List` / `Table` viewport is allowed to come to rest.
//
//  Created by Wade Tregaskis
//  License: MIT

extension ItemListHandler {

    /// Snaps the viewport off a resting offset of 1, where an "▲ 1 more row
    /// above" indicator would hide a single row using the very line that could
    /// show it. At offset 0 the row shows and the indicator is gone, and the
    /// freed line keeps the bottom row visible — strictly more content.
    ///
    /// Called once per RENDER pass by both `List` and `Table` after the
    /// ordinary clamp. It lives here, on the handler, because it is a rule
    /// about the scroll offset rather than about either view's rendering —
    /// and because the two views had already drifted apart on it twice, the
    /// `Table` keeping a bare `scrollOffset == 1` test long after the `List`
    /// had learned the three exceptions below. That divergence is what made a
    /// drag auto-scroll unable to leave the top of a `Table`.
    ///
    /// Three things are not "resting", and each is skipped:
    ///
    /// - **A scrollbar is drawn.** It has no indicator line to save, so there
    ///   is nothing to win — and the snap would undo a single up/down-arrow
    ///   click on the bar (0↔1).
    /// - **A line-granular step landed mid-row.** A wheel tick over multi-line
    ///   rows legitimately rests at row 1 (one three-line tick over three-line
    ///   rows), and snapping it back makes the list unscrollable whenever the
    ///   ticks happen to land row-aligned.
    /// - **A drag is auto-scrolling this viewport.** A viewport being driven a
    ///   row per tick is not resting anywhere; snapping it back turns the first
    ///   tick into a permanent 0↔1 stall, so the drag can never leave the top.
    ///
    /// - Parameters:
    ///   - overflowing: Whether the content is taller than the viewport. A list
    ///     that fits has no indicator to save in the first place.
    ///   - showsScrollbar: Whether a scrollbar is drawn instead of the text
    ///     indicators.
    ///   - firstRowHeight: The first row's height in lines — only consulted
    ///     under line granularity, hence `@autoclosure`: a `List` resolves it by
    ///     building the row, which is not worth doing on the frames (nearly all
    ///     of them) that fail the cheap tests first.
    func settleRestingOffset(
        overflowing: Bool,
        showsScrollbar: Bool,
        firstRowHeight: @autoclosure () -> Int
    ) {
        guard overflowing, !showsScrollbar, scrollOffset == 1, !isAutoScrolling else { return }
        let restingMidRow =
            scrollGranularity == .line && (scrollTopClipLines > 0 || firstRowHeight() > 1)
        guard !restingMidRow else { return }
        scrollOffset = 0
    }

    /// The origin the viewport is DRAWN from this frame: the scroll offset and
    /// top clip after absorbing any hidden content an "▲ N more" indicator
    /// would cost more to announce than it hides.
    ///
    /// An indicator spends a line to report that content is hidden. Where no
    /// more lines are hidden than the indicator itself costs, that is pure
    /// loss — it says "1 more row above" in the very line the content would
    /// have occupied (and calls a single clipped LINE a row while it is at
    /// it). The window starts at the un-clipped origin instead and shows the
    /// content; the freed indicator line pays for it exactly, so nothing below
    /// moves.
    ///
    /// Resolution only, never a state change — which is why this is a query
    /// and ``settleRestingOffset(overflowing:showsScrollbar:firstRowHeight:)``
    /// is a mutation. The handler must keep counting fine steps: a clip
    /// snapped back to zero would be re-made by the next step and snapped
    /// again, stalling the wheel at the top forever. Only the drawing absorbs
    /// it.
    ///
    /// Only an offset of 0 or 1 can qualify (every row is at least one line),
    /// which keeps this O(1) — no walking a tall list's rows.
    ///
    /// - Parameter firstRowHeight: Row 0's height in lines, consulted only at
    ///   offset 1, hence `@autoclosure`: a `List` resolves it by building the
    ///   row, not worth doing on the frames that fail the offset test first.
    /// - Returns: The offset and top clip to draw from. Callers must use BOTH
    ///   for the rows, the indicators, the published bands and the click
    ///   mapping — a renderer that draws from the absorbed origin while the
    ///   hit test measures from the raw one puts every row a line off its band.
    func resolvedWindowOrigin(
        firstRowHeight: @autoclosure () -> Int
    ) -> (offset: Int, topClip: Int) {
        ScrollWindowOrigin.absorbing(
            offset: scrollOffset, topClip: scrollTopClipLines,
            firstRowHeight: firstRowHeight())
    }
}

/// The rule for where a scrolled row viewport is drawn from, shared by `List`
/// and `Table` so it cannot drift between them (the `Table`'s window resolver
/// learned it first, and the `List` spent a line on "▲ 1 more row above"
/// hiding the very line it was reporting until it learned it too).
enum ScrollWindowOrigin {

    /// See ``ItemListHandler/resolvedWindowOrigin(firstRowHeight:)``, which is
    /// how a handler-holding caller asks. `Table` calls this directly, with an
    /// offset it has already clamped into its row range.
    static func absorbing(
        offset: Int, topClip: Int, firstRowHeight: @autoclosure () -> Int
    ) -> (offset: Int, topClip: Int) {
        let hiddenAbove =
            switch offset {
            case 0: topClip
            case 1: firstRowHeight() + topClip
            default: 2  // ">= 2", enough to earn the indicator
            }
        return hiddenAbove == 1 ? (0, 0) : (offset, topClip)
    }
}
