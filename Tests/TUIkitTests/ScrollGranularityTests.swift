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
    private func renderList(
        granularity: ScrollGranularity = .line,
        linesPerRow: Int = 3,
        wheelTicks: Int = 0
    ) -> String {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.stateStorage = tui.stateStorage
        env.lifecycle = tui.lifecycle
        env.keyEventDispatcher = tui.keyEventDispatcher
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        env.renderCache = tui.renderCache
        env.preferenceStorage = tui.preferences
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
}
