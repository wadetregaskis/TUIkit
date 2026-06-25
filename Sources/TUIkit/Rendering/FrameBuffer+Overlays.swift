//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer+Overlays.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension FrameBuffer {
    /// Composites every accumulated ``overlays`` layer onto this buffer in
    /// z-order — ascending ``OverlayLevel`` (popover < alert < modal <
    /// notification), then ``OverlayLayer/zIndex`` — resolving each layer's
    /// placement against a `maxWidth` × `maxHeight` area.
    ///
    /// A layer that ``OverlayLayer/centered`` is placed in the centre of that
    /// area; otherwise it draws at its (clamped, flip-on-overflow) offset. A layer
    /// that ``OverlayLayer/dimsBackground`` first dims everything beneath it into a
    /// flat, inert backdrop (using `palette` for the colours) — so a screen-level
    /// modal reads as modal over the whole screen no matter where it was attached.
    ///
    /// Layers that a composited layer itself emits are drained in further passes,
    /// bounded by a small cap against a pathological re-emitting layer.
    ///
    /// This is exactly what `RenderLoop` runs at the screen root; it's public so
    /// tests can reproduce the composited result a headless `renderToBuffer`
    /// otherwise leaves pending in ``overlays``.
    public func compositingOverlays(
        maxWidth: Int, maxHeight: Int, palette: any Palette
    ) -> FrameBuffer {
        var result = self
        // A small pass cap guards against a pathological layer that somehow keeps
        // re-emitting itself; 16 levels of nesting is far beyond real use.
        var passesRemaining = 16
        while !result.overlays.isEmpty && passesRemaining > 0 {
            passesRemaining -= 1
            let layers = result.overlays
            result.overlays = []

            let ordered = layers.enumerated().sorted { lhs, rhs in
                if lhs.element.level != rhs.element.level {
                    return lhs.element.level < rhs.element.level
                }
                if lhs.element.zIndex != rhs.element.zIndex {
                    return lhs.element.zIndex < rhs.element.zIndex
                }
                return lhs.offset < rhs.offset
            }.map(\.element)

            for layer in ordered {
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
                result = result.composited(with: placed.content, at: (x: placed.x, y: placed.y))
            }
        }
        return result
    }
}
