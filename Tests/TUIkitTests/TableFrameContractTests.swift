//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableFrameContractTests.swift
//
//  What a `Table` owes ACROSS frames, rather than within one.
//
//  Every other Table suite in this target renders once and asserts on the
//  ANSI-stripped text of that render. That pins what a table draws; it cannot
//  see a row that came back stale, re-coloured, or served from a cache that
//  should have declined — which is the entire failure mode of the per-row
//  memoisation `Table` does not yet have and `List` does. These are the
//  properties such a memo would have to keep, asserted on the bytes.
//
//  They are worth holding either way: three of them are simply true of a
//  correct table, and two of them turn out to record costs nothing had
//  measured.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("What a Table owes across frames")
struct TableFrameContractTests {

    /// A settled table drawing unchanged data must produce the same BYTES,
    /// escape sequences and all.
    ///
    /// The assertion every existing Table test is one `.stripped` away from
    /// being able to make. A row served from a stale cache, a colour resolved
    /// against a palette that moved, a clip that lost its closing reset — none
    /// of them change the visible text, and all of them change this.
    @Test("The same data draws the same bytes", arguments: TableMatrixShape.sweep)
    func sameDataDrawsTheSameBytes(_ testCase: TableMatrixCase) {
        let harness = TableMatrixHarness(testCase.shape)
        harness.settle()
        let first = harness.frame()
        let second = harness.frame()
        let third = harness.frame()

        #expect(first.lines == second.lines, "frame 2 differed from frame 1")
        #expect(second.lines == third.lines, "frame 3 differed from frame 2")
        #expect(!first.lines.isEmpty, "the fixture drew nothing")
    }

    /// And a warm cache must draw what a cold one draws — AFTER the data has
    /// moved under it.
    ///
    /// The mutation is the whole test. A first version compared the two with
    /// unchanged data and could not fail: a memo serving a stale answer for
    /// data that has not changed is serving the right answer. Deliberately
    /// breaking the `.fit` memo's key — so it serves across a data change —
    /// left that version green, which is how this one came to mutate first.
    ///
    /// The `.fit` column width is the only thing a `Table` keeps across frames
    /// today, so today that is mostly what this exercises. It is the standing
    /// net for everything added to that list later.
    @Test("A warm cache draws what a cold one draws", arguments: TableMatrixShape.sweep)
    func warmDrawsWhatColdDraws(_ testCase: TableMatrixCase) {
        let harness = TableMatrixHarness(testCase.shape)
        harness.settle()
        for index in 0..<min(6, testCase.shape.rows) { harness.mutate(rowAt: index) }
        let warm = harness.frame()
        let cold = harness.frame(coldCache: true)

        #expect(warm.lines == cold.lines, "a served frame differed from an unserved one")
    }

    /// A `.fit` column has to follow its widest value, and its width is the one
    /// thing a `Table` keeps across frames — so it is the one place a stale
    /// answer can already shift every column to its right.
    ///
    /// Deterministic rather than probabilistic: the `.cheap` cell text is
    /// `"<id>.<generation>"`, so with single-digit ids every cell is three
    /// cells wide, and ten mutations of one row take it to `0.10` — four —
    /// which the column must grow to fit.
    ///
    /// EIGHT rows, not forty, and the difference is the test. At forty the ids
    /// reach `39.0`, the column is already four cells wide, and widening row
    /// zero to `0.10` changes nothing about the layout — so the first version
    /// of this test passed against a `.fit` memo deliberately broken to serve
    /// stale widths, while asserting that it would not.
    @Test("A .fit column follows its widest value across frames")
    func fitColumnFollowsItsWidestValue() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 8,
                columns: [
                    TableMatrixColumn(title: "K", width: .fit, cost: .cheap),
                    TableMatrixColumn(title: "Rest", cost: .cheap),
                ]))
        harness.settle()
        let before = harness.frame()

        for _ in 0..<10 { harness.mutate(rowAt: 0) }
        let after = harness.frame()
        let cold = harness.frame(coldCache: true)

        #expect(after.lines == cold.lines, "the kept width differed from the computed one")
        #expect(after.lines != before.lines, "the widened value did not reach the frame")
    }

    /// Changing one row of many changes that row's line and no other.
    ///
    /// The owner's shape — a very large table updating very frequently, a small
    /// fraction of rows at a time — asked as a correctness question. Restricted
    /// to the single-line composer and to columns whose width cannot move: a
    /// `.fit` column legitimately re-lays the whole table when its widest value
    /// changes, and a wrapped row legitimately changes its own height.
    @Test("Changing one row changes one line")
    func changingOneRowChangesOneLine() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 200,
                columns: [
                    TableMatrixColumn(title: "ID", width: .fixed(6), cost: .cheap),
                    TableMatrixColumn(title: "Value", width: .fixed(18), cost: .formatted),
                    TableMatrixColumn(title: "Tail", width: .fixed(10), cost: .cheap),
                ]))
        harness.settle()
        let before = harness.frame()

        harness.mutate(rowAt: 2)
        let after = harness.frame()

        let changed = zip(before.lines, after.lines).enumerated()
            .filter { $0.element.0 != $0.element.1 }
            .map(\.offset)
        #expect(before.lines.count == after.lines.count, "the table changed height")
        #expect(changed.count == 1, "lines \(changed) changed, expected exactly one")
    }

    /// Moving the selection changes two rows and no others, though the DATA
    /// did not change at all.
    ///
    /// The case that decides what a row memo may key on. Both affected rows
    /// compare exactly equal to what they were — one gained the mark and the
    /// selected background, the other lost them — so a memo keyed on the row
    /// value alone would serve both of them stale and the selection would
    /// simply not move on screen.
    @Test("Moving the selection changes two rows and no others")
    func movingTheSelectionChangesTwoRows() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 100,
                columns: [
                    TableMatrixColumn(title: "ID", width: .fixed(6), cost: .cheap),
                    TableMatrixColumn(title: "Value", width: .fixed(18), cost: .formatted),
                ],
                selection: .single(1)))
        harness.settle()
        let before = harness.frame()

        harness.select(3)
        let after = harness.frame()

        let changed = zip(before.lines, after.lines).enumerated()
            .filter { $0.element.0 != $0.element.1 }
            .map(\.offset)
        #expect(changed.count == 2, "lines \(changed) changed, expected the two marked rows")
        #expect(after.lines == harness.frame(coldCache: true).lines, "warm differed from cold")
    }

    /// Scrolling moves the WINDOW: the rows on screen shift by one, each one
    /// keeps its own content, and the warm frame still matches a cold one.
    ///
    /// The axis no Table scenario or test covered — nothing anywhere scrolled a
    /// table between frames and then asked what it drew. It is also where a row
    /// memo is most likely to go wrong in an interesting way: after a scroll of
    /// one row, all but one of the rows on screen were on screen a moment ago
    /// with exactly the same content, at a different LINE. A memo keyed by
    /// position serves every one of them stale; a memo keyed by the row's
    /// identity serves them all correctly. This says which happened, by reading
    /// the drawn ids back off the picture rather than asking the scroll offset.
    @Test("Scrolling shifts the window by one and keeps each row's content")
    func scrollingShiftsTheWindow() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 200,
                columns: [
                    TableMatrixColumn(title: "ID", width: .fixed(8), cost: .cheap),
                    TableMatrixColumn(title: "Value", width: .fixed(18), cost: .formatted),
                ]))
        harness.settle()
        // Down to the bottom of the window first, so the next press scrolls
        // rather than just moving the cursor within what is already drawn.
        harness.pressDown(30)
        let before = harness.frame()
        let idsBefore = TableMatrixHarness.drawnRowIDs(in: before)

        harness.pressDown(1)
        let after = harness.frame()
        let idsAfter = TableMatrixHarness.drawnRowIDs(in: after)

        #expect(idsBefore.count > 4, "the fixture drew \(idsBefore.count) rows")
        #expect(
            idsAfter == idsBefore.map { $0 + 1 },
            "window went \(idsBefore) -> \(idsAfter)")
        #expect(
            after.lines == harness.frame(coldCache: true).lines,
            "a scrolled frame differed from an unserved one")
    }

    /// Each drawn row asks each column for its value exactly once.
    ///
    /// `renderRow` states this in its own comment — "the column's value closure
    /// still runs exactly once and in the same order whichever branch below
    /// draws it" — and nothing checked it. A value closure is the one part of a
    /// cell an app writes, so running it twice is the app's cost doubled.
    @Test("Each drawn row asks each column once")
    func eachDrawnRowAsksEachColumnOnce() {
        let columns = [
            TableMatrixColumn(title: "A", width: .fixed(6), cost: .cheap),
            TableMatrixColumn(title: "B", width: .fixed(10), cost: .formatted),
            TableMatrixColumn(title: "C", cost: .styled),
        ]
        let harness = TableMatrixHarness(TableMatrixShape(rows: 300, columns: columns))
        harness.settle()
        harness.frame()

        let perRow = Set(harness.calls.perRow.values)
        #expect(perRow == [columns.count], "a drawn row asked for \(perRow.sorted()) values")
        #expect(
            harness.calls.total == harness.calls.perRow.count * columns.count,
            "\(harness.calls.total) calls over \(harness.calls.perRow.count) rows")
    }

    /// And a single-line table's per-frame work is bounded by the WINDOW, not
    /// by the data: three hundred rows and three thousand cost the same.
    @Test("A single-line table's work is bounded by its window")
    func singleLineWorkIsBoundedByTheWindow() {
        func calls(rows: Int) -> Int {
            let harness = TableMatrixHarness(
                TableMatrixShape(
                    rows: rows,
                    columns: [
                        TableMatrixColumn(title: "ID", width: .fixed(6), cost: .cheap),
                        TableMatrixColumn(title: "Value", cost: .formatted),
                    ]))
            harness.settle()
            harness.frame()
            return harness.calls.total
        }
        #expect(calls(rows: 300) == calls(rows: 3_000))
    }

    /// The multi-line composer is NOT bounded by its window, and there is a
    /// cliff at 256 rows where it stops being bounded by the data either.
    ///
    /// Deliberate, and documented where the two frame-local memos are built:
    /// under `ScrollExtentPrecision.exact` "or for any table at or below its
    /// 256-row limit" the scrollbar's extent estimator measures EVERY row, so
    /// every row's cells are built every frame. Above the limit it samples.
    ///
    /// Recorded here because nothing measured it and the shape is surprising:
    /// a 250-row wrapped table does an order of magnitude more per-frame work
    /// than a 300-row one. The numbers are the current behaviour, not a budget
    /// — if a change moves them, this test is where the decision gets made.
    @Test("A wrapped table measures every row below the estimator's limit")
    func wrappedTableMeasuresEveryRowBelowTheLimit() {
        func touched(rows: Int) -> Int {
            let harness = TableMatrixHarness(
                TableMatrixShape(
                    rows: rows,
                    columns: [
                        TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                        TableMatrixColumn(title: "Body", lineLimit: 3, cost: .overlong),
                    ]))
            harness.settle()
            harness.frame()
            return harness.calls.perRow.count
        }
        let below = touched(rows: 250)
        let above = touched(rows: 300)

        #expect(below == 250, "below the limit every row is measured, got \(below)")
        #expect(above < 40, "above the limit the estimator samples, got \(above)")
    }
}
