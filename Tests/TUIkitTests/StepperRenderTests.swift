//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StepperRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Render tests for Stepper now that its label renders inline (SwiftUI parity).

import Testing

@testable import TUIkit

private final class IntBox {
    var value: Int
    init(_ value: Int) { self.value = value }
    var binding: Binding<Int> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("Stepper rendering")
struct StepperRenderTests {

    private func line(_ v: some View, w: Int = 20) -> String {
        renderToBuffer(v, context: makeRenderContext(width: w, height: 2))
            .lines.first.map { $0.stripped } ?? ""
    }

    private func mouseContext(width: Int = 20, height: Int = 2) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
    }

    @Test("A labelled stepper renders its label inline before the control")
    func labelInline() {
        let out = line(Stepper("Qty", value: .constant(5)))
        #expect(out.hasPrefix("Qty"), "got: \(out)")
        #expect(out.contains("◀") && out.contains("5") && out.contains("▶"))
    }

    @Test("An empty-label stepper has no leading space before the control")
    func emptyLabelNoLeadingSpace() {
        let out = line(Stepper("", value: .constant(5)))
        #expect(out.hasPrefix("◀"), "got: \(out)")
    }

    @Test("A range stepper still renders its label")
    func rangeLabel() {
        let out = line(Stepper("Rating", value: .constant(3), in: 1...5))
        #expect(out.hasPrefix("Rating"))
        #expect(out.contains("3"))
    }

    @Test("A labelled stepper's arrow hit-regions are offset past the label")
    func labelledArrowRegionsOffset() {
        // "Qty ◀ 5 ▶" (width 9): the inline "Qty " label is 4 cells, so the
        // control's 1-cell arrow regions sit at x=4 (◀) and x=8 (▶). If the
        // composing HStack didn't translate the control's regions, they'd land
        // under the label and clicks would miss.
        let buffer = renderToBuffer(
            Stepper("Qty", value: .constant(5), in: 0...10), context: mouseContext())
        let arrowRegions = buffer.hitTestRegions.filter { $0.width == 1 }
        #expect(arrowRegions.contains { $0.offsetX == buffer.width - 1 }, "right arrow ▶ at far right")
        #expect(arrowRegions.contains { $0.offsetX == 4 }, "left arrow ◀ just after the 'Qty ' label")
        #expect(buffer.hitTestRegions.allSatisfy { $0.offsetX >= 4 }, "no hit region under the label")
    }
}

// MARK: - Live range (bounds must track the current render)

@MainActor
@Suite("Stepper live range")
struct StepperLiveRangeTests {
    /// The persisted handler must honour the range the CURRENT render
    /// declared. It is created once and kept in state storage; only its
    /// value binding used to be refreshed each render, so a `Stepper` whose
    /// `in:` range derives from other state (the Image demo's Glyphs
    /// stepper: ceiling 2 under the blocks charset, 15 under ascii) stayed
    /// clamped to the FIRST render's range forever. Like every interaction
    /// test, this re-renders between state changes and events — the live
    /// render-loop shape.
    @Test("A range that grows between renders takes effect")
    func rangeGrowthTakesEffect() {
        let fm = FocusManager()
        let box = IntBox(2)
        var ceiling = 2
        let ctx = makeRenderContext(width: 30, height: 2) { env, _ in
            env.focusManager = fm
        }
        func render() {
            _ = renderToBuffer(
                Stepper("G", value: box.binding, in: 0...ceiling).focusID("st"), context: ctx)
        }
        render()  // the handler is created against 0...2
        ceiling = 15
        render()  // THIS render declares 0...15 — it must win
        #expect(fm.currentFocusedID == "st")
        _ = fm.currentFocused?.handleKeyEvent(KeyEvent(key: .right))
        #expect(box.value == 3, "stepping past the original ceiling, got \(box.value)")
        for _ in 0..<20 { _ = fm.currentFocused?.handleKeyEvent(KeyEvent(key: .right)) }
        #expect(box.value == 15, "pinned at the CURRENT ceiling, got \(box.value)")
    }

    @Test("A range that shrinks between renders clamps the value")
    func rangeShrinkClamps() {
        let fm = FocusManager()
        let box = IntBox(8)
        var ceiling = 15
        let ctx = makeRenderContext(width: 30, height: 2) { env, _ in
            env.focusManager = fm
        }
        func render() {
            _ = renderToBuffer(
                Stepper("G", value: box.binding, in: 0...ceiling).focusID("st"), context: ctx)
        }
        render()
        ceiling = 2
        render()  // the render-time clamp pulls the value into the new range
        #expect(box.value == 2, "clamped to the shrunken ceiling, got \(box.value)")
        _ = fm.currentFocused?.handleKeyEvent(KeyEvent(key: .right))
        #expect(box.value == 2, "cannot step past the shrunken ceiling, got \(box.value)")
    }

    @Test("A changed step size takes effect on the next press")
    func stepChangeTakesEffect() {
        let fm = FocusManager()
        let box = IntBox(0)
        var step = 1
        let ctx = makeRenderContext(width: 30, height: 2) { env, _ in
            env.focusManager = fm
        }
        func render() {
            _ = renderToBuffer(
                Stepper("G", value: box.binding, in: 0...100, step: step).focusID("st"),
                context: ctx)
        }
        render()
        _ = fm.currentFocused?.handleKeyEvent(KeyEvent(key: .right))
        #expect(box.value == 1)
        step = 10
        render()
        _ = fm.currentFocused?.handleKeyEvent(KeyEvent(key: .right))
        #expect(box.value == 11, "the current render's step applies, got \(box.value)")
    }
}
