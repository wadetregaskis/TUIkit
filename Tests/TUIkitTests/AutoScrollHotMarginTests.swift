//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AutoScrollHotMarginTests.swift
//
//  A drag hovering the MIDDLE of a scrollable must not auto-scroll it.
//
//  The hot margin is a fixed 2 rows in from each edge. On a short scrollable
//  that is more than half the viewport, so the top and bottom hot zones
//  OVERLAP and every row counts as "near an edge" — hovering the second row of
//  a four-row list scrolled it, with nothing like an edge under the cursor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Auto-scroll hot margins never swallow the whole viewport")
struct AutoScrollHotMarginTests {

    /// The per-tick step for a cursor at `row` of a scrollable `extent` rows
    /// tall that can scroll both ways.
    private func delta(row: Int, extent: Int) -> Int {
        DragAndDropSession.autoScrollDeltaForTesting(
            position: row, start: 0, extent: extent,
            canBackward: true, canForward: true)
    }

    @Test("a four-row viewport keeps a neutral middle")
    func shortViewportHasNeutralMiddle() {
        // Rows 0 and 3 are the edges; 1 and 2 are the middle and must be inert.
        #expect(delta(row: 0, extent: 4) < 0, "the top row engages backward")
        #expect(delta(row: 3, extent: 4) > 0, "the bottom row engages forward")
        #expect(
            delta(row: 1, extent: 4) == 0,
            "row 1 of 4 is the middle, not an edge — got \(delta(row: 1, extent: 4))")
        #expect(
            delta(row: 2, extent: 4) == 0,
            "row 2 of 4 is the middle, not an edge — got \(delta(row: 2, extent: 4))")
    }

    @Test("the margins never overlap, at any viewport height")
    func marginsNeverOverlap() {
        // Whatever the height, no row may be BOTH inside the top margin and
        // inside the bottom one; overlap is what makes a middle row scroll.
        for extent in 1...12 {
            let deltas = (0..<extent).map { delta(row: $0, extent: extent) }
            let backward = deltas.filter { $0 < 0 }.count
            let forward = deltas.filter { $0 > 0 }.count
            #expect(
                backward + forward <= extent,
                "extent \(extent): zones overlap — \(deltas)")
            if extent >= 3 {
                #expect(
                    deltas.contains(0),
                    "extent \(extent) must leave a neutral row: \(deltas)")
            }
        }
    }

    @Test("a roomy viewport still gets the full two-row margin")
    func roomyViewportUnchanged() {
        #expect(delta(row: 0, extent: 20) < 0)
        #expect(delta(row: 1, extent: 20) < 0, "the 2-row margin survives where there is room")
        #expect(delta(row: 2, extent: 20) == 0)
        #expect(delta(row: 18, extent: 20) > 0)
        #expect(delta(row: 19, extent: 20) > 0)
    }
}
