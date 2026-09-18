//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteEditedInPlaceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Why these tests exist
//
// The render loop kept memoized subtrees across frames until an
// `EnvironmentSnapshot` differed, and the snapshot knew the palette only by its
// `id`. The Example's Theme page edits its palette IN PLACE — a
// `CustomizablePalette` that keeps its preset's id while its colours change — so
// an edit changed no field of the snapshot, the cache was kept, and every
// memoized row went on drawing the colours from before the edit. When these
// tests were written nothing else cleared it: the App's `@State` was never bound,
// so the write invalidated nothing. It is bound now (see AppStateBindingTests),
// but a palette can reach the scene from elsewhere, so the snapshot comparison
// has to stand on its own.

/// The Example's `CustomizablePalette` in miniature: every colour a stored
/// property, the id fixed while they are edited.
private struct EditablePalette: Palette, Hashable {
    var id = "editable"
    var name = "Editable"
    var background: Color = .rgb(0, 0, 0)
    var foreground: Color = .rgb(200, 200, 200)
    var accent: Color = .rgb(0, 200, 0)
    var success: Color = .rgb(0, 200, 0)
    var warning: Color = .rgb(200, 200, 0)
    var error: Color = .rgb(200, 0, 0)
    var info: Color = .rgb(0, 200, 200)
    var border: Color = .rgb(100, 100, 100)
}

/// The same shape, deliberately NOT `Equatable`: nothing can compare its
/// colours, so the framework knows it only by its id.
private struct IdentifiedOnlyPalette: Palette {
    var id = "identified"
    var name = "Identified"
    var background: Color = .rgb(0, 0, 0)
    var foreground: Color = .rgb(200, 200, 200)
    var accent: Color = .rgb(0, 200, 0)
    var success: Color = .rgb(0, 200, 0)
    var warning: Color = .rgb(200, 200, 0)
    var error: Color = .rgb(200, 0, 0)
    var info: Color = .rgb(0, 200, 200)
    var border: Color = .rgb(100, 100, 100)
}

/// The snapshot of an environment holding `palette`, through the same setter the
/// render loop uses — so a translucent ground arrives grounded, as it does live.
private func snapshot(_ palette: any Palette) -> EnvironmentSnapshot {
    var environment = EnvironmentValues()
    environment.palette = palette
    return EnvironmentSnapshot(from: environment)
}

@Suite("A palette edited in place")
struct PaletteEditedInPlaceSnapshotTests {
    @Test("An edit that keeps the id changes the snapshot")
    func editKeepingIDChangesSnapshot() {
        var palette = EditablePalette()
        let before = snapshot(palette)
        palette.accent = .rgb(200, 0, 0)
        #expect(before != snapshot(palette), "an in-place edit must clear the render cache")
    }

    @Test("An edit under a tint changes the snapshot, and so does a new tint")
    func editUnderTintChangesSnapshot() {
        var palette = EditablePalette()
        let before = snapshot(TintedPalette(base: palette, tint: .rgb(0, 0, 200)))
        #expect(before != snapshot(TintedPalette(base: palette, tint: .rgb(0, 200, 200))))
        palette.background = .rgb(40, 0, 0)
        #expect(before != snapshot(TintedPalette(base: palette, tint: .rgb(0, 0, 200))))
    }

    @Test("An edit to a palette with a translucent ground changes the snapshot")
    func editUnderGroundingChangesSnapshot() {
        // The Theme page's pickers carry an alpha channel, and a translucent ground
        // puts the palette into the environment wrapped in a `GroundedPalette`.
        var palette = EditablePalette()
        palette.background = Color.rgb(0, 0, 0).opacity(0.5)
        let before = snapshot(palette)
        palette.foreground = .rgb(255, 255, 0)
        #expect(before != snapshot(palette))
    }

    @Test("An equal palette rebuilt every frame keeps the snapshot equal")
    func rebuiltEqualPaletteKeepsSnapshot() {
        // The scene's `.theme(…)` builds its palette afresh on every frame — a new
        // `TintedPalette` whenever there is a tint. Answering "changed" for an equal
        // rebuild would clear the whole render cache on every frame. Each side is
        // built separately, so the comparison is between two rebuilds, not a value
        // and itself.
        let plainFrame = snapshot(EditablePalette())
        let plainNextFrame = snapshot(EditablePalette())
        #expect(plainFrame == plainNextFrame)

        let tintedFrame = snapshot(TintedPalette(base: EditablePalette(), tint: .rgb(0, 0, 200)))
        let tintedNextFrame = snapshot(TintedPalette(base: EditablePalette(), tint: .rgb(0, 0, 200)))
        #expect(tintedFrame == tintedNextFrame)

        var translucent = EditablePalette()
        translucent.background = Color.rgb(0, 0, 0).opacity(0.5)
        let groundedFrame = snapshot(translucent)
        let groundedNextFrame = snapshot(translucent)
        #expect(groundedFrame == groundedNextFrame)
    }

    @Test("A palette that is not Equatable is known by its id")
    func nonEquatablePaletteIsKnownByID() {
        var palette = IdentifiedOnlyPalette()
        let before = snapshot(palette)
        palette.accent = .rgb(200, 0, 0)
        #expect(before == snapshot(palette), "the documented contract: a new id, or Equatable")
        palette.id = "identified.2"
        #expect(before != snapshot(palette))
    }
}

// MARK: - The Example's shape, whole frames

/// Draws the accent it rendered under as text, so a buffer served from the memo
/// is visible as the OLD colour's name.
private struct AccentProbe: View, Equatable, Renderable {
    var body: Never { fatalError("AccentProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: Self.label(context.environment.palette.accent))
    }

    /// Short enough to fit the mock terminal's 80 columns: a `Color`'s own
    /// description does not, and a clipped label matches nothing.
    static func label(_ accent: Color) -> String {
        accent.rgbComponents.map { "accent \($0.red),\($0.green),\($0.blue)" } ?? "accent ?"
    }
}

/// How the Example applies its palette: app-level `@State`, handed to the scene's
/// `.theme(…)` with no tint (the Example's default), over a memoized subtree.
private struct EditedPaletteApp: App {
    @State private var palette = EditablePalette()

    init() {}

    var body: some Scene {
        WindowGroup {
            AccentProbe().equatable()
        }
        .theme(Theme(palette: palette))
    }

    /// A binding onto one colour of the palette — the Theme page's `colorBinding`,
    /// which is how the Example's colour pickers write.
    func colorBinding(_ keyPath: WritableKeyPath<EditablePalette, Color>) -> Binding<Color> {
        Binding(
            get: { palette[keyPath: keyPath] },
            set: { palette[keyPath: keyPath] = $0 }
        )
    }
}

@MainActor
@Suite("A palette edited in place, rendered")
struct PaletteEditedInPlaceFrameTests {
    private func frameText<A: App>(_ loop: RenderLoop<A>) -> String {
        (loop.replayable?.contentLines ?? []).map(\.stripped).joined(separator: "\n")
    }

    @Test("A memoized view redraws in the edited colour on the next frame")
    func memoizedViewFollowsEdit() {
        let app = EditedPaletteApp()
        let harness = RenderLoopHarness()
        let loop = harness.loop(app)

        loop.render()
        #expect(frameText(loop).contains(AccentProbe.label(.rgb(0, 200, 0))))

        app.colorBinding(\.accent).wrappedValue = .rgb(200, 0, 0)
        loop.render()
        #expect(
            frameText(loop).contains(AccentProbe.label(.rgb(200, 0, 0))),
            "the memoized probe kept the accent from before the edit")
    }
}

// MARK: - The palette an app writes, under a `.theme(…)`

@MainActor
@Suite("A palette that cannot be compared, under a theme", .serialized)
struct IncomparablePaletteThemeTests {
    /// A context with a fresh, test-local cache, and one frame of the loop's
    /// cache lifecycle around a walk — the same pair `RenderCacheContractTests`
    /// builds by hand, and for the same reason: these assert cache statistics,
    /// so nothing else may touch this cache. The frame boundary is load-bearing
    /// rather than ceremony — `noteAppliedEnvironment` answers every visit
    /// within one pass from its short circuit, so two renders without one
    /// between them are one pass and compare nothing.
    private func context() -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.renderCache = RenderCache()
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: 40, availableHeight: 4, environment: environment,
            identity: ViewIdentity(path: "Root"))
    }

    @discardableResult
    private func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }

    private func palette(_ id: String, accent: Color) -> IdentifiedOnlyPalette {
        var palette = IdentifiedOnlyPalette()
        palette.id = id
        palette.accent = accent
        return palette
    }

    /// `RenderCacheContractTests` asks this of a theme carrying a `SystemPalette`,
    /// which is `Hashable` — as every palette this package ships is. The palette
    /// an APP writes need not be: the shape ``ThemingGuide`` tells one to write
    /// conforms to `Palette` and nothing else, and `noteAppliedEnvironment`
    /// answers `.incomparable` for it. `ThemeModifier` matched only `.changed`,
    /// so that answer fell through ignored, the slot was deadened for good, and
    /// the memoized subtree below went on drawing the accent from the palette
    /// before.
    ///
    /// The control is what makes this the modifier's bug rather than the
    /// palette's: `.palette(_:)` is an ordinary `EnvironmentModifier`, which
    /// handles `.incomparable` by declining the memo below it, so the SAME two
    /// palettes through THAT door have always painted correctly.
    @Test("A theme carrying a palette that cannot be compared still repaints")
    func themeWithIncomparablePaletteIsNotServedStale() {
        let green = palette("green", accent: .rgb(0, 200, 0))
        let blue = palette("blue", accent: .rgb(0, 0, 200))

        let themed = context()
        frame(themed, AccentProbe().equatable().theme(Theme(palette: green)))
        let servedByTheme = frame(themed, AccentProbe().equatable().theme(Theme(palette: blue)))
        #expect(
            servedByTheme.lines.map(\.stripped) == [AccentProbe.label(blue.accent)],
            "the memo below .theme served the buffer painted in the old palette")

        let plain = context()
        frame(plain, AccentProbe().equatable().palette(green))
        let servedByPalette = frame(plain, AccentProbe().equatable().palette(blue))
        #expect(
            servedByPalette.lines.map(\.stripped) == [AccentProbe.label(blue.accent)],
            "control: .palette(_:) declines the memo for a palette it cannot compare")
    }

    /// The other direction, and the one a careless fix breaks: the SAME
    /// incomparable palette every frame must not clear the subtree every frame.
    /// `isSamePalette(as:)` answers that from the `id`, which is exactly what
    /// `Palette`'s documentation says such a palette is known by.
    @Test("An unchanged palette that cannot be compared does not defeat the memo")
    func unchangedIncomparablePaletteStillMemoizes() {
        let shared = context()
        func themed() -> some View {
            AccentProbe().equatable()
                .theme(Theme(palette: palette("green", accent: .rgb(0, 200, 0))))
        }
        frame(shared, themed())
        let before = shared.renderCache?.stats.subtreeClears ?? 0
        frame(shared, themed())
        #expect(
            shared.renderCache?.stats.subtreeClears == before,
            "an unchanged palette cleared the subtree anyway")
    }
}
