//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // The slot still has to EXIST, though, and has to declare its width —
        // see ``FrameBuffer/init(footprintWidth:height:)``, which carries both
        // halves of that and why each one was a bug.
        var placeholder = FrameBuffer(footprintWidth: rendered.width, height: rendered.height)
        placeholder.overlays.append(
            OverlayLayer(
                offsetX: x, offsetY: y, content: rendered, level: .popover,
                // Below the anchored presentations that share this level: a
                // displaced label is not a window, so an open drop-down it
                // overlaps draws over it, whatever order the tree emitted them
                // in. See ``OverlayLayer/displacedDrawingZIndex``.
                zIndex: OverlayLayer.displacedDrawingZIndex,
                // Displaced drawing, not a surface: `.offset` moves this view's
                // own cells to another place on the page, and the page behind
                // them is meant to keep showing. See ``OverlayLayer/isOpaque``.
                isOpaque: false))
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

// MARK: - Seeing Through the Wrapper

/// - Note: Layout is unaffected either way (the content is measured at its
///   natural place), so shifting each member by `(x, y)` puts the same cells
///   in the same places as shifting the pair by `(x, y)`.
extension OffsetView: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        OffsetView<V>(content: view, x: x, y: y)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension OffsetView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension OffsetView: GridRowProviding where Content: GridRowProviding {}
