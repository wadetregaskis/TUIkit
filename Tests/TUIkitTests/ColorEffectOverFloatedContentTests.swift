//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEffectOverFloatedContentTests.swift
//
//  A colour effect rewrites what a view DRAWS, and `.offset` and `.position`
//  draw in an overlay layer, leaving a placeholder of empty lines behind. The
//  effects are `.opacity(_:)`'s twin in that, and had to learn the same two
//  things it did: an empty placeholder is not an empty subtree, and an anchored
//  layer is this view's own drawing where a presented dialog is not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Colour effects over content that floats")
struct ColorEffectOverFloatedContentTests {

    private var context: RenderContext {
        makeRenderContext(width: 12, height: 3)
    }

    /// One effect applied in flow and applied over an offset, compared: the first
    /// line the in-flow view draws against the first line of the layer the
    /// displaced one floats. Displacing a view must change where it lands, never
    /// what the effect does to its colours.
    private func expectSameEffect(
        _ name: String, inFlow: some View, displaced: some View, plain: String?
    ) {
        let effected = renderToBuffer(inFlow, context: context).lines.first
        let floated = renderToBuffer(displaced, context: context)
            .overlays.first?.content.lines.first
        #expect(effected != plain, "sanity: \(name) changes the colours in flow")
        #expect(
            floated == effected,
            "\(name) over an offset child drew \(floated.debugDescription), in flow \(effected.debugDescription)")
    }

    @Test("Every effect reaches an offset child, which used to be a complete no-op")
    func effectsReachOffsetChildren() {
        // `.offset` returns a placeholder whose lines are all empty and puts the
        // drawing in a layer, so the effects' `isEmpty` guard returned before
        // doing anything at all: the child drew in its own colours with no hint
        // that an effect had been asked for.
        let base = Text("hi").foregroundStyle(Color.rgb(200, 40, 90))
        let moved = base.offset(x: 1)
        let plain = renderToBuffer(base, context: context).lines.first
        expectSameEffect("grayscale", inFlow: base.grayscale(1), displaced: moved.grayscale(1), plain: plain)
        expectSameEffect("brightness", inFlow: base.brightness(0.5), displaced: moved.brightness(0.5), plain: plain)
        expectSameEffect("contrast", inFlow: base.contrast(3), displaced: moved.contrast(3), plain: plain)
        expectSameEffect("saturation", inFlow: base.saturation(0), displaced: moved.saturation(0), plain: plain)
        expectSameEffect(
            "hueRotation", inFlow: base.hueRotation(.degrees(90)),
            displaced: moved.hueRotation(.degrees(90)), plain: plain)
        expectSameEffect("colorInvert", inFlow: base.colorInvert(), displaced: moved.colorInvert(), plain: plain)
        expectSameEffect(
            "colorMultiply", inFlow: base.colorMultiply(.rgb(255, 0, 0)),
            displaced: moved.colorMultiply(.rgb(255, 0, 0)), plain: plain)
    }

    @Test("An effect over a column reaches its offset row as well as its in-flow one")
    func effectReachesBothHalvesOfAMixedTree() throws {
        // The column's lines are not empty, so the guard passed — and then the
        // rewrite walked `lines` alone, leaving the layer the offset row lives in
        // at its own colours: one row grey, the row below it red.
        let red = Color.rgb(200, 40, 40)
        let column = VStack {
            Text("a").foregroundStyle(red)
            Text("b").foregroundStyle(red).offset(x: 1)
        }
        let drawn = renderToBuffer(column.grayscale(1), context: context)
        let anchored = drawn.overlays.first { !$0.isScreenLevel }
        let layer = try #require(anchored, "precondition: the offset row produced a layer")
        let inFlow = drawn.lines.joined()
        let floated = layer.content.lines.joined()
        // The Rec. 709 grey of (200, 40, 40) is 74.016.
        #expect(inFlow.contains("74;74;74"), "sanity: the in-flow row greys: \(inFlow.debugDescription)")
        #expect(
            floated.contains("74;74;74"),
            "the offset row kept its colour beside a greyed sibling: \(floated.debugDescription)")
    }

    @Test("A clear tint hides an offset child, and stamps nothing over the empty slot")
    func clearTintReachesOffsetChildren() throws {
        let drawn = renderToBuffer(Text("hi").offset(x: 1).colorMultiply(.clear), context: context)
        let anchored = drawn.overlays.first { !$0.isScreenLevel }
        let layer = try #require(anchored, "precondition: the offset child produced a layer")
        let layers = layer.content.opacityRegions.map(\.opacity)
        #expect(layers == [0], "the layer's own drawing was never faded: \(layers)")
        // The slot left in flow drew nothing, so a rectangle over it would claim
        // cells no one painted — `_OpacityView` declines it for the same reason.
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")

        // And composited, where the layer's region is resolved against what it
        // lands on: gone, not painted black.
        let palette = context.environment.palette
        let screen = drawn.compositingOverlays(maxWidth: 12, maxHeight: 3, palette: palette)
        let visible = screen.lines.map(\.stripped).joined()
        #expect(!visible.contains("hi"), "hidden, not merely black: \(visible.debugDescription)")
    }

    @Test("An effect does NOT reach a dialog the view presented")
    func effectsSparePresentations() {
        // A `.sheet` is a panel over the whole screen that the root compositor
        // draws — not this view's drawing, and no more recoloured by a modifier on
        // its presenter than it is faded by one. The same `isScreenLevel` line
        // `.opacity(_:)`, `.hidden()` and `.allowsHitTesting(false)` all draw.
        let context = makeRenderContext(width: 30, height: 8)
        let red = Color.rgb(200, 40, 40)
        func modalLayer(grey amount: Double) -> FrameBuffer? {
            let view = Text("page").foregroundStyle(red)
                .modal(isPresented: .constant(true)) {
                    Dialog(title: "D") { Text("body").foregroundStyle(red) }
                }
                .grayscale(amount)
            return renderToBuffer(view, context: context)
                .overlays.first { $0.level == .modal }?.content
        }
        let untouched = modalLayer(grey: 0)
        let greyed = modalLayer(grey: 1)
        #expect(untouched != nil, "precondition: the modal layer reached the buffer")
        #expect(greyed?.lines == untouched?.lines, "the dialog was recoloured with its presenter")
    }
}
