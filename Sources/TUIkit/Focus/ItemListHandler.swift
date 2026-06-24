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
    var itemCount: Int

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

    /// A closure giving the height in lines of row `i`, for a table whose cells can
    /// span multiple lines — or `nil` when every row is exactly one line (a `List`,
    /// and single-line tables). When set, ``ensureFocusedItemVisible()`` accumulates
    /// these so a tall focused row is fully revealed rather than partially scrolled
    /// off. It is a *closure*, not an array, so the owning view answers it lazily —
    /// only for the rows the scroll arithmetic actually touches (a viewport's worth,
    /// not every row) — which is what lets a tall table skip wrapping its off-screen
    /// rows. A `nil` value leaves the original uniform-height behaviour (and `List`)
    /// completely unchanged.
    var rowHeight: ((Int) -> Int)?

    /// The selection mode (single or multi).
    let selectionMode: SelectionMode

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// The currently focused item index (keyboard cursor).
    var focusedIndex: Int = 0

    /// The scroll offset (first visible item index).
    var scrollOffset: Int = 0

    /// Grab point within the thumb during a scrollbar drag (``ScrollableOffsetState``).
    var scrollbarDragGrab: Int?

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
            moveFocus(by: -1, wrap: true)
            return true

        case .down:
            moveFocus(by: 1, wrap: true)
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
            toggleSelectionAtFocusedIndex()
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
        // (just below the indicator), so it stays visible.
        if focusedIndex < scrollOffset {
            scrollOffset = focusedIndex
        }

        // Scroll down: keep the focused row within the visible rows. The
        // conservative both-indicators budget (contentHeight - 2) keeps the
        // focused row off an indicator line; clampScrollOffset() pulls the offset
        // back to the true bottom near the end.
        if let rowHeight, focusedIndex < itemCount {
            // Multi-line rows: pull the top down only as far as needed for the
            // focused row to fit as the last visible row, accumulating heights.
            let budget = max(1, contentHeight - 2)
            var top = focusedIndex
            var used = rowHeight(focusedIndex)
            while top > 0, used + rowHeight(top - 1) <= budget {
                used += rowHeight(top - 1)
                top -= 1
            }
            if scrollOffset < top {
                scrollOffset = top
            }
        } else {
            let safeRows =
                itemCount <= contentHeight
                ? contentHeight
                : max(1, contentHeight - 2)
            if focusedIndex >= scrollOffset + safeRows {
                scrollOffset = focusedIndex - safeRows + 1
            }
        }

        clampScrollOffset()
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
