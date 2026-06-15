//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SemanticColorResolutionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  A palette slot can hold a semantic *reference* to another role (a colour
//  picker's semantic tab does this). If that reference points — directly or
//  through a chain — back at the slot being resolved, one-hop resolution
//  returns a still-`.semantic` colour, which `ANSIRenderer` traps on. These
//  tests pin that `Color.resolve(with:)` always reaches a concrete colour.

import Testing

@testable import TUIkit

// MARK: - Stub palettes with semantic references in their slots

/// `accent` references its own role — resolving `.accent` yields `.semantic(.accent)`
/// again (the crash the colour picker hit: pick "Accent" while editing accent).
private struct SelfRefPalette: Palette {
    let id = "selfref"
    let name = "Self-ref"
    let background = Color.black
    let foreground = Color.white
    var accent: Color { .palette.accent }
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.brightBlack
}

/// `accent` → `success` → `accent`: a two-role cycle.
private struct CyclePalette: Palette {
    let id = "cycle"
    let name = "Cycle"
    let background = Color.black
    let foreground = Color.white
    var accent: Color { .palette.success }
    var success: Color { .palette.accent }
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.brightBlack
}

/// `accent` → `success`, and `success` is concrete — a chain that resolves in
/// two hops.
private struct ChainPalette: Palette {
    let id = "chain"
    let name = "Chain"
    let background = Color.black
    let foreground = Color.white
    var accent: Color { .palette.success }
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.brightBlack
}

@MainActor
@Suite("Semantic colour resolution")
struct SemanticColorResolutionTests {

    @Test("A self-referential slot resolves to a concrete colour, not a trap")
    func selfReferenceResolvesConcrete() {
        let resolved = Color.palette.accent.resolve(with: SelfRefPalette())
        #expect(resolved.rgbComponents != nil, "resolution must reach RGB, got \(resolved)")
        if case .semantic = resolved.value {
            Issue.record("resolve() returned a still-semantic colour: \(resolved)")
        }
    }

    @Test("A reference cycle resolves to a concrete colour, not an infinite loop")
    func cycleResolvesConcrete() {
        let viaAccent = Color.palette.accent.resolve(with: CyclePalette())
        let viaSuccess = Color.palette.success.resolve(with: CyclePalette())
        #expect(viaAccent.rgbComponents != nil)
        #expect(viaSuccess.rgbComponents != nil)
    }

    @Test("A non-cyclic reference chain resolves to the target's concrete colour")
    func chainResolvesToTarget() {
        let palette = ChainPalette()
        // accent → success → (concrete success). The resolved accent must equal
        // the resolved success.
        let accent = Color.palette.accent.resolve(with: palette)
        let success = Color.palette.success.resolve(with: palette)
        #expect(accent.rgbComponents != nil)
        #expect(accent.rgbComponents! == success.rgbComponents!, "accent should resolve to success's colour")
        if case .semantic = accent.value { Issue.record("accent left unresolved") }
    }

    @Test("Rendering text tinted by a self-referential semantic role does not trap")
    func renderingSelfReferenceDoesNotTrap() {
        // This is the actual crash path: a Text tinted with `.palette.accent`,
        // resolved against a palette whose accent slot is itself `.semantic(.accent)`,
        // used to reach ANSIRenderer as an unresolved semantic colour and trap.
        var environment = EnvironmentValues()
        environment.palette = SelfRefPalette()
        let context = RenderContext(
            availableWidth: 20, availableHeight: 3,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()

        let buffer = renderToBuffer(Text("x").foregroundStyle(.palette.accent), context: context)
        #expect(buffer.lines.first?.stripped == "x", "renders the text without trapping")
    }
}
