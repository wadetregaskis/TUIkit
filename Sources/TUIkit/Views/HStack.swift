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

    /// Measures the HStack without rendering.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }

        // Pass 1 — natural sizes at the proposal we were given.
        var naturalSizes: [ViewSize] = []
        naturalSizes.reserveCapacity(children.count)
        var hasFlexibleWidth = false
        var totalNaturalWidth = 0
        var maxNaturalHeight = 0
        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            naturalSizes.append(size)
            totalNaturalWidth += size.width
            maxNaturalHeight = max(maxNaturalHeight, size.height)
            if child.isSpacer || size.isWidthFlexible {
                hasFlexibleWidth = true
            }
        }

        // Pass 1.5 — re-measure heights at the widths children will actually
        // be given. Without this, a child squeezed narrow enough to wrap
        // text would report its natural (unconstrained) height during
        // measurement, leaving the parent VStack/HStack reserving too few
        // rows and clipping the wrapped content at render time. We mirror
        // the same width-distribution logic the renderer uses.
        let widthLimit = proposal.width ?? context.availableWidth
        let totalSpacing = max(0, children.count - 1) * spacing
        let contentWidth = max(0, widthLimit - totalSpacing)
        var naturalWidth = [Int](repeating: 0, count: children.count)
        var isFlexible = [Bool](repeating: false, count: children.count)
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                naturalWidth[index] = child.spacerMinLength ?? 0
                isFlexible[index] = true
            } else {
                naturalWidth[index] = naturalSizes[index].width
                isFlexible[index] = naturalSizes[index].isWidthFlexible
            }
        }
        let finalWidths = distributeLinearSpace(
            naturalSizes: naturalWidth,
            isFlexible: isFlexible,
            available: contentWidth
        )
        var maxHeight = maxNaturalHeight
        for (index, child) in children.enumerated() where !child.isSpacer {
            // Avoid an unnecessary re-measure when the allocated width
            // matches what we already measured — the height cannot change.
            if finalWidths[index] == naturalSizes[index].width { continue }
            let probe = ProposedSize(width: finalWidths[index], height: nil)
            let size = child.measure(proposal: probe, context: context)
            maxHeight = max(maxHeight, size.height)
        }

        let totalWidth = totalNaturalWidth + totalSpacing
        return ViewSize(
            width: min(totalWidth, max(0, widthLimit)),
            height: maxHeight,
            isWidthFlexible: hasFlexibleWidth,
            isHeightFlexible: false
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        // === PASS 1: Measure every child's natural size ===
        var childSizes: [ViewSize] = []
        childSizes.reserveCapacity(children.count)
        var maxHeight = 1
        for child in children {
            let size = child.measure(proposal: .unspecified, context: context)
            childSizes.append(size)
            maxHeight = max(maxHeight, size.height)
        }

        let totalSpacing = max(0, children.count - 1) * spacing
        let contentWidth = max(0, context.availableWidth - totalSpacing)

        var naturalWidth = [Int](repeating: 0, count: children.count)
        var isFlexible = [Bool](repeating: false, count: children.count)
        for (index, child) in children.enumerated() {
            if child.isSpacer {
                naturalWidth[index] = child.spacerMinLength ?? 0
                isFlexible[index] = true
            } else {
                naturalWidth[index] = childSizes[index].width
                isFlexible[index] = childSizes[index].isWidthFlexible
            }
        }

        let finalWidths = distributeLinearSpace(
            naturalSizes: naturalWidth,
            isFlexible: isFlexible,
            available: contentWidth
        )

        // === PASS 1.5: Re-measure heights at the allocated widths ===
        // PASS 1 measured each child at its natural (unspecified) width, but a
        // child that wraps text is taller at a narrow allocated width than at
        // its natural width. Without this pass the row would size to the
        // natural-width heights and PASS 2 would clip whatever wrapped over.
        var allocatedHeight = maxHeight
        for (index, child) in children.enumerated() where !child.isSpacer {
            let proposed = ProposedSize(width: finalWidths[index], height: nil)
            let size = child.measure(proposal: proposed, context: context)
            allocatedHeight = max(allocatedHeight, size.height)
        }

        // === PASS 2: Render each child into its allocated width ===
        // The row is as tall as the tallest child, bounded by the space the
        // stack itself was given. Children render into exactly this height
        // so a child squeezed narrow enough to wrap truncates (with an
        // ellipsis) instead of silently spilling an extra row that the
        // parent — which measured the stack as shorter — then clips.
        let rowHeight = max(1, min(allocatedHeight, context.availableHeight))
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
