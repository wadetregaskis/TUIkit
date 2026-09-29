//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteModifierMemoTests.swift
//
//  `.palette(_:)` writes the environment through the generic
//  `EnvironmentModifier`, which notes the value it injects into the render
//  cache and, for a value it cannot compare, turns memoization off below it —
//  for good, since an incomparable slot never answers "changed" again. A
//  palette is compared by `ComparablePalette` everywhere else a palette is
//  kept (`.theme(_:)`, the render loop's snapshot): by value where it is
//  `Equatable`, through its derivation for the framework's own wrappers, and
//  by id otherwise, which `Palette`'s documentation asks a palette whose
//  colours change to honour. Through `.palette(_:)` a palette was noted raw, so
//  a custom palette — the shape the Theming guide writes, with no `Equatable` —
//  and the Terminal palette the environment grounds turned every memo below
//  them off. Found by the Stress `themes` session: with its whole page under
//  `.palette(_:)` of the palette it already had, 300 steps gave 668 value-memo
//  hits against 1,891 without.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// A palette as the Theming guide writes one: no `Equatable`, an id of its own.
private struct GuidePalette: Palette {
    let id: String
    var name: String { id }
    let background = Color.rgb(26, 26, 46)
    let foreground = Color.rgb(224, 224, 224)
    let accent = Color.rgb(0, 212, 255)
    let success = Color.rgb(0, 255, 136)
    let warning = Color.rgb(255, 204, 0)
    let error = Color.rgb(255, 68, 68)
    let info = Color.rgb(68, 136, 255)
    let border = Color.rgb(96, 96, 128)
}

/// A leaf that reads the palette it is drawn in and nothing else volatile.
private struct PaletteLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text).foregroundStyle(.palette.accent)
    }
}

@MainActor
@Suite("A memo below .palette(_:)", .serialized)
struct PaletteModifierMemoTests {
    /// A context with a fresh, test-local cache (see `ThemeStyleMemoTests`).
    private func context() -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.renderCache = RenderCache()
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: 24, availableHeight: 6, environment: environment,
            identity: ViewIdentity(path: "Root"))
    }

    /// One frame of the real loop's cache lifecycle.
    @discardableResult
    private func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }

    @Test(
        "A memo below .palette(_:) of a palette that is not Equatable is kept and served",
        arguments: ["guide", "terminal"])
    func memoUnderAnUnequatablePalette(_ which: String) {
        // The Terminal palette as a view reads it back from the environment,
        // which grounds it on the terminal's page: a wrapper, not Equatable.
        var environment = EnvironmentValues()
        environment.palette = LiveTerminalPalette()
        let palette: any Palette = which == "guide" ? GuidePalette(id: "guide") : environment.palette
        let context = context()
        let cache = context.environment.renderCache!
        let view = PaletteLeaf(text: "hi").equatable().palette(palette)
        frame(context, view)
        let before = cache.stats
        frame(context, view)
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "the memo below .palette(\(which)) was not served: \(delta)")
    }

    /// The other half, which comparing by the palette's id must not lose: a
    /// palette with another id is another palette.
    @Test("A memo below .palette(_:) is dropped when the palette becomes another")
    func memoDroppedWhenThePaletteChanges() {
        let context = context()
        let cache = context.environment.renderCache!
        let first = frame(context, PaletteLeaf(text: "hi").equatable().palette(GuidePalette(id: "one")))
        let before = cache.stats
        let second = frame(context, PaletteLeaf(text: "hi").equatable().palette(SystemPalette(.amber)))
        #expect(cache.stats.delta(since: before).hits == 0, "served the buffer drawn in the palette before")
        #expect(first.lines != second.lines, "precondition: the two palettes draw differently")
    }
}
