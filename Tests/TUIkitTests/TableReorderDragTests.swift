//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableReorderDragTests.swift
//
//  Mouse drag-to-reorder for a `Table.onMove` — the same gesture, state machine
//  and feedback modes as `List`'s (see ListReorderDragTests), driven here through
//  a Table's own geometry: a column header, "N more" indicators or a scrollbar,
//  and rows that are lines of text rather than child buffers.
//
//  The two views keep drifting apart where they hold the same rules in two
//  places, so the pairs that must agree are asserted on BOTH sides: the drop
//  index is a drawn position, the slot is a drop target, and a motionless press
//  is still a click.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table drag-to-reorder")
struct TableReorderDragTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        var name: String { id }
    }

    /// A row-order holder plus the pieces to render it. A reference type so the
    /// `onMove` closure — which fires during a later mouse dispatch, not during
    /// the render that installed it — writes straight back into `rows`.
    @MainActor
    private final class Fixture {
        var rows: [String]
        let reorderable: Bool
        /// Rows selected before the gesture. Non-empty switches the table to
        /// multi-selection, which is what makes a drag pick up a block.
        var selection: Set<String> = []
        private(set) var moves = 0
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(
            rows: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true,
            feedback: RowReorderFeedback = .live,
            scrollbar: ScrollbarVisibility = .hidden
        ) {
            self.rows = rows
            self.reorderable = reorderable
            env.focusManager = FocusManager()
            env.rowReorderFeedback = feedback
            env.scrollbarVisibility = scrollbar
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let move: (IndexSet, Int) -> Void = {
                self.moves += 1
                self.rows.move(fromOffsets: $0, toOffset: $1)
            }
            let table: AnyView
            if selection.isEmpty {
                let base = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                    TableColumn<Row>("Name", value: \.name)
                }
                table = AnyView(reorderable ? AnyView(base.onMove(move)) : AnyView(base))
            } else {
                let base = Table(
                    rows.map(Row.init),
                    selection: Binding(get: { self.selection }, set: { self.selection = $0 })
                ) {
                    TableColumn<Row>("Name", value: \.name)
                }
                table = AnyView(reorderable ? AnyView(base.onMove(move)) : AnyView(base))
            }
            let view = table.frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The table's own handler — the press focuses it, which is what makes
        /// it reachable from here.
        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        /// The screen line of the row whose text IS `label`, matched on its
        /// letters alone.
        ///
        /// Not "contains": a Table draws a column HEADER ("Name"), and matching
        /// by containment pressed that instead of row "a". And not the whole
        /// stripped line either: the scrollbar path appends a bar cell (▲/█/▼) to
        /// every row, which is why the same test passed without a bar and missed
        /// every row with one.
        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == label } ?? -1
        }

        /// Press on `source`'s line, drag to `target`'s, release there — with a
        /// render between each step, as the run loop has.
        func drag(from source: String, to target: String) {
            let buffer = render()
            let ySource = rowY(buffer, source)
            let yTarget = rowY(buffer, target)
            dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
            render()
            dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
            render()
            dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
            render()
        }
    }

    // MARK: - The gesture

    @Test("Dragging a row downward drops it after the target")
    func dragDown() {
        let fixture = Fixture()
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    @Test("Dragging a row upward drops it before the target")
    func dragUp() {
        let fixture = Fixture()
        fixture.drag(from: "d", to: "b")
        #expect(fixture.rows == ["a", "d", "b", "c", "e"])
    }

    @Test("A table with no onMove does not reorder", arguments: [true, false])
    func withoutOnMoveNothingMoves(scrollbar: Bool) {
        let fixture = Fixture(
            reorderable: false, scrollbar: scrollbar ? .visible : .hidden)
        fixture.drag(from: "a", to: "d")
        #expect(fixture.rows == ["a", "b", "c", "d", "e"], "the rows are exactly as they were")
    }

    @Test("A press released without moving is a click, not a reorder")
    func motionlessPressIsAClick() {
        let fixture = Fixture()
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: y))
        fixture.render()

        #expect(fixture.rows == ["a", "b", "c", "d", "e"])
        #expect(fixture.moves == 0, "nothing was moved by pressing and letting go")
    }

    /// The same gesture over a table that draws a scrollbar instead of "N more"
    /// indicators — a separate render path, and one that reserves no line above
    /// the rows, so the click-to-line mapping differs.
    @Test("Reordering works on the scrollbar path too")
    func dragWithScrollbar() {
        let fixture = Fixture(scrollbar: .visible)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    // MARK: - Feedback modes

    /// `.live` is the preview: the rows themselves move as the cursor crosses
    /// each slot, so one drag fires `onMove` more than once.
    @Test("Live feedback moves the rows as the drag goes")
    func liveMovesAsItGoes() {
        let fixture = Fixture(feedback: .live)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves >= 1, "the list itself was the preview")
    }

    /// `.dimmed` and `.cursor` take the row OUT and open a slot, so the table
    /// keeps its length mid-drag and the data moves exactly once, on the drop.
    @Test(
        "Dimmed and cursor feedback move the row exactly once, on the drop",
        arguments: [RowReorderFeedback.dimmed, .cursor])
    func slotModesMoveOnceOnDrop(feedback: RowReorderFeedback) {
        let fixture = Fixture(feedback: feedback)
        fixture.drag(from: "a", to: "c")
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
        #expect(fixture.moves == 1, "one move, at the drop — the drag showed a slot instead")
    }

    /// Mid-drag, the dragged row has left its place: the rows below close up and
    /// a slot opens where it would land. So the row is drawn once (in the slot,
    /// faintly, under `.dimmed`) — never twice.
    @Test("Mid-drag the row is out of the table, and the slot is where it lands")
    func midDragShowsTheSlot() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "a")
        let yTarget = fixture.rowY(buffer, "c")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        let dragging = fixture.render()

        let order = dragging.lines.compactMap { line -> String? in
            let text = line.stripped.filter { !"│╭╮╰╯─ ".contains($0) }
            return ["a", "b", "c", "d", "e"].contains(text) ? text : nil
        }
        #expect(
            order == ["b", "c", "a", "d", "e"],
            """
            the drawn order IS the order a drop would produce, with "a" appearing \
            once — in the slot: \(dragging.lines.map(\.stripped))
            """)

        // And the drop lands it exactly where the slot showed it.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        fixture.render()
        #expect(fixture.rows == ["b", "c", "a", "d", "e"])
    }

    /// The slot's own line is a drop target: after every step of the drag the
    /// pointer is resting on it, so releasing there must commit the move it has
    /// been advertising rather than reading as "off the rows".
    @Test("Releasing on the slot commits the move it was showing")
    func releaseOnTheSlotCommits() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "a")
        let yTarget = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        // Two steps to the same line: the second lands on the gap the first
        // opened there.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        fixture.render()

        #expect(fixture.rows == ["b", "c", "d", "a", "e"])
    }

    /// Dragging back to the row's own place is a legitimate destination — mid-drag
    /// it is the only way to change your mind — and it must leave the order alone.
    @Test("Dragging back to where it started changes nothing")
    func dragBackToTheOrigin() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let yOrigin = fixture.rowY(buffer, "b")
        let yAway = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: yOrigin))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yAway))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yOrigin))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yOrigin))
        fixture.render()

        #expect(fixture.rows == ["a", "b", "c", "d", "e"], "back where it started")
    }

    /// `.dimmed` draws the row itself, faint, at the slot it would land in — and
    /// it must be faint ALL the way along. A Table row is several styled runs
    /// (starting with the one-cell selection gutter) and each carries its own
    /// reset, so a `dim … reset` wrapper used to die before the first character
    /// and the row drew at full intensity. Asserting `contains(dim)` cannot see
    /// that; asserting that no reset is left un-reopened can.
    @Test("The dimmed slot stays faint past the row's own resets")
    func dimmedSlotIsFaintThroughout() {
        let fixture = Fixture(feedback: .dimmed)
        let buffer = fixture.render()
        let ySource = fixture.rowY(buffer, "b")
        let yTarget = fixture.rowY(buffer, "d")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        let dragging = fixture.render()

        guard let slot = dragging.lines.first(where: { $0.contains(ANSIRenderer.dim) }) else {
            Issue.record("expected a dimmed slot line"); return
        }
        guard let column = slot.stripped.firstIndex(of: "b").map({ slot.stripped.distance(from: slot.stripped.startIndex, to: $0) })
        else {
            Issue.record("the slot should hold a copy of the dragged row: \(slot.stripped)"); return
        }
        // The state in force AT the row's text — not merely somewhere on the
        // line. Everything before the last reset has been cancelled by it.
        let state = slot.ansiStateBefore(visibleColumn: column)
        let live = state.components(separatedBy: ANSIRenderer.reset).last ?? ""
        #expect(
            live.contains(ANSIRenderer.dim),
            "the dim was cancelled before the text: \(state.debugDescription)")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
    }

    /// The grabbed cell must stay under the pointer, so with the pointer held
    /// still the float must sit exactly on the row's own left edge. Measuring
    /// the grab from the first CLICKABLE column instead of the first ROW cell
    /// put it a cell out — and because the preview was the full-interior-width
    /// styled line, the overhang painted over the scrollbar and the border.
    @Test("The floating row lands on the row's own left edge")
    func cursorPreviewAnchorsToTheRow() {
        let fixture = Fixture(feedback: .cursor)
        let buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        guard let line = buffer.lines.first(where: { $0.stripped.contains("b") }),
            let textColumn = line.stripped.firstIndex(of: "b").map({
                line.stripped.distance(from: line.stripped.startIndex, to: $0)
            })
        else {
            Issue.record("expected a row line holding \"b\""); return
        }
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: textColumn, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: textColumn, y: y + 2))
        fixture.render()

        guard let frame = fixture.tui.dragAndDropSession.previewFrame(),
            let preview = fixture.tui.dragAndDropSession.active?.preview
        else {
            Issue.record("expected a floating row"); return
        }
        let previewText = preview.lines[0].stripped
        guard let inPreview = previewText.firstIndex(of: "b").map({
            previewText.distance(from: previewText.startIndex, to: $0)
        }) else {
            Issue.record("the float should be the row: \(previewText.debugDescription)"); return
        }
        #expect(
            frame.x + inPreview == textColumn,
            "the grabbed cell drifted off the pointer: float x \(frame.x) + \(inPreview)")
        #expect(
            frame.x + preview.width <= buffer.width - 1,
            "and the float stays inside the table's own frame, off the border and scrollbar")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: textColumn, y: y + 2))
    }

    /// What floats is the ROW, not the row as the grid drew it. The drawn line
    /// carries the focus/selection background and is padded out to the grid's
    /// interior — floating that painted a bar of highlight across the scrollbar
    /// column and the right border, because a styled blank is real content and
    /// the preview trim (rightly) keeps it.
    @Test("The floating row is the row itself, not its line in the grid")
    func cursorPreviewIsUnstyled() {
        let fixture = Fixture(feedback: .cursor, scrollbar: .visible)
        var buffer = fixture.render()
        let y = fixture.rowY(buffer, "b")
        // Select it first: the row you drag is normally the row you are on.
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y))
        buffer = fixture.render()

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        fixture.render()
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: y + 2))
        fixture.render()

        guard let frame = fixture.tui.dragAndDropSession.previewFrame(),
            let preview = fixture.tui.dragAndDropSession.active?.preview
        else {
            Issue.record("expected a floating row"); return
        }
        #expect(
            preview.lines[0].stripped.trimmingCharacters(in: .whitespaces) == "b",
            "the float is one row's content: \(preview.lines[0].stripped.debugDescription)")
        #expect(
            frame.x + preview.width <= buffer.width - 2,
            "it clears the scrollbar column and the border: x \(frame.x) w \(preview.width)")

        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y + 2))
    }

    /// A table with a wrapping column publishes no row bands at all until now,
    /// so the drag had nothing to hit-test: the row never moved AND the click
    /// was swallowed. Multi-line tables force `.live` feedback (no slot), so a
    /// successful drag is visible in the data.
    @Test("A multi-line table reorders by drag too")
    func multiLineDragReorders() {
        let rows = ["alpha beta gamma", "delta epsilon", "zeta eta"]
        let holder = MultiLineFixture(rows: rows)
        let buffer = holder.render()
        let ySource = holder.rowY(buffer, "alpha")
        let yTarget = holder.rowY(buffer, "zeta")
        #expect(ySource >= 0 && yTarget > ySource, "both rows on screen")

        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: ySource))
        holder.render()
        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 4, y: yTarget))
        holder.render()
        holder.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: yTarget))
        holder.render()

        #expect(holder.rows.first != rows[0], "the dragged row left the top: \(holder.rows)")
        #expect(Set(holder.rows) == Set(rows), "and nothing was lost")
    }

    /// A table whose column wraps — rows are taller than one line, so the band
    /// heights are what a click maps through.
    @MainActor
    private final class MultiLineFixture {
        var rows: [String]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(rows: [String]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

        @discardableResult
        func render() -> FrameBuffer {
            dispatcher.beginRenderPass()
            let view = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name).lineLimit(2)
            }
            .onMove { self.rows.move(fromOffsets: $0, toOffset: $1) }
            .frame(width: 14, height: 12)
            var context = RenderContext(
                availableWidth: 14, availableHeight: 14, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.contains(label) } ?? -1
        }
    }
    // MARK: - Several rows at once

    /// The `List` twin of this pair lives in ListReorderDragTests; the two views
    /// hold the same rule in two places and keep drifting, so both are asserted.
    /// Every row in hand has to be visible and moving — the slot stands for the
    /// whole block, so it is as tall as the rows it holds.
    @Test("A dimmed multi-row drag shows every row it is carrying")
    func dimmedMultiRowShowsThemAll() {
        let fixture = Fixture(feedback: .dimmed)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        let height = buffer.height
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        let dragging = fixture.render()

        let letters = dragging.lines.map { $0.stripped.filter(\.isLetter) }
        #expect(letters.contains("a"), "the grabbed row is on screen")
        #expect(letters.contains("b"), "and so is the one travelling with it")
        #expect(dragging.height == height, "and the table is no taller for it")
    }

    /// `.cursor` carries the block on the pointer, so the float is as tall as
    /// the block: one line per row, not just the row that was grabbed.
    @Test("A cursor multi-row drag floats every row it is carrying")
    func cursorMultiRowFloatsThemAll() {
        let fixture = Fixture(feedback: .cursor)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "d")))
        fixture.render()

        let floating = (session.active?.preview.lines ?? []).map { $0.stripped.filter(\.isLetter) }
        #expect(floating == ["a", "b"], "both rows ride the pointer, in order")
        // Grabbed by its SECOND row, so the block hangs one line higher than its
        // top — otherwise it jumps up under the pointer as the drag starts.
        #expect(session.active?.grabY == 1, "the grabbed row stays under the cursor")
    }
    /// Auto-scroll can make an "N more above" line appear mid-drag, and that
    /// line pushes every row down by one. The row geometry the gesture reads
    /// must follow: it used to be captured at the press, so from the moment the
    /// table left the top every drag position read one row low — the dragged row
    /// settling a row below the cursor, exactly as reported.
    @Test("A drag still tracks the cursor after the viewport leaves the top")
    func dragTracksAfterScrollingAwayFromTheTop() {
        let fixture = Fixture(rows: ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "b")))
        fixture.render()
        #expect(fixture.rows.first == "b", "the live drag has started")

        // What auto-scroll does: the viewport leaves the top, so an indicator
        // line appears above the rows and they all shift down one.
        fixture.handler?.scrollFine(by: 3)
        let scrolled = fixture.render()
        #expect(fixture.rowY(scrolled, "f") > 0, "row f is on screen after the scroll")

        // Drop ON row f. It must land there, not a row past it.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(scrolled, "f")))
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: fixture.rowY(scrolled, "f")))
        #expect(
            fixture.rows == ["b", "c", "d", "e", "f", "a", "g", "h", "i", "j"],
            "landed on the row under the cursor — got \(fixture.rows)")
    }
    /// The `List` twin of this lives in ListReorderDragTests: `.live` under the
    /// mouse shuffles the whole block as the pointer crosses slots, in the
    /// Table too, and nothing is drawn faint (that is the keyboard's cue).
    @Test("A live multi-row mouse drag shuffles the block, undimmed")
    func liveMultiRowShufflesAsItGoes() {
        let fixture = Fixture(feedback: .live)
        fixture.selection = ["a", "b"]
        let buffer = fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        #expect(fixture.handler?.heldRowCount == 2)
        #expect(fixture.handler?.effectiveReorderFeedback == .live, "the mouse keeps live")

        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        let dragging = fixture.render()
        #expect(fixture.rows == ["c", "a", "b", "d", "e"], "the block moved, live")
        #expect(
            !dragging.lines.contains { $0.contains("\u{1b}[2m") },
            "and nothing is dimmed — a pointer is its own indicator")
    }
    /// The float is a row in your hand, not a slice of the grid: a `.flexible`
    /// column pads its cell out to whatever interior is left, which made the
    /// floating row as wide as the table. It carries the VALUES, two cells
    /// apart.
    @Test("A cursor drag floats a condensed row, not a grid-width one")
    func cursorFloatIsCondensed() {
        let fixture = Fixture(rows: ["a", "b", "c"], feedback: .cursor)
        let buffer = fixture.render()
        let session = fixture.tui.dragAndDropSession
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: fixture.rowY(buffer, "a")))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: fixture.rowY(buffer, "c")))
        fixture.render()

        let float = try? #require(session.active?.preview.lines.first)
        // Gutter + "a" — nowhere near the 20-cell table it came from.
        #expect(
            (float?.strippedLength ?? 99) <= 4,
            "condensed to its content: \((float ?? "").debugDescription)")
        #expect(float?.stripped.filter(\.isLetter) == "a")
    }
    /// Empty is a state, not an absence: the table still occupies its frame,
    /// so it is still the thing under the pointer — clickable, focusable, and
    /// somewhere an enclosing `ScrollView` can find to reveal. It used to
    /// contribute no hit-test region of its own at all once its rows were gone.
    @Test("An empty table still claims its frame")
    func emptyTableStaysInteractive() throws {
        let fixture = Fixture(rows: [])
        let buffer = fixture.render()
        let focused = buffer.hitTestRegions.filter { $0.focusID != nil }
        #expect(!focused.isEmpty, "the container region carries the table's focusID")
        let region = try #require(focused.first)
        #expect(
            region.width > 1 && region.height > 1,
            "and covers the box, not a sliver: \(region.width)x\(region.height)")
    }
    /// `Table.dropDestination(for:action:)` — the row-level counterpart of
    /// `ForEach.dropDestination`, which a Table cannot have because its rows are
    /// values with no `ForEach` to attach one to. It opens the same landing slot
    /// a reorder does, and reports the index it opened at.
    @Test("A table takes a drop between its rows, and reports where")
    func tableRowDropDestination() throws {
        final class Log: @unchecked Sendable { var got: [(Int, [String])] = [] }
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)

        func render(_ rows: [String]) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name)
            }
            .dropDestination(for: String.self) { index, values in log.got.append((index, values)) }
            .frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let rows = ["a", "b", "c"]
        let buffer = render(rows)
        let rowY = try #require(
            buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == "b" })

        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 3, y: rowY)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        let hovering = render(rows)
        #expect(
            hovering.lines.firstIndex { $0.stripped.filter(\.isLetter) == "b" } == rowY + 1,
            "a gap opened at the pointer, pushing row b down one")

        #expect(tui.dragAndDropSession.performDrop(), "the table took it")
        #expect(log.got.first?.0 == 1, "before row b: \(log.got)")
        #expect(log.got.first?.1 == ["zzz"])

        // And an EMPTY table reports the only index there is.
        log.got.removeAll()
        _ = render([])
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 3, y: rowY)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render([])
        #expect(tui.dragAndDropSession.performDrop(), "an empty table takes it too")
        #expect(log.got.first?.0 == 0, "at index 0: \(log.got)")
    }
}
