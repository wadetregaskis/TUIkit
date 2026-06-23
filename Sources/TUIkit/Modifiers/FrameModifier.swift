//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Frame Dimension

/// Represents a frame dimension that can be a fixed value or infinity.
public enum FrameDimension: Equatable, Sendable {
    /// A fixed size in characters/lines.
    case fixed(Int)

    /// Expand to fill all available space.
    case infinity

    /// The special infinity value for frame constraints.
    public static let max: FrameDimension = .infinity
}

// MARK: - Flexible Frame View

/// A view that applies flexible frame constraints to its content.
///
/// This view handles min/max constraints and renders content with
/// the appropriate available space.
public struct FlexibleFrameView<Content: View>: View {
    /// The content view to constrain.
    let content: Content

    /// The minimum width in characters, or nil for no minimum.
    let minWidth: Int?

    /// The ideal width in characters, or nil to use intrinsic size.
    let idealWidth: Int?

    /// The maximum width constraint, or nil for no maximum.
    let maxWidth: FrameDimension?

    /// The minimum height in lines, or nil for no minimum.
    let minHeight: Int?

    /// The ideal height in lines, or nil to use intrinsic size.
    let idealHeight: Int?

    /// The maximum height constraint, or nil for no maximum.
    let maxHeight: FrameDimension?

    /// The alignment of the content within the frame.
    let alignment: Alignment

    public var body: Never {
        fatalError("FlexibleFrameView renders via Renderable")
    }
}

// MARK: - Equatable Conformance

extension FlexibleFrameView: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: FlexibleFrameView<Content>, rhs: FlexibleFrameView<Content>) -> Bool {
        lhs.content == rhs.content && lhs.minWidth == rhs.minWidth && lhs.idealWidth == rhs.idealWidth && lhs.maxWidth == rhs.maxWidth
            && lhs.minHeight == rhs.minHeight && lhs.idealHeight == rhs.idealHeight && lhs.maxHeight == rhs.maxHeight
            && lhs.alignment == rhs.alignment
    }
}

// MARK: - Renderable

extension FlexibleFrameView {
    /// The width the content is offered for a given available width.
    ///
    /// Shared by ``renderToBuffer(context:)`` and ``sizeThatFits(proposal:context:)``
    /// so the measure and render passes can never disagree about how the
    /// frame constrains its content.
    func contentTargetWidth(availableWidth: Int) -> Int {
        if let maximumWidth = maxWidth {
            switch maximumWidth {
            case .infinity:
                return availableWidth
            case .fixed(let value):
                return min(value, availableWidth)
            }
        } else if let ideal = idealWidth {
            return min(ideal, availableWidth)
        }
        // No max constraint - offer the available width, then size to content.
        return availableWidth
    }

    /// The height the content is offered for a given available height, or
    /// `nil` to use the content's intrinsic height. Shared by the render and
    /// measure passes (see ``contentTargetWidth(availableWidth:)``).
    func contentTargetHeight(availableHeight: Int) -> Int? {
        if let maximumHeight = maxHeight {
            switch maximumHeight {
            case .infinity:
                return availableHeight
            case .fixed(let value):
                return min(value, availableHeight)
            }
        } else if let ideal = idealHeight {
            return min(ideal, availableHeight)
        }
        return nil  // Use intrinsic height
    }
}

extension FlexibleFrameView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Calculate the target width and height based on constraints (the same
        // computation the measure pass uses, see contentTargetWidth/Height).
        let targetWidth = contentTargetWidth(availableWidth: context.availableWidth)
        let targetHeight = contentTargetHeight(availableHeight: context.availableHeight)

        // Create context for content with constrained width
        var contentContext = context
        contentContext.availableWidth = targetWidth
        if let height = targetHeight {
            contentContext.availableHeight = height
        }

        // Mark that an explicit width constraint was set
        if minWidth != nil || idealWidth != nil || maxWidth != nil {
            contentContext.hasExplicitWidth = true
        }

        // Render content
        let buffer = TUIkit.renderToBuffer(content, context: contentContext)

        // Apply minimum constraints
        var finalWidth = buffer.width
        var finalHeight = buffer.height

        if let minimumWidth = minWidth {
            finalWidth = max(finalWidth, minimumWidth)
        }
        if let minimumHeight = minHeight {
            finalHeight = max(finalHeight, minimumHeight)
        }

        // Apply maximum constraints (expand to fill if infinity)
        if let maximumWidth = maxWidth, case .infinity = maximumWidth {
            finalWidth = max(finalWidth, context.availableWidth)
        }
        if let maximumHeight = maxHeight, case .infinity = maximumHeight {
            finalHeight = max(finalHeight, context.availableHeight)
        }

        // If size matches buffer, return as-is
        if finalWidth == buffer.width && finalHeight == buffer.height {
            return buffer
        }

        // Otherwise, align content within the frame
        return alignBuffer(buffer, toWidth: finalWidth, height: finalHeight)
    }

    /// Aligns buffer content within the target frame size.
    private func alignBuffer(_ buffer: FrameBuffer, toWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
        var result: [String] = []

        // Calculate vertical offset for alignment
        let verticalOffset: Int
        switch alignment.vertical {
        case .top:
            verticalOffset = 0
        case .center:
            verticalOffset = max(0, (targetHeight - buffer.height) / 2)
        case .bottom:
            verticalOffset = max(0, targetHeight - buffer.height)
        }

        // Track the aligned result's width as we build it — `alignHorizontally`
        // measures each line for its padding decision anyway, so threading that
        // width out lets the final `replacingLines` skip re-measuring every line.
        var resultWidth = 0
        for row in 0..<targetHeight {
            let contentRow = row - verticalOffset
            let line: String
            if contentRow >= 0 && contentRow < buffer.height {
                line = buffer.lines[contentRow]
            } else {
                line = ""
            }

            // Align horizontally within the frame
            let (aligned, alignedWidth) = alignHorizontally(line, toWidth: targetWidth)
            result.append(aligned)
            resultWidth = max(resultWidth, alignedWidth)
        }

        // The content shifted within the frame; carry overlay layers by the
        // same amount. The horizontal shift matches the widest line — exact
        // for the common uniform-width buffer.
        let horizontalOffset: Int
        switch alignment.horizontal {
        case .leading:
            horizontalOffset = 0
        case .center:
            horizontalOffset = max(0, (targetWidth - buffer.width) / 2)
        case .trailing:
            horizontalOffset = max(0, targetWidth - buffer.width)
        }
        // Pass the now-known width so `replacingLines` doesn't re-measure every
        // padded line. When nothing overflowed the frame, every line is exactly
        // `targetWidth` — flag that so the buffer can skip per-line work too.
        return buffer.replacingLines(
            result, width: resultWidth, uniformWidth: resultWidth == targetWidth,
            overlayShiftX: horizontalOffset, overlayShiftY: verticalOffset)
    }

    /// Aligns a single line within the given width, returning the aligned line
    /// and its visible width — `max(targetWidth, the line's own width)` — so the
    /// caller can total the result width without a second `strippedLength` pass.
    private func alignHorizontally(_ line: String, toWidth targetWidth: Int) -> (line: String, width: Int) {
        let visibleWidth = line.strippedLength

        if visibleWidth >= targetWidth {
            return (line, visibleWidth)
        }

        let padding = targetWidth - visibleWidth

        switch alignment.horizontal {
        case .leading:
            return (line + String(repeating: " ", count: padding), targetWidth)
        case .center:
            let left = padding / 2
            let right = padding - left
            return (String(repeating: " ", count: left) + line + String(repeating: " ", count: right), targetWidth)
        case .trailing:
            return (String(repeating: " ", count: padding) + line, targetWidth)
        }
    }
}

// MARK: - Layoutable

extension FlexibleFrameView: Layoutable {
    /// Measures the frame, skipping the render-to-measure fallback's double
    /// render for the common fill case.
    ///
    /// `FlexibleFrameView` is `Renderable`, so `measureChild` measured it
    /// through the render-to-measure fallback: render the whole subtree once for
    /// its natural size, then again 8 cells wider to probe width-flexibility
    /// (and the real render then made three passes in total).
    ///
    /// A `maxWidth: .infinity` frame always fills the width it is offered and is
    /// always width-flexible, so its size needs no flexibility probe — a single
    /// content measure (structural when the content is itself `Layoutable`, the
    /// common `VStack`/`HStack`/`Text` case) gives the height, and the width is
    /// the available width. Every other constraint shape makes the frame's width
    /// depend on how the content *reflows* at different widths (a wrapping label
    /// widens when given more room), which only re-rendering reliably captures —
    /// those keep the original two-render measurement, byte-for-byte unchanged.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard hasInfiniteMaxWidth else {
            return measureByRendering(proposal: proposal, context: context)
        }

        let availableWidth = proposal.width ?? context.availableWidth
        let availableHeight = proposal.height ?? context.availableHeight

        // Measure the content once, in the same context renderToBuffer renders
        // it in (full width, optional fixed height, explicit-width flag), to get
        // the height the frame reports. The width is the available width: the
        // content's `max(_, availableWidth)` bump fills it and the outer clamp
        // caps it there.
        let targetHeight = contentTargetHeight(availableHeight: availableHeight)
        var contentContext = context
        contentContext.availableWidth = availableWidth
        if let targetHeight {
            contentContext.availableHeight = targetHeight
        }
        contentContext.hasExplicitWidth = true
        let contentSize = measureChild(
            content,
            proposal: ProposedSize(width: availableWidth, height: targetHeight),
            context: contentContext)

        var height = contentSize.height
        if let minHeight {
            height = max(height, minHeight)
        }
        if let maximumHeight = maxHeight, case .infinity = maximumHeight {
            height = max(height, availableHeight)
        }
        height = min(height, availableHeight)

        return ViewSize.flexibleWidth(minWidth: availableWidth, height: height)
    }

    /// Whether the frame fills its available width (`maxWidth: .infinity`).
    private var hasInfiniteMaxWidth: Bool {
        if case .infinity? = maxWidth { return true }
        return false
    }

    /// A render-and-probe measure, kept locally for the constraint shapes whose
    /// width depends on content reflow: render for the natural size, then 8 cells
    /// wider to see whether the width grows. This is the same heuristic
    /// `measureChild`'s fallback once used globally (since retired there in favour
    /// of a single render); `FrameModifier` keeps it for these specific shapes
    /// because their width genuinely tracks reflow.
    private func measureByRendering(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.hasExplicitWidth = false
        if let width = proposal.width {
            measureContext.availableWidth = width
        }
        if let height = proposal.height {
            measureContext.availableHeight = height
        }
        let buffer = TUIkit.renderToBuffer(self, context: measureContext)
        let naturalWidth = buffer.width

        var probeContext = measureContext
        probeContext.availableWidth = naturalWidth + 8
        let probedWidth = TUIkit.renderToBuffer(self, context: probeContext).width

        if probedWidth > naturalWidth {
            return ViewSize.flexibleWidth(minWidth: naturalWidth, height: buffer.height)
        }
        return ViewSize.fixed(naturalWidth, buffer.height)
    }
}
