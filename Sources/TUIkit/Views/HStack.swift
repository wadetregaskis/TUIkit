//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HStack.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - HStack

/// A view that arranges its children horizontally.
///
/// `HStack` arranges its child views side by side, from left to right.
///
/// # Example
///
/// ```swift
/// HStack {
///     Text("[OK]")
///     Text("[Cancel]")
/// }
/// ```
///
/// # Alignment
///
/// ```swift
/// HStack(alignment: .top) {
///     Text("Left")
///     Text("Right")
/// }
/// ```
public struct HStack<Content: View>: View {
    /// The vertical alignment of the children.
    public let alignment: VerticalAlignment

    /// The horizontal spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// Creates a horizontal stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment of children (default: .center).
    ///   - spacing: The spacing between children in characters (default: 1).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _HStackCore(alignment: alignment, spacing: spacing, overflow: .clip, content: content)
    }
}

// MARK: - Internal HStack Core

/// Internal view that handles the actual rendering of both ``HStack`` and
/// ``LazyHStack``. The two differ only in their ``StackOverflow`` policy:
/// `HStack` is `.clip` (distribute + clip trailing columns at the cell),
/// `LazyHStack` is `.window` (append whole columns while they fit
/// `availableWidth`, stopping at the first that won't).
struct _HStackCore<Content: View>: View, Renderable, Layoutable {
    // The one-byte `overflow` after the content, not before it: before, it
    // left seven undefined bytes ahead of the word-aligned content, which the
    // per-pass memos' value hash read then and must skip now; with none, the
    // core is hashed as plain words (`ContainerLayoutPaddingTests`).
    let alignment: VerticalAlignment
    let spacing: Int
    let content: Content
    /// Trailing-overflow behaviour: `.clip` (eager `HStack`) or `.window`
    /// (lazy `LazyHStack`).
    let overflow: StackOverflow

    init(alignment: VerticalAlignment, spacing: Int, overflow: StackOverflow, content: Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
        self.overflow = overflow
    }

    var body: Never {
        fatalError("_HStackCore renders via Renderable")
    }

    /// What `resolvedLayout` decided for a row: the widths to render at, the
    /// row's own size and flexibility, and — per child — the height each was
    /// measured at and whether it fills its height. Both passes read the same
    /// answer, which is what keeps them from disagreeing.
    private struct ResolvedRowLayout {
        let widths: [Int]
        let totalWidth: Int
        let height: Int
        let fills: Bool
        let fillsHeight: Bool
        let childHeights: [Int]
        /// Bit `i` set when child `i` fills its height. A mask rather than a
        /// `[Bool]`: this routine runs once per row per walk, and one more
        /// array per call measured +1.9% on the `churn` stress page, where no
        /// row has a ramp and the answer is never read. A row of more than 64
        /// children reports every further child as filling, which only costs
        /// it a measure. See `fillsHeight(ofChildAt:)`.
        let childFillsHeightMask: UInt64
        let guideRun: AlignmentGuideRun?
        /// Whether every measured child reported a ``ViewSize/isNaturalSize``,
        /// so this row's size may claim one too — see `clipSizeThatFits`.
        let childrenAreNatural: Bool
        /// The tallest child answer this layout was built FROM, which is not
        /// always ``height``: a child squeezed narrower than its ideal is
        /// re-measured and can come back shorter, and the row's height is the
        /// max of the *final* heights. See `clipSizeThatFits` for why the
        /// difference matters.
        let tallestConsumedChild: Int

        func fillsHeight(ofChildAt index: Int) -> Bool {
            index >= UInt64.bitWidth || childFillsHeightMask & (1 << UInt64(index)) != 0
        }
    }

    /// The single sizing routine shared by `sizeThatFits` and `renderToBuffer`,
    /// so the two passes cannot disagree about widths or height — measuring each
    /// child once at its ideal, distributing, then re-measuring heights at the
    /// allocated widths. (Previously each pass had its own copy of this logic
    /// and measured children at a different proposal, which let the reported
    /// size drift from the rendered one — e.g. a nested row measured one row
    /// taller than it rendered.)
    ///
    /// - Parameter asksIdealWidth: Whether this is the ideal-width ask
    ///   (``RenderContext/asksIdealWidth`` under a nil width), which a row
    ///   answers with its children's ideal widths summed and nothing
    ///   distributed — see the comment at the distribution.
    private func resolvedLayout(
        _ children: [ChildView], availableWidth: Int, asksIdealWidth: Bool = false,
        context: RenderContext
    ) -> ResolvedRowLayout {
        let count = children.count

        var ideal = [Int](repeating: 0, count: count)
        var idealHeight = [Int](repeating: 0, count: count)
        var fills = [Bool](repeating: false, count: count)
        // Whether any child would take more HEIGHT if it were offered. Measured
        // here beside the width flexibility rather than assumed: `clipSizeThatFits`
        // reported a hard-coded `false`, which is the same under-reporting
        // `VStack` had on its own axis and fixed — a row containing anything
        // that fills its height (a ScrollView, a Spacer-bearing column, a
        // bordered box asked to grow) told its parent it was rigid, and the
        // parent then distributed vertical space as though nothing wanted any.
        var fillsHeight = false
        // Per child as well as in aggregate: the render's ramp placement
        // (below) reuses a child's measured height only when THAT child is
        // rigid, and one flexible sibling must not send the whole row back to
        // the measure it was avoiding.
        var childFillsHeightMask: UInt64 = 0
        // A row's size is its children's, so its claim to be natural is theirs.
        // Spacers take no part: they are not measured, and what they contribute
        // (a minimum length and a fill flag) is the same at any budget.
        var childrenAreNatural = true
        var tallestConsumedChild = 0
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                ideal[index] = child.spacerMinLength ?? 0
                fills[index] = true
            } else {
                // Behaviour-preserving: feed the same ideal width + reported
                // flexibility the old renderToBuffer used. The change here is
                // only that sizeThatFits now goes through this SAME routine, so
                // measure and render can no longer disagree.
                let size = child.measure(proposal: .unspecified, context: context)
                if !size.isNaturalSize { childrenAreNatural = false }
                tallestConsumedChild = max(tallestConsumedChild, size.height)
                // A child that came back filling the limit has no ideal width
                // of its own to add to the row's (`wholeContentWidth(of:limit:)`).
                ideal[index] =
                    asksIdealWidth ? wholeContentWidth(of: size, limit: availableWidth) : size.width
                idealHeight[index] = size.height
                fills[index] = size.isWidthFlexible
                if size.isHeightFlexible {
                    fillsHeight = true
                    if index < UInt64.bitWidth { childFillsHeightMask |= 1 << UInt64(index) }
                }
            }
        }

        // Full available width + spacing: the distribution charges each gap only
        // between columns it places, so an over-wide row clips its trailing
        // columns instead of collapsing every column to zero.
        //
        // Except under the ideal-width ask, where the row offers itself only
        // its children's ideal widths and their gaps — capped at the limit,
        // which still squeezes an over-wide row as above. The leftover a
        // filler takes when the row is DRAWN is the offer's width, not the
        // row's; distributed here, it made every row holding a `Spacer` or a
        // filling frame answer the ladder's rung. SwiftUI's `HStack` answers an
        // unspecified width with the sum, not an offer — measured,
        // `HStack { Text("a"); Spacer(); Text("b") }` reports 23.5 points.
        var distributable = availableWidth
        if asksIdealWidth {
            var idealTotal = 0
            var occupying = 0
            for index in ideal.indices {
                idealTotal += max(0, ideal[index])
                // Who occupies the axis, by `distributeLinearSpace`'s own rule.
                if fills[index] || ideal[index] > 0 { occupying += 1 }
            }
            distributable = min(
                availableWidth,
                idealTotal + totalLinearSpacing(occupiedChildren: occupying, spacing: max(0, spacing)))
        }
        let widths = distributeLinearSpace(
            naturalSizes: ideal, isFlexible: fills, available: distributable, spacing: spacing)

        // Heights at the widths children will actually be given. A child given
        // at least its ideal width wraps no further than it did at `.unspecified`
        // (its ideal width is where it wrapped, and the allocation never exceeds
        // the available width that ideal was measured against), so its height is
        // the one already measured — reuse it. Only a child squeezed *narrower*
        // than its ideal can grow taller, so only those are re-measured. This
        // halves the per-child measures in the common (un-squeezed) case.
        var height = 1
        var finalHeight = [Int](repeating: 0, count: count)
        for (index, child) in children.enumerated() where !child.isSpacer {
            if widths[index] >= ideal[index] {
                finalHeight[index] = idealHeight[index]
            } else {
                let size = child.measure(proposal: ProposedSize(width: widths[index], height: nil), context: context)
                if !size.isNaturalSize { childrenAreNatural = false }
                tallestConsumedChild = max(tallestConsumedChild, size.height)
                finalHeight[index] = size.height
            }
            height = max(height, finalHeight[index])
        }

        // Explicit vertical guides are resolved HERE, off the same measured
        // heights both passes share, rather than separately off the rendered
        // buffers — measure and render must not be able to disagree about the
        // row's height, which a guide can grow past the tallest child. Spacers
        // have no visual box and take no part.
        // Asked before the arrays are built: see ``anyAlignmentGuide(in:)``.
        // This routine runs once per row per walk, and the three arrays below
        // exist only to be thrown away by the guard inside the run builder.
        var guideRun: AlignmentGuideRun?
        if anyAlignmentGuide(in: children) {
            let placed = children.indices.filter { !children[$0].isSpacer }
            guideRun = verticalGuideRun(
                placed.map { children[$0] },
                sizes: placed.map { (width: widths[$0], height: finalHeight[$0]) },
                alignment: alignment,
                minimumExtent: height)
        }

        // Gaps between the columns the row actually PLACES, not one per child.
        // PASS 3 appends a zero-width child through
        // `FrameBuffer.appendHorizontally`'s contributes-nothing branch, which
        // charges no gap — so one gap per child made this report a `spacing` per
        // `EmptyView` the row never draws: `HStack(spacing: 2) { Text("A");
        // EmptyView(); Text("B") }` measured 6 and drew "A  B" (4). `widths` is
        // the array PASS 3 assembles from, so this is the render's own count and
        // not a second guess at it — a column allocated 0 cells is clipped to
        // empty lines (`ansiAwarePrefixWithWidth` returns "" at visibleCount 0)
        // and a 0-width spacer's `FrameBuffer(emptyWithWidth: 0, …)` is all "",
        // so both take that same branch.
        let totalWidth =
            widths.reduce(0, +)
            + totalLinearSpacing(occupiedChildren: widths.count { $0 > 0 }, spacing: spacing)
        return ResolvedRowLayout(
            widths: widths,
            totalWidth: min(totalWidth, max(0, availableWidth)),
            height: guideRun?.extent ?? height,
            fills: fills.contains(true),
            fillsHeight: fillsHeight,
            childHeights: finalHeight,
            childFillsHeightMask: childFillsHeightMask,
            guideRun: guideRun,
            childrenAreNatural: childrenAreNatural,
            tallestConsumedChild: tallestConsumedChild)
    }

    /// The explicit-guide run over the columns a lazy row actually placed, or
    /// `nil` — the common answer, which is why the question is asked before the
    /// three arrays that would carry it are built. See ``anyAlignmentGuide(in:)``.
    private func placedGuideRun(
        _ collected: [(FrameBuffer, Int, ChildView?)], minimumExtent: Int
    ) -> AlignmentGuideRun? {
        guard anyAlignmentGuide(in: collected.compactMap(\.2)) else { return nil }
        let placed = collected.compactMap { entry in entry.2.map { ($0, entry.0) } }
        return verticalGuideRun(
            placed.map(\.0),
            sizes: placed.map { (width: $0.1.width, height: $0.1.height) },
            alignment: alignment,
            minimumExtent: minimumExtent)
    }

    /// Measures the HStack without rendering.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let context = context.publishingContainerAxis(.horizontal)
        switch overflow {
        case .clip: return clipSizeThatFits(proposal: proposal, context: context)
        case .window: return windowSizeThatFits(proposal: proposal, context: context)
        }
    }

    /// `.clip` size: the shared `resolvedLayout` (measure → distribute → height),
    /// reported with its analytic total width clamped to the constraint.
    private func clipSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }
        let widthLimit = proposal.width ?? context.availableWidth
        let asksIdealWidth = proposal.width == nil && context.asksIdealWidth
        let layout = resolvedLayout(
            children, availableWidth: widthLimit, asksIdealWidth: asksIdealWidth, context: context)
        // Natural when its children are AND the row is at least as tall as the
        // tallest answer it was built from. A row reads the vertical budget
        // nowhere: it measures children at their ideal, distributes WIDTH, and
        // reports the tallest — unclamped, so a row taller than the space it was
        // given still says so. Its own width question is the effective width
        // (`proposal.width ?? context.availableWidth`), and its children are
        // measured against `context.availableWidth`; the memo keys on both.
        //
        // The height test is the part that is easy to miss. A child's natural
        // claim only reaches budgets down to its OWN height, and a child squeezed
        // narrower than its ideal is re-measured and can come back shorter — so
        // the row can end up shorter than an answer it consumed, and claiming
        // natural there would offer the row at budgets where one of the answers
        // underneath it had already lapsed.
        //
        // Under the ideal-width ask a CAPPED row is not flexible, as a column's
        // is not (`wholeContentFlexibility(_:width:limit:)`): the ladder stops
        // climbing at a flexible answer that reached its budget.
        return ViewSize(
            width: layout.totalWidth,
            height: layout.height,
            isWidthFlexible: asksIdealWidth
                ? wholeContentFlexibility(layout.fills, width: layout.totalWidth, limit: widthLimit)
                : layout.fills,
            isHeightFlexible: layout.fillsHeight
        ).declaringNaturalSize(layout.childrenAreNatural && layout.tallestConsumedChild <= layout.height)
    }

    /// `.window` size, computed analytically from the same append-while-fits
    /// walk `renderWindow` performs (Stage 3 of "Locating things without
    /// drawing them": measuring must not render). Children accumulate left to
    /// right at their `.unspecified` measures — exactly the fit-check the
    /// render uses — and the size stops at the first column that would
    /// overflow the width limit, so the width ends on a child boundary just
    /// as the render's does; the height is the tallest fitting column's.
    /// Flexibility mirrors the fill rules: a (horizontal) spacer fills the
    /// width, and any width/height-flexible child fills its axis.
    ///
    /// A stack WITH a spacer keeps the render-based measure: spacer widths
    /// come from distributing the leftover after every sibling has rendered,
    /// which is genuinely a property of the fill, not of any one child.
    /// (`renderWindow` forfeits laziness for spacers for the same reason.)
    private func windowSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true

        let children = resolveChildViews(from: content, context: measureContext)
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }
        let widthLimit = proposal.width ?? context.availableWidth

        var widthFlexible = false
        var heightFlexible = false
        var hasSpacer = false
        var sizes: [ViewSize] = []
        sizes.reserveCapacity(children.count)
        for child in children {
            if child.isSpacer {
                hasSpacer = true
                widthFlexible = true
                sizes.append(ViewSize.fixed(0, 0))
                continue
            }
            let size = child.measure(proposal: .unspecified, context: measureContext)
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
            sizes.append(size)
        }

        if hasSpacer {
            let size = measureFixedByRendering(self, proposal: proposal, context: context)
            return ViewSize(
                width: size.width, height: size.height,
                isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
        }

        var width = 0
        var height = 1
        for size in sizes {
            // A gap only between columns that occupy cells, as `renderWindow`
            // assembles them: see `linearSpacing(before:placedExtent:spacing:)`.
            let next = width + linearSpacing(before: size.width, placedExtent: width, spacing: spacing) + size.width
            if next > widthLimit {
                // Saturated: content extends past the limit. Report the LIMIT
                // — see the identical break in _VStackCore.windowSizeThatFits:
                // a column-boundary report a few cells under the budget ended
                // measureNaturalExtent's ladder on its first rung, truncating
                // horizontally-scrollable content at ~the starting budget.
                // The partially-shown column's height still counts.
                width = widthLimit
                height = max(height, size.height)
                break
            }
            width = next
            height = max(height, size.height)
        }
        // The vertical twin of the run `_VStackCore.windowSizeThatFits`
        // resolves, and here for the same reason: `renderWindow` computes
        // `placedGuideRun(collected, minimumExtent: maxHeight)` and places
        // every buffer into `guideRun?.extent ?? maxHeight`, which an explicit
        // `.alignmentGuide` is allowed to push PAST the tallest column. Taking
        // the tallest alone measured shorter than the render drew. Costs
        // nothing where no column sets a guide — `anyAlignmentGuide` is asked
        // first — which is almost always.
        let guideRun = anyAlignmentGuide(in: children)
            ? verticalGuideRun(
                children,
                sizes: sizes.map { (width: $0.width, height: $0.height) },
                alignment: alignment,
                minimumExtent: height)
            : nil
        return ViewSize(
            width: width, height: guideRun?.extent ?? height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let context = context.publishingContainerAxis(.horizontal)
        switch overflow {
        case .clip: return renderClip(context: context)
        case .window: return renderWindow(context: context)
        }
    }

    /// `.clip` render (eager `HStack`): the shared `resolvedLayout` distributes
    /// the width (clipping trailing columns at the cell), children render into the
    /// row height, are vertically aligned, and the row is clamped.
    private func renderClip(context: RenderContext) -> FrameBuffer {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        let layout = resolvedLayout(children, availableWidth: context.availableWidth, context: context)
        let finalWidths = layout.widths

        // The row is as tall as the tallest child, bounded by the space the
        // stack itself was given. Children render into exactly this height
        // so a child squeezed narrow enough to wrap truncates (with an
        // ellipsis) instead of silently spilling an extra row that the
        // parent — which measured the stack as shorter — then clips.
        let rowHeight = max(1, min(layout.height, context.availableHeight))
        // Empty children (e.g. `if false { ChildView() }`, which
        // ViewBuilder lowers to `Optional<ChildView>.none`, and
        // `EmptyView()`) are filtered from layout entirely: they
        // contribute no width, and FrameBuffer.appendHorizontally
        // drops the spacing slot they would otherwise have claimed.
        // This matches SwiftUI's HStack semantics — a non-rendering
        // child is treated as if it weren't in the children list at
        // all. To reserve a column regardless, opt in with a sized
        // placeholder (Color.clear.frame(width: 1), Spacer with an
        // explicit width, etc.) — note that EmptyView() in an else
        // branch will also be filtered.
        // Children render before any of them is placed: an explicit
        // `.alignmentGuide` is resolved against the size a child actually
        // rendered at, and the row's height can grow past the tallest child
        // when a guide pushes one down.
        // A `.gradientExtent(.subtree)` ramp needs each child to know where it
        // sits in the rectangle the ramp spans. Horizontally that is exactly
        // what `resolvedLayout` just distributed — exact. Vertically it is not:
        // alignment is applied below, off the rendered heights, so it is taken
        // from the measured ones, which is what they are for.
        // The row's own content size, from the distribution above — the same
        // service `VStack` performs for an enclosing `.gradientExtent(.subtree)`.
        // Read from `resolvedLayout` rather than recomputed: this WAS a second
        // copy of the sum-and-clamp, spacing rule included, and `totalWidth` is
        // the same expression over the same widths (`min(sum + gaps,
        // availableWidth)`, and `resolvedLayout` was handed this very
        // `context.availableWidth`).
        let gradientFrame = context.gradientContentFrame(
            width: layout.totalWidth, height: rowHeight)
        var gradientX = 0
        var buffers: [FrameBuffer?] = []
        buffers.reserveCapacity(children.count)
        for (index, child) in children.enumerated() {
            // The ramp advances by what the row DRAWS. A column of no cells is
            // appended through `appendHorizontally`'s contributes-nothing branch
            // and earns no gap, so it must not push the ramp along by one
            // either. `gradientX > 0` rather than `index > 0` because that same
            // branch withholds the gap while nothing has been placed yet (its
            // `spacingApplied = priorWidth > 0 ? spacing : 0`), so a LEADING
            // empty child must not indent the ramp.
            if gradientX > 0, finalWidths[index] > 0 { gradientX += spacing }
            var childContext = context
            // A spacer renders nothing and takes no ramp position: its context
            // is never used, so nothing is measured or built for it.
            if gradientFrame != nil, !child.isSpacer {
                // The height the child will stand in the row at. For a rigid
                // child it is the height `resolvedLayout` already measured —
                // at the width the child is about to be rendered at — because
                // a height proposal of `rowHeight` cannot change a rigid
                // answer: `rowHeight` is at least every measured height unless
                // the stack itself was clamped, and a clamped child reports
                // `rowHeight` either way, leaving no slack in both readings.
                // Only a child that FILLS its height answers a height proposal
                // differently (it takes it), so only that child is asked
                // again. Measuring every child here a second time was ~20% of
                // the row's render on the `gradients` stress page.
                let childHeight =
                    layout.fillsHeight(ofChildAt: index)
                    ? child.measure(
                        proposal: ProposedSize(width: finalWidths[index], height: rowHeight),
                        context: context
                    ).height
                    : layout.childHeights[index]
                let slack = max(0, rowHeight - childHeight)
                let y =
                    switch alignment {
                    case .top: 0
                    case .bottom: slack
                    default: slack / 2
                    }
                childContext = context.placingGradientChild(gradientFrame, x: gradientX, y: y)
            }
            buffers.append(
                child.isSpacer
                    ? nil
                    : child.render(
                        width: finalWidths[index], height: rowHeight, context: childContext))
            gradientX += finalWidths[index]
        }

        // The guide run came from `resolvedLayout`, off the same measured
        // heights `sizeThatFits` reported — not off these buffers — so the two
        // passes cannot disagree about where a guided child sits.
        let guideRun = layout.guideRun

        var result = FrameBuffer()
        var placedIndex = 0
        for index in children.indices {
            let spacingToApply = index > 0 ? spacing : 0
            guard let buffer = buffers[index] else {
                result.appendHorizontally(
                    FrameBuffer(emptyWithWidth: finalWidths[index], height: rowHeight),
                    spacing: spacingToApply)
                continue
            }
            defer { placedIndex += 1 }
            // A child shorter than the row is positioned within it by
            // `alignment` (top/center/bottom). Without this every child is
            // top-pinned, because `appendHorizontally` only top-aligns.
            let aligned =
                guideRun.map {
                    buffer.placedVertically(
                        inHeight: rowHeight, topPadding: $0.offsets[placedIndex])
                } ?? buffer.verticallyAligned(toHeight: rowHeight, alignment: alignment)
            result.appendHorizontally(aligned, spacing: spacingToApply)
        }

        // Final guard: the assembled row never exceeds the space we were given,
        // even when inter-child spacing alone would overflow a tiny terminal.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// `.window` render (lazy `LazyHStack`): append whole children left-to-right
    /// while they fit `availableWidth`, stopping at the first that won't. Columns
    /// beyond the available width are never rendered.
    /// `.window` render (lazy `LazyHStack`): append whole children left-to-right
    /// while they fit `availableWidth`, stopping at the first that won't.
    /// Children beyond that first overflow are never rendered (when no Spacer
    /// is present).
    ///
    /// Children resolve through the two-pass `ChildView` API — the same one the
    /// `.clip` path uses — so `ChildViewProvider` content (a `ForEach`, above
    /// all) expands to its individual columns with per-child identities. The
    /// legacy single-pass `resolveChildInfos` used here before only expanded
    /// `ChildInfoProvider`s, which `ForEach` is not, so `LazyHStack { ForEach }`
    /// rendered nothing at all (issue #8).
    private func renderWindow(context: RenderContext) -> FrameBuffer {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return FrameBuffer() }
        let availableWidth = context.availableWidth

        // A ramp spanning this row needs each column's place in it before the
        // column renders, and this path renders as it walks — so the placement
        // is measured up front, stopping at the same fold the walk will. Costs
        // nothing without a `.gradientExtent(.subtree)` above.
        let (gradientFrame, gradientOffsets) = windowGradientPlacement(children, context: context)
        func columnContext(_ index: Int) -> RenderContext {
            guard index < gradientOffsets.count else { return context }
            return context.placingGradientChild(
                gradientFrame, x: gradientOffsets[index].x, y: gradientOffsets[index].y)
        }

        // Spacer distribution (same as HStack) needs every non-spacer child's
        // rendered width up front, so the presence of a Spacer forfeits the
        // early-stop: pre-render everything, as the single-pass path always
        // did. The common spacer-less lazy stack keeps its laziness below.
        let spacerCount = children.count { $0.isSpacer }
        var eagerBuffers: [FrameBuffer?] = []
        var spacerWidth = 0
        var spacerRemainder = 0
        if spacerCount > 0 {
            eagerBuffers = children.enumerated().map { index, child in
                child.isSpacer
                    ? nil
                    : child.render(
                        width: availableWidth, height: context.availableHeight,
                        context: columnContext(index))
            }
            let fixedWidth = eagerBuffers.compactMap { $0?.width }.reduce(0, +)
            // Gaps between the columns that will occupy cells — every spacer and
            // every column that drew some — the count `distributeLinearSpace`
            // reserves for the eager row. One per child left a Spacer beside an
            // `EmptyView` a `spacing` short of flush.
            let totalSpacing = totalLinearSpacing(occupiedChildren: spacerCount + eagerBuffers.count { ($0?.width ?? 0) > 0 }, spacing: spacing)
            let availableForSpacers = max(0, availableWidth - fixedWidth - totalSpacing)
            spacerWidth = availableForSpacers / spacerCount
            spacerRemainder = availableForSpacers % spacerCount
        }

        // === PASS 1: Collect the children that fit (rendering on demand)
        //             and compute the max height ===
        // Each entry: (buffer, spacingBefore, isSpacer). The walk stops at the
        // first child that would overflow.
        var collected: [(FrameBuffer, Int, ChildView?)] = []
        var maxHeight = 1
        var currentWidth = 0
        var spacerIndex = 0

        // Every gap below is `linearSpacing(before:placedExtent:spacing:)`, the
        // rule PASS 2's `appendHorizontally` applies: a column of no cells earns
        // none. Charged per index, the fit-check spent a gap per `EmptyView` that
        // PASS 2 never drew, and stopped before a column that fitted.
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                let extraWidth = spacerIndex < spacerRemainder ? 1 : 0
                let width = max(child.spacerMinLength ?? 0, spacerWidth + extraWidth)
                let spacingToApply = linearSpacing(before: width, placedExtent: currentWidth, spacing: spacing)
                if currentWidth + spacingToApply + width > availableWidth { break }
                // Spacer height is set to maxHeight in pass 2
                collected.append((FrameBuffer(emptyWithWidth: width, height: 1), spacingToApply, nil))
                currentWidth += spacingToApply + width
                spacerIndex += 1
            } else if spacerCount > 0 {
                let buffer = eagerBuffers[index]!
                let spacingToApply = linearSpacing(before: buffer.width, placedExtent: currentWidth, spacing: spacing)
                if currentWidth + spacingToApply + buffer.width > availableWidth { break }
                maxHeight = max(maxHeight, buffer.height)
                collected.append((buffer, spacingToApply, child))
                currentWidth += spacingToApply + buffer.width
            } else {
                // Fit-check on a (side-effect-free) measure BEFORE rendering —
                // see renderWindow in VStack.swift: rendering-to-check fired
                // the first overflowing child's lifecycle every frame.
                let measured = child.measure(proposal: .unspecified, context: context)
                let spacingToApply = linearSpacing(before: measured.width, placedExtent: currentWidth, spacing: spacing)
                if currentWidth + spacingToApply + measured.width > availableWidth {
                    // Saturated: the column does not fit whole. Render what
                    // shows, clipped at the cell, so the row fills the limit
                    // the measure reports — see the identical break in
                    // VStack's renderWindow.
                    let remaining = availableWidth - currentWidth - spacingToApply
                    if remaining > 0 {
                        let buffer = child.render(
                            width: measured.width, height: context.availableHeight,
                            context: columnContext(index))
                        let clipped = buffer.clamped(toWidth: remaining, height: buffer.height)
                        maxHeight = max(maxHeight, clipped.height)
                        collected.append((clipped, spacingToApply, child))
                        currentWidth += spacingToApply + clipped.width
                    } else if spacingToApply > 0 {
                        // Only (part of) the spacing shows — account it,
                        // render nothing. See the identical break in VStack.
                        // As an explicit blank block: the assembler drops the
                        // spacing of an EMPTY buffer.
                        let spacingShown = min(spacingToApply, availableWidth - currentWidth)
                        collected.append(
                            (FrameBuffer(emptyWithWidth: spacingShown, height: 1), 0, nil))
                        currentWidth += spacingShown
                    }
                    break
                }
                let buffer = child.render(
                    width: availableWidth, height: context.availableHeight,
                    context: columnContext(index))
                let renderedGap = linearSpacing(before: buffer.width, placedExtent: currentWidth, spacing: spacing)
                if currentWidth + renderedGap + buffer.width > availableWidth { break }
                maxHeight = max(maxHeight, buffer.height)
                collected.append((buffer, renderedGap, child))
                currentWidth += renderedGap + buffer.width
            }
        }

        // === PASS 2: Apply vertical alignment and build result ===
        // Explicit guides resolve over the columns actually placed — a lazy row
        // stops at the first child that will not fit, so that is the run.
        let guideRun = placedGuideRun(collected, minimumExtent: maxHeight)
        let finalHeight = guideRun?.extent ?? maxHeight

        var result = FrameBuffer()
        var placedIndex = 0
        for (buffer, spacingToApply, child) in collected {
            guard child != nil else {
                result.appendHorizontally(
                    FrameBuffer(emptyWithWidth: buffer.width, height: finalHeight),
                    spacing: spacingToApply)
                continue
            }
            defer { placedIndex += 1 }
            let aligned =
                guideRun.map {
                    buffer.placedVertically(
                        inHeight: finalHeight, topPadding: $0.offsets[placedIndex])
                } ?? buffer.verticallyAligned(toHeight: maxHeight, alignment: alignment)
            result.appendHorizontally(aligned, spacing: spacingToApply)
        }

        return result
    }
}

// MARK: - Equatable

extension HStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: HStack<Content>, rhs: HStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}
