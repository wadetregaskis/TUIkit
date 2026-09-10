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

    /// The successor to `noAlphaChannel`, which pinned the gap and has now been
    /// rewritten by the fourth channel landing — exactly as it asked to be.
    ///
    /// A label with no letters of its own, so the channel captions are the only ones
    /// on the row: "Accent" contains an A, which made the first version of that test
    /// fail for the wrong reason.
    @Test("The channel sliders read R, G, B and A")
    func alphaChannelIsOffered() {
        let drawn = buffer(
            ColorPicker("·", selection: .constant(.rgb(80, 160, 255))), width: 70)
        let text = drawn.lines.joined(separator: "\n").stripped
        for caption in ["R", "G", "B", "A"] {
            #expect(text.contains(caption), "no \(caption) channel: \(text)")
        }
    }

    @Test("supportsOpacity: false withholds the channel")
    func opacityCanBeWithheld() {
        let drawn = buffer(
            ColorPicker("·", selection: .constant(.rgb(80, 160, 255)), supportsOpacity: false),
            width: 70)
        let text = drawn.lines.joined(separator: "\n").stripped
        #expect(text.contains("R") && text.contains("G") && text.contains("B"))
        #expect(!text.contains("A"), "\(text)")
    }

    /// **The bug the fourth channel exposed, which was there all along.**
    ///
    /// `.rgb(r, g, b)` is opaque, so rewriting the colour on a channel edit deleted a
    /// translucent binding's alpha on the first arrow press — a picker that could not
    /// edit opacity silently destroyed it instead. Independent of
    /// ``supportsOpacity``: withholding the editor is not licence to overwrite the
    /// value.
    @Test("Editing R, G or B keeps the alpha the colour already had")
    func rgbEditKeepsAlpha() {
        for supportsOpacity in [true, false] {
            final class Box { var color = Color.rgb(80, 160, 255).opacity(0.5) }
            let box = Box()
            let picker = ColorPicker(
                "·", selection: Binding(get: { box.color }, set: { box.color = $0 }),
                supportsOpacity: supportsOpacity)
            _ = buffer(picker, width: 70)
            // Drive the binding the way an arrow press does.
            picker.channelBindingForTests(.red).wrappedValue = 200
            #expect(box.color.rgbComponents?.red == 200, "the edit did not land")
            #expect(
                box.color.alpha == 128,
                "supportsOpacity: \(supportsOpacity) destroyed the alpha: \(box.color.alpha)")
        }
    }

    /// A control that withholds the opacity editor should not display an opacity
    /// either — the one state you cannot reach must not be the one you can see. The
    /// BINDING keeps its alpha regardless; this is only about what the swatch draws.
    @Test("supportsOpacity: false draws an opaque swatch over a translucent binding")
    func withheldOpacityDrawsOpaque() {
        let faded = Color.rgb(80, 160, 255).opacity(0.5)
        let drawn = buffer(
            ColorPicker("Accent", selection: .constant(faded), supportsOpacity: false))
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    // MARK: - The panel

    @Test("The panel offers an opacity row, outside the model tabs")
    func panelHasAnOpacityRow() {
        let context = RenderContext(
            availableWidth: 70, availableHeight: 30, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let drawn = renderToBuffer(
            ColorPickerPanel("C", selection: .constant(.rgb(80, 160, 255)), isPresented: .constant(true)),
            context: context)
        #expect(drawn.lines.joined(separator: "\n").stripped.contains("Opacity"))
    }

    @Test("A model tab's edit keeps the alpha, and the opacity row keeps the colour")
    func panelChannelsAndOpacityAreOrthogonal() {
        // The division of labour the panel states: the model tabs edit the COLOUR and
        // the opacity row edits the OPACITY. Before the alpha-preserving transform,
        // every one of the six write paths — RGB/HSL/HSB/CMYK, a swatch grid, a typed
        // hex, a semantic role — rewrote the colour as an opaque spelling.
        var held = Color.rgb(80, 160, 255).opacity(0.5)
        let binding = Binding(get: { held }, set: { held = $0 })
        let body = _ColorPickerBody(selection: binding)
        body.colorOnlyForTests.wrappedValue = .rgb(10, 20, 30)
        #expect(held.rgbComponents?.red == 10)
        #expect(held.alpha == 128, "the colour edit spent the alpha: \(held.alpha)")
        body.alphaBindingForTests.wrappedValue = 64
        #expect(held.alpha == 64)
        #expect(held.rgbComponents?.red == 10, "the opacity edit moved the colour")
    }
}
