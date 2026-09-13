//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageMonoColours.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Mono's two colours

/// The ink and paper a ``ASCIIColorMode/mono`` picture is drawn in, derived in
/// ONE place for both of `_ImageCore`'s renderers.
///
/// The glyph path states the pair around the converter's lines after the render
/// cache (`inked`, with the pair's alpha claimed beside it by `inkClaims`). The
/// pixel path bakes it into the picture (`recoloured`), and so into the store's
/// signature. Derived twice, the two could disagree, and which renderer a
/// terminal happens to get would decide what colour the picture is.
struct ImageMonoColours {
    /// What the picture's lit pixels are drawn in.
    let ink: Color
    /// What the rest of the picture is drawn in.
    let paper: Color

    /// `ASCIIConverter.recoloured`'s own defaults: what mono means with no
    /// colours in the conversation.
    static let defaultInk = RGBA(r: 255, g: 255, b: 255)
    static let defaultPaper = RGBA(r: 0, g: 0, b: 0)

    /// The pair for a picture drawn in `colorMode`, or `nil` for every mode but
    /// ``ASCIIColorMode/mono``, which is the only one that has no colours of its
    /// own to draw in.
    ///
    /// The test is on the REQUESTED mode, and it is the test `recoloured` makes
    /// before it paints the pair. A different test here (the depth-capped mode, a
    /// resolved palette) would let the signature carry a pair the pixels ignore.
    init?(for colorMode: ASCIIColorMode, in environment: EnvironmentValues) {
        guard colorMode == .mono else { return nil }
        let palette = environment.palette
        ink = palette.foreground
        paper = palette.background
    }

    /// Whether neither colour carries alpha, so the glyph path owes no claim.
    var isOpaque: Bool { ink.isOpaque && paper.isOpaque }

    /// The pair as pixels, for the pixel path: the defaults for every mode but
    /// `.mono`, so a picture in any other mode keeps one signature whatever the
    /// pair would have been.
    static func pixels(
        for colorMode: ASCIIColorMode, in environment: EnvironmentValues
    ) -> (ink: RGBA, paper: RGBA) {
        guard let colours = Self(for: colorMode, in: environment) else {
            return (defaultInk, defaultPaper)
        }
        let palette = environment.palette
        return (
            rgb(colours.ink, in: palette) ?? defaultInk,
            rgb(colours.paper, in: palette) ?? defaultPaper
        )
    }

    /// A colour as pixels, or `nil` for a semantic colour that has no RGB even
    /// after resolution.
    private static func rgb(_ color: Color, in palette: any Palette) -> RGBA? {
        // Alpha is not carried, for the reason `ASCIIPalette.init` states: this is
        // a colour being handed to the image pipeline as a MATCHING candidate or a
        // recolouring target, and transparency is not an axis of either. An
        // image's own transparency comes from its alpha channel instead.
        guard let components = color.resolve(with: palette).rgbComponents else { return nil }
        return RGBA(r: components.red, g: components.green, b: components.blue)
    }
}
