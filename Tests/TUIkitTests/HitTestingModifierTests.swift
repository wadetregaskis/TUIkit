//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VisibilityModifierTests.swift
//
//  `allowsHitTesting(_:)` — taking the mouse away from a view without taking
//  its drawing or its space.
//
//  The property worth guarding is that it changes NOTHING else: not one byte
//  of output, not one cell of layout. A modifier that quietly restyled would
//  be `disabled(_:)` wearing the wrong name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Hit testing")
struct HitTestingModifierTests {

    private func lines(_ view: some View, width: Int = 24, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map {
                $0.stripped.replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression)
            }
    }

    private func buffer(_ view: some View, width: Int = 24, height: Int = 8) -> FrameBuffer {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
    }

    private func size(_ view: some View, width: Int = 24, height: Int = 8) -> ViewSize {
        measureChild(
            view, proposal: ProposedSize(width: width, height: height),
            context: makeBareRenderContext(width: width, height: height))
    }

    // MARK: - allowsHitTesting()

    @Test("allowsHitTesting(false) drops the hit regions")
    func dropsRegions() {
        let live = buffer(Button("Press") {})
        let inert = buffer(Button("Press") {}.allowsHitTesting(false))
        #expect(!live.hitTestRegions.isEmpty)
        #expect(inert.hitTestRegions.isEmpty)
    }

    /// Unlike `hidden()`, it still draws — that is the whole distinction.
    @Test("a non-hit-testable view still draws and still measures the same")
    func stillDraws() {
        let shown = Text(verbatim: "watermark")
        let inert = shown.allowsHitTesting(false)
        #expect(lines(inert) == lines(shown))
        #expect(size(inert).width == size(shown).width)
        #expect(size(inert).height == size(shown).height)
    }

    @Test("allowsHitTesting(true) changes nothing")
    func trueIsANoOp() {
        let live = buffer(Button("Press") {})
        let stillLive = buffer(Button("Press") {}.allowsHitTesting(true))
        #expect(live.hitTestRegions.count == stillLive.hitTestRegions.count)
        #expect(!stillLive.hitTestRegions.isEmpty)
    }

    /// A subtree can float an OVERLAY — a pop-over, a drop-down — whose hit
    /// regions live on the layer rather than in the buffer's own lines.
    /// Clearing only the top level would leave that layer clickable underneath
    /// a view that just declared itself untouchable.
    @Test("overlays lose their hit regions too")
    func overlaysAreCleared() {
        func regionCount(_ view: some View) -> (own: Int, overlay: Int) {
            let drawn = buffer(view, width: 40, height: 12)
            return (drawn.hitTestRegions.count,
                    drawn.overlays.reduce(0) { $0 + $1.content.hitTestRegions.count })
        }
        let shown = Text(verbatim: "page")
            .popover(isPresented: .constant(true)) { Button("Inside") {} }
        let live = regionCount(shown)
        #expect(live.overlay > 0, "the fixture really does float a clickable overlay")

        let inert = regionCount(shown.allowsHitTesting(false))
        #expect(inert.own == 0)
        #expect(inert.overlay == 0, "the floated layer is inert too")
    }

    /// It is not `disabled(_:)`: the control keeps its ordinary appearance and
    /// stays reachable by keyboard, which is why both modifiers exist.
    ///
    /// Compared on the RAW lines, because the difference disabling makes is a
    /// colour one — the glyphs are identical either way, so a stripped
    /// comparison sees no change at all and would pass whatever happened.
    @Test("it is not the same as disabled")
    func notDisabled() {
        let live = buffer(Button("Press") {}).lines.joined()
        let inert = buffer(Button("Press") {}.allowsHitTesting(false)).lines.joined()
        let switchedOff = buffer(Button("Press") {}.disabled(true)).lines.joined()
        #expect(inert == live, "hit-testing does not restyle — not one byte")
        #expect(switchedOff != live, "…whereas disabling recolours")
        #expect(
            switchedOff.stripped == live.stripped,
            "and even disabling changes only the colour, never the glyphs")
    }
}
