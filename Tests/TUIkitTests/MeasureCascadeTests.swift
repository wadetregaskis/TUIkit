//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MeasureCascadeTests.swift
//
//  Regression guards for GitHub issue #7 ("Immense CPU resource consumption"):
//  the layout cascade must not multiply passes over a subtree. The frame
//  modifier used to measure by rendering its subtree twice (natural + probe),
//  and because ancestors measure a child both in their own sizeThatFits and
//  again in their render pass, nested `.frame`s compounded that into 15 full
//  subtree renders and 29 leaf measures per frame for the issue's layout —
//  ~18 ms per idle pulse frame on a fast machine, 70–90% of a core at 10 Hz
//  on the reporter's. With the frame measuring analytically the same leaf
//  sees one render and a handful of cheap measures.
//
//  These tests count actual passes through a probe leaf — deterministic, no
//  wall-clock — so a regression in the measure cascade fails loudly and
//  precisely.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Pass-counting probe

@MainActor
private final class PassCounter {
    var renders = 0
    var measures = 0
    func reset() {
        renders = 0
        measures = 0
    }
}

private struct CountingProbe: View, Renderable, Layoutable {
    let counter: PassCounter

    var body: Never { fatalError("probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if context.isMeasuring {
            counter.measures += 1
        } else {
            counter.renders += 1
        }
        return FrameBuffer(text: "PROBE")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        counter.measures += 1
        return ViewSize.fixed(5, 1)
    }
}

@MainActor
@Suite("Measure cascade pass counts (issue #7)")
struct MeasureCascadeTests {
    /// Renders one settled frame (after warm-up frames for focus registration
    /// and caches) and returns the probe's per-frame pass counts.
    private func passCounts<V: View>(
        _ counter: PassCounter, _ view: V, width: Int = 100, height: Int = 32
    ) -> (renders: Int, measures: Int) {
        let context = makeRenderContext(width: width, height: height)
        for _ in 0..<2 { _ = renderToBuffer(view, context: context) }
        counter.reset()
        _ = renderToBuffer(view, context: context)
        return (counter.renders, counter.measures)
    }

    @Test("A framed leaf is not re-measured by rendering")
    func framedLeafMeasuresOnce() {
        let counter = PassCounter()
        let view = VStack {
            Card(title: "T") { CountingProbe(counter: counter) }.frame(height: 8)
            Spacer()
        }.frame(width: 30)

        let passes = passCounts(counter, view)
        #expect(passes.renders == 1, "one real render per frame, got \(passes.renders)")
        #expect(
            passes.measures <= 3,
            "nested frames must not multiply measures (was 29 pre-fix), got \(passes.measures)")
    }

    @Test("The issue's nested layout visits a leaf O(depth) times, not O(2^depth)")
    func issueShapePassCounts() {
        let counter = PassCounter()
        // The issue's shape: framed columns in an HStack under an outer VStack,
        // with a List sibling and a Panel column — the probe sits where the
        // toggle rows were.
        let view = VStack {
            Text("Hello, TUIkit!")
            Text("Welcome")
            HStack {
                Button("A") {}
                Button("B") {}
            }.padding()
            HStack {
                VStack {
                    List("Customer", selection: .constant(String?.none)) { Text("Harry") }
                        .frame(height: 5)
                    Card(title: "Item List", padding: .init(horizontal: 1)) {
                        VStack(spacing: 0) { CountingProbe(counter: counter) }
                    }
                    .frame(height: 8)
                    Spacer()
                }
                .frame(width: 30)
                VStack {
                    Panel("Log", padding: EdgeInsets(horizontal: 1)) {
                        ScrollView(showsIndicators: true) {
                            VStack(alignment: .leading) { Text("a") }
                        }
                    }
                }
            }
        }.padding()

        let passes = passCounts(counter, view)
        #expect(passes.renders == 1, "one real render per frame, got \(passes.renders)")
        #expect(
            passes.measures <= 8,
            "the cascade must stay linear in nesting depth (was 29 pre-fix), got \(passes.measures)")
    }
}
