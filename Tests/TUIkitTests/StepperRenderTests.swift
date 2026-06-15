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
            environment.stateStorage = tui.stateStorage
            environment.lifecycle = tui.lifecycle
            environment.keyEventDispatcher = tui.keyEventDispatcher
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.renderCache = tui.renderCache
            environment.preferenceStorage = tui.preferences
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
