//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackLayoutPlacing.swift
//
//  _VStackCore's LayoutPlacing conformance ("Locating things without drawing
//  them" §5b): the stack's children placed by measurement alone. The windowed
//  render path (`renderViewportWindow`) consumes the same slot walk, so the
//  window visitor and the locate/enumerate answers cannot disagree — one
//  traversal, many visitors.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Row Slots

extension _VStackCore {
    /// One child's vertical slot: content origin (below the inter-row spacing
    /// gap), measured size, and the spacing charged before it.
    struct RowSlot {
        let child: ChildView
        /// Content top, container-relative (spacing already applied).
        let y: Int
        let size: ViewSize
        let spacingBefore: Int

        var height: Int { size.height }
        var width: Int { size.width }
    }

    /// Every child's natural-height slot, top to bottom, measured at the
    /// given width (unconstrained when `nil`) with inter-row spacing charged
    /// between consecutive rows that occupy a line — the gaps `appendVertically`
    /// draws, not one per child.
    ///
    /// Pass the width the rows will actually render at: a wrapping `Text`
    /// measures taller at the real width than unconstrained, and the slot
    /// height is authoritative — the windowed render pads/clamps the row to
    /// it, so a width-blind slot would clip wrapped rows.
    ///
    /// Measurement-only: no rendering, no side effects. Callers inside a
    /// scroll window must pass a context whose `scrollContentWindow` is
    /// cleared (descendants aren't at the scroll origin).
    ///
    /// `keepsMeasuresLive` marks every row measured here live for the render
    /// cache's end-of-pass collection. A LAZY stack passes `true`: it draws
    /// only the rows in its viewport, and the memos deliberately do not mark
    /// on a measure (ebf547fe: doing so cost +13.5% on a giant eager tree), so
    /// nothing else marks the rest. Unmarked, every one of those rows lost its
    /// measure memo at the end of every frame and was measured from scratch on
    /// the next: a 250-message chat spent 6 ms a frame re-measuring bubbles
    /// nobody could see. The windowed paths above 256 rows mark the rows they
    /// touch for the same reason (`AnchoredWindowFrame.pitch`); this is the
    /// same mark on the path below that threshold, bounded by the rows this
    /// stack holds. An eager stack draws every row, so the render marks them.
    func naturalRowSlots(width: Int?, context: RenderContext, keepsMeasuresLive: Bool = false) -> [RowSlot] {
        let children = resolveChildViews(from: content, context: context)
        return rowSlots(
            count: children.count, childAt: { children[$0] }, width: width, context: context,
            keepsMeasuresLive: keepsMeasuresLive)
    }

    /// The one slot rule, walked over `count` children in order, each fetched
    /// by ordinal from `childAt` — so a caller holding a lazily built
    /// collection hands out only the rows the walk actually takes.
    private func rowSlots(
        count: Int, childAt: (Int) -> ChildView, width: Int?, context: RenderContext,
        keepsMeasuresLive: Bool
    ) -> [RowSlot] {
        let proposal = ProposedSize(width: width, height: nil)
        let liveMarks = keepsMeasuresLive ? context.renderCache : nil
        var slots: [RowSlot] = []
        slots.reserveCapacity(count)
        var runningY = 0
        for ordinal in 0..<count {
            let child = childAt(ordinal)
            // Measured before the gap is decided, because the gap depends on it:
            // a row of no lines earns none (see `linearSpacing(before:…)`).
            // Charged per index, every row below an `EmptyView` sat one line
            // lower here than either stack draws it — the lazy measure claimed
            // the line, the viewport window painted it as a blank row the plain
            // window never drew, and placement queries and `scrollTo` (the eager
            // stack's seek reads these slots too) aimed one line past their row
            // per empty row above.
            let size = child.measure(proposal: proposal, context: context)
            liveMarks?.markActive(child.identity(under: context))
            let spacingBefore = linearSpacing(before: size.height, placedExtent: runningY, spacing: spacing)
            let y = runningY + spacingBefore
            slots.append(RowSlot(child: child, y: y, size: size, spacingBefore: spacingBefore))
            runningY = y + size.height
        }
        return slots
    }

    /// The content lines drawn for real when the rows `renders` marks are the
    /// only ones drawn and the rest are placeholders — from the top of the
    /// first slot (its spacing included) to the bottom of the last row, or
    /// open-ended when that last row is the stack's last, since nothing below
    /// it needs drawing. `nil` when no row is drawn.
    ///
    /// Asked of a CONTIGUOUS run: the full walk asks before it adds the rows
    /// it draws out of line (the focused row and a pending focus target, with
    /// their neighbours), which sit elsewhere with placeholders between.
    static func drawnLines(of slots: [RowSlot], renders: [Bool]) -> Range<Int>? {
        guard let first = renders.firstIndex(of: true), let last = renders.lastIndex(of: true)
        else { return nil }
        let top = slots[first].y - slots[first].spacingBefore
        let bottom = last == slots.count - 1 ? Int.max : slots[last].y + slots[last].height
        return top..<bottom
    }

    /// A placement-query context: the stack's own context with any scroll
    /// window cleared, so geometry answers are window-independent.
    private func placementContext(_ context: RenderContext) -> RenderContext {
        var placementContext = context
        placementContext.environment.scrollContentWindow = nil
        return placementContext
    }

    /// The published scroll window, when this stack is entitled to consume
    /// it: either the window names no owner (tests, direct injection —
    /// trust the publisher), or this stack is a single-child descent from
    /// the ScrollView's direct content. A stack that is one sibling among
    /// several (a lazy stack below a header, say) is NOT at the scroll
    /// origin — consuming the window there blanked the wrong rows.
    func consumableScrollWindow(context: RenderContext) -> ScrollContentWindow? {
        guard let window = context.environment.scrollContentWindow else { return nil }
        guard let owner = window.contentIdentity else { return window }
        return context.identity.isDirectDescent(from: owner) ? window : nil
    }
}

// MARK: - LayoutPlacing

extension _VStackCore: LayoutPlacing {
    func placementCount(context: RenderContext) -> Int {
        // O(1) for lazy providers (a ForEach answers from its data's count);
        // eager content pays its (already-paid) resolution.
        resolveChildViewCollection(from: content, context: placementContext(context)).count
    }

    func placement(at ordinal: Int, proposal: ProposedSize, context: RenderContext) -> Placement? {
        let queryContext = placementContext(context)
        let slots = naturalRowSlots(width: proposal.width, context: queryContext)
        guard slots.indices.contains(ordinal) else { return nil }
        let slot = slots[ordinal]
        return Placement(
            child: slot.child,
            identity: slot.child.identity(under: queryContext),
            x: 0, y: slot.y, width: slot.width, height: slot.height)
    }

    func ordinal(of target: ViewIdentity, context: RenderContext) -> Int? {
        guard let step = target.childStep(below: context.identity) else { return nil }
        let children = resolveChildViewCollection(from: content, context: placementContext(context))
        if let key = step.key {
            // Keys come from the provider's data — no row views are built.
            return children.firstOrdinal(forKey: key)
        }
        if let index = step.index {
            // Keyed children never match a positional step; a uniformly keyed
            // provider (ForEach) can answer nil without building anything.
            guard !children.isUniformlyKeyed else { return nil }
            return children.buildingAll().firstIndex {
                $0.identityChildKey == nil && $0.identityChildIndex == index
            }
        }
        return nil
    }
}
