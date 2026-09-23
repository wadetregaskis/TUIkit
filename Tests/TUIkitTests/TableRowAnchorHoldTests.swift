//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowAnchorHoldTests.swift
//
//  The SIBLING of `ListRowAnchorHoldTests`. `Table` scrolls through the same
//  `ItemListHandler` as `List`, which made it easy to assume it inherited the
//  anchoring — `Documentation/Scroll-anchoring.md` §3.4 said "List / Table hold
//  too". It did not: `Table.resolveHandler` never captured
//  `environment.anchorPosition` at all, so every anchor behaviour (the row hold,
//  the wheel release, the edge follow) was dead there while its twin worked.
//
//  Sharing a handler type is not sharing behaviour when each view wires its own
//  per-frame inputs. Hence this file: whatever `List` is asserted to do with an
//  anchor, `Table` is asserted to do too.
//
//  And `Table` wires its handler from TWO places, so every case here runs
//  against BOTH: `resolveHandler` composes single-line rows, and
//  `buildMultiLineContent` composes rows whose column has a `.lineLimit(> 1)`,
//  building its own handler and re-deriving every per-frame input rather than
//  calling `resolveHandler`. The anchor capture and the `applyAnchorHold()`
//  call are written out separately in each. Until these cases were doubled the
//  whole suite stayed green with the multi-line pair deleted — 017683fa's
//  defect exactly, one path down.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct Row: Identifiable, Sendable {
    let id: Int
    var name: String { "row \(id)" }
}

/// The same rows, written wide enough to wrap.
private struct TallRow: Identifiable, Sendable {
    let id: Int
    /// The label REPEATED rather than padded with filler of its own: the row
    /// then wraps to exactly two lines whatever the id's digit count (`row 0`
    /// at 23 cells and `row 104` at 31 both land between one and two of the
    /// column's 22), which is what lets one `rowLines` describe every row here.
    ///
    /// It does NOT make every drawn line name its row: the wrap can fall inside
    /// a label (`… row` / `0`), so the row's LAST line is not reliably a match.
    /// Only the first line is — which is all `screenLine(of:in:)` asks for, and
    /// why `isFullyDrawn` measures from that line rather than counting matches.
    var name: String { Array(repeating: "row \(id)", count: 4).joined(separator: " ") }
}

@MainActor
@Suite("Table row-anchor hold")
struct TableRowAnchorHoldTests {

    // Every case below runs twice. `multiLine` picks which of `Table`'s two row
    // composers it exercises (see the note at the top of the file), and it is a
    // parameter threaded through rather than a second fixture because the shape
    // is a COLUMN property, so the row type has to change along with it.

    /// Lines per row: the unit every screen-line assertion here counts in.
    private func rowLines(_ multiLine: Bool) -> Int { multiLine ? 2 : 1 }

    /// Frame height, doubled for the two-line shape so a comparable number of
    /// ROWS is on screen: the cases scroll to row 20 of 30 and then edit the
    /// rows above it, which needs the window to hold more than a handful.
    private func frameHeight(_ multiLine: Bool) -> Int { multiLine ? 20 : 12 }

    /// The Table draws a top border, a column header and a bottom border, so
    /// the rows get `frameHeight(_:) - 3`.
    private func renderFrame(
        multiLine: Bool, ids: [Int], anchored: Int?, tui: TUIContext, fm: FocusManager,
        hiddenIndicators: Bool = false
    ) -> [String] {
        let height = frameHeight(multiLine)
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        if let anchored {
            env.anchorPosition = AnchorPositionBinding(.constant(.row(AnyHashable(anchored))))
        }
        let context = RenderContext(
            availableWidth: 28, availableHeight: height, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        // Two literal `Table`s rather than one over a shared row protocol: the
        // shape is a column property (`.lineLimit`), and the row type has to
        // differ with it because a one-line name in a `.lineLimit(2)` column
        // still composes as a one-line row.
        let buffer: FrameBuffer
        if multiLine {
            buffer = renderToBuffer(
                Table(ids.map(TallRow.init), selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \TallRow.name).lineLimit(2)
                }
                .scrollIndicators(hiddenIndicators ? .hidden : .automatic)
                .frame(height: height),
                context: context)
        } else {
            buffer = renderToBuffer(
                Table(ids.map(Row.init), selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \Row.name)
                }
                .scrollIndicators(hiddenIndicators ? .hidden : .automatic)
                .frame(height: height),
                context: context)
        }
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func screenLine(of row: Int, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains("row \(row)") && !$0.contains("row \(row)0") }
    }

    /// Whether every line of the row is on screen.
    ///
    /// Measured from where the row STARTS plus its height, not by counting the
    /// lines that name it: the wrap can split a label across the break (`… row`
    /// / `0`), so a fully drawn two-line row is not reliably two matches. The
    /// last frame line is the bottom border, so the last row line is the one
    /// before it.
    private func isFullyDrawn(_ row: Int, in lines: [String], multiLine: Bool) -> Bool {
        guard let start = screenLine(of: row, in: lines) else { return false }
        return start + rowLines(multiLine) - 1 <= lines.count - 2
    }

    @Test(
        "Anchoring the row already at the bottom of the viewport does not scroll the table",
        arguments: [false, true])
    func adoptingTheBottomRowLeavesTheOffsetAlone(multiLine: Bool) {
        // Under the default bar (spends no line) and with the indicators hidden
        // (spends none either). The single-line fallback subtracted the
        // reservation from a viewport that had ALREADY given the line up, so
        // designating the row on the last line scrolled by one under a bar and
        // by two with the indicators hidden. The "▲/▼ N more" style spends two
        // lines and was right all along.
        for hidden in [false, true] {
            let tui = TUIContext()
            let fm = FocusManager()
            let ids = Array(0..<30)
            let plain = renderFrame(
                multiLine: multiLine, ids: ids, anchored: nil, tui: tui, fm: fm, hiddenIndicators: hidden)
            // The last FULLY drawn row, not merely the last one with a line on
            // screen. They are the same row on the single-line shape; on the
            // multi-line one the bottom row is usually half-clipped, and
            // designating a clipped row is a request to REVEAL it, so the
            // table is right to scroll and the case would be asserting the
            // opposite of what it means.
            guard
                let bottom = ids.last(where: { isFullyDrawn($0, in: plain, multiLine: multiLine) }),
                let before = screenLine(of: bottom, in: plain)
            else {
                Issue.record("no rows drawn (hidden=\(hidden))")
                continue
            }
            let after = renderFrame(
                multiLine: multiLine, ids: ids, anchored: bottom, tui: tui, fm: fm, hiddenIndicators: hidden)
            #expect(
                screenLine(of: bottom, in: after) == before,
                "hidden=\(hidden): row \(bottom) moved from line \(before) to \(String(describing: screenLine(of: bottom, in: after)))")
            #expect(screenLine(of: 0, in: after) != nil, "hidden=\(hidden): the table scrolled")
        }
    }

    private func settle(
        multiLine: Bool, ids: [Int], anchored: Int, tui: TUIContext, fm: FocusManager
    ) -> Int? {
        var lines: [String] = []
        for _ in 0..<4 {
            lines = renderFrame(multiLine: multiLine, ids: ids, anchored: anchored, tui: tui, fm: fm)
        }
        return screenLine(of: anchored, in: lines)
    }

    @Test(
        "Inserting rows above the anchored row holds it on its screen line",
        arguments: [false, true])
    func insertAboveHoldsTheRow(multiLine: Bool) {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)
        let anchored = 20

        guard let before = settle(multiLine: multiLine, ids: ids, anchored: anchored, tui: tui, fm: fm) else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        ids.insert(contentsOf: 100..<105, at: 15)
        let after = renderFrame(multiLine: multiLine, ids: ids, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), now \(after)")
    }

    @Test(
        "Deleting rows above the anchored row also holds it",
        arguments: [false, true])
    func deleteAboveHoldsTheRow(multiLine: Bool) {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)
        let anchored = 20

        guard let before = settle(multiLine: multiLine, ids: ids, anchored: anchored, tui: tui, fm: fm) else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        ids.removeSubrange(5..<10)
        let after = renderFrame(multiLine: multiLine, ids: ids, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), now \(after)")
    }

    /// The contrast, matching `ListRowAnchorHoldTests`: with no bound anchor a
    /// Table does NOT hold, so the machinery is provably what does the work and
    /// an un-anchored Table is unaffected by it.
    @Test(
        "Without a bound anchor the same insert DOES move the row",
        arguments: [false, true])
    func withoutAnchorTheRowMoves(multiLine: Bool) throws {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)

        _ = settle(multiLine: multiLine, ids: ids, anchored: 20, tui: tui, fm: fm)
        let before = renderFrame(multiLine: multiLine, ids: ids, anchored: nil, tui: tui, fm: fm)

        // Watch the row at the TOP of the viewport, not the row 20 the
        // anchored tests watch. Holding the offset pushes row 20 five rows past
        // the bottom, so `screenLine` answers nil for it — and `nil != Optional`
        // is true no matter what happened, including a viewport that jumped
        // somewhere else entirely. The control has to compare two real lines.
        let watched = 15
        let lineBefore = try #require(
            screenLine(of: watched, in: before),
            "row \(watched) was not on screen to begin with: \(before)")

        ids.insert(contentsOf: 100..<105, at: 5)
        let after = renderFrame(multiLine: multiLine, ids: ids, anchored: nil, tui: tui, fm: fm)
        let lineAfter = try #require(
            screenLine(of: watched, in: after),
            "row \(watched) left the screen entirely: \(after)")
        #expect(
            lineAfter == lineBefore + 5 * rowLines(multiLine),
            "an un-anchored Table holds the offset, so the row shifts down by the five inserted rows: \(before) → \(after)")
    }
}
