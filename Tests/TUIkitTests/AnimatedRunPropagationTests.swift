//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedRunPropagationTests.swift
//
//  A run only earns its keep if it reaches the FINAL composited buffer. The run
//  loop keeps the animation clock alive on the strength of the runs it finds
//  there, so a run dropped on the way up does not merely fail to animate — it
//  takes the clock down with it and FREEZES the indicator, while the CPU graph
//  reads as a total win. That happened (commit 47aa5420); these are the tests
//  that would have caught it.
//
//  The existing FrameBuffer tests cover its own stacking and compositing. These
//  cover the journey: a control's buffer through the kind of tree a real page
//  actually builds around it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A leaf that draws two cells and declares them animated — the shape of every
/// focus indicator in the framework, with nothing else going on.
private struct AnimatedProbe: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }

    static let frames = ["ab", "cd", "ef"]

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [Self.frames[0]])
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 2, frames: Self.frames, clock: .cursor)
        ]
        return buffer
    }
}

@MainActor
@Suite("Animated run propagation")
struct AnimatedRunPropagationTests {

    private func runs<V: View>(of view: V, width: Int = 40, height: Int = 12)
        -> [AnimatedCellRun]
    {
        TUIkit.renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .animatedCells
    }

    @Test("A bare probe carries its own run")
    func bareProbe() {
        // The control, so a failure below is about the tree and not the probe.
        #expect(runs(of: AnimatedProbe()).count == 1)
    }

    @Test("A run survives padding")
    func throughPadding() {
        let found = runs(of: AnimatedProbe().padding())
        #expect(found.count == 1, "padding dropped the run")
        // Padding insets the content, so the run has to move with its cells.
        #expect(found.first?.offsetX ?? 0 > 0)
        #expect(found.first?.offsetY ?? 0 > 0)
    }

    @Test("A run survives a border")
    func throughBorder() {
        #expect(runs(of: AnimatedProbe().border()).count == 1, "border dropped the run")
    }

    @Test("A run survives being stacked with siblings")
    func throughStacks() {
        let stacked = VStack {
            Text("above")
            HStack {
                Text("left")
                AnimatedProbe()
            }
            Text("below")
        }
        let found = runs(of: stacked)
        #expect(found.count == 1, "stacking dropped the run")
        // One row down (past "above") and to the right of "left".
        #expect(found.first?.offsetY == 1)
        #expect(found.first?.offsetX ?? 0 >= 4)
    }

    @Test("A run survives a ScrollView")
    func throughScrollView() {
        // The hardest crossing: a ScrollView renders its content to a full
        // buffer and then windows it, which is exactly the kind of rebuild that
        // used to lose runs.
        let scrolled = ScrollView {
            VStack {
                ForEach(0..<3, id: \.self) { _ in Text("filler") }
                AnimatedProbe()
            }
        }
        #expect(runs(of: scrolled).count == 1, "the ScrollView dropped the run")
    }

    @Test("A run survives the whole realistic stack at once")
    func throughEverything() {
        // What a page actually looks like around a focused control.
        let page = ScrollView {
            VStack {
                Text("header")
                HStack {
                    Text("label")
                    AnimatedProbe().padding(.horizontal, 1)
                }
                .border()
                .padding()
            }
        }
        let found = runs(of: page)
        #expect(found.count == 1, "the run did not reach the root")
        // Its position must be absolute in the final buffer, not still relative
        // to the control — a run at the wrong coordinates repaints the wrong
        // cells on a clock, which is worse than not animating.
        #expect(found.first?.offsetX ?? 0 > 1)
        #expect(found.first?.offsetY ?? 0 > 0)
    }
}
