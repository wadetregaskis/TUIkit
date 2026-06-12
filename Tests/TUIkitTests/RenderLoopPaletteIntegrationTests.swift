//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoopPaletteIntegrationTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

private struct DistinctBackgroundPalette: Palette {
    let id = "distinct-bg"
    let name = "Distinct BG"
    let background = Color.red
    let foreground = Color.white
    let accent = Color.cyan
    let success = Color.green
    let warning = Color.yellow
    let error = Color.magenta
    let info = Color.blue
    let border = Color.brightBlack
    let statusBarBackground = Color.green
    let appHeaderBackground = Color.blue
}

@MainActor
@Suite("Render Loop Palette Integration Tests")
struct RenderLoopPaletteIntegrationTests {

    @Test("RenderBackgroundCodes map each surface to the correct palette token")
    func renderBackgroundCodesUseSurfaceTokens() {
        let palette = DistinctBackgroundPalette()
        let codes = RenderBackgroundCodes(palette: palette)

        #expect(codes.content == ANSIRenderer.backgroundCode(for: palette.background))
        #expect(codes.appHeader == ANSIRenderer.backgroundCode(for: palette.appHeaderBackground))
        #expect(codes.statusBar == ANSIRenderer.backgroundCode(for: palette.statusBarBackground))
        #expect(codes.content != codes.statusBar)
        #expect(codes.content != codes.appHeader)
    }

    @Test("WindowGroup root palette override is discovered for built-in palettes")
    func discoversSystemPaletteOverride() {
        let scene = WindowGroup {
            Text("Hello")
                .palette(SystemPalette(.blue))
        }

        #expect(scene.rootPaletteOverride()?.id == "blue")
    }

    @Test("WindowGroup root palette override supports custom palettes")
    func discoversCustomPaletteOverride() {
        let palette = DistinctBackgroundPalette()
        let scene = WindowGroup {
            Text("Hello")
                .palette(palette)
        }

        #expect(scene.rootPaletteOverride()?.id == palette.id)
        #expect(scene.rootPaletteOverride()?.statusBarBackground == palette.statusBarBackground)
    }

    @Test("WindowGroup root palette override prefers the outermost palette")
    func outermostPaletteWins() {
        let scene = WindowGroup {
            VStack {
                Text("Nested")
                    .palette(SystemPalette(.blue))
            }
            .palette(SystemPalette(.amber))
        }

        #expect(scene.rootPaletteOverride()?.id == "amber")
    }

    @Test("WindowGroup without root palette override returns nil")
    func noRootOverrideReturnsNil() {
        let scene = WindowGroup {
            VStack {
                Text("Nested")
                    .palette(SystemPalette(.blue))
            }
        }

        #expect(scene.rootPaletteOverride() == nil)
    }

    // MARK: - Scene-level `.palette(_:)`

    // Regression coverage for phranck/TUIkit issue #2: `.palette(_:)` could only
    // be applied to a View, so the documented `WindowGroup { … }.palette(…)`
    // form (theming at the scene level) did not compile.

    /// The palette override of a scene, as `RenderLoop` discovers it.
    private func sceneOverride(_ scene: some Scene) -> (any Palette)? {
        (scene as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }

    /// The mouse support of a scene, as `RenderLoop` discovers it.
    private func sceneMouseSupport(_ scene: some Scene) -> MouseSupport? {
        (scene as? any MouseSupportProvidingScene)?.resolvedMouseSupport()
    }

    @Test(".palette applies to a WindowGroup (scene level) and is discovered")
    func scenePaletteOnWindowGroup() {
        let scene = WindowGroup {
            Text("Hello")
        }
        .palette(SystemPalette(.green))

        #expect(sceneOverride(scene)?.id == "green")
    }

    @Test("scene-level .palette supports custom palettes")
    func sceneCustomPalette() {
        let palette = DistinctBackgroundPalette()
        let scene = WindowGroup { Text("Hello") }.palette(palette)

        #expect(sceneOverride(scene)?.id == palette.id)
        #expect(sceneOverride(scene)?.statusBarBackground == palette.statusBarBackground)
    }

    @Test("a view-level palette inside the WindowGroup wins over the scene palette")
    func innerViewPaletteWins() {
        let scene = WindowGroup {
            Text("Hello")
                .palette(SystemPalette(.blue))
        }
        .palette(SystemPalette(.green))

        #expect(sceneOverride(scene)?.id == "blue")
    }

    @Test("chained scene .palette resolves to the innermost")
    func chainedScenePalette() {
        let scene = WindowGroup { Text("Hello") }
            .palette(SystemPalette(.green))
            .palette(SystemPalette(.amber))

        #expect(sceneOverride(scene)?.id == "green")
    }

    @Test(".palette composes with .mouseSupport in either order")
    func paletteComposesWithMouseSupport() {
        let paletteThenMouse = WindowGroup { Text("Hello") }
            .palette(SystemPalette(.green))
            .mouseSupport(.full)
        #expect(sceneOverride(paletteThenMouse)?.id == "green")
        #expect(sceneMouseSupport(paletteThenMouse) == .full)

        let mouseThenPalette = WindowGroup { Text("Hello") }
            .mouseSupport(.full)
            .palette(SystemPalette(.green))
        #expect(sceneOverride(mouseThenPalette)?.id == "green")
        #expect(sceneMouseSupport(mouseThenPalette) == .full)
    }
}
