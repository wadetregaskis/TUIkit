//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyStackGuideMeasureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A windowed stack must measure the width its alignment guides make it draw.
///
/// An explicit `.alignmentGuide` moves a row off the alignment line, and the
/// run that resolves it is allowed to come out WIDER than the widest row —
/// which is why the render places every buffer into `run.extent` rather than
/// into the widest child. The windowed MEASURE reported the widest child and
/// nothing else, so the two disagreed and the parent clipped the difference.
///
/// Both stacks, deliberately. This project records `_VStackCore` and
/// `_HStackCore` as twins that implement the same rules twice and drift, and
/// this defect was present in both.
@MainActor
@Suite("A windowed stack measures the extent its guides draw")
struct LazyStackGuideMeasureTests {

    /// The stack itself, with a window in the environment so it takes the
    /// WINDOWED path rather than the eager one.
    ///
    /// Not wrapped in a `ScrollView`: that would make the scroll view the
    /// subject, and a scroll view fills the width it is offered, so both
    /// numbers come back as the viewport and the comparison proves nothing.
    /// The first version of this file did that and its no-guide control case
    /// failed, which is how it was caught.
    private func measuredAndRendered(
        _ view: some View, width: Int, height: Int
    ) -> (measured: ViewSize, rendered: FrameBuffer) {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.scrollContentWindow = ScrollContentWindow(
                offset: 0, viewportHeight: height)
        }
        return (
            measureChild(view, proposal: .unspecified, context: context),
            renderToBuffer(view, context: context)
        )
    }

    /// How far the drawn INK reaches, which is what a width measure has to
    /// agree with. `FrameBuffer.width` is no use here: a windowed stack pads
    /// its lines out to the viewport, so it reads 40 whatever the content did.
    private func inkWidth(_ buffer: FrameBuffer) -> Int {
        buffer.lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.reversed().prefix(while: { $0 == " " }).count
        }.max() ?? 0
    }

    @Test("LazyVStack: a guide that widens the run is measured, not just drawn")
    func verticalGuideRunIsMeasured() {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            Text("aaaa")
            // Pushed right of the alignment line: the run has to be wider
            // than any single row to hold both.
            Text("bbbb").alignmentGuide(.leading) { _ in -6 }
            Text("cc")
        }
        let (measured, rendered) = measuredAndRendered(view, width: 40, height: 10)
        // The guide pushes "bbbb" clear of the alignment line, so the ink
        // reaches further than the widest row (4) on its own.
        #expect(inkWidth(rendered) > 4, "the guide did not widen the drawn run")
        #expect(
            measured.width == inkWidth(rendered),
            "measured \(measured.width) but drew \(inkWidth(rendered))")
    }

    @Test("LazyHStack: a guide that heightens the run is measured, not just drawn")
    func horizontalGuideRunIsMeasured() {
        let view = LazyHStack(alignment: .top, spacing: 0) {
            Text("a")
            Text("b").alignmentGuide(.top) { _ in -4 }
            Text("c")
        }
        let (measured, rendered) = measuredAndRendered(view, width: 40, height: 12)
        #expect(
            measured.height == rendered.lines.count,
            "measured \(measured.height) but drew \(rendered.lines.count)")
    }

    /// The far commoner case, and the one the fix must not disturb: with no
    /// explicit guide anywhere, the run is never built and the answer is the
    /// widest row exactly as before.
    @Test("Without a guide the measure is unchanged")
    func withoutGuidesNothingChanges() {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            Text("aaaa")
            Text("bb")
        }
        let (measured, rendered) = measuredAndRendered(view, width: 40, height: 10)
        #expect(measured.width == inkWidth(rendered))
        #expect(measured.width == 4, "the widest row, not the run: \(measured.width)")
    }
}
