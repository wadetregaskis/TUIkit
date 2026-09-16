//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorSchemeEnvironmentTests.swift
//
//  `EnvironmentValues.colorScheme`: the palette's own reading, and what happens
//  when a view pins it — through the same palette setter every write comes
//  through, so a pin survives a `.palette` written inside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// A palette that states nothing but a page (and the seven roles with no default).
private struct PagePalette: Palette, Hashable {
    let id = "page"
    let name = "Page"
    var background: Color
    let foreground = Color.rgb(200, 200, 200)
    let accent = Color.rgb(0, 200, 0)
    let success = Color.rgb(0, 200, 0)
    let warning = Color.rgb(200, 200, 0)
    let error = Color.rgb(200, 0, 0)
    let info = Color.rgb(0, 200, 200)
    let border = Color.rgb(100, 100, 100)
}

/// Draws the scheme in force where it renders, so a modifier stack can be asked
/// what the environment says without a sink to carry it out.
private struct SchemeProbe: View, Renderable {
    var body: Never { fatalError("SchemeProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(text: context.environment.colorScheme == .dark ? "dark" : "light")
    }
}

@MainActor
@Suite("The environment's colour scheme")
struct ColorSchemeEnvironmentTests {

    private static let darkPage = PagePalette(background: .rgb(10, 10, 10))
    private static let lightPage = PagePalette(background: .rgb(250, 250, 250))

    /// An environment holding `palette`, written through the setter every palette
    /// write comes through.
    private func environment(_ palette: any Palette) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = palette
        return environment
    }

    /// How many wrappers named `name` the stored palette holds, walking the chain
    /// of derivations. By NAME rather than by `is`: the count is the assertion, and
    /// a wrapper around a wrapper answers `is` exactly as one wrapper does.
    private func wrappers(named name: String, in palette: any Palette) -> Int {
        var count = 0
        var current: any Palette = palette
        while true {
            if String(describing: type(of: current)) == name { count += 1 }
            guard let derived = current as? any DerivedPalette else { return count }
            current = derived.base
        }
    }

    private func rendered(_ view: some View) -> String {
        renderToBuffer(view, context: makeBareRenderContext()).lines.joined()
    }

    // MARK: - Reading

    @Test("The environment reads the palette's scheme, and a .palette flips it")
    func paletteDecides() {
        #expect(environment(Self.darkPage).colorScheme == .dark)
        #expect(environment(Self.lightPage).colorScheme == .light)
    }

    /// A surface painted inside the app is not the appearance. SwiftUI's scheme
    /// comes from the environment, and a white panel on a dark page is a white
    /// panel on a dark page.
    @Test("A surface painted under a view does not flip the scheme")
    func surfaceIsNotTheScheme() {
        #expect(rendered(SchemeProbe().palette(Self.darkPage)).contains("dark"))
        #expect(rendered(SchemeProbe().background(.white).palette(Self.darkPage)).contains("dark"))
        var environment = environment(Self.darkPage)
        environment.surfaceBackground = .white
        #expect(environment.colorScheme == .dark)
    }

    // MARK: - Pinning

    @Test("A pin outranks the palette's own page")
    func pinOutranksThePage() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .dark
        #expect(environment.colorScheme == .dark)
    }

    @Test("A pin survives a .palette written inside it")
    func pinSurvivesAnInnerPalette() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .dark
        environment.palette = Self.lightPage
        #expect(environment.colorScheme == .dark)
        #expect(
            rendered(SchemeProbe().palette(Self.darkPage).environment(\.colorScheme, .light))
                .contains("light"))
    }

    /// Both halves of idempotence: a second write of the same pin, and a write of
    /// the other one, each leave exactly one wrapper. Without it every `.tint` and
    /// every `.palette` under a pin would add a hop to every colour read below.
    @Test("A pin replaces an earlier pin rather than stacking on it")
    func pinsDoNotStack() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .dark
        environment.colorScheme = .dark
        environment.colorScheme = .light
        environment.palette = Self.darkPage
        #expect(environment.colorScheme == .light)
        #expect(wrappers(named: "SchemedPalette", in: environment.palette) == 1)
    }

    @Test("Three nested tints under a pin hold one scheme wrapper")
    func nestedTintsHoldOneWrapper() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .dark
        for tint in [Color.rgb(200, 0, 0), .rgb(0, 200, 0), .rgb(0, 0, 200)] {
            environment.palette = TintedPalette(base: environment.palette, tint: tint)
        }
        #expect(wrappers(named: "SchemedPalette", in: environment.palette) == 1)
        #expect(environment.colorScheme == .dark)
    }

    /// The forwarding line on the wrapper, from the other side: a role a wrapper
    /// leaves unstated falls to `Palette`'s collapsing defaults, which would
    /// recompute the scheme from the wrapper's own page and lose the pin.
    @Test("A tinted palette over a pinned base reports the pin")
    func tintedPaletteReportsThePin() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .dark
        let tinted = TintedPalette(base: environment.palette, tint: .rgb(200, 0, 0))
        #expect(tinted.colorScheme == .dark)
    }

    // MARK: - Telling two palettes apart

    /// What a memoized subtree is kept or dropped on. The scheme is part of the
    /// derivation, so a pin flip over one base palette is a different palette.
    @Test("One palette under two pins is not the same palette")
    func pinFlipIsADifferentPalette() {
        var environment = environment(Self.lightPage)
        environment.colorScheme = .light
        let light = environment.palette
        environment.colorScheme = .dark
        let dark = environment.palette
        #expect(!light.isSamePalette(as: dark))
        #expect(light.colorScheme == .light)
        #expect(dark.colorScheme == .dark)
    }

    @Test("A palette edited across grey 117 and 118 is not the same palette")
    func editedAcrossTheCrossoverIsADifferentPalette() {
        let dark = environment(PagePalette(background: .rgb(117, 117, 117))).palette
        let light = environment(PagePalette(background: .rgb(118, 118, 118))).palette
        #expect(!dark.isSamePalette(as: light))
        #expect(dark.colorScheme == .dark)
        #expect(light.colorScheme == .light)
    }
}
