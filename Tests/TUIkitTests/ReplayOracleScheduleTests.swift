//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayOracleScheduleTests.swift
//
//  The replay oracle (`ReplayOracle`) is only as good as its model of the run
//  loop, and the loop does not only replay: it renders whenever a firing a frame
//  asked for falls due — a lattice, or a one-shot wake. A view can hand an
//  animation to a wake instead of leaving it in a run, and a focused `List`'s
//  cursor row does: it breathes, repaints its whole line on every tick, so it
//  drops its row's own runs and asks for a render at their next step. An oracle
//  that only replayed held the glyph that row was drawn with, and reported the
//  app wrong where the app is right.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A focused list with no selection, a spinner in every row: its cursor row
/// breathes, and drops that row's spinner run for as long as it does.
private struct BreathingListApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) { Text("row \(row) "); Spinner(style: .dots) }
                }
            }
            .frame(width: 20, height: 3)
        }
    }
}

@MainActor
@Suite("The replay oracle renders where the run loop would")
struct ReplayOracleScheduleTests {

    @Test("A wake a breathing List row asks for is rendered, so its spinner moves on")
    func aWakeFallingDueIsRendered() {
        let found = ReplayOracle.compare({ BreathingListApp() }, focusSteps: 0, ticks: 24, size: (40, 8))
        #expect(found.compared > 0, "nothing was replayed")
        // Not vacuous: the list asked for renders, and the walk made them.
        #expect(found.scheduledRenders > 0, "no wake the list asked for fell due in the walk")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }
}
