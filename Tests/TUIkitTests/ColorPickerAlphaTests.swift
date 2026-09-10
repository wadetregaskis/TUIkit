//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorPickerAlphaTests.swift
//
//  A `ColorPicker` bound to a translucent `Color`. The swatch turns out to be
//  built from already-migrated pieces; `supportsOpacity` is the part that is not
//  there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A ColorPicker on a translucent binding")
struct ColorPickerAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 40, height: Int = 2) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    @Test("The swatch fades, because it is a Text on a background")
    func swatchFades() {
        // `_ColorSwatchButtonStyle` draws `Text("█").foregroundStyle(fill).background(fill)`,
        // and both of those are migrated (§14 and the flat `.background` arm). So the
        // swatch needed no work — but "needed no work" is worth a test rather than an
        // assumption, because the composition it relies on is two features deep.
        let faded = Color.rgb(80, 160, 255).opacity(0.5)
        let drawn = buffer(ColorPicker("Accent", selection: .constant(faded)))
        #expect(
            drawn.opacityRegions.contains { $0.fieldOpacity < 1 },
            "the swatch's field: \(drawn.opacityRegions)")
        #expect(
            drawn.opacityRegions.contains { $0.inkOpacity < 1 },
            "and its glyph: \(drawn.opacityRegions)")
    }

    @Test("An opaque binding claims nothing")
    func opaqueBindingClaimsNothing() {
        let drawn = buffer(ColorPicker("Accent", selection: .constant(.rgb(80, 160, 255))))
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    @Test("The channel sliders still read only R, G and B")
    func noAlphaChannel() {
        // The parity gap, asserted so it is a recorded decision rather than an
        // oversight: SwiftUI's `ColorPicker(selection:supportsOpacity:label:)` has a
        // fourth channel and this has three. The reason the omission was documented
        // with — "terminal colours have no alpha" — stopped being true when `Color`
        // gained one. If a fourth channel lands, this test should fail and be
        // rewritten. See `Documentation/Opacity as composition.md` §26.
        // A label with no letters of its own, so the channel letters are the only
        // ones on the row — "Accent" contains an A, which made the first version of
        // this test fail for the wrong reason.
        let drawn = buffer(
            ColorPicker("·", selection: .constant(.rgb(80, 160, 255))), width: 60)
        let text = drawn.lines.joined(separator: "\n").stripped
        #expect(text.contains("R") && text.contains("G") && text.contains("B"))
        #expect(!text.contains("A"), "no alpha channel yet: \(text)")
    }
}
