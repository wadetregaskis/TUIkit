//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+Recolouring.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The picture, as this converter would colour it

extension ASCIIConverter {

    /// `image` resampled to `width` × `height` pixels and put through every
    /// stage of this converter that is about the PICTURE rather than about
    /// choosing a character for it.
    ///
    /// ## Why this exists
    ///
    /// ``convert(_:width:height:)`` does two separable things: it decides what
    /// the picture looks like — recolour it, lift its local contrast, quantise
    /// it to a palette, diffuse the error of that quantisation — and then it
    /// chooses a glyph per cell to approximate the result. A renderer that
    /// hands real pixels to the terminal wants the first half and none of the
    /// second, and it should get *the same* first half, or the two renderings
    /// of one picture would disagree about what the picture is.
    ///
    /// So the stages live here and both callers use them. The settings that
    /// have no meaning without glyphs — the charset, its size, shape matching,
    /// edge line tracing, supersampling — are simply not consulted.
    ///
    /// ## The two deliberate differences from the glyph path
    ///
    /// - **The colour mode is honoured as asked, not capped by
    ///   ``TUIkitStyling/ColorDepth``.** That ladder exists because SGR cannot
    ///   express more than the terminal has; a transmitted image is not SGR,
    ///   so a 256-colour terminal that draws images draws them in full colour.
    ///   Asking for ``ASCIIColorMode/ansi256`` still gets 256 — it is a look,
    ///   and looks are honoured.
    /// - **Local contrast is measured in PIXELS, not in cells.** The glyph
    ///   path uses a radius of one cell because a cell is its resolution and a
    ///   finer lift would average straight back out before a character was
    ///   chosen. Here the pixels survive, so the radius is the conventional
    ///   one for an unsharp mask.
    ///
    /// - Parameters:
    ///   - image: The decoded picture.
    ///   - width: Target width in pixels.
    ///   - height: Target height in pixels.
    /// - Returns: The recoloured picture, or an empty image for a
    ///   non-positive size.
    public func recoloured(_ image: RGBAImage, width: Int, height: Int) -> RGBAImage {
        guard width > 0, height > 0, image.width > 0, image.height > 0 else {
            return RGBAImage(width: 0, height: 0, pixels: [])
        }

        var scaled = image.scaledBilinear(to: width, height)

        // Recolouring first, before anything measures or quantises — the same
        // order, and the same reason, as `convert(_:width:height:)`: an
        // inversion moves where the ink/background split falls, so a threshold
        // taken from the original would be taken from tones that no longer
        // exist.
        if let toneCurve, !toneCurve.isIdentity {
            scaled.mapPixels(toneCurve.apply(to:))
        }

        // …and the local lift after it, for the same reason in the other
        // direction: a curve says what a TONE becomes, and this says how far a
        // pixel stands from its neighbours, so sharpening first would let the
        // curve flatten some of what it separated.
        if edgeContrast > 0 {
            scaled = scaled.sharpened(amount: edgeContrast)
        }

        // The split between ink and background, measured from THIS picture —
        // and before any dithering, which quantises against it.
        let monoThreshold = Self.monoInkThreshold(for: scaled)

        guard colorMode != .trueColor else { return scaled }

        if dithering == .floydSteinberg {
            return applyFloydSteinbergDithering(
                scaled, mode: colorMode, monoThreshold: monoThreshold)
        }

        // Without dithering the quantisation still has to happen: the glyph
        // path quantises when it emits each cell's SGR, and there is no SGR
        // here — the pixels ARE the output.
        scaled.mapPixels { quantizePixel($0, mode: colorMode, monoThreshold: monoThreshold) }
        return scaled
    }
}
