//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteDefaultTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitStyling

/// Minimal palette that only provides required properties,
/// so all defaults come from the protocol extension.
private struct MinimalPalette: Palette {
    let id = "minimal"
    let name = "Minimal"
    let background = Color.black
    let foreground = Color.white
    let accent = Color.cyan
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.brightBlack
}

@MainActor
@Suite("Palette Default Implementation Tests")
struct PaletteDefaultTests {

    @Test("Defaults derive foregroundSecondary from foreground")
    func defaultForegroundSecondary() {
        let palette = MinimalPalette()
        #expect(palette.foregroundSecondary == palette.foreground)
    }

    @Test("Defaults derive foregroundTertiary from foreground")
    func defaultForegroundTertiary() {
        let palette = MinimalPalette()
        #expect(palette.foregroundTertiary == palette.foreground)
    }

    /// Transitively, through `appHeaderBackground` — the status bar follows the
    /// header rather than the page, so a palette that states only a header tone
    /// gets both bars in it.
    @Test("Defaults derive statusBarBackground from background")
    func defaultStatusBarBackground() {
        let palette = MinimalPalette()
        #expect(palette.statusBarBackground == palette.background)
    }

    @Test("A stated header tone carries to the status bar")
    func statusBarFollowsTheHeader() {
        struct HeaderOnlyPalette: Palette {
            let id = "header-only"
            let name = "Header Only"
            let background = Color.rgb(0, 0, 0)
            let appHeaderBackground = Color.rgb(40, 40, 40)
            let foreground = Color.rgb(255, 255, 255)
            let accent = Color.rgb(0, 128, 255)
            let success = Color.rgb(0, 200, 0)
            let warning = Color.rgb(200, 160, 0)
            let error = Color.rgb(200, 0, 0)
            let info = Color.rgb(0, 160, 200)
            let border = Color.rgb(80, 80, 80)
        }
        let palette = HeaderOnlyPalette()
        #expect(palette.statusBarBackground == palette.appHeaderBackground)
    }

    @Test("Defaults derive appHeaderBackground from background")
    func defaultAppHeaderBackground() {
        let palette = MinimalPalette()
        #expect(palette.appHeaderBackground == palette.background)
    }

    @Test("Defaults derive overlayBackground from background")
    func defaultOverlayBackground() {
        let palette = MinimalPalette()
        #expect(palette.overlayBackground == palette.background)
    }
}
