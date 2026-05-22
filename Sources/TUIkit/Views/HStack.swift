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

        var totalWidth = 0
        var maxHeight = 0
        var hasFlexibleWidth = false

        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            totalWidth += size.width
            maxHeight = max(maxHeight, size.height)
            if child.isSpacer || size.isWidthFlexible {
                hasFlexibleWidth = true
            }
        }
        totalWidth += max(0, children.count - 1) * spacing

        // Never advertise a width larger than the constraint we were given —
        // an over-report would make the parent reserve space that does not
        // exist and let siblings overlap.
        let widthLimit = proposal.width ?? context.availableWidth
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

        let finalWidths = Self.distributeWidths(
            naturalWidth: naturalWidth,
            isFlexible: isFlexible,
            contentWidth: contentWidth
        )

        // === PASS 2: Render each child into its allocated width ===
        var result = FrameBuffer()
        for (index, child) in children.enumerated() {
            let spacingToApply = index > 0 ? spacing : 0
            let finalWidth = finalWidths[index]

            if child.isSpacer {
                let spacerBuffer = FrameBuffer(emptyWithWidth: finalWidth, height: maxHeight)
                result.appendHorizontally(spacerBuffer, spacing: spacingToApply)
            } else {
                let buffer = child.render(width: finalWidth, height: context.availableHeight, context: context)
                result.appendHorizontally(buffer, spacing: spacingToApply)
            }
        }

        // Final guard: the assembled row never exceeds the space we were given,
        // even when inter-child spacing alone would overflow a tiny terminal.
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Distributes `contentWidth` (available width minus inter-child spacing)
    /// across the children.
    ///
    /// - When everything fits, fixed children keep their natural width and
    ///   flexible children absorb the surplus.
    /// - When space is short, flexible children are shrunk first.
    /// - When even the fixed content overflows, flexible children collapse to
    ///   zero and fixed children are truncated left-to-right, so the leftmost
    ///   content stays readable.
    ///
    /// The returned widths always sum to at most `contentWidth`.
    private static func distributeWidths(
        naturalWidth: [Int],
        isFlexible: [Bool],
        contentWidth: Int
    ) -> [Int] {
        var result = naturalWidth
        let flexIndices = isFlexible.indices.filter { isFlexible[$0] }
        var nonFlexTotal = 0
        var flexTotal = 0
        for index in naturalWidth.indices {
            if isFlexible[index] {
                flexTotal += naturalWidth[index]
            } else {
                nonFlexTotal += naturalWidth[index]
            }
        }

        if nonFlexTotal + flexTotal <= contentWidth {
            // Case A — everything fits; flexible children absorb the surplus.
            distribute(contentWidth - nonFlexTotal - flexTotal, to: flexIndices, of: &result, weights: nil)
        } else if nonFlexTotal <= contentWidth {
            // Case B — fixed content fits; flexible children share the remainder.
            for index in flexIndices { result[index] = 0 }
            let weights = flexTotal > 0 ? flexIndices.map { naturalWidth[$0] } : nil
            distribute(contentWidth - nonFlexTotal, to: flexIndices, of: &result, weights: weights)
        } else {
            // Case C — even the fixed content overflows; flexible → 0, fixed
            // truncated left-to-right.
            for index in flexIndices { result[index] = 0 }
            var used = 0
            for index in naturalWidth.indices where !isFlexible[index] {
                result[index] = max(0, min(naturalWidth[index], contentWidth - used))
                used += result[index]
            }
        }
        return result
    }

    /// Adds `amount` cells across `indices`, either evenly or proportionally
    /// to `weights`, handing out the rounding remainder one cell at a time.
    private static func distribute(_ amount: Int, to indices: [Int], of result: inout [Int], weights: [Int]?) {
        guard !indices.isEmpty, amount > 0 else { return }

        let weightTotal = weights?.reduce(0, +) ?? 0
        if let weights, weightTotal > 0 {
            var distributed = 0
            for (offset, index) in indices.enumerated() {
                let share = amount * weights[offset] / weightTotal
                result[index] += share
                distributed += share
            }
            var remainder = amount - distributed
            var cursor = 0
            while remainder > 0 {
                result[indices[cursor % indices.count]] += 1
                remainder -= 1
                cursor += 1
            }
        } else {
            let per = amount / indices.count
            let remainder = amount % indices.count
            for (offset, index) in indices.enumerated() {
                result[index] += per + (offset < remainder ? 1 : 0)
            }
        }
    }
}

// MARK: - Equatable

extension HStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: HStack<Content>, rhs: HStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}
