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
        _HStackCore(alignment: alignment, spacing: spacing, content: content)
    }
}

// MARK: - Internal HStack Core

/// Internal view that handles the actual rendering of HStack.
private struct _HStackCore<Content: View>: View, Renderable, Layoutable {
    let alignment: VerticalAlignment
    let spacing: Int
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
        let contentWidth = max(0, availableWidth - totalSpacing)

        var ideal = [Int](repeating: 0, count: count)
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
                fills[index] = size.isWidthFlexible
            }
        }

        let widths = distributeLinearSpace(naturalSizes: ideal, isFlexible: fills, available: contentWidth)

        // Heights at the widths children will actually be given (a child
        // squeezed narrow enough to wrap is taller than at its natural width).
        var height = 1
        for (index, child) in children.enumerated() where !child.isSpacer {
            let size = child.measure(proposal: ProposedSize(width: widths[index], height: nil), context: context)
            height = max(height, size.height)
        }

        let totalWidth = widths.reduce(0, +) + totalSpacing
        return (widths, min(totalWidth, max(0, availableWidth)), height, fills.contains(true))
    }

    /// Measures the HStack without rendering.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
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

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
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
                let buffer = child.render(width: finalWidth, height: rowHeight, context: context)
                result.appendHorizontally(buffer, spacing: spacingToApply)
            }
        }

        // Final guard: the assembled row never exceeds the space we were given,
        // even when inter-child spacing alone would overflow a tiny terminal.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }
}

// MARK: - Equatable

extension HStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: HStack<Content>, rhs: HStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}
