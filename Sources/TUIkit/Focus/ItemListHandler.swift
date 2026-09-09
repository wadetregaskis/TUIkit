//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// A `Table` with a `sortOrder` binding adds Ctrl+S (sort by the next sortable
/// column, wrapping) and Ctrl+D (reverse the direction) — the keyboard route to
/// a header click.
///
/// Every chord above is rebindable — see ``RowShortcuts`` — and a reorderable
/// list adds Ctrl+R to pick the focused row up, after which the movement keys
/// move its landing slot and Return/Escape place it or put it back.
/// | Escape | Exit extend mode, else clear a non-empty selection; otherwise falls through (page navigation is never blocked) |
final class ItemListHandler<SelectionValue: Hashable>: PersistedFocusable, ScrollableOffsetState {
    /// The unique identifier for this focusable element.
    var focusID: String

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

    /// The scrollbar extent estimator's mean row height, carried across frames
    /// while `signature` — a hash of everything that shapes row heights (row
    /// count, widths/limits, precision) — holds. See the `cachedMean` parameter
    /// of ``ScrollExtentEstimator/lineMetrics`` for the contract; the sample it
    /// spares is the same 64 rows every frame, each of which costs a wrap (a
    /// Table) or a row materialisation (a List) to ask.
    var extentMeanCache: (signature: Int, mean: Double)?

    /// The chord → action map this list's keys dispatch through, resolved from
    /// `environment.rowShortcuts` during render (see ``RowShortcuts``). Captured
    /// rather than read live: a key event arrives between renders, with no
    /// environment to consult.
    var shortcuts: RowShortcutLookup = .default

    /// What ``shortcuts`` was built from, so it is not built again from the same
    /// pair. Memoised for the reason ``extentMeanCache`` is: the inputs change
    /// almost never and the work is not free.
    ///
    /// `lookup` builds a fresh `Dictionary`, walks every ``RowAction`` twice
    /// (defaults, then overrides) and hashes some fifty chords — to produce a
    /// value that is identical for every list on the page and, for the vast
    /// majority of apps, never changes at all. It ran once per List/Table per
    /// PASS, and the measure pass counts: eight tables in a stack, each measured
    /// and then rendered, paid it sixteen times a frame.
    var shortcutsKey: ShortcutsKey?

    /// The pair ``shortcuts`` is a function of.
    struct ShortcutsKey: Equatable {
        let shortcuts: RowShortcuts
        let commandKey: CommandKeyBinding
    }

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

    /// Whether a drag hovering this control is drawing a landing slot that
    /// NOTHING left the control to make room for — so the rows plus the slot
    /// need one line more than the rows alone.
    ///
    /// True only for a drag that came from elsewhere. A reorder takes its rows
    /// out of the list before opening the slot, and a `.draggable` row of this
    /// list's own is dropped from the drawing for the same reason (see
    /// `_ListCore.decorateForReorder`) — both are one row out, one slot in, no
    /// net change. Set by the owning view every render, because only it knows
    /// where the drag started and whether a slot is open here at all.
    ///
    /// The line is granted as CONTENT, not as height: the control cannot grow
    /// mid-drag without shifting the page under the pointer. So an
    /// exactly-full list overflows by one, which is a state the scroll
    /// machinery already knows how to express — the "▼ N more below" indicator
    /// or the scrollbar appears, and ``maxOffset`` rises by one so the wheel,
    /// the mid-drag navigators and the edge auto-scroll can all reach the
    /// position after the last row. Without it the extent says the rows fit
    /// exactly, ``maxOffset`` is zero, nothing can scroll, and the slot's line
    /// is silently clipped off the bottom — taking a real row with it, and
    /// leaving "drop at the end" impossible to point at.
    ///
    /// Deliberately NOT folded into ``itemCount``: that is the DATA count, and
    /// every piece of reorder index arithmetic — ``reorderInsertionOffset``,
    /// the `externalDropSlot` clamp, the keyboard-move clamps — is defined
    /// against it. A phantom row there would let a drop name an index the data
    /// has no room for.
    var dropSlotAddsRow = false

    /// Whether this frame's render spends content lines on "▲/▼ N more"
    /// indicators. Synced by the owning view, because only it knows: a `List`
    /// swaps its indicators for a scrollbar, while a `Table` draws both (the bar
    /// takes a column, the indicators take lines). The reveal budgets rows
    /// against `contentHeight` MINUS these — see ``rowLineBudget``.
    var drawsScrollIndicators = true

    /// Whether a "▲/▼ N more" line comes out of the content area this frame.
    ///
    /// The two flags are set together by the views (a bar and the text lines
    /// are alternatives), but both have to be consulted: `showsScrollbar`
    /// alone was the old proxy for "spends no line", and it misses the case
    /// this cannot — indicators hidden outright, which spends nothing either.
    var reservesIndicatorLine: Bool { drawsScrollIndicators && !showsScrollbar }

    /// Whether BOTH "N more" lines come out of the content area at every offset,
    /// whatever is hidden — ``EnvironmentValues/alwaysShowsVerticalTextIndicators``.
    ///
    /// Synced by the owning view beside ``drawsScrollIndicators``, and consulted
    /// wherever a bound is worked out from the content height: the reservation
    /// stops depending on where the viewport is, which is the whole point of
    /// `.visible`, and every one of those bounds has to say so or the view can
    /// scroll a line past its own last row.
    var alwaysReservesIndicatorLines = false

    /// How many lines the "N more" chrome takes out of the content area.
    ///
    /// One number, so the several places that budget against the content height
    /// cannot each decide for themselves — under
    /// ``alwaysReservesIndicatorLines`` it is 2 at every offset, and otherwise it
    /// is at most 1 (the "above" line; the "below" one is discovered by filling,
    /// because whether rows remain past the window is what it depends on).
    var reservedIndicatorLines: Int {
        guard reservesIndicatorLine else { return 0 }
        return alwaysReservesIndicatorLines ? 2 : 1
    }

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

    /// How many DRAWABLE entries the row area holds this frame.
    ///
    /// ``viewportHeight`` counts ROWS, and the owning view has already taken
    /// the landing slot's line out of it (`contentHeight - dropSlotAddsRow`).
    /// ``extent`` counts ENTRIES, and has already added that same line in. A
    /// bound taken as `extent - viewportHeight` therefore counts one line
    /// twice, in opposite directions, and lands one offset past the end: the
    /// window there holds a row fewer than the area has lines for, so the
    /// frame draws the slot AND a blank the rows should have filled — the
    /// "two blank lines, one of them nowhere near the pointer" report. Adding
    /// the line back here is what makes the two sides speak the same units.
    var viewportEntries: Int { viewportHeight + (dropSlotAddsRow ? 1 : 0) }

    /// The largest valid scroll offset, in rows, **as it applies to where the
    /// viewport currently sits** — see ``resolvedMaxOffset(reaching:)``, which
    /// this asks with ``scrollOffset``. A mover that wants to go somewhere else
    /// must ask about *that* offset, or it will be clamped by a bound computed
    /// for the position it is leaving.
    var maxOffset: Int { resolvedMaxOffset(reaching: scrollOffset) }

    /// The largest valid scroll offset, in rows, resolved precisely enough to
    /// clamp `offset`.
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
    ///
    /// The walk is skipped for an `offset` that cannot reach the tail, which is
    /// why this takes a parameter at all: materialising tail rows' heights is
    /// the expensive part on a large lazy list, and an offset short of the
    /// cheap floor below is clamped by neither bound, so which one it is
    /// cannot matter. Asking about the WRONG offset is a real bug, though —
    /// the floor is a strict UNDER-estimate whenever an indicator line is
    /// reserved, so a jump that clamps against it lands a row short of the
    /// bottom and needs a second press to arrive. That is what
    /// ``settledMaxOffset`` and the `offset`-driven clamps exist to prevent.
    func resolvedMaxOffset(reaching offset: Int) -> Int {
        guard let contentHeight, contentHeight > 0, rowHeight != nil else {
            return max(0, extent - viewportEntries)
        }
        // Every row is at least one line, so at most `contentHeight` rows fit:
        // the true bound is never below this floor, and an offset short of it
        // is inside every candidate answer. Landing exactly ON the floor does
        // need the walk, though — `maxOffset` asks about ``scrollOffset``, and
        // "am I at the bottom?" is answerable only by the exact bound.
        let floor = max(0, extent - contentHeight)
        guard offset >= floor else { return floor }
        return bottomWalk()?.top ?? floor
    }

    /// The walk both bottom bounds share: the smallest top row for which
    /// everything below it fits the content area, how many lines of the budget
    /// that leaves UNUSED, and the height of the row that would not fit.
    ///
    /// The shortfall is the interesting part, and it is why this answers three
    /// things rather than one. Nothing forces a suffix of the row heights to sum
    /// to the budget: three-line rows in a sixteen-line budget make the last
    /// whole-row screenful fifteen lines, and the sixteenth is blank — see
    /// ``fillBottomShortfall()``, which is what spends it.
    ///
    /// The budget the shortfall is measured against is the ACCEPTED top's, never
    /// the candidate the walk rejected — the local `budget(forTop:)` is asked
    /// about a named top for exactly that reason.
    ///
    /// `nil` when there are no row heights to walk (a single-line `Table`, the
    /// handler's own unit tests); the bound is arithmetic there.
    func bottomWalk() -> (top: Int, shortfall: Int, straddlingHeight: Int)? {
        guard let rowHeight, let contentHeight, contentHeight > 0 else { return nil }
        // Reserve the "above" indicator's line only when there IS one — a
        // scrollbar draws no such line and hidden indicators draw nothing at
        // all, so in both cases the rows fill the full height.
        // Under `always` both lines are there at every offset, including at
        // the bottom this walk is finding and at row 0 — so the budget is a
        // constant rather than a question about where the top lands.
        //
        // Asked about a top rather than carried in a running variable, because
        // the two askers mean different tops: the fit test asks about the
        // CANDIDATE (`top - 1`, the row it is trying to admit) and the shortfall
        // about the ACCEPTED one. They differ by a line exactly when the walk
        // stops at top 1 — row 0 did not fit, so the "▲ N more above" line stays
        // and the rows keep only `contentHeight - 1`. Reporting the candidate's
        // budget there made the shortfall a line too large, and
        // ``fillBottomShortfall()`` then clipped a line too FEW off the row it
        // backs up to: the destination overfilled its budget by one, the last row
        // lost its last line, and the window had reached `count` so no
        // "▼ N more below" was drawn to say so.
        func budget(forTop topRow: Int) -> Int {
            alwaysReservesIndicatorLines
                ? max(1, contentHeight - 2)
                : ((!reservesIndicatorLine || topRow == 0) ? contentHeight : contentHeight - 1)
        }
        var used = 0
        var top = extent
        var straddling = 0
        while top > 0 {
            // The row a hovering drag borrows (``dropSlotAddsRow``) sits past
            // the last real one and has no data to measure: it is the slot,
            // one blank line. Asking `rowHeight` for it indexes past the data.
            let height = top - 1 < itemCount ? max(1, rowHeight(top - 1)) : 1
            if used + height > budget(forTop: top - 1) {
                straddling = height
                break
            }
            used += height
            top -= 1
        }
        return (top, max(0, budget(forTop: top) - used), straddling)
    }

    /// The row-activation action (``List``/``Table`` `.onRowActivate(_:)`):
    /// invoked with the focused row's id on Return/Enter, and by the owning
    /// view on double-click. When set, Enter ACTIVATES instead of toggling
    /// selection — Space still toggles — matching the file-browser convention
    /// (and AppKit's action/doubleAction split). `nil` keeps the original
    /// behaviour: Enter and Space both toggle selection.
    var primaryAction: ((SelectionValue) -> Void)?

    /// The tree inside this list, when there is one — see
    /// ``OutlineRowActivating``. Left and Right collapse and expand through it.
    var outlineActivation: (any OutlineRowActivating)?

    /// Opens or closes the branch the cursor is on.
    ///
    /// - Parameters:
    ///   - expanded: `true` to open, `false` to close.
    ///   - includingDescendants: Whether to carry that state down the whole
    ///     subtree rather than one level — the Option-held gesture.
    /// - Returns: Whether anything moved. `false` when the list is not a tree,
    ///   when the focused row is a leaf, and when the subtree is already in the
    ///   requested state — the key falls through in each case.
    func setFocusedRowExpanded(_ expanded: Bool, includingDescendants: Bool = false) -> Bool {
        guard let outlineActivation, let id = id(at: focusedIndex) else { return false }
        return outlineActivation.setRowExpanded(
            AnyHashable(id), to: expanded, includingDescendants: includingDescendants)
    }

    /// Right opens the focused branch; Left closes it, and — when there is
    /// nothing to close — leaves the subtree instead of the list.
    func handleDisclosureKey(_ event: KeyEvent) -> Bool {
        if event.key == .right {
            if setFocusedRowExpanded(true, includingDescendants: event.alt) { return true }
            // Nothing opened — a leaf, or a branch already open. In a TREE the
            // key is still the tree's: it is consumed and does nothing, rather
            // than falling through to move the focus sideways out of the
            // outline. Pressing Right on an open folder to see what happens
            // should not land you in the control next to the list.
            //
            // A list that is not a tree keeps its fall-through: it has no use
            // for Right at all, so nothing is taken away.
            return outlineActivation != nil
        }
        if setFocusedRowExpanded(false, includingDescendants: event.alt) { return true }
        return moveFocusOutOfSubtree()
    }

    /// Left's second act, once there is nothing left to close: move the cursor
    /// OUT of the subtree it is in rather than letting the key escape the list.
    ///
    /// The ladder is the one an outline view uses, and each rung answers "where
    /// is 'out' from here?":
    ///
    /// 1. The parent row, when this row has one — up one level.
    /// 2. The first row, when it does not — a root row's "out" is the top of
    ///    the tree, which is where a fold-everything-up gesture lands you.
    /// 3. Nothing, when the cursor is already on the first row. Only then does
    ///    Left leave, so the key reaches the next view exactly once the outline
    ///    has run out of places to go — instead of, as before, on the first
    ///    press that met a leaf.
    ///
    /// - Returns: Whether the cursor moved. `false` on a list that is not a
    ///   tree, so a plain list's Left is untouched.
    private func moveFocusOutOfSubtree() -> Bool {
        guard let outlineActivation, focusedIndex >= 0 else { return false }
        if let id = id(at: focusedIndex),
            let parent = outlineActivation.parentRowID(of: AnyHashable(id))?.base
                as? SelectionValue,
            let parentIndex = index(of: parent)
        {
            focusedIndex = parentIndex
            ensureFocusedItemVisible()
            return true
        }
        guard focusedIndex > 0 else { return false }
        focusedIndex = 0
        ensureFocusedItemVisible()
        return true
    }

    /// Deletes the focused row when the enclosing `ForEach` is deletable.
    ///
    /// The focus index IS the data offset here — `onDelete` is wired only for
    /// the homogeneous all-content list (see `_ListCore`), so no header/footer
    /// rows shift it.
    ///
    /// - Returns: Whether a row was deleted. `false` leaves Delete / Backspace
    ///   to fall through, so a plain list never swallows either.
    func deleteFocusedRow() -> Bool {
        guard let onDelete, focusedIndex >= 0, focusedIndex < itemCount,
            // `.deleteDisabled()` on the row. Returning FALSE rather than true:
            // a refused row must leave Delete alone entirely, so it falls
            // through to whatever else wants the key — exactly as it does in a
            // list that is not deletable at all. Swallowing it would make a
            // locked row silently eat a shortcut.
            !deleteDisabledRows.contains(focusedIndex)
        else { return false }
        let offset = focusedIndex
        onDelete(IndexSet(integer: offset))
        // The row below slides up into this slot; keep focus on it, clamped to
        // the about-to-shrink data (itemCount refreshes next render).
        focusedIndex = max(0, min(offset, itemCount - 2))
        ensureFocusedItemVisible()
        return true
    }

    /// Data offsets whose rows carry `.deleteDisabled()`, republished each
    /// frame by the `List` from what the drawn rows reported.
    ///
    /// Absence means allowed. A row that never rendered cannot appear here, and
    /// does not need to: the only row Delete can name is the focused one, and
    /// the focus machinery keeps that on screen.
    var deleteDisabledRows: Set<Int> = []

    /// Data offsets whose rows carry `.moveDisabled()`. Same publication and
    /// the same reasoning as ``deleteDisabledRows`` — a drag can only grab a
    /// row it can point at.
    var moveDisabledRows: Set<Int> = []

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

    /// A `Table`'s keyboard sort gestures, if it has a `sortOrder` binding:
    /// invoked with ``RowAction/sortNextColumn`` or
    /// ``RowAction/reverseSortOrder``, and it applies the same `toggleSort` a
    /// header CLICK applies. `nil` for a `List`, and for a `Table` with nothing
    /// to sort, which is what leaves those chords to the app.
    ///
    /// Set every frame beside ``onMove``, at BOTH `_TableCore` viewports: it
    /// closes over that frame's binding, while the handler persists at one
    /// identity across frames and across a switch between the two paths.
    var onSort: ((RowAction) -> Void)?

    /// The state of an in-flight mouse reorder drag, or `nil`. See
    /// ``ItemListHandler/dragReorder(toContentY:)`` for the state machine.
    var reorder: RowReorder?

    /// What a reorder drag shows, synced from `environment.rowReorderFeedback`
    /// during render; read at event time, when the environment is out of reach.
    var reorderFeedback: RowReorderFeedback = .live

    /// Whether a KEYBOARD move shuffles the data as it goes instead of
    /// previewing `.dimmed`. Set by a view whose row composer draws no slot —
    /// the multi-line `Table` — because a dimmed preview it never draws left
    /// Ctrl-R moving nothing visible while the handler parked the cursor
    /// beside a slot that was not there. See ``effectiveReorderFeedback``.
    var keyboardMoveIsLive = false

    /// Whether the reorder in flight was started from the KEYBOARD (see
    /// ``ItemListHandler/beginKeyboardMove()``) rather than by a drag.
    var isKeyboardMove = false

    /// The row the last left release landed on — the identity half of the
    /// multi-click question. See ``completesMultiClick(on:clickCount:)``.
    var lastClickedRow: Int?

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

    /// The ``scrollOffset`` ``visibleRowBands`` were published against.
    ///
    /// A band says "this LINE holds that row", which stops being true the
    /// moment the viewport scrolls — the line is still there, a different row
    /// is on it. Keeping the offset alongside is what lets
    /// ``carryReorderTargetThroughAutoScroll()`` tell how far the rows have
    /// moved under a pointer that has not.
    var visibleRowBandsOffset: Int = 0

    /// Backing storage for ``drawnOffset``; see there.
    var drawnWindowOffset: Int?

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
    ///
    /// Moving it retires ``drawnOffset``: that answer describes the frame the
    /// rows were last drawn in, and once the viewport has moved there is no
    /// drawn origin again until something draws. Leaving it behind is not a
    /// stale-by-a-bit problem but a wrong-sign one — the app drains a burst of
    /// auto-repeated keys before it renders, and `pageDelta(_:)` subtracting a
    /// several-page-old origin turned the second Page Down of a held key into
    /// a scroll UP, pinning the viewport one page from the top.
    var scrollOffset: Int = 0 {
        didSet {
            if scrollOffset != oldValue { drawnWindowOffset = nil }
        }
    }

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

    /// Where a drag from OUTSIDE this list would land, while one is hovering
    /// — a data index, since nothing has been taken out of this list.
    ///
    /// Draws the same gap a `.cursor` reorder shows, because it means the same
    /// thing: let go here and the rows arrive at this place.
    var externalDropSlot: Int? {
        didSet {
            // The remembered pointer position belongs to the slot: when the slot
            // goes, so does it.
            if externalDropSlot == nil {
                lastExternalDropContentY = nil
                externalDropResolvedOffset = nil
            }
        }
    }

    /// The content-space line the incoming drag last hovered, so an auto-scroll
    /// tick can re-resolve the slot with no mouse event to go on. See
    /// ``hoverExternalDrop(atContentY:)``, which is the only thing that should
    /// write it.
    var lastExternalDropContentY: Int?

    /// The scroll offset the slot was last resolved at — by the auto-scroll
    /// retarget, or by a hover that had a band to read — or `nil` when the
    /// standing answer is one the retarget should replace.
    ///
    /// That retarget exists for one reason: the rows move under a motionless
    /// pointer, so the slot the pointer named goes stale. It follows that it
    /// must not run again while the rows sit still — and there it is worse than
    /// useless, because the question it asks is answered by bands that its own
    /// previous answer helped lay out. On a list whose rows exactly fill it,
    /// the slot's line pushes the last row out of view, which changes which row
    /// is last, which changes the answer, which puts the line back: the gap
    /// flips between two places on alternate frames with the pointer perfectly
    /// still.
    ///
    /// So a hover that landed ON a band writes the current offset here rather
    /// than clearing it: it has answered from the pointer's own position, and
    /// the retarget can only replace that with a derived one. Clearing it on
    /// every newly-named line (which is what this did until 2026-08-29) did not
    /// avoid the flip, only its frequency — the render after each mouse movement
    /// still overrode the pointer, so the gap sat one line above the cursor on
    /// the bottom row of a full list.
    ///
    /// `nil` only for a hover that landed on no band at all. The pointer that
    /// starts auto-scroll is by definition on chrome, and there the hover's own
    /// rule ("past the rows means append") is an answer about the end of the
    /// data rather than about anywhere near the cursor — exactly what the
    /// retarget is for.
    var externalDropResolvedOffset: Int?

    /// Rows whose picture is still flying home, drawn BLANK where they belong.
    ///
    /// A cancelled reorder puts its rows back the instant the button comes up,
    /// while the preview takes a fifth of a second to walk back to them — so
    /// for that fifth of a second the same rows were on screen twice, once in
    /// the list and once in the air above it.
    ///
    /// Blank in place, NOT held out of the list. Taking them out for the
    /// duration would change the list's length after the gesture is over,
    /// which moves the very rows the user is looking at (and can change what
    /// the list can scroll to). Their space is theirs; they simply have nothing
    /// drawn in it until the picture lands. So this is a question the RENDERER
    /// asks and the layout never does — no window, band, budget or index
    /// arithmetic reads it.
    ///
    /// Cleared by the owning view on any frame with no flight in the air, which
    /// makes it self-limiting: a path that sets it without starting a flight
    /// loses it on the very next render rather than blanking a row for ever.
    var returningRows: IndexSet = []

    /// Drops any blanking left over from a flight that has already landed.
    ///
    /// Called by the owning view every render — both of them, on every path,
    /// which is why it is a method rather than the two lines it replaces: the
    /// rule is "a row blanks itself only while a picture is walking back to
    /// it", and a path that forgot to say so left a row blank for good.
    func syncReturningRows(with session: DragAndDropSession?) {
        if session?.returnFlight == nil { returningRows = [] }
    }

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

    /// The scrollbar cell under the pointer (``ScrollableOffsetState``).
    var hoveredBarCell: Int?
    /// Bound `.anchorPosition` override, captured each render so a USER scroll
    /// can release it to `.window` at event time. See
    /// `ScrollableOffsetState.releaseAnchorOnUserScroll()`.
    var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>?

    /// The anchor mode the view DECLARED (from `defaultScrollAnchor`), synced
    /// each render. Read by ``anchorOnSelection(at:)`` to scope the §1.2
    /// shadow-switch to the edge modes the spec names.
    var declaredAnchorMode: ScrollAnchorMode = .window

    /// The anchor mode the view declared for the OPENING frame (from
    /// `defaultScrollAnchor(_:for: .initialOffset)`), synced each render beside
    /// ``declaredAnchorMode``.
    ///
    /// `nil` means none was stated, and then the opening frame uses
    /// ``declaredAnchorMode`` like every frame after it — which is exactly what
    /// a view using the unlabelled modifier gets, and what makes the role split
    /// inert for everything written before it.
    var declaredOpeningAnchorMode: ScrollAnchorMode?

    /// Whether this scrollable has rendered a frame yet.
    ///
    /// The opening frame is placed by ``declaredOpeningAnchorMode`` and every
    /// frame after it by ``declaredAnchorMode`` — see
    /// ``ScrollAnchorMode/governing(opening:standing:hasOpened:)``. Set on
    /// render passes only: a measure must not spend the opening frame.
    var hasOpened = false

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

    /// Last glued frame's ``itemCount``, so the Bottom follow can tell a frame
    /// where the tail actually ADVANCED (rows arrived — carry the focus cursor
    /// along) from a steady glued frame (nothing changed — leave the cursor
    /// alone, or the arrow keys are dead; see ``followBottomEdge()``). Counts
    /// rather than offsets, because a list shorter than its viewport appends
    /// without ever moving the offset. Starts at -1 so the first glued frame
    /// always reads as an advance (the opening placement carries the cursor).
    var bottomFollowItemCount = -1

    /// The row the Bottom follow last parked the focus cursor on, or `nil` when
    /// it has never carried it.
    ///
    /// How the follow tells its own cursor move from the user's: finding the
    /// cursor somewhere else means they moved it, and their place in the list
    /// outranks the newest row. See ``followBottomEdge()``.
    var bottomFollowCursor: Int?

    /// The last row index the Bottom follow saw, so a cursor walked back onto
    /// the tail re-engages the follow even though rows have arrived since (the
    /// CURRENT tail is one of the new rows, which the user has never seen).
    var bottomFollowTail = -1

    /// Whether this list holds the focus, as of the last render.
    ///
    /// Set by the owning view alongside the rest of the per-frame wiring. The
    /// Bottom follow reads it: an unfocused list has no cursor anyone is
    /// looking at, so it scrolls without moving one — anchoring a log view must
    /// not put a highlight on a row the user never chose.
    var isFocusEngaged = false

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
