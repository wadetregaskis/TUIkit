//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReorderOverrunClipTests.swift
//
//  Which end of an over-long reorder frame gives way.
//
//  The rule was written twice — once in `Table.clipOverrun`, once in
//  `_ListCore.clipReorderOverrun` — and the two copies had drifted apart at the
//  boundary, one clipping against `budget` and the other against
//  `max(1, budget)`. Pinned here now that it is one function, including the
//  boundary neither copy had a case for.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Reorder overrun clipping")
struct ReorderOverrunClipTests {

    private typealias Handler = ItemListHandler<Int>

    @Test("A frame within its budget is not clipped")
    func withinBudget() {
        #expect(
            Handler.reorderOverrun(lineCount: 5, budget: 5, endsWithSlot: false)
                == (front: 0, back: 0))
        #expect(
            Handler.reorderOverrun(lineCount: 3, budget: 5, endsWithSlot: true)
                == (front: 0, back: 0))
    }

    @Test("An overrun comes off the TAIL when the slot is not there")
    func tailGivesWay() {
        let clip = Handler.reorderOverrun(lineCount: 8, budget: 5, endsWithSlot: false)
        #expect(clip == (front: 0, back: 3))
    }

    /// The whole point of the rule: the slot says where the rows will land, so
    /// clipping through it reads as the selection falling off the bottom.
    @Test("An overrun comes off the FRONT when the slot ends the frame")
    func frontGivesWayToProtectTheSlot() {
        let clip = Handler.reorderOverrun(lineCount: 8, budget: 5, endsWithSlot: true)
        #expect(clip == (front: 3, back: 0))
    }

    @Test("Only one end ever gives way")
    func onlyOneEnd() {
        for lineCount in 0...12 {
            for budget in 0...12 {
                for endsWithSlot in [false, true] {
                    let clip = Handler.reorderOverrun(
                        lineCount: lineCount, budget: budget, endsWithSlot: endsWithSlot)
                    #expect(
                        clip.front == 0 || clip.back == 0,
                        "\(lineCount)/\(budget)/\(endsWithSlot) → \(clip)")
                    #expect(clip.front >= 0 && clip.back >= 0)
                    #expect(
                        lineCount - clip.front - clip.back <= max(0, budget),
                        "what survives fits the budget: \(clip)")
                }
            }
        }
    }

    /// The boundary the two copies disagreed about. A budget of zero clips
    /// everything rather than keeping a line nobody budgeted for — the safe
    /// direction, since an unbudgeted line overflows whatever box the frame is
    /// being drawn into.
    ///
    /// Neither view can reach it (the List's budgets are `max(1, …)` at source,
    /// the Table's is a count of rows it has already drawn), so this pins the
    /// rule rather than a behaviour anyone sees. That is worth having: the two
    /// copies drifted precisely because nothing said what should happen here.
    @Test("A budget of zero keeps nothing")
    func zeroBudgetKeepsNothing() {
        #expect(
            Handler.reorderOverrun(lineCount: 4, budget: 0, endsWithSlot: false)
                == (front: 0, back: 4))
        #expect(
            Handler.reorderOverrun(lineCount: 4, budget: 0, endsWithSlot: true)
                == (front: 4, back: 0))
    }
}
