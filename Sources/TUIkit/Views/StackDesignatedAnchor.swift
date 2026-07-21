//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackDesignatedAnchor.swift
//
//  `.anchorPosition(.row(id))` names a row and asks the viewport to HOLD it:
//  as rows are inserted or removed around it, the scroll position moves so
//  that the named row keeps its place on screen (Scroll-anchoring.md §1.2).
//
//  The anchored walk (§5e) gets this structurally — it lays rows out relative
//  to the anchor, so the anchor's screen position is the coordinate system.
//  The other two paths place rows at ABSOLUTE content y (`ordinal * pitch`
//  for uniform rows, walked slot y for the exact walk), so an edit above the
//  row genuinely moves it, and holding it means correcting the OFFSET instead.
//
//  That correction has to reach the ScrollView or the next frame would slice
//  the old window: it travels back up the existing Stage-6 reply channel as
//  `seekResolvedOffset`, the same way a `scrollTo` seek reports the offset it
//  rendered at. A designation is, in effect, a seek re-issued every frame.
//
//  Created by Wade Tregaskis

import TUIkitCore

/// The screen line a designated row is being held on, and the offset that
/// keeps it there. Shared by the uniform and exact paths so the adoption
/// rule cannot drift between them.
extension StackWindowState {

    /// The offset that keeps the designated row on its held screen line, or
    /// `nil` when nothing is designated (the caller then leaves the window
    /// alone).
    ///
    /// - Parameters:
    ///   - key: the designated row's stable `ForEach` key.
    ///   - rowY: its top in absolute content space.
    ///   - rowHeight: its extent, so the ADOPTION clamp can hold a row that is
    ///     partly off-screen at the edge it is nearest.
    ///   - window: the window as published (pre-correction).
    ///   - totalHeight: the content extent, for the scrollable-range clamp.
    ///
    /// The screen line is adopted ONCE, on the frame the designation changes,
    /// and held from then on. Re-deriving it every frame would defeat the
    /// purpose: the line would track the offset instead of the offset tracking
    /// the line, and the row would drift exactly as it does with no anchor.
    func offsetHoldingDesignatedRow(
        key: String, rowY: Int, rowHeight: Int,
        window: ScrollContentWindow, totalHeight: Int
    ) -> Int {
        // Adoption clamps into the viewport: a row designated while off-screen
        // has no meaningful line to hold, and holding an out-of-range one
        // pins the window somewhere the row isn't — a blank viewport. Clamped,
        // designating an off-screen row brings it into view by the minimum
        // movement, which is also what `scrollTo(_:anchor: nil)` does.
        if designatedAnchorKey != key {
            designatedAnchorKey = key
            // Reserve the indicator lines: landing the row exactly under a
            // "N more below" indicator places it correctly and shows nothing.
            let lastLine = max(
                window.edgeInset, window.viewportHeight - rowHeight - window.edgeInset)
            anchorHeldScreenLine = min(max(rowY - window.offset, window.edgeInset), lastLine)
        }
        // The hold is best-effort at the ends: near the tail the offset runs
        // out of room before the line is reached, and the row rides up the
        // last screenful. That is the sticky-edge behaviour, not a failure —
        // there is no offset that would place it lower.
        let maxOffset = max(0, totalHeight - window.viewportHeight)
        return min(max(rowY - anchorHeldScreenLine, 0), maxOffset)
    }

    /// Forgets any adopted line, so the next designation adopts afresh.
    /// Called on the frame no row is designated — otherwise re-designating the
    /// same row later would silently reuse a line adopted against a viewport
    /// and dataset that no longer exist.
    func clearDesignatedAnchor() {
        designatedAnchorKey = nil
        anchorHeldScreenLine = 0
    }
}

/// The designated row key in scope, if the effective anchor mode names one.
/// `nil` covers both "no binding" and "bound to an edge or to Window" — only
/// `.row(id)` designates.
func designatedRowKey(context: RenderContext) -> String? {
    let mode = ScrollAnchorMode.effective(
        boundAnchor: context.environment.anchorPosition?.wrappedValue,
        defaultScrollAnchor: context.environment.defaultScrollAnchor)
    guard mode == .row else { return nil }
    return context.environment.anchorPosition?.wrappedValue?.rowKey
}

extension _VStackCore {
    /// Re-aims a window so the designated row keeps its screen line, for the
    /// paths that place rows at absolute content y. Returns the window
    /// unchanged (and a `nil` offset to report) when nothing is designated or
    /// the key names no row here.
    ///
    /// `rowY` is a closure so each path supplies its own geometry: arithmetic
    /// for uniform rows, the walked slot's y for the exact path.
    func holdingDesignatedRow(
        in window: ScrollContentWindow, children: ChildViewCollection,
        state: StackWindowState, rowY: (Int) -> Int, rowHeight: Int,
        totalHeight: Int, context: RenderContext
    ) -> (window: ScrollContentWindow, resolved: Int?) {
        guard let key = designatedRowKey(context: context) else {
            state.clearDesignatedAnchor()
            return (window, nil)
        }
        guard let ordinal = resolveOrdinal(forKey: key, children: children, state: state) else {
            // An unknown id is a no-op, as it is for `scrollTo` — the row may
            // simply not have been inserted yet.
            return (window, nil)
        }
        var window = window
        let offset = state.offsetHoldingDesignatedRow(
            key: key, rowY: rowY(ordinal), rowHeight: rowHeight,
            window: window, totalHeight: totalHeight)
        window.offset = offset
        return (window, offset)
    }

    /// The exact full walk's designation: same rule, but the geometry comes
    /// from the walked slots (which carry every row's true y and height)
    /// rather than from arithmetic.
    func holdDesignatedRow(
        slots: [RowSlot], window: inout ScrollContentWindow, context: RenderContext
    ) {
        let state = uniformWindowState(context: context)
        guard let key = designatedRowKey(context: context) else {
            state.clearDesignatedAnchor()
            return
        }
        guard let index = slots.firstIndex(where: { $0.child.identityChildKey == key })
        else { return }
        let offset = state.offsetHoldingDesignatedRow(
            key: key, rowY: slots[index].y, rowHeight: slots[index].height,
            window: window, totalHeight: slots.last.map { $0.y + $0.height } ?? 0)
        window.offset = offset
        window.reply?.seekResolvedOffset = offset
    }
}
