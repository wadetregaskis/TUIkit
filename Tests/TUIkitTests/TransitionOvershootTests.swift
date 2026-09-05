//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionOvershootTests.swift
//
//  A spring goes past its target and comes back. `.move` and `.offset` draw
//  that, standing a cell or two clear of the slot they are arriving in; the
//  other effects cannot, and stop at 1.
//
//  Measured, with `Animation.bouncy`: the curve peaks at 1.0460 (0.350 s into
//  a 0.745 s pass), which is one cell for a twenty-cell view. `.snappy` peaks
//  at 1.0063 — sub-cell, so it never draws a bounce, which is right: SwiftUI's
//  snappy does not visibly bounce either.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit
@testable import TUIkitStyling

/// A view that comes and goes, in a slot that survives it.
private struct Host: View {
    let showing: Bool
    let transition: AnyTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showing {
                Text("XXXXXXXXXXXXXXXXXXXX").transition(transition)
            }
            Text("--------------------")
        }
    }
}

@MainActor
@Suite("Transition overshoot")
struct TransitionOvershootTests {

    /// The frame the compositor produces, which is where a floated layer
    /// becomes visible at all.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 30, height: 4)

        init(_ animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func drawBuffer(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int)
            -> FrameBuffer
        {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Host(showing: showing, transition: transition), context: context)
        }

        func draw(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int) -> [String] {
            drawBuffer(showing, transition, atMillis: millis)
                .compositingOverlays(maxWidth: 30, maxHeight: 4, palette: SystemPalette.green)
                .lines.map { $0.stripped }
        }
    }

    /// 0.350 s: where `Animation.bouncy` peaks, at phase 1.0460.
    private static let peakMillis = 350

    // MARK: - The two effects that overshoot

    @Test("A view sliding in from the leading edge carries on past its home")
    func moveOvershoots() {
        let screen = Screen(.bouncy)
        _ = screen.draw(false, .slide, atMillis: 0)
        _ = screen.draw(true, .slide, atMillis: 0)
        let peak = screen.draw(true, .slide, atMillis: Self.peakMillis)
        // One cell right of home — it came from the left, so it overshoots to
        // the right, and 20 cells × 0.0460 rounds to 1.
        #expect(peak[0] == " XXXXXXXXXXXXXXXXXXXX", "\(peak)")
        // And the row below is untouched: the picture floats, it does not drag
        // the layout with it. (It is one cell wider, because the composite grew
        // to hold the layer.)
        #expect(peak[1].hasPrefix("--------------------"), "\(peak)")
        #expect(peak[1].dropFirst(20).allSatisfy { $0 == " " }, "\(peak)")
    }

    @Test("An offset transition overshoots the way it came")
    func offsetOvershoots() {
        let screen = Screen(.bouncy)
        let transition = AnyTransition.offset(x: -20)
        _ = screen.draw(false, transition, atMillis: 0)
        _ = screen.draw(true, transition, atMillis: 0)
        let peak = screen.draw(true, transition, atMillis: Self.peakMillis)
        // Arriving from 20 columns left, so past its target it stands one
        // column right of home: −20 × −0.046 → +1.
        #expect(peak[0] == " XXXXXXXXXXXXXXXXXXXX", "\(peak)")
    }

    @Test("A sub-cell overshoot draws no bounce at all")
    func noMinimumBounce() {
        // `.snappy` peaks at 1.0063, which is 0.13 of a cell across twenty. The
        // picture follows the curve rather than a floor: rounding a sub-cell
        // overshoot up to one cell would make snappy bounce where SwiftUI's
        // does not.
        let screen = Screen(.snappy)
        _ = screen.draw(false, .slide, atMillis: 0)
        _ = screen.draw(true, .slide, atMillis: 0)
        // 0.475 s is where `.snappy` peaks.
        let peak = screen.draw(true, .slide, atMillis: 475)
        #expect(peak[0] == "XXXXXXXXXXXXXXXXXXXX", "\(peak)")
    }

    @Test("An overshoot off the screen edge loses the columns, and stays put")
    func overshootAtTheScreenEdge() {
        // The pointer-anchored policy rather than the pop-over one: a layer
        // that would hang off the edge is CUT there, not slid back on. A view
        // bouncing at the left edge that jumped right instead would be a
        // different animation from the one the curve describes.
        let screen = Screen(.bouncy)
        let transition = AnyTransition.offset(x: 20)
        _ = screen.draw(false, transition, atMillis: 0)
        _ = screen.draw(true, transition, atMillis: 0)
        let peak = screen.draw(true, transition, atMillis: Self.peakMillis)
        // Home is column 0, so one column left of it is off the screen: the
        // twenty-cell view arrives nineteen cells wide, still at column 0.
        #expect(peak[0].hasPrefix("XXXXXXXXXXXXXXXXXXX "), "\(peak)")
        #expect(!peak[0].hasPrefix("XXXXXXXXXXXXXXXXXXXX"), "\(peak)")
    }

    @Test("The settled frame is exactly the content, with no layer")
    func settlesExactly() {
        // What bounds the cost: an idle frame emits nothing, so it composites
        // nothing. A floated layer is one full-page rebuild per frame through
        // the copying `composited(with:at:)` path — measured at ~23 µs on a
        // 120 × 40 page, linear in the number of layers — and it is spent only
        // while a view is actually past its target.
        let screen = Screen(.bouncy)
        _ = screen.draw(false, .slide, atMillis: 0)
        _ = screen.draw(true, .slide, atMillis: 0)
        let settled = screen.drawBuffer(true, .slide, atMillis: 2000)
        #expect(settled.lines[0].stripped == "XXXXXXXXXXXXXXXXXXXX", "\(settled.lines)")
        #expect(settled.overlays.isEmpty, "a settled transition emitted a layer")
    }

    // MARK: - The effects that cannot

    @Test("A fade does not become more than opaque, and a scale more than whole")
    func clampedEffectsStayClamped() {
        for transition in [AnyTransition.opacity, .scale, .opacity.combined(with: .scale)] {
            let screen = Screen(.bouncy)
            _ = screen.draw(false, transition, atMillis: 0)
            _ = screen.draw(true, transition, atMillis: 0)
            let peak = screen.draw(true, transition, atMillis: Self.peakMillis)
            let settled = screen.draw(true, transition, atMillis: 2000)
            #expect(peak == settled, "past 1 it drew something other than the view: \(peak)")
        }
    }

    @Test("A move combined with a fade floats the FADED picture, not an empty slot")
    func combinedKeepsItsCells() {
        // The trap this shape exists to catch: if the move baked its
        // displacement into the buffer, the fade would run over the emptied
        // slot and the floated cells would arrive unfaded — or, worse, the
        // picture would be a blank box.
        let screen = Screen(.bouncy)
        let transition = AnyTransition.slide.combined(with: .opacity)
        _ = screen.draw(false, transition, atMillis: 0)
        _ = screen.draw(true, transition, atMillis: 0)
        let peak = screen.draw(true, transition, atMillis: Self.peakMillis)
        #expect(peak[0] == " XXXXXXXXXXXXXXXXXXXX", "\(peak)")
    }

    // MARK: - Where it draws

    @Test("The overshoot floats over a sibling rather than pushing it")
    func floatsOverSiblings() {
        // A ZStack sibling occupies the cells the bounce lands on; the layer
        // draws over them, and the sibling keeps the cells the bounce vacates.
        struct Overlapping: View {
            let showing: Bool
            var body: some View {
                ZStack(alignment: .topLeading) {
                    Text("....................")
                    if showing {
                        Text("XXXXXXXXXXXXXXXXXXXX").transition(.slide)
                    }
                }
            }
        }
        var context = makeRenderContext(width: 30, height: 4)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .bouncy)
        func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Overlapping(showing: showing), context: context)
                .compositingOverlays(maxWidth: 30, maxHeight: 4, palette: SystemPalette.green)
                .lines.map { $0.stripped }
        }
        _ = draw(false, atMillis: 0)
        _ = draw(true, atMillis: 0)
        let peak = draw(true, atMillis: Self.peakMillis)
        #expect(peak[0].hasPrefix(".XXXXXXXXXXXXXXXXXXXX"), "\(peak)")
    }

    @Test("A bouncing view does not erase what its padding passes over")
    func paddingDoesNotErase() {
        // Compositing replaces the base cell under EVERY overlay cell, spaces
        // included — `isOpaque` decides only whether blanks are pre-painted, not
        // whether they are drawn. So a view whose slot is wider than its text
        // carries 26 cells of padding, and a bounce would wipe a column of the
        // sibling beneath it for each one.
        struct Overlapping: View {
            let showing: Bool
            var body: some View {
                ZStack(alignment: .topLeading) {
                    Text("..............................")
                    if showing {
                        Text("XXXX").frame(width: 30).transition(.slide)
                    }
                }
            }
        }
        var context = makeRenderContext(width: 30, height: 4)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .bouncy)
        func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(Overlapping(showing: showing), context: context)
                .compositingOverlays(maxWidth: 30, maxHeight: 4, palette: SystemPalette.green)
                .lines.map { $0.stripped }
        }
        _ = draw(false, atMillis: 0)
        _ = draw(true, atMillis: 0)
        let peak = draw(true, atMillis: Self.peakMillis)
        // One dot survives at column 0, the four cells of text land at 1...4,
        // and the twenty-five dots the padding passed over are all still there.
        #expect(peak[0] == "." + "XXXX" + String(repeating: ".", count: 25), "\(peak)")
    }

    @Test("An overshoot on the page stays under a dialog, and one inside it above")
    func relativeOrdering() {
        // The ordering is relative because the NESTING is: a layer emitted
        // inside a presentation's content rides in that presentation's buffer
        // and is drained in the pass after it. No level had to move.
        struct Paged: View {
            let showing: Bool
            var body: some View {
                VStack(spacing: 0) {
                    // Padded so the page's bouncing row lands ON the dialog's
                    // own row. Without this the two never share a row, and the
                    // assertion below passes with no clipping and no zIndex at
                    // all — which is how the first version of this test was
                    // vacuous in exactly the half it existed for.
                    Text(verbatim: "")
                    Text(verbatim: "")
                    Text(verbatim: "")
                    if showing {
                        Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX").transition(.slide)
                    }
                    Spacer()
                }
                .sheet(isPresented: .constant(true)) {
                    VStack(spacing: 0) {
                        Text("AAAAAAAAAAAAAAAAAAAA")
                        if showing {
                            Text("BBBBBBBBBBBBBBBBBBBB").transition(.slide)
                        }
                    }
                }
            }
        }
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.canAnimate = true
        environment.transaction = Transaction(animation: .bouncy)
        var context = RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: tui)

        func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            environment.focusManager?.beginRenderPass()
            defer {
                tui.stateStorage.endRenderPass()
                environment.focusManager?.endRenderPass()
            }
            return renderToBuffer(Paged(showing: showing), context: context)
                .compositingOverlays(
                    maxWidth: 30, maxHeight: 6, palette: environment.palette
                ).lines.map { $0.stripped }
        }
        /// Where the first `character` sits on `line`, in cells. (Stdlib
        /// rather than `range(of:)`, which is Foundation and so needs an import
        /// this package does not make on Linux.)
        func column(ofFirst character: Character, in line: String) -> Int? {
            line.firstIndex(of: character).map { line.distance(from: line.startIndex, to: $0) }
        }

        _ = draw(false, atMillis: 0)
        _ = draw(true, atMillis: 0)
        let peak = draw(true, atMillis: Self.peakMillis)
        let settled = draw(true, atMillis: 3000)
        let dialogRow = peak.firstIndex { $0.contains("AAAAAAAAAAAAAAAAAAAA") }
        #expect(dialogRow != nil, "no dialog on screen: \(peak)")
        guard let dialogRow else { return }
        // The page is padded so its bouncing row SHARES a row with the dialog —
        // without that overlap the assertion below passes with no clipping and
        // no zIndex at all, which is how the first version of this test was
        // vacuous in exactly the half it existed for. So the overlap is
        // asserted first, and then that the dialog wins the columns it occupies
        // while the page's overshoot survives only outside them.
        let sharedRow = peak.firstIndex { $0.contains("X") }
        #expect(sharedRow != nil, "the page's overshoot is not on screen: \(peak)")
        guard let sharedRow else { return }
        #expect(sharedRow == dialogRow + 1, "the two do not share a row: \(peak)")
        #expect(peak[sharedRow].contains("BBBBBBBBBBBBBBBBBBBB"),
            "the page's overshoot drew over the dialog: \(peak)")
        #expect(peak[sharedRow].hasPrefix(" XXXX"),
            "the page's overshoot lost the columns beside the dialog: \(peak)")
        // The dialog's own bouncing row draws one cell right of where it
        // settles, over cells the dialog itself painted — which only a layer
        // composited after the dialog can do.
        let peakColumn = column(ofFirst: "B", in: peak[dialogRow + 1])
        let settledColumn = column(ofFirst: "B", in: settled[dialogRow + 1])
        #expect(settledColumn != nil, "\(settled)")
        #expect(peakColumn == settledColumn.map { $0 + 1 },
            "the dialog's overshoot did not draw above it: \(peak) vs \(settled)")
    }
}
