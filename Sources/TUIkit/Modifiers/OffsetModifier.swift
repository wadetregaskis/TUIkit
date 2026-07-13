//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OffsetModifier.swift
//
//  `.offset(x:y:)` — draw a view displaced from its natural position,
//  floating over its siblings, modelled on SwiftUI's `offset`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The view wrapper created by ``View/offset(x:y:)``.
///
/// The content is measured at its natural place (layout is unaffected, as in
/// SwiftUI) but DRAWN `x` columns right and `y` rows down of it, floating
/// over whatever it lands on. Terminal-forced deviations from SwiftUI,
/// documented on the modifier: the vacated cells show the layer beneath
/// (there is no transparency, so nothing is painted there), and the
/// displaced content composites above its siblings.
public struct OffsetView<Content: View>: View {
    let content: Content
    let x: Int
    let y: Int

    public var body: Never {
        fatalError("OffsetView renders via Renderable")
    }
}

extension OffsetView: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Layout keeps the content's natural size — the offset displaces
        // only the drawing (SwiftUI semantics).
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let rendered = TUIkit.renderToBuffer(content, context: context)
        guard !context.isMeasuring else { return rendered }

        // Paint NOTHING at the natural position (the terminal has no
        // transparency, so an in-place blank box would erase the layers
        // beneath — the opposite of SwiftUI, where the vacated region shows
        // the background). The displaced drawing floats as an overlay layer,
        // carrying the content's hit regions (and any layers it emitted
        // itself) so interaction follows the visible position.
        var empty = FrameBuffer()
        empty.overlays.append(
            OverlayLayer(offsetX: x, offsetY: y, content: rendered, level: .popover))
        return empty
    }
}

extension View {
    /// Offsets this view's DRAWN position by `x` columns and `y` rows,
    /// leaving layout untouched — the view still occupies its natural place
    /// for sizing, but paints displaced, floating over its siblings.
    ///
    /// Deviations from SwiftUI, forced by the terminal's compositing model
    /// (no per-cell transparency): the vacated cells show whatever is
    /// beneath them (nothing is painted at the natural position), and the
    /// displaced content composites above sibling views rather than in its
    /// own z-position. In practice this matches the main uses — nudging
    /// decorations and floating transient effects (see the Mouse page's
    /// drag-and-drop poof).
    ///
    /// - Parameters:
    ///   - x: Columns to shift right (negative shifts left).
    ///   - y: Rows to shift down (negative shifts up).
    /// - Returns: A view drawn at the offset position.
    public func offset(x: Int = 0, y: Int = 0) -> some View {
        OffsetView(content: self, x: x, y: y)
    }
}
