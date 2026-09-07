//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VStack.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - VStack

/// A view that arranges its children vertically.
///
/// `VStack` stacks its child views on top of each other, from top to bottom.
/// This corresponds to the default behavior in a terminal.
///
/// # Example
///
/// ```swift
/// VStack {
///     Text("Line 1")
///     Text("Line 2")
///     Text("Line 3")
/// }
/// ```
///
/// # Alignment
///
/// ```swift
/// VStack(alignment: .center) {
///     Text("Short")
///     Text("Longer text")
/// }
/// ```
public struct VStack<Content: View>: View {
    /// The horizontal alignment of the children.
    public let alignment: HorizontalAlignment

    /// The vertical spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// Creates a vertical stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The horizontal alignment of children (default: .center, like SwiftUI).
    ///   - spacing: The spacing between children in lines (default: 0).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _VStackCore(alignment: alignment, spacing: spacing, overflow: .clip, content: content)
    }
}

// MARK: - Internal VStack Core

/// Internal view that handles the actual rendering of both ``VStack`` and
/// ``LazyVStack``. The two differ only in their ``StackOverflow`` policy:
/// `VStack` is `.clip` (distribute + clip trailing rows at the cell),
/// `LazyVStack` is `.window` (append whole rows while they fit `availableHeight`,
/// stopping at the first that won't).
struct _VStackCore<Content: View>: View, Renderable, Layoutable {
    let alignment: HorizontalAlignment
    let spacing: Int
    /// Trailing-overflow behaviour: `.clip` (eager `VStack`) or `.window`
    /// (lazy `LazyVStack`).
    let overflow: StackOverflow
    let content: Content

    var body: Never {
        fatalError("_VStackCore renders via Renderable")
    }

    /// Measures the VStack without rendering.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let context = context.publishingContainerAxis(.vertical)
        switch overflow {
        case .clip: return clipSizeThatFits(proposal: proposal, context: context)
        case .window: return windowSizeThatFits(proposal: proposal, context: context)
        }
    }

    /// `.clip` size: analytic sum-and-clamp. Sums child heights, takes the widest
    /// child for the width, and clamps both to the constraint so the column never
    /// over-reports the space it was given.
    private func clipSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }

        var totalHeight = 0
        var maxWidth = 0
        var hasFlexibleHeight = false
        var hasFlexibleWidth = false
        // Sized as the render sizes them, so a guide resolved here lands where
        // the render puts it: a spacer has no visual box, so it contributes
        // nothing (`renderClip` gives it no buffer either).
        var guideSizes: [(width: Int, height: Int)] = []
        guideSizes.reserveCapacity(children.count)

        // A column's size is its children's, so its claim to be natural is
        // theirs — plus the clamp below, which is the one place a column reads
        // the budget at all.
        var childrenAreNatural = true
        var tallestChild = 0
        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            if !size.isNaturalSize { childrenAreNatural = false }
            tallestChild = max(tallestChild, size.height)
            guideSizes.append(
                child.isSpacer ? (width: 0, height: 0) : (width: size.width, height: size.height))
            totalHeight += size.height
            maxWidth = max(maxWidth, size.width)
            if child.isSpacer || size.isHeightFlexible {
                hasFlexibleHeight = true
            }
            // A VStack fills its width exactly when a child does — its
            // renderToBuffer fills `availableWidth` in that case (a width-flexible
            // child rendered at the full width makes maxChildWidth == available).
            // Spacers here are vertical, so they don't make the column
            // width-flexible — SwiftUI: a Spacer "expands along the major axis
            // of its containing stack layout", which for a column is the
            // vertical one. `Spacer` has no axis input and reports BOTH axes
            // flexible, so the exclusion has to happen here; `_HStackCore`
            // makes the mirror one by handling spacers in a branch of their
            // own. (Was hard-coded `false`, which under-reported the column to
            // its parent and mis-drove width distribution.)
            if !child.isSpacer, size.isWidthFlexible {
                hasFlexibleWidth = true
            }
        }
        totalHeight += max(0, children.count - 1) * spacing

        // Never advertise a size larger than the constraint we were given —
        // an over-report would make the parent reserve space that does not
        // exist and let content overlap.
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        // A guide can make the column wider than its widest child; the report
        // has to say so or the parent reserves too little and clips it.
        if anyAlignmentGuide(in: children),
            let run = horizontalGuideRun(
                children, sizes: guideSizes, alignment: alignment,
                fixedExtent: hasFlexibleWidth ? max(0, widthLimit) : nil,
                minimumExtent: maxWidth)
        {
            maxWidth = run.extent
        }
        // Natural when the children are AND the height clamp did not bite: the
        // column then reported the height it chose, which is the same height at
        // any budget that could hold it. When the clamp DID bite the answer is
        // the budget's, not the column's, and must not answer for another.
        // (The width clamp needs no such test: its limit is the effective width,
        // which the memo keys on.)
        //
        // The last term is the same rule the row states at length: a child's
        // claim reaches down only to its own height, so a column may not offer
        // itself below the tallest answer it consumed. A sum of non-negative
        // heights is already at least its own maximum — the test earns its keep
        // for a NEGATIVE `spacing`, which subtracts from the total and could
        // otherwise report a column shorter than a child inside it.
        return ViewSize(
            width: min(maxWidth, max(0, widthLimit)),
            height: min(totalHeight, max(0, heightLimit)),
            isWidthFlexible: hasFlexibleWidth,
            isHeightFlexible: hasFlexibleHeight
        ).declaringNaturalSize(
            childrenAreNatural && totalHeight <= max(0, heightLimit) && tallestChild <= totalHeight)
    }

    /// `.window` size, computed analytically from the same width-aware slot
    /// walk the render paths use (Stage 3 of "Locating things without drawing
    /// them": measuring must not render). The walk mirrors `renderWindow`'s
    /// append-while-fits exactly — children accumulate top-down and the size
    /// stops at the first child that would overflow `availableHeight`, so the
    /// height ends on a child boundary just as the render does. Flexibility
    /// mirrors the fill rules: a (vertical) spacer makes the stack fill both
    /// axes, and any width/height-flexible child fills its axis.
    ///
    /// A stack WITH a spacer keeps the render-based measure: spacer heights
    /// come from distributing the leftover after every sibling has rendered,
    /// which is genuinely a property of the fill, not of any one child.
    /// (`renderWindow` forfeits laziness for spacers for the same reason.)
    private func windowSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        // Children of a windowed stack are not at the scroll origin; the
        // window must not leak into their own measures.
        measureContext.environment.scrollContentWindow = nil

        // The seek ladder (mirroring the render): uniform arithmetic when
        // the hypothesis is live, else — for any LARGE keyed collection —
        // the sample-based anchored estimate. The latter needs no persisted
        // state, so it also covers the very first frame (seeding is a
        // render-path mutation): without it, frame 1's measures would
        // eagerly walk millions of rows before the render ever got the
        // chance to seed. Checked BEFORE the eager resolve, which would
        // build every row.
        let collection = resolveChildViewCollection(from: content, context: measureContext)
        if collection.isUniformlyKeyed {
            if let fast = uniformSeekSizeThatFits(collection, proposal: proposal, context: context) {
                return fast
            }
            if collection.count > Self.anchoredWindowThreshold,
                let anchored = anchoredSizeThatFits(collection, proposal: proposal, context: context)
            {
                return anchored
            }
        }

        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        let slots = naturalRowSlots(width: widthLimit, context: measureContext)

        var widthFlexible = false
        var heightFlexible = false
        var hasSpacer = false
        for slot in slots {
            if slot.child.isSpacer {
                hasSpacer = true
                // Vertical only, as in the eager path above.
                heightFlexible = true
            }
            if slot.size.isWidthFlexible { widthFlexible = true }
            if slot.size.isHeightFlexible { heightFlexible = true }
        }

        if hasSpacer {
            let size = measureFixedByRendering(self, proposal: proposal, context: context)
            return ViewSize(
                width: size.width, height: size.height,
                isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
        }

        var height = 0
        var maxWidth = 0
        for slot in slots {
            let next = height + slot.spacingBefore + slot.height
            if next > heightLimit {
                // Saturated: content extends past the limit. Report the LIMIT
                // — the eager stack's own min(total, proposal) convention —
                // not the row boundary a few lines under it. A row-boundary
                // report is indistinguishable from a chosen natural size, and
                // it ended measureNaturalExtent's ladder on its first rung:
                // whenever the row pitch did not divide the budget, scrollable
                // content was silently truncated at ~the starting budget
                // (thousands of lines that existed, rendered nowhere, and
                // could not be scrolled to). The ladder still converges on the
                // exact total: on a later rung the walk exhausts every row
                // without breaking and reports the size the content CHOSE.
                // The partially-shown row's width still counts — the render
                // places its clipped buffer, so the column hugs it.
                height = heightLimit
                maxWidth = max(maxWidth, min(slot.width, widthLimit))
                break
            }
            height = next
            maxWidth = max(maxWidth, min(slot.width, widthLimit))
        }
        return ViewSize(
            width: maxWidth, height: height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let context = context.publishingContainerAxis(.vertical)
        switch overflow {
        case .clip: return renderClip(context: context)
        case .window: return renderWindow(context: context)
        }
    }

    /// `.clip` render (eager `VStack`): measure every child, distribute the
    /// available height (clipping trailing rows at the cell), render, align, and
    /// clamp.
    private func renderClip(context: RenderContext) -> FrameBuffer {
        resolveEagerSeek(context: context)
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        // === PASS 1: Measure every child's natural size ===
        var childSizes: [ViewSize] = []
        childSizes.reserveCapacity(children.count)
        for child in children {
            childSizes.append(child.measure(proposal: .unspecified, context: context))
        }

        var naturalHeight = [Int](repeating: 0, count: children.count)
        var isFlexible = [Bool](repeating: false, count: children.count)
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                naturalHeight[index] = child.spacerMinLength ?? 0
                isFlexible[index] = true
            } else {
                naturalHeight[index] = childSizes[index].height
                isFlexible[index] = childSizes[index].isHeightFlexible
            }
        }

        // Pass the full available height and the spacing: the distribution
        // charges each gap only between children it actually places, so an
        // over-tall stack clips its trailing rows instead of starving every row
        // to zero (which rendered the whole stack blank when the gaps alone
        // exceeded the height).
        let finalHeights = distributeLinearSpace(
            naturalSizes: naturalHeight,
            isFlexible: isFlexible,
            available: context.availableHeight,
            spacing: spacing
        )
        let hasFlexible = isFlexible.contains(true)

        // === PASS 2: Render each child into its allocated height ===
        //
        // A `.gradientExtent(.subtree)` ramp needs each child to know where it
        // sits in the rectangle the ramp spans, and the vertical half of that
        // is exactly what PASS 1 just worked out. The horizontal half is not —
        // alignment needs the RENDERED widths, which is PASS 3 — so it is
        // predicted from the measured ones, which is what they are for.
        // The stack's own content size, from PASS 1 — which is what an enclosing
        // `.gradientExtent(.subtree)` needs and what it would otherwise have
        // paid a second measure pass to learn.
        let contentWidth = hasFlexible ? context.availableWidth : (childSizes.map(\.width).max() ?? 0)
        let contentHeight = min(
            context.availableHeight,
            finalHeights.reduce(0, +) + spacing * max(0, finalHeights.count - 1))
        let gradientFrame = context.gradientContentFrame(
            width: contentWidth, height: contentHeight)
        let gradientPlacement = gradientFrame.map { _ in
            Self.gradientOffsets(
                heights: finalHeights, spacing: spacing, sizes: childSizes,
                alignment: alignment,
                extentWidth: hasFlexible ? context.availableWidth : nil)
        }
        var buffers: [FrameBuffer?] = []
        buffers.reserveCapacity(children.count)
        var maxChildWidth = 0
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                buffers.append(nil)
            } else {
                var childContext = context
                if let placement = gradientPlacement {
                    childContext = context.placingGradientChild(
                        gradientFrame, x: placement[index].x, y: placement[index].y)
                }
                let buffer = child.render(
                    width: context.availableWidth, height: finalHeights[index],
                    context: childContext)
                maxChildWidth = max(maxChildWidth, buffer.width)
                buffers.append(buffer)
            }
        }

        // With a flexible child present the stack fills the available width;
        // otherwise it shrinks to its widest child.
        let alignmentWidth = hasFlexible ? context.availableWidth : maxChildWidth

        // Explicit guides, when any child set one: the run's placement replaces
        // the per-child centring below, and can make the column WIDER than its
        // widest child (a child hanging left of the alignment line pushes every
        // other one right). Spacers have no visual box, so they place at the
        // leading edge and take no part in the run.
        var guideRun: AlignmentGuideRun?
        if anyAlignmentGuide(in: children) {
            guideRun = horizontalGuideRun(
                children,
                sizes: buffers.map { (width: $0?.width ?? 0, height: $0?.height ?? 0) },
                alignment: alignment,
                fixedExtent: hasFlexible ? context.availableWidth : nil,
                minimumExtent: maxChildWidth)
        }

        // === PASS 3: Assemble vertically ===
        // Empty children (e.g. `if false { ChildView() }`, which
        // ViewBuilder lowers to `Optional<ChildView>.none`, and
        // `EmptyView()`) are filtered from layout entirely: they
        // contribute no height, and FrameBuffer.appendVertically
        // drops the spacing slot they would otherwise have claimed.
        // This matches SwiftUI's VStack semantics — a non-rendering
        // child is treated as if it weren't in the children list at
        // all. To reserve a row regardless, opt in with a sized
        // placeholder (Color.clear.frame(height: 1), Spacer with an
        // explicit height, etc.) — note that EmptyView() in an else
        // branch will also be filtered.
        var result = FrameBuffer()
        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0
            if child.isSpacer {
                result.appendVertically(
                    FrameBuffer(emptyWithHeight: finalHeights[index]), spacing: spacingToApply)
            } else if let buffer = buffers[index] {
                let alignedBuffer =
                    guideRun.map {
                        placeBuffer(buffer, toWidth: $0.extent, offset: $0.offsets[index])
                    } ?? alignBuffer(buffer, toWidth: alignmentWidth, alignment: alignment)
                result.appendVertically(alignedBuffer, spacing: spacingToApply)
            }
        }

        // Final guard against overflow on a terminal smaller than the content.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// `.window` render (lazy `LazyVStack`): append whole children top-down while
    /// they fit `availableHeight`, stopping at the first that won't. Items beyond
    /// that first overflow are never rendered (when no Spacer is present).
    ///
    /// Children resolve through the two-pass `ChildView` API — the same one the
    /// `.clip` path uses — so `ChildViewProvider` content (a `ForEach`, above
    /// all) expands to its individual rows with per-child identities. The legacy
    /// single-pass `resolveChildInfos` used here before only expanded
    /// `ChildInfoProvider`s, which `ForEach` is not, so `LazyVStack { ForEach }`
    /// pushed the whole `ForEach` through the universal `renderToBuffer` and
    /// rendered nothing at all (issue #8).
    private func renderWindow(context: RenderContext) -> FrameBuffer {
        // The seek ladder, checked BEFORE the eager resolve below (which
        // would build every row of a huge ForEach just to count spacers):
        // uniform arithmetic first; for large variable-height content, the
        // anchored walk (§5e); a nil from both (small N, spacers, a first
        // frame with no hypothesis) falls through to the exact paths.
        if let window = consumableScrollWindow(context: context), !context.isMeasuring {
            let collection = resolveChildViewCollection(from: content, context: context)
            if collection.isUniformlyKeyed {
                if let fast = renderUniformSeekWindow(collection, window: window, context: context) {
                    return fast
                }
                if collection.count > Self.anchoredWindowThreshold,
                    let anchored = renderAnchoredWindow(collection, window: window, context: context)
                {
                    return anchored
                }
            }
        }

        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return FrameBuffer() }
        let availableHeight = context.availableHeight

        // A ramp spanning this stack needs each row's place in it before the
        // row renders, and this path renders as it walks — so the placement is
        // measured up front, stopping at the same fold the walk will. Costs
        // nothing without a `.gradientExtent(.subtree)` above.
        let (gradientFrame, gradientOffsets) = windowGradientPlacement(children, context: context)
        func rowContext(_ index: Int) -> RenderContext {
            guard index < gradientOffsets.count else { return context }
            return context.placingGradientChild(
                gradientFrame, x: gradientOffsets[index].x, y: gradientOffsets[index].y)
        }

        // True viewport windowing: when an enclosing vertical `ScrollView`
        // published the visible slice (and this isn't a measure pass, and there's
        // no Spacer forcing a full render), render ONLY the rows intersecting the
        // viewport into a full-height buffer — off-window rows never render, so
        // their `onAppear`/`.task` don't fire and their cost is skipped, while the
        // ScrollView's clip and content-height stay correct.
        if let window = consumableScrollWindow(context: context),
            !context.isMeasuring,
            children.allSatisfy({ !$0.isSpacer })
        {
            return renderViewportWindow(children: children, window: window, context: context)
        }

        // Spacer distribution (same as VStack) needs every non-spacer child's
        // rendered height up front, so the presence of a Spacer forfeits the
        // early-stop: pre-render everything, as the single-pass path always did.
        // The common spacer-less lazy stack keeps its laziness below.
        let spacerCount = children.count { $0.isSpacer }
        var eagerBuffers: [FrameBuffer?] = []
        var spacerHeight = 0
        var spacerRemainder = 0
        if spacerCount > 0 {
            eagerBuffers = children.enumerated().map { index, child in
                child.isSpacer
                    ? nil
                    : child.render(
                        width: context.availableWidth, height: availableHeight,
                        context: rowContext(index))
            }
            let fixedHeight = eagerBuffers.compactMap { $0?.height }.reduce(0, +)
            let totalSpacing = max(0, children.count - 1) * spacing
            let availableForSpacers = max(0, availableHeight - fixedHeight - totalSpacing)
            spacerHeight = availableForSpacers / spacerCount
            spacerRemainder = availableForSpacers % spacerCount
        }

        // === PASS 1: Collect the children that fit, rendering on demand ===
        // The walk stops at the first child that would overflow.
        var collected: [(buffer: FrameBuffer, spacingBefore: Int, child: ChildView?)] = []
        var currentHeight = 0
        var spacerIndex = 0
        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0

            if child.isSpacer {
                let extraHeight = spacerIndex < spacerRemainder ? 1 : 0
                let height = max(child.spacerMinLength ?? 0, spacerHeight + extraHeight)
                if currentHeight + spacingToApply + height > availableHeight {
                    break
                }
                collected.append((FrameBuffer(emptyWithHeight: height), spacingToApply, nil))
                currentHeight += spacingToApply + height
                spacerIndex += 1
            } else if spacerCount > 0 {
                let buffer = eagerBuffers[index]!
                if currentHeight + spacingToApply + buffer.height > availableHeight {
                    break
                }
                collected.append((buffer, spacingToApply, child))
                currentHeight += spacingToApply + buffer.height
            } else {
                // Fit-check on a (side-effect-free) measure BEFORE rendering:
                // rendering-to-check would run the first overflowing child's
                // render every frame without ever displaying it — firing its
                // onAppear and keeping its .task alive for an invisible row.
                let measured = child.measure(proposal: .unspecified, context: context)
                if currentHeight + spacingToApply + measured.height > availableHeight {
                    appendSaturatedTail(
                        child, measuredHeight: measured.height,
                        spacingToApply: spacingToApply, currentHeight: currentHeight,
                        availableHeight: availableHeight, into: &collected,
                        context: rowContext(index))
                    break
                }
                let buffer = child.render(
                    width: context.availableWidth, height: availableHeight,
                    context: rowContext(index))
                if currentHeight + spacingToApply + buffer.height > availableHeight {
                    break  // a child whose render exceeds its measure still can't overflow the window
                }
                collected.append((buffer, spacingToApply, child))
                currentHeight += spacingToApply + buffer.height
            }
        }

        return assembleWindow(collected, fillsWidth: spacerCount > 0, context: context)
    }

    /// The saturated tail of the classic append-while-fits walk: the first
    /// row that does not fit whole is rendered CLIPPED at the cell — the
    /// eager stack's convention, and the one the measure reports
    /// (`windowSizeThatFits` answers the LIMIT when it breaks there, so the
    /// two agree to the line). The row is partially VISIBLE, so its lifecycle
    /// firing is correct. When only (part of) the spacing shows, that space
    /// is accounted as an explicit blank block — `appendVertically` drops the
    /// spacing of an EMPTY buffer — and the row is NOT rendered: it would
    /// show zero lines, and rendering it would fire its lifecycle for an
    /// invisible row.
    private func appendSaturatedTail(
        _ child: ChildView, measuredHeight: Int, spacingToApply: Int, currentHeight: Int,
        availableHeight: Int,
        into collected: inout [(buffer: FrameBuffer, spacingBefore: Int, child: ChildView?)],
        context: RenderContext
    ) {
        let remaining = availableHeight - currentHeight - spacingToApply
        if remaining > 0 {
            let buffer = child.render(
                width: context.availableWidth, height: measuredHeight, context: context)
            let clipped = buffer.clamped(toWidth: buffer.width, height: remaining)
            collected.append((clipped, spacingToApply, child))
        } else if spacingToApply > 0 {
            let spacingShown = min(spacingToApply, availableHeight - currentHeight)
            collected.append((FrameBuffer(emptyWithHeight: spacingShown), 0, nil))
        }
    }

    /// `.window` PASS 2: align the collected children and stack them.
    ///
    /// With a Spacer the column fills the available width (as the eager stack
    /// does); otherwise it hugs its widest *placed* child. A `nil` child marks a
    /// spacer's blank slot, which is never aligned.
    /// The explicit-guide run over the rows a lazy column actually placed, or
    /// `nil` — the common answer, which is why the question is asked before the
    /// three arrays that would carry it are built. See ``anyAlignmentGuide(in:)``.
    private func placedGuideRun(
        _ collected: [(buffer: FrameBuffer, spacingBefore: Int, child: ChildView?)],
        fixedExtent: Int?, minimumExtent: Int
    ) -> AlignmentGuideRun? {
        guard anyAlignmentGuide(in: collected.compactMap(\.child)) else { return nil }
        let placed = collected.compactMap { entry in entry.child.map { ($0, entry.buffer) } }
        return horizontalGuideRun(
            placed.map(\.0),
            sizes: placed.map { (width: $0.1.width, height: $0.1.height) },
            alignment: alignment,
            fixedExtent: fixedExtent,
            minimumExtent: minimumExtent)
    }

    private func assembleWindow(
        _ collected: [(buffer: FrameBuffer, spacingBefore: Int, child: ChildView?)],
        fillsWidth: Bool,
        context: RenderContext
    ) -> FrameBuffer {
        let maxWidth =
            fillsWidth ? context.availableWidth : collected.map(\.buffer.width).max() ?? 0

        // Explicit guides resolve over the children this stack actually PLACED.
        // A lazy stack stops at the first row that will not fit, so the run is
        // the realized rows — the same limit SwiftUI has, and the reason a guide
        // is best used on content whose realized set is stable.
        let guideRun = placedGuideRun(
            collected, fixedExtent: fillsWidth ? context.availableWidth : nil,
            minimumExtent: maxWidth)

        var result = FrameBuffer()
        var placedIndex = 0
        for (buffer, spacingToApply, child) in collected {
            guard child != nil else {
                result.appendVertically(buffer, spacing: spacingToApply)
                continue
            }
            defer { placedIndex += 1 }
            let alignedBuffer =
                guideRun.map {
                    placeBuffer(buffer, toWidth: $0.extent, offset: $0.offsets[placedIndex])
                } ?? alignBuffer(buffer, toWidth: maxWidth, alignment: alignment)
            result.appendVertically(alignedBuffer, spacing: spacingToApply)
        }

        return result
    }

    /// A pending scrollTo against EAGER (`.clip`) content: the stack renders
    /// in full regardless, so the seek only needs the target row's exact y —
    /// answered from the same slot walk `LayoutPlacing` uses — reported for
    /// the ScrollView to adopt this frame. Without this,
    /// `ScrollView { VStack { ForEach } }` (the most natural SwiftUI
    /// composition) silently ignored `scrollTo`.
    private func resolveEagerSeek(context: RenderContext) {
        guard !context.isMeasuring,
            let window = consumableScrollWindow(context: context),
            let seek = window.seek, let reply = window.reply
        else { return }
        var childContext = context
        childContext.environment.scrollContentWindow = nil
        let slots = naturalRowSlots(width: context.availableWidth, context: childContext)
        guard let index = slots.firstIndex(where: { $0.child.identityChildKey == seek.key })
        else { return }
        let total = slots.last.map { $0.y + $0.height } ?? 0
        reply.seekResolvedOffset = seek.windowOffset(
            targetY: slots[index].y, rowHeight: slots[index].height,
            currentOffset: window.offset, viewportHeight: window.viewportHeight,
            totalHeight: total)
    }

    /// Renders only the children intersecting an enclosing ScrollView's visible
    /// vertical slice, into a full-height buffer (off-window rows become blank
    /// placeholders of their measured height). Off-window children are measured
    /// (cheap, side-effect-free) to keep every row at its true `y`, but never
    /// rendered — so their `onAppear`/`.task` don't fire and their render cost is
    /// skipped. The full height + exact positions keep the ScrollView's clip and
    /// `contentHeight` correct. Only reached for a spacer-less lazy stack that is
    /// the direct content of a vertical ScrollView.
    /// The explicit-guide run over a windowed stack's slots, or `nil` — the
    /// common answer, which is why the question is asked before the two arrays
    /// that would carry it are built. See ``anyAlignmentGuide(in:)``.
    private func slotGuideRun(_ slots: [RowSlot], fixedExtent: Int) -> AlignmentGuideRun? {
        guard anyAlignmentGuide(in: slots.map(\.child)) else { return nil }
        return horizontalGuideRun(
            slots.map(\.child),
            sizes: slots.map { (width: $0.width, height: $0.height) },
            alignment: alignment,
            fixedExtent: fixedExtent)
    }

    private func renderViewportWindow(
        children: [ChildView], window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer {
        // Off-window rows leave the WINDOW, not the tree: their @State (and
        // onChange baselines) must survive this frame's prune. Declared per
        // frame; lapses when this stack stops rendering, pruning the subtree.
        context.stateStorage?.retainSubtree(context.identity)

        // Descendants aren't at the scroll origin, so they must not re-window.
        var childContext = context
        childContext.environment.scrollContentWindow = nil

        let width = context.availableWidth

        // The same slot walk LayoutPlacing answers from (one traversal, many
        // visitors): the window predicate below and any locate/enumerate
        // query agree on every row's y by construction. Width-aware, so a
        // wrapping row's slot is its wrapped height.
        let slots = naturalRowSlots(width: width, context: childContext)

        // A pending scrollTo: exact on this path — the slots carry every
        // row's true y. Re-aim the window before choosing the render set,
        // and report the offset so the ScrollView adopts it this frame.
        var window = window
        if let seek = window.seek {
            window.seek = nil
            if let index = slots.firstIndex(where: { $0.child.identityChildKey == seek.key }) {
                let total = slots.last.map { $0.y + $0.height } ?? 0
                let newOffset = seek.windowOffset(
                    targetY: slots[index].y, rowHeight: slots[index].height,
                    currentOffset: window.offset, viewportHeight: window.viewportHeight,
                    totalHeight: total)
                window.offset = newOffset
                window.reply?.seekResolvedOffset = newOffset
            }
        }

        // A designated anchor row overrides the offset so it keeps its screen
        // line as rows come and go around it. Exact here: the slots carry
        // every row's true y and height.
        holdDesignatedRow(slots: slots, window: &window, context: context)

        // The offset can be STALE beyond the walked content — the data
        // shrank this frame, and the ScrollView clamps only after this
        // render returns. An unclamped window then intersects no slot and
        // the whole buffer comes out as blank placeholders — which the
        // ScrollView cannot repair, because this classic full-height path
        // has no slice metadata for coverSnappedViewport to check. Clamp
        // to the real extent so the tail rows render at their true y; the
        // ScrollView's own clamp then lands the clip exactly on them.
        let walkedTotal = slots.last.map { $0.y + $0.height } ?? 0
        let top = min(window.offset, max(0, walkedTotal - window.viewportHeight))
        let bottom = top + window.viewportHeight

        reportExactWalkSample(
            slots: slots, window: window, top: top, walkedTotal: walkedTotal,
            context: childContext)

        // The enumerate visitor's row set (§5d/§6a): the rows meeting the
        // viewport, plus one margin row past each edge (so a directional
        // focus move can step just beyond the window — the ring only holds
        // what registers, and registration happens on render), plus the
        // focused row and any pending focus target with THEIR neighbours
        // (focus must keep registering wherever it is, or the end-of-pass
        // validation would steal it; the target must register once to
        // resolve the intent). Off-window renders land in the full-height
        // buffer where the ScrollView's clip hides them — invisible, but
        // registered.
        var rendersRow = [Bool](repeating: false, count: slots.count)
        for (index, slot) in slots.enumerated() {
            rendersRow[index] = slot.y + slot.height > top && slot.y < bottom
        }
        if let first = rendersRow.firstIndex(of: true), first > 0 {
            rendersRow[first - 1] = true
        }
        if let last = rendersRow.lastIndex(of: true), last < slots.count - 1 {
            rendersRow[last + 1] = true
        }
        if let focusManager = context.environment.focusManager {
            for target in [focusManager.currentFocusedID, focusManager.pendingFocusID] {
                guard let index = rowIndex(addressedBy: target, slots: slots, context: childContext)
                else { continue }
                for neighbour in max(0, index - 1)...min(slots.count - 1, index + 1) {
                    rendersRow[neighbour] = true
                }
            }
            // Ring continuation (see StackFocusReach.swift): a disabled
            // neighbour registers nothing, so the nearest focusable row past
            // it must render too or Tab dead-ends at the run. The sweep
            // below renders ascending, so the ring stays in data order.
            for stop in focusRingContinuations(
                focusedOrdinal: rowIndex(
                    addressedBy: focusManager.currentFocusedID, slots: slots,
                    context: childContext),
                count: slots.count, child: { slots[$0].child },
                width: width, viewportHeight: window.viewportHeight, context: childContext)
            {
                rendersRow[stop] = true
            }
        }

        // Explicit guides, resolved from the slot walk's measured sizes so an
        // off-window row still contributes its guide — the alignment column
        // must not shift as rows scroll in and out. Costs nothing (one stored
        // `Bool` per row) unless a row actually set a guide.
        let guideRun = slotGuideRun(slots, fixedExtent: width)

        // A ramp spanning this stack runs across the whole CONTENT, not the
        // viewport: a row keeps its colour as it scrolls, rather than the
        // column crawling under a stationary ramp. The walk above already
        // knows every row's true y and the content's full height, so this is
        // exact — including for the rows outside the window, which render into
        // the same coordinates.
        let gradientFrame = context.gradientContentFrame(width: width, height: walkedTotal)

        var result = FrameBuffer()
        for (index, slot) in slots.enumerated() {
            let slotHeight = slot.spacingBefore + slot.height

            if !rendersRow[index] {
                // Off-window: a blank placeholder of the same height.
                result.appendVertically(FrameBuffer(emptyWithHeight: slotHeight), spacing: 0)
                continue
            }

            let child = slot.child
            let spacingBefore = slot.spacingBefore
            // Render at the SLOT's height, not the viewport's: the slot walk
            // measured the row's natural height, and the canvas below pads to
            // exactly that — but the render used to be clamped to the
            // viewport, so any row TALLER than the viewport had its tail
            // permanently blanked (scrolling to the row's later lines showed
            // empty rows the content height and scrollbar accounted for).
            let rendered = child.render(
                width: width, height: slot.height,
                context: childContext.placingGradientChild(
                    gradientFrame,
                    x: guideRun.map { $0.offsets[index] }
                        ?? Self.gradientX(
                            childWidth: slot.width, extent: width, alignment: alignment),
                    y: slot.y))
            var slot = FrameBuffer()
            if spacingBefore > 0 {
                slot.appendVertically(FrameBuffer(emptyWithHeight: spacingBefore), spacing: 0)
            }
            let placed =
                guideRun.map {
                    placeBuffer(rendered, toWidth: width, offset: $0.offsets[index])
                } ?? alignBuffer(rendered, toWidth: width, alignment: alignment)
            slot.appendVertically(placed, spacing: 0)
            // Keep the slot exactly `slotHeight` tall so later rows stay at their
            // true `y` even if a row rendered a different height than it measured.
            if slot.height < slotHeight {
                slot.appendVertically(FrameBuffer(emptyWithHeight: slotHeight - slot.height), spacing: 0)
            } else if slot.height > slotHeight {
                slot = slot.clamped(toWidth: max(width, slot.width), height: slotHeight)
            }
            result.appendVertically(slot, spacing: 0)
        }
        return result
    }

    /// Reports the row the viewport shows at the report anchor — exact here,
    /// the slots carry every row's true y. This path never sampled at all, so
    /// `.scrollPosition` read-back went silent for exactly the content its
    /// own doc example shows: a variable-height lazy stack under the
    /// anchored threshold. The collection is resolved only when someone is
    /// actually listening; for a lone `ForEach` it is the lazy form whose
    /// ids come straight from the data.
    private func reportExactWalkSample(
        slots: [RowSlot], window: ScrollContentWindow, top: Int, walkedTotal: Int,
        context childContext: RenderContext
    ) {
        guard let unit = window.reportsIDAt, let reply = window.reply, !slots.isEmpty
        else { return }
        var sampling = window
        sampling.offset = top
        let line = sampling.sampleY(
            at: unit, contentBelow: top + window.viewportHeight < walkedTotal)
        // The first row whose bottom lies past the sampled line (a line in an
        // inter-row gap belongs to the row below it), clamped to the last row.
        let ordinal = slots.firstIndex { line < $0.y + $0.height } ?? (slots.count - 1)
        let ids = resolveChildViewCollection(from: content, context: childContext)
        reply.anchorID = ids.anyID(at: ordinal)
    }

    /// The slot index of the row whose subtree a focus ID addresses, when the
    /// ID is a default (identity-path-derived) one and the addressed control
    /// lives under one of this stack's rows.
    ///
    /// Cheap rejection first: unless the ID embeds this stack's own path,
    /// no row can match and no per-row path is materialised. When it does,
    /// the scan renders each row's identity path — O(rows) string work, only
    /// on frames where focus (or a pending target) is inside this stack.
    private func rowIndex(
        addressedBy focusID: String?, slots: [RowSlot], context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        let stackPath = context.identity.path
        guard focusID.contains(stackPath) else { return nil }
        return slots.firstIndex { slot in
            FocusManager.focusID(focusID, addressesSubtreeAt: slot.child.identity(under: context).path)
        }
    }

    /// Aligns a buffer horizontally within the given width.
    func alignBuffer(_ buffer: FrameBuffer, toWidth width: Int, alignment: HorizontalAlignment) -> FrameBuffer {
        guard buffer.width < width else { return buffer }
        return placeBuffer(
            buffer, toWidth: width,
            offset: alignment.childOffset(childWidth: buffer.width, in: width))
    }

    /// Places a buffer at an explicit horizontal offset within the given width.
    ///
    /// The arithmetic ``alignBuffer(_:toWidth:alignment:)`` performs, split out
    /// so a container that resolved the offset from an explicit
    /// ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)`` can reuse the same padding
    /// (and the same overlay/hit-region carry) instead of a second copy of it.
    func placeBuffer(_ buffer: FrameBuffer, toWidth width: Int, offset: Int) -> FrameBuffer {
        guard offset > 0 || buffer.width < width else { return buffer }

        var alignedLines: [String] = []

        let bufferOffset = offset
        // A guide can push a child past the nominal width; the buffer must
        // still describe its own true extent, or `replacingLines`' uniform-width
        // promise below would be a lie the whole pipeline then trusts.
        let width = max(width, offset + buffer.width)

        let leftCount = bufferOffset
        let rightCount = max(0, width - bufferOffset - buffer.width)

        // When the input is already uniform every line is exactly `buffer.width`,
        // so the inner pad is empty — skip the per-line measure entirely. For a
        // ragged input (e.g. a column of word-wrapped `Text`) reuse the carried
        // per-line widths when present, falling back to `strippedLength` only when
        // they are unknown. This is the hot path for a `VStack` of wrapped text.
        //
        // Each aligned line is built in place: reserve `width` cells then append
        // the leading spaces, the line, the (ragged-only) inner pad, and the
        // trailing spaces — all borrowed from the shared spaces run, with no
        // `String(repeating:)` temporaries and no `+`-chain intermediates. The
        // byte sequence is identical to `leftPadding + paddedLine + rightPadding`.
        let inputIsUniform = buffer.linesAreUniformWidth
        let carriedWidths = buffer.lineWidths
        alignedLines.reserveCapacity(buffer.lines.count)
        for (index, line) in buffer.lines.enumerated() {
            let innerPad = inputIsUniform ? 0 : max(0, buffer.width - (carriedWidths?[index] ?? line.strippedLength))
            var aligned = ""
            aligned.reserveCapacity(line.utf8.count + leftCount + innerPad + rightCount)
            aligned += asciiSpaces(leftCount)
            aligned += line
            if innerPad > 0 { aligned += asciiSpaces(innerPad) }
            aligned += asciiSpaces(rightCount)
            alignedLines.append(aligned)
        }

        // Each aligned line is exactly `width` wide (leftPad + buffer.width +
        // rightPad), so hand that known width through — and flag it uniform — to
        // skip re-measuring every line in `replacingLines`. That re-measure was
        // ~32% of the AnyView-storm frame (a VStack aligning 500 rows), redundant
        // with the widths just used above. The content shifted right by
        // `bufferOffset`; carry overlay layers by the same amount so they stay
        // anchored.
        return buffer.replacingLines(
            alignedLines, width: width, uniformWidth: true,
            overlayShiftX: bufferOffset, overlayShiftY: 0)
    }
}

// MARK: - Equatable

extension VStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: VStack<Content>, rhs: VStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}
