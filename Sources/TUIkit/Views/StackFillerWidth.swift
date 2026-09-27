//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackFillerWidth.swift
//
//  How the uniform seek counts the rows that FILLED the width they were
//  offered — the width-flexible ones: a `Spacer` between two texts, a
//  `.frame(maxWidth: 40)` offered less than 40 — when it answers an ask from
//  the widths its render recorded.
//
//  A row with a width of its own is the same width at any ask that can hold
//  it, so the render's measure of it answers every later one. A row that
//  filled its offer reported the offer (or, squeezed, a column or two less),
//  and at a wider ask it is somewhere between that and the ask: the whole ask
//  for a true filler, its cap for a capped one — and flexible or not
//  accordingly. The render and its askers do
//  not agree on the offer, either. A `ScrollView` measures its content at its
//  own width and renders it at that width less the scrollbar's column, and a
//  resize changes the width every later ask is made at while the records
//  still hold the old one. Answered with the render's number, a `TabView` —
//  which sizes its panel to it — cut the scrollbar off from the second frame
//  on, and after a resize drew the list at the old terminal's width.
//
//  The rule: a row that filled R is as wide as any ask up to R, and still
//  filling it, which costs nothing to answer; asked wider, it is measured at
//  the ask, which is what the exact walk that answers the first frame does.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension _VStackCore {
    /// `width` — the seek's answer from the rows with a width of their own,
    /// capped at `widthLimit` — with the flexible rows, which FILLED their
    /// offer, counted as they are at this ask; and whether the stack is
    /// width-flexible here, which only they can make it.
    ///
    /// A filler that filled at least `widthLimit` fills this ask: the answer
    /// is the limit, flexible, and nothing is measured. That is every frame of
    /// the common case — a list rendered at the width it is asked at, or
    /// asked narrower. Asked wider than any filled, each known filler is
    /// measured at the ask, as the exact walk measures it, stopping once the
    /// answer is at the limit and flexible: one row for a list of true
    /// fillers, whose first answers with the whole ask. Only capped rows,
    /// filled below a cap the ask is past, cost a measure each — the rows the
    /// budget reaches, as the walk's do.
    ///
    /// Asked for its IDEAL width (``RenderContext/asksIdealWidth``), a filler
    /// has no reach: it answers with its content, measured under a nil width
    /// and counted as the walk counts it (``wholeContentWidth(of:limit:)``).
    ///
    /// Which fillers count toward the width: every row from the first known
    /// one to the end of what the records were seeded from (every row the
    /// budget reaches, for a stack the walk answers), the fillers the records
    /// keep beyond that (the first to fill as far as each), and the fillers
    /// the last render drew — the floor ``StackWindowState/bandWidth`` keeps
    /// for the others. A row before the first filler has a width of its own;
    /// a row measured here that has one answers with it, which is the answer
    /// the walk gives. The walk's flexibility is over every row, so the
    /// fillers the records keep past the budget are asked too, while nothing
    /// yet says flexible.
    ///
    /// Nothing measured here is kept: the records are a sample, which only the
    /// render path may write (``RenderContext/isMeasuring``).
    func widthCountingFillers(
        _ width: Int, children: ChildViewCollection, walked: Int, state: StackWindowState,
        proposal: ProposedSize, widthLimit: Int, context: RenderContext
    ) -> (width: Int, isFlexible: Bool) {
        let records = state.rowWidths
        let bandReach = state.bandFillReach
        let anyReach = max(records.fillReach(forFirst: children.count), bandReach)
        guard anyReach > 0 || !state.bandFillers.isEmpty else { return (width, false) }
        let asksIdealWidth = proposal.width == nil && context.asksIdealWidth
        if !asksIdealWidth, max(records.fillReach(forFirst: walked), bandReach) >= widthLimit {
            return (widthLimit, true)
        }

        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.leaveScrollOrigin()
        let rowProposal = ProposedSize(width: asksIdealWidth ? nil : widthLimit, height: nil)
        func measured(_ ordinal: Int) -> ViewSize {
            let child = children[ordinal]
            let size = child.measure(proposal: rowProposal, context: measureContext)
            // Measured but perhaps not drawn — keep the memo entry past the
            // pass GC, as the seed and the sample do.
            measureContext.renderCache?.markActive(child.identity(under: measureContext))
            return size
        }
        var result = width
        var flexible = !asksIdealWidth && anyReach >= widthLimit
        // Whether nothing left can change the answer: it is at the limit, and
        // flexible — or under the ideal ask, where a capped answer never is
        // (``wholeContentFlexibility(_:width:limit:)``).
        var isSettled: Bool { result >= widthLimit && (flexible || asksIdealWidth) }
        func counts(_ ordinal: Int) -> Bool {
            let size = measured(ordinal)
            result = max(
                result,
                asksIdealWidth
                    ? wholeContentWidth(of: size, limit: widthLimit) : min(size.width, widthLimit))
            if size.isWidthFlexible { flexible = true }
            return isSettled
        }

        if isSettled { return (widthLimit, !asksIdealWidth) }
        if let first = records.firstFiller(before: walked) {
            let seeded = max(first, min(walked, Self.seededRowCount(children.count)))
            for ordinal in first..<seeded where counts(ordinal) {
                return (widthLimit, !asksIdealWidth)
            }
            for ordinal in records.recordedFillers(in: seeded..<walked) where counts(ordinal) {
                return (widthLimit, !asksIdealWidth)
            }
        }
        // The band is the last render's, and the collection may have lost rows
        // since: a row past the end is not drawn any more.
        for ordinal in state.bandFillers where ordinal < children.count && counts(ordinal) {
            return (widthLimit, !asksIdealWidth)
        }
        if !flexible {
            for ordinal in records.recordedFillers(in: walked..<children.count)
            where measured(ordinal).isWidthFlexible {
                flexible = true
                break
            }
        }
        return (
            result,
            asksIdealWidth
                ? wholeContentFlexibility(flexible, width: result, limit: widthLimit) : flexible
        )
    }
}
