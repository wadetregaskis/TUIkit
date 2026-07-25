//  🖥️ TUIKit — Terminal UI Kit for Swift
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
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct Row: Identifiable, Sendable {
    let id: Int
    var name: String { "row \(id)" }
}

@MainActor
@Suite("Table row-anchor hold")
struct TableRowAnchorHoldTests {

    /// Interior height: the Table draws a top border, a column header and a
    /// bottom border, so the rows get `height - 3`.
    private static let height = 12

    private func renderFrame(
        ids: [Int], anchored: Int?, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        let rows = ids.map { Row(id: $0) }
        let table = Table(rows, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name)
        }
        .frame(height: Self.height)

        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        if let anchored {
            env.anchorPosition = .constant(.row(AnyHashable(anchored)))
        }
        let context = RenderContext(
            availableWidth: 28, availableHeight: Self.height, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(table, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func screenLine(of row: Int, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains("row \(row)") && !$0.contains("row \(row)0") }
    }

    private func settle(
        ids: [Int], anchored: Int, tui: TUIContext, fm: FocusManager
    ) -> Int? {
        var lines: [String] = []
        for _ in 0..<4 {
            lines = renderFrame(ids: ids, anchored: anchored, tui: tui, fm: fm)
        }
        return screenLine(of: anchored, in: lines)
    }

    @Test("Inserting rows above the anchored row holds it on its screen line")
    func insertAboveHoldsTheRow() {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)
        let anchored = 20

        guard let before = settle(ids: ids, anchored: anchored, tui: tui, fm: fm) else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        ids.insert(contentsOf: 100..<105, at: 15)
        let after = renderFrame(ids: ids, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), now \(after)")
    }

    @Test("Deleting rows above the anchored row also holds it")
    func deleteAboveHoldsTheRow() {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)
        let anchored = 20

        guard let before = settle(ids: ids, anchored: anchored, tui: tui, fm: fm) else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        ids.removeSubrange(5..<10)
        let after = renderFrame(ids: ids, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), now \(after)")
    }

    /// The contrast, matching `ListRowAnchorHoldTests`: with no bound anchor a
    /// Table does NOT hold, so the machinery is provably what does the work and
    /// an un-anchored Table is unaffected by it.
    @Test("Without a bound anchor the same insert DOES move the row")
    func withoutAnchorTheRowMoves() {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<30)

        _ = settle(ids: ids, anchored: 20, tui: tui, fm: fm)
        let before = renderFrame(ids: ids, anchored: nil, tui: tui, fm: fm)
        let lineBefore = screenLine(of: 20, in: before)

        ids.insert(contentsOf: 100..<105, at: 5)
        let after = renderFrame(ids: ids, anchored: nil, tui: tui, fm: fm)
        #expect(
            screenLine(of: 20, in: after) != lineBefore,
            "an un-anchored Table holds the POSITION, so the row shifts: \(before) → \(after)")
    }
}
