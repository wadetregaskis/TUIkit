//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoopAppearanceIntegrationTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Coverage for the scene-level `.appearance(_:)` override and the app-header
/// divider honouring the active appearance — the two halves that let a custom
/// border reach the out-of-tree app header and status bar (not just content).
@MainActor
@Suite("Render Loop Appearance Integration Tests")
struct RenderLoopAppearanceIntegrationTests {

    /// A star border so a custom appearance is unmistakable in rendered output.
    private static let starAppearance = Appearance(
        id: Appearance.ID(rawValue: "stars"),
        borderStyle: BorderStyle(
            topLeft: "*", topRight: "*", bottomLeft: "*", bottomRight: "*",
            horizontal: "*", vertical: "*"))

    /// The appearance override of a scene, as `RenderLoop` discovers it.
    private func sceneAppearance(_ scene: some Scene) -> Appearance? {
        (scene as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
    }

    /// The palette override of a scene, as `RenderLoop` discovers it.
    private func scenePalette(_ scene: some Scene) -> (any Palette)? {
        (scene as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }

    /// The mouse support of a scene, as `RenderLoop` discovers it.
    private func sceneMouseSupport(_ scene: some Scene) -> MouseSupport? {
        (scene as? any MouseSupportProvidingScene)?.resolvedMouseSupport()
    }

    // MARK: - Scene-level `.appearance(_:)` discovery

    @Test(".appearance applies to a WindowGroup (scene level) and is discovered")
    func sceneAppearanceOnWindowGroup() {
        let scene = WindowGroup { Text("Hello") }
            .appearance(Self.starAppearance)

        #expect(sceneAppearance(scene)?.id == "stars")
        #expect(sceneAppearance(scene)?.borderStyle.horizontal == "*")
    }

    @Test("a nil scene appearance defers to the appearance manager (no override)")
    func nilSceneAppearanceReturnsNil() {
        let scene = WindowGroup { Text("Hello") }
            .appearance(nil)

        #expect(sceneAppearance(scene) == nil)
    }

    @Test("a bare WindowGroup has no appearance override")
    func bareWindowGroupReturnsNil() {
        let scene = WindowGroup { Text("Hello") }

        #expect(sceneAppearance(scene) == nil)
    }

    @Test("chained scene .appearance resolves to the innermost")
    func chainedSceneAppearance() {
        let scene = WindowGroup { Text("Hello") }
            .appearance(Self.starAppearance)
            .appearance(Appearance(id: .line, borderStyle: .line))

        // Innermost (closest to the content) wins, mirroring `.palette(_:)`.
        #expect(sceneAppearance(scene)?.id == "stars")
    }

    @Test("an outer nil .appearance does not shadow an inner appearance")
    func outerNilDoesNotShadowInner() {
        let scene = WindowGroup { Text("Hello") }
            .appearance(Self.starAppearance)
            .appearance(nil)

        #expect(sceneAppearance(scene)?.id == "stars")
    }

    // MARK: - Composition with the other scene modifiers

    @Test(".appearance composes with .palette in either order")
    func appearanceComposesWithPalette() {
        let appearanceThenPalette = WindowGroup { Text("Hello") }
            .appearance(Self.starAppearance)
            .palette(SystemPalette(.green))
        #expect(sceneAppearance(appearanceThenPalette)?.id == "stars")
        #expect(scenePalette(appearanceThenPalette)?.id == "green")

        let paletteThenAppearance = WindowGroup { Text("Hello") }
            .palette(SystemPalette(.green))
            .appearance(Self.starAppearance)
        #expect(sceneAppearance(paletteThenAppearance)?.id == "stars")
        #expect(scenePalette(paletteThenAppearance)?.id == "green")
    }

    @Test(".appearance composes with .mouseSupport in either order")
    func appearanceComposesWithMouseSupport() {
        let appearanceThenMouse = WindowGroup { Text("Hello") }
            .appearance(Self.starAppearance)
            .mouseSupport(.full)
        #expect(sceneAppearance(appearanceThenMouse)?.id == "stars")
        #expect(sceneMouseSupport(appearanceThenMouse) == .full)

        let mouseThenAppearance = WindowGroup { Text("Hello") }
            .mouseSupport(.full)
            .appearance(Self.starAppearance)
        #expect(sceneAppearance(mouseThenAppearance)?.id == "stars")
        #expect(sceneMouseSupport(mouseThenAppearance) == .full)
    }

    // MARK: - App-header divider honours the appearance

    /// Renders the internal `AppHeader` with the given appearance and returns the
    /// divider line (the last line of the header buffer).
    private func headerDivider(appearance: Appearance) -> String {
        let content = FrameBuffer(lines: ["My App"])
        let header = AppHeader(contentBuffer: content)
        var environment = EnvironmentValues()
        environment.appearance = appearance
        let context = RenderContext(
            availableWidth: 12,
            availableHeight: content.height + 1,
            tuiContext: TUIContext()
        ).withEnvironment(environment)
        let buffer = renderToBuffer(header, context: context)
        return buffer.lines.last ?? ""
    }

    @Test("app-header divider uses the appearance's horizontal glyph")
    func appHeaderDividerUsesAppearanceGlyph() {
        let starDivider = headerDivider(appearance: Self.starAppearance)
        // Strip SGR colouring; the divider is `*` repeated to the width.
        #expect(starDivider.contains("*"))
        #expect(!starDivider.contains("─"))
    }

    @Test("app-header divider uses ─ for a line appearance")
    func appHeaderDividerLineAppearance() {
        let lineDivider = headerDivider(appearance: Appearance(id: .line, borderStyle: .line))
        #expect(lineDivider.contains("─"))
        #expect(!lineDivider.contains("*"))
    }
}
