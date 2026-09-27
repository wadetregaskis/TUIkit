//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnchoredSeekNearTopTests.swift
//
//  A seek to a row near the top of the anchored window (more than 256 rows of
//  varying height) whose first rows are taller than the running pitch. The
//  seek placed the target at that pitch, and the anchor walk from there, by
//  exact pitches, is what puts the row on its line — but under a section's
//  header an offset in the header took the rows from row 0 instead, and the
//  target was left off screen. Placed exactly, the target's place must then
//  be read in the same coordinates by what the seek asks of it: the clamp to
//  the stack's end, and a minimal-movement seek's choice of edge — which, as
//  a near seek's walk does, reads the rows on screen from the anchor, and so
//  from the anchor at the frame's offset, not where the last frame left it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Row `index`: the rows in `tall` are `lines` lines each, every other row
/// one line — so once the view has scrolled into the one-line rows, the
/// running pitch prices the tall rows at a line or two.
@MainActor
private func tallHeadRow(_ index: Int, tall: Range<Int> = 0..<3, lines: Int = 5) -> Text {
    guard tall.contains(index) else { return Text("row \(index)") }
    return Text((["row \(index)"] + Array(repeating: "  of \(index)", count: lines - 1)).joined(separator: "\n"))
}

/// `count` rows (`tallHeadRow`) in a lazy stack — under a section's header
/// with `header` — or, with `flat`, the same lines in one eager column, whose
/// seek is exact. With `glued`, the view starts at its end and follows it.
private struct TallHeadPage: View {
    let box: SectionProxyBox
    let header: Bool
    let flat: Bool
    var count = 300
    var tall = 0..<3
    var lines = 5
    var glued = false

    var body: some View {
        ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            ScrollView { content }
                .defaultScrollAnchor(glued ? .bottom : nil)
                .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
                .frame(height: 8)
        }
    }

    @ViewBuilder private var content: some View {
        if flat {
            VStack(alignment: .leading, spacing: 0) {
                if header { Text("header") }
                ForEach(0..<count, id: \.self) { row($0) }
            }
        } else if header {
            Section("header") { rows }
        } else {
            rows
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { row($0) }
        }
    }

    private func row(_ index: Int) -> Text { tallHeadRow(index, tall: tall, lines: lines) }
}

/// A lazy page and its flat twin, each with its own context, drawn a frame at
/// a time together.
@MainActor
private struct TallHeadPair {
    let lazyBox = SectionProxyBox()
    let flatBox = SectionProxyBox()
    let lazyTUI = TUIContext()
    let flatTUI = TUIContext()
    let lazyFocus = FocusManager()
    let flatFocus = FocusManager()
    let page: (SectionProxyBox, Bool) -> TallHeadPage

    /// Draws one frame of each: the lazy page's, then the flat one's.
    @discardableResult
    func frame() -> (lazy: [String], flat: [String]) {
        (
            scrollFrame(page(lazyBox, false), tui: lazyTUI, focusManager: lazyFocus),
            scrollFrame(page(flatBox, true), tui: flatTUI, focusManager: flatFocus)
        )
    }

    /// Applies `move` to both pages, at event time.
    func apply(_ move: (SectionProxyBox) -> Void) {
        move(lazyBox)
        move(flatBox)
    }
}

@MainActor
@Suite("An anchored seek near the top lands its row where the flat column does")
struct AnchoredSeekNearTopTests {
    @Test(
        "A .bottom or .center seek to row 3, under rows taller than the running pitch, lands where it lands in the flat column",
        arguments: [UnitPoint.bottom, .center], [true, false])
    func seekNearTheTopLandsAsInTheFlatColumn(anchor: UnitPoint, header: Bool) {
        // Scrolled mid-list first, so the running pitch is the one-line rows'.
        // Before, under a header: the seek's priced offset fell in the header,
        // and an offset there placed the rows from row 0 — rows 0-2 are
        // fifteen lines, so row 3 was nowhere on the eight. With no header the
        // offset clamps to the stack's top, and the walk from the priced place
        // put row 3 on line 3, where the column puts it on line 7 (`.bottom`)
        // or 4 (`.center`).
        let pair = TallHeadPair { TallHeadPage(box: $0, header: header, flat: $1) }
        pair.frame()
        pair.apply { $0.position.scrollTo(y: 150) }
        pair.frame()
        pair.frame()
        pair.apply { $0.proxy?.scrollTo(3, anchor: anchor) }
        let (inLazy, inFlat) = pair.frame()
        #expect(inFlat.contains("row 3"), "precondition: the column shows the row: \(inFlat)")
        #expect(inLazy.firstIndex(of: "row 3") == inFlat.firstIndex(of: "row 3"), "\(inLazy) vs \(inFlat)")
        #expect(inLazy == inFlat)
    }

    @Test("A .top seek to a row under rows far taller than the whole list at the running pitch lands on line 0")
    func topSeekPastTheEstimatedEndLandsOnLineZero() {
        // Seven rows of sixty lines, then one-line rows, glued to the end. At
        // 250 rows the exact walk draws the end; at 300 the anchored window
        // does, measuring only one-line rows, so the running pitch is one and
        // the stack is priced at 300 lines. Row 7's exact top is line 420.
        // Before: the seek clamped that to the priced end, 292, 128 lines
        // short of the place the anchor was set at, and the anchor walk took
        // a gap that wide for a jump and placed the rows by estimate — the
        // screen showed rows in the twenties, and row 7 was nowhere on it.
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 0..<7, lines: 60, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.proxy?.scrollTo(7, anchor: .top) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.first == "row 7", "precondition: the column puts the row on line 0: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }

    @Test(
        "A far minimal-movement seek to a row above the screen, near the top, puts it on the top line",
        arguments: [5, 10])
    func farMinimalSeekUpLandsOnTheTopLine(lines: Int) {
        // Rows 0-6 of `lines` lines, glued to the end of 300 as above, then
        // scrolled to line 30 — a jump, placed at the running pitch of one:
        // rows 30 to 37. Row 7 is above them, so a seek that moves as little
        // as it can puts it on the top line, as the flat column puts a row
        // that is above its screen. Its exact top (35 or 70) was compared with
        // the offset, 30, which is at the pitch: at ten lines a row, below
        // the screen, and row 7 was put on the bottom line; at five, on it,
        // and nothing moved but the anchor — row 7 was drawn on line 5.
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 0..<7, lines: lines, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.position.scrollTo(y: 30) }
        let before = pair.frame().lazy
        #expect(before.first == "row 30", "precondition: the jump shows rows from 30: \(before)")
        pair.apply { $0.proxy?.scrollTo(7) }
        let seek = pair.frame().lazy
        let settled = pair.frame().lazy
        #expect(seek.first == "row 7", "\(seek)")
        #expect(seek == settled, "the frame after: \(settled)")
    }

    @Test(
        "A minimal-movement seek on the frame the stack first takes the anchored window moves from the rows on screen",
        arguments: [5, 100])
    func minimalSeekOnTheFirstAnchoredFrame(target: Int) {
        // Row 0 one line and rows 1-3 five, glued to the end at 250 rows (the
        // exact walk, which keeps no anchor), then grown to 300 in the frame
        // that seeks: the anchored window's first, which starts from the
        // anchor it has never walked, row 0. Row 5 and row 100 are above the
        // screen, so the column puts each on the top line. Before, row 100
        // was far from row 0 and after it, so it was taken for a row below
        // the screen and put on the bottom line; row 5 was near row 0 and
        // measured from it as if row 0 were at the top, found below the
        // screen, and the offset was moved down from the tail, not up to it.
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 1..<4, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        pair.apply { $0.proxy?.scrollTo(target) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.first == "row \(target)", "precondition: the column puts the row on line 0: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }

    @Test(
        "A minimal-movement seek to a row above the screen puts it on the top line, when the jump that took the screen past it is in the same frame too",
        arguments: [false, true], [12, 100])
    func minimalSeekAfterAJump(sameFrame: Bool, target: Int) {
        // As in the far seek above: from line 30 (rows 30 to 37), then a jump
        // to line 200 (rows from 200) and `scrollTo(target)`, in one frame or
        // the jump a frame first. Both rows are above the screen the jump
        // shows. Before, in the same frame, the seek moved from rows 30 to 37,
        // where the anchor was last drawn: row 100 was far from row 30 and
        // after it, so it went on the bottom line; row 12 was near and above
        // it, so the offset went up from 200 by the lines from row 12 to row
        // 30, and the screen showed rows from 182.
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 0..<7, lines: 10, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.position.scrollTo(y: 30) }
        let before = pair.frame().lazy
        #expect(before.first == "row 30", "precondition: the jump shows rows from 30: \(before)")
        pair.apply { $0.position.scrollTo(y: 200) }
        if !sameFrame {
            let jumped = pair.frame().lazy
            #expect(jumped.first == "row 200", "precondition: the jump shows rows from 200: \(jumped)")
        }
        pair.apply { $0.proxy?.scrollTo(target) }
        let seek = pair.frame().lazy
        let settled = pair.frame().lazy
        #expect(seek.first == "row \(target)", "\(seek)")
        #expect(seek == settled, "the frame after: \(settled)")
    }
}
