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

        return renderToBuffer(_ImageCore(source: .file("unused")), context: context).lines
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
}
