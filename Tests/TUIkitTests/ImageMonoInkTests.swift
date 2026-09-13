//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageMonoInkTests.swift
//
//  What `.mono` draws with inside an app that paints its own page: the view's
//  `.foregroundStyle` on its `.backgroundStyle`, and the theme's two colours
//  where neither is stated.
//
//  Reaching the LOADED phase without a load: the phase lives in `StateStorage`
//  at the view's identity, and a measure pass reads it without touching the
//  lifecycle ("what's measured is what's drawn"). So seeding the box and
//  rendering with `isMeasuring` set is enough — no file, no network, no async.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage
@testable import TUIkitStyling

@MainActor
@Suite("Mono images use the view's styles, and the theme's ink by default")
struct ImageMonoInkTests {

    /// A gradient, so the conversion has something to threshold.
    private func ramp(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<height {
            for x in 0..<width {
                let level = UInt8((x * 255) / max(1, width - 1))
                pixels.append(RGBA(r: level, g: level, b: level))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Nothing of the picture on the left, white on the right: a transparent surround
    /// beside a subject, laid out so that every renderer sees both at any size it draws.
    private func halfTransparent(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<height {
            for x in 0..<width {
                pixels.append(
                    x < width / 2 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: 255, g: 255, b: 255))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Renders a loaded image at `mode`, and returns the drawn lines.
    private func lines(mode: ASCIIColorMode, palette: any Palette) -> [String] {
        buffer(mode: mode, palette: palette).lines
    }

    /// The same render, whole: the claims matter as much as the bytes.
    ///
    /// `configure` runs after the palette is set, so a test can state styles beside it.
    private func buffer(
        mode: ASCIIColorMode, palette: any Palette, image: RGBAImage? = nil,
        characterSet: ASCIICharacterSet = .blocks(.fine), shapeAware: Bool = false,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> FrameBuffer {
        render(
            _ImageCore(source: .file("unused")), mode: mode, palette: palette, image: image,
            characterSet: characterSet, shapeAware: shapeAware, configure: configure)
    }

    /// Renders `view` — an image core, or one wrapped in modifiers that render it at
    /// the SAME identity, which is where the seeded phase is found.
    private func render<V: View>(
        _ view: V,
        mode: ASCIIColorMode, palette: any Palette, image: RGBAImage? = nil,
        characterSet: ASCIICharacterSet = .blocks(.fine), shapeAware: Bool = false,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> FrameBuffer {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        environment.imageColorMode = mode
        environment.imageCharacterSet = characterSet
        environment.imageShapeAware = shapeAware
        configure(&environment)
        var context = RenderContext(
            availableWidth: 24, availableHeight: 8, environment: environment, tuiContext: tui)
        // Reads the phase, runs no lifecycle — see the file note.
        context.isMeasuring = true

        let box: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: .loading)
        box.value = .success(image ?? ramp(width: 48, height: 32))

        return renderToBuffer(view, context: context)
    }

    /// The first line that states a colour.
    private func painted(_ drawn: FrameBuffer) throws -> String {
        try #require(drawn.lines.first { $0.contains("\u{1B}[") }, "the image drew something")
    }

    private func foreground(_ colour: Color) -> String {
        colour.foregroundCodes().joined(separator: ";")
    }

    private func background(_ colour: Color) -> String {
        colour.backgroundCodes().joined(separator: ";")
    }

    /// The reported case: under the default Green theme a mono image was
    /// entirely black.
    ///
    /// `.mono` emits no colour, which is what makes it work on a terminal that
    /// has none — but inside an app that has already painted its page, "no
    /// colour" means the TERMINAL's defaults over the app's background. Where
    /// that default is dark and the theme is too, the image is ink on ink and
    /// simply does not appear.
    @Test("Mono ink is the palette's foreground, not the terminal's default")
    func monoDrawsInThePaletteForeground() throws {
        let palette = SystemPalette(.green)
        let drawn = lines(mode: .mono, palette: palette)
        let inked = try #require(
            drawn.first { $0.stripped.contains { !$0.isWhitespace } },
            "nothing was drawn: \(drawn.map(\.stripped))")
        let foreground = palette.foreground.foregroundCodes()
            .joined(separator: ";")
        #expect(!foreground.isEmpty, "the palette names a foreground")
        #expect(
            inked.contains(foreground),
            "no explicit ink (\(foreground)) on \(inked.debugDescription)")
    }

    /// The colour modes are unaffected: they emit their own per-cell colours,
    /// and wrapping them in the palette's would fight that.
    @Test("A colour mode is left to paint itself")
    func colourModesAreNotOverpainted() throws {
        let palette = SystemPalette(.green)
        let drawn = lines(mode: .trueColor, palette: palette)
        let painted = try #require(
            drawn.first { $0.contains("\u{1B}[") }, "the image drew something")
        let foreground = palette.foreground.foregroundCodes()
            .joined(separator: ";")
        #expect(
            !painted.hasPrefix("\u{1B}[\(foreground)"),
            "true colour was wrapped in the theme's ink")
    }

    /// A mono image is inked like any other basic view: in `.foregroundStyle`, on
    /// `.backgroundStyle`. `inked` read the palette whatever was stated, so the only
    /// way to draw mono in other colours was a different renderer.
    @Test("Mono draws in the view's foreground style on its background style")
    func monoDrawsInTheStyles() throws {
        let palette = SystemPalette(.green)
        let ink = Color.rgb(230, 40, 40)
        let paper = Color.rgb(10, 10, 60)
        let line = try painted(
            buffer(mode: .mono, palette: palette) {
                $0.foregroundStyle = .color(ink)
                $0.backgroundStyle = .color(paper)
            })
        #expect(line.contains(foreground(ink)), "\(line.debugDescription)")
        #expect(line.contains(background(paper)), "\(line.debugDescription)")
        #expect(
            !line.hasPrefix("\u{1B}[\(foreground(palette.foreground));"),
            "still the theme's ink: \(line.debugDescription)")
    }

    /// …through the public modifiers, not only the environment slots they fill.
    @Test("The foregroundStyle and backgroundStyle modifiers ink a mono image")
    func monoFollowsTheStyleModifiers() throws {
        let ink = Color.rgb(230, 40, 40)
        let paper = Color.rgb(10, 10, 60)
        let line = try painted(
            render(
                _ImageCore(source: .file("unused")).foregroundStyle(ink).backgroundStyle(paper),
                mode: .mono, palette: SystemPalette(.green)))
        #expect(line.contains(foreground(ink)), "\(line.debugDescription)")
        #expect(line.contains(background(paper)), "\(line.debugDescription)")
    }

    /// A style set straight into the environment is not resolved on the way in, as
    /// `.foregroundStyle(_:)` resolves it. A semantic colour reaching the emitter
    /// unresolved traps, so the derivation resolves against the palette itself.
    @Test("A semantic style resolves against the palette")
    func aSemanticStyleResolves() throws {
        let palette = SystemPalette(.green)
        let line = try painted(
            buffer(mode: .mono, palette: palette) { $0.foregroundStyle = .color(.palette.accent) })
        let accent = foreground(palette.accent.resolve(with: palette).opaqueSpelling)
        #expect(line.contains(accent), "\(line.debugDescription)")
    }

    /// A faded palette's two colours are CLAIMED, not handed to the emitter.
    ///
    /// `inked` is the post-cache pass that gives mono art the theme's ink and
    /// paper, and it passed both colours to `colorize` raw. `art.claims` — the only
    /// regions the buffer had — describe the SOURCE PICTURE's per-pixel
    /// transparency and are empty for an opaque picture; they say nothing about the
    /// palette colours this pass stamps. So a faded theme tripped the emitter's
    /// `isOpaque` assertion in debug and, in release, drew the picture at full
    /// strength over a page it was meant to follow. §68's bug in its seventh place
    /// — the one the live sweep could not reach, because no fixed poke sequence
    /// drives the Images page to Mono.
    @Test("A faded palette's mono ink is spelled opaque and claimed")
    func aFadedPaletteMonoInkIsClaimed() throws {
        let palette = FadedAll()
        let drawn = buffer(mode: .mono, palette: palette)

        // The bytes: the opaque spelling of both colours, and NOT the faded one.
        let opaqueInk = palette.foreground.opaqueSpelling.foregroundCodes()
            .joined(separator: ";")
        let opaquePaper = palette.background.opaqueSpelling.backgroundCodes()
            .joined(separator: ";")
        let painted = try #require(
            drawn.lines.first { $0.contains("\u{1B}[") }, "the image drew something")
        #expect(painted.contains(opaqueInk), "\(painted.debugDescription)")
        #expect(painted.contains(opaquePaper), "\(painted.debugDescription)")

        // And the claim, on every line that drew: the ink at the palette's own alpha,
        // which is the half that makes the picture follow its page.
        let claims = drawn.opacityRegions.filter { $0.offsetY == 0 }
        let claim = try #require(
            claims.first { $0.inkOpacity < 1 || $0.fieldOpacity < 1 },
            "no claim for the theme's colours: \(drawn.opacityRegions)")
        #expect(claim.inkOpacity < 1)
        // The paper is the page's background — a root ground, which reaches the view
        // already spent (§70.4) — so only the ink is still owed.
        #expect(claim.fieldOpacity == 1)
        #expect(claim.offsetX == 0)
        #expect(claim.width > 0)
    }

    /// A faded STYLE is the same pairing as a faded palette: the opaque spelling in the
    /// bytes, the alpha claimed beside them — and both halves owed, because a
    /// `.backgroundStyle` is not a root ground. Nothing spends its alpha on the way to
    /// the view the way the palette setter spends the page's (§70.4).
    @Test("A faded style is spelled opaque and claimed")
    func aFadedStyleIsClaimed() throws {
        let ink = Color.rgb(230, 40, 40).opacity(0.5)
        let paper = Color.rgb(10, 10, 60).opacity(0.5)
        let drawn = buffer(mode: .mono, palette: SystemPalette(.green)) {
            $0.foregroundStyle = .color(ink)
            $0.backgroundStyle = .color(paper)
        }
        let line = try painted(drawn)
        #expect(line.contains(foreground(ink.opaqueSpelling)), "\(line.debugDescription)")
        #expect(line.contains(background(paper.opaqueSpelling)), "\(line.debugDescription)")

        let claim = try #require(
            drawn.opacityRegions.first { $0.offsetY == 0 && $0.inkOpacity < 1 },
            "no claim for the styles: \(drawn.opacityRegions)")
        #expect(claim.fieldOpacity < 1)
        #expect(claim.offsetX == 0)
        #expect(claim.width > 0)
    }

    /// An opaque palette adds nothing — the guard, so the common case allocates no
    /// regions and the resolver keeps its `opacityRegions.isEmpty` fast path.
    @Test("An opaque palette claims nothing extra")
    func anOpaquePaletteClaimsNothing() {
        let drawn = buffer(mode: .mono, palette: SystemPalette(.green))
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity == 1 && $0.fieldOpacity == 1 })
    }

    /// What is claimed is what is DRAWN: an opaque style pair over a faded theme owes
    /// nothing, since none of the theme's colours reach the picture.
    @Test("An opaque style pair claims nothing, even over a faded palette")
    func anOpaqueStylePairClaimsNothing() throws {
        let ink = Color.rgb(230, 40, 40)
        let drawn = buffer(mode: .mono, palette: FadedAll()) {
            $0.foregroundStyle = .color(ink)
            $0.backgroundStyle = .color(.rgb(10, 10, 60))
        }
        #expect(drawn.opacityRegions.allSatisfy { $0.inkOpacity == 1 && $0.fieldOpacity == 1 })
        let line = try painted(drawn)
        #expect(line.contains(foreground(ink)), "\(line.debugDescription)")
    }

    /// The glyph path and the pixel path read one derivation, so a terminal that draws
    /// pictures cannot show a mono image in a different colour from one that draws
    /// glyphs.
    @Test("Both renderers take mono's colours from one derivation")
    func bothRenderersShareTheDerivation() throws {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette(.green)
        let palette = environment.palette

        let unstated = ImageMonoColours.pixels(for: .mono, in: environment)
        let theme = try #require(palette.foreground.resolve(with: palette).rgbComponents)
        #expect(unstated.ink == RGBA(r: theme.red, g: theme.green, b: theme.blue))

        environment.foregroundStyle = .color(.rgb(230, 40, 40))
        environment.backgroundStyle = .color(.rgb(10, 10, 60))
        let glyphs = try #require(ImageMonoColours(for: .mono, in: environment))
        #expect(glyphs.ink == .rgb(230, 40, 40))
        #expect(glyphs.paper == .rgb(10, 10, 60))
        let pixels = ImageMonoColours.pixels(for: .mono, in: environment)
        #expect(pixels.ink == RGBA(r: 230, g: 40, b: 40))
        #expect(pixels.paper == RGBA(r: 10, g: 10, b: 60))

        // Outside mono neither renderer has a pair to read.
        #expect(ImageMonoColours(for: .trueColor, in: environment) == nil)
        let other = ImageMonoColours.pixels(for: .trueColor, in: environment)
        #expect(other.ink == ImageMonoColours.defaultInk)
        #expect(other.paper == ImageMonoColours.defaultPaper)
    }

    /// A transparent surround keeps what is behind it, in every mono renderer.
    ///
    /// `inked` wrapped each line whole, so the paper covered the cells the converter had
    /// left blank for want of any picture: `.imageColorMode(.mono).background(.blue)` hid
    /// the blue completely round a logo that `.trueColor` let it show round. A mono line
    /// cannot say "absent" — that space and a dark pixel's are the same byte — so the
    /// converter says it in `ASCIIArt.uncovered`, and the paper stops there.
    ///
    /// Asserted on the BYTES, not on a claim, because the bytes are what a `.background`
    /// fill reads: it restates its colour after every reset, and a paper stated at column
    /// 0 is not a reset. Every renderer, because `inked` wraps them all.
    @Test(
        "A mono image states no colour over a transparent surround",
        arguments: [ASCIICharacterSet.blocks(.fine), .blocks(.solid), .blocks(.braille), .ascii],
        [false, true])
    func monoLeavesAnUncoveredSurroundUnpainted(
        characterSet: ASCIICharacterSet, shapeAware: Bool
    ) throws {
        let palette = SystemPalette(.green)
        let drawn = buffer(
            mode: .mono, palette: palette, image: halfTransparent(width: 16, height: 8),
            characterSet: characterSet, shapeAware: shapeAware)
        let top = try #require(drawn.lines.first, "the image drew nothing")
        // The left half is not there, so nothing is stated before it…
        #expect(!top.hasPrefix("\u{1B}["), "the surround was painted: \(top.debugDescription)")
        // …and the right half, which is, still wears the theme's paper.
        let paper = palette.background.opaqueSpelling.backgroundCodes().joined(separator: ";")
        #expect(top.contains(paper), "the picture lost its paper: \(top.debugDescription)")
    }

    /// A faded theme's alpha is claimed only where its colours were painted.
    ///
    /// A claim left over an uncovered cell is not merely wasted: that cell shows whatever
    /// is behind the picture, and the resolver would fade THAT toward the surface by the
    /// palette's alpha.
    @Test("A faded palette claims nothing over a transparent surround")
    func aFadedPaletteClaimsNothingOverTheSurround() throws {
        let drawn = buffer(
            mode: .mono, palette: FadedAll(), image: halfTransparent(width: 16, height: 8))
        let overSurround = drawn.opacityRegions.filter {
            $0.contains(column: 0, row: 0) && ($0.inkOpacity < 1 || $0.fieldOpacity < 1)
        }
        #expect(overSurround.isEmpty, "\(drawn.opacityRegions)")
        // A narrower claim, not none: the covered half still owes the palette's alpha —
        // the ink's, since the paper is a root ground and reaches the view spent (§70.4).
        let top = try #require(drawn.lines.first, "the image drew nothing")
        let lastColumn = top.strippedLength - 1
        let overPicture = drawn.opacityRegions.filter {
            $0.contains(column: lastColumn, row: 0) && $0.inkOpacity < 1
        }
        #expect(!overPicture.isEmpty, "\(drawn.opacityRegions)")
    }
}
