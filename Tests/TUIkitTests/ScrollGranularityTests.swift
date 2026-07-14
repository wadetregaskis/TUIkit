//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollGranularityTests.swift
//
//  `.scrollGranularity(_:)` — line-centric scrolling (the default) steps the
//  viewport one terminal LINE at a time through multi-line rows, clipping the
//  top row partially; row granularity (opt-in) keeps the classic
//  whole-row-jump behaviour. Selection and focus stay row-based in both.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scroll granularity (line vs row)")
struct ScrollGranularityTests {

    // MARK: - Handler stepping

    /// A handler over `count` rows of `height` lines each, in a viewport
    /// sized for `visibleRows` whole rows.
    private func makeHandler(
        count: Int, rowHeight: Int, contentHeight: Int, granularity: ScrollGranularity
    ) -> ItemListHandler<Int> {
        let handler = ItemListHandler<Int>(
            focusID: "test", itemCount: count,
            viewportHeight: max(1, contentHeight / rowHeight),
            selectionMode: .single)
        handler.contentHeight = contentHeight
        handler.rowHeight = { _ in rowHeight }
        handler.scrollGranularity = granularity
        handler.itemIDs = Array(0..<count)
        return handler
    }

    @Test("Line granularity: each fine step moves one line through a tall row")
    func lineStepsThroughTallRow() {
        let handler = makeHandler(count: 10, rowHeight: 3, contentHeight: 9, granularity: .line)

        #expect(handler.scrollFine(by: 1))
        #expect(handler.scrollOffset == 0)
        #expect(handler.scrollTopClipLines == 1, "first step clips one line off the top row")

        #expect(handler.scrollFine(by: 1))
        #expect(handler.scrollTopClipLines == 2)

        #expect(handler.scrollFine(by: 1))
        #expect(handler.scrollOffset == 1, "third step rolls into the next row")
        #expect(handler.scrollTopClipLines == 0)
    }

    @Test("Line granularity: stepping back up re-enters the previous row's last line")
    func lineStepsBackUp() {
        let handler = makeHandler(count: 10, rowHeight: 3, contentHeight: 9, granularity: .line)
        handler.scrollOffset = 2
        handler.scrollTopClipLines = 0

        #expect(handler.scrollFine(by: -1))
        #expect(handler.scrollOffset == 1)
        #expect(handler.scrollTopClipLines == 2, "enters the row above at its LAST line")

        #expect(handler.scrollFine(by: -2))
        #expect(handler.scrollOffset == 1)
        #expect(handler.scrollTopClipLines == 0)

        #expect(!handler.scrollFine(by: -100) || handler.scrollOffset == 0)
        handler.scrollFine(by: -100)
        #expect(handler.scrollOffset == 0 && handler.scrollTopClipLines == 0, "clamped at the top")
        #expect(!handler.scrollFine(by: -1), "at the very top a further up-step reports no movement")
    }

    @Test("Row granularity: fine steps jump whole rows (the classic behaviour)")
    func rowGranularityJumpsRows() {
        let handler = makeHandler(count: 10, rowHeight: 3, contentHeight: 9, granularity: .row)

        #expect(handler.scrollFine(by: 1))
        #expect(handler.scrollOffset == 1)
        #expect(handler.scrollTopClipLines == 0, "row granularity never clips")
    }

    @Test("Single-line rows: line and row granularity are identical")
    func singleLineRowsIdentical() {
        let line = makeHandler(count: 10, rowHeight: 1, contentHeight: 5, granularity: .line)
        let row = makeHandler(count: 10, rowHeight: 1, contentHeight: 5, granularity: .row)
        for _ in 0..<3 {
            line.scrollFine(by: 1)
            row.scrollFine(by: 1)
        }
        #expect(line.scrollOffset == row.scrollOffset)
        #expect(line.scrollTopClipLines == 0)
    }

    @Test("Line granularity stops at the row-aligned bottom (no clip past maxOffset)")
    func lineStopsAtBottom() {
        let handler = makeHandler(count: 4, rowHeight: 3, contentHeight: 9, granularity: .line)
        handler.scrollFine(by: 100)
        #expect(handler.scrollOffset == handler.maxOffset)
        #expect(handler.scrollTopClipLines == 0, "the bottom rest position is row-aligned")
        #expect(!handler.scrollFine(by: 1), "no movement past the bottom")
    }

    @Test("Focus reveal clears the top clip so the focused row is fully visible")
    func revealClearsClip() {
        let handler = makeHandler(count: 10, rowHeight: 3, contentHeight: 9, granularity: .line)
        handler.scrollFine(by: 1)  // (row 0, clip 1)
        #expect(handler.scrollTopClipLines == 1)

        handler.focusedIndex = 0
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollTopClipLines == 0, "the focused top row must be fully shown")
        #expect(handler.scrollOffset == 0)
    }

    @Test("clampTopClip zeroes the clip under row granularity and at the bottom")
    func clampTopClipRules() {
        let handler = makeHandler(count: 10, rowHeight: 3, contentHeight: 9, granularity: .line)
        handler.scrollTopClipLines = 2
        handler.scrollGranularity = .row
        handler.clampTopClip()
        #expect(handler.scrollTopClipLines == 0)

        handler.scrollGranularity = .line
        // maxOffset short-circuits to a cheap floor until the offset nears
        // the tail (documented ItemListHandler behaviour) — walk there with
        // fine steps the way real scrolling does, then verify the bottom
        // clears any residual clip.
        handler.scrollFine(by: 1000)
        #expect(handler.scrollOffset == 8, "10×3-line rows in 9 lines bottom out at row 8")
        handler.scrollTopClipLines = 2
        handler.clampTopClip()
        #expect(handler.scrollTopClipLines == 0)
    }

    // MARK: - List rendering

    /// Renders a six-row list (each row `linesPerRow` tall), delivers
    /// `wheelTicks` wheel events through the real mouse-dispatch path (each
    /// event is the default three fine steps), and returns the final frame's
    /// stripped lines.
    /// Like ``renderList(granularity:linesPerRow:wheelTicks:)`` but returns
    /// every frame's buffer, for asserting across-scroll invariants (constant
    /// height, partial bottom rows).
    private func renderListFrames(
        granularity: ScrollGranularity = .line,
        linesPerRow: Int = 3,
        wheelTicks: Int = 0
    ) -> [FrameBuffer] {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        env.scrollGranularity = granularity
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        let view = List(selection: .constant(String?.none)) {
            ForEach(["a", "b", "c", "d", "e", "f"], id: \.self) { name in
                Text((1...linesPerRow).map { "\(name)-\($0)" }.joined(separator: "\n"))
            }
        }
        .frame(height: 11)

        func renderOnce() -> FrameBuffer {
            var context = RenderContext(
                availableWidth: 24, availableHeight: 14, environment: env, tuiContext: tui)
            context.hasExplicitWidth = true
            context.hasExplicitHeight = true
            return renderToBuffer(view, context: context)
        }

        var frames = [renderOnce()]
        for _ in 0..<wheelTicks {
            let buffer = frames[frames.count - 1]
            dispatcher.setRegions(buffer.hitTestRegions)
            guard let region = buffer.hitTestRegions.max(by: { $0.height < $1.height }) else {
                Issue.record("expected the list's hit-test region")
                break
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown, phase: .scrolled,
                    x: region.offsetX + 2, y: region.offsetY + 2))
            frames.append(renderOnce())
        }
        return frames
    }

    private func renderList(
        granularity: ScrollGranularity = .line,
        linesPerRow: Int = 3,
        wheelTicks: Int = 0
    ) -> String {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        env.scrollGranularity = granularity
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        let view = List(selection: .constant(String?.none)) {
            ForEach(["a", "b", "c", "d", "e", "f"], id: \.self) { name in
                Text((1...linesPerRow).map { "\(name)-\($0)" }.joined(separator: "\n"))
            }
        }
        .frame(height: 11)

        func renderOnce() -> FrameBuffer {
            var context = RenderContext(
                availableWidth: 24, availableHeight: 14, environment: env, tuiContext: tui)
            context.hasExplicitWidth = true
            context.hasExplicitHeight = true
            return renderToBuffer(view, context: context)
        }

        var buffer = renderOnce()
        for tick in 0..<wheelTicks {
            dispatcher.setRegions(buffer.hitTestRegions)
            guard let region = buffer.hitTestRegions.max(by: { $0.height < $1.height }) else {
                Issue.record("expected the list's hit-test region")
                break
            }
            _ = tick
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown, phase: .scrolled,
                    x: region.offsetX + 2, y: region.offsetY + 2))
            buffer = renderOnce()
        }
        return buffer.lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("List (line granularity): the height stays constant, clipping the bottom row")
    func listLineGranularityConstantHeight() {
        // Three-line rows in an 11-line frame: the content area can't hold a
        // whole number of rows, so the bottom row must be PARTIALLY clipped
        // — never pushing the list taller — and the height must not change
        // as the window scrolls through different row phases.
        let frames = renderListFrames(linesPerRow: 3, wheelTicks: 5)
        let heights = Set(frames.map(\.height))
        #expect(heights.count == 1, "the list's height never changes: \(frames.map(\.height))")

        // At the top: rows a and b fit whole; row c is clipped mid-row.
        let first = frames[0].lines.map(\.stripped).joined(separator: "\n")
        #expect(first.contains("c-1"), "the partial bottom row's first lines show:\n\(first)")
        #expect(!first.contains("c-3"), "…but its last line is clipped off:\n\(first)")
    }

    @Test("List (line granularity): a wheel event moves three LINES, clipping the top row")
    func listRendersClippedTopRow() {
        // Four-line rows: one wheel event (three fine steps) leaves the top
        // row partially visible — its first three lines scrolled off, its
        // fourth still on screen.
        let body = renderList(linesPerRow: 4, wheelTicks: 1)
        #expect(!body.contains("a-3"), "the top row's first three lines are scrolled off:\n\(body)")
        #expect(body.contains("a-4"), "the top row's last line still shows:\n\(body)")
        #expect(body.contains("more above"), "the above indicator marks the partial row:\n\(body)")
    }

    @Test("List (row granularity): a wheel event moves three whole ROWS")
    func listRowGranularityJumpsWholeRow() {
        let body = renderList(granularity: .row, wheelTicks: 1)
        #expect(!body.contains("a-1") && !body.contains("c-3"), "rows a-c entirely gone:\n\(body)")
        #expect(body.contains("d-1"), "row d is the new top — 3 rows per event:\n\(body)")
    }

    @Test("List (line granularity): repeated ticks reach the bottom row-aligned")
    func listLineTicksReachBottom() {
        let body = renderList(wheelTicks: 30)
        #expect(body.contains("f-3"), "the last row's last line is reachable:\n\(body)")
        #expect(!body.contains("more below"), "nothing remains below at the bottom:\n\(body)")
    }

    // MARK: - Table rendering

    /// The Table Demo's fixed-height shape: variable-height rows (lineLimit
    /// wraps them to 1-3 lines) in a fixed frame, driven by real wheel
    /// events. Mirrors the List harness above — the Table line-granularity
    /// path shipped with NO render coverage, and the demo's toggle silently
    /// did nothing.
    private struct NoteRow: Identifiable {
        let id: Int
        let index: String
        let note: String
    }

    private func renderTableFrames(
        granularity: ScrollGranularity = .line,
        wheelTicks: Int = 0
    ) -> [FrameBuffer] {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        // The page-level default deliberately DIFFERS from the demo's own
        // .scrollGranularity modifier (applied on the table below), which
        // must win for its subtree.
        env.scrollGranularity = granularity == .line ? .row : .line
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        // Rows n1…n9: the first is one line, the rest wrap to three — chosen
        // so whole rows UNDERFILL the viewport at offset 0 (1+3+3 = 7 of 8
        // budget lines), the exact phase where a row-granular window leaves
        // line mode a hole and row mode a shrunken table.
        let rows = (1...9).map { n in
            NoteRow(
                id: n, index: "n\(n)",
                note: n == 1
                    ? "w1x0"
                    : (0...2).map { "w\(n)x\($0) word word" }.joined(separator: " "))
        }
        // The demo's exact wrapper: the table sits inside the page's outer
        // ScrollView (content measured at natural height), in a VStack.
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("caption")
                Table(rows, selection: .constant(Set<Int>())) {
                    TableColumn("#", value: \NoteRow.index).width(.fixed(4))
                    TableColumn("Note", value: \NoteRow.note).width(.flexible).lineLimit(3)
                }
                .frame(height: 12)
                .scrollbarVisibility(.visible)
                .scrollGranularity(granularity)
            }
        }

        func renderOnce() -> FrameBuffer {
            var context = RenderContext(
                availableWidth: 30, availableHeight: 16, environment: env, tuiContext: tui)
            context.hasExplicitWidth = true
            context.hasExplicitHeight = true
            return renderToBuffer(view, context: context)
        }

        var frames = [renderOnce()]
        for _ in 0..<wheelTicks {
            let buffer = frames[frames.count - 1]
            dispatcher.setRegions(buffer.hitTestRegions)
            guard let region = buffer.hitTestRegions.max(by: { $0.height < $1.height }) else {
                Issue.record("expected the table's hit-test region")
                break
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown, phase: .scrolled,
                    x: region.offsetX + 2, y: region.offsetY + 2))
            frames.append(renderOnce())
        }
        return frames
    }

    /// The table's own bordered height (╭ to ╰) — the outer ScrollView pads
    /// the buffer to a constant size, so `buffer.height` can NOT detect the
    /// table's frame breathing; only the border box can.
    private func tableBoxHeight(_ buffer: FrameBuffer) -> Int {
        let stripped = buffer.lines.map(\.stripped)
        guard let top = stripped.firstIndex(where: { $0.contains("╭") }),
            let bottom = stripped.lastIndex(where: { $0.contains("╰") })
        else { return 0 }
        return bottom - top + 1
    }

    @Test("Table (line granularity): the height stays constant while scrolling")
    func tableLineGranularityConstantHeight() {
        let frames = renderTableFrames(wheelTicks: 6)
        let heights = frames.map(tableBoxHeight)
        #expect(Set(heights).count == 1, "the table's box never changes: \(heights)")
    }

    @Test("Table (row granularity): the height ALSO stays constant (padded)")
    func tableRowGranularityConstantHeight() {
        // Whole rows can't always fill the viewport exactly; the shortfall
        // must be padded — a fixed-height table's frame never breathes as
        // rows of different heights scroll through.
        let frames = renderTableFrames(granularity: .row, wheelTicks: 6)
        let heights = frames.map(tableBoxHeight)
        #expect(Set(heights).count == 1, "the table's box never changes: \(heights)")
    }

    @Test("Table (line granularity): a wheel event moves LINES, not whole rows")
    func tableLineGranularityMovesLines() {
        let frames = renderTableFrames(wheelTicks: 1)
        let before = frames[0].lines.map(\.stripped).joined(separator: "\n")
        let after = frames[1].lines.map(\.stripped).joined(separator: "\n")
        // n1 is one line, n2 is three: one wheel event (three fine steps)
        // scrolls past n1 and clips into n2 — n2's later lines remain while
        // its first wrapped line is gone.
        #expect(before.contains("n1"), "precondition — top row visible:\n\(before)")
        #expect(!after.contains("n1"), "the one-line first row scrolled off:\n\(after)")
        // One wheel = three fine steps: past n1 (one line) and two lines
        // into n2 — only n2's LAST wrapped line remains visible.
        #expect(
            after.contains("w2x2") && !after.contains("w2x0"),
            "row n2 shows only its tail (first lines clipped):\n\(after)")
    }

    @Test("Table (row granularity): the same wheel event jumps whole rows")
    func tableRowGranularityJumpsWholeRows() {
        let frames = renderTableFrames(granularity: .row, wheelTicks: 1)
        let after = frames[1].lines.map(\.stripped).joined(separator: "\n")
        #expect(!after.contains("n1"), "row 1 gone:\n\(after)")
        // Row granularity never clips: whichever row is now on top shows
        // from its FIRST wrapped line.
        if after.contains("w2x1") {
            #expect(after.contains("w2x0"), "row-granularity rows are whole:\n\(after)")
        }
    }
}
