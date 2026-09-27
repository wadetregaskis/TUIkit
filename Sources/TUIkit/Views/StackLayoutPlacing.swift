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
            keepsMeasuresLive: keepsMeasuresLive, stoppingPast: nil)
    }

    /// The slots of the rows `renderWindow`'s append-while-fits walk DRAWS
    /// under `heightLimit`: every row that wholly fits, then the first that
    /// does not, which it draws clipped at the cell (`appendSaturatedTail`).
    ///
    /// Built one ordinal at a time and stopped there, so it touches the rows
    /// the drawing will: every row for a stack whose budget holds all of them,
    /// a screenful for one whose budget is a screen. Marks what it measures
    /// live, as a lazy stack's walk does (see above).
    ///
    /// - Parameter built: Children already built by the caller, reused rather
    ///   than built again for the leading ordinals they cover.
    func reachedRowSlots(
        _ children: ChildViewCollection, built: [ChildView] = [], heightLimit: Int, width: Int?,
        context: RenderContext
    ) -> [RowSlot] {
        rowSlots(
            count: children.count, childAt: { $0 < built.count ? built[$0] : children[$0] },
            width: width, context: context, keepsMeasuresLive: true, stoppingPast: heightLimit)
    }

    /// The one slot rule, walked over `count` children in order, each fetched
    /// by ordinal from `childAt` — so a caller holding a lazily built
    /// collection hands out only the rows the walk actually takes — and
    /// stopped after the first slot whose bottom passes `heightLimit`, when
    /// one is given.
    private func rowSlots(
        count: Int, childAt: (Int) -> ChildView, width: Int?, context: RenderContext,
        keepsMeasuresLive: Bool, stoppingPast heightLimit: Int?
    ) -> [RowSlot] {
        let proposal = ProposedSize(width: width, height: nil)
        let liveMarks = keepsMeasuresLive ? context.renderCache : nil
        var slots: [RowSlot] = []
        // Only an unbounded walk knows it will take every row; a bounded one
        // over a million rows may take forty.
        if heightLimit == nil { slots.reserveCapacity(count) }
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
            // The fit test `renderWindow` and `windowSizeThatFits` both make:
            // this row is the first that does not fit whole.
            if let heightLimit, runningY > heightLimit { break }
        }
        return slots
    }

    /// The rows the full walk draws for a viewport from `top` to `bottom`, in
    /// the stack's lines: those meeting it, plus one margin row past each edge
    /// of that run, so a directional focus move can step just beyond the
    /// window. A contiguous run, whose lines ``drawnLines(of:renders:)`` names.
    static func windowRows(of slots: [RowSlot], top: Int, bottom: Int) -> [Bool] {
        var renders = slots.map { $0.y + $0.height > top && $0.y < bottom }
        if let first = renders.firstIndex(of: true), first > 0 {
            renders[first - 1] = true
        }
        if let last = renders.lastIndex(of: true), last < slots.count - 1 {
            renders[last + 1] = true
        }
        return renders
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
    /// window cleared, so geometry answers are window-independent — and, for a
    /// windowed stack, the scroll content's origin passed, as its layout
    /// passes it to the rows it measures (`RenderContext.leaveScrollOrigin()`),
    /// so a row is asked here the question the layout asks it. An eager
    /// column hands its rows its own context, and a lone row of one is at the
    /// origin still.
    private func placementContext(_ context: RenderContext) -> RenderContext {
        var placementContext = context
        switch overflow {
        case .clip: placementContext.environment.scrollContentWindow = nil
        case .window: placementContext.leaveScrollOrigin()
        }
        return placementContext
    }

    /// The published scroll window, when this stack is entitled to consume
    /// it: either the window names no owner (tests, direct injection —
    /// trust the publisher), or this stack is a single-child descent from
    /// the ScrollView's direct content. A stack that is one sibling among
    /// several (a lazy stack below a header, say) is NOT at the scroll
    /// origin — consuming the window there blanked the wrong rows.
    func consumableScrollWindow(context: RenderContext) -> ScrollContentWindow? {
        guard let window = context.environment.scrollContentWindow,
            window.isAtOrigin(context.identity)
        else { return nil }
        return window
    }

    /// Whether this stack is inside a scroll view's content WITHOUT being the
    /// stack that consumes its window — a lazy stack below a header, say, or
    /// one inside a row of an outer lazy stack.
    ///
    /// Such a stack is drawn whole by `renderWindow`'s append-while-fits walk,
    /// into the height its parent gives it, and its parent gives it the height
    /// this stack MEASURED: so its measure is the drawing's extent, not an
    /// estimate for a scrollbar.
    ///
    /// The measure-time twin of ``consumableScrollWindow(context:)``, asked of
    /// the origin the scroll view marks for its measures and its render alike
    /// (`RenderContext.scrollContentOriginDepth`), since a measure has no window
    /// to ask. No origin means no scroll view above — or a window injected
    /// directly, which the render trusts — and is not this. An origin already
    /// passed (`RenderContext.leaveScrollOrigin()`) is this, whatever steps
    /// lead here.
    func isNestedInScrollContent(context: RenderContext) -> Bool {
        let origin = context.scrollContentOriginDepth
        guard origin > 0 else { return false }
        guard origin != RenderContext.belowScrollContentOrigin else { return true }
        return !context.identity.isDirectDescent(fromDepth: Int(origin) - 1)
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
