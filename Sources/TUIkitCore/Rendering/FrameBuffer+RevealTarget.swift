//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+RevealTarget.swift
//
//  Where a reveal scrolls to for a control, read off a buffer's hit-test regions.
//  Split from `FrameBuffer.swift`, which had reached the file-length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// Where a reveal should scroll to for the control identified by `focusID`.
    ///
    /// A focusable container emits SEVERAL regions under one id: a whole-
    /// control region (which spans its border), and a smaller one for whatever
    /// is currently active inside it — a List's selected row, say. Which one to
    /// reveal depends on what just happened, and the two answers differ:
    ///
    /// - `wholeControl` (focus just MOVED here): you tabbed to the *list*, so
    ///   show as much of the list as will fit — its border and header included.
    ///   Selecting a row is a secondary effect of arriving, not the point.
    ///   Returns the union of every region carrying the id.
    /// - otherwise (focus moved WITHIN a control that already had it): you are
    ///   moving between rows, not regarding the list as a whole, so reveal only
    ///   the thing that changed. Returns the smallest region — the active row —
    ///   which is what keeps a cursor visible while walking a long table.
    ///
    /// Revealing the union in BOTH cases pushes the cursor off-screen on every
    /// arrow key; revealing the row in both leaves a bordered control's top rule
    /// just above the fold. Hence the split.
    public func revealTarget(focusID: String, wholeControl: Bool) -> (top: Int, height: Int)? {
        var top = Int.max
        var bottom = Int.min
        var smallest: HitTestRegion?
        for region in hitTestRegions where region.focusID == focusID {
            // The union grows by whatever chrome an ancestor drew flush against
            // the region — the border it is framed by is part of "the control"
            // when you have just arrived at it. The smallest region, which the
            // within-control path uses, deliberately ignores the outsets: a
            // cursor moving row to row is not re-revealing the frame.
            top = Swift.min(top, region.offsetY - region.revealOutsetTop)
            bottom = Swift.max(bottom, region.offsetY + region.height + region.revealOutsetBottom)
            if smallest == nil || region.height < smallest!.height { smallest = region }
        }
        guard top <= bottom, let smallest else { return nil }
        return wholeControl ? (top, bottom - top) : (smallest.offsetY, smallest.height)
    }
}
