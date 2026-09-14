//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackRaster.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - A determinate track as pixels

/// A progress track — the lit run, the boundary, the unlit remainder — as a
/// picture, for a style whose cells are colour and nothing else.
///
/// `TrackRenderer.renderConfigured` draws a `.block` or `.blockFine` track as
/// full cells of `█` painted glyph-on-matching-background, a boundary cell
/// from an eighths ramp, and spaces on the unfilled colour. Every one of
/// those cells is a rectangle of one colour, so the whole track is a picture
/// waiting to be drawn as one: the same colours, at pixel resolution, with
/// the boundary landing on a PIXEL — sixteen steps a cell where the eighths
/// ramp had eight and `.block` had one — and a fill gradient sampled once a
/// pixel rather than once a cell. The look is the look the cells had; only
/// the resolution changes.
///
/// A style with a texture — a shade ramp, braille, a patterned unfill, a
/// head glyph — is not this: its glyphs are its look, and a picture cannot
/// carry a glyph. ``TrackConfiguration/isColourField`` is the line.
enum TrackRaster {

    /// The pixels for a `width`-cell, one-row track at `fraction`.
    ///
    /// The picture is ``GradientRaster/resolution(columns:rows:cellPixels:)``'s
    /// size for the box, so its proportions are the box's and the terminal's
    /// fit is exact. Colours are what the cell renderer would have painted:
    /// the fill gradient (or the flat fill colour) across the span
    /// `fillScaling` names, and the unfilled colour or gradient over the rest
    /// across the span `emptyScaling` names — sampled through
    /// `Color.quantisedRamp` at truecolor exactly as
    /// `TrackRenderer.gradientColor` does, so the two renderings agree about
    /// every colour and share one ramp cache.
    ///
    /// - Returns: the picture, or `nil` for a box with no pixels.
    static func picture(
        fraction: Double, width: Int, config: TrackConfiguration,
        filledColor: Color, emptyColor: Color,
        fillScaling: TrackGradientScaling, emptyScaling: TrackGradientScaling,
        cellPixels: TerminalCellPixels
    ) -> GradientRaster.Picture? {
        guard let size = GradientRaster.resolution(columns: width, rows: 1, cellPixels: cellPixels)
        else { return nil }
        let fraction = min(1, max(0, fraction))
        // The boundary, on a pixel. Rounded like the cell renderer rounds its
        // steps, so 50% of an even width is exactly half.
        let lit = Int((fraction * Double(size.width)).rounded())
        let unlit = size.width - lit
        let empty = config.backgroundColor ?? emptyColor

        // The fill's ramp spans the bar or the lit part, as the cells' does;
        // `TrackRenderer` says why a scale-meaning ramp must span the bar.
        let fillSpan = fillScaling == .track ? size.width : lit
        let fillRamp = ramp(config.fillGradient, span: fillSpan, fallback: filledColor)
        // The unfilled ramp starts AT the boundary (the cells' rule for the
        // same reason), spanning the bar or the remainder.
        let emptySpan = emptyScaling == .track ? size.width : unlit
        let emptyRamp = ramp(config.backgroundGradient, span: emptySpan, fallback: empty)

        var bytes = [UInt8](repeating: 0, count: size.width * size.height * 3)
        var row = [UInt8](repeating: 0, count: size.width * 3)
        for x in 0..<size.width {
            let colour: (UInt8, UInt8, UInt8)
            if x < lit {
                colour = fillRamp[min(fillRamp.count - 1, x)]
            } else {
                let index = emptyScaling == .track ? x : x - lit
                colour = emptyRamp[min(emptyRamp.count - 1, max(0, index))]
            }
            row[x * 3] = colour.0
            row[x * 3 + 1] = colour.1
            row[x * 3 + 2] = colour.2
        }
        // Every row is the same row — which is what deflate is for.
        for y in 0..<size.height {
            bytes.replaceSubrange((y * row.count)..<((y + 1) * row.count), with: row)
        }
        return GradientRaster.Picture(bytes: bytes, width: size.width, height: size.height)
    }

    /// `span` colours of a ramp, or of the fallback where there is no ramp —
    /// through the same quantiser the cells use, so a ramp cached for one
    /// renderer serves the other.
    private static func ramp(_ gradient: Gradient?, span: Int, fallback: Color) -> [(UInt8, UInt8, UInt8)] {
        let flat = fallback.rgbComponents.map { ($0.red, $0.green, $0.blue) } ?? (0, 0, 0)
        guard let gradient, !gradient.stops.isEmpty, span > 1 else { return [flat] }
        let colours = Color.quantisedRamp(gradient, count: span, depth: .truecolor)
        guard !colours.isEmpty else { return [flat] }
        return colours.map { colour in
            colour.rgbComponents.map { ($0.red, $0.green, $0.blue) } ?? flat
        }
    }
}

extension TrackConfiguration {
    /// Whether every cell of this track is a rectangle of one colour — a `█`
    /// fill on a `.solid` background, whatever the leading edge — and so
    /// can be a picture without losing anything a person could see.
    ///
    /// The boundary ramp is not consulted: a picture puts the boundary on a
    /// pixel, which is finer than any ramp, so the ramp's job is done better
    /// rather than left undone. What disqualifies a track is a glyph that IS
    /// the look — a shade, a dot pattern, braille — and those live in the
    /// fill and the unfill.
    var isColourField: Bool {
        fill == "█" && background == .solid
    }
}
