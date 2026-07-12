//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Selection Mode

/// The selection mode for a list or table component.
public enum SelectionMode: Sendable {
    /// Single selection with optional binding (nil = no selection).
    case single

    /// Multi-selection with Set binding.
    case multi
}

// MARK: - Item List Handler

/// A reusable focus handler for list and table components.
///
/// `ItemListHandler` consolidates the navigation and selection logic shared by
/// `List` and `Table`. It handles:
/// - Focus registration with the focus manager
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single and multi-selection modes
/// - Scroll offset management to keep the focused item visible
/// - Disabled state (prevents focus when disabled)
///
/// ## Usage
///
/// ```swift
/// // In List's renderToBuffer:
/// let handler = ItemListHandler(
///     focusID: focusID,
///     itemCount: items.count,
///     viewportHeight: visibleRows,
///     selectionMode: .single,
///     canBeFocused: !isDisabled
/// )
/// handler.singleSelection = singleSelectionBinding
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Navigation Keys
///
/// | Key | Action |
/// |-----|--------|
/// | Up | Move focus up (wrap to end) |
/// | Down | Move focus down (wrap to start) |
/// | Home | Jump to first item |
/// | End | Jump to last item |
/// | PageUp | Move up by viewport height |
/// | PageDown | Move down by viewport height |
/// | Enter/Space | Toggle selection at focused index |
final class ItemListHandler<SelectionValue: Hashable>: Focusable, ScrollableOffsetState {
    /// The unique identifier for this focusable element.
    let focusID: String

    /// The total number of items in the list.
    ///
    /// Shrinking the count immediately re-bounds ``scrollOffset`` to the last
    /// item. This is the *viewport-independent* half of the scroll clamp, so
    /// it is safe on any pass — unlike ``clampScrollOffset()``, whose
    /// `maxOffset` depends on the offered viewport and is therefore gated to
    /// render passes by the owning views. Without it, a measure pass that
    /// syncs a freshly-shrunk count (rows removed by an async reload) leaves
    /// a scrolled-near-the-end offset pointing past the data, and range /
    /// `data[index]` math downstream traps.
    var itemCount: Int {
        didSet {
            let bound = max(0, itemCount - 1)
            if scrollOffset > bound {
                scrollOffset = bound
            }
        }
    }

    /// The number of visible items in the viewport.
    ///
    /// Callers set this to the number of rows that are *actually*
    /// shown at the current ``scrollOffset`` — i.e. the content
    /// area minus a line for each scroll indicator that is present
    /// (see ``contentHeight``). Every ``ScrollableOffsetState``
    /// predicate (``hasContentBelow``, ``visibleRange``,
    /// ``rowsBelow``, ``maxOffset``) is derived from it, so keeping
    /// it equal to the rows on screen is what makes the indicators
    /// line up exactly with the content area.
    var viewportHeight: Int

    /// How many rows a Shift-accelerated Up/Down moves the focus cursor. Set from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// moves one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

    /// The full height of the scrollable content area, in rows —
    /// the space available for visible rows *plus* whichever
    /// scroll indicators are showing.
    ///
    /// When set, ``ensureFocusedItemVisible()`` reserves room for
    /// the indicators so the focused row never lands on an
    /// indicator line. `nil` means the caller manages indicator
    /// reservation itself and ``viewportHeight`` is the literal
    /// visible-row count (the original behaviour, still used by the
    /// handler's own unit tests).
    var contentHeight: Int?

    /// A closure giving the height in lines of row `i`, for rows that can span
    /// multiple lines — `List` rows are arbitrary views and `Table` cells can
    /// wrap, so both wire this. `nil` (single-line tables, plus the handler's
    /// own unit tests) keeps the original uniform-height arithmetic. When set,
    /// ``ensureFocusedItemVisible()`` accumulates these so a tall focused row
    /// is fully revealed rather than partially scrolled off. It is a
    /// *closure*, not an array, so the owning view answers it lazily — only
    /// for the rows the scroll arithmetic actually touches (a viewport's
    /// worth, not every row) — which is what lets a tall table/list skip
    /// wrapping or rendering its off-screen rows.
    var rowHeight: ((Int) -> Int)?

    /// The largest valid scroll offset, in rows.
    ///
    /// With variable-height rows (``rowHeight`` set) the default
    /// `extent - viewportHeight` mixes units — the extent is rows but the
    /// provisional viewport is lines — capping the offset short of the true
    /// bottom (and letting the render-pass clamp scrub back a reveal that had
    /// correctly scrolled a tall focused row into view). Walk back from the
    /// last row instead, accumulating real heights: the answer is the
    /// smallest top row for which everything below fits the content area
    /// (reserving the "above" indicator's line whenever that top isn't row
    /// zero). O(viewport) closure calls, on rows the frame renders anyway.
    var maxOffset: Int {
        guard let rowHeight, let contentHeight, contentHeight > 0 else {
            return max(0, extent - viewportHeight)
        }
        // Every row is at least one line, so at most `contentHeight` rows fit:
        // the true bound is never below this floor. Until the viewport is
        // actually within reach of the tail, the floor is exact enough for
        // every consumer — the clamp can't bite (offset ≤ floor ≤ max) and the
        // scrollbar's denominator is off by at most a viewport — and returning
        // it early avoids materialising tail rows' heights every frame on
        // large lists.
        let floor = max(0, itemCount - contentHeight)
        guard scrollOffset >= floor else { return floor }
        var used = 0
        var top = itemCount
        while top > 0 {
            let budget = (top - 1 == 0) ? contentHeight : contentHeight - 1
            let height = max(1, rowHeight(top - 1))
            if used + height > budget { break }
            used += height
            top -= 1
        }
        return top
    }

    /// The row-activation action (``List``/``Table`` `.onRowActivate(_:)`):
    /// invoked with the focused row's id on Return/Enter, and by the owning
    /// view on double-click. When set, Enter ACTIVATES instead of toggling
    /// selection — Space still toggles — matching the file-browser convention
    /// (and AppKit's action/doubleAction split). `nil` keeps the original
    /// behaviour: Enter and Space both toggle selection.
    var primaryAction: ((SelectionValue) -> Void)?

    /// The selection mode (single or multi).
    let selectionMode: SelectionMode

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// The currently focused item index (keyboard cursor).
    var focusedIndex: Int = 0

    /// The anchor row for shift-click range selection (macOS semantics): the
    /// last row plainly clicked or modifier-toggled. A later shift-click
    /// selects the whole span between the anchor and the clicked row.
    var selectionAnchor: Int?

    /// The scroll offset (first visible item index).
    var scrollOffset: Int = 0

    /// How many LINES of the top visible row (``scrollOffset``) are scrolled
    /// off the top edge — the sub-row position that makes
    /// ``ScrollGranularity/line`` scrolling line-precise while
    /// ``scrollOffset`` / ``maxOffset`` / ``extent`` stay row-based (O(1) for
    /// any list size). Always `0` under ``ScrollGranularity/row``, for
    /// single-line rows, and at the very bottom (``maxOffset`` is the last
    /// row-aligned top). Clamped each render by ``clampTopClip()``.
    var scrollTopClipLines: Int = 0

    /// The scroll granularity, synced from `environment.scrollGranularity`
    /// during render (default ``ScrollGranularity/line``); read at event time
    /// by ``scrollFine(by:)``, when the environment is no longer reachable.
    var scrollGranularity: ScrollGranularity = .line

    /// Grab point within the thumb during a scrollbar drag (``ScrollableOffsetState``).
    var scrollbarDragGrab: Int?

    /// Held arrow/track auto-repeat action (``ScrollableOffsetState``).
    var scrollbarRepeat: ScrollbarRepeat?

    /// Wheel-chaining grace state (``ScrollableOffsetState``).
    var wheelEdgeHold = WheelEdgeHold()

    /// Binding for single selection mode (optional ID).
    var singleSelection: Binding<SelectionValue?>?

    /// Binding for multi-selection mode (Set of IDs).
    var multiSelection: Binding<Set<SelectionValue>>?

    /// Maps item indices to their IDs for selection management.
    ///
    /// Entries are `nil` for non-selectable rows (e.g. section headers/footers in List).
    ///
    /// Eager backing for the small/structured cases (Table, Sections, tests). A
    /// large flat windowed `List` leaves this empty and supplies ``idAt`` instead,
    /// so it never materialises an id per off-screen row. Read ids through
    /// ``id(at:)`` / ``index(of:)``, never this array directly.
    var itemIDs: [SelectionValue?] = []

    /// Lazy id resolver used in place of ``itemIDs`` by the windowed `List` path.
    ///
    /// When set, ``id(at:)`` resolves a row's id on demand (only the visible
    /// window and the focused row are ever asked), so a 50k-row list pays O(1)
    /// for handler setup instead of building a 50k-entry ``itemIDs``. `nil` for
    /// the eager paths, which use ``itemIDs``.
    var idAt: ((Int) -> SelectionValue?)?

    /// The set of indices that can be selected and focused.
    ///
    /// Headers and footers have non-selectable indices (not in this set).
    /// Only content rows have indices in `selectableIndices`.
    /// When empty, all items are considered selectable (backward compatibility) —
    /// which is exactly what the all-content windowed `List` wants, so it leaves
    /// this empty rather than allocating a full `Set(0..<count)`.
    var selectableIndices: Set<Int> = []

    /// Creates an item list handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - itemCount: The total number of items.
    ///   - viewportHeight: The number of visible items.
    ///   - selectionMode: Single or multi-selection mode.
    ///   - canBeFocused: Whether this element can receive focus.
    init(
        focusID: String,
        itemCount: Int,
        viewportHeight: Int,
        selectionMode: SelectionMode,
        canBeFocused: Bool = true
    ) {
        self.focusID = focusID
        self.itemCount = itemCount
        self.viewportHeight = viewportHeight
        self.selectionMode = selectionMode
        self.canBeFocused = canBeFocused
    }
}

// MARK: - Item ID Resolution

extension ItemListHandler {
    /// The id of the row at `index`, or `nil` for a non-selectable / out-of-range
    /// row. Resolves through the lazy ``idAt`` when present (windowed `List`),
    /// else the eager ``itemIDs`` (Table / Sections). O(1) either way — only the
    /// visible window and the focused row are ever asked.
    func id(at index: Int) -> SelectionValue? {
        guard index >= 0 else { return nil }
        if let idAt {
            guard index < itemCount else { return nil }
            return idAt(index)
        }
        guard index < itemIDs.count else { return nil }
        return itemIDs[index]
    }

    /// The index of the row whose id equals `id`, or `nil`.
    ///
    /// Backed by ``itemIDs`` (O(total) hash-free scan) for the eager paths. The
    /// windowed path scans `0..<itemCount` through ``idAt`` — O(total) too, but
    /// only ever invoked on focus-lost under an active selection, never per
    /// frame, so it stays off the hot path.
    func index(of id: SelectionValue) -> Int? {
        if let idAt {
            for index in 0..<itemCount where idAt(index) == id { return index }
            return nil
        }
        return itemIDs.firstIndex(of: id)
    }
}

// MARK: - Focus Lifecycle

extension ItemListHandler {
    func onFocusLost() {
        // When focus is lost, reset focused index to the first selected item
        // (if any) so that when focus returns, the user sees the selection.
        switch selectionMode {
        case .single:
            if let selection = singleSelection?.wrappedValue,
                let index = index(of: selection)
            {
                focusedIndex = index
            }
        case .multi:
            if let selection = multiSelection?.wrappedValue,
                let firstSelected = selection.first,
                let index = index(of: firstSelected)
            {
                focusedIndex = index
            }
        }

        // Ensure scroll offset keeps focused item visible
        ensureFocusedItemVisible()
    }

    func onFocusReceived() {
        // Ensure the focused item is visible when focus is received
        ensureFocusedItemVisible()
    }
}

// MARK: - Key Event Handling

extension ItemListHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard itemCount > 0 else { return false }

        switch event.key {
        case .up:
            // A plain Up moves one row and wraps; Shift jumps by the multiplier
            // and clamps at the top (an accelerated move, not a cycle).
            if event.shift {
                moveFocus(by: -max(1, shiftStepMultiplier), wrap: false)
            } else {
                moveFocus(by: -1, wrap: true)
            }
            return true

        case .down:
            if event.shift {
                moveFocus(by: max(1, shiftStepMultiplier), wrap: false)
            } else {
                moveFocus(by: 1, wrap: true)
            }
            return true

        case .home:
            if selectableIndices.isEmpty {
                focusedIndex = 0
            } else if let firstSelectable = selectableIndices.min() {
                focusedIndex = firstSelectable
            } else {
                return false
            }
            ensureFocusedItemVisible()
            return true

        case .end:
            if selectableIndices.isEmpty {
                focusedIndex = itemCount - 1
            } else if let lastSelectable = selectableIndices.max() {
                focusedIndex = lastSelectable
            } else {
                return false
            }
            ensureFocusedItemVisible()
            return true

        case .pageUp:
            moveFocus(by: -viewportHeight, wrap: false)
            return true

        case .pageDown:
            moveFocus(by: viewportHeight, wrap: false)
            return true

        case .enter, .space:
            handleSelectionKey(event.key)
            return true

        default:
            return false
        }
    }
}

// MARK: - Navigation Helpers

extension ItemListHandler {
    /// Moves focus by the given delta, optionally wrapping around.
    ///
    /// - Parameters:
    ///   - delta: The number of items to move (negative = up, positive = down).
    ///   - wrap: Whether to wrap around at boundaries.
    func moveFocus(by delta: Int, wrap: Bool) {
        guard itemCount > 0, delta != 0 else { return }

        var newIndex = focusedIndex + delta

        // If selectableIndices is populated, skip non-selectable rows
        if !selectableIndices.isEmpty {
            let step = delta > 0 ? 1 : -1
            let maxAttempts = itemCount + 1
            var attempts = 0

            // Keep moving until we find a selectable index or hit max attempts
            while attempts < maxAttempts {
                if wrap {
                    // Wrap around: -1 becomes last, count becomes 0
                    newIndex = ((newIndex % itemCount) + itemCount) % itemCount
                } else {
                    // If the jump overshoots a boundary (common for Page Up /
                    // Page Down within one page of the top/bottom), land on the
                    // nearest selectable item AT that boundary rather than
                    // refusing to move. The previous `return` here made
                    // Page Up/Down "stop short" — it did nothing whenever the
                    // jump would pass the first/last item instead of clamping
                    // to it.
                    if newIndex < 0 {
                        newIndex = selectableIndices.min() ?? 0
                        break
                    }
                    if newIndex >= itemCount {
                        newIndex = selectableIndices.max() ?? (itemCount - 1)
                        break
                    }
                }

                // Check if this index is selectable
                if selectableIndices.contains(newIndex) {
                    break
                }

                newIndex += step
                attempts += 1
            }

            // If we couldn't find a selectable index, don't move
            if attempts >= maxAttempts {
                return
            }
        } else {
            // Backward compatibility: all items are selectable
            if wrap {
                // Wrap around: -1 becomes last, count becomes 0
                newIndex = ((newIndex % itemCount) + itemCount) % itemCount
            } else {
                // Clamp to valid range
                newIndex = max(0, min(itemCount - 1, newIndex))
            }
        }

        focusedIndex = newIndex
        ensureFocusedItemVisible()
    }

    /// The extent that ``ScrollableOffsetState`` measures
    /// against. For ``ItemListHandler`` that's
    /// ``itemCount`` — total rows.
    ///
    /// (``scroll(by:)`` and ``clampScrollOffset()`` are
    /// supplied by the ``ScrollableOffsetState`` extension
    /// using this extent. Wheel-scroll routing is similarly
    /// handled by the protocol's ``handleWheelEvent(_:
    /// linesPerTick:)``. See the protocol comment for why
    /// these moved out of this class.)
    var extent: Int { itemCount }

    /// The wheel/arrow step (``ScrollableOffsetState`` requirement). Under
    /// ``ScrollGranularity/line`` with multi-line rows, each step moves one
    /// terminal LINE: the top clip advances within the top row and rolls into
    /// ``scrollOffset`` at row boundaries, so a five-line row scrolls in five
    /// smooth steps instead of one jump. Row granularity — or uniform
    /// single-line rows, where the two coincide — keeps the protocol's
    /// row-stepping default. Only the touched rows' heights are queried, so
    /// the cost is O(delta), independent of list size.
    @discardableResult
    func scrollFine(by delta: Int) -> Bool {
        guard scrollGranularity == .line, let rowHeight else {
            let before = scrollOffset
            scroll(by: delta)
            return scrollOffset != before
        }
        guard delta != 0, viewportHeight > 0, maxOffset > 0 else { return false }
        var moved = false
        var remaining = delta
        while remaining > 0 {  // Scrolling down.
            // maxOffset is recomputed per step: far from the tail it
            // short-circuits to a cheap floor (an UNDER-estimate — stopping
            // there would strand the scroll short of the true bottom), and
            // only within reach of the tail does it do the exact walk.
            if scrollOffset >= maxOffset {
                // The bottom: the last row-aligned top; no clip past it.
                scrollTopClipLines = 0
                break
            }
            let topHeight = max(1, rowHeight(scrollOffset))
            if scrollTopClipLines + 1 < topHeight {
                scrollTopClipLines += 1
            } else {
                scrollOffset += 1
                scrollTopClipLines = 0
            }
            moved = true
            remaining -= 1
        }
        while remaining < 0 {  // Scrolling up.
            if scrollTopClipLines > 0 {
                scrollTopClipLines -= 1
            } else if scrollOffset > 0 {
                scrollOffset -= 1
                scrollTopClipLines = max(0, max(1, rowHeight(scrollOffset)) - 1)
            } else {
                break
            }
            moved = true
            remaining += 1
        }
        return moved
    }

    /// Clamps ``scrollTopClipLines`` to its valid range for the current rows
    /// and granularity: zero under ``ScrollGranularity/row``, zero at the
    /// bottom (``maxOffset``), and always inside the top row's height. Called
    /// alongside ``ScrollableOffsetState/clampScrollOffset()`` on the render
    /// pass.
    func clampTopClip() {
        guard scrollTopClipLines > 0 else { return }
        guard scrollGranularity == .line, let rowHeight else {
            scrollTopClipLines = 0
            return
        }
        if scrollOffset >= maxOffset {
            scrollTopClipLines = 0
            return
        }
        scrollTopClipLines = min(scrollTopClipLines, max(0, max(1, rowHeight(scrollOffset)) - 1))
    }

    /// Adjusts scroll offset to keep the focused item visible.
    ///
    /// When ``contentHeight`` is set the scroll-down target reserves
    /// a line for the scroll indicators that will be present, so the
    /// focused row never ends up hidden behind a "N more below"
    /// indicator at the top→middle transition. ``clampScrollOffset()``
    /// then snaps the offset back to the true bottom near the end,
    /// where only one indicator shows and one extra row fits.
    ///
    /// With ``contentHeight`` `nil` the original literal-viewport
    /// arithmetic is used (the caller has already reserved indicator
    /// space, and the handler's unit tests rely on this form).
    func ensureFocusedItemVisible() {
        guard let contentHeight else {
            ensureFocusedItemVisibleLegacy()
            return
        }
        guard contentHeight > 0 else { return }

        // Scroll up: the focused row becomes the first visible row.
        // When it isn't the very first item an "above" indicator
        // appears, but the focused row is still the first *row* shown
        // (just below the indicator), so it stays visible. A focused
        // row must be FULLY visible, so any line-granularity top clip
        // on it is cleared too.
        if focusedIndex < scrollOffset {
            scrollOffset = focusedIndex
            scrollTopClipLines = 0
        } else if focusedIndex == scrollOffset, scrollTopClipLines > 0 {
            scrollTopClipLines = 0
        }

        // Scroll down: keep the focused row within the visible rows. The
        // conservative both-indicators budget (contentHeight - 2) keeps the
        // focused row off an indicator line; clampScrollOffset() pulls the offset
        // back to the true bottom near the end.
        if let rowHeight, focusedIndex < itemCount {
            // Multi-line rows: pull the top down only as far as needed for the
            // focused row to fit as the last visible row, accumulating heights.
            // The top row's height counts net of any line-granularity clip.
            let budget = max(1, contentHeight - 2)
            var top = focusedIndex
            var used = rowHeight(focusedIndex)
            while top > 0, used + rowHeight(top - 1) <= budget {
                used += rowHeight(top - 1)
                top -= 1
            }
            // A top clip only frees MORE lines below, so it can never hide a
            // focused row this arithmetic says fits — reset it only when the
            // reveal actually repositions the top.
            if scrollOffset < top {
                scrollOffset = top
                scrollTopClipLines = 0
            }
        } else {
            let safeRows =
                itemCount <= contentHeight
                ? contentHeight
                : max(1, contentHeight - 2)
            if focusedIndex >= scrollOffset + safeRows {
                scrollOffset = focusedIndex - safeRows + 1
                scrollTopClipLines = 0
            }
        }

        clampScrollOffset()
        clampTopClip()
    }

    /// The pre-dynamic-indicator scroll-into-view arithmetic, kept
    /// for callers (and tests) that set ``viewportHeight`` to the
    /// literal visible-row count and do their own indicator
    /// reservation.
    private func ensureFocusedItemVisibleLegacy() {
        guard viewportHeight > 0 else { return }

        // If focused item is above the viewport, scroll up
        if focusedIndex < scrollOffset {
            scrollOffset = focusedIndex
        }

        // If focused item is below the viewport, scroll down
        if focusedIndex >= scrollOffset + viewportHeight {
            scrollOffset = focusedIndex - viewportHeight + 1
        }

        // Clamp scroll offset to valid range
        let maxOffset = max(0, itemCount - viewportHeight)
        scrollOffset = max(0, min(maxOffset, scrollOffset))
    }
}

// MARK: - Selection Helpers

extension ItemListHandler {
    /// Enter/Space at the focused row. With an activation action set, Enter
    /// "opens" the row while Space remains the selection key (the
    /// file-browser convention); without one, both keep the original select
    /// behaviour.
    func handleSelectionKey(_ key: Key) {
        if key == .enter, let primaryAction, let id = id(at: focusedIndex) {
            primaryAction(id)
            return
        }
        toggleSelectionAtFocusedIndex()
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
        focusedIndex = index
        guard selectionMode == .multi else {
            toggleSelectionAtFocusedIndex()
            return
        }
        guard let clickedID = id(at: index) else { return }

        if event.shift, let anchor = selectionAnchor {
            var range = Set<SelectionValue>()
            for row in min(anchor, index)...max(anchor, index) {
                if let id = id(at: row) { range.insert(id) }
            }
            multiSelection?.wrappedValue = range
            // The anchor stays put, so successive shift-clicks re-pivot the
            // range around the original anchor (Finder behaviour).
            return
        }

        if event.ctrl || event.meta {
            toggleSelectionAtFocusedIndex()
            selectionAnchor = index
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
            // Multi-selection: toggle this item in the set
            if var current = multiSelection?.wrappedValue {
                if current.contains(itemID) {
                    current.remove(itemID)
                } else {
                    current.insert(itemID)
                }
                multiSelection?.wrappedValue = current
            }
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

// (``hasContentAbove`` / ``hasContentBelow`` / ``visibleRange``
//  are provided by the ``ScrollableOffsetState`` extension and
//  read the ``extent`` defined above. The list-specific
//  arithmetic lives in ``ensureFocusedItemVisible()``.)
