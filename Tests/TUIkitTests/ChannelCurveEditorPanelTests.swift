//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChannelCurveEditorPanelTests.swift
//
//  The plot IS the editor's claim: filled height equals the value the ramp
//  gives at that column. These measure that off the rendered buffer, plus the
//  two behaviours that make the thing usable rather than merely correct.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitImage

@testable import TUIkit

@MainActor
@Suite("Channel curve editor")
struct ChannelCurveEditorPanelTests {

    private typealias Panel = ChannelCurveEditorPanel
    private typealias Ramp = ASCIIToneCurve.Ramp
    private typealias Point = ASCIIToneCurve.Ramp.Point

    /// The panel rendered with `channels`, as stripped lines.
    private func lines(_ channels: ASCIIToneCurve.Channels, context: RenderContext) -> [String] {
        let panel = ChannelCurveEditorPanel(
            "Channel curves", channels: .constant(channels), isPresented: .constant(true))
        _ = renderToBuffer(panel, context: context)
        return renderToBuffer(panel, context: context).lines.map(\.stripped)
    }

    @Test("A column and its input are inverses")
    func columnsAndInputsAgree() {
        #expect(Panel.column(forInput: 0) == 0)
        #expect(Panel.input(atColumn: 0) == 0)
        #expect(Panel.input(atColumn: Panel.column(forInput: 1)) == 1)
        for column in 0..<12 {
            #expect(Panel.column(forInput: Panel.input(atColumn: column)) == column)
        }
    }

    @Test("The plot's filled height is the ramp's value at that column")
    func plotDrawsTheRamp() {
        let rows = Panel.plotRows(for: .identity)
        #expect(rows.count == Panel.plotHeight)
        #expect(rows.allSatisfy { $0.count == Panel.plotWidth })
        // Identity: nothing at the left edge, everything at the right. Read off
        // the ends, which is where the claim is unambiguous — a partial glyph
        // in between would be asserting the sub-cell rounding rather than the
        // mapping.
        for (index, row) in rows.enumerated() {
            #expect(row.first == " ", "row \(index) is not empty at input 0: \(row)")
            #expect(row.last == "█", "row \(index) is not full at input 1: \(row)")
        }
        // A step function is the sharpest case: everything below the step is
        // empty, everything above it full.
        let step = Panel.plotRows(for: [(0, 0), (0.499, 0), (0.5, 1), (1, 1)])
        for row in step {
            #expect(row.prefix(Panel.plotWidth / 2).allSatisfy { $0 == " " }, "\(row)")
            #expect(row.suffix(Panel.plotWidth / 2).allSatisfy { $0 == "█" }, "\(row)")
        }
    }

    @Test("An inverted ramp draws the mirror of the identity one")
    func invertedMirrorsIdentity() {
        let identity = Panel.plotRows(for: .identity)
        let inverted = Panel.plotRows(for: .inverted)
        // Mirrored in the COLUMNS only, row for row: identity is f(x) = x and
        // inverted is g(x) = 1 - x, so g(x) = f(1 - x) and reflecting
        // horizontally is the whole of the difference. (Reflecting vertically
        // as well would map it straight back to identity — which is why this
        // assertion has to name the axis rather than say "mirrored".)
        for (row, mirrored) in zip(identity, inverted) {
            #expect(String(row.reversed()) == mirrored, "\(row) vs \(mirrored)")
        }
    }

    @Test("The panel draws the rows the plot function produces")
    func theViewDrawsThePlot() {
        // Ties the function above to the view: without this the plot could be
        // exactly right and never reach the screen.
        let rendered = lines(.identity, context: makeRenderContext(width: 90, height: 60))
        for row in Panel.plotRows(for: .identity) {
            #expect(
                rendered.contains { $0.contains(row) },
                "the plot row is not on screen: \(row)")
        }
    }

    @Test("Moving a point moves its marker, in the same render pass")
    func markersFollowThePoints() {
        // The `ForEach`-over-indices memo trap, which this panel's plot and
        // marker row would both have had if they looped over column numbers.
        let context = makeRenderContext(width: 90, height: 60)
        func markerColumns(_ ramp: Ramp) -> [Int] {
            let rendered = lines(ASCIIToneCurve.Channels(red: ramp, green: .identity, blue: .identity), context: context)
            guard let row = rendered.first(where: { $0.contains(TerminalSymbols.toneCurveStop) })
            else { return [] }
            return row.enumerated()
                .filter { String($0.element) == TerminalSymbols.toneCurveStop }
                .map(\.offset)
        }
        let before = markerColumns([(0, 0), (0.3, 0.5), (1, 1)])
        let after = markerColumns([(0, 0), (0.8, 0.5), (1, 1)])
        #expect(!before.isEmpty && !after.isEmpty)
        #expect(before != after, "the marker row did not follow the points: \(before)")
    }

    @Test("Adding a point changes nothing about the ramp")
    func addingAPointIsInert() {
        let points: [Point] = [.init(input: 0, output: 0.2), .init(input: 1, output: 0.9)]
        let (updated, index) = Panel.adding(to: points, after: 0)
        #expect(updated.count == 3)
        #expect(index == 1, "the new point is the one selected")
        let before = Ramp(points)
        let after = Ramp(updated)
        for step in 0...20 {
            let input = Double(step) / 20
            #expect(abs(before.value(at: input) - after.value(at: input)) < 1e-9, "at \(input)")
        }
    }

    @Test("Adding on the last point falls back INTO the ramp")
    func addingOnTheLastPoint() {
        let points: [Point] = [.init(input: 0, output: 0), .init(input: 1, output: 1)]
        let (updated, index) = Panel.adding(to: points, after: 1)
        #expect(updated.count == 3)
        #expect(updated[index].input < 1, "landed on top of the last point")
        #expect(updated[index].input > 0, "landed on top of the first")
        #expect(updated.map(\.input) == updated.map(\.input).sorted())
    }

    // MARK: - The pointer

    /// A frame of the panel driven the way the run loop drives one: render,
    /// publish the regions the render produced, then dispatch. The buffer is
    /// the root here, so its region offsets ARE screen coordinates.
    @MainActor
    private struct Harness {
        let panel: ChannelCurveEditorPanel
        let context: RenderContext
        let dispatcher: MouseEventDispatcher

        @discardableResult
        func frame() -> [String] {
            let buffer = renderToBuffer(panel, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer.lines.map(\.stripped)
        }

        /// The screen position of the plot's `(column, row)` cell, found from
        /// the rendered picture rather than computed: the panel is centred
        /// inside a dialog inside whatever the context proposes, and a test
        /// that did that arithmetic itself would be testing its own copy of it.
        func plotOrigin(_ lines: [String]) -> (x: Int, y: Int)? {
            // The identity ramp's top plot row is empty until its very last
            // cells, so the marker row is the reliable landmark: it is the
            // first row carrying the stop glyph.
            guard
                let markerRow = lines.firstIndex(where: {
                    $0.contains(TerminalSymbols.toneCurveStop)
                }),
                let line = lines.first(where: { $0.contains(TerminalSymbols.toneCurveStop) }),
                let mark = line.range(of: TerminalSymbols.toneCurveStop)
            else { return nil }
            let x = line.distance(from: line.startIndex, to: mark.lowerBound)
            // The marker row sits directly under the plot's last row.
            return (x: x, y: markerRow - Panel.plotHeight)
        }
    }

    private func harness(_ channels: Binding<ASCIIToneCurve.Channels>) -> Harness {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 90, availableHeight: 60, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        tui.mouseEventDispatcher.setActiveSupport(.standard)
        return Harness(
            panel: ChannelCurveEditorPanel(
                "Channel curves", channels: channels, isPresented: .constant(true)),
            context: context,
            dispatcher: tui.mouseEventDispatcher)
    }

    /// The gesture the whole thing exists for: press on the chart, drag, and
    /// the curve follows. Driven through the real dispatcher against the real
    /// regions, so a wrong offset — the caption gutter, the dialog's border,
    /// the centring — fails here and not only on screen.
    @Test("Dragging on the plot moves a point in both axes")
    func draggingThePlotMovesAPoint() {
        var channels = ASCIIToneCurve.Channels(red: .identity, green: .identity, blue: .identity)
        let harness = harness(Binding(get: { channels }, set: { channels = $0 }))
        let lines = harness.frame()
        guard let origin = harness.plotOrigin(lines) else {
            Issue.record("the plot did not render")
            return
        }
        // Grab the identity ramp's first point — input 0, output 0, so the
        // bottom-left cell — and take it to the top of the plot.
        let left = origin.x
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: left, y: origin.y + Panel.plotHeight - 1))
        harness.frame()
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: left, y: origin.y))
        #expect(
            channels.red.points.first?.output == 1,
            "the point did not follow the drag: \(channels.red.points)")
        #expect(channels.red.points.first?.input == 0, "it moved sideways too")
        harness.frame()
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: left, y: origin.y))
        #expect(channels.red.points.count == 2, "the drag added a point instead of moving one")
    }

    /// The other half: a press where there is no point puts one there, so
    /// "click the tone you want to change and drag it" is one gesture.
    @Test("Pressing empty chart adds a point at that input and output")
    func pressingEmptyChartAddsAPoint() {
        var channels = ASCIIToneCurve.Channels(red: .identity, green: .identity, blue: .identity)
        let harness = harness(Binding(get: { channels }, set: { channels = $0 }))
        let lines = harness.frame()
        guard let origin = harness.plotOrigin(lines) else {
            Issue.record("the plot did not render")
            return
        }
        let column = Panel.plotWidth / 2
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: origin.x + column, y: origin.y + 1))
        #expect(channels.red.points.count == 3, "no point was added: \(channels.red.points)")
        let added = channels.red.points[1]
        #expect(Panel.column(forInput: added.input) == column)
        #expect(abs(added.output - Panel.output(atRow: 1)) < 1e-9, "wrong level: \(added.output)")
    }

    /// The marker row is a handle strip, not a canvas.
    @Test("Dragging a marker moves its input and leaves its output alone")
    func draggingAMarkerMovesOneAxis() {
        var channels = ASCIIToneCurve.Channels(
            red: [(0, 0), (0.5, 0.25), (1, 1)], green: .identity, blue: .identity)
        let harness = harness(Binding(get: { channels }, set: { channels = $0 }))
        let lines = harness.frame()
        guard let origin = harness.plotOrigin(lines) else {
            Issue.record("the plot did not render")
            return
        }
        let markerRow = origin.y + Panel.plotHeight
        let from = origin.x + Panel.column(forInput: 0.5)
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: from, y: markerRow))
        harness.frame()
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: from + 5, y: markerRow))
        let moved = channels.red.points[1]
        #expect(
            Panel.column(forInput: moved.input) == Panel.column(forInput: 0.5) + 5,
            "the marker did not follow: \(channels.red.points)")
        #expect(moved.output == 0.25, "the drag changed the level as well")
        #expect(channels.red.points.count == 3, "a marker drag added a point")
    }

    /// A press on the marker row that lands on nothing must not add one —
    /// which is what makes the two rows' gestures distinguishable.
    @Test("Pressing empty marker row does nothing")
    func pressingEmptyMarkerRowDoesNothing() {
        var channels = ASCIIToneCurve.Channels(red: .identity, green: .identity, blue: .identity)
        let harness = harness(Binding(get: { channels }, set: { channels = $0 }))
        let lines = harness.frame()
        guard let origin = harness.plotOrigin(lines) else {
            Issue.record("the plot did not render")
            return
        }
        harness.dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .pressed, x: origin.x + Panel.plotWidth / 2,
                y: origin.y + Panel.plotHeight))
        #expect(channels.red == .identity)
    }

    @Test("A plot row and its output are inverses at the ends")
    func rowsAndOutputsAgree() {
        #expect(Panel.output(atRow: 0) == 1, "the top row is not full output")
        #expect(Panel.output(atRow: Panel.plotHeight - 1) == 0, "the bottom row is not zero")
        let outputs = (0..<Panel.plotHeight).map(Panel.output(atRow:))
        #expect(outputs == outputs.sorted(by: >), "the rows are not monotone")
    }

    @Test("A press grabs the nearest point, and only within reach")
    func grabbingIsNearestWithinReach() {
        let points: [Point] = [
            .init(input: 0, output: 0), .init(input: 0.5, output: 0.5), .init(input: 1, output: 1),
        ]
        let middle = Panel.column(forInput: 0.5)
        #expect(Panel.point(in: points, near: middle)?.input == 0.5)
        #expect(Panel.point(in: points, near: middle + Panel.grabRadius)?.input == 0.5)
        #expect(Panel.point(in: points, near: middle + Panel.grabRadius + 1) == nil)
        // Between two, the nearer one wins.
        #expect(Panel.point(in: points, near: 1)?.input == 0)
    }
}
