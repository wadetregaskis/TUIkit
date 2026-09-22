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

    /// A row a `Table` COMPOSES asks each column for its value exactly once —
    /// which `renderRow` states in its own comment and nothing checked — and a
    /// row it SERVES asks for nothing at all.
    ///
    /// A value closure is the one part of a cell an app writes, so running it
    /// twice is the app's cost doubled and not running it is the app's cost
    /// removed. Both halves are asserted against the frame's own counters
    /// rather than inferred from a clock.
    @Test("A composed row asks each column once")
    func composedRowAsksEachColumnOnce() {
        let columns = [
            TableMatrixColumn(title: "A", width: .fixed(6), cost: .cheap),
            TableMatrixColumn(title: "B", width: .fixed(10), cost: .formatted),
            TableMatrixColumn(title: "C", cost: .styled),
        ]
        let harness = TableMatrixHarness(TableMatrixShape(rows: 300, columns: columns))
        harness.settle()
        harness.frame()

        #expect(
            Set(harness.calls.perRow.values) == [columns.count],
            "a composed row asked for \(Set(harness.calls.perRow.values).sorted()) values")
        #expect(harness.rowWork.cellValues == harness.rowWork.rendered * columns.count)
    }

    /// A table whose every column NAMES its value keeps its rows across frames;
    /// one with a single closure column keeps none of them.
    ///
    /// That is the whole of the memo's soundness argument, asserted rather than
    /// argued. A key path has no closure context, so it cannot capture the
    /// search term or the formatter that a closure column captures and that no
    /// row value would ever show — so where every column is a key path, an
    /// equal row draws equal text, and where any column is not, it does not.
    @Test("Rows are kept only when every column names its value")
    func rowsAreKeptOnlyForKeyPathColumns() {
        func work(namesAProperty: Bool) -> RenderCache.RowWork {
            let harness = TableMatrixHarness(
                TableMatrixShape(
                    rows: 300,
                    columns: [
                        TableMatrixColumn(
                            title: "A", width: .fixed(8), cost: .cheap,
                            namesAProperty: namesAProperty),
                        TableMatrixColumn(
                            title: "B", cost: .formatted, namesAProperty: namesAProperty),
                    ]))
            harness.settle()
            harness.frame()
            return harness.rowWork
        }
        let kept = work(namesAProperty: true)
        #expect(kept.rendered == 0, "a settled key-path table composed \(kept.rendered) rows")
        #expect(kept.served > 4, "a settled key-path table served only \(kept.served)")
        #expect(kept.cellValues == 0, "a served frame still read \(kept.cellValues) values")

        let computed = work(namesAProperty: false)
        #expect(computed.served == 0, "a closure column's table kept \(computed.served) rows")
        #expect(computed.rendered > 4)
    }

    /// And a kept row still follows its data, its selection and the window.
    @Test("A kept row still follows the things that change it")
    func keptRowsStillFollowTheirInputs() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 200,
                columns: [
                    TableMatrixColumn(
                        title: "ID", width: .fixed(8), cost: .cheap, namesAProperty: true),
                    TableMatrixColumn(title: "V", cost: .formatted, namesAProperty: true),
                ],
                selection: .single(1)))
        harness.settle()
        let before = harness.frame()
        #expect(harness.rowWork.served > 4, "the fixture is not exercising the memo")

        harness.mutate(rowAt: 2)
        let mutated = harness.frame()
        #expect(mutated.lines != before.lines, "a changed row did not reach the frame")
        #expect(mutated.lines == harness.frame(coldCache: true).lines)

        harness.select(4)
        let reselected = harness.frame()
        #expect(reselected.lines != mutated.lines, "the moved selection did not reach the frame")
        #expect(reselected.lines == harness.frame(coldCache: true).lines)

        harness.pressDown(30)
        let scrolled = harness.frame()
        #expect(scrolled.lines == harness.frame(coldCache: true).lines)
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

    /// The multi-line composer is not bounded by its window: below the scroll
    /// estimator's 256-row limit it measures EVERY row, because that is the mode
    /// a small table gets for free. It now KEEPS that answer, so it pays for it
    /// once rather than on every frame.
    ///
    /// The first frame still walks the whole table — the heights have to come
    /// from somewhere — and a settled frame asks about its window and nothing
    /// else. Above the limit the estimator samples, as it always did.
    @Test("A wrapped table measures every row once, not every frame")
    func wrappedTableMeasuresEveryRowOnce() {
        func shape(rows: Int, precision: ScrollExtentPrecision = .approximate) -> TableMatrixShape {
            TableMatrixShape(
                rows: rows,
                columns: [
                    TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                    TableMatrixColumn(title: "Body", lineLimit: 3, cost: .overlong),
                ],
                precision: precision)
        }
        let below = TableMatrixHarness(shape(rows: 250))
        below.frame()
        let firstFrame = below.calls.perRow.count
        below.settle()
        below.frame()
        let settled = below.calls.perRow.count

        #expect(firstFrame == 250, "the first frame has to walk the table, got \(firstFrame)")
        #expect(settled < 40, "a settled frame walked \(settled) rows of 250")

        let above = TableMatrixHarness(shape(rows: 300))
        above.settle()
        above.frame()
        #expect(above.calls.perRow.count < 40, "above the limit the estimator samples")
    }

    /// `.exact` is never cached, and that is the point of it.
    ///
    /// Its own documentation sells it as O(rows) per frame for callers who want
    /// a thumb proportionally exact to the line. Keeping its answer across
    /// frames would quietly hand them the approximation they declined — the
    /// heights are a function of the rows' CONTENT, and the signature the stash
    /// is keyed on deliberately does not include it.
    @Test("An .exact table re-measures every row on every frame")
    func exactPrecisionIsNeverCached() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 120,
                columns: [
                    TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                    TableMatrixColumn(title: "Body", lineLimit: 3, cost: .overlong),
                ],
                precision: .exact))
        harness.settle()
        harness.frame()
        #expect(
            harness.calls.perRow.count == 120,
            "a settled .exact table walked \(harness.calls.perRow.count) rows of 120")
    }
}
