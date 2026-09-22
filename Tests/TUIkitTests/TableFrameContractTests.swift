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
    /// A row a `Table` COMPOSES asks each column for its value exactly once —
    /// which `renderRow` states in its own comment and nothing checked.
    @Test("A composed row asks each column once")
    func composedRowAsksEachColumnOnce() {
        let columns = [
            TableMatrixColumn(title: "A", width: .fixed(6), cost: .cheap),
            TableMatrixColumn(title: "B", width: .fixed(10), cost: .formatted),
            TableMatrixColumn(title: "C", cost: .styled),
        ]
        let harness = TableMatrixHarness(TableMatrixShape(rows: 300, columns: columns))
        harness.frame()

        #expect(
            Set(harness.calls.perRow.values) == [columns.count],
            "a composed row asked for \(Set(harness.calls.perRow.values).sorted()) values")
        #expect(harness.rowWork.cellValues == harness.rowWork.rendered * columns.count)
    }

    /// Both kinds of table keep their rows, and the difference between them is
    /// exactly what each has to do to earn a hit.
    ///
    /// A CLOSURE column may capture a search term, a formatter, a units
    /// toggle — none of which the row carries — so an equal row proves nothing
    /// about its text and the closures have to run. But once they have run,
    /// what they produced IS the text, so the line can still be kept: the app
    /// pays for its own closures and nothing else.
    ///
    /// A KEY-PATH column names its value, so the cells are a pure function of
    /// the row and an equal row is enough — not one property is read.
    @Test("A key-path table serves without reading its rows; a closure table reads and still serves")
    func bothKindsServeAndOnlyOneReadsItsRows() {
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
        let named = work(namesAProperty: true)
        #expect(named.rendered == 0, "a settled key-path table composed \(named.rendered) rows")
        #expect(named.served > 4, "a settled key-path table served only \(named.served)")
        #expect(named.cellValues == 0, "a key-path serve still read \(named.cellValues) values")

        let computed = work(namesAProperty: false)
        #expect(computed.rendered == 0, "a settled closure table composed \(computed.rendered)")
        #expect(computed.served > 4, "a settled closure table served only \(computed.served)")
        #expect(
            computed.cellValues == computed.served * 2,
            "a closure serve read \(computed.cellValues) values for \(computed.served) rows")
    }

    /// A row type that cannot be compared is kept all the same, because what is
    /// compared is what its columns PRODUCED rather than the row itself.
    ///
    /// `Table` requires only `Identifiable`, so this is not an edge case — it is
    /// every table whose row type nobody thought to make `Equatable`. An
    /// earlier design of this memo keyed on the row and so stood aside for all
    /// of them.
    @Test("A row type that is not Equatable is kept anyway")
    func uncomparableRowsAreKeptToo() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 200,
                columns: [
                    TableMatrixColumn(title: "A", width: .fixed(8), cost: .cheap),
                    TableMatrixColumn(title: "B", cost: .formatted),
                ],
                comparableRows: false))
        harness.settle()
        let warm = harness.frame()

        #expect(
            harness.rowWork.served > 4,
            "an uncomparable table served \(harness.rowWork.served) rows")
        #expect(warm.lines == harness.frame(coldCache: true).lines)
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

    /// A row that changed in a way its columns do not show must not be demoted
    /// from the cheapest tier — not on the next frame, and not for ever.
    ///
    /// The cheap tier compares the ROW, which a key-path table may do because
    /// its cells are a pure function of it. The tier below compares the CELLS,
    /// which costs a build per column. A row whose hidden field moves fails the
    /// first and passes the second — and if serving it that way leaves the kept
    /// entry pointing at the row it was COMPOSED for, it fails the first test
    /// again on the next frame, and the next, having permanently fallen to the
    /// expensive path while drawing identical bytes. On a table whose cells come
    /// from a formatter that is the difference between a frame and ten.
    ///
    /// Found by sweeping the `table-api` matrix: `text-cheap` built 139 cell
    /// values a frame — four columns × every drawn row — while composing none.
    @Test("A row whose hidden field changes goes back to the cheap tier")
    func hiddenFieldDoesNotDemoteARowForEver() {
        let harness = TableMatrixHarness(
            TableMatrixShape(
                rows: 40,
                columns: [
                    TableMatrixColumn(
                        title: "ID", width: .fixed(6), cost: .cheap, namesAProperty: true),
                    TableMatrixColumn(title: "Name", cost: .formatted, namesAProperty: true),
                ]))
        harness.settle()
        harness.frame()
        #expect(
            harness.rowWork.cellValues == 0,
            "a settled key-path table built \(harness.rowWork.cellValues) cell values")

        // One row changes in a way nothing draws.
        harness.touch(rowAt: 0)
        harness.frame()

        // The frame AFTER: every row is equal to the row the kept line was last
        // proved to answer for, so nothing needs a cell built at all.
        harness.frame()
        #expect(
            harness.rowWork.cellValues == 0,
            "a row touched two frames ago still costs \(harness.rowWork.cellValues) cell values")

        // And it is still drawing the right thing.
        let drawn = TableMatrixHarness.drawnRowIDs(in: harness.frame())
        #expect(drawn.first == 0, "the touched row is no longer first, got \(String(describing: drawn.first))")
    }
}
