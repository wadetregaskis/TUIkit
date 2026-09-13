//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorMultiplyAlphaTests.swift
//
//  `colorMultiply` multiplies RGBA, so a translucent tint fades what is under it.
//  The RGB half is arithmetic on the escapes; the alpha half cannot be, because a
//  colour's alpha is not in the bytes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent colorMultiply tint")
struct ColorMultiplyAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 10, height: Int = 1) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    @Test("An opaque tint claims nothing")
    func opaqueTint() {
        #expect(
            buffer(Text("hi").foregroundStyle(Color.red).colorMultiply(.green))
                .opacityRegions.isEmpty)
    }

    @Test("A half-transparent tint fades the layer by half")
    func halfTint() throws {
        let drawn = buffer(
            Text("hi").foregroundStyle(Color.red).colorMultiply(Color.white.opacity(0.5)))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(claim.opacity == 128.0 / 255)
        // The LAYER channel, not ink or field: this says how PRESENT the subtree is.
        // On ink and field instead, a fully transparent multiply would still draw its
        // glyphs — and `.opacity(_:)` would mean something different from
        // `.colorMultiply(.white.opacity(_:))`, which in SwiftUI it does not.
        #expect(claim.inkOpacity == 1)
        #expect(claim.fieldOpacity == 1)
    }

    @Test("A white tint at half alpha changes no hue, only presence")
    func whiteTintIsHueNeutral() {
        // `.white` is the multiply identity by SPELLING, not by arithmetic:
        // `Color.white` is ANSI white — 229, not 255 — so running it through the
        // multiply darkens by 229/255. The identity shortcut is what makes
        // `.colorMultiply(.white)` mean what it says, and this asserts a faded white
        // gets the same shortcut. It did not, before: it slipped past the check and
        // darkened the subtree as a side effect of fading it, which is how this test
        // found the bug rather than confirming the fix.
        let plain = buffer(Text("hi").foregroundStyle(Color.red))
        let tinted = buffer(
            Text("hi").foregroundStyle(Color.red).colorMultiply(Color.white.opacity(0.5)))
        #expect(tinted.lines[0] == plain.lines[0], "\(tinted.lines[0].debugDescription)")
        #expect(!tinted.opacityRegions.isEmpty, "and yet it fades")
    }

    @Test("A clear tint hides the subtree")
    func clearTint() throws {
        let drawn = buffer(Text("hi").foregroundStyle(Color.red).colorMultiply(.clear))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(claim.opacity == 0)
        // Resolved over a page, a layer at zero yields the destination back — the
        // glyph loses the ½ contest rather than being painted in the page's colour.
        let context = makeRenderContext(width: 10, height: 1)
        let resolved = drawn.resolvingOpacity(
            surface: .blue, palette: context.environment.palette)
        #expect(
            !resolved.lines[0].contains("hi"),
            "hidden, not merely faint: \(resolved.lines[0].debugDescription)")
    }

    @Test("The tint's own hue still multiplies")
    func hueStillMultiplies() {
        // The RGB half must not have been traded for the alpha half. A green tint
        // zeroes red's red channel whatever its alpha.
        let drawn = buffer(
            Text("hi").foregroundStyle(Color.red).colorMultiply(Color.green.opacity(0.5)))
        #expect(!drawn.opacityRegions.isEmpty, "the alpha half")
        let plain = buffer(Text("hi").foregroundStyle(Color.red))
        #expect(drawn.lines[0] != plain.lines[0], "and the hue half")
    }

    @Test("The content's own claims survive the rewrite")
    func contentClaimsSurvive() {
        // The effect rewrites the escapes and the content's alpha is not IN the
        // escapes, so a claim the content made has to travel through untouched.
        let drawn = buffer(
            Text("hi").foregroundStyle(Color.red.opacity(0.5)).colorMultiply(.green))
        #expect(
            drawn.opacityRegions.contains { $0.inkOpacity < 1 },
            "the text's ink claim: \(drawn.opacityRegions)")
    }

    @Test("A tint nests with an inner fade, the way a second fade would")
    func tintNestsWithInnerFade() {
        // The resolution takes the LAYER from the first region covering a cell, so
        // that region has to hold the product already — the rule `.opacity(_:)`
        // follows. Appended bare, the tint's rectangle came second and lost: the
        // pair resolved at the inner 0.5 and the tint's half went nowhere, where
        // SwiftUI (and `.opacity(0.5).opacity(0.5)` here) gives a quarter.
        let drawn = buffer(Text("hi").opacity(0.5).colorMultiply(Color.white.opacity(0.5)))
        let layers = drawn.opacityRegions.map(\.opacity)
        let tint = 128.0 / 255
        #expect(layers == [0.5 * tint, tint], "the first region is the layer: \(layers)")
    }

    @Test("A clear tint hides a subtree that claims an alpha of its own")
    func clearTintHidesAClaimingSubtree() {
        // The sharpest form of the ordering bug needs no `.opacity(_:)` at all. A
        // translucent foreground claims its ink at layer 1; that claim came first,
        // so the layer resolved at 1 and the text drew. `clearTint` above passes
        // only because its text claims nothing.
        let drawn = buffer(
            Text("hi").foregroundStyle(Color.red.opacity(0.5)).colorMultiply(.clear))
        let context = makeRenderContext(width: 10, height: 1)
        let resolved = drawn.resolvingOpacity(
            surface: .blue, palette: context.environment.palette)
        let visible = resolved.lines[0].stripped
        #expect(
            !visible.contains("hi"),
            "hidden, not merely recoloured: \(visible.debugDescription)")
    }
}
