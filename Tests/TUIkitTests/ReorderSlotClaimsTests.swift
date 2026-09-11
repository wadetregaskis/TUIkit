//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReorderSlotClaimsTests.swift
//
//  A row in hand is drawn only at the slot where it would land, as a faint copy —
//  and both twins built that copy from the row's lines alone. A translucent row
//  lost its claims there and showed at its opaque spelling for as long as it was
//  held. Both views are asserted, since the rule lives in two places.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A row in hand keeps its claims at the slot")
struct ReorderSlotClaimsTests {

    /// Six rows: the fixtures' frames hold them all, so no "N more" line or
    /// scrollbar joins the frame.
    private static let labels = (0..<6).map { "row\($0)" }

    /// Picked up from the keyboard and not yet moved: the slot sits where the row
    /// was, holding its faint copy.
    @Test("A List row held from the keyboard keeps its claims in the slot")
    func listKeyboardHold() {
        let fixture = ListReorderFixture(items: Self.labels, feedback: .dimmed)
        fixture.env.palette = FadedInk()
        fixture.render()
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        let held = fixture.render()

        #expect(fixture.handler?.reorder?.active == true, "a hold is in flight")
        #expect(showsFaintCopy(of: "row0", in: held), "the slot holds the row's faint copy")
        expectInkOnLabelsOnly(held)
    }

    /// A block of three held from the keyboard. The row the cursor is on stays at
    /// full strength while the others go faint, so it lost its claims without even
    /// the faint to soften it.
    @Test("A List block held from the keyboard keeps every row's claims in the slot")
    func listKeyboardHoldOfABlock() {
        let fixture = ListReorderFixture(items: Self.labels, feedback: .dimmed)
        fixture.selection = Set(Self.labels.prefix(3))
        fixture.env.palette = FadedInk()
        fixture.render()
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        let held = fixture.render()

        #expect(fixture.handler?.reorder?.held.count == 3, "the whole block is in hand")
        #expect(showsFaintCopy(of: "row1", in: held), "the slot holds the block's faint copies")
        expectInkOnLabelsOnly(held)
    }

    /// A mouse drag under `.dimmed`: the copy sits at the slot the pointer is over.
    @Test("A List row dragged under .dimmed keeps its claims in the slot")
    func listMouseDrag() {
        let fixture = ListReorderFixture(items: Self.labels, feedback: .dimmed)
        fixture.env.palette = FadedInk()
        let buffer = fixture.render()
        let target = fixture.rowY(buffer, "row3")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "row1")))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: target))
        let dragging = fixture.render()

        #expect(showsFaintCopy(of: "row1", in: dragging), "the slot holds the row's faint copy")
        expectInkOnLabelsOnly(dragging)
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: target))
    }

    /// The `Table` twin, which re-renders each held row from its data for the slot
    /// and kept the line and the pulse of that render, not its claims.
    @Test("A Table row dragged under .dimmed keeps its claims in the slot")
    func tableMouseDrag() throws {
        let fixture = TableReorderFixture(feedback: .dimmed)
        fixture.env.palette = FadedInk()
        let buffer = fixture.render()
        let target = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: target))
        let dragging = fixture.render()
        defer {
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: target))
        }

        let faded = owed(FadedInk().foreground)
        // The premise: a row still in place owes the faded ink, so the palette does
        // reach a Table's cells and the slot's copy has something to lose.
        let resting = try #require(cell(of: "a", onLine: fixture.rowY(dragging, "a"), in: dragging))
        #expect(owed(atColumn: resting.column, row: resting.row, in: dragging).ink == faded)
        let slotLine = try #require(
            dragging.lines.firstIndex { $0.contains(ANSIRenderer.dim) }, "a dimmed slot line")
        let copy = try #require(cell(of: "b", onLine: slotLine, in: dragging), "the slot holds row b's copy")
        let owes = owed(atColumn: copy.column, row: copy.row, in: dragging)
        #expect(owes.ink == faded, "the held row's copy owes \(owes)")
    }

    // MARK: - Helpers

    /// Whether a line draws `label` inside a faint run: the slot's copy.
    private func showsFaintCopy(of label: String, in frame: FrameBuffer) -> Bool {
        frame.lines.contains { $0.contains(ANSIRenderer.dim) && $0.stripped.contains(label) }
    }

    /// The cell where `letter` is drawn on line `row`, if that line draws it.
    private func cell(of letter: Character, onLine row: Int, in frame: FrameBuffer) -> (column: Int, row: Int)? {
        guard frame.lines.indices.contains(row) else { return nil }
        let line = frame.lines[row].stripped
        return line.firstIndex(of: letter).map { (column: line.distance(from: line.startIndex, to: $0), row: row) }
    }
}
