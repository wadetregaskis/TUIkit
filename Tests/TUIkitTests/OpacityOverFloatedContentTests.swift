//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityOverFloatedContentTests.swift
//
//  `.opacity()` fades what a view DRAWS. Some of what a view draws does not
//  live in its buffer's lines — `.offset` and `.position` put their content in
//  an overlay layer and leave a placeholder behind — and some of what a view
//  hosts is not its drawing at all, which is what a presented sheet is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Opacity over content that floats")
struct OpacityOverFloatedContentTests {

    /// The composited screen, raw — the fade is a colour change and nothing
    /// else, so stripping the styling would strip the entire subject.
    private func screen(_ view: some View, width: Int = 30, height: Int = 6) -> String {
        let context = makeRenderContext(width: width, height: height)
        let buffer = renderToBuffer(view, context: context)
        return buffer.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: context.environment.palette
        ).lines.joined(separator: "\n")
    }

    @Test("A fade reaches an offset child, which used to be a complete no-op")
    func fadeReachesOffsetChildren() {
        // `.offset` returns a placeholder whose lines are all empty and puts
        // the content in a layer, so the modifier's `isEmpty` guard returned
        // before doing anything at all: the child rendered at FULL strength
        // with no hint that a fade had been asked for.
        let plain = screen(Text("x").offset(x: 2))
        let faded = screen(Text("x").offset(x: 2).opacity(0.5))
        #expect(plain != faded, "the fade did not reach the offset child")

        // And it fades to the SAME colour it would in flow: displacing a view
        // must not change how far it fades, only where it lands.
        let inFlowColour = colour(in: screen(Text("x").opacity(0.5)))
        let offsetColour = colour(in: faded)
        #expect(inFlowColour != nil, "sanity: the in-flow fade named a colour")
        #expect(
            offsetColour == inFlowColour,
            "offset child faded to \(offsetColour ?? "nothing"), in flow it is \(inFlowColour ?? "nothing")")
    }

    /// The first `38;2;r;g;b` foreground in a rendered screen.
    private func colour(in screen: String) -> String? {
        guard let start = screen.range(of: "38;2;") else { return nil }
        let rest = screen[start.upperBound...]
        return String(rest.prefix { $0.isNumber || $0 == ";" })
    }

    @Test("A fade reaches a positioned child too")
    func fadeReachesPositionedChildren() {
        #expect(
            screen(Text("x").position(x: 3, y: 1))
                != screen(Text("x").position(x: 3, y: 1).opacity(0.5)))
    }

    @Test("A fade does NOT reach a dialog the view presented")
    func fadeSparesPresentations() {
        // `.opacity` recolours what this view draws. A `.sheet` is a panel over
        // the whole screen that the root compositor draws — not this view's
        // drawing, and not something a modifier on the presenter should be able
        // to dim, any more than it is in SwiftUI. The same `centered`
        // distinction `.hidden()` and `.allowsHitTesting(false)` turn on.
        let context = makeRenderContext(width: 30, height: 8)
        func modalLayer(opacity: Double) -> FrameBuffer? {
            let view = Text("page")
                .modal(isPresented: .constant(true)) { Dialog(title: "D") { Text("body") } }
                .opacity(opacity)
            return renderToBuffer(view, context: context)
                .overlays.first { $0.level == .modal }?.content
        }
        let opaque = modalLayer(opacity: 1)
        let faded = modalLayer(opacity: 0.2)
        #expect(opaque != nil, "precondition: the modal layer reached the buffer")
        #expect(faded?.lines == opaque?.lines, "the dialog faded with its presenter")
    }

    @Test("A repeating fade over an offset child keeps moving")
    func repeatingFadeDoesNotFreezeAnOffsetChild() {
        // The pre-rendered cycle builds its runs out of the buffer's LINES, so
        // it cannot carry a layer through the phases — replaying would freeze
        // the offset child at whichever phase it was first drawn. The modifier
        // declines that path when an anchored layer is present and pays a
        // render per frame instead, which is what every fade cost before the
        // cycle existed.
        let context = makeRenderContext(width: 30, height: 6)
        let view = Text("x").offset(x: 2).opacity(0.5)
        let buffer = renderToBuffer(view, context: context)
        #expect(
            buffer.animatedCells.isEmpty,
            "an anchored layer must not be handed to the replay path")
    }
}
