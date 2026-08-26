//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ZStack.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ZStack

/// A view that stacks its children on top of each other (z-axis).
///
/// `ZStack` layers views on top of each other, with later views
/// appearing above earlier ones. Apply ``View/zIndex(_:)`` to a child to
/// override the tree order — higher z-index values draw on top.
///
/// The stack is as wide and tall as its largest child. Each child is placed
/// within that frame according to `alignment`, and compositing is
/// character-level: a smaller child only paints its own cells, so the larger
/// layer beneath shows through around it (and a coloured fill is preserved).
///
/// # Example
///
/// Centre a label over a filled background. There is no need to pad the label
/// to width — `alignment` (default `.center`) positions it:
///
/// ```swift
/// ZStack {
///     Text("████████████████")
///     Text("Overlay")           // → "████Overlay█████"
/// }
/// ```
///
/// ```swift
/// ZStack {
///     Text("BBB").zIndex(1)   // drawn on top despite appearing first
///     Text("AAA")
/// }
/// ```
public struct ZStack<Content: View>: View {
    /// The alignment of the children.
    public let alignment: Alignment

    /// The content of the stack.
    public let content: Content

    /// Creates a z-stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The alignment of children (default: .center).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        _ZStackCore(alignment: alignment, content: content)
    }
}

// MARK: - Internal ZStack Core

/// Internal view that handles the actual rendering of ZStack.
private struct _ZStackCore<Content: View>: View, Renderable {
    let alignment: Alignment
    let content: Content

    var body: Never {
        fatalError("_ZStackCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Children resolve through the two-pass `ChildView` API (as
        // `sizeThatFits` below already did), so `ChildViewProvider` content —
        // a `ForEach`, above all — expands to its individual layers with
        // per-child identities. The legacy single-pass `resolveChildInfos`
        // used here before only expanded `ChildInfoProvider`s, which `ForEach`
        // is not, so `ZStack { ForEach }` rendered nothing at all (the ZStack
        // face of issue #8).
        let children = resolveChildViews(from: content, context: context)

        // Draw children in ascending z-index. Ties keep their tree order, so
        // the sort is made stable by using the original index as a tiebreaker.
        let ordered = children.enumerated().sorted { lhs, rhs in
            if lhs.element.zIndex != rhs.element.zIndex {
                return lhs.element.zIndex < rhs.element.zIndex
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        // The stack's frame is the union of its children's sizes (like SwiftUI,
        // a ZStack is as wide/tall as its widest/tallest child). Spacers have
        // no visual box in a ZStack.
        let drawn = ordered.filter { !$0.isSpacer }
        let buffers = drawn.map {
            $0.render(
                width: context.availableWidth, height: context.availableHeight, context: context)
        }
        // Explicit guides on either axis, when any layer set one. They can grow
        // the frame past the largest layer — a layer hanging off the alignment
        // line pushes the others across — so they are resolved before the frame
        // size is decided.
        let sizes = buffers.map { (width: $0.width, height: $0.height) }
        let horizontalRun = horizontalGuideRun(
            drawn, sizes: sizes, alignment: alignment.horizontal,
            minimumExtent: buffers.map(\.width).max() ?? 0)
        let verticalRun = verticalGuideRun(
            drawn, sizes: sizes, alignment: alignment.vertical,
            minimumExtent: buffers.map(\.height).max() ?? 0)
        let frameWidth = horizontalRun?.extent ?? buffers.map(\.width).max() ?? 0
        let frameHeight = verticalRun?.extent ?? buffers.map(\.height).max() ?? 0
        // A zero-size frame means no child drew anything IN FLOW — but a
        // child can still be carrying the whole point of the view as a
        // free-floating layer: `OffsetView` renders exactly that (no lines, one
        // `OverlayLayer` holding the offset content and its hit regions).
        // Returning a bare buffer dropped them, so `ZStack { Text("💨").offset() }`
        // rendered nothing at all. Fold them in instead — the ZStack face of the
        // OverlayModifier bug fixed in 3aedeb1f, and what every other combining
        // op already promises.
        //
        // The in-flow result is unchanged: every buffer reaching this guard is
        // line-empty (a non-empty line would have made `frameWidth > 0`), so
        // `composited` takes its lift-the-layers branch and no line content is
        // produced. The offsets are (0, 0) because a zero-size frame gives every
        // alignment a zero child offset, and each layer's own position already
        // lives inside it. `ZStack {}` still yields a bare buffer — `reduce`
        // over no children returns the initial value.
        guard frameWidth > 0, frameHeight > 0 else {
            return buffers.reduce(FrameBuffer()) {
                $0.compositedResolvingOpacity(with: $1, at: (x: 0, y: 0), palette: context.environment.palette)
            }
        }

        // Composite each child onto a blank frame at its alignment offset, in
        // ascending z-order. Character-level compositing (vs. the old whole-line
        // overlay) means a narrower child no longer truncates a wider one beneath
        // it — the uncovered sides of the lower layer show through — and a child's
        // own offset is honoured so `alignment` actually positions it. A child
        // still paints its full bounding box (including blank-but-coloured fills),
        // so backgrounds are preserved; to centre a label over a fill, size the
        // label to its content and let `alignment` place it rather than padding
        // the string by hand.
        var result = FrameBuffer(
            lines: Array(
                repeating: String(repeating: " ", count: frameWidth),
                count: frameHeight))
        for (index, buffer) in buffers.enumerated() {
            let dx =
                horizontalRun?.offsets[index]
                ?? alignment.horizontal.childOffset(childWidth: buffer.width, in: frameWidth)
            let dy =
                verticalRun?.offsets[index]
                ?? alignment.vertical.childOffset(childHeight: buffer.height, in: frameHeight)
            result = result.compositedResolvingOpacity(
                with: buffer, at: (x: dx, y: dy), palette: context.environment.palette)
        }
        return result
    }
}

// MARK: - Layout

extension _ZStackCore: Layoutable {
    /// Measures the z-stack without rendering: it is as wide/tall as its largest
    /// child (the union of their sizes, matching `renderToBuffer`'s frame), and is
    /// flexible on an axis when any child is — a flexible child fills that extent,
    /// so the stack does too. Alignment and z-index affect placement/draw order,
    /// not size.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }

        var maxWidth = 0
        var maxHeight = 0
        var hasFlexibleWidth = false
        var hasFlexibleHeight = false
        var guideSizes: [(width: Int, height: Int)] = []
        guideSizes.reserveCapacity(children.count)
        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            // Spacers have no visual box in a ZStack — `renderToBuffer` filters
            // them — so they must not contribute a guide here either.
            guideSizes.append(
                child.isSpacer ? (width: 0, height: 0) : (width: size.width, height: size.height))
            maxWidth = max(maxWidth, size.width)
            maxHeight = max(maxHeight, size.height)
            hasFlexibleWidth = hasFlexibleWidth || size.isWidthFlexible
            hasFlexibleHeight = hasFlexibleHeight || size.isHeightFlexible
        }
        // A guide can push a layer off the alignment line and grow the frame
        // past the largest child; the render does this, so the measure must.
        let drawn = children.indices.filter { !children[$0].isSpacer }
        if let run = horizontalGuideRun(
            drawn.map { children[$0] }, sizes: drawn.map { guideSizes[$0] },
            alignment: alignment.horizontal, minimumExtent: maxWidth)
        {
            maxWidth = run.extent
        }
        if let run = verticalGuideRun(
            drawn.map { children[$0] }, sizes: drawn.map { guideSizes[$0] },
            alignment: alignment.vertical, minimumExtent: maxHeight)
        {
            maxHeight = run.extent
        }
        // Never advertise larger than the constraint (mirrors VStack/HStack).
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        return ViewSize(
            width: min(maxWidth, max(0, widthLimit)),
            height: min(maxHeight, max(0, heightLimit)),
            isWidthFlexible: hasFlexibleWidth,
            isHeightFlexible: hasFlexibleHeight)
    }
}

// MARK: - Equatable

extension ZStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: ZStack<Content>, rhs: ZStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.content == rhs.content
    }
}
