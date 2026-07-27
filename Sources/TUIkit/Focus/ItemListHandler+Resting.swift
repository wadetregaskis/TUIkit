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
}
