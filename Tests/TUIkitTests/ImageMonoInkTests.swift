//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageMonoInkTests.swift
//
//  What `.mono` draws with inside an app that paints its own page.
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
@Suite("Mono images use the theme's ink")
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

    /// Renders a loaded image at `mode`, and returns the drawn lines.
    private func lines(mode: ASCIIColorMode, palette: any Palette) -> [String] {
        buffer(mode: mode, palette: palette).lines
    }

    /// The same render, whole: the claims matter as much as the bytes.
    private func buffer(mode: ASCIIColorMode, palette: any Palette) -> FrameBuffer {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        environment.imageColorMode = mode
        var context = RenderContext(
            availableWidth: 24, availableHeight: 8, environment: environment, tuiContext: tui)
        // Reads the phase, runs no lifecycle — see the file note.
        context.isMeasuring = true

        let box: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: .loading)
        box.value = .success(ramp(width: 48, height: 32))

        return renderToBuffer(_ImageCore(source: .file("unused")), context: context)
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

        // And the claim, on every line that drew: both channels at the palette's
        // own alpha, which is the half that makes the picture follow its page.
        let claims = drawn.opacityRegions.filter { $0.offsetY == 0 }
        let claim = try #require(
            claims.first { $0.inkOpacity < 1 || $0.fieldOpacity < 1 },
            "no claim for the theme's colours: \(drawn.opacityRegions)")
        #expect(claim.inkOpacity < 1)
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
}
