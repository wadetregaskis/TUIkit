//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// between consecutive children.
    ///
    /// Pass the width the rows will actually render at: a wrapping `Text`
    /// measures taller at the real width than unconstrained, and the slot
    /// height is authoritative — the windowed render pads/clamps the row to
    /// it, so a width-blind slot would clip wrapped rows.
    ///
    /// Measurement-only: no rendering, no side effects. Callers inside a
    /// scroll window must pass a context whose `scrollContentWindow` is
    /// cleared (descendants aren't at the scroll origin).
    func naturalRowSlots(width: Int?, context: RenderContext) -> [RowSlot] {
        let children = resolveChildViews(from: content, context: context)
        let proposal = ProposedSize(width: width, height: nil)
        var slots: [RowSlot] = []
        slots.reserveCapacity(children.count)
        var runningY = 0
        for (index, child) in children.enumerated() {
            let spacingBefore = index > 0 ? spacing : 0
            let size = child.measure(proposal: proposal, context: context)
            let y = runningY + spacingBefore
            slots.append(RowSlot(child: child, y: y, size: size, spacingBefore: spacingBefore))
            runningY = y + size.height
        }
        return slots
    }

    /// A placement-query context: the stack's own context with any scroll
    /// window cleared, so geometry answers are window-independent.
    private func placementContext(_ context: RenderContext) -> RenderContext {
        var placementContext = context
        placementContext.environment.scrollContentWindow = nil
        return placementContext
    }
}

// MARK: - LayoutPlacing

extension _VStackCore: LayoutPlacing {
    func placementCount(context: RenderContext) -> Int {
        resolveChildViews(from: content, context: placementContext(context)).count
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
        let children = resolveChildViews(from: content, context: placementContext(context))
        if let key = step.key {
            return children.firstIndex { $0.identityChildKey == key }
        }
        if let index = step.index {
            return children.firstIndex { $0.identityChildKey == nil && $0.identityChildIndex == index }
        }
        return nil
    }
}
