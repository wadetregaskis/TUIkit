//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Anchor.swift
//
//  How `List` and `Table` honour `Documentation/Scroll-anchoring.md` §1.1 —
//  every mode, in one place, expressed in the list's ROW-based scroll offset:
//
//  - **Row**: a bound `.anchorPosition(.row(id))` (set directly, or via the
//    §1.2 selection shadow-switch) pins that row, so the offset adjusts to keep
//    it on its screen line as rows change around it. The counterpart of the
//    LazyVStack windowed paths' `offsetHoldingDesignatedRow`.
//  - **Bottom**: follow-the-log — the offset tracks the tail as rows arrive.
//  - **Top** and **Window**: nothing to do. Both are satisfied by leaving the
//    offset alone, because a row-indexed offset already IS line coordinates
//    (Window), and no data change moves an offset of 0 away from the top.
//    Snapping to the top unconditionally would be worse than useless: it would
//    nail a `.defaultScrollAnchor(.top)` list to row 0 and make it unscrollable.
//
//  Created by Wade Tregaskis
//  License: MIT

extension ItemListHandler {

    /// Applies whichever anchor mode is in effect. Called once per RENDER pass
    /// (it mutates the persistent scroll offset), after the frame's row count,
    /// viewport, row heights and id resolver are wired and the ordinary clamp
    /// has run.
    ///
    /// A no-op for a list that neither binds `.anchorPosition` nor declares a
    /// `defaultScrollAnchor` — which is every list written before this feature.
    func applyAnchorHold() {
        let bound = anchorPositionBinding?.wrappedValue
        adoptWrittenAnchor(bound)
        switch ScrollAnchorMode.effective(boundAnchor: bound, declared: declaredAnchorMode) {
        case .row:
            applyRowAnchorHold()
        case .bottom:
            forgetRowAnchor()
            followBottomEdge()
        case .top, .window:
            forgetRowAnchor()
        }
        bottomFollowBound = maxOffset
    }

    /// Jumps to an edge the app just *wrote* into the binding — §3.2's
    /// `anchor(to:)`. Only the change jumps; the standing policy afterwards is
    /// positional, so the user can still scroll away from the edge.
    ///
    /// A first sighting is the list appearing rather than the app writing, and
    /// is left alone: the declared anchor's own opening placement (the
    /// `bottomFollowBound == 0` first-frame glue below) handles it.
    private func adoptWrittenAnchor(_ bound: ScrollAnchor<AnyHashable>?) {
        guard lastBoundAnchor != .some(bound) else { return }
        let isFirstSighting = lastBoundAnchor == nil
        lastBoundAnchor = .some(bound)
        guard !isFirstSighting else { return }
        switch bound {
        case .top:
            scrollOffset = 0
            scrollTopClipLines = 0
        case .bottom:
            scrollOffset = settledMaxOffset
            scrollTopClipLines = 0
        default:
            break
        }
    }

    /// Follow-the-log: while the view is AT the tail, keep it there as rows
    /// arrive. Engagement is positional — being at the bottom *is* the
    /// engagement, so scrolling up releases the follow and scrolling back down
    /// re-engages it, with no stored flag to get out of step. Mirrors
    /// `_ScrollViewCore.isGluedToBottom`.
    ///
    /// **The focus cursor comes along — but only when the tail advances.** A
    /// focused list's scroll position is owned by its cursor —
    /// `ensureFocusedItemVisible()` runs whenever focus is (re-)received and
    /// drags the viewport back to whatever row the cursor is on, which is the
    /// shipped "the selection must stay visible" invariant. So a follow that
    /// moved the offset alone would be undone within the same frame, leaving
    /// `.bottom` inert on any focused list: the cursor starts at row 0, row 0
    /// is not visible from the tail, and the reveal wins. Carrying the cursor
    /// to the last row is what "follow the log" means anyway — the newest row
    /// is the interesting one.
    ///
    /// The carry fires on frames where the tail actually ADVANCED (the opening
    /// placement, an append, a re-engagement), **never on a steady glued
    /// frame**. Snapping every glued render made the arrow keys dead: Up moved
    /// the cursor to a row that was already visible, so no offset moved, so
    /// the next render was still glued and snapped the cursor straight back —
    /// the release path this comment used to promise ("arrowing up moves the
    /// offset off the tail") could never engage, because the cursor was reset
    /// before it could ever walk to the viewport's top edge. With the carry
    /// scoped to advances, arrowing up walks freely inside the viewport; when
    /// the walk reaches the top edge it moves the offset, which releases the
    /// follow (positional, as ever), and arrowing back down to the tail
    /// re-engages it.
    private func followBottomEdge() {
        guard scrollOffset >= bottomFollowBound else { return }
        let offsetBefore = scrollOffset
        // `settledMaxOffset`, not `maxOffset`: the latter early-outs to a cheap
        // LOWER bound while the offset is nowhere near the tail (so as not to
        // materialise tail row heights every frame on a huge list), which would
        // leave the follow a row or two short — visible as the last rows still
        // being cut off after an append. Following the tail is exactly the case
        // that has to pay for the exact answer.
        scrollOffset = settledMaxOffset
        // Offsets alone can't detect an advance: a list shorter than its
        // viewport appends at offset 0 forever, and the cursor must still
        // chase its tail.
        let tailAdvanced = scrollOffset != offsetBefore || itemCount != bottomFollowItemCount
        bottomFollowItemCount = itemCount
        guard tailAdvanced else { return }
        // The tail sits on a whole-row boundary, so any line-granularity clip
        // carried from the previous top row no longer describes anything.
        scrollTopClipLines = 0
        // `selectableIndices` is empty for an all-content list, meaning "every
        // row" — the same fallback the End key uses.
        focusedIndex = selectableIndices.max() ?? max(0, itemCount - 1)
    }

    /// Drops the row-hold memo, so re-designating the same row later adopts it
    /// afresh rather than reusing a screen line chosen against a viewport and
    /// dataset that no longer exist.
    private func forgetRowAnchor() {
        anchorHeldKey = nil
        anchorHeldOrdinal = nil
    }

    /// Holds a bound `.anchorPosition(.row(id))` in place: adjusts
    /// ``scrollOffset`` so the anchored row keeps the screen position it had
    /// when adopted, as rows are inserted or removed around it.
    ///
    /// A no-op unless a `.row` anchor is bound to a row that exists in this
    /// list, so a list without `.anchorPosition` (every existing List/Table) is
    /// wholly unaffected. Render pass only (it mutates the persistent offset);
    /// call it after the id resolver and the viewport/extent are wired.
    ///
    /// The offset works in ROWS, so the hold does too: the anchored row is kept
    /// at the same row index from the top of the viewport, which for the common
    /// single-line rows is the same screen line. Adoption records that row when
    /// the designation changes; a later edit that forces the row off its line
    /// (an edge clamps the offset) re-anchors it where it landed rather than
    /// letting it spring back — matching the LazyVStack paths.
    func applyRowAnchorHold() {
        guard let anchor = anchorPositionBinding?.wrappedValue,
            case .row(let key) = anchor,
            let value = key.base as? SelectionValue,
            let ordinal = resolveAnchorOrdinal(key: key, value: value)
        else {
            anchorHeldKey = nil
            anchorHeldOrdinal = nil
            return
        }
        // A row held mid-list shows BOTH "N more above/below" indicators, and
        // `viewportHeight` reserved only the above one. Reserve the below one
        // too (unless a scrollbar draws no indicator lines) so a row revealed
        // from off-screen lands clear of the bottom indicator rather than one
        // line under it. An already-visible row's line is ≤ this, so adopting
        // it is unaffected.
        let lastRow = lastHoldableRow(for: ordinal)
        func held(landingAt row: Int) -> Int { min(max(row, 0), lastRow) }
        if anchorHeldKey != key {
            anchorHeldKey = key
            anchorHeldRow = held(landingAt: ordinal - scrollOffset)
        }
        // The viewport can shrink between frames as indicators appear; keep the
        // held line inside it.
        anchorHeldRow = min(anchorHeldRow, lastRow)
        let desired = ordinal - anchorHeldRow
        // Clamped against the bound at the DESTINATION: `maxOffset` early-outs
        // to a cheap lower bound for offsets that cannot reach the tail, and a
        // hold that jumps a long way down — designating a row far below the
        // current viewport — would be clamped to it and still leave the
        // anchored row short of view.
        let clamped = min(max(desired, 0), resolvedMaxOffset(reaching: desired))
        if clamped != desired { anchorHeldRow = held(landingAt: ordinal - clamped) }
        scrollOffset = clamped
        // Holding pins the row on a whole-row boundary; any line-granularity
        // sub-row clip on the old top row no longer applies.
        scrollTopClipLines = 0
    }

    /// The lowest screen ROW the anchored row may be held at: how many whole
    /// rows fit above it, counting real heights up from it.
    ///
    /// ``viewportHeight`` cannot answer this. A `List` finalises it to a
    /// visible-ROW count only AFTER the window is built, so when the hold runs
    /// it is still the provisional LINE count — and over multi-line rows those
    /// differ by a factor of the row height, so the clamp admitted row
    /// positions far below the fold and the "held" row landed off screen. The
    /// `Table` twin escapes it only because its own count is offset-independent.
    ///
    /// Walking real heights up from the anchored row asks the question
    /// directly, needs no convention from the caller, and costs O(viewport) on
    /// rows this frame renders anyway — they are precisely the window the hold
    /// is about to produce, and a `List`'s row-height closure is lazy and
    /// memoised.
    ///
    /// Falls back to the line arithmetic when there are no row heights to walk:
    /// a single-line `Table` (where rows and lines are the same thing anyway)
    /// and the handler's own unit tests, which set no content height.
    private func lastHoldableRow(for ordinal: Int) -> Int {
        guard let rowHeight, contentHeight != nil else {
            return max(0, viewportHeight - (showsScrollbar ? 1 : 2))
        }
        let budget = rowLineBudget
        var used = max(1, rowHeight(ordinal))
        var rows = 0
        var index = ordinal - 1
        while index >= 0, used + max(1, rowHeight(index)) <= budget {
            used += max(1, rowHeight(index))
            rows += 1
            index -= 1
        }
        return rows
    }

    /// The held anchor row's current ordinal, via an O(1) memo (the key usually
    /// stays put frame to frame) falling back to the O(total) ``index(of:)``
    /// scan only when the data around it actually shifted.
    private func resolveAnchorOrdinal(key: AnyHashable, value: SelectionValue) -> Int? {
        if key == anchorHeldKey, let memo = anchorHeldOrdinal,
            memo < itemCount, id(at: memo) == value
        {
            return memo
        }
        let ordinal = index(of: value)
        anchorHeldOrdinal = ordinal
        return ordinal
    }
}
