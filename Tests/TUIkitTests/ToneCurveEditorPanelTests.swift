//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToneCurveEditorPanelTests.swift
//
//  The editor's whole claim is that the two strips are the mapping, read
//  column by column, and that the markers say where the stops are. These
//  measure exactly that, off the rendered buffer.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitImage

@testable import TUIkit

@MainActor
@Suite("Tone curve editor")
struct ToneCurveEditorPanelTests {

    private typealias Panel = ToneCurveEditorPanel
    private typealias Stop = ASCIIToneCurve.Stop

    private let stops: [Stop] = [
        .init(at: 0, to: .rgb(10, 10, 40)),
        .init(at: 0.3, to: .rgb(180, 40, 70)),
        .init(at: 1, to: .rgb(255, 250, 220)),
    ]

    // MARK: - The model

    @Test("A stop's position is the tone of its `from`, and survives a round trip")
    func positionRoundTrips() {
        for wanted in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let stop = Stop(at: wanted, to: .rgb(1, 2, 3))
            // Through a byte, so a rounding of at most half a level.
            #expect(abs((stop.position ?? -1) - wanted) <= 0.5 / 255)
        }
    }

    @Test("An unresolved semantic `from` has no position")
    func semanticFromHasNoPosition() {
        #expect(Stop(from: .palette.accent, to: .rgb(0, 0, 0)).position == nil)
    }

    @Test("Adding a stop changes nothing about the curve")
    func addingAStopIsInert() {
        // The property that makes a curve refinable rather than restartable: a
        // new stop takes the colour the curve ALREADY produces where it lands.
        let before = ASCIIToneCurve(stops)
        let (updated, index) = Panel.adding(to: stops, after: 0)
        #expect(updated.count == stops.count + 1)
        #expect(index == 1, "the new stop is the one selected")
        let after = ASCIIToneCurve(updated)
        for step in 0...20 {
            let tone = Double(step) / 20
            let old = before.color(atTone: tone).rgbComponents!
            let new = after.color(atTone: tone).rgbComponents!
            // One level of slack per channel: the inserted stop's colour is
            // quantised to bytes on the way in.
            #expect(abs(Int(old.red) - Int(new.red)) <= 1, "tone \(tone)")
            #expect(abs(Int(old.green) - Int(new.green)) <= 1, "tone \(tone)")
            #expect(abs(Int(old.blue) - Int(new.blue)) <= 1, "tone \(tone)")
        }
    }

    @Test("Adding on the last stop falls back INTO the curve, not on top of it")
    func addingOnTheLastStop() {
        // The last stop is at white, which is where it nearly always is, so
        // there is no room after it. Landing a second stop at the same tone
        // would make "+" look broken: nothing new is visible, and the new
        // stop cannot be reached by dragging because its span is zero.
        let (updated, index) = Panel.adding(to: stops, after: 2)
        #expect(updated.count == 4)
        let landed = Panel.position(of: updated[index])
        #expect(landed < Panel.position(of: stops[2]), "landed on top of the last stop")
        #expect(landed > Panel.position(of: stops[1]), "landed past the stop before it")
        #expect(Panel.sorted(updated).map(Panel.position) == updated.map(Panel.position))
    }

    @Test("Adding on the only stop of a one-stop list still lands somewhere new")
    func addingOnASoleStop() {
        let (updated, index) = Panel.adding(to: [.init(at: 1, to: .rgb(9, 9, 9))], after: 0)
        #expect(updated.count == 2)
        #expect(Panel.position(of: updated[index]) < 1)
    }

    @Test("Stops sort by position, and equal positions keep their written order")
    func sortingIsStable() {
        let shuffled: [Stop] = [
            .init(at: 0.5, to: .rgb(1, 0, 0)),
            .init(at: 0.0, to: .rgb(2, 0, 0)),
            .init(at: 0.5, to: .rgb(3, 0, 0)),
        ]
        let sorted = Panel.sorted(shuffled)
        #expect(sorted.map { $0.to.rgbComponents!.red } == [2, 1, 3])
    }

    @Test("A column and its tone are inverses")
    func columnsAndTonesAgree() {
        #expect(Panel.column(forTone: 0) == 0)
        #expect(Panel.tone(atColumn: 0) == 0)
        #expect(Panel.tone(atColumn: Panel.column(forTone: 1)) == 1)
        for column in 0..<10 {
            #expect(Panel.column(forTone: Panel.tone(atColumn: column)) == column)
        }
    }

    // MARK: - What it draws

    /// The panel rendered with `stops`, as stripped lines.
    private func rendered(_ list: [Stop]) -> [String] {
        let context = makeRenderContext(width: 100, height: 60)
        let panel = ToneCurveEditorPanel(
            "Tone curve", stops: .constant(list), isPresented: .constant(true))
        _ = renderToBuffer(panel, context: context)
        return renderToBuffer(panel, context: context).lines.map(\.stripped)
    }

    @Test("There is one marker per stop, at that stop's own column")
    func markersSitWhereTheStopsAre() {
        let lines = rendered(stops)
        guard let markers = lines.first(where: { $0.contains(TerminalSymbols.toneCurveStop) })
        else {
            Issue.record("no marker row: \(lines)")
            return
        }
        let columns = markers.enumerated()
            .filter { String($0.element) == TerminalSymbols.toneCurveStop }
            .map(\.offset)
        #expect(columns.count == stops.count, "one marker per stop: \(markers)")
        // The marker row carries the same gutter the strips do, so the offsets
        // differ from the strip columns by exactly that — which is what makes
        // the diagram legible, and is worth asserting rather than eyeballing.
        let offsets = columns.map { $0 - columns[0] }
        let expected = stops.map {
            Panel.column(forTone: Panel.position(of: $0))
                - Panel.column(forTone: Panel.position(of: stops[0]))
        }
        #expect(offsets == expected)
    }

    @Test("Moving a stop moves its marker, in the same render pass")
    func markersFollowTheStops() {
        // The `ForEach`-over-indices trap: an `Equatable` element wraps each
        // cell in the element-keyed render memo, which cannot see data the
        // cell captured from outside the loop — so the row freezes at whatever
        // it drew first. `GradientEditorPanel`'s preview shipped with exactly
        // that bug once.
        let context = makeRenderContext(width: 100, height: 60)
        func markerColumns(_ list: [Stop]) -> [Int] {
            let panel = ToneCurveEditorPanel(
                "Tone curve", stops: .constant(list), isPresented: .constant(true))
            let lines = renderToBuffer(panel, context: context).lines.map(\.stripped)
            guard let row = lines.first(where: { $0.contains(TerminalSymbols.toneCurveStop) })
            else { return [] }
            return row.enumerated()
                .filter { String($0.element) == TerminalSymbols.toneCurveStop }
                .map(\.offset)
        }
        let before = markerColumns(stops)
        let after = markerColumns([
            .init(at: 0, to: .rgb(10, 10, 40)),
            .init(at: 0.8, to: .rgb(180, 40, 70)),
            .init(at: 1, to: .rgb(255, 250, 220)),
        ])
        #expect(!before.isEmpty && !after.isEmpty)
        #expect(before != after, "the marker row did not follow the stops: \(before)")
    }

    @Test("The output strip shows the curve, not a gradient of the stop colours")
    func outputStripIsTheCurve() {
        // Two stops crowded into the first third: an evenly-spaced gradient of
        // the same three colours would put the middle colour at the MIDDLE,
        // and the difference is the whole reason this is not that editor.
        let crowded: [Stop] = [
            .init(at: 0, to: .rgb(0, 0, 0)),
            .init(at: 0.25, to: .rgb(255, 0, 0)),
            .init(at: 1, to: .rgb(255, 255, 255)),
        ]
        let context = makeRenderContext(width: 100, height: 60)
        let panel = ToneCurveEditorPanel(
            "Tone curve", stops: .constant(crowded), isPresented: .constant(true))
        _ = renderToBuffer(panel, context: context)
        let buffer = renderToBuffer(panel, context: context)

        // The red stop sits a quarter along, so the red is a quarter along.
        let curve = ASCIIToneCurve(crowded)
        let atQuarter = curve.color(atTone: 0.25).rgbComponents!
        #expect(atQuarter == (red: 255, green: 0, blue: 0))
        let atHalf = curve.color(atTone: 0.5).rgbComponents!
        #expect(atHalf.green > 0, "half way is already past the red: \(atHalf)")

        // And the strip drew it: the pure red appears in the rendered bytes.
        let text = buffer.lines.joined()
        #expect(
            text.contains("38;2;255;0;0"),
            "the quarter-point colour is not on the strip")
    }

    // MARK: - The pointer

    /// A frame of the panel driven the way the run loop drives one: render,
    /// publish the regions the render produced, then dispatch. The buffer is
    /// the root here, so its region offsets ARE screen coordinates.
    @MainActor
    private struct Harness {
        let panel: ToneCurveEditorPanel
        let context: RenderContext
        let dispatcher: MouseEventDispatcher

        @discardableResult
        func frame() -> [String] {
            let buffer = renderToBuffer(panel, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer.lines.map(\.stripped)
        }

        /// Where the strip's column 0 sits on screen, found from the rendered
        /// picture rather than computed: the caption gutter, the dialog border
        /// and the centring all lie between, and a test that added them up
        /// itself would be testing its own copy of the arithmetic instead of
        /// the panel's.
        func stripOrigin(_ lines: [String]) -> (x: Int, y: Int)? {
            guard
                let row = lines.firstIndex(where: { $0.contains(TerminalSymbols.toneCurveStop) })
            else { return nil }
            let line = lines[row]
            guard let mark = line.range(of: TerminalSymbols.toneCurveStop) else { return nil }
            // The first stop of every fixture below sits at tone 0, so its
            // marker IS column 0.
            return (x: line.distance(from: line.startIndex, to: mark.lowerBound), y: row)
        }
    }

    @MainActor
    private func harness(_ stops: Binding<[Stop]>) -> Harness {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 90, availableHeight: 60, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        tui.mouseEventDispatcher.setActiveSupport(.standard)
        return Harness(
            panel: ToneCurveEditorPanel(
                "Tone", stops: stops, isPresented: .constant(true)),
            context: context,
            dispatcher: tui.mouseEventDispatcher)
    }

    /// The gesture, through the real dispatcher against the real regions — so
    /// the caption gutter being counted (or not) is what this fails on.
    @MainActor
    @Test("Dragging a marker moves that stop along the tone axis")
    func draggingAMarkerMovesTheStop() {
        var list: [Stop] = [
            .init(at: 0, to: .rgb(0, 0, 0)), .init(at: 0.5, to: .rgb(128, 0, 0)),
            .init(at: 1, to: .rgb(255, 255, 255)),
        ]
        let harness = harness(Binding(get: { list }, set: { list = $0 }))
        let lines = harness.frame()
        guard let origin = harness.stripOrigin(lines) else {
            Issue.record("the diagram did not render")
            return
        }
        let from = origin.x + Panel.column(forTone: 0.5)
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: from, y: origin.y))
        harness.frame()
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: from + 6, y: origin.y))
        #expect(list.count == 3, "the drag added a stop instead of moving one")
        #expect(
            Panel.column(forTone: Panel.position(of: list[1]))
                == Panel.column(forTone: 0.5) + 6,
            "the stop did not follow: \(list.map { Panel.position(of: $0) })")
        #expect(list[1].to == .rgb(128, 0, 0), "the drag changed the colour")
    }

    /// Every row of the diagram is the same axis, so pressing the OUT strip
    /// grabs the stop above it just as the marker row does.
    @MainActor
    @Test("The strips are the axis too, not just the marker row")
    func theStripsGrabAsWell() {
        var list: [Stop] = [
            .init(at: 0, to: .rgb(0, 0, 0)), .init(at: 0.5, to: .rgb(128, 0, 0)),
            .init(at: 1, to: .rgb(255, 255, 255)),
        ]
        let harness = harness(Binding(get: { list }, set: { list = $0 }))
        let lines = harness.frame()
        guard let origin = harness.stripOrigin(lines) else {
            Issue.record("the diagram did not render")
            return
        }
        let from = origin.x + Panel.column(forTone: 0.5)
        // One row BELOW the markers: the first `out` strip.
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: from, y: origin.y + 1))
        harness.frame()
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: from - 4, y: origin.y + 1))
        #expect(list.count == 3)
        #expect(
            Panel.column(forTone: Panel.position(of: list[1]))
                == Panel.column(forTone: 0.5) - 4,
            "\(list.map { Panel.position(of: $0) })")
    }

    /// A press where no stop is adds one — coloured with what the curve
    /// already produces there, so the press alone changes nothing.
    @MainActor
    @Test("Pressing empty axis adds a stop that changes nothing")
    func pressingEmptyAxisAddsAnInertStop() {
        var list: [Stop] = [.init(at: 0, to: .rgb(0, 0, 0)), .init(at: 1, to: .rgb(255, 255, 255))]
        let before = ASCIIToneCurve(list)
        let harness = harness(Binding(get: { list }, set: { list = $0 }))
        let lines = harness.frame()
        guard let origin = harness.stripOrigin(lines) else {
            Issue.record("the diagram did not render")
            return
        }
        let column = Panel.stripWidth / 2
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: origin.x + column, y: origin.y))
        #expect(list.count == 3, "no stop was added: \(list.count)")
        #expect(Panel.column(forTone: Panel.position(of: list[1])) == column)
        let after = ASCIIToneCurve(list)
        for step in 0...20 {
            let tone = Double(step) / 20
            #expect(
                before.color(atTone: tone).rgbComponents! == after.color(atTone: tone).rgbComponents!,
                "the added stop changed the curve at \(tone)")
        }
    }

    /// The gutter is caption, not axis: a press on `in` / `out` must not be
    /// read as tone 0 and drag the black stop out from under everything.
    @MainActor
    @Test("A press in the caption gutter is ignored")
    func pressingTheGutterDoesNothing() {
        var list: [Stop] = [.init(at: 0, to: .rgb(0, 0, 0)), .init(at: 1, to: .rgb(255, 255, 255))]
        let harness = harness(Binding(get: { list }, set: { list = $0 }))
        let lines = harness.frame()
        guard let origin = harness.stripOrigin(lines) else {
            Issue.record("the diagram did not render")
            return
        }
        harness.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: origin.x - 1, y: origin.y))
        #expect(list.count == 2, "a press on the caption added a stop")
    }

    @Test("A press grabs the nearest stop, and only within reach")
    func grabbingIsNearestWithinReach() {
        let list: [Stop] = [
            .init(at: 0, to: .rgb(0, 0, 0)), .init(at: 0.5, to: .rgb(128, 0, 0)),
            .init(at: 1, to: .rgb(255, 255, 255)),
        ]
        // Compared as COLUMNS: a stop's position is the tone of its grey
        // `from`, so 0.5 comes back as 128/255 and an equality on the Double
        // would be asserting the byte round-trip rather than the reach.
        func column(_ stop: Stop?) -> Int? { stop.map { Panel.column(forTone: Panel.position(of: $0)) } }
        let middle = Panel.column(forTone: 0.5)
        #expect(column(Panel.stop(in: list, near: middle)) == middle)
        #expect(column(Panel.stop(in: list, near: middle + Panel.grabRadius)) == middle)
        #expect(Panel.stop(in: list, near: middle + Panel.grabRadius + 1) == nil)
        #expect(column(Panel.stop(in: list, near: 1)) == 0)
    }
}
