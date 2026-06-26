//  🖥️ TUIKit — Terminal UI Kit for Swift
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

        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            totalHeight += size.height
            maxWidth = max(maxWidth, size.width)
            if child.isSpacer || size.isHeightFlexible {
                hasFlexibleHeight = true
            }
            // A VStack fills its width exactly when a child does — its
            // renderToBuffer fills `availableWidth` in that case (a width-flexible
            // child rendered at the full width makes maxChildWidth == available).
            // Spacers here are vertical, so they don't make the column
            // width-flexible. (Was hard-coded `false`, which under-reported the
            // column to its parent and mis-drove width distribution.)
            if size.isWidthFlexible {
                hasFlexibleWidth = true
            }
        }
        totalHeight += max(0, children.count - 1) * spacing

        // Never advertise a size larger than the constraint we were given —
        // an over-report would make the parent reserve space that does not
        // exist and let content overlap.
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        return ViewSize(
            width: min(maxWidth, max(0, widthLimit)),
            height: min(totalHeight, max(0, heightLimit)),
            isWidthFlexible: hasFlexibleWidth,
            isHeightFlexible: hasFlexibleHeight
        )
    }

    /// `.window` size from one render: the layout stops appending children once
    /// the running height would exceed `availableHeight`, so the rendered height
    /// ends on a child boundary and can fall short of the height limit by a
    /// truncated child. Summing children analytically (as `.clip` does) would
    /// over-report that boundary, so the exact size must come from a render under
    /// this context. Flexibility mirrors `renderWindow`'s fill rules: a (vertical)
    /// spacer makes `maxWidth` become `availableWidth` and expands the height, and
    /// any width/height-flexible child fills its axis.
    private func windowSizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        var widthFlexible = false
        var heightFlexible = false
        for child in resolveChildViews(from: content, context: context) {
            if child.isSpacer { widthFlexible = true; heightFlexible = true }
            let childSize = child.measure(proposal: proposal, context: context)
            if childSize.isWidthFlexible { widthFlexible = true }
            if childSize.isHeightFlexible { heightFlexible = true }
        }
        return ViewSize(
            width: size.width, height: size.height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        switch overflow {
        case .clip: return renderClip(context: context)
        case .window: return renderWindow(context: context)
        }
    }

    /// `.clip` render (eager `VStack`): measure every child, distribute the
    /// available height (clipping trailing rows at the cell), render, align, and
    /// clamp.
    private func renderClip(context: RenderContext) -> FrameBuffer {
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
        var buffers: [FrameBuffer?] = []
        buffers.reserveCapacity(children.count)
        var maxChildWidth = 0
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                buffers.append(nil)
            } else {
                let buffer = child.render(
                    width: context.availableWidth, height: finalHeights[index], context: context)
                maxChildWidth = max(maxChildWidth, buffer.width)
                buffers.append(buffer)
            }
        }

        // With a flexible child present the stack fills the available width;
        // otherwise it shrinks to its widest child.
        let alignmentWidth = hasFlexible ? context.availableWidth : maxChildWidth

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
                let alignedBuffer = alignBuffer(buffer, toWidth: alignmentWidth, alignment: alignment)
                result.appendVertically(alignedBuffer, spacing: spacingToApply)
            }
        }

        // Final guard against overflow on a terminal smaller than the content.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// `.window` render (lazy `LazyVStack`): append whole children top-down while
    /// they fit `availableHeight`, stopping at the first that won't. Items beyond
    /// the available height are never rendered.
    private func renderWindow(context: RenderContext) -> FrameBuffer {
        let infos = resolveChildInfos(from: content, context: context)

        // Lazy rendering: only render items that fit within availableHeight
        let availableHeight = context.availableHeight

        // Spacer distribution (same as VStack)
        let spacerCount = infos.filter(\.isSpacer).count
        let fixedHeight = infos.compactMap(\.buffer).reduce(0) { $0 + $1.height }
        let totalSpacing = max(0, infos.count - 1) * spacing

        let availableForSpacers = max(0, availableHeight - fixedHeight - totalSpacing)
        let spacerHeight = spacerCount > 0 ? availableForSpacers / spacerCount : 0
        let spacerRemainder = spacerCount > 0 ? availableForSpacers % spacerCount : 0

        let childMaxWidth = infos.compactMap(\.buffer).map(\.width).max() ?? 0
        let maxWidth = spacerCount > 0 ? context.availableWidth : childMaxWidth

        var result = FrameBuffer()
        var currentHeight = 0
        var spacerIndex = 0

        for (index, info) in infos.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0

            if info.isSpacer {
                let extraHeight = spacerIndex < spacerRemainder ? 1 : 0
                let height = max(info.spacerMinLength ?? 0, spacerHeight + extraHeight)

                // Lazy: check if spacer fits
                if currentHeight + spacingToApply + height > availableHeight {
                    break
                }

                result.appendVertically(FrameBuffer(emptyWithHeight: height), spacing: spacingToApply)
                currentHeight += spacingToApply + height
                spacerIndex += 1
            } else if let buffer = info.buffer {
                // Lazy: check if item fits
                if currentHeight + spacingToApply + buffer.height > availableHeight {
                    break
                }

                let alignedBuffer = alignBuffer(buffer, toWidth: maxWidth, alignment: alignment)
                result.appendVertically(alignedBuffer, spacing: spacingToApply)
                currentHeight += spacingToApply + buffer.height
            }
        }

        return result
    }

    /// Aligns a buffer horizontally within the given width.
    private func alignBuffer(_ buffer: FrameBuffer, toWidth width: Int, alignment: HorizontalAlignment) -> FrameBuffer {
        guard buffer.width < width else { return buffer }

        var alignedLines: [String] = []

        let bufferOffset: Int
        switch alignment {
        case .leading:
            bufferOffset = 0
        case .center:
            bufferOffset = (width - buffer.width) / 2
        case .trailing:
            bufferOffset = width - buffer.width
        }

        let leftPadding = String(repeating: " ", count: bufferOffset)
        let rightPadding = String(repeating: " ", count: max(0, width - bufferOffset - buffer.width))

        // When the input is already uniform every line is exactly `buffer.width`,
        // so the inner pad is empty — skip the per-line `strippedLength` entirely.
        let inputIsUniform = buffer.linesAreUniformWidth
        for line in buffer.lines {
            let paddedLine =
                inputIsUniform
                ? line
                : line + String(repeating: " ", count: max(0, buffer.width - line.strippedLength))
            alignedLines.append(leftPadding + paddedLine + rightPadding)
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
