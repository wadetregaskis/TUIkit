//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    let alignment: VerticalAlignment
    let spacing: Int
    /// Trailing-overflow behaviour: `.clip` (eager `HStack`) or `.window`
    /// (lazy `LazyHStack`).
    let overflow: StackOverflow
    let content: Content

    var body: Never {
        fatalError("_HStackCore renders via Renderable")
    }

    /// The single sizing routine shared by `sizeThatFits` and `renderToBuffer`,
    /// so the two passes cannot disagree about widths or height — measuring each
    /// child once at its ideal, distributing, then re-measuring heights at the
    /// allocated widths. (Previously each pass had its own copy of this logic
    /// and measured children at a different proposal, which let the reported
    /// size drift from the rendered one — e.g. a nested row measured one row
    /// taller than it rendered.)
    private func resolvedLayout(
        _ children: [ChildView], availableWidth: Int, context: RenderContext
    ) -> (widths: [Int], totalWidth: Int, height: Int, fills: Bool) {
        let count = children.count
        let totalSpacing = max(0, count - 1) * spacing

        var ideal = [Int](repeating: 0, count: count)
        var idealHeight = [Int](repeating: 0, count: count)
        var fills = [Bool](repeating: false, count: count)
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
                ideal[index] = size.width
                idealHeight[index] = size.height
                fills[index] = size.isWidthFlexible
            }
        }

        // Full available width + spacing: the distribution charges each gap only
        // between columns it places, so an over-wide row clips its trailing
        // columns instead of collapsing every column to zero.
        let widths = distributeLinearSpace(
            naturalSizes: ideal, isFlexible: fills, available: availableWidth, spacing: spacing)

        // Heights at the widths children will actually be given. A child given
        // at least its ideal width wraps no further than it did at `.unspecified`
        // (its ideal width is where it wrapped, and the allocation never exceeds
        // the available width that ideal was measured against), so its height is
        // the one already measured — reuse it. Only a child squeezed *narrower*
        // than its ideal can grow taller, so only those are re-measured. This
        // halves the per-child measures in the common (un-squeezed) case.
        var height = 1
        for (index, child) in children.enumerated() where !child.isSpacer {
            if widths[index] >= ideal[index] {
                height = max(height, idealHeight[index])
            } else {
                let size = child.measure(proposal: ProposedSize(width: widths[index], height: nil), context: context)
                height = max(height, size.height)
            }
        }

        let totalWidth = widths.reduce(0, +) + totalSpacing
        return (widths, min(totalWidth, max(0, availableWidth)), height, fills.contains(true))
    }

    /// Measures the HStack without rendering.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
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
        let layout = resolvedLayout(
            children, availableWidth: proposal.width ?? context.availableWidth, context: context)
        return ViewSize(
            width: layout.totalWidth,
            height: layout.height,
            isWidthFlexible: layout.fills,
            isHeightFlexible: false
        )
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
        for (index, size) in sizes.enumerated() {
            let next = width + (index > 0 ? spacing : 0) + size.width
            if next > widthLimit { break }
            width = next
            height = max(height, size.height)
        }
        return ViewSize(
            width: width, height: height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
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
        var result = FrameBuffer()
        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0
            let finalWidth = finalWidths[index]

            if child.isSpacer {
                let spacerBuffer = FrameBuffer(emptyWithWidth: finalWidth, height: rowHeight)
                result.appendHorizontally(spacerBuffer, spacing: spacingToApply)
            } else {
                // A child shorter than the row is positioned within it by
                // `alignment` (top/center/bottom). Without this every child is
                // top-pinned, because `appendHorizontally` only top-aligns.
                let buffer = child.render(width: finalWidth, height: rowHeight, context: context)
                    .verticallyAligned(toHeight: rowHeight, alignment: alignment)
                result.appendHorizontally(buffer, spacing: spacingToApply)
            }
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

        // Spacer distribution (same as HStack) needs every non-spacer child's
        // rendered width up front, so the presence of a Spacer forfeits the
        // early-stop: pre-render everything, as the single-pass path always
        // did. The common spacer-less lazy stack keeps its laziness below.
        let spacerCount = children.count { $0.isSpacer }
        var eagerBuffers: [FrameBuffer?] = []
        var spacerWidth = 0
        var spacerRemainder = 0
        if spacerCount > 0 {
            eagerBuffers = children.map { child in
                child.isSpacer
                    ? nil
                    : child.render(
                        width: availableWidth, height: context.availableHeight, context: context)
            }
            let fixedWidth = eagerBuffers.compactMap { $0?.width }.reduce(0, +)
            let totalSpacing = max(0, children.count - 1) * spacing
            let availableForSpacers = max(0, availableWidth - fixedWidth - totalSpacing)
            spacerWidth = availableForSpacers / spacerCount
            spacerRemainder = availableForSpacers % spacerCount
        }

        // === PASS 1: Collect the children that fit (rendering on demand)
        //             and compute the max height ===
        // Each entry: (buffer, spacingBefore, isSpacer). The walk stops at the
        // first child that would overflow.
        var collected: [(FrameBuffer, Int, Bool)] = []
        var maxHeight = 1
        var currentWidth = 0
        var spacerIndex = 0

        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0

            if child.isSpacer {
                let extraWidth = spacerIndex < spacerRemainder ? 1 : 0
                let width = max(child.spacerMinLength ?? 0, spacerWidth + extraWidth)
                if currentWidth + spacingToApply + width > availableWidth { break }
                // Spacer height is set to maxHeight in pass 2
                collected.append((FrameBuffer(emptyWithWidth: width, height: 1), spacingToApply, true))
                currentWidth += spacingToApply + width
                spacerIndex += 1
            } else if spacerCount > 0 {
                let buffer = eagerBuffers[index]!
                if currentWidth + spacingToApply + buffer.width > availableWidth { break }
                maxHeight = max(maxHeight, buffer.height)
                collected.append((buffer, spacingToApply, false))
                currentWidth += spacingToApply + buffer.width
            } else {
                // Fit-check on a (side-effect-free) measure BEFORE rendering —
                // see renderWindow in VStack.swift: rendering-to-check fired
                // the first overflowing child's lifecycle every frame.
                let measured = child.measure(proposal: .unspecified, context: context)
                if currentWidth + spacingToApply + measured.width > availableWidth { break }
                let buffer = child.render(
                    width: availableWidth, height: context.availableHeight, context: context)
                if currentWidth + spacingToApply + buffer.width > availableWidth { break }
                maxHeight = max(maxHeight, buffer.height)
                collected.append((buffer, spacingToApply, false))
                currentWidth += spacingToApply + buffer.width
            }
        }

        // === PASS 2: Apply vertical alignment and build result ===
        var result = FrameBuffer()
        for (buffer, spacingToApply, isSpacer) in collected {
            let aligned: FrameBuffer
            if isSpacer {
                aligned = FrameBuffer(emptyWithWidth: buffer.width, height: maxHeight)
            } else {
                aligned = buffer.verticallyAligned(toHeight: maxHeight, alignment: alignment)
            }
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
