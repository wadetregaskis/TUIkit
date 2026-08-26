//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasureEnvironmentResolutionTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A composite view whose *shape* depends on an `@Environment` value, so a
/// measure that resolved the environment differently from the render would
/// produce a different size — not merely different pixels.
private struct WidthBranchingView: View {
    @Environment(\.terminalWidth) private var terminalWidth

    var body: some View {
        if terminalWidth >= 100 {
            Text("wide")
        } else {
            VStack(spacing: 0) {
                Text("narrow")
                Text("second line")
            }
        }
    }
}

/// `@Environment` inside a composite view must resolve the same way on the
/// measure walk as on the render walk.
///
/// It did not. The measure path published the environment as a task local for
/// the `@Environment` *fallback* to find, but never filled the wrapper's box —
/// so a read that consulted its box got the framework default. `\.terminalWidth`
/// answered 80 whatever the terminal was, and a view branching on it measured
/// the subtree it would have rendered at 80 columns.
///
/// Both walks now run the same `resolveEnvironmentProperties`, which is also
/// what let the task local come off the two hottest paths in the framework.
@MainActor
@Suite("Measure-time environment resolution")
struct MeasureEnvironmentResolutionTests {

    private func context(terminalWidth: Int) -> RenderContext {
        makeRenderContext(width: terminalWidth, height: 24) { environment, _ in
            environment.terminalWidth = terminalWidth
        }
    }

    @Test("A view branching on the environment measures the branch it renders")
    func measureMatchesRenderAcrossTheBranch() {
        for width in [80, 120] {
            let context = self.context(terminalWidth: width)
            let measured = measureChild(
                WidthBranchingView(),
                proposal: ProposedSize(width: nil, height: nil),
                context: context)
            let rendered = renderToBuffer(WidthBranchingView(), context: context)

            #expect(
                measured.height == rendered.lines.count,
                "measure and render must agree at terminalWidth \(width)")
        }
    }

    @Test("The two branches really do differ, so the test above can fail")
    func theBranchesDiffer() {
        // Without this the assertion above would hold vacuously if both branches
        // happened to be the same height.
        let narrow = renderToBuffer(WidthBranchingView(), context: context(terminalWidth: 80))
        let wide = renderToBuffer(WidthBranchingView(), context: context(terminalWidth: 120))
        #expect(narrow.lines.count != wide.lines.count)
    }

    @Test("Measuring resolves the box, not just the fallback")
    func measureFillsTheEnvironmentBox() {
        // The distinction that matters: reading through the *box* is what a
        // closure captured from `body` does, and what `wrappedValue` prefers.
        let view = WidthBranchingView()
        let context = self.context(terminalWidth: 120)
        _ = measureChild(view, proposal: ProposedSize(width: nil, height: nil), context: context)

        var boxed: Int?
        for child in Mirror(reflecting: view).children {
            if let environment = child.value as? Environment<Int> {
                boxed = environment.wrappedValue
            }
        }
        #expect(boxed == 120, "the measure pass must fill the @Environment box, not only a fallback")
    }
}
