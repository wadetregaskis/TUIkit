//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler+Keys.swift
//
//  The list handler's keyboard half: what each chord does to the cursor, the
//  selection and the viewport, and the navigation arithmetic behind it. Split
//  from ItemListHandler.swift, which holds the state and its scroll geometry —
//  the two halves had grown past the file-length gate together.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Key Event Handling

extension ItemListHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard itemCount > 0 else { return false }

        // Everything reordering claims — picking a row up, the keys a held row
        // answers, and the navigators during a mouse drag — ahead of the
        // selection keys and of the plain movement below, both of which would
        // otherwise move the cursor out from under the gesture.
        if let handled = handleReorderKey(event) {
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

        // The CURSOR moves by the rows on screen, which is what
        // `viewportHeight` already is — deliberately NOT `pageDistance`, whose
        // job is the SCROLL OFFSET's unit (lines under line granularity) and
        // whose walk starts at the viewport, not at the focused row. A cursor
        // page that overshoots is corrected by `ensureFocusedItemVisible`
        // anyway, so the staleness that forces `pageDistance` to recompute
        // does not bite here.
        case .pageUp:
            moveFocus(by: -viewportHeight, wrap: false)
            return true

        case .pageDown:
            moveFocus(by: viewportHeight, wrap: false)
            return true

        case .enter, .space:
            handleSelectionKey(event.key)
            return true

        // A tree's own keys, and the reason the row does not have to spend
        // Space or Return on disclosure: Right opens the focused branch. It
        // falls through on a leaf, on a node already open, and on a list that
        // is not a tree at all — the list has no other use for the key, so
        // nothing is taken away.
        //
        // Held with Option it carries that state down the WHOLE subtree, which
        // is the outline-view gesture people already know from the Finder: ⌥→
        // opens everything under the branch, ⌥← folds it all away again.
        case .right, .left:
            return handleDisclosureKey(event)

        case .delete, .backspace:
            return deleteFocusedRow()

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
    var extent: Int { itemCount + (dropSlotAddsRow ? 1 : 0) }

    /// The "▼ N more rows below" indicator's subject, which is ROWS THE USER
    /// CANNOT SEE — so it counts the data, never the line a hovering drag
    /// borrowed (``dropSlotAddsRow``). That line is the landing slot, which is
    /// on screen and is not a row.
    ///
    /// The split is deliberate and is the whole shape of the feature: the
    /// SCROLL BOUNDS (``extent``, ``maxOffset``) describe everything drawable,
    /// so the viewport can reach the slot past the last row; the INDICATORS
    /// describe the data, so they never promise a row that isn't one. Deriving
    /// both from `extent` says "▼ 0 more rows below" at the bottom of a
    /// hovering list, and deriving both from `itemCount` puts the end out of
    /// reach again.
    /// One screenful of rows from where the viewport is NOW — recomputed per
    /// press rather than read from ``viewportHeight``.
    ///
    /// A list's visible row count is not a constant: it shrinks by a line for
    /// each "N more" indicator on screen, and an indicator appears the moment
    /// you leave an edge. `viewportHeight` is last render's answer, and the app
    /// drains a burst of auto-repeated keys before rendering again — so paging
    /// by it means a held Page Down measures the second jump with the first
    /// jump's viewport and steps over a row nobody saw. The walk below is
    /// bounded by one viewport, and only runs on a page key.
    ///
    /// Answers in ``scrollFine(by:)``'s unit for this granularity: LINES under
    /// `.line` (where the offset advances a line at a time and a row may
    /// straddle the edge), whole ROWS otherwise.
    ///
    /// **This is a third statement of the window rule**, after
    /// `_ListCore.resolveVisibleWindow` and `Table.reserveIndicatorLines`, and
    /// the three must agree — `PageDistanceTests` renders a real list and
    /// checks this against the rows actually drawn, at every offset, so a
    /// change to one of the others cannot quietly drift from this.
    var pageDistance: Int {
        // No content height means the owner reserves indicator lines itself and
        // `viewportHeight` is the literal visible count (the handler's own unit
        // tests, and any caller following that contract).
        guard let contentHeight, contentHeight > 0 else { return max(1, viewportHeight) }
        // The landing slot is drawn among the rows and takes one of their
        // lines — the same subtraction `_ListCore` makes before its walk.
        var budget = contentHeight - (dropSlotAddsRow ? 1 : 0)
        if reservesIndicatorLine {
            // A scrollbar spends a column, not a line, so it reserves nothing.
            // Otherwise: a line for "▲ N more" whenever anything is hidden
            // above…
            if drawnOffset > 0 || scrollTopClipLines > 0 { budget -= 1 }
            // …and one for "▼ N more" if the fill leaves rows over, resolved
            // the way the window walk resolves it — fill assuming none, then
            // look to see whether any remain.
            if drawnOffset + rowsFitting(in: budget) < itemCount { budget -= 1 }
        }
        budget = max(1, budget)
        return scrollGranularity == .line ? budget : max(1, rowsFitting(in: budget))
    }

    /// How many whole rows fit in `lines`, starting at ``drawnOffset``.
    ///
    /// At least one: a row taller than the viewport still has to be pageable,
    /// or Page Down would sit on it forever. The top clip is not subtracted —
    /// a row-granularity step clears it (see ``scrollFine(by:)``), and under
    /// line granularity this result is not used as the distance.
    private func rowsFitting(in lines: Int) -> Int {
        guard let rowHeight else { return max(1, lines) }
        var used = 0
        var count = 0
        var index = drawnOffset
        while index < itemCount {
            let height = max(1, rowHeight(index))
            if used + height > lines, count > 0 { break }
            used += height
            count += 1
            index += 1
        }
        return count
    }

    var hasContentBelow: Bool { drawnOffset + viewportHeight < itemCount }

    var rowsBelow: Int { max(0, itemCount - (drawnOffset + viewportHeight)) }

    /// The offset the viewport was actually DRAWN from, which the indicators
    /// count from — `nil` until a frame publishes one, and then
    /// ``scrollOffset``.
    ///
    /// ``ScrollWindowOrigin/absorbing(offset:topClip:firstRowHeight:)`` draws a
    /// one-line-hidden offset from the line above instead, because announcing
    /// it would cost the very line it hides. That is a resolution, not a state
    /// change, so the two disagree — and the indicators must follow the
    /// drawing, exactly as the rows, the bands and the click mapping do.
    ///
    /// Normally the disagreement cannot be seen, because
    /// ``settleRestingOffset(overflowing:drawsTextIndicators:firstRowHeight:)``
    /// snaps a resting offset of 1 down to 0. It deliberately does not while a
    /// drop slot hovers — a viewport being steered is not resting — and there
    /// two frames drawing identical rows disagreed about how many were below,
    /// one of them by counting a row the user could plainly see.
    ///
    /// The indicators are not the only consumer: a PAGE is also measured from
    /// here, via ``ScrollableOffsetState/pageDelta(_:)``, so that one Page Down
    /// from two identical-looking screens goes to the same place. Steps are
    /// not, and must not be — see that method.
    var drawnOffset: Int {
        get { drawnWindowOffset ?? scrollOffset }
        set { drawnWindowOffset = newValue }
    }

    /// The rows on screen, and therefore DATA indices — `Table` subscripts
    /// `data` with them directly. The protocol's default bounds this by
    /// ``extent``, which while a drag hovers is one past the last row: that
    /// borrowed line is the landing slot, and there is nothing to subscript
    /// for it. (`List` never exposed this — it reads rows through a window it
    /// computed itself — so the trap only bites the `Table`.)
    var visibleRange: Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let start = max(0, min(scrollOffset, itemCount - 1))
        return start..<min(itemCount, start + max(0, viewportHeight))
    }

    /// The rows on screen as DRAWN — from ``drawnOffset``, the origin after
    /// the single-line absorb — where ``visibleRange`` reads the raw offset.
    /// The doctrine is +Resting's: everything derived from the offset picks a
    /// side, and *the indicators count from `drawnOffset`*; the two differ
    /// only at offset 1 under text indicators, which survives to render
    /// exactly while steering.
    var drawnVisibleRange: Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let start = max(0, min(drawnOffset, itemCount - 1))
        return start..<min(itemCount, start + max(0, viewportHeight))
    }

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

    /// An absolute jump lands row-aligned (``ScrollableOffsetState``
    /// requirement — its doc promises a sub-row-unit conformer discards the
    /// clip too). Without this override a generic caller's Home — the focus
    /// system's section scroll, a mid-drag navigator — jumped the OFFSET to 0
    /// but left ``scrollTopClipLines`` where the wheel had put it, showing
    /// row 0 with its first lines still scrolled off at the very top.
    func scrollToOffset(_ offset: Int) {
        scrollOffset = max(0, min(resolvedMaxOffset(reaching: offset), offset))
        scrollTopClipLines = 0
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
                (!reservesIndicatorLine || itemCount <= contentHeight)
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
    var rowLineBudget: Int {
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

// (``hasContentAbove`` / ``hasContentBelow`` / ``visibleRange``
//  are provided by the ``ScrollableOffsetState`` extension and
//  read the ``extent`` defined above. The list-specific
//  arithmetic lives in ``ensureFocusedItemVisible()``.)
