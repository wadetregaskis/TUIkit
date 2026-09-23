//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentWidthChallengeTests.swift
//
//  The width of ALL of a windowed stack's rows, kept across frames in `@State`
//  (`StackContentWidth.swift`), and every way it could go stale or be asked a
//  question it answers differently depending on who asked first.
//
//  The record survives a `@State` write on purpose — that is how a growing
//  collection is extended rather than re-walked — so a write that changes what
//  rows DRAW under unchanged data is answered by a challenge: the one row the
//  record names is re-measured. Most tests here are a way an earlier version of
//  that went wrong, found by adversarial review; each was confirmed to fail with
//  the rule it pins removed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Row 200 of `aMovingRowIsNotMarkedChecked`: `.onRenderPass` stands in for an
/// animation in flight, because it declares the same thing an animatable
/// modifier does mid-flight — "what I measured is not a value to keep".
private struct MaybeMovingRow: View {
    let index: Int
    let width: WidthBox
    let moving: MovingFlag

    var body: some View {
        let text = Text(String(repeating: "\(index % 10)", count: index == 200 ? width.cells : 8))
        if index == 200, moving.value {
            text.onRenderPass { _ in }
        } else {
            text
        }
    }
}

/// `TallyRow` with its wide row's width read at build time, from a box a test
/// can change between frames without changing the rows' data.
private struct WidthBoxRow: View {
    let index: Int
    let wideRow: Int
    let width: WidthBox
    let tally: RowRenderTally

    var body: some View {
        tally.note(index)
        return Text(String(repeating: "\(index % 10)", count: index == wideRow ? width.cells : 8))
    }
}

/// Row 200 and row 300 each read their width from a box, and every row says
/// when it was built — the fixture of `aShrinkingWidestRowIsNotReWalked`.
private struct TwoWideRows: View {
    let index: Int
    let first: WidthBox
    let second: WidthBox
    let tally: RowRenderTally

    var body: some View {
        tally.note(index)
        return Text(
            String(
                repeating: "\(index % 10)",
                count: index == 200 ? first.cells : index == 300 ? second.cells : 8))
    }
}

@MainActor
@Suite("A windowed stack's kept content width")
struct ContentWidthChallengeTests {
    private static let rows = 400
    private static let wideRowWidth = 120

    /// The record is keyed on the rows' DATA, and a row draws more than its
    /// data: a units toggle, a "show details", a locale. Those arrive as a
    /// `@State` write, which takes the render cache's own memos with it — and
    /// deliberately does NOT take this record, because it lives in `@State` so
    /// that an arriving row cannot sweep it. So a write challenges the record
    /// instead of invalidating it: the one row it names as its widest is
    /// re-measured — here row 0, which every row is as wide as — and the record
    /// follows it.
    ///
    /// Without that, this is the original defect wearing a different trigger —
    /// the rows grow, the extent does not, and their tails are unreachable
    /// until the collection happens to change.
    @Test("A write that widens the rows is not served the old width")
    func aWriteChallengesTheKeptWidth() {
        let cells = WidthBox(cells: 8)
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext,
            row: { index in Text(String(repeating: "\(index % 10)", count: cells.cells)) })

        let narrow = frame().stripped
        #expect(
            !narrow.contains("\u{25C0}"), "8-cell rows need no horizontal bar: \(narrow)")

        // What a `@State` write does: the rows draw differently, and the cache
        // drops the subtree that drew them.
        cells.cells = 120
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        let wide = frame().stripped
        #expect(
            wide.contains("\u{25C0}"),
            "the widened rows are reachable: \(wide)")
    }

    /// The challenge's other direction, and why a narrower row is not simply
    /// taken at its word: when the widest row shrinks, some OTHER row may be the
    /// widest now, and only a walk can say which. So there are two wide rows —
    /// 200 at 120 and 300 at 60, both wider than the viewport — and they
    /// shrink one at a time. Taking the first shrink at its word would report 8
    /// and drop the bar while row 300 still needs it; keeping the old maximum
    /// after the second would leave the content scrollable into blank space
    /// that nothing draws.
    @Test("A write that narrows the widest row gives the width back")
    func aNarrowedWidestRowIsReWalked() {
        let first = WidthBox(cells: Self.wideRowWidth)
        let second = WidthBox(cells: 60)
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext,
            row: { index in
                Text(
                    String(
                        repeating: "\(index % 10)",
                        count: index == 200 ? first.cells : index == 300 ? second.cells : 8))
            })

        let before = frame().stripped
        #expect(before.contains("\u{25C0}"), "the 120-cell row needs a bar: \(before)")

        first.cells = 8
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        let one = frame().stripped
        #expect(
            one.contains("\u{25C0}"),
            "row 300 is still 60 cells wide, so its tail still needs the bar: \(one)")

        second.cells = 8
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        let both = frame().stripped
        #expect(
            !both.contains("\u{25C0}"),
            "no row is wider than the viewport, so nothing is left to scroll to: \(both)")
    }

    /// The case the widened outcome exists for: typing at the end of a
    /// document's longest line. Each keystroke widens the row the record names,
    /// and under the challenge's premise — the other rows did not move — the new
    /// maximum is that row's new width, so there is nothing a walk would add.
    /// Counted in measures rather than read off a clock: a walk is every row.
    @Test("A write that widens the widest row costs that row, not a walk")
    func aWidenedWidestRowIsNotReWalked() {
        let wide = WidthBox(cells: 60)
        let tally = RowRenderTally()
        let tuiContext = TUIContext()
        // Counted by body runs, not `.onRenderPass`: that modifier declares a
        // side effect so that memos decline around it, and the record is one of
        // them — every frame would walk, and the count would say nothing.
        let frame = twoAxisFrames(
            tuiContext: tuiContext,
            row: { index in WidthBoxRow(index: index, wideRow: 200, width: wide, tally: tally) })

        let before = frame()
        wide.cells = 240
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        tally.reset()
        let after = frame()
        #expect(
            tally.rendered.count < Self.rows / 4,
            "a widened widest row re-walked: \(tally.rendered.count) of \(Self.rows) rows built")
        #expect(tally.rendered.contains(200), "the challenged row is the one built")
        #expect(after != before, "the thumb did not move: \(after.debugDescription)")
        let fresh = twoAxisFrames(
            tuiContext: TUIContext(),
            row: { index in WidthBoxRow(index: index, wideRow: 200, width: wide, tally: tally) })()
        #expect(
            after == fresh,
            """
            the kept width is not the width a first frame finds: \
            kept \(after.debugDescription), fresh \(fresh.debugDescription)
            """)
    }

    /// The rule that keeps the verdict independent of which ask runs it: the
    /// challenged row is measured at the width it was FILED at, not at the
    /// asking width.
    ///
    /// Measured at a narrow ask's own limit, a row wider than the limit either
    /// clips to exactly the limit — unbreakable text — or WRAPS to a little
    /// under it, and a wrap looks like an honest width. So the first version
    /// failed a good record when a narrow ask came first (a bounded ask cannot
    /// walk, so it got the sampled width), got the kept one when a wide ask came
    /// first, and on a widening could mark the record checked at the WRAPPED
    /// width, which the next wide ask then served as the content's. Every
    /// combination of text, order and the row widening in between gives the
    /// same answers now.
    @Test(
        "A narrow ask gets the same answer whichever ask came first",
        arguments: [false, true], [false, true])
    func aChallengeMeasuresAtTheRecordsOwnWidth(breakable: Bool, wideFirst: Bool) {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext,
            row: { index in
                Text(index == 200 ? wideText(wide.cells, breakable: breakable) : "01234567")
            })
        #expect(ask(4_096) == Self.wideRowWidth, "the walk finds row 200")

        wide.cells = 200
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        if wideFirst {
            #expect(ask(4_096) == 200, "the wide ask follows row 200 to 200 cells")
        }
        #expect(
            ask(40) == 40,
            "the narrow ask \(wideFirst ? "after" : "before") the wide one lost the kept width")
        #expect(ask(4_096) == 200, "the next wide ask is not served a stale or wrapped width")
    }

    /// A write and an append in the SAME frame — which is every frame of a
    /// document someone types into while it grows. The collection only grew,
    /// so the record is EXTENDED rather than re-walked, and the challenge has
    /// to run on that path too, and its verdict — raised, or fallen — has to be
    /// honoured before the extension files anything. Row 7 is wider than the
    /// first rung, so this is also the case that made the challenge measure at
    /// the width the record was FILED at: challenged at the 4,096 rung's own
    /// width, a 6,000-cell row can only say "at least 4,096", and a first
    /// version of this took that as confirmation and served the next rung the
    /// old width. (That the extension inherits an UNCHECKED verdict rather than
    /// stamping it checked is `aMovingRowIsNotMarkedChecked(append: true)`.)
    @Test("A write and an append in one frame are both seen", arguments: [6_020, 5_980])
    func aWriteAndAnAppendInOneFrame(newWidth: Int) {
        let wide = WidthBox(cells: 6_000)
        let rows = WidthBox(cells: 400)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext, rows: { rows.cells },
            row: { index in Text(String(repeating: "0", count: index == 7 ? wide.cells : 8)) })
        #expect(ask(4_096) == 4_096, "row 7 saturates the first rung")
        #expect(ask(32_768) == 6_000, "and the second rung finds it")

        wide.cells = newWidth
        rows.cells = 401
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(ask(4_096) == 4_096, "row 7 still saturates the first rung")
        #expect(ask(32_768) == newWidth, "the second rung is served the old width")
    }

    /// The same, drawn: a toggle that changes the widest row, arriving with a
    /// new row, must look exactly like a first frame of the result — narrowed,
    /// so the extension must not carry the old maximum forward, and widened, so
    /// it must carry the RAISED one.
    @Test("An appended row does not carry a stale width with it", arguments: [8, 240])
    func anAppendCarriesTheChallenge(newWidth: Int) {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let rows = WidthBox(cells: Self.rows)
        func frames(_ tuiContext: TUIContext) -> () -> String {
            twoAxisFrames(
                tuiContext: tuiContext, rows: { rows.cells },
                row: { index in
                    Text(String(repeating: "\(index % 10)", count: index == 200 ? wide.cells : 8))
                })
        }
        let tuiContext = TUIContext()
        let kept = frames(tuiContext)
        _ = kept()

        wide.cells = newWidth
        rows.cells += 1
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        let after = kept()
        let fresh = frames(TUIContext())()
        #expect(
            after.stripped.contains("\u{25C0}") == (newWidth > 40),
            "row 200 at \(newWidth) cells in a 40-cell viewport: \(after.stripped)")
        #expect(
            after == fresh,
            "kept \(after.debugDescription), fresh \(fresh.debugDescription)")
    }

    /// A challenge whose measure read something that moves on its own answers
    /// the ask it serves, and does not mark the record checked — or an animation
    /// that is at its FIRST frame when the write lands would be filed at its
    /// starting width, and animation ticks are not writes, so nothing would ask
    /// again once it had moved. With an append in the same frame, the walk that
    /// extends the record must inherit "not checked" rather than stamp it.
    @Test("A row measured mid-animation is not marked checked", arguments: [false, true])
    func aMovingRowIsNotMarkedChecked(append: Bool) {
        let wide = WidthBox(cells: 60)
        let rows = WidthBox(cells: Self.rows)
        let moving = MovingFlag()
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext, rows: { rows.cells },
            row: { index in MaybeMovingRow(index: index, width: wide, moving: moving) })
        #expect(ask(4_096) == 60)

        moving.value = true
        wide.cells = 80
        if append { rows.cells += 1 }
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(ask(4_096) == 80, "the moving row answers the ask it serves")

        // An animation tick: the row moves again and settles, and nothing writes.
        moving.value = false
        wide.cells = 100
        #expect(ask(4_096) == 100, "the settled row was never asked again")
    }

    /// Growth alone, and the ceiling an inherited maximum can already be at.
    /// Row 7 is 6,000 cells, over the first rung's 4,096, so on that rung the
    /// answer is the ceiling before a single new row is measured — and a new row
    /// measured under that ceiling is not a width that can be kept beside one
    /// measured under a higher one: 8,000 cells of words WRAP to a little under
    /// 4,096 and look like an honest width. So the first rung stops where it
    /// stands, and the second measures the new row under a ceiling that holds it.
    @Test("A row appended wider than the first rung is not measured under it")
    func anAppendedRowIsMeasuredUnderARungThatHoldsIt() {
        let rows = WidthBox(cells: Self.rows)
        let ask = contentWidthAsks(
            tuiContext: TUIContext(), rows: { rows.cells },
            row: { index in
                Text(
                    index == 7
                        ? String(repeating: "0", count: 6_000)
                        : index == Self.rows ? wideText(8_000, breakable: true) : "01234567")
            })
        #expect(ask(4_096) == 4_096)
        #expect(ask(32_768) == 6_000)

        rows.cells += 1
        #expect(ask(4_096) == 4_096, "the first rung is saturated by row 7 alone")
        #expect(ask(32_768) == 8_000, "the appended row was filed at its wrapped width")
    }

    /// The challenge's third way to fall: the row reaching the width it was
    /// measured at. Unbreakable text clips to EXACTLY a proposal it overflows,
    /// so a row that grew from 3,000 cells to 6,000 re-measures as 4,096 under
    /// the 4,096 it was filed at — which is wider than the record, and without
    /// this rule would be raised to and stamped as checked, and every wider rung
    /// served 4,096 for a row with 1,904 cells past it.
    @Test("A row that outgrew the width it was measured at is re-walked")
    func aRowThatOutgrewItsMeasureFalls() {
        let wide = WidthBox(cells: 3_000)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext,
            row: { index in Text(String(repeating: "0", count: index == 7 ? wide.cells : 8)) })
        #expect(ask(4_096) == 3_000)

        wide.cells = 6_000
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(ask(4_096) == 4_096)
        #expect(ask(32_768) == 6_000, "the clipped width was kept as the row's")
    }

    /// The challenge MEASURES its row; it does not ask the row's memo. That
    /// memo compares only the row's element and survives a clear about some
    /// other identity — and a row measured but never drawn reads its
    /// `@Observable`s untracked, so a write to one clears the rows that were
    /// drawn and not this one. Here the clears are all about an identity that
    /// is no ancestor of the rows, so the memo is left holding whatever was
    /// last measured, and served it, the challenge certifies the width it
    /// exists to catch. A write that changes nothing and then three that do,
    /// because an earlier version bypassed the memo with a bumped generation —
    /// the SAME bumped generation every time — so an unchanged challenge filed
    /// its answer where the next challenge would look it up.
    @Test("The challenged row is measured, not remembered — every time")
    func theChallengeBypassesTheRowMemo() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext,
            row: { index in
                Text(String(repeating: "\(index % 10)", count: index == 200 ? wide.cells : 8))
            })
        #expect(ask(4_096) == Self.wideRowWidth)

        for cells in [Self.wideRowWidth, 200, 300, 250] {
            wide.cells = cells
            tuiContext.renderCache.clearAffected(by: ViewIdentity(path: "Elsewhere"))
            #expect(ask(4_096) == cells, "the challenge was served a memoized width")
        }
    }

    /// And when the challenge FALLS, the walk that follows must not be served
    /// the stale size the challenge just refused. The walk runs at its own
    /// rung, which need not be the width the challenge measured at — here the
    /// record was filed at 8,192 (the collection changed, so the 8,192 ask
    /// walked) and the fall is met at 4,096, where an earlier walk left the row
    /// memoized at 120 — so the fresh answer the challenge stored does not
    /// cover it, and the row's other sizes are dropped instead. Narrowed below
    /// the runner-up (row 300 at 60) the answer is 60, not 120; widened past
    /// the width it was measured at, it is its full 9,000. And the same beneath
    /// an `invalidatingMeasureMemo()`, where this pass's entries are filed
    /// under a hash with the generation folded in, and a drop that matched the
    /// plain identity hash missed every one of them.
    @Test(
        "The walk after a fallen challenge is not served the stale row",
        arguments: [50, 9_000], [false, true])
    func theWalkAfterAFallIsFresh(newWidth: Int, underInvalidatedMemo: Bool) {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let rows = WidthBox(cells: Self.rows)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext, rows: { rows.cells },
            underInvalidatedMemo: underInvalidatedMemo,
            row: { index in
                Text(
                    String(
                        repeating: "0",
                        count: index == 200 ? wide.cells : index == 300 ? 60 : 8))
            })
        #expect(ask(4_096) == Self.wideRowWidth)
        rows.cells -= 1
        #expect(ask(8_192) == Self.wideRowWidth, "a shorter collection is walked again")

        wide.cells = newWidth
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: "Elsewhere"))
        let expected = newWidth < 60 ? 60 : newWidth
        #expect(ask(4_096) == min(expected, 4_096), "the walk re-read the refused width")
        #expect(ask(65_536) == expected)
    }

    /// Holding Backspace at the end of the longest line: each keystroke is a
    /// write that narrows the row the record names. Only a walk can say which
    /// row is widest once it stops being this one — but while it is still at
    /// least as wide as the SECOND-widest, which the record keeps as a bound,
    /// the new maximum is exactly its new width, and a walk of every row per
    /// keystroke buys nothing. So it costs that row until it drops below row
    /// 300, and one walk then.
    @Test("Shrinking the widest row costs that row while it stays the widest")
    func aShrinkingWidestRowIsNotReWalked() {
        let first = WidthBox(cells: Self.wideRowWidth)
        let second = WidthBox(cells: 60)
        let tally = RowRenderTally()
        let tuiContext = TUIContext()
        let row = { (index: Int) in
            TwoWideRows(index: index, first: first, second: second, tally: tally)
        }
        let frame = twoAxisFrames(tuiContext: tuiContext, row: row)
        _ = frame()

        for cells in [110, 90, 61, 60, 50] {
            first.cells = cells
            tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
            tally.reset()
            let after = frame()
            let built = tally.rendered.count
            let fresh = twoAxisFrames(tuiContext: TUIContext(), row: row)()
            #expect(after == fresh, "at \(cells) cells the kept width is not a first frame's")
            if cells >= 60 {
                #expect(
                    built < Self.rows / 4,
                    "row 200 at \(cells) is still the widest, and \(built) rows were built")
            }
        }
    }

    /// The runner-up is carried through an EXTENSION, not re-derived from the
    /// rows the extension walked. Rows 200 (120) and 300 (60) are in the
    /// prefix; a row is appended, and then row 200 narrows to 50. Below the
    /// runner-up, so only a walk can say which row is widest — and it is row
    /// 300, at 60. An extension that forgot the prefix's runner-up would have
    /// kept only the appended row's 8 as the bound, and lowered to 50.
    @Test("The runner-up survives an extension")
    func theRunnerUpSurvivesAnExtension() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let rows = WidthBox(cells: Self.rows)
        let tuiContext = TUIContext()
        let ask = contentWidthAsks(
            tuiContext: tuiContext, rows: { rows.cells },
            row: { index in
                Text(
                    String(
                        repeating: "0",
                        count: index == 200 ? wide.cells : index == 300 ? 60 : 8))
            })
        #expect(ask(4_096) == Self.wideRowWidth)
        rows.cells += 1
        #expect(ask(4_096) == Self.wideRowWidth, "the extension kept the maximum")

        wide.cells = 50
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(ask(4_096) == 60, "the extension lost the runner-up, and lowered to 50")
    }

    /// A clear that keeps sizes promises that no cell moved — a paint, a tint,
    /// a colour ramp that turns every frame — so it must not cost a challenge
    /// per frame.
    @Test("A clear that keeps sizes does not challenge the width")
    func anInkClearIsNotAChallenge() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tally = RowRenderTally()
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext,
            row: { index in WidthBoxRow(index: index, wideRow: 200, width: wide, tally: tally) })
        _ = frame()

        let before = tuiContext.renderCache.sizeClearGeneration
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""), keepingSizes: true)
        #expect(tuiContext.renderCache.sizeClearGeneration == before)
        tally.reset()
        _ = frame()
        #expect(!tally.rendered.contains(200), "an ink-only clear re-measured the widest row")

        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(tuiContext.renderCache.sizeClearGeneration == before &+ 1)
        tally.reset()
        _ = frame()
        #expect(tally.rendered.contains(200), "a clear that drops sizes did not challenge")
    }
}
