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
}
