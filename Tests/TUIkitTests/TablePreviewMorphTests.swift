//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TablePreviewMorphTests.swift
//
//  A carried Table row is not a slice of the grid: its cells are clipped to
//  their columns and joined by two spaces, where the grid pads every cell out
//  to its column's width. That difference used to happen between two frames, so
//  the cells jumped. These measure that it now travels — and, more importantly,
//  that both ends of the travel line up with what is on screen either side of
//  it, which is the only way the jump is actually gone rather than moved.
//
//  Its own fixture rather than ``TableReorderFixture``'s: that one has a single
//  column, and a single column has no gaps to close.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct MorphRow: Identifiable, Sendable {
    let id: String
    let qty: String
}

@MainActor
@Suite("Table preview morph")
struct TablePreviewMorphTests {

    private let rows = [
        MorphRow(id: "alpha", qty: "1"),
        MorphRow(id: "beta", qty: "22"),
        MorphRow(id: "gamma", qty: "333"),
    ]

    /// A three-row, two-column table with `onMove`, rendered through the real
    /// dispatcher.
    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()
        var order: [MorphRow]

        init(_ rows: [MorphRow]) {
            order = rows
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            env.rowReorderFeedback = .cursor
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let table = Table(order, selection: .constant(String?.none)) {
                TableColumn<MorphRow>("Name", value: \.id)
                TableColumn<MorphRow>("Qty", value: \.qty)
            }
            .onMove { from, to in self.order.move(fromOffsets: from, toOffset: to) }
            var context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(table.frame(width: 30, height: 10), context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.contains(label) && !$0.contains("Name") } ?? -1
        }
    }

    /// The columns each run of ink occupies in a line — the geometry both ends
    /// of the travel have to agree with.
    private func inkRuns(_ line: String) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        let cells = Array(line.stripped)
        for (index, cell) in cells.enumerated() {
            if cell == " " {
                if let from = start { runs.append(from..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let from = start { runs.append(from..<cells.count) }
        return runs
    }

    /// The ink runs of a rendered ROW line, in the row's own space: the
    /// container's border and padding taken off the front, and the border at
    /// the end dropped, so what is left lines up with a carried row's line.
    ///
    /// Two cells, which is `contentColumns.lowerBound + containerPadding.leading`
    /// — the same offset the reorder grab point is measured from.
    private func rowCellRuns(_ line: String) -> [Range<Int>] {
        let width = line.stripped.count
        return inkRuns(line)
            .filter { $0.lowerBound >= 2 && $0.upperBound <= width - 1 }
            .map { ($0.lowerBound - 2)..<($0.upperBound - 2) }
    }

    /// Opens a `.cursor` drag on `label` and answers the session driving it.
    private func dragging(_ fixture: Fixture, _ label: String) -> (
        session: DragAndDropSession, rowLine: String
    ) {
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, label)
        let rowLine = buffer.lines[y]
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: y + 2))
        fixture.render()
        return (fixture.tui.dragAndDropSession, rowLine)
    }

    @Test("The travel starts as the row was drawn and ends condensed")
    func theTravelSpansBothLayouts() {
        let fixture = Fixture(rows)
        let (session, rowLine) = dragging(fixture, "gamma")
        guard let drag = session.active, !drag.morph.isEmpty else {
            Issue.record("a cursor drag on a Table must carry a travel")
            return
        }

        // Frame 0 IS the row's own layout, so nothing shifts on the frame the
        // picture appears — it lands exactly on the hole the table just opened.
        let first = drag.morph.first!.lines.first ?? ""
        #expect(
            inkRuns(first) == rowCellRuns(rowLine),
            "frame 0 does not match the row: \(first.stripped) vs \(rowLine.stripped)")

        // …and the last is the hand layout: the same cells, closed up.
        let last = drag.morph.last!.lines.first ?? ""
        let lastRuns = inkRuns(last)
        #expect(lastRuns.count == rowCellRuns(rowLine).count, "same cells: \(last.stripped)")
        #expect(
            lastRuns.last!.upperBound < rowCellRuns(rowLine).last!.upperBound,
            "the cells did not close up: \(last.stripped)")
        // Two cells between them, which is what a carried row joins with.
        for (left, right) in zip(lastRuns, lastRuns.dropFirst()) {
            #expect(right.lowerBound - left.upperBound == 2, "\(last.stripped)")
        }

        // The steady picture and the end of the travel are the same thing —
        // they have to be, or the cells jump the moment the lift finishes.
        #expect(drag.preview.lines == drag.morph.last!.lines)
    }

    @Test("The picture painted during the lift walks the travel")
    func theLiftWalksTheTravel() {
        let fixture = Fixture(rows)
        let (session, _) = dragging(fixture, "gamma")
        let atStart = session.liftedPreviewContent()?.lines.first ?? ""
        session.driveLift(nowNanos: 0)
        session.driveLift(nowNanos: DragAndDropSession.ActiveDrag.liftDurationNanos / 2)
        let midway = session.liftedPreviewContent()?.lines.first ?? ""
        session.driveLift(nowNanos: DragAndDropSession.ActiveDrag.liftDurationNanos)
        let atEnd = session.liftedPreviewContent()?.lines.first ?? ""

        #expect(atStart != midway, "the picture did not move off the row's layout")
        #expect(midway != atEnd, "the picture did not finish closing up")
        #expect(inkRuns(atStart).last!.upperBound > inkRuns(atEnd).last!.upperBound)
    }

    @Test("A dropped row's cells spread back out, and the row waits for them")
    func theDropSettles() {
        let fixture = Fixture(rows)
        let buffer = fixture.render()
        let yGamma = fixture.rowY(buffer, "gamma")
        let yAlpha = fixture.rowY(buffer, "alpha")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yGamma))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yAlpha))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yAlpha))

        let session = fixture.tui.dragAndDropSession
        guard let flight = session.returnFlight else {
            Issue.record("a successful drop must settle its picture")
            return
        }
        // In place: the slot is at the pointer and so is the picture.
        #expect(flight.fromX == flight.toX && flight.fromY == flight.toY)

        // Condensed first, grid last — the travel played backward.
        let start = session.driveReturnFlight(nowNanos: 0)!
        #expect(start.preview.lines == flight.morph.last!.lines, "it did not start in the hand")

        // The row it is becoming draws nothing while it becomes it.
        let flying = fixture.render()
        #expect(
            !flying.lines.contains { $0.stripped.contains("gamma") },
            "the row is on screen twice: \(flying.lines.map(\.stripped))")

        _ = session.driveReturnFlight(
            nowNanos: DragAndDropSession.ReturnFlight.durationNanos)
        let landed = fixture.render()
        let row = landed.lines.first { $0.stripped.contains("gamma") }
        #expect(row != nil, "the row never came back")
        // And it came back where the last frame of the travel had put the
        // cells — which is the whole point: nothing jumps at the handoff.
        #expect(rowCellRuns(row ?? "") == inkRuns(flight.morph.first!.lines.first ?? ""))
    }
}
