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
    /// - **A named colour is xterm's default RGB, not the profile's.** The
    ///   glyph path emits `.ansi16` (and any `.standard`/`.bright` palette
    ///   entry) as SGR 30–37 / 90–97, which the terminal paints from the
    ///   user's profile; a pixel cannot carry a name, and there is no query
    ///   for what a profile paints, so here `.red` is (205, 0, 0) whatever
    ///   the terminal thinks red is. One setting, two pictures on a
    ///   Solarized profile — and not something this path can fix.
    ///
    /// ## Mono has to be given its two colours
    ///
    /// ``ASCIIColorMode/mono`` emits no colour at all — that is the point of
    /// it — and the character renderer relies on that: its cells take whatever
    /// the page is already painted in, and `_ImageCore.inked(_:mode:palette:)`
    /// states the theme's ink and paper *after* the render cache, so a theme
    /// change re-colours a cached conversion for free.
    ///
    /// Pixels have no such inheritance. A pixel is a colour or it is nothing,
    /// so mono here means "these two colours", and they must be named. The
    /// defaults are literal black and white, which is what mono means with no
    /// theme in the conversation; ``Image`` passes the palette's foreground
    /// and background, which is what `inked` puts on the character rendering
    /// of the same picture.
    ///
    /// - Parameters:
    ///   - image: The decoded picture.
    ///   - width: Target width in pixels.
    ///   - height: Target height in pixels.
    ///   - monoInk: What ``ASCIIColorMode/mono`` paints its subject in.
    ///   - monoPaper: …and what it paints the rest in.
    /// - Returns: The recoloured picture, or an empty image for a
    ///   non-positive size.
    public func recoloured(
        _ image: RGBAImage, width: Int, height: Int,
        monoInk: RGBA = RGBA(r: 255, g: 255, b: 255),
        monoPaper: RGBA = RGBA(r: 0, g: 0, b: 0)
    ) -> RGBAImage {
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

        // One table, built once, for the modes that would otherwise search a
        // palette per pixel — see `ASCIIPalette.quantisationTable()`. `nil`
        // for every other mode, and for a palette too large to index with a
        // byte, in which case the exact search runs as before.
        let table = colorMode.searchedPalette?.quantisationTable()

        if dithering == .floydSteinberg {
            scaled = applyFloydSteinbergDithering(
                scaled, mode: colorMode, monoThreshold: monoThreshold, table: table)
        } else {
            // Without dithering the quantisation still has to happen: the glyph
            // path quantises when it emits each cell's SGR, and there is no SGR
            // here — the pixels ARE the output.
            //
            // The mode is switched on ONCE and captured, rather than switched
            // on per pixel. Per pixel it was an enum dispatch, a static
            // property access with its one-time-initialisation check, and a
            // retain of the palette's storage — a million times, for an answer
            // that could not change between pixels.
            let mode = colorMode
            let threshold = monoThreshold
            scaled.mapPixels { quantizePixel($0, mode: mode, monoThreshold: threshold, table: table) }
        }

        // Mono's two values become mono's two COLOURS. Done after the
        // quantisation rather than inside it so the dither, when there is one,
        // diffuses its error in the black-and-white space it was designed in:
        // what a mono dither produces is a PATTERN, and the pattern is the same
        // whichever two colours it is finally drawn in.
        if colorMode == .mono, monoInk != RGBA(r: 255, g: 255, b: 255)
            || monoPaper != RGBA(r: 0, g: 0, b: 0)
        {
            scaled.mapPixels { pixel in
                var painted = pixel.r == 0 ? monoPaper : monoInk
                painted.a = pixel.a
                return painted
            }
        }
        return scaled
    }
}
