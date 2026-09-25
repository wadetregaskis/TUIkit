//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+Overlays.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {
    /// Composites every accumulated ``overlays`` layer onto this buffer in
    /// z-order — ascending ``OverlayLevel`` (popover < modal < alert <
    /// notification), then ``OverlayLayer/zIndex`` — resolving each layer's
    /// placement against a `maxWidth` × `maxHeight` area.
    ///
    /// A layer that ``OverlayLayer/centered`` is placed in the centre of that
    /// area; otherwise it draws at its (clamped, flip-on-overflow) offset. A layer
    /// that ``OverlayLayer/dimsBackground`` first dims everything beneath it into a
    /// flat, inert backdrop (using `palette` for the colours) — so a screen-level
    /// modal reads as modal over the whole screen no matter where it was attached.
    ///
    /// Layers that a composited layer itself emits join the same ordered queue
    /// and take their place by level, bounded by a cap against a pathological
    /// re-emitting layer.
    ///
    /// This is exactly what `RenderLoop` runs at the screen root; it's public so
    /// tests can reproduce the composited result a headless `renderToBuffer`
    /// otherwise leaves pending in ``overlays``.
    public func compositingOverlays(
        maxWidth: Int, maxHeight: Int, palette: any Palette
    ) -> FrameBuffer {
        // The page's OWN opacity resolves first, before anything is drawn over
        // it. This is the screen root, so nothing is behind the page but the
        // surface — and if a region were still pending when a layer composited
        // over it, the region would go on naming those cells and the LAYER's
        // cells would be faded at the root instead of the page's.
        var result = resolvingOpacity(surface: palette.background, palette: palette)
        // ONE queue, re-sorted every time a layer is drawn. A layer nested in
        // another layer's content — an alert presented from inside a sheet —
        // is lifted into `overlays` only when its host composites, and a pass
        // that sorted its snapshot and drained it would draw the newcomer
        // after everything in that pass: a `.notification` toast, declared
        // topmost, was buried by the nested alert's dimming. Lifted layers
        // join the queue behind what is still pending and take their place by
        // level; a drawn host is drawn, so its own nested layers land above it
        // whatever their level. A cap guards against a pathological layer that
        // keeps re-emitting itself; 256 is far beyond real use.
        var queue = result.overlays.enumerated().map { (order: $0.offset, layer: $0.element) }
        result.overlays = []
        var nextOrder = queue.count
        var drawsRemaining = 256
        while !queue.isEmpty && drawsRemaining > 0 {
            drawsRemaining -= 1
            queue.sort { lhs, rhs in
                if lhs.layer.level != rhs.layer.level {
                    return lhs.layer.level < rhs.layer.level
                }
                if lhs.layer.zIndex != rhs.layer.zIndex {
                    return lhs.layer.zIndex < rhs.layer.zIndex
                }
                return lhs.order < rhs.order
            }
            let layer = queue.removeFirst().layer
            do {
                // A modal/alert layer dims everything beneath it first.
                if layer.dimsBackground {
                    // Expand to the full area first, so the backdrop dims the whole
                    // screen and the centred layer has room — even when the page
                    // beneath is shorter or narrower than the screen. Padding moves
                    // no content, so the (already-shifted) layers are preserved.
                    if result.height < maxHeight || result.width < maxWidth {
                        let target = max(result.height, maxHeight)
                        let expanded = (0..<target).map { row -> String in
                            row < result.lines.count
                                ? result.lines[row].padToVisibleWidth(maxWidth)
                                : String(repeating: " ", count: maxWidth)
                        }
                        result = result.replacingLines(expanded)
                    }
                    result = result.dimmedAsBackdrop(
                        foreground: palette.foregroundTertiary, background: palette.overlayBackground)
                }
                let placed = layer.placed(maxWidth: maxWidth, maxHeight: maxHeight)
                // A surface hides what is behind it, so its blanks are painted
                // onto the surface colour BEFORE anything else happens to them —
                // see ``OverlayLayer/isOpaque``. Cells that already state a
                // background are untouched, so a dialog that paints itself
                // comes back byte-identical.
                //
                // Before the blend, not after, and that ordering is the whole
                // of what makes a fading toast still fade: `resolvingOpacity`
                // blends the layer against what is behind it, so painting first
                // gives it a background to fade FROM. Painting afterwards would
                // stamp the surface colour over the blend and freeze every
                // translucent layer fully opaque.
                var content =
                    layer.isOpaque
                    ? placed.content.paintedOver(
                        background: ANSIRenderer.backgroundCode(
                            for: palette.background.resolve(with: palette)))
                    : placed.content
                // And a surface is the backdrop of every fade INSIDE it (§96.2): a
                // label faded in a sheet fades into the sheet, whose surface stays
                // put. Only a centred layer — a sheet, an alert, a cover — because a
                // fade outside the presenter never reaches one (`fadingOverlays`),
                // so every region it carries is its own content's. An anchored layer
                // may carry the presenter's fade, which must take the surface with
                // it, in the same list as its content's, and cannot be told apart
                // here.
                if layer.isOpaque, layer.isScreenLevel {
                    content = content.resolvingOpacity(
                        onOpaqueFill: { nil }, surface: palette.background, palette: palette)
                }
                result = result.compositedResolvingOpacity(
                    with: content, at: (x: placed.x, y: placed.y), palette: palette)
            }
            // What this layer's content carried, lifted by the composite: into
            // the queue, not the next pass.
            for lifted in result.overlays {
                queue.append((order: nextOrder, layer: lifted))
                nextOrder += 1
            }
            result.overlays = []
        }
        return result
    }
}
