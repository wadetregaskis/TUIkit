//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIndicatorContainerAnimationTests.swift
//
//  The half of the focus-indicator conversions that animate something a
//  CONTAINER draws — a section's ●, a list or table's cursor row, the "N more"
//  edge indicators — rather than a control's own glyphs (those are in
//  `FocusIndicatorAnimationTests`). Split when the one file crossed the length
//  limit; the assertions both halves are held to are shared, in
//  `FocusIndicatorAnimationSupport.swift`.
//
//  These are the awkward ones. A control's run sits where the control drew it;
//  a container's has to survive whatever the container does to its lines
//  afterwards — clipping at either end, an overscroll slide, an indicator row
//  pushing everything down — which is why each assembly path is pinned
//  separately rather than trusted to behave like its twin.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Focus indicator animation: containers")
struct FocusIndicatorContainerAnimationTests {

    // MARK: - Focus section indicator

    /// Two bordered boxes, each its own focus section, rendered twice: the first
    /// pass registers both sections, the second draws them with `active`
    /// activated — which is also the real sequence, since a section cannot be
    /// activated before it exists.
    ///
    /// Two, because one section on its own is always the active one: an
    /// "inactive section" only exists where there is another to be active
    /// instead.
    private func sectionBuffer(width: Int = 30, active: String = "first") -> FrameBuffer {
        let view = VStack {
            Box { Button("Play") {} }.focusSection("first")
            Box { Button("Stop") {} }.focusSection("second")
        }
        let context = makeRenderContext(width: width, height: 12)
        _ = renderToBuffer(view, context: context)
        context.environment.focusManager!.activateSection(id: active)
        return renderToBuffer(view, context: context)
    }

    /// The runs sitting on a box's top border row — the ●, and nothing else.
    private func borderRuns(_ buffer: FrameBuffer, row: Int) -> [AnimatedCellRun] {
        buffer.animatedCells.filter { $0.offsetY == row }
    }

    @Test("The ACTIVE section's border hands over its ●, and only it")
    func sectionIndicator() {
        let buffer = sectionBuffer(active: "first")
        let top = borderRuns(buffer, row: 0)
        #expect(top.count == 1, "the active section's ● is not on its top border")
        #expect(top.first?.offsetX == 1, "the ● sits just inside the corner")
        // The inactive box below it draws no ●, so its border row is bare. Its
        // top border is three rows down (border, button, border).
        #expect(borderRuns(buffer, row: 3).isEmpty, "an inactive section is breathing")
        expectReplayIsIdentity(buffer, "the section ● does not match the drawn cells")
    }

    @Test("Activating the other section moves the ● to it")
    func sectionIndicatorFollowsActivation() {
        // A run left on the old section would pulse a box that no longer holds
        // the focus — and still look plausible, because something is breathing.
        let buffer = sectionBuffer(active: "second")
        #expect(borderRuns(buffer, row: 0).isEmpty, "the ● stayed on the deactivated section")
        #expect(borderRuns(buffer, row: 3).count == 1, "the ● did not follow the activation")
    }

    @Test("A box too narrow for a ● leaves no run on its border")
    func sectionIndicatorNarrow() {
        // `BorderRenderer` declines to draw the ● when the inner width has no
        // cell to spare. A run left behind anyway would repaint the corner
        // forever — the exact failure two copies of that condition invite.
        let buffer = sectionBuffer(width: 3)
        #expect(borderRuns(buffer, row: 0).isEmpty)
        expectReplayIsIdentity(buffer, "a narrow box repainted its own border")
    }

    // MARK: - List cursor row

    /// A focused list whose cursor row is also selected — the one state in
    /// which a row's background breathes.
    private func selectedRowList(height: Int = 8) -> FrameBuffer {
        let list = List(selection: .constant("Alpha" as String?)) {
            ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { Text($0) }
        }
        return renderToBuffer(list, context: makeRenderContext(width: 30, height: height))
    }

    @Test("A focused list's selected row hands its whole line to the run loop")
    func listCursorRow() {
        let buffer = selectedRowList()
        expectAnimates(buffer, runs: 1, "list cursor row")
        let run = buffer.animatedCells[0]
        // The row sits one line down and one column in, past the border.
        #expect(run.offsetY == 1)
        #expect(run.offsetX == 1)
        // A background pulse recolours the row without moving a glyph.
        #expect(Set(run.frames.map(\.stripped)).count == 1, "the pulse changed the row's text")
        #expect(run.frames.allSatisfy { $0.strippedLength == run.width })
    }

    @Test("The run survives the scrollbar path too")
    func listCursorRowWithScrollbar() {
        // A list that overflows draws a scrollbar, and its rows are assembled by
        // a SECOND compose function with its own clipping and its own bar-cell
        // merge. Same rules in two places is how the two drift apart, so the
        // scrolling path is pinned separately.
        let list = List(selection: .constant("Alpha" as String?)) {
            ForEach((0..<40).map { $0 == 0 ? "Alpha" : "Row \($0)" }, id: \.self) { Text($0) }
        }
        let buffer = renderToBuffer(list, context: makeRenderContext(width: 30, height: 8))
        expectAnimates(buffer, runs: 1, "list cursor row, scrolling")
        // The run stops short of the bar's column — it must not repaint it.
        let run = buffer.animatedCells[0]
        #expect(run.offsetX + run.width < buffer.width - 1)
    }

    @Test("An unfocused list, or one whose cursor row is unselected, animates nothing")
    func listCursorRowStill() {
        let context = makeRenderContext(width: 30, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        let unfocused = renderToBuffer(
            List(selection: .constant("Alpha" as String?)) {
                ForEach(["Alpha", "Bravo"], id: \.self) { Text($0) }
            }, context: context)
        #expect(unfocused.animatedCells.isEmpty, "an unfocused list is breathing")

        // Focused, but the cursor row is not the selected one: the cursor row
        // gets the flat focus background, which does not animate.
        let unselected = renderToBuffer(
            List(selection: .constant(String?.none)) {
                ForEach(["Alpha", "Bravo"], id: \.self) { Text($0) }
            }, context: makeRenderContext(width: 30, height: 8))
        #expect(unselected.animatedCells.isEmpty, "an unselected cursor row is breathing")
    }

    // MARK: - Table cursor row

    /// Rows for the table cases. `Identifiable`, because a `Table`'s selection
    /// is by id.
    private struct Row: Identifiable, Sendable {
        let id: String
        let name: String
        let note: String
    }

    private var tableRows: [Row] {
        (0..<3).map { Row(id: "\($0)", name: "Row \($0)", note: "note \($0)") }
    }

    /// The same rows with a note long enough to wrap onto a second line, so the
    /// multi-line path really does produce a row taller than one line.
    private var wrappingTableRows: [Row] {
        (0..<3).map {
            Row(id: "\($0)", name: "Row \($0)", note: "a note long enough to wrap over two lines")
        }
    }

    /// A focused table whose cursor row is also selected, at whatever height —
    /// short enough and it fits, tall enough and it scrolls, which are
    /// different assembly paths inside the table.
    private func selectedRowTable(
        height: Int = 10, rows: [Row]? = nil, multiLine: Bool = false
    ) -> FrameBuffer {
        let data = rows ?? tableRows
        let table = Table(data, selection: .constant("0" as String?)) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Note", value: \Row.note).lineLimit(multiLine ? 2 : 1)
        }
        return renderToBuffer(table, context: makeRenderContext(width: 40, height: height))
    }

    @Test("A focused table's selected row hands its whole line to the run loop")
    func tableCursorRow() {
        let buffer = selectedRowTable()
        expectAnimates(buffer, runs: 1, "table cursor row")
        let run = buffer.animatedCells[0]
        // Past the border and the column header vertically; past the border
        // and the container's one cell of horizontal padding across.
        #expect(run.offsetY == 2)
        #expect(run.offsetX == 2)
        #expect(Set(run.frames.map(\.stripped)).count == 1, "the pulse changed the row's text")
    }

    @Test("The table's run survives the scrollbar path")
    func tableCursorRowWithScrollbar() {
        // An overflowing table draws a bar, and its rows go through a SECOND
        // assembly function with its own clipping and its own bar-cell merge.
        let many = (0..<40).map { Row(id: "\($0)", name: "Row \($0)", note: "note \($0)") }
        let buffer = selectedRowTable(height: 8, rows: many)
        expectAnimates(buffer, runs: 1, "table cursor row, scrolling")
        let run = buffer.animatedCells[0]
        #expect(run.offsetX + run.width < buffer.width - 1, "the run reaches the bar's column")
    }

    @Test("The table's run survives the multi-line path")
    func tableCursorRowMultiLine() {
        // A column with a line limit above 1 takes a THIRD assembly path, where
        // a row is several lines tall and each of them carries the background.
        let buffer = selectedRowTable(rows: wrappingTableRows, multiLine: true)
        // The row is two lines tall, and BOTH carry the background — so both
        // want a run, on consecutive rows. One run would leave half the
        // highlight frozen while the other half breathed.
        #expect(buffer.animatedCells.count == 2, "the multi-line path left the wrong runs")
        #expect(buffer.animatedCells.allSatisfy { $0.isAnimating })
        expectReplayIsIdentity(buffer, "the multi-line run does not match the drawn cells")
        let rows = buffer.animatedCells.map(\.offsetY).sorted()
        #expect(rows == [rows[0], rows[0] + 1])
    }

    @Test("An unfocused table, or one whose cursor row is unselected, animates nothing")
    func tableCursorRowStill() {
        let context = makeRenderContext(width: 40, height: 10)
        context.environment.focusManager!.register(FocusSentinel())
        let unfocused = renderToBuffer(
            Table(tableRows, selection: .constant("0" as String?)) {
                TableColumn("Name", value: \Row.name)
            }, context: context)
        #expect(unfocused.animatedCells.isEmpty, "an unfocused table is breathing")

        let unselected = renderToBuffer(
            Table(tableRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
            }, context: makeRenderContext(width: 40, height: 10))
        #expect(unselected.animatedCells.isEmpty, "an unselected cursor row is breathing")
    }

    // MARK: - "N more" scroll indicators

    /// A focused, overflowing list drawing text indicators rather than a bar.
    private func indicatorList(scrolled: Bool) -> FrameBuffer {
        let list = List(selection: .constant(String?.none)) {
            ForEach((0..<40).map { "Row \($0)" }, id: \.self) { Text($0) }
        }
        .scrollIndicatorStyle(.text)
        let context = makeRenderContext(width: 30, height: 8)
        var buffer = renderToBuffer(list, context: context)
        guard scrolled else { return buffer }
        // Scroll so BOTH indicators are showing — the top one only exists once
        // something is above the window.
        for _ in 0..<10 { _ = context.environment.focusManager!.dispatchKeyEvent(KeyEvent(key: .down)) }
        buffer = renderToBuffer(list, context: context)
        return buffer
    }

    @Test("A focused list's \"N more\" indicators hand their cells over")
    func scrollIndicatorsAnimate() {
        // The scrollbar-less focus cue. It used to resolve the clock as it
        // rendered, which re-rendered the page on every tick to recolour one
        // short line at each end.
        let buffer = indicatorList(scrolled: true)
        let text = buffer.lines.map(\.stripped)
        guard let topRow = text.firstIndex(where: { $0.contains("▲") }),
            let bottomRow = text.lastIndex(where: { $0.contains("▼") })
        else {
            Issue.record("expected both indicators: \(text)")
            return
        }
        let rows = Set(buffer.animatedCells.map(\.offsetY))
        #expect(rows.contains(topRow), "the ▲ indicator left no run")
        #expect(rows.contains(bottomRow), "the ▼ indicator left no run")
        expectReplayIsIdentity(buffer, "an indicator run does not match the drawn cells")
    }

    @Test("An unfocused list's indicators animate nothing")
    func scrollIndicatorsStill() {
        let context = makeRenderContext(width: 30, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(
            List(selection: .constant(String?.none)) {
                ForEach((0..<40).map { "Row \($0)" }, id: \.self) { Text($0) }
            }
            .scrollIndicatorStyle(.text),
            context: context)
        #expect(buffer.animatedCells.isEmpty)
    }

    // MARK: - Colour grids

    @Test("A focused 256-colour grid hands over its cursor swatch")
    func color256GridCursor() {
        // A cube swatch, which measures: the cursor on slots 0-15 holds still until the
        // terminal reports its sixteen (SteadyBreathCopiesOnUnmeasurableColourTests).
        let buffer = renderToBuffer(
            _Color256GridCore(selection: .constant(Color.palette(196)), focusID: "grid-anim"),
            context: makeRenderContext(width: 80, height: 24))
        expectAnimates(buffer, runs: 1, "256-colour grid cursor")
        // The cursor swatch and nothing else — a run per swatch would be 256
        // runs repainting cells that never change.
        #expect(buffer.animatedCells[0].width > 0)
    }

    @Test("An unfocused 256-colour grid animates nothing")
    func color256GridStill() {
        let context = makeRenderContext(width: 80, height: 24)
        context.environment.focusManager!.register(FocusSentinel())
        #expect(
            renderToBuffer(
                _Color256GridCore(selection: .constant(Color.palette(1)), focusID: "grid-still"),
                context: context
            ).animatedCells.isEmpty)
    }

    // MARK: - The reorder slot in hand

    @Test("A keyboard-held reorder slot breathes")
    func heldSlotPulses() {
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it — with the SAME pulse a focused, selected row uses. That came
        // from the live clock, so holding a row re-rendered the page ~20 times
        // a second for as long as you held it.
        let fixture = ListReorderFixture(items: (0..<6).map { "row\($0)" }, feedback: .dimmed)
        _ = fixture.render()
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        let held = fixture.render()

        #expect(fixture.handler?.reorder?.active == true, "a hold is in flight")
        #expect(!held.animatedCells.isEmpty, "the slot does not breathe")
        for run in held.animatedCells {
            #expect(run.isAnimating)
            #expect(
                Set(run.frames.map(\.stripped)).count == 1, "the pulse moved a glyph")
        }
        expectReplayIsIdentity(held, "the slot's run does not match the drawn cells")
    }
}
