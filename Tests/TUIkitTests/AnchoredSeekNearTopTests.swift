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
//  And the anchor the seek leaves is its target at that place, at the offset
//  it chose, near or far, so the walk to the offset after it is never taken
//  for a scrollbar jump.
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

    @Test(
        "A minimal-movement seek to a near row more than four screens of lines away lands where the column puts it",
        arguments: [true, false])
    func nearMinimalSeekFarInLines(up: Bool) {
        // Row 0 one line and every other row two, 300 rows. Glued to the end
        // (rows 296 to 299), `scrollTo(278)` is 18 rows up; from the top (rows
        // 0 to 4), `scrollTo(20)` is 20 rows down. Each is near enough to be
        // walked to from the rows on screen (`nilAnchorSeekOffset`), exactly,
        // and the column puts it on the edge it is past: row 278 on the top
        // line, row 20 on the bottom one. Before, the moves of 36 and 33
        // lines were more than four screens, and the anchor walk after the
        // seek took them for a scrollbar jump and placed the rows by the
        // running pitch, two lines, where row 0's one line puts every row a
        // line higher: row 278 was drawn a line low, under row 277's last,
        // and row 20 a line high, its second line below the screen.
        let target = up ? 278 : 20
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, tall: 1..<300, lines: 2, glued: up)
        }
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.proxy?.scrollTo(target) }
        let seek = pair.frame()
        let settled = pair.frame()
        let edge = up ? seek.flat.first : seek.flat.dropLast().last
        #expect(edge == "row \(target)", "precondition: the column puts the row on its edge: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }

    @Test("A minimal-movement seek to row 0, from rows a jump placed by the running pitch, shows it from its first line")
    func nearMinimalSeekToRowZeroAfterAJump() {
        // Rows 0-6 of ten lines and the rest one, glued to the end of 300 as
        // above, then scrolled to line 10: a jump, placed at the running pitch
        // of one, so rows 10 to 17 are drawn where the column shows row 1.
        // Row 0 is near them, and walked to from row 10 by the rows' exact
        // pitches its top is 63 lines above the stack's. `scrollTo(0)` moves
        // to the stack's top, which the seek takes for row 0's whatever the
        // walk says, as the column does. Before, the anchor walk after the
        // seek moved up the ten lines from row 10 to the offset, and drew row
        // 6 from its fourth line; pinned at the walk's place, row 0 would be
        // drawn from its tenth.
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 0..<7, lines: 10, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.position.scrollTo(y: 10) }
        let before = pair.frame().lazy
        #expect(before.first == "row 10", "precondition: the jump shows rows from 10: \(before)")
        pair.apply { $0.proxy?.scrollTo(0) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.first == "row 0", "precondition: the column shows row 0 from the top: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }

    @Test("A minimal-movement seek to a near row, on the frame a list of rows taller than row 0 grows onto the anchored window, is on screen")
    func nearMinimalSeekOnTheFirstAnchoredFrame() {
        // The same rows, glued to the end at 250 (the exact walk), grown to 300
        // in the frame that runs `scrollTo(280)`. That frame's anchor is walked
        // to the old tail's offset first, by the running pitch — row 0's one
        // line, since the window has measured nothing yet — so to row 299,
        // and row 280 is near it: 39 lines up. Before, the walk after the seek
        // took that for a jump, and the screen showed rows 226 to 229, and
        // held them.
        //
        // The column shows rows 246 to 249 when the seek runs, and puts row
        // 280, below them, on the bottom line. Walked to from row 299 it is
        // above the screen, and goes on the top line: the first anchored
        // frame's estimate, not this seek's (see the known remaining issues of
        // the commit that walks the anchor before a seek).
        var count = 250
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, count: count, tall: 1..<300, lines: 2, glued: true)
        }
        pair.frame()
        pair.frame()
        count = 300
        pair.apply { $0.proxy?.scrollTo(280) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.contains("row 280"), "precondition: the column shows the row: \(seek.flat)")
        #expect(seek.lazy.contains("row 280"), "\(seek.lazy)")
        #expect(settled.lazy == seek.lazy, "the frame after: \(settled.lazy)")
    }

    @Test(
        "A seek that shows the end of a row more than five screens tall shows it as the column does",
        arguments: [(150, UnitPoint?.some(.bottom)), (20, nil)])
    func seekToTheEndOfATallRow(target: Int, anchor: UnitPoint?) {
        // One row of sixty lines among 300 one-line rows, the view at the top.
        // `scrollTo(150, anchor: .bottom)` is a far seek; `scrollTo(20)`, a row
        // below the screen, a near one that puts it on the bottom edge. Each
        // makes the target the anchor at its top, and moves the offset 52 lines
        // down it, to its last eight. Before, the anchor walk after the seek
        // took those 52 lines for a scrollbar jump, and placed the rows by the
        // running pitch: the screen showed rows 6 to 13, or row 20's first
        // lines under rows 18 and 19.
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, tall: target..<(target + 1), lines: 60)
        }
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.proxy?.scrollTo(target, anchor: anchor) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(
            seek.flat == Array(repeating: "  of \(target)", count: 8),
            "precondition: the column shows the row's last lines: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }

    @Test(
        "A seek whose anchor lies outside the row shows the rows its offset names, as the column does",
        arguments: [(0..<3, 5, -0.5, 154), (0..<3, 5, 1.5, 139)])
    func seekAnchoredOutsideTheRow(tall: Range<Int>, lines: Int, y: Double, firstRow: Int) {
        // `UnitPoint(x:y:)` is public and the offset does not clamp its y, so a
        // seek can name lines past its target's end: y -0.5 on row 150 of one
        // line is four lines below its top. The seek hid those lines in the
        // target, whose pitch then clamped them away: the screen showed the
        // target on line 0, rows 150 to 157. Above the target's top (y 1.5)
        // the walk up from it was already right.
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: false, flat: $1, tall: tall, lines: lines)
        }
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.proxy?.scrollTo(150, anchor: UnitPoint(x: 0.5, y: y)) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.first == "row \(firstRow)", "precondition: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }
}

@MainActor
@Suite("A seek on the frame that refutes a short list's uniform rows lands where the column does")
struct UniformRefutingSeekTests {
    @Test(
        "A seek to the row under the one tall row of 200 shows it, as the column does",
        arguments: [UnitPoint?.none, .some(.bottom)], [false, true])
    func seekPastTheTallRow(anchor: UnitPoint?, header: Bool) {
        // Rows of one line, but row 190 of sixty. A stack under 256 rows takes
        // its rows for as tall as the first until a drawn row says otherwise,
        // and the scroll view's canvas is that measure's height: 200 lines.
        // `scrollTo(191)` drew row 190, which refuted it, and the exact walk
        // put row 191 on line 250 — past the canvas, whose lines there were
        // cut, and the offset was clamped back into row 190. Row 191 was never
        // shown, on the seek's frame or after. Under a section's header the
        // content answers through the header's relay.
        let pair = TallHeadPair {
            TallHeadPage(box: $0, header: header, flat: $1, count: 200, tall: 190..<191, lines: 60)
        }
        for _ in 0..<3 { pair.frame() }
        pair.apply { $0.proxy?.scrollTo(191, anchor: anchor) }
        let seek = pair.frame()
        let settled = pair.frame()
        #expect(seek.flat.last == "row 191", "precondition: \(seek.flat)")
        #expect(seek.lazy == seek.flat, "\(seek.lazy) vs \(seek.flat)")
        #expect(settled.lazy == settled.flat, "the frame after: \(settled.lazy) vs \(settled.flat)")
    }
}
