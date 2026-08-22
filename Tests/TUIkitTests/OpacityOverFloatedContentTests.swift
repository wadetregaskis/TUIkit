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

    /// Drives a repeating fade the way the run loop does — the store prunes its
    /// records at the end of every pass, so a pass that is not bracketed sees a
    /// first sight every time, and a first sight never animates.
    @MainActor
    private final class Cycling {
        var context = makeRenderContext(width: 20, height: 4)

        init() {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(
                animation: .linear(duration: 0.4).repeatForever(autoreverses: true))
        }

        func render(_ opacity: Double, atTick tick: Int) -> FrameBuffer {
            context.environment.animationTick = tick
            context.environment.frameNowNanos =
                Int64(Double(tick) * AnimationClock.cursor.tickInterval * 1_000_000_000)
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Text("x").offset(x: 2).opacity(opacity), context: context)
        }
    }

    @Test("A repeating fade hands the offset child its own frames")
    func repeatingFadeAnimatesAnOffsetChild() {
        // The pre-rendered cycle builds runs from the buffer's LINES, and an
        // offset child has none — its content is in a layer. The modifier used
        // to decline the whole path when a layer was present and pay a render
        // per frame; now the layer carries its own frames, in its own
        // coordinate space, which the compositor shifts by wherever it places
        // the layer.
        let screen = Cycling()
        _ = screen.render(1, atTick: 0)
        let buffer = screen.render(0.2, atTick: 0)

        guard let layer = buffer.overlays.first(where: { !$0.isScreenLevel }) else {
            Issue.record("precondition: the offset child produced a layer")
            return
        }
        #expect(
            !layer.content.animatedCells.isEmpty,
            "the layer got no frames, so the fade would freeze it")
        #expect(
            layer.content.animatedCells.allSatisfy { $0.isAnimating },
            "a frame set that never changes is a still picture")
        #expect(
            layer.content.animatedCells.allSatisfy { $0.frames.count == 16 },
            "0.4s out and back is sixteen ticks of the replay clock")
    }

    @Test("…and the loop then stops rendering for it")
    func repeatingFadeOverALayerStopsTheRenders() {
        // The whole point of the pre-rendered path, and what declining it cost:
        // a fade that never ends, served by re-rendering, costs a render pass
        // for as long as the view is on screen.
        let screen = Cycling()
        _ = screen.render(1, atTick: 0)
        _ = screen.render(0.2, atTick: 0)
        let animations = screen.context.environment.stateStorage!.animations
        #expect(
            !animations.hasLiveAnimations(at: 400 * 1_000_000),
            "a repeating fade over an offset child woke the loop up again")
    }

    @Test("The layer's frames survive compositing, shifted to where it landed")
    func layerFramesReachTheScreen() {
        // A run attached to a layer is in the LAYER's space; it only means
        // anything if the compositor lifts and shifts it. `FrameBuffer
        // .composited` does — this is what says so end to end, since a run that
        // never reaches the final buffer is an animation the loop stops
        // clocking.
        var layerContent = FrameBuffer(lines: ["ab"])
        layerContent.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 2, frames: ["ab", "cd"], clock: .cursor)
        ]
        let base = FrameBuffer(lines: ["........", "........"])
        let composited = base.composited(
            with: FrameBuffer(lines: [""]).replacingLines([""]).withOverlay(
                OverlayLayer(offsetX: 0, offsetY: 0, content: layerContent)),
            at: (x: 3, y: 1))
        let screen = composited.compositingOverlays(
            maxWidth: 8, maxHeight: 2, palette: SystemPalette(.green))
        #expect(
            screen.animatedCells.contains { $0.offsetX == 3 && $0.offsetY == 1 },
            "the layer's run did not reach the screen at its placement: \(screen.animatedCells)")
    }
}

extension FrameBuffer {
    /// Test helper: this buffer carrying `layer`.
    fileprivate func withOverlay(_ layer: OverlayLayer) -> FrameBuffer {
        var copy = self
        copy.overlays.append(layer)
        return copy
    }
}
