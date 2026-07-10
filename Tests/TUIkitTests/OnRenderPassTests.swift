//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OnRenderPassTests.swift
//
//  `.onRenderPass(_:)` — the instrumentation hook reporting a view's
//  participation in measurement vs real rendering. Pins the property the
//  Layout demo displays: a windowed LazyVStack MEASURES rows it never draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("onRenderPass instrumentation")
struct OnRenderPassTests {

    @Test("A real render reports .render (and sizing reports .measure)")
    func reportsRenderAndMeasure() {
        final class Box { var passes: [RenderPass] = [] }
        let box = Box()
        let view = Text("hello").onRenderPass { box.passes.append($0) }
        _ = renderToBuffer(view, context: makeRenderContext(width: 20, height: 3))

        #expect(box.passes.contains(.render), "the view was really drawn")
        #expect(!box.passes.isEmpty)
    }

    @Test("A measuring context reports only .measure")
    func measuringReportsMeasureOnly() {
        final class Box { var passes: [RenderPass] = [] }
        let box = Box()
        let view = Text("hello").onRenderPass { box.passes.append($0) }
        var context = makeRenderContext(width: 20, height: 3)
        context.isMeasuring = true
        _ = renderToBuffer(view, context: context)

        #expect(!box.passes.isEmpty, "measurement observed")
        #expect(!box.passes.contains(.render), "nothing was actually drawn")
    }

    @Test("A windowed LazyVStack measures rows it never renders")
    func lazyStackMeasuresMoreThanItRenders() {
        final class Box {
            var measured: Set<Int> = []
            var rendered: Set<Int> = []
        }
        let box = Box()

        // 40 one-line rows in an 8-line viewport: only ~8 can render.
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { index in
                    Text("Row \(index)")
                        .onRenderPass { pass in
                            switch pass {
                            case .measure: box.measured.insert(index)
                            case .render: box.rendered.insert(index)
                            }
                        }
                }
            }
        }
        .frame(height: 8)

        _ = renderToBuffer(view, context: makeRenderContext(width: 24, height: 12))

        #expect(!box.rendered.isEmpty, "some rows drew")
        #expect(box.rendered.count < 40, "windowing: not every row renders")
        #expect(
            box.rendered.isSubset(of: box.measured),
            "everything drawn was first measured: rendered \(box.rendered.sorted()), measured \(box.measured.sorted())")
        #expect(
            box.measured.count > box.rendered.count,
            "layout touches rows the window never draws (the demo's premise): measured \(box.measured.count) vs rendered \(box.rendered.count)")
    }
}
