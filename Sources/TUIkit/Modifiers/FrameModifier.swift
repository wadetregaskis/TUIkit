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

        // Build the aligned line in place: reserve `line` plus its padding, then
        // append the leading spaces (if any), the line, and the trailing spaces
        // (if any) as borrowed runs from the shared spaces buffer. Byte-identical
        // to the former `String(repeating:) + line + String(repeating:)` forms,
        // without the per-line spaces temporaries or `+`-chain intermediates. This
        // runs once per line of every `.frame(...)` (e.g. the `modifiers`
        // scenario, two framed-and-padded chains per row).
        let leftPad: Int
        let rightPad: Int
        switch alignment.horizontal {
        case .leading:
            leftPad = 0
            rightPad = padding
        case .center:
            leftPad = padding / 2
            rightPad = padding - leftPad
        case .trailing:
            leftPad = padding
            rightPad = 0
        }
        var aligned = ""
        aligned.reserveCapacity(line.utf8.count + padding)
        if leftPad > 0 { aligned += asciiSpaces(leftPad) }
        aligned += line
        if rightPad > 0 { aligned += asciiSpaces(rightPad) }
        return (aligned, targetWidth)
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
    /// the available width. Every other constraint shape measures analytically
    /// too, by mirroring `renderToBuffer`'s sizing math around one content
    /// measure — see ``measureAnalytically(proposal:context:)``.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard hasInfiniteMaxWidth else {
            return measureAnalytically(proposal: proposal, context: context)
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

    /// An analytic measure for the general constraint shapes (fixed, ideal and
    /// min-only frames): one content *measure* through `measureChild`, with the
    /// frame's own sizing math mirrored from ``renderToBuffer(context:)`` so
    /// the two can never disagree.
    ///
    /// This replaces a render-and-probe measure (render the whole subtree for
    /// its natural size, then again 8 cells wider to detect width growth) that
    /// predated Layoutable-everywhere. Now that every view reports an honest
    /// size *and flexibility* structurally, rendering to measure was only cost:
    /// each `.frame(width:)`/`.frame(height:)` measure was two full subtree
    /// renders, and because ancestors measure a child both in their own
    /// `sizeThatFits` and again in their render pass, nested frames compounded
    /// those renders multiplicatively — the issue #7 layout (two nested framed
    /// columns of interactive rows) fully rendered its Card subtree 15 times
    /// per idle pulse frame.
    ///
    /// Two clamps mirror the render path exactly:
    /// - the *content's* report is capped at the width/height the frame offers
    ///   it, because the universal `renderToBuffer` clamps the content's buffer
    ///   to its available space (a Slider whose track floor exceeds a narrow
    ///   `.frame(width:)` still renders inside it);
    /// - the *frame's* report is capped at its own availability, because the
    ///   same clamp applies to the frame's buffer in its parent (a
    ///   `.frame(width: 20)` squeezed into 12 cells renders 12 wide).
    private func measureAnalytically(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let availableWidth = proposal.width ?? context.availableWidth
        let availableHeight = proposal.height ?? context.availableHeight

        // The width/height the content is offered — the same shared helpers
        // renderToBuffer uses.
        let targetWidth = contentTargetWidth(availableWidth: availableWidth)
        let targetHeight = contentTargetHeight(availableHeight: availableHeight)

        var contentContext = context
        contentContext.availableWidth = targetWidth
        contentContext.availableHeight = targetHeight ?? availableHeight
        if minWidth != nil || idealWidth != nil || maxWidth != nil {
            contentContext.hasExplicitWidth = true
        }
        let contentSize = measureChild(
            content,
            proposal: ProposedSize(width: targetWidth, height: targetHeight),
            context: contentContext)

        // Mirror renderToBuffer's final-size math: the content is capped at
        // what the frame offers it, minimums floor the result, and an
        // `.infinity` max fills the available extent.
        var wantedWidth = min(contentSize.width, targetWidth)
        var wantedHeight = targetHeight.map { min(contentSize.height, $0) } ?? contentSize.height
        if let minimumWidth = minWidth {
            wantedWidth = max(wantedWidth, minimumWidth)
        }
        if let minimumHeight = minHeight {
            wantedHeight = max(wantedHeight, minimumHeight)
        }
        if let maximumWidth = maxWidth, case .infinity = maximumWidth {
            wantedWidth = max(wantedWidth, availableWidth)
        }
        if let maximumHeight = maxHeight, case .infinity = maximumHeight {
            wantedHeight = max(wantedHeight, availableHeight)
        }

        // The universal render clamp caps the frame's own buffer at its
        // availability, so the report must not exceed it either.
        let width = min(wantedWidth, availableWidth)
        let height = min(wantedHeight, availableHeight)

        // An axis is flexible iff offering more space would grow the rendered
        // frame:
        // - an `.infinity` max always fills whatever is offered;
        // - a frame squeezed below the size its constraints want (the clamp
        //   engaged) grows back toward it when offered more — e.g. a
        //   `.frame(width: 20)` in 12 cells reports (12, flexible);
        // - otherwise growth comes from the content filling extra space,
        //   unless a cap (a fixed max, or an ideal acting as one) already pins
        //   the reported size — a `.frame(width: 30)` at its cap is rigid,
        //   while a `maxWidth: .fixed(60)` frame in 40 cells still grows.
        func axisFlexible(
            isInfinity: Bool, reported: Int, wanted: Int, contentFlexible: Bool, cap: Int?
        ) -> Bool {
            if isInfinity { return true }
            if reported < wanted { return true }
            guard contentFlexible else { return false }
            guard let cap else { return true }
            return wanted < cap
        }
        let widthCap: Int?
        var widthInfinity = false
        if let maximumWidth = maxWidth {
            if case .fixed(let value) = maximumWidth {
                widthCap = value
            } else {
                widthCap = nil
                widthInfinity = true
            }
        } else {
            widthCap = idealWidth
        }
        let heightCap: Int?
        var heightInfinity = false
        if let maximumHeight = maxHeight {
            if case .fixed(let value) = maximumHeight {
                heightCap = value
            } else {
                heightCap = nil
                heightInfinity = true
            }
        } else {
            heightCap = idealHeight
        }

        return ViewSize(
            width: width,
            height: height,
            isWidthFlexible: axisFlexible(
                isInfinity: widthInfinity, reported: width, wanted: wantedWidth,
                contentFlexible: contentSize.isWidthFlexible, cap: widthCap),
            isHeightFlexible: axisFlexible(
                isInfinity: heightInfinity, reported: height, wanted: wantedHeight,
                contentFlexible: contentSize.isHeightFlexible, cap: heightCap))
    }
}
