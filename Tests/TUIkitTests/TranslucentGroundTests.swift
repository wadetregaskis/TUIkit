//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TranslucentGroundTests.swift
//
//  A palette whose GROUND is translucent: the page, the app header and the status
//  bar have nothing inside the app behind them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// Every ground translucent, every paint opaque — so a failure here is about the
/// grounds and nothing else.
///
/// Stated in full rather than leaning on `Palette`'s defaults, which collapse the
/// header and bar onto `background`: each root is asserted on its own.
private struct TranslucentGrounds: Palette {
    let id = "translucent-grounds"
    let name = "Translucent grounds"
    let background = Color.rgb(10, 10, 20).opacity(0.5)
    let statusBarBackground = Color.rgb(20, 10, 10).opacity(0.5)
    let appHeaderBackground = Color.rgb(10, 20, 10).opacity(0.5)
    let overlayBackground = Color.rgb(30, 30, 30).opacity(0.5)
    let foreground = Color.rgb(230, 230, 240)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// The Theme page's colour pickers offer an `A` channel on every role, the three
/// grounds included, and moving it on `background` crashed the app on the next
/// frame. The emitter asserts every colour it spells is opaque, and a root ground
/// reached it from `RenderBackgroundCodes` on every frame — before any view drew —
/// as well as from the root's `resolvingOpacity(surface:)` and from the controls that
/// paint the ground directly.
@MainActor
@Suite("A translucent ground")
struct TranslucentGroundTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = TranslucentGrounds()
        environment.focusManager = FocusManager()
        return environment
    }

    /// The crash as reported: the root spells its three grounds before anything else
    /// is drawn, on every frame.
    @Test("The root's background codes are spelled from a translucent ground")
    func rootBackgroundCodes() {
        let codes = RenderBackgroundCodes(palette: environment().palette)
        #expect(codes.content == ANSIRenderer.backgroundCode(for: .rgb(10, 10, 20)))
        #expect(codes.appHeader == ANSIRenderer.backgroundCode(for: .rgb(10, 20, 10)))
        #expect(codes.statusBar == ANSIRenderer.backgroundCode(for: .rgb(20, 10, 10)))
    }

    /// A fade at the root resolves against the ground as its surface.
    @Test("A faded view resolves against a translucent ground")
    func fadeResolvesAgainstTheGround() {
        let palette = environment().palette
        var buffer = FrameBuffer(lines: [ANSIRenderer.colorize("hi", foreground: .ansi(.red))])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.5)
        ]
        let resolved = buffer.resolvingOpacity(surface: palette.background, palette: palette)
        #expect(resolved.lines.first?.stripped == "hi")
    }

    /// A control that paints the ground itself, rather than through the root.
    @Test("A toggle draws under a translucent ground")
    func toggleDraws() {
        let context = RenderContext(
            availableWidth: 20, availableHeight: 1, environment: environment(),
            tuiContext: TUIContext())
        let buffer = renderToBuffer(Toggle("on", isOn: .constant(true)), context: context)
        #expect(buffer.lines.first?.stripped.contains("on") == true)
    }

    /// The overlay wash is NOT a root: it has the page behind it, and §68.5 claims its
    /// field and resolves it against that page. Spending it here would freeze every
    /// translucent wash opaque.
    @Test("The overlay wash keeps its alpha")
    func overlayWashKeepsItsAlpha() {
        #expect(environment().palette.overlayBackground.alpha == Color.rgb(30, 30, 30).opacity(0.5).alpha)
    }

    /// An opaque palette is handed back as it was stated — no wrapper, so the hot
    /// read path pays nothing for a case that needs nothing.
    @Test("An opaque palette is stored as it was given")
    func opaquePaletteIsUntouched() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette(.amber)
        #expect(environment.palette is SystemPalette)
    }
}
