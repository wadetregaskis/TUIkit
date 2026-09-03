//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PositionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Places this view's centre at a point in its parent's coordinate space.
    ///
    /// The absolute counterpart of ``offset(x:y:)``, and it differs from it in
    /// layout as well as in arithmetic: an offset keeps the view's natural
    /// place and displaces the drawing, while a positioned view **takes the
    /// space it is offered** and draws itself at the point given. That is
    /// SwiftUI's rule too, and it is what makes `.position` the thing to reach
    /// for inside a `ZStack` or a `GeometryReader` and `.offset` the thing to
    /// nudge with.
    ///
    /// ```swift
    /// GeometryReader { proxy in
    ///     Text("×").position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    /// }
    /// ```
    ///
    /// The centre of an even-sized view falls between cells; it rounds down, so
    /// a two-cell-wide view centred at column 10 occupies columns 9 and 10.
    ///
    /// - Parameters:
    ///   - x: The column its centre sits on.
    ///   - y: The row its centre sits on.
    /// - Returns: A view drawn at that position, filling the space offered.
    public func position(x: Int = 0, y: Int = 0) -> some View {
        PositionView(content: self, x: x, y: y)
    }

    /// Places this view's centre at `position` — the same modifier as
    /// ``position(x:y:)``, spelled the way SwiftUI spells it when the point is
    /// already a value.
    ///
    /// - Parameter position: Where its centre sits.
    /// - Returns: A view drawn at that position, filling the space offered.
    public func position(_ position: CellSize) -> some View {
        self.position(x: position.width, y: position.height)
    }
}

/// Draws its content centred on a point, and fills the space it was offered.
/// See ``View/position(x:y:)``.
public struct PositionView<Content: View>: View {
    let content: Content
    var x: Int
    var y: Int

    public var body: Never {
        fatalError("PositionView renders via Renderable")
    }
}

extension PositionView: Animatable {
    /// The point is what moves, so a change to it inside
    /// ``withAnimation(_:_:)`` glides rather than jumps.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(x), Double(y)) }
        set {
            x = Int(newValue.first.rounded())
            y = Int(newValue.second.rounded())
        }
    }
}

extension PositionView: Renderable, Layoutable {
    /// Fills what it is offered: a positioned view's own size says nothing
    /// about where it sits, and its parent must reserve the whole space for
    /// the coordinates to mean anything.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: proposal.width ?? context.availableWidth,
            height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true, isHeightFlexible: true)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let rendered = TUIkit.renderToBuffer(content, context: context)
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        guard !context.isMeasuring else { return rendered }

        // Floated rather than composited into the lines, for the reason
        // `OffsetView` floats: a terminal has no transparency, so painting a
        // full-size blank field here would erase whatever is beneath it. The
        // rows still have to EXIST or a stack drops the child entirely, and the
        // WIDTH has to be declared or a container that aligns its children
        // places this one as though it were nothing wide — the footprint the
        // measure above promised, with nothing drawn in it.
        var placeholder = FrameBuffer(
            lines: Array(repeating: "", count: height), width: width)
        placeholder.overlays.append(
            OverlayLayer(
                offsetX: x - rendered.width / 2,
                offsetY: y - rendered.height / 2,
                content: rendered,
                level: .popover,
                // Displaced drawing, not a surface — as for `.offset`. See
                // ``OverlayLayer/isOpaque``.
                isOpaque: false))
        _ = width
        return placeholder
    }
}
