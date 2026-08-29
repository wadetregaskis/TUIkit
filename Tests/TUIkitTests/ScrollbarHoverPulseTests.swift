//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarHoverPulseTests.swift
//
//  A focused scrollbar breathes through the run loop, and the cell under the
//  pointer is lifted a step further. Those two facts have to agree: the runs
//  ARE the bar from the first tick onward, so a run built without the hover
//  paints the lift away and it never comes back while the pointer sits there.
//
//  The lift is the ARROWS' alone. A thumb is drawn as a filled cell background
//  rather than a glyph, so lifting the one cell under the pointer put a
//  brighter block in the middle of a solid bar and read as a block cursor
//  parked on the scroller; an arrow is a single cell and IS its own control.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A hovered scrollbar cell keeps its lift while the bar pulses")
struct ScrollbarHoverPulseTests {

    /// A focused, overflowing ScrollView with a visible bar, rendered through
    /// the real mouse dispatcher so hover arrives the way it does in an app.
    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100, id: \.self) { Text("L\($0)") }
                }
            }
            .scrollIndicators(.visible)
            .scrollIndicatorStyle(.scrollbar)
            .frame(width: 12, height: 8)
        }

        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 12, availableHeight: 8,
                environment: environment, tuiContext: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            tui.mouseEventDispatcher.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(body, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// Renders until the ScrollView has measured its content — the first
        /// pass reports extent == viewport, so its bar is an inert gutter.
        func settled() -> FrameBuffer {
            _ = frame()
            return frame()
        }

        func movePointer(to point: (x: Int, y: Int)) {
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
        }
    }

    @Test("The pointer lifts the cell it is on, and the pulse does not undo it")
    func hoverSurvivesTheReplay() {
        let harness = Harness()
        let plain = harness.settled()
        let barColumn = plain.width - 1

        // The leading arrow: a cell that earns a run AND takes the lift, which
        // is the pair of facts under test.
        guard let target = plain.animatedCells.first(where: { $0.offsetY == 0 }) else {
            Issue.record("a focused bar hands over an animated arrow row; got none")
            return
        }
        let row = target.offsetY

        harness.movePointer(to: (x: barColumn, y: row))
        let hovered = harness.frame()

        // The static draw answers the pointer. Without this the rest of the
        // test could pass by the hover never having registered at all.
        // Raw lines, SGR bytes and all: the styling is the whole of what this
        // is about. Only the bar cell can differ — the content either side of
        // this render is the same text at the same scroll offset.
        #expect(
            hovered.lines[row] != plain.lines[row],
            "the pointer did not lift the cell it is on")

        guard let run = hovered.animatedCells.first(where: { $0.offsetY == row }) else {
            Issue.record("the hovered row stopped animating")
            return
        }
        // Every frame, not just the first: the pointer is still there for the
        // whole breath, so every picture of that cell owes it the lift.
        #expect(
            run.frames != target.frames,
            "the run replays the un-hovered cell, so the first tick wipes the lift")
    }

    @Test("Rows the pointer is not on are unaffected")
    func hoverIsLocal() {
        let harness = Harness()
        let plain = harness.settled()
        let barColumn = plain.width - 1
        guard let target = plain.animatedCells.first,
            let other = plain.animatedCells.first(where: { $0.offsetY != target.offsetY })
        else {
            Issue.record("expected at least two animated rows on the bar")
            return
        }

        harness.movePointer(to: (x: barColumn, y: target.offsetY))
        let hovered = harness.frame()

        #expect(
            hovered.animatedCells.first(where: { $0.offsetY == other.offsetY })?.frames
                == other.frames,
            "a row the pointer is not on changed")
    }

    /// The thumb does not answer the pointer, and that is the fix rather than
    /// an omission.
    ///
    /// It is drawn as a filled cell background, so the one-cell lift landed as
    /// a brighter block sitting in the middle of a solid bar — a block cursor
    /// on the scroller, which is what it was reported as. An arrow is a single
    /// cell and is the whole of its own control, so it keeps the lift.
    @Test("The pointer does not put a bright cell on the thumb")
    func hoveringTheThumbChangesNothing() {
        let harness = Harness()
        let plain = harness.settled()
        let barColumn = plain.width - 1

        // Every row that is not an arrow. The thumb is the point of this test
        // and it is ONE cell here (100 rows in a viewport of eight), so a range
        // chosen to be safely clear of the ends skips the only row that can
        // fail — a track cell is drawn from `track` and never took the lift
        // even before the fix, so a test that hovers only track passes on
        // broken code. It did.
        let interior = 1..<(plain.lines.count - 1)
        var offenders: [Int] = []
        for row in interior {
            harness.movePointer(to: (x: barColumn, y: row))
            if harness.frame().lines[row] != plain.lines[row] { offenders.append(row) }
        }
        #expect(
            offenders.isEmpty,
            "the pointer lifted a track/thumb cell on rows \(offenders)")
    }
}
