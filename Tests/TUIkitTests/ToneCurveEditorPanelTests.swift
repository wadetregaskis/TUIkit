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
}
