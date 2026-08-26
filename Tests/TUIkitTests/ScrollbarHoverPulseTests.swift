//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarHoverPulseTests.swift
//
//  A focused scrollbar breathes through the run loop, and the cell under the
//  pointer is lifted a step further. Those two facts have to agree: the runs
//  ARE the bar from the first tick onward, so a run built without the hover
//  paints the lift away and it never comes back while the pointer sits there.
//
//  The cell under the pointer is by construction a thumb or an arrow — exactly
//  the cells that earn a run — so this is not an edge case, it is the whole of
//  what hovering a scrollbar looks like.
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

        // Hover a cell that ACTUALLY earns a run: that is the claim under test
        // — the cells the pointer can meaningfully land on are the cells the
        // run loop repaints.
        guard let target = plain.animatedCells.first else {
            Issue.record("a focused bar hands over animated rows; got none")
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
}
