//  🖥️ TUIKit — Terminal UI Kit for Swift
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
        let infos = resolveChildInfos(from: content, context: context)

        // Draw children in ascending z-index. Ties keep their tree order, so
        // the sort is made stable by using the original index as a tiebreaker.
        let ordered = infos.enumerated().sorted { lhs, rhs in
            if lhs.element.zIndex != rhs.element.zIndex {
                return lhs.element.zIndex < rhs.element.zIndex
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        // The stack's frame is the union of its children's sizes (like SwiftUI,
        // a ZStack is as wide/tall as its widest/tallest child).
        let buffers = ordered.compactMap(\.buffer)
        let frameWidth = buffers.map(\.width).max() ?? 0
        let frameHeight = buffers.map(\.height).max() ?? 0
        guard frameWidth > 0, frameHeight > 0 else { return FrameBuffer() }

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
        for buffer in buffers {
            let dx = alignment.horizontal.childOffset(childWidth: buffer.width, in: frameWidth)
            let dy = alignment.vertical.childOffset(childHeight: buffer.height, in: frameHeight)
            result = result.composited(with: buffer, at: (x: dx, y: dy))
        }
        return result
    }
}

// MARK: - Equatable

extension ZStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: ZStack<Content>, rhs: ZStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.content == rhs.content
    }
}
