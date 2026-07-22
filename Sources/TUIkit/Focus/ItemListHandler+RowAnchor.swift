//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+RowAnchor.swift
//
//  The List/Table visual row-anchor hold: a bound `.anchorPosition(.row(id))`
//  (set directly, or via the §1.2 selection shadow-switch) pins that row, so
//  the scroll offset adjusts to keep it on its screen line as rows are inserted
//  or removed around it — the counterpart of the LazyVStack windowed paths'
//  `offsetHoldingDesignatedRow`, expressed in the list's row-based offset.
//
//  Created by Wade Tregaskis
//  License: MIT

extension ItemListHandler {

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
        let lastRow = max(0, viewportHeight - (showsScrollbar ? 1 : 2))
        func held(landingAt row: Int) -> Int { min(max(row, 0), lastRow) }
        if anchorHeldKey != key {
            anchorHeldKey = key
            anchorHeldRow = held(landingAt: ordinal - scrollOffset)
        }
        // The viewport can shrink between frames as indicators appear; keep the
        // held line inside it.
        anchorHeldRow = min(anchorHeldRow, lastRow)
        let desired = ordinal - anchorHeldRow
        let clamped = min(max(desired, 0), maxOffset)
        if clamped != desired { anchorHeldRow = held(landingAt: ordinal - clamped) }
        scrollOffset = clamped
        // Holding pins the row on a whole-row boundary; any line-granularity
        // sub-row clip on the old top row no longer applies.
        scrollTopClipLines = 0
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
