//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    ///
    /// The six dimensions are `var` so an animation can substitute them — see
    /// the `Animatable` conformance below.
    var minWidth: Int?

    /// The ideal width in characters, or nil to use intrinsic size.
    var idealWidth: Int?

    /// The maximum width constraint, or nil for no maximum.
    var maxWidth: FrameDimension?

    /// The minimum height in lines, or nil for no minimum.
    var minHeight: Int?

    /// The ideal height in lines, or nil to use intrinsic size.
    var idealHeight: Int?

    /// The maximum height constraint, or nil for no maximum.
    var maxHeight: FrameDimension?

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
        let target: Int
        if let maximumWidth = maxWidth {
            switch maximumWidth {
            case .infinity:
                target = availableWidth
            case .fixed(let value):
                target = min(value, availableWidth)
            }
        } else if let ideal = idealWidth {
            target = min(ideal, availableWidth)
        } else {
            // No max constraint - offer the available width, then size to content.
            target = availableWidth
        }
        // Floored, because this number is written straight onto the content's
        // `availableWidth` and a leaf that builds a run from it (Divider) has
        // no defence: `String(repeating:count:)` requires a non-negative count.
        // Every chrome subtraction in the framework already clamps; the frame
        // is where an app's own arithmetic — `.frame(width: available -
        // labelWidth)` — arrives unexamined.
        return max(0, target)
    }

    /// The height the content is offered for a given available height, or
    /// `nil` to use the content's intrinsic height. Shared by the render and
    /// measure passes (see ``contentTargetWidth(availableWidth:)``).
    ///
    /// - Parameter fills: Whether `maxHeight: .infinity` should expand to
    ///   `availableHeight`. True when rendering — the frame is being given
    ///   concrete space and fills it. False when the caller asked for an IDEAL
    ///   height (no height in the proposal): "as tall as I'm given" has no
    ///   answer when nothing was given, so the honest report is the content's
    ///   own height, flagged flexible. SwiftUI resolves an unspecified
    ///   proposal the same way, and the alternative is a lie with visible
    ///   consequences — inside a `ScrollView`, a frame reporting the measure
    ///   budget as its natural height invents thousands of lines of scrollable
    ///   emptiness under a one-line label.
    func contentTargetHeight(availableHeight: Int, fills: Bool = true) -> Int? {
        let target: Int?
        if let maximumHeight = maxHeight {
            switch maximumHeight {
            case .infinity:
                target = fills ? availableHeight : nil
            case .fixed(let value):
                target = min(value, availableHeight)
            }
        } else if let ideal = idealHeight {
            target = min(ideal, availableHeight)
        } else {
            target = nil  // Use intrinsic height
        }
        // Floored for the reason given on `contentTargetWidth(availableWidth:)`
        // — nil still means "use the content's own height", not zero.
        return target.map { max(0, $0) }
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
        // …and the height half, which was missing. `hasExplicitHeight` is the flag
        // by which "child views (like List) know to expand to fill the available
        // height" (see `RenderContext.withAvailableHeight(_:)`), and a
        // `.frame(height:)` is precisely a container giving a height — but only
        // the width half was ever set, so a `Table` inside one hugged its rows and
        // left the rest of the frame blank.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
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

        // The content's own explicit `.alignmentGuide`, when it set one. The
        // frame is a fixed region holding one child, so there is no run to
        // merge — the child's guide meets the frame's. A guided child shifts as
        // a BLOCK (one offset for every line) rather than per-line, which is
        // what the ragged-line arithmetic below does by default.
        let contentSize = (width: buffer.width, height: buffer.height)
        let horizontalGuide = horizontalGuidePlacement(
            of: content, size: contentSize, alignment: alignment.horizontal, in: targetWidth)

        // Calculate vertical offset for alignment
        let verticalOffset =
            verticalGuidePlacement(
                of: content, size: contentSize, alignment: alignment.vertical, in: targetHeight)
            ?? alignment.vertical.childOffset(childHeight: buffer.height, in: targetHeight)

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
            let (aligned, alignedWidth) = alignHorizontally(
                line, toWidth: targetWidth, guideOffset: horizontalGuide)
            result.append(aligned)
            resultWidth = max(resultWidth, alignedWidth)
        }

        // The content shifted within the frame; carry overlay layers by the
        // same amount. The horizontal shift matches the widest line — exact
        // for the common uniform-width buffer.
        let horizontalOffset =
            horizontalGuide
            ?? alignment.horizontal.childOffset(childWidth: buffer.width, in: targetWidth)
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
    private func alignHorizontally(
        _ line: String, toWidth targetWidth: Int, guideOffset: Int?
    ) -> (line: String, width: Int) {
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
        // The same guide arithmetic as every other placement: a `padding`-wide
        // gap is a child of width `lineWidth` inside `targetWidth`.
        // A guide shifts the whole block by one offset; without one, each line
        // is padded on its own width (the long-standing ragged behaviour).
        let leftPad =
            guideOffset.map { min($0, padding) }
            ?? alignment.horizontal.childOffset(
                childWidth: targetWidth - padding, in: targetWidth)
        let rightPad = padding - leftPad
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
    /// measure — see `measureAnalytically(proposal:context:)`.
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
        // An `.infinity` maximum only fills a height that was actually proposed
        // (see `contentTargetHeight(availableHeight:fills:)`).
        let fillsHeight = proposal.height != nil
        let targetHeight = contentTargetHeight(availableHeight: availableHeight, fills: fillsHeight)
        var contentContext = context
        contentContext.availableWidth = availableWidth
        if let targetHeight {
            contentContext.availableHeight = targetHeight
        }
        contentContext.hasExplicitWidth = true
        // As the render path: a height constraint is an explicit height.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
        }
        let contentSize = measureChild(
            content,
            proposal: ProposedSize(width: availableWidth, height: targetHeight),
            context: contentContext)

        var height = contentSize.height
        if let minHeight {
            height = max(height, minHeight)
        }
        if let maximumHeight = maxHeight, case .infinity = maximumHeight, fillsHeight {
            height = max(height, availableHeight)
        }
        height = min(height, availableHeight)

        // The height half of the flexibility report, which `flexibleWidth` hard-codes
        // to false. It used to be unobservable — an `.infinity` maxHeight reported
        // `availableHeight`, so a parent offering more got the same answer whether or
        // not it knew the frame could grow. Now that the report is the content's own
        // height, "can grow" is the only thing distinguishing this from a rigid frame,
        // and the measure/render parity harness reads it.
        return ViewSize(
            width: availableWidth, height: height,
            isWidthFlexible: true,
            isHeightFlexible: hasInfiniteMaxHeight || contentSize.isHeightFlexible)
    }

    /// Whether the frame fills its available height (`maxHeight: .infinity`).
    private var hasInfiniteMaxHeight: Bool {
        if case .infinity? = maxHeight { return true }
        return false
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
        // renderToBuffer uses. An `.infinity` maximum fills only a height that
        // was actually proposed (see `contentTargetHeight(availableHeight:fills:)`).
        let fillsHeight = proposal.height != nil
        let targetWidth = contentTargetWidth(availableWidth: availableWidth)
        let targetHeight = contentTargetHeight(availableHeight: availableHeight, fills: fillsHeight)

        var contentContext = context
        contentContext.availableWidth = targetWidth
        contentContext.availableHeight = targetHeight ?? availableHeight
        if minWidth != nil || idealWidth != nil || maxWidth != nil {
            contentContext.hasExplicitWidth = true
        }
        // As the render path: a height constraint is an explicit height.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
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
        if let maximumHeight = maxHeight, case .infinity = maximumHeight, fillsHeight {
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

// MARK: - Animating a fixed frame

extension FlexibleFrameView: Animatable {
    /// A **fixed** frame's width and height — what `.frame(width:height:)`
    /// pins — so growing or shrinking a box inside ``withAnimation(_:_:)``
    /// is a resize rather than a jump.
    ///
    /// Only the fixed case. SwiftUI draws the same line by having two types
    /// (`_FrameLayout` is `Animatable`, `_FlexFrameLayout` is not); TUIkit has
    /// one, so the distinction is made here instead: a dimension is animated
    /// only where the view was built by pinning min, ideal and max to the same
    /// number. A genuinely flexible frame — `maxWidth: .infinity` — has no
    /// number to move between, and `-1` is the sentinel that says so. A
    /// dimension going from unconstrained to fixed therefore snaps, which is
    /// the honest answer: there is no width it was previously at.
    public var animatableData: AnimatablePair<Double, Double> {
        get {
            AnimatablePair(
                Self.pinned(minWidth, idealWidth, maxWidth),
                Self.pinned(minHeight, idealHeight, maxHeight))
        }
        set {
            Self.repin(&minWidth, &idealWidth, &maxWidth, to: newValue.first)
            Self.repin(&minHeight, &idealHeight, &maxHeight, to: newValue.second)
        }
    }

    /// The number a dimension is pinned to, or `-1` when it is not pinned.
    private static func pinned(_ min: Int?, _ ideal: Int?, _ max: FrameDimension?) -> Double {
        guard let ideal, min == ideal, max == .fixed(ideal) else { return -1 }
        return Double(ideal)
    }

    /// Moves a pinned dimension, leaving an unpinned one alone.
    private static func repin(
        _ min: inout Int?, _ ideal: inout Int?, _ max: inout FrameDimension?, to value: Double
    ) {
        guard value >= 0, pinned(min, ideal, max) >= 0 else { return }
        let cells = Int(value.rounded())
        min = cells
        ideal = cells
        max = .fixed(cells)
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: Each member gets its OWN frame, which is the measured SwiftUI
///   result rather than the convenient reading:
///   `HStack { Group { Text("AA"); Text("BB") }.frame(width: 80) }` lays the
///   two texts out at exactly the frames writing `.frame(width: 80)` on each
///   member separately produces. A `.frame(maxWidth: .infinity)` on a `Group`
///   therefore gives every member the greed, and they share the slack.
extension FlexibleFrameView: SingleContentWrapper {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        FlexibleFrameView<V>(
            content: view,
            minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
            alignment: alignment)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension FlexibleFrameView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension FlexibleFrameView: GridRowProviding where Content: GridRowProviding {}
