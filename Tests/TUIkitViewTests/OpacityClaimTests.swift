//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityClaimTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// `OpacityRegion.claim` is the one place the alpha half of a translucent paint
/// is derived from the colours actually painted with. Three sites derived it by
/// hand before, and a fourth getting the arithmetic subtly different is the
/// failure this consolidation exists to prevent.
@Suite("Deriving a claim from the colours painted")
struct OpacityClaimTests {

    @Test("Two opaque colours claim nothing at all")
    func opaqueClaimsNothing() {
        #expect(OpacityRegion.claim(width: 10, height: 2, ink: .red, field: .blue) == nil)
        #expect(OpacityRegion.claim(width: 10, height: 2) == nil)
        // `.default` is SGR 39/49 — the terminal's own colour, and fully opaque.
        #expect(OpacityRegion.claim(width: 10, height: 2, ink: .default) == nil)
    }

    @Test("A translucent ink claims the ink channel and leaves the field alone")
    func inkOnly() throws {
        let claim = try #require(
            OpacityRegion.claim(width: 10, height: 2, ink: .red.opacity(0.5)))
        #expect(claim.inkOpacity == 128.0 / 255)
        #expect(claim.fieldOpacity == 1)
        // The LAYER channel stays at 1: faint text is drawn, not half-present.
        // Folding the two would make `.foregroundStyle(.red.opacity(0.3))` lose
        // its glyph to the ½ contest instead of fading it.
        #expect(claim.opacity == 1)
        #expect(claim.isTranslucent)
    }

    @Test("A translucent field claims the field channel and leaves the ink alone")
    func fieldOnly() throws {
        let claim = try #require(
            OpacityRegion.claim(width: 4, height: 1, field: .blue.opacity(0.25)))
        #expect(claim.fieldOpacity == 64.0 / 255)
        #expect(claim.inkOpacity == 1)
    }

    @Test("A fully transparent colour still claims its cells")
    func transparentStillClaims() throws {
        // Required, not an optimisation left on the table: the cells were painted
        // and the glyphs written, so only a region routes them through the blend
        // that yields the destination back. Dropping the claim leaves the colour's
        // underlying value — black, for `.clear` — on screen.
        let claim = try #require(OpacityRegion.claim(width: 3, height: 1, field: .clear))
        #expect(claim.fieldOpacity == 0)
        #expect(claim.isTranslucent)
    }

    @Test("The claim takes the rectangle it is given")
    func geometry() throws {
        let claim = try #require(
            OpacityRegion.claim(
                offsetX: 7, offsetY: 3, width: 5, height: 2, ink: .red.opacity(0.5)))
        #expect(claim.offsetX == 7)
        #expect(claim.offsetY == 3)
        #expect(claim.width == 5)
        #expect(claim.height == 2)
    }

    @Test("An empty rectangle claims nothing, however translucent its colours")
    func degenerateGeometry() {
        #expect(OpacityRegion.claim(width: 0, height: 1, ink: .clear) == nil)
        #expect(OpacityRegion.claim(width: 4, height: 0, ink: .clear) == nil)
        #expect(OpacityRegion.claim(width: -3, height: 1, field: .clear) == nil)
    }

    @Test("A semantic colour's own alpha is read without resolving it")
    func semanticAlpha() throws {
        // The claim is made where the paint is, and a paint site has already
        // resolved its colour — but a caller that has not must still get the
        // right answer rather than a silently opaque one.
        let claim = try #require(
            OpacityRegion.claim(width: 2, height: 1, ink: Color.Semantic.accent.opacity(0.5)))
        #expect(claim.inkOpacity == 128.0 / 255)
    }
}
