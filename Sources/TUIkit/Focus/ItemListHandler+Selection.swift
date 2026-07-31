//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Selection.swift
//
//  `List`/`Table` selection: the macOS model (plain click = sole selection,
//  Shift = range from the anchor, Ctrl/Cmd = toggle), the `v` extend mode that
//  stands in for Shift+arrows where terminals strip the modifier, and the
//  anchor bookkeeping the two share. Split from ItemListHandler.swift purely
//  for length; it is the same type.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Selection Helpers

extension ItemListHandler {
    /// Enter/Space at the focused row. With an activation action set, Enter
    /// "opens" the row while Space remains the selection key (the
    /// file-browser convention); without one, both keep the original select
    /// behaviour. Either way the key is an *action*, so it ends extend mode.
    func handleSelectionKey(_ key: Key) {
        isExtendingSelection = false
        if key == .enter, let primaryAction, let id = id(at: focusedIndex) {
            primaryAction(id)
            return
        }
        toggleSelectionAtFocusedIndex()
        anchorOnSelection(at: focusedIndex)
    }

    /// The §1.2 shadow-switch: **selecting a row turns an EDGE anchor into a
    /// Row anchor** on that row, so a follow-the-log view stops chasing the
    /// tail and holds what the user just picked.
    ///
    /// Scoped exactly as the spec scopes it — "selecting a row shadow-switches
    /// **Top/Bottom** modes to Row" — and that is the whole scope: the declared
    /// anchor must name an edge. A declared Window has no edge policy to depart
    /// from, and its app asked for no anchoring at all, so selecting there must
    /// not silently start holding a row.
    ///
    /// It deliberately does NOT also require the view to be undeparted. That
    /// extra guard used to be here, and it made this the *first* switch away
    /// from an edge rather than a gesture the user can reach for: once a scroll
    /// had released the view to `.window`, selecting a row did nothing, so there
    /// was no way back to row-anchoring at all. **Re-selection IS the restore**
    /// (owner decision, 2026-07-31, `Documentation/Scroll-anchoring.md` §3.1) —
    /// which requires that it work precisely when the view has departed, since
    /// that is the only time there is anything to restore. The rationale the old
    /// guard carried — "the user never asked for anchoring" — is the *declared
    /// Window* case, and that is still excluded below.
    ///
    /// A code-set `.top`/`.bottom` is overwritten too, on the same reading of
    /// the spec: an app that programmatically re-asserted "follow the log" and a
    /// user who then picks a row want the same thing — stop chasing the tail and
    /// hold this.
    ///
    /// The id is erased through `AnyHashable`, which preserves the base value —
    /// so it round-trips back to the app's own `ID`. If the app bound a
    /// *differently typed* `ScrollAnchor`, the modifier's setter drops the write
    /// rather than force-casting.
    func anchorOnSelection(at index: Int) {
        guard let binding = anchorPositionBinding,
            declaredAnchorMode == .top || declaredAnchorMode == .bottom,
            let id = id(at: index)
        else { return }
        binding.wrappedValue = .row(AnyHashable(id))
    }

    /// Extends the selection by moving the focus cursor `delta` rows (no
    /// wrap — extension clamps at the ends, like macOS) and selecting the
    /// whole span from the anchor to the new cursor. The first extension
    /// anchors at the pre-move cursor.
    func extendSelection(movingBy delta: Int) {
        if selectionAnchor == nil { selectionAnchor = focusedIndex }
        moveFocus(by: delta, wrap: false)
        applyAnchoredSpan()
    }

    /// Extends the selection to `index` (Home/End): the cursor jumps there
    /// and the span from the anchor is selected.
    func extendSelection(to index: Int) {
        if selectionAnchor == nil { selectionAnchor = focusedIndex }
        focusedIndex = max(0, min(itemCount - 1, index))
        ensureFocusedItemVisible()
        applyAnchoredSpan()
    }

    /// Replaces the selection with the span between ``selectionAnchor`` and
    /// the focus cursor, skipping non-selectable rows. Shared by shift-click
    /// and every keyboard extension gesture, so the two pivot around the same
    /// anchor. Both ends are clamped into the current data range first — the
    /// anchor persists across frames and the data can shrink underneath it
    /// (the inverted-range trap of the scroll-offset seam).
    func applyAnchoredSpan() {
        guard let anchor = selectionAnchor, itemCount > 0 else { return }
        let bound = itemCount - 1
        let anchorRow = max(0, min(bound, anchor))
        let cursorRow = max(0, min(bound, focusedIndex))
        var span = Set<SelectionValue>()
        for row in min(anchorRow, cursorRow)...max(anchorRow, cursorRow) {
            if let id = id(at: row) { span.insert(id) }
        }
        multiSelection?.wrappedValue = span
    }

    /// Selects every selectable row (Ctrl+A). The one deliberate O(total)
    /// id materialisation on the windowed `List` path — user-initiated,
    /// never per-frame.
    func selectAll() {
        guard selectionMode == .multi else { return }
        var all = Set<SelectionValue>()
        if selectableIndices.isEmpty {
            all.reserveCapacity(itemCount)
            for row in 0..<itemCount {
                if let id = id(at: row) { all.insert(id) }
            }
        } else {
            for row in selectableIndices {
                if let id = id(at: row) { all.insert(id) }
            }
        }
        multiSelection?.wrappedValue = all
    }

    /// Applies macOS mouse-selection semantics for a click on `index`:
    ///
    /// - plain click — the clicked row becomes the SOLE selection (and the
    ///   range anchor);
    /// - shift-click — selects the whole span from the anchor to the clicked
    ///   row (replacing the selection, exactly like Finder);
    /// - ctrl- or option-click — toggles the clicked row individually, like
    ///   command-click (terminals never report the command key, so both
    ///   reportable modifiers stand in for it).
    ///
    /// Single-selection mode keeps its existing click-to-toggle behaviour;
    /// the keyboard path (Space toggles at the focus cursor) is unchanged.
    func handleClickSelection(at index: Int, event: MouseEvent) {
        defer { anchorOnSelection(at: index) }
        focusedIndex = index
        // A click is a pointer gesture with its own selection semantics —
        // whatever it does, it ends keyboard extend mode.
        isExtendingSelection = false
        guard selectionMode == .multi else {
            toggleSelectionAtFocusedIndex()
            return
        }
        guard let clickedID = id(at: index) else { return }

        if event.shift, selectionAnchor != nil {
            // The anchor stays put, so successive shift-clicks re-pivot the
            // range around the original anchor (Finder behaviour) — and
            // keyboard extension continues from the same anchor.
            applyAnchoredSpan()
            return
        }

        if event.ctrl || event.meta {
            toggleSelectionAtFocusedIndex()
            return
        }

        multiSelection?.wrappedValue = [clickedID]
        selectionAnchor = index
    }

    /// Toggles the selection state at the focused index.
    func toggleSelectionAtFocusedIndex() {
        guard let itemID = id(at: focusedIndex) else { return }

        switch selectionMode {
        case .single:
            // Single selection: set to this item (or nil if already selected to deselect)
            if singleSelection?.wrappedValue == itemID {
                singleSelection?.wrappedValue = nil
            } else {
                singleSelection?.wrappedValue = itemID
            }

        case .multi:
            // Multi-selection: toggle this item in the set. A toggle moves
            // the range anchor (like command-click), so a following range
            // extension pivots around the toggled row.
            if var current = multiSelection?.wrappedValue {
                if current.contains(itemID) {
                    current.remove(itemID)
                } else {
                    current.insert(itemID)
                }
                multiSelection?.wrappedValue = current
            }
            selectionAnchor = focusedIndex
        }
    }

    /// Returns whether the item at the given index is selected.
    ///
    /// - Parameter index: The item index.
    /// - Returns: True if the item is selected.
    func isSelected(at index: Int) -> Bool {
        guard let itemID = id(at: index) else { return false }

        switch selectionMode {
        case .single:
            return singleSelection?.wrappedValue == itemID
        case .multi:
            return multiSelection?.wrappedValue.contains(itemID) ?? false
        }
    }

    /// Returns whether the item at the given index is focused.
    ///
    /// - Parameter index: The item index.
    /// - Returns: True if the item is focused.
    func isFocused(at index: Int) -> Bool {
        focusedIndex == index
    }
}
