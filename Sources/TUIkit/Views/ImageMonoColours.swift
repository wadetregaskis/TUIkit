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
///
/// ## Where the colours come from
///
/// A mono picture is inked like any other basic view: the ink is the
/// environment's `foregroundStyle`, the paper its `backgroundStyle`, and each
/// falls back to the palette's colour where nothing is stated (the paper by
/// `BackgroundStyle`'s own rule). Two deliberate differences from `Text`:
///
/// - **A gradient is its representative colour.** One pair inks the whole
///   picture. A ramp across a picture is a tone curve, which is
///   `imageToneCurve`'s job.
/// - **The style cascade is not consulted.** `Text` asks `.textStyle`'s entries
///   before `foregroundStyle`, and an image is not text.
///
/// Both colours are resolved here, against the palette: a style stated straight
/// into the environment arrives unresolved, and a semantic colour that reaches
/// the emitter traps. Their alpha is KEPT. The glyph path spells the pair opaque
/// and claims the alpha; the pixel path drops it.
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
        ink = (environment.foregroundStyle?.representative ?? palette.foreground)
            .resolve(with: palette)
        paper = BackgroundStyle().paint(in: environment).representative
            .resolve(with: palette)
    }

    /// Whether neither colour carries alpha, so the glyph path owes no claim.
    var isOpaque: Bool { ink.isOpaque && paper.isOpaque }

    /// The pair as pixels, for the pixel path: the defaults for every mode but
    /// `.mono`, so a picture in any other mode keeps one signature whatever the
    /// pair would have been.
    ///
    /// `nil` for a `.mono` pair with a colour that has no RGB: `Color.default`, or
    /// the terminal's own colours before it has reported them. A pixel cannot hold
    /// such a colour, so the picture is drawn in glyphs, which can spell it. It used
    /// to be baked as white ink or black paper.
    ///
    /// The ink is the one place the two paths part: under a breathing label's
    /// own ink the picture takes the ink the breath holds instead. See
    /// ``PictureInkHold``.
    static func pixels(
        for colorMode: ASCIIColorMode, in environment: EnvironmentValues
    ) -> (ink: RGBA, paper: RGBA)? {
        guard let colours = Self(for: colorMode, in: environment) else {
            return (defaultInk, defaultPaper)
        }
        guard var ink = rgb(colours.ink), let paper = rgb(colours.paper) else { return nil }
        if let hold = environment.pictureInkHold {
            let palette = environment.palette
            // Compared as the pixels they would bake, which is what decides the
            // picture: the ink in force is the breath's own unless something
            // between the label and the picture stated a different one.
            if rgb(hold.breath.resolve(with: palette)) == ink {
                guard let held = rgb(hold.held.resolve(with: palette)) else { return nil }
                ink = held
            }
        }
        return (ink, paper)
    }

    /// A resolved colour as pixels, or `nil` for a colour with no RGB.
    private static func rgb(_ color: Color) -> RGBA? {
        // Alpha is not carried, for the reason `ASCIIPalette.init` states: this is
        // a colour being handed to the image pipeline as a MATCHING candidate or a
        // recolouring target, and transparency is not an axis of either. An
        // image's own transparency comes from its alpha channel instead.
        guard let components = color.rgbComponents else { return nil }
        return RGBA(r: components.red, g: components.green, b: components.blue)
    }
}

// MARK: - A breathing label's pictures

/// The one ink a picture keeps while the label it sits in breathes.
///
/// A breathing label (`BreathingLabel.draw(ends:cycle:indicating:isMeasuring:render:)`)
/// is rendered once per frame of its breath, each time under that frame's
/// `.foregroundStyle`, and the run loop replays the rows. Glyphs breathe that
/// way. A picture cannot: its pixels carry the ink, so each frame's render is a
/// different picture, while the rows a run replays name ONE image id. Followed,
/// the store sent every frame's picture on every pass that re-rendered the label,
/// and the terminal kept whichever came last.
///
/// So on the pixel path a picture holds ``held`` for the whole breath. The breath
/// hands it the bright end, which is the colour the label rests in without the
/// focus and the colour a focus draws under `.selectionIndicatorStyle(.none)`, so
/// the breath starting or stopping sends nothing either. Nor does the window
/// losing the terminal's focus: the label's glyphs then hold still half-way
/// between the ends (`SelectionEmphasis.held(_:)`), and the picture stays at the
/// bright end rather than being re-sent in that shade.
///
/// The hold applies only while the ink in force is the breath's own ``breath``
/// colour, compared in the 8-bit RGB the picture would bake. A picture that
/// states its own ink inside the label, or sits under a control that states one,
/// keeps that ink. The comparison cannot tell a stated ink that equals the
/// current frame's colour exactly from the breath's: that picture takes ``held``
/// in that one frame's render and its own ink in the others, and re-sends
/// between them.
struct PictureInkHold: Equatable, Sendable {
    /// The ink this render of the label breathes in.
    let breath: Color
    /// The ink a picture keeps instead.
    let held: Color
}

private struct PictureInkHoldKey: EnvironmentKey {
    static let defaultValue: PictureInkHold? = nil
}

extension EnvironmentValues {
    /// The hold a breathing label publishes to the pictures in it, or `nil`
    /// outside a breath. See ``PictureInkHold``.
    var pictureInkHold: PictureInkHold? {
        get { self[PictureInkHoldKey.self] }
        set { self[PictureInkHoldKey.self] = newValue }
    }
}

extension View {
    /// This view in one frame of a breath: `.foregroundStyle(breath)`, with any
    /// picture inside keeping `held` instead. Both halves in one call, so a
    /// breath cannot publish one without the other. See ``PictureInkHold``.
    func breathingForegroundStyle(_ breath: Color, holdingPicturesAt held: Color) -> some View {
        foregroundStyle(breath)
            .environment(\.pictureInkHold, PictureInkHold(breath: breath, held: held))
    }
}
