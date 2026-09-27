//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackAnchoredMeasure.swift
//
//  The anchored window's measure: what a large, variable-height lazy stack
//  answers when asked its size, without walking every row. Its render — the
//  anchor walk and the outward fill — is `StackAnchoredWindow.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension _VStackCore {
    /// `windowSizeThatFits` for anchored (large, variable) content: the
    /// total is the running estimate, exact at the endpoints; width and
    /// flexibility come from a bounded sample. Estimation here is honest —
    /// the absolute total feeds only the scrollbar and the clip bound, both
    /// of which the design declares estimated (§3).
    ///
    /// Honest, that is, for the stack whose render consumes the scroll window,
    /// and for no other. One NESTED in a scroll view's content — below a
    /// header, or in a row of an outer lazy stack — never gets the window
    /// (`consumableScrollWindow`): it is drawn whole, by `renderWindow`'s
    /// append-while-fits walk, into the height its parent gives it, and its
    /// parent gives it the height measured here. The estimate was therefore its
    /// drawn height, and rows past it were drawn nowhere: 300 rows priced at
    /// the sixteen-row sample's one line each, of which all but sixteen were
    /// two, ended the scroll view at row 157. So that stack is measured over
    /// the rows its budget reaches instead (`reachedRows`) — exactly the rows
    /// the walk would draw.
    func anchoredSizeThatFits(
        _ children: ChildViewCollection, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? {
        let state = uniformWindowState(context: context)
        let count = children.count
        guard count > 0 else { return ViewSize.fixed(0, 0) }
        // Declined for the same reason the render declines it — see
        // `renderAnchoredWindow`.
        guard !children[0].providesAlignmentGuide else { return nil }

        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.leaveScrollOrigin()
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        let sampleProposal = ProposedSize(width: widthLimit, height: nil)
        let sampleSize = min(count, Self.anchoredWidthSampleCount)
        // Built once, for the check below and the sample: a subscript BUILDS
        // its child, and building the sixteen twice cost a million-row
        // `scrollfollow` 4-5% of its frame (measured). Declined before anything
        // is measured, because the eager path that answers instead measures
        // every row, and an exact walk here first would be paid for twice.
        let sampleChildren = (0..<sampleSize).map { children[$0] }
        guard !sampleChildren.contains(where: \.isSpacer) else { return nil }

        // A whole-content ask is not the prefix question the sample below
        // answers: it is a two-axis `ScrollView` asking how far right its
        // content can be scrolled, and a sample cannot answer it — see
        // `StackContentWidth.swift`. Which ask this is comes from
        // `contentWidthAsk`, by marks rather than by the size of the offer.
        //
        // Asked BEFORE the sample, as the uniform twin asks it: its challenge
        // can find the widest row moved and drop that row's memoized sizes, and
        // a sample taken first had already been served the old one — so the
        // ask that corrected the record answered with the width it corrected.
        //
        // Not asked of a NESTED stack outside the ideal-width probe. It is drawn
        // whole, every row its budget reaches (`reachedRows`), so the rows it
        // measures below are the rows it draws, and their width is the width
        // the question wants — which is how the eager column and a nested stack
        // of 256 rows or fewer (`windowSizeThatFits`) answer it too, whatever
        // the canvas. Asked here, the kept record made every such answer a
        // whole-content one, which reads the budget to classify itself and so
        // may not claim a natural size: in a view that scrolls both ways every
        // ask walked the stack again. The probe itself still asks, because its
        // budget can stop the walk short of rows the record has counted.
        let isNested = isNestedInScrollContent(context: context)
        let ask =
            isNested && !context.asksIdealWidth
            ? .prefix
            : context.contentWidthAsk(
                proposal: proposal, widthLimit: widthLimit, heightLimit: heightLimit)
        let exact =
            ask == .prefix
            ? nil
            : contentWidthOverAllRows(
                children, widthLimit: widthLimit, ask: ask, state: state, context: context)

        // The rows whose widths count, and the height: estimated for a stack
        // whose window will band it, exact for one that will be drawn whole.
        let counted: ArraySlice<ViewSize>
        let height: Int
        var isNatural = false
        if isNested {
            guard
                let reached = reachedRows(
                    children, built: sampleChildren, proposal: sampleProposal,
                    heightLimit: heightLimit, context: measureContext)
            else { return nil }
            // Tells the scroll view above that its content walks: see
            // `RenderCache.nestedStackWalks`. Only once the walk has answered:
            // a stack with a spacer falls back to the exact walk, which
            // measures every row whatever budget it is offered, so a smaller
            // budget would save it nothing.
            context.renderCache?.nestedStackWalks &+= 1
            (counted, height) = (reached.counted, reached.height)
            // A whole-content width ask reads the budget to classify itself
            // (`contentWidthAsk`), so only the prefix answer may claim it —
            // for a nested stack, every answer but the probe's (above).
            isNatural = reached.isNatural && exact == nil
        } else {
            (counted, height) = sampledRows(
                sampleChildren, count: count, state: state, proposal: sampleProposal,
                heightLimit: heightLimit, context: measureContext)
        }

        var maxWidth = 0
        var widthFlexible = false
        var heightFlexible = false
        for size in counted {
            // With the exact answer in hand a row counts as the walk counts it
            // — a filler its flexibility, not the budget it was measured under
            // (`wholeContentWidth(of:limit:)`) — so that this arm and the walk
            // give one answer to one question: the uniform path answers with
            // the walk from the second frame for rows of one height, and this
            // answers every frame for rows of several.
            maxWidth = max(
                maxWidth,
                exact == nil
                    ? min(size.width, widthLimit)
                    : wholeContentWidth(of: size, limit: widthLimit))
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
        }

        if let exact {
            maxWidth = max(maxWidth, exact.width)
            widthFlexible = wholeContentFlexibility(
                widthFlexible || exact.isWidthFlexible, width: maxWidth, limit: widthLimit)
        }

        return ViewSize(
            width: maxWidth, height: height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible
        ).declaringNaturalSize(isNatural)
    }

    /// The estimate: the first sixteen rows measured, the pitch averaged over
    /// them (or the running average the windowed render keeps), and every row
    /// priced at it — capped at the budget. Returns the sampled rows whose
    /// widths count, and the height.
    private func sampledRows(
        _ sample: [ChildView], count: Int, state: StackWindowState, proposal: ProposedSize,
        heightLimit: Int, context: RenderContext
    ) -> (counted: ArraySlice<ViewSize>, height: Int) {
        var estimate = state.estimatedPitch(spacing: spacing)
        var sampleTotal = 0
        var sampled: [ViewSize] = []
        sampled.reserveCapacity(sample.count)
        for (ordinal, child) in sample.enumerated() {
            let size = child.measure(proposal: proposal, context: context)
            // Sample rows are measured but never rendered — keep their memo
            // entries alive (see `AnchoredWindowFrame.pitch`).
            context.renderCache?.markActive(child.identity(under: context))
            sampleTotal += max(1, size.height) + (ordinal < count - 1 ? spacing : 0)
            sampled.append(size)
        }
        if state.measuredPitchCount < 1, !sample.isEmpty {
            estimate = max(1, sampleTotal / sample.count)
        }

        // The PITCH is a property of the content, so it averages the whole
        // sample. The WIDTH is not: this stack hugs the rows it draws, and at
        // this budget it draws the ones the exact walk would have reached —
        // so only those may widen it. Sampling sixteen rows for a width the
        // budget has room for eight of made the same stack answer 24 wide to
        // the natural-size ask on its first frame and 2 wide from its second
        // (once the render's own band-derived hypothesis took over), for a
        // tree nothing had changed.
        let prefix = min(sample.count, Self.walkedRowCount(
            budget: heightLimit, pitch: estimate, spacing: spacing, count: count))
        let total = count * estimate - spacing
        return (sampled.prefix(prefix), min(total, max(0, heightLimit)))
    }

    /// Every row a stack drawn WHOLE will draw under `heightLimit`, measured,
    /// and the height they take — `reachedRowSlots`, the same fit test the
    /// append-while-fits walk makes, so the two cannot disagree about where the
    /// stack ends. Every reached row counts for the width: the walk draws each,
    /// the last one clipped. `nil` at a spacer, whose share of the height only
    /// the full walk can distribute.
    ///
    /// `isNatural` when the walk took every row inside the budget and every
    /// row's own answer was natural: the budget then shaped nothing, and the
    /// measure memo may serve this answer to any ask at the same width with
    /// room for it (`ViewSize.isNaturalSize`). A scroll view asks its content
    /// at several budgets a pass — each rung of the natural-extent ladder, then
    /// the render's own canvas — and without the claim each ask walked every
    /// row again.
    ///
    /// Ω(rows reached) per measure, and inside a scroll view that is every row.
    /// Where the stack is drawn, that is the order of the drawing itself, which
    /// builds, measures and renders each of those rows. Where it is NOT drawn
    /// it is pure cost: a nested stack in a row of an outer lazy stack is
    /// measured whenever the outer stack places its rows, on screen or not.
    /// Forty such rows of 300 rows each, with a `@State` write above the scroll
    /// view every frame, build 14,662 rows a frame where the estimate built
    /// 4,402, each the same in three runs of the probe that counted it — one
    /// walk of each at the width the content is drawn at, since the
    /// scrollbar's first round asks the other width only a screenful
    /// (`contentOverflowsCanvas`) — see "What ships" under §6b of
    /// `Documentation/Locating things without drawing them.md`, which also
    /// says why a count of rows built can move.
    private func reachedRows(
        _ children: ChildViewCollection, built: [ChildView], proposal: ProposedSize,
        heightLimit: Int, context: RenderContext
    ) -> (counted: ArraySlice<ViewSize>, height: Int, isNatural: Bool)? {
        let slots = reachedRowSlots(
            children, built: built, heightLimit: heightLimit, width: proposal.width,
            context: context)
        guard !slots.contains(where: \.child.isSpacer) else { return nil }
        // A walk that stopped past the limit reports the LIMIT, as the exact
        // walk does (`windowSizeThatFits`): the row it stopped at is drawn
        // clipped to it.
        let bottom = slots.last.map { $0.y + $0.height } ?? 0
        let isNatural =
            slots.count == children.count && bottom <= max(0, heightLimit)
            && slots.allSatisfy(\.size.isNaturalSize)
        return (slots.map(\.size)[...], min(bottom, max(0, heightLimit)), isNatural)
    }

    /// How many rows a walk of this stack touches under `budget`: the ones
    /// that wholly fit, plus the first that does not — the exact walk measures
    /// that one too, because a windowed stack under a `ScrollView` draws its
    /// clipped remainder, and the stack hugs what it draws.
    static func walkedRowCount(budget: Int, pitch: Int, spacing: Int, count: Int) -> Int {
        guard pitch > 0 else { return count }
        let whole = max(0, min(count, (max(0, budget) + spacing) / pitch))
        return min(count, whole + (whole < count ? 1 : 0))
    }
}
