//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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
///
/// Multi-selection (`Set`-bound) lists additionally follow the macOS
/// keyboard-selection model, adapted to what terminals can deliver:
///
/// | Key | Action |
/// |-----|--------|
/// | Shift+Up/Down/Home/End/PageUp/PageDown | Extend the selection from the anchor (where the terminal reports Shift — Terminal.app strips it from Up/Down) |
/// | Ctrl+V | Toggle extend mode: plain movement keys extend the selection, in ANY terminal |
/// | Ctrl+A | Select all |
///
/// Every chord above is rebindable — see ``RowShortcuts`` — and a reorderable
/// list adds Ctrl+R to pick the focused row up, after which the movement keys
/// move its landing slot and Return/Escape place it or put it back.
/// | Escape | Exit extend mode, else clear a non-empty selection; otherwise falls through (page navigation is never blocked) |
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

    /// The chord → action map this list's keys dispatch through, resolved from
    /// `environment.rowShortcuts` during render (see ``RowShortcuts``). Captured
    /// rather than read live: a key event arrives between renders, with no
    /// environment to consult.
    var shortcuts: RowShortcutLookup = .default

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

    /// Whether the owning view draws a scrollbar instead of the "N more
    /// above/below" text indicators.
    ///
    /// A scrollbar marks the off-screen rows in its own gutter column, so the
    /// rows fill the *whole* ``contentHeight`` — there is no reserved indicator
    /// line. The scroll-bound arithmetic (``maxOffset``,
    /// ``ensureFocusedItemVisible()``) otherwise reserves a line for an
    /// indicator that a scrollbar list never draws, which over-scrolls the
    /// bottom by one row and leaves a blank remainder (one blank line per
    /// row-height). With this set, that reservation is skipped.
    var showsScrollbar = false

    /// Whether this frame's render spends content lines on "▲/▼ N more"
    /// indicators. Synced by the owning view, because only it knows: a `List`
    /// swaps its indicators for a scrollbar, while a `Table` draws both (the bar
    /// takes a column, the indicators take lines). The reveal budgets rows
    /// against `contentHeight` MINUS these — see ``rowLineBudget``.
    var drawsScrollIndicators = true

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

    /// How eagerly the viewport follows the focus cursor — synced from the
    /// environment each render (see ``ScrollFollowMargin``). With the default
    /// `.none`, ``ensureFocusedItemVisible()`` scrolls only when the cursor
    /// reaches a viewport edge; a margin starts the scroll early so that many
    /// lines/rows of context stay visible beyond the cursor.
    var followMargin: ScrollFollowMargin = .none

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
            // Reserve the "above" indicator's line only when there IS one — a
            // scrollbar draws no such line, so its rows fill the full height.
            let budget =
                (showsScrollbar || top - 1 == 0) ? contentHeight : contentHeight - 1
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

    /// The `.onDelete(perform:)` action from an editable `ForEach`, if any:
    /// pressing Delete / Backspace on the focused row invokes it with that
    /// row's data offset (its focus index, in the all-content list this is only
    /// wired for). `nil` keeps Delete inert so it falls through to page
    /// navigation. See ``handleKeyEvent(_:)`` and ``DynamicViewContentActions``.
    var onDelete: ((IndexSet) -> Void)?

    /// The `.onMove(perform:)` reorder action from an editable `ForEach`, if
    /// any: dragging a row with the mouse commits through it on release with
    /// `(source offset, destination offset)`. `nil` makes rows non-draggable.
    /// See ``RowReorder`` and `_ListCore`'s mouse handler.
    var onMove: ((IndexSet, Int) -> Void)?

    /// The state of an in-flight mouse reorder drag, or `nil`. See
    /// ``ItemListHandler/dragReorder(toContentY:)`` for the state machine.
    var reorder: RowReorder?

    /// One in-flight row-reorder drag.
    struct RowReorder: Equatable {
        /// The data offset of the row picked up on press.
        var grabbedOffset: Int
        /// Where that row sits *now*. Only ``RowReorderFeedback/live`` moves it
        /// mid-drag; the other modes leave the data alone until the drop, so
        /// this stays equal to ``grabbedOffset`` throughout.
        var currentOffset: Int
        /// Whether the cursor has actually moved since the press — a plain
        /// press/release with no motion is a click (selection), not a reorder.
        var active: Bool

        /// Where the row would land if released now, or `nil` when the cursor is
        /// off the rows entirely. `.dimmed` and `.cursor` show this slot — as a
        /// copy of the row and as a gap respectively — and `nil` is what makes a
        /// drag off the list read as "release here and nothing moves".
        var targetOffset: Int?

        /// Every row in hand, by data offset — the whole selection when the
        /// grabbed row was part of one, otherwise just that row.
        ///
        /// Disjoint sets are allowed and stay disjoint until the drop: rows 2,
        /// 4 and 5 travel as three rows and land as one block. Consolidating
        /// earlier would be a data change the user has not asked for yet, and
        /// could not be undone by a cancel (one `onMove` cannot scatter a block
        /// back to disjoint places).
        var held: IndexSet

        /// Where `grabbedOffset` sits within ``held``, so the row the pointer
        /// took hold of stays the one it is holding after the drop.
        var primaryRank: Int {
            held.integerLessThanOrEqualTo(grabbedOffset).map { _ in
                held.count(where: { $0 < grabbedOffset })
            } ?? 0
        }

        init(grabbedOffset: Int, held: IndexSet, active: Bool) {
            self.grabbedOffset = grabbedOffset
            self.currentOffset = grabbedOffset
            self.held = held.isEmpty ? IndexSet(integer: grabbedOffset) : held
            self.active = active
        }
    }

    /// What a reorder drag shows, synced from `environment.rowReorderFeedback`
    /// during render; read at event time, when the environment is out of reach.
    var reorderFeedback: RowReorderFeedback = .live

    /// Whether the reorder in flight was started from the KEYBOARD (see
    /// ``ItemListHandler/beginKeyboardMove()``) rather than by a drag.
    var isKeyboardMove = false

    /// Whether a dragged row can actually be floated at the pointer — there has
    /// to be a drag-and-drop session to draw it above the frame. Captured at
    /// render; see ``effectiveReorderFeedback``.
    var canFloatDraggedRow = false

    /// Where each visible row sits in the rendered content, republished every
    /// render (see ``RowBand``). A drag reads the CURRENT bands rather than the
    /// press-frame copy its closure captured, because under
    /// ``RowReorderFeedback/live`` the rows genuinely move underneath the cursor
    /// — and a wheel tick can scroll them under any mode.
    var visibleRowBands: [RowBand] = []

    /// One visible row's extent within the list's rendered content, in lines
    /// measured from the first content line (i.e. below the border and padding,
    /// and below the "N more above" indicator when one is drawn).
    struct RowBand: Equatable, Sendable {
        /// The row's data offset.
        var rowIndex: Int
        /// The row's first line.
        var yStart: Int
        /// How many lines it occupies (clipped rows count what's shown).
        var height: Int
        /// Whether this is a content row — a real, selectable row. Section
        /// headers and the reorder drop slot are not.
        var isContent: Bool
        /// Where a reorder drop on this line would put the dragged row, or `nil`
        /// for a line that is not a drop target (a section header).
        ///
        /// A line's position in the order currently DRAWN, which is a
        /// prospective final index — see ``dropTarget(atContentY:)``. Outside a
        /// non-`.live` drag that is simply ``rowIndex``; during one the list has
        /// closed up behind the dragged row and opened a slot elsewhere, so the
        /// two part company (``reorderDrawnPosition(of:)``).
        ///
        /// It is separate from ``rowIndex`` for two reasons, then: that, and the
        /// one line that is a drop target without being a row at all — the
        /// reorder slot, which the pointer rests on after every step of a drag.
        /// Reading that line as "off the rows" is what made a `.cursor` drag
        /// cancel its own gap.
        var dropIndex: Int?
    }

    /// The selection mode (single or multi).
    let selectionMode: SelectionMode

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// The currently focused item index (keyboard cursor).
    var focusedIndex: Int = 0

    /// The anchor row for range selection (macOS semantics): the last row
    /// plainly clicked, modifier-toggled, or Space-toggled. Shift-clicks and
    /// keyboard range extension both select the whole span between the anchor
    /// and the cursor, re-pivoting around it.
    var selectionAnchor: Int?

    /// Whether extend mode (`v`) is active: plain movement keys extend the
    /// selection from the anchor instead of just moving the cursor. The
    /// portable stand-in for Shift+movement — most terminals don't deliver
    /// Shift on Up/Down (Terminal.app strips it) and none distinguish
    /// Shift+Space from Space, so a mode toggled by a plain printable key is
    /// the only gesture guaranteed to work everywhere. Exited by `v`, Escape,
    /// Space/Enter, any click, or focus loss.
    var isExtendingSelection = false

    /// The scroll offset (first visible item index).
    var scrollOffset: Int = 0

    /// How many LINES of the top visible row (``scrollOffset``) are scrolled
    /// off the top edge — the sub-row position that makes
    /// ``ScrollGranularity/line`` scrolling line-precise while
    /// ``scrollOffset`` / ``maxOffset`` / ``extent`` stay row-based (O(1) for
    /// any list size). Always `0` for single-line rows and at the very bottom
    /// (``maxOffset`` is the last row-aligned top). Clamped each render by
    /// ``clampTopClip()``.
    ///
    /// Under ``ScrollGranularity/row`` a scroll STEP always leaves this at `0`
    /// (``scrollFine(by:)``), but a reveal or a centred anchor may still set
    /// it: those position the viewport on a row the user chose, and forcing
    /// them onto a row boundary moves the row off the position they computed.
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

    /// Overscroll excursion + allowance (``ScrollableOffsetState``), resolved
    /// from the environment each render.
    var overscrollState = ScrollOverscrollState()

    /// Drag auto-scroll drive flag (``ScrollableOffsetState``).
    var isAutoScrolling = false

    /// The content Y the reorder drag last saw, so the drop target can be
    /// recomputed when edge auto-scroll moves the rows under a still pointer.
    var lastReorderContentY: Int?

    /// Set when Escape cancels a drag whose button is still down: the release
    /// that follows must be swallowed rather than read as a click.
    var reorderCancelled = false

    /// The drag session, captured at render, so a cancel can take the floating
    /// preview down without waiting for the release that ends the gesture.
    weak var dragSession: DragAndDropSession?

    /// Whether the user may scroll (``ScrollableOffsetState``), synced from
    /// `environment.isScrollEnabled` each render. Selection movement is NOT
    /// gated by it — moving a cursor is not adjusting a scroll position, and the
    /// reveal that keeps the cursor on screen is a framework guarantee.
    var isScrollEnabled = true
    /// Bound `.anchorPosition` override, captured each render so a USER scroll
    /// can release it to `.window` at event time. See
    /// `ScrollableOffsetState.releaseAnchorOnUserScroll()`.
    var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>?

    /// The anchor mode the view DECLARED (from `defaultScrollAnchor`), synced
    /// each render. Read by ``anchorOnSelection(at:)`` to scope the §1.2
    /// shadow-switch to the edge modes the spec names.
    var declaredAnchorMode: ScrollAnchorMode = .window

    /// The declared anchor as an EDGE, for the shared user-scroll path
    /// (``ScrollableOffsetState/declaredEdgeAnchor``). Row and Window name no
    /// edge, so they answer `nil`.
    var declaredEdgeAnchor: ScrollAnchor<AnyHashable>? {
        switch declaredAnchorMode {
        case .top: return .top
        case .bottom: return .bottom
        case .row, .window: return nil
        }
    }

    /// The screen ROW a bound `.row` anchor is held at (0 = first visible row),
    /// and the key it was adopted for. Row-based, like ``scrollOffset``: for
    /// single-line rows it is the screen line; for taller rows it is the
    /// anchored row's index from the top of the viewport. See
    /// ``applyRowAnchorHold()`` (in `ItemListHandler+Anchor.swift`).
    var anchorHeldRow = 0
    var anchorHeldKey: AnyHashable?
    /// Last resolved ordinal of the held anchor key — an O(1) fast path so the
    /// per-frame hold doesn't rescan the whole list once the row settles.
    var anchorHeldOrdinal: Int?

    /// The bound anchor as of the last render, so a *change* can be detected
    /// and jumped to (§3.2's `anchor(to:)`). Outer optional = "never seen yet";
    /// inner = the binding's own `nil`. See ``applyAnchorHold()``.
    var lastBoundAnchor: ScrollAnchor<AnyHashable>??

    /// Last render's ``maxOffset``, against which "is this view at the bottom?"
    /// is judged for the Bottom follow.
    ///
    /// The test cannot use the CURRENT `maxOffset`: by the time the hold runs,
    /// `itemCount` has already been re-synced to the new data, so an append has
    /// moved `maxOffset` out from under an offset that was at the tail a moment
    /// ago, and the view would read as "not at the bottom" exactly when it
    /// should follow. Last frame's bound is the one the user's offset was
    /// actually formed against — including any scrolling they did between
    /// renders, which is what makes scrolling away release the follow.
    ///
    /// Starting at 0 makes the first frame glued by construction (offset 0 ≥ 0),
    /// which is how a declared `.bottom` list opens at its tail.
    var bottomFollowBound = 0

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
    /// When set, ``id(at:)`` resolves a row's id on demand — per frame only the
    /// visible window and the focused row are asked — so a 50k-row list pays
    /// O(1) for handler setup instead of building a 50k-entry ``itemIDs``.
    /// (User-initiated selection gestures ask for more: a range extension
    /// resolves its span, select-all every row — but never per-frame.) `nil`
    /// for the eager paths, which use ``itemIDs``.
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
    /// else the eager ``itemIDs`` (Table / Sections). O(1) either way — per
    /// frame only the visible window and the focused row are asked (selection
    /// gestures ask for their span on the way in, never per-frame).
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
        // Extend mode is a transient interaction state of THIS focus tenure —
        // arrows silently extending the selection after tabbing away and back
        // would be a surprise.
        isExtendingSelection = false

        // A row in hand is the same: the keys that would place it have gone
        // with the focus, so put it back rather than leaving it stranded.
        if isKeyboardMove { cancelKeyboardMove() }

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

        // Deliberately NOT revealing that index here. A list the user has just
        // left must not scroll itself: clicking a checkbox beside a table the
        // user had arrowed away from its selection would yank the rows out from
        // under the click — dozens of rows, whenever cursor and selection had
        // parted company, which is exactly why it looked intermittent.
        // ``onFocusReceived()`` reveals it when focus comes back, which is when
        // the comment above actually cares.
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

        // Picking a row up, and the keys a held one answers — ahead of the
        // selection keys, and of the plain movement below, because a row in
        // hand takes the movement keys over. `nil` means neither applies.
        if let handled = handleRowMoveKey(event) {
            return handled
        }

        // Multi-selection lists understand the macOS selection keys (range
        // extension, select-all, clear). Consulted first so an extending
        // movement key doesn't fall into the plain-movement cases below;
        // `nil` means "not a selection concern — handle normally".
        if selectionMode == .multi, let handled = handleMultiSelectionKey(event) {
            return handled
        }

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
            focusedIndex = selectableIndices.min() ?? 0
            ensureFocusedItemVisible()
            return true

        case .end:
            focusedIndex = selectableIndices.max() ?? (itemCount - 1)
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

        case .delete, .backspace:
            // Delete the focused row when the enclosing ForEach is deletable.
            // The focus index IS the data offset here — `onDelete` is wired only
            // for the homogeneous all-content list (see `_ListCore`), so no
            // header/footer rows shift it. Left inert (fall through) otherwise,
            // so a plain list never swallows Backspace.
            guard let onDelete, focusedIndex >= 0, focusedIndex < itemCount else {
                return false
            }
            let offset = focusedIndex
            onDelete(IndexSet(integer: offset))
            // The row below slides up into this slot; keep focus on it, clamped
            // to the about-to-shrink data (itemCount refreshes next render).
            focusedIndex = max(0, min(offset, itemCount - 2))
            ensureFocusedItemVisible()
            return true

        default:
            return false
        }
    }

    /// The multi-selection keyboard model (macOS semantics, adapted to what
    /// terminals can deliver — see the type comment's key table). Returns
    /// `nil` when the event isn't a selection gesture, `false` when it is one
    /// but there's nothing to do (Escape with no selection MUST fall through,
    /// so a focused list never blocks page navigation).
    private func handleMultiSelectionKey(_ event: KeyEvent) -> Bool? {
        // A movement key extends while Shift is held OR extend mode is on;
        // any other movement falls to the plain-navigation handling.
        if isExtendingSelection || event.shift,
            let handled = handleExtensionMovement(event)
        {
            return handled
        }

        // Chord-bound operations go through the app-customisable table (see
        // `RowShortcuts`), captured at render because the environment is out of
        // reach by the time the key arrives.
        switch shortcuts.action(for: event)?.action {
        case .extendSelection:
            toggleExtendMode()
            return true

        case .selectAll:
            selectAll()
            isExtendingSelection = false
            return true

        case .pickUpRow, .placeRow, .cancelMove, .moveRowUp, .moveRowDown,
            .moveRowToTop, .moveRowToBottom, .moveRowPageUp, .moveRowPageDown, nil:
            // Not selection business — handled above, or not a chord at all.
            break
        }

        switch event.key {
        case .escape:
            return handleEscapeKey()

        default:
            return nil
        }
    }

    /// The movement keys while extending: each moves the cursor and selects
    /// the anchored span. `nil` for non-movement keys.
    private func handleExtensionMovement(_ event: KeyEvent) -> Bool? {
        switch event.key {
        case .up, .down:
            // Inside extend mode Shift keeps its accelerated meaning (the
            // multiplier); outside it Shift+arrow extends one row, exactly
            // like macOS.
            let step = (isExtendingSelection && event.shift) ? max(1, shiftStepMultiplier) : 1
            extendSelection(movingBy: event.key == .up ? -step : step)
            return true

        case .home:
            extendSelection(to: selectableIndices.min() ?? 0)
            return true

        case .end:
            extendSelection(to: selectableIndices.max() ?? (itemCount - 1))
            return true

        case .pageUp:
            extendSelection(movingBy: -viewportHeight)
            return true

        case .pageDown:
            extendSelection(movingBy: viewportHeight)
            return true

        default:
            return nil
        }
    }

    /// `v`: enters or exits extend mode. Entering re-anchors at the cursor
    /// and selects it (a span of one) — the immediate highlight is the
    /// mode's feedback. Exiting keeps the selection made; the mode only
    /// changes what movement keys do.
    private func toggleExtendMode() {
        if isExtendingSelection {
            isExtendingSelection = false
        } else {
            isExtendingSelection = true
            selectionAnchor = focusedIndex
            applyAnchoredSpan()
        }
    }

    /// Escape, staged — one action per press: exit extend mode, then clear
    /// the selection. With neither to do, the event is deliberately NOT
    /// consumed so it falls through to the page (back-navigation etc.) — a
    /// focused list must never block Escape.
    private func handleEscapeKey() -> Bool {
        if isExtendingSelection {
            isExtendingSelection = false
            return true
        }
        if let selection = multiSelection?.wrappedValue, !selection.isEmpty {
            multiSelection?.wrappedValue = []
            selectionAnchor = nil
            return true
        }
        return false
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
            let before = (scrollOffset, scrollTopClipLines)
            // Row granularity is a promise about this gesture: a step lands on
            // a row boundary. It is the ONLY place that promise is kept — a
            // reveal or a centred anchor may well have left the viewport
            // mid-row, and snapping here is what returns it to the lattice
            // without forbidding those positions in the first place.
            scrollTopClipLines = 0
            scroll(by: delta)
            return (scrollOffset, scrollTopClipLines) != before
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

    /// Clamps ``scrollTopClipLines`` to its valid range for the current rows:
    /// zero at the bottom (``maxOffset``), and always inside the top row's
    /// height. Called alongside ``ScrollableOffsetState/clampScrollOffset()``
    /// on the render pass.
    ///
    /// Deliberately NOT conditioned on ``scrollGranularity``. Granularity is
    /// how far one scroll STEP moves — see ``scrollFine(by:)``, which is where
    /// row granularity re-aligns to a row boundary. It is not a constraint on
    /// where the viewport may sit, and zeroing the clip here made it one:
    /// every position a reveal or an anchor computed was quantised to the
    /// lattice of row-height prefix sums, which with variable row heights
    /// almost never contains the line a centred row needs.
    func clampTopClip() {
        guard scrollTopClipLines > 0 else { return }
        guard let rowHeight else {
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
        // A reveal positions the viewport precisely on a row; an overscroll
        // excursion left under it would offset the very row it just aimed at.
        // Moving the cursor is also the clearest statement that the user is done
        // pushing past the edge.
        clearOverscroll()
        guard let contentHeight else {
            ensureFocusedItemVisibleLegacy()
            return
        }
        guard contentHeight > 0 else { return }

        // Centring a multi-line-row list: hold a specific LINE of the focused
        // row at the viewport centre with sub-row precision, rather than the
        // whole-row margin below (which drifts as neighbouring row heights vary).
        if let anchor = followMargin.centeredAnchor, rowHeight != nil {
            anchorFocusedRow(anchor: anchor)
            return
        }

        // Scroll up: the focused row (plus any follow margin) becomes the
        // first visible content. When it isn't the very first item an
        // "above" indicator appears, but the focused row is still shown
        // (just below the indicator), so it stays visible. A focused
        // row must be FULLY visible, so any line-granularity top clip
        // on it is cleared too.
        let marginAbove = followMarginRows(from: focusedIndex, step: -1)
        if focusedIndex - marginAbove < scrollOffset {
            scrollOffset = max(0, focusedIndex - marginAbove)
            scrollTopClipLines = 0
        } else if focusedIndex == scrollOffset, scrollTopClipLines > 0 {
            scrollTopClipLines = 0
        }

        // Scroll down: keep the focused row within the visible rows.
        // `rowLineBudget` is how many of those lines rows actually get once the
        // "N more" indicators have taken theirs; clampScrollOffset() pulls the
        // offset back to the true bottom near the end.
        if let rowHeight, focusedIndex < itemCount {
            // Multi-line rows: pull the top down only as far as needed for the
            // focused row (plus as much of the follow margin below it as the
            // area allows) to fit as the last visible content, accumulating
            // heights. The top row's height counts net of any line-granularity
            // clip. A scrollbar reserves no indicator lines, so it gets the
            // full area.
            let budget = rowLineBudget
            var used = rowHeight(focusedIndex)
            var tail = focusedIndex
            let marginTail = min(
                itemCount - 1, focusedIndex + followMarginRows(from: focusedIndex, step: 1))
            while tail < marginTail, used + rowHeight(tail + 1) <= budget {
                used += rowHeight(tail + 1)
                tail += 1
            }
            // Land the LAST row this reveal must show flush against the bottom
            // edge, rather than scrolling the least that fits it. Scrolling the
            // least leaves the leftover lines below the row — and the renderer
            // fills them from the row AFTER it, so arrowing onto a row revealed
            // that row *and a slice of the next one*. Walking up from the tail
            // instead spends the slack above, where it hides content the user
            // has already passed.
            var top = tail
            var covered = rowHeight(tail)
            while covered < budget, top > 0 {
                covered += rowHeight(top - 1)
                top -= 1
            }
            // Whatever overshoots the budget is clipped off the TOP row, which
            // is what lands `tail` exactly flush against the bottom edge.
            //
            // Dropping the top row whole instead — which row granularity used
            // to do, having no sub-row position to clip with — leaves those
            // lines as slack at the BOTTOM, and the renderer fills slack from
            // the row after `tail`. So the reveal showed a row the follow
            // margin never asked for: with a margin of 1, arrowing onto row 19
            // revealed 21. Granularity sizes a scroll step; it does not get to
            // round off a reveal.
            let clip = max(0, covered - budget)
            // Only ever scroll DOWN here — the scroll-up branch above owns the
            // other direction, and re-deciding it would fight a user who has
            // scrolled away and is arrowing back.
            if top > scrollOffset || (top == scrollOffset && clip > scrollTopClipLines) {
                scrollOffset = top
                scrollTopClipLines = clip
            }
        } else {
            let safeRows =
                (showsScrollbar || itemCount <= contentHeight)
                ? contentHeight
                : max(1, contentHeight - 2)
            let tail = min(
                itemCount - 1, focusedIndex + followMarginRows(from: focusedIndex, step: 1))
            if tail >= scrollOffset + safeRows {
                // Keep the margin rows below the cursor visible too — but the
                // cursor itself always wins over its margin.
                scrollOffset = min(focusedIndex, tail - safeRows + 1)
                scrollTopClipLines = 0
            }
        }

        clampScrollOffset()
        clampTopClip()
    }

    /// How many of ``contentHeight``'s lines the ROWS actually get — the area
    /// minus whatever the "▲/▼ N more" indicators take.
    ///
    /// The reveal has to reason in these, not in the whole content height, or it
    /// counts lines the renderer has already spent on chrome: a `Table` showing
    /// both indicators gives its rows two fewer lines than the reveal assumed,
    /// so the reveal placed the top a row too high and the renderer filled the
    /// difference from below — the row after the one being revealed.
    ///
    /// A scrollbar is not an indicator: it takes a *column*, so it costs rows no
    /// lines. Both ends are assumed to need one while scrolling, which is what
    /// makes this a bound rather than an exact count: at the very top or bottom
    /// one of them is absent, and `clampScrollOffset()` reclaims that line.
    private var rowLineBudget: Int {
        guard let contentHeight else { return 1 }
        let indicators = drawsScrollIndicators ? 2 : 0
        return max(1, contentHeight - indicators)
    }

    /// Positions the viewport so a chosen LINE of the focused row lands on the
    /// viewport's centre line — sub-row precise via ``scrollTopClipLines``, so a
    /// tall multi-line row centres stably instead of the whole-row margin
    /// jumping as neighbouring heights vary. Walks UP from ``focusedIndex`` only,
    /// accumulating real row heights until it has covered the lines that must
    /// sit above the anchor, so it is O(viewport) whatever the list size. Near
    /// the top the row still rests against the edge; near the bottom
    /// ``clampScrollOffset()`` pulls it back.
    ///
    /// Line-precise under BOTH granularities. Arrow keys move the selection, so
    /// the anchor runs identically either way, and the row they land on is the
    /// same row — quantising the resulting viewport to a row boundary under
    /// ``ScrollGranularity/row`` only moved the row off the centre it had just
    /// been given, by a different amount for each neighbourhood of row heights.
    /// Granularity is the size of a scroll STEP; see ``scrollFine(by:)``.
    private func anchorFocusedRow(anchor: ScrollFollowMargin.RowAnchor) {
        guard let rowHeight, let contentHeight, contentHeight > 0,
            focusedIndex >= 0, focusedIndex < itemCount
        else { return }

        let focusedHeight = max(1, rowHeight(focusedIndex))
        // How many content lines must sit above the focused row's FIRST line.
        //
        // `.center` centres the ROW, not a line within it. It must NOT be
        // computed as (viewport centre line) − (row centre line): that floors
        // twice, and the two roundings disagree by one whenever the viewport
        // height and the row height are BOTH even — placing the row a line above
        // centre and leaving half a row visible at each edge instead of whole
        // rows. A 6-line viewport of 2-line rows (the Multi-line Cells demo) is
        // exactly that case. One subtraction, floored once, is correct for every
        // parity; where the row cannot be exactly centred (even row in an even
        // viewport has no single middle line) it sits the half-line HIGH, which
        // keeps whole rows at both edges.
        //
        // Measured in the lines the ROWS get, not the whole content area: the
        // "N more" indicators own the rest, and counting them centred the row
        // against a taller area than it lives in — one line low for every
        // indicator drawn above it.
        let area = rowLineBudget
        var linesAbove: Int
        switch anchor {
        case .top:
            linesAbove = (area - 1) / 2
        case .center:
            linesAbove = (area - focusedHeight) / 2
        case .line(let index):
            linesAbove = (area - 1) / 2 - max(0, min(focusedHeight - 1, index))
        }

        if linesAbove <= 0 {
            // The focused row's own above-anchor lines already overfill the space
            // above the centre — clip into the focused row itself.
            scrollOffset = focusedIndex
            scrollTopClipLines = -linesAbove
        } else {
            // Walk up through whole rows until the required lines are covered.
            // If the rows above run out, the row simply rests against the top.
            let wanted = linesAbove
            var top = focusedIndex
            var covered = 0
            while top > 0, covered < wanted {
                covered += max(1, rowHeight(top - 1))
                top -= 1
            }
            // Whatever the walk overshot by is clipped off the top row, so the
            // anchor lands on the exact line it asked for. No granularity test:
            // the row a centred anchor puts under the cursor is the same row
            // either way, and rounding it to a row boundary — which is what the
            // clip-zeroing forced — is what made `.row` drift by a line or
            // three from row to row while `.line` sat still.
            let clip = max(0, covered - wanted)
            scrollOffset = top
            scrollTopClipLines = clip
        }

        clampScrollOffset()
        clampTopClip()
    }

    /// The number of rows of context the follow margin keeps visible beyond
    /// the cursor in one direction (`step` −1 above / +1 below) — see
    /// ``followMargin``.
    ///
    /// A `.steps` margin is expressed in whatever this scrollable moves by, so
    /// under ``ScrollGranularity/row`` a step IS a row and counts directly.
    /// Under line granularity — and for `.fraction` / `.centered`, which are
    /// line-space by definition — it resolves to terminal lines and converts by
    /// walking real row heights outward from `index` (1:1 when rows are
    /// single-line). Clamped so the cursor can always rest strictly inside the
    /// visible area.
    private func followMarginRows(from index: Int, step: Int) -> Int {
        guard let contentHeight, contentHeight > 1 else { return 0 }
        switch followMargin.value {
        case .steps(let count) where scrollGranularity == .row:
            return min(max(0, count), max(0, (contentHeight - 1) / 2))
        case .steps, .fraction, .centered:
            let lines = followMargin.resolvedLines(viewportLines: contentHeight)
            guard lines > 0 else { return 0 }
            guard let rowHeight else { return lines }
            var rows = 0
            var used = 0
            var i = index + step
            while i >= 0, i < itemCount, used < lines {
                used += max(1, rowHeight(i))
                rows += 1
                i += step
            }
            return rows
        }
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

// MARK: - Escape Claim

extension ItemListHandler {
    /// Publishes this frame's Escape claim when the focused multi-selection
    /// list would act on it (exit extend mode / clear a non-empty selection).
    ///
    /// Status-bar items and page `onKeyPress` handlers see keys BEFORE the
    /// focused element, so without a claim a page-level "esc back" would
    /// steal the key and navigate away instead of clearing the selection.
    /// The claim (the same mechanism an open Picker drop-down uses) routes
    /// ESC to the focus chain first for this frame AND relabels the status
    /// bar's escape entry, so what ESC currently does is always visible.
    /// When Escape has nothing to do here, no claim is published and page
    /// navigation is completely untouched — the list never blocks it.
    /// Unlike a modal surface's claim, this one does not suppress the
    /// global app-chrome shortcuts (`grabsInput` false): a selection is
    /// ordinary control state, not a transient surface the user must leave.
    ///
    /// Called by the owning view during its render pass, after focus
    /// registration (never on measure passes).
    func publishEscapeClaim(context: RenderContext, isFocused: Bool) {
        guard isFocused, !context.isMeasuring else { return }

        // A row in hand owns Escape — it puts the row back — and has to SAY so:
        // `InputHandler` routes a claimed Escape through the focus system first,
        // and without the claim a page-level "⎋ back" navigates out from under
        // the move instead. (Found by driving the real app; the handler-level
        // tests never see the app's Escape.) It also advertises the mode, which
        // is what makes it discoverable at all.
        // A mouse drag claims it on the same terms: mid-drag Escape used to
        // fall through to the page's "⎋ back", navigating out from under a
        // live drag while the floating preview kept compositing over the new
        // page until the button came up.
        if isKeyboardMove || isReordering {
            context.environment.statusBar.escapeLabelOverride = "cancel move"
            context.environment.statusBar.escapeClaimGrabsInput = false
            return
        }

        guard selectionMode == .multi else { return }
        if isExtendingSelection {
            context.environment.statusBar.escapeLabelOverride = "stop extending selection"
            context.environment.statusBar.escapeClaimGrabsInput = false
        } else if let selection = multiSelection?.wrappedValue, !selection.isEmpty {
            context.environment.statusBar.escapeLabelOverride = "clear selection"
            context.environment.statusBar.escapeClaimGrabsInput = false
        }
    }
}

// (``hasContentAbove`` / ``hasContentBelow`` / ``visibleRange``
//  are provided by the ``ScrollableOffsetState`` extension and
//  read the ``extent`` defined above. The list-specific
//  arithmetic lives in ``ensureFocusedItemVisible()``.)
