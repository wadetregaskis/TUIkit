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
    var x: Int
    var y: Int

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
        // The slot still has to EXIST, though. A buffer with no lines is not
        // "a blank view" to a stack — it is "no child": `appendVertically`
        // drops it, spacing and all, so every sibling after an offset view
        // moved up into its place and the floated drawing composited on top of
        // whatever took it. Empty lines reserve the rows and paint no cells,
        // which is exactly the shape this needs: the footprint the measure pass
        // promised, and nothing drawn in it.
        //
        // The WIDTH is declared even though no cell carries it, because a
        // container that aligns its children asks each buffer how wide it is:
        // `_ZStackCore` positions by `alignment.childOffset(childWidth:)`, and
        // a zero-width answer centres an 8-cell label 4 cells right of centre
        // and pins a trailing-aligned one to the frame's right edge. Compositing
        // reads the lines, not this number, so the promise above still holds —
        // an empty line paints nothing wherever it is placed.
        var placeholder = FrameBuffer(
            lines: Array(repeating: "", count: rendered.height), width: rendered.width)
        placeholder.overlays.append(
            OverlayLayer(offsetX: x, offsetY: y, content: rendered, level: .popover))
        return placeholder
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

    /// Offsets this view's drawn position by a size — SwiftUI's
    /// `offset(_ offset: CGSize)`, in whole cells.
    ///
    /// The same modifier as ``offset(x:y:)``, spelled the way SwiftUI spells it
    /// when the displacement is already a value rather than two numbers. A size
    /// used as a displacement is SwiftUI's own idiom, not this framework's
    /// invention; ``CellSize`` is the counterpart of the `CGSize` it takes,
    /// because a terminal counts cells where SwiftUI counts points.
    ///
    /// - Parameter offset: Columns to shift right in `width`, rows to shift
    ///   down in `height` (negative shifts the other way).
    /// - Returns: A view drawn at the offset position.
    public func offset(_ offset: CellSize) -> some View {
        self.offset(x: offset.width, y: offset.height)
    }
}

// MARK: - Animating the offset

extension OffsetView: Animatable {
    /// The displacement is what moves, so a change to it inside
    /// ``withAnimation(_:_:)`` slides rather than jumps.
    ///
    /// The cheapest kind of animated geometry here: an offset does not change
    /// layout — the view keeps its natural place for sizing — so a frame of
    /// this animation re-renders the subtree but re-measures nothing.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(x), Double(y)) }
        set {
            x = Int(newValue.first.rounded())
            y = Int(newValue.second.rounded())
        }
    }
}
