//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuTests.swift
//
//  `Menu` in both styles: `.automatic` (a collapsed label that opens a
//  floating menu) and `.inline` (the items expanded in place).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Menu")
struct MenuTests {

    // MARK: - Harness

    private func harness(width: Int = 40, height: Int = 24, overlayContentHeight: Int? = nil)
        -> (TUIContext, RenderContext)
    {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        // A status bar of this frame's own: the environment no longer
        // hands out a shared instance, which is what let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        environment.focusManager = FocusManager()
        // Predates the visibility/style split (#555): these assertions are written
        // against the "N more above / below" lines, which are now a style. The
        // shipped default is a scrollbar; cases about THAT ask for it by name.
        environment.scrollIndicatorStyle = .text
        environment.applyRuntimeServices(from: tui)
        if let overlayContentHeight { environment.overlayContentHeight = overlayContentHeight }
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// Renders `view` through a full frame and arms the mouse dispatcher, so a
    /// following click lands on the regions this frame published.
    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext)
        -> FrameBuffer
    {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        // Composite before arming: a presented menu's regions live inside its
        // overlay until the overlays are flattened, which is what the run loop
        // does before it hands the frame to the dispatcher.
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        // The focus pass closes too, as the run loop closes it: that is where
        // an unfinished Home/End resumes against the rows this pass laid out.
        context.environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    private func lines(_ buffer: FrameBuffer) -> [String] { buffer.lines.map(\.stripped) }

    // MARK: - Inline style

    @Test("An inline menu renders its label as a heading over every item")
    func inlineRendersHeadingAndItems() {
        let (tui, context) = harness()
        let view = Menu("Main Menu") {
            Button("Text Styles") {}
            Button("Colors") {}
            Button("Quit") {}
        }
        .menuStyle(.inline)

        let out = lines(renderArmed(view, tui: tui, context: context))
        #expect(out.count == 7, "border + heading + rule + 3 items + border, got \(out)")
        #expect(out[1].contains("Main Menu"))
        #expect(out[2].contains("──"), "a rule separates the heading: \(out[2])")
        #expect(out[3].contains("Text Styles"))
        #expect(out[4].contains("Colors"))
        #expect(out[5].contains("Quit"))
    }

    @Test("An inline menu's paging keys move its cursor, not just the view")
    func inlinePagingMovesTheCursor() {
        // The report: on a menu taller than the terminal, Page Up/Down and
        // Home/End felt dead. They were scrolling — the focus ring's answer for
        // keys a focused control declines — and leaving the highlight behind,
        // so the cursor was off screen and the next arrow key snapped the view
        // back to it. A menu is a list; its paging keys move its cursor.
        withColorDepth(.truecolor) {
            let (tui, context) = harness(height: 9)
            let view = Menu("Menu") {
                ForEach(0..<12, id: \.self) { index in Button("Item \(index)") {} }
            }
            .menuStyle(.inline)

            /// The item text on the row the cursor is on — the one row whose
            /// fill differs from its neighbours' (every row carries the menu's
            /// own surface, so "has a background" does not distinguish them).
            func cursorRow(_ buffer: FrameBuffer) -> String? {
                let rows = buffer.lines.filter { $0.contains("Item ") }
                func fill(_ line: String) -> String {
                    line.ranges(of: "48;2;").first.map {
                        String(line[$0.lowerBound...].prefix(16))
                    } ?? ""
                }
                let counts = rows.reduce(into: [String: Int]()) { $0[fill($1), default: 0] += 1 }
                return rows.first { counts[fill($0)] == 1 }?.stripped
                    .trimmingCharacters(in: .whitespaces)
            }

            let start = cursorRow(renderArmed(view, tui: tui, context: context))
            #expect(start?.contains("Item 0") == true, "the first row starts focused: \(start ?? "-")")

            #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .pageDown)))
            let paged = cursorRow(renderArmed(view, tui: tui, context: context))
            #expect(paged != start, "Page Down left the cursor where it was")

            #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .end)))
            // Two frames: a menu taller than the terminal lays out only the
            // rows it can show, so the first frame reaches the last row laid
            // out and scrolls; the second lays out the rows that revealed and
            // the jump finishes against them (see `pendingSubtreeJump`).
            _ = renderArmed(view, tui: tui, context: context)
            let last = cursorRow(renderArmed(view, tui: tui, context: context))
            #expect(last?.contains("Item 11") == true, "End is the last row: \(last ?? "-")")

            #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .home)))
            _ = renderArmed(view, tui: tui, context: context)
            let home = cursorRow(renderArmed(view, tui: tui, context: context))
            #expect(home?.contains("Item 0") == true, "Home is the first row: \(home ?? "-")")

            // Pressing Home again is a no-op for the cursor — it is already
            // there — and the menu still takes the key, because "go to the top"
            // is also an instruction to the view.
            _ = tui.keyEventDispatcher.dispatch(KeyEvent(key: .home))
            #expect(
                cursorRow(renderArmed(view, tui: tui, context: context))?.contains("Item 0") == true,
                "the cursor stayed where it was")
        }
    }

    @Test("An arrow key after End is not undone")
    func arrowAfterEndSticks() {
        // The latch that lets Home/End keep travelling while more rows are laid
        // out was re-armed unconditionally, so it never cleared: every later
        // pass re-ran the jump, and an Up pressed after End was snapped back to
        // the last row at the end of its own render. The arrow key read as
        // dead.
        withColorDepth(.truecolor) {
            let (tui, context) = harness(height: 9)
            let view = Menu("Menu") {
                ForEach(0..<12, id: \.self) { index in Button("Item \(index)") {} }
            }
            .menuStyle(.inline)
            func cursorRow(_ buffer: FrameBuffer) -> String? {
                let rows = buffer.lines.filter { $0.contains("Item ") }
                func fill(_ line: String) -> String {
                    line.ranges(of: "48;2;").first.map {
                        String(line[$0.lowerBound...].prefix(16))
                    } ?? ""
                }
                let counts = rows.reduce(into: [String: Int]()) { $0[fill($1), default: 0] += 1 }
                return rows.first { counts[fill($0)] == 1 }?.stripped
                    .trimmingCharacters(in: .whitespaces)
            }

            _ = renderArmed(view, tui: tui, context: context)
            #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .end)))
            // Let the jump settle (it travels as rows are laid out).
            for _ in 0..<4 { _ = renderArmed(view, tui: tui, context: context) }
            #expect(
                cursorRow(renderArmed(view, tui: tui, context: context))?.contains("Item 11") == true)

            // Up, and it stays up.
            context.environment.focusManager!.focusPreviousInSection()
            let afterUp = cursorRow(renderArmed(view, tui: tui, context: context))
            #expect(
                afterUp?.contains("Item 10") == true,
                "the arrow was undone by a stale jump: \(afterUp ?? "-")")
        }
    }

    @Test("A menu leaves the paging keys alone when the cursor is elsewhere")
    func inlinePagingIsScopedToTheCursor() {
        // The handler is registered per SECTION, not per control, so a menu
        // sharing a page with other controls would otherwise answer a Page Down
        // aimed at the page — moving its own cursor instead of scrolling what
        // the reader was looking at.
        let (tui, context) = harness(height: 9)
        let view = VStack(alignment: .leading, spacing: 0) {
            Button("outside") {}.focusID("outside")
            Menu("Menu") {
                ForEach(0..<8, id: \.self) { index in Button("Item \(index)") {} }
            }
            .menuStyle(.inline)
        }

        _ = renderArmed(view, tui: tui, context: context)
        context.environment.focusManager!.focus(id: "outside")
        _ = renderArmed(view, tui: tui, context: context)

        #expect(
            !tui.keyEventDispatcher.dispatch(KeyEvent(key: .pageDown)),
            "the menu answered a key aimed past it")
        #expect(
            context.environment.focusManager!.isFocused(id: "outside"),
            "and it moved the focus it does not own")
    }

    @Test("Every row of a menu is the same width, and the menu hugs its widest")
    func inlineRowsShareOneWidth() {
        let (tui, context) = harness()
        let view = Menu("Menu") {
            Button("A") {}
            Button("A rather longer item") {}
        }
        .menuStyle(.inline)

        let buffer = renderArmed(view, tui: tui, context: context)
        let widths = Set(buffer.lines.map(\.strippedLength))
        #expect(widths.count == 1, "uniform width, got \(widths)")
        #expect(buffer.width < context.availableWidth, "the menu hugs rather than fills")
    }

    /// CJK is the case that catches width arithmetic done in Characters: 文件
    /// is two characters but four cells.
    @Test("CJK labels still yield uniform-width rows")
    func inlineCJKWidth() {
        let (tui, context) = harness(width: 80)
        let view = Menu("設定") {
            Button("文件") {}
            Button("AB") {}
        }
        .menuStyle(.inline)

        let buffer = renderArmed(view, tui: tui, context: context)
        #expect(Set(buffer.lines.map(\.strippedLength)).count == 1)
    }

    @Test("Items render as menu rows, not as buttons")
    func inlineItemsAreMenuRows() {
        let (tui, context) = harness()
        let view = Menu("Menu") {
            Button("Cut") {}
            Button("Copy") {}
        }
        .menuStyle(.inline)

        for row in lines(renderArmed(view, tui: tui, context: context))
        where row.contains("Cut") || row.contains("Copy") {
            // The default button chrome is half-block caps around the label; a
            // menu row is the bare label on a highlight bar.
            #expect(
                !row.contains("▐") && !row.contains("▌"),
                "a menu row carries no button chrome, got \(row.debugDescription)")
        }
    }

    @Test("A Divider between items renders as a rule spanning the menu")
    func inlineDivider() {
        let (tui, context) = harness()
        let view = Menu("Menu") {
            Button("First") {}
            Divider()
            Button("Second") {}
        }
        .menuStyle(.inline)

        let buffer = renderArmed(view, tui: tui, context: context)
        let out = lines(buffer)
        // border + heading + rule + First + divider + Second + border
        #expect(out.count == 7, "got \(out)")
        #expect(out[4].contains("──"), "the divider is a rule: \(out[4].debugDescription)")
        #expect(out[4].strippedLength == buffer.width, "…spanning the menu's width")
    }

    /// The behaviour the old bespoke windowing provided, now from the shared
    /// dialog machinery: a menu with more items than the terminal has rows
    /// stays inside its budget instead of running off the bottom.
    @Test("A menu taller than the available height fits it, and scrolls instead")
    func inlineTallMenuFitsTheHeight() {
        let (tui, context) = harness(height: 10)
        let view = Menu("Menu") {
            ForEach(1...30, id: \.self) { index in
                Button("Item \(index)") {}
            }
        }
        .menuStyle(.inline)

        let buffer = renderArmed(view, tui: tui, context: context)
        #expect(
            buffer.height <= 10,
            "the menu must fit the height it was offered, got \(buffer.height)")
        #expect(lines(buffer).contains { $0.contains("Item 1") }, "…showing the top: \(lines(buffer))")
    }

    @Test("Walking the focus past the fold scrolls the menu to follow")
    func inlineTallMenuFollowsFocus() {
        let (tui, context) = harness(height: 10)
        let view = Menu("Menu") {
            ForEach(0..<20, id: \.self) { index in
                Button("Item \(index)") {}.focusID("item-\(index)")
            }
        }
        .menuStyle(.inline)

        _ = renderArmed(view, tui: tui, context: context)
        _ = renderArmed(view, tui: tui, context: context)
        context.environment.focusManager?.focus(id: "item-15")
        let out = lines(renderArmed(view, tui: tui, context: context))
        #expect(
            out.contains { $0.contains("Item 15") },
            "the focused item must be scrolled into view: \(out)")
    }

    // MARK: - Automatic (pop-up) style

    @Test("A pop-up menu is CLOSED until it is activated")
    func popupStartsClosed() {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("Rename") {}
            Button("Delete") {}
        }

        let buffer = renderArmed(view, tui: tui, context: context)
        let out = lines(buffer)
        #expect(buffer.height == 1, "just the collapsed label, got \(out)")
        #expect(out[0].contains("Actions"))
        #expect(out[0].contains(DropdownMenu.closedCaret), "…marked as openable")
        #expect(!out.contains { $0.contains("Rename") }, "the items are not on screen: \(out)")
        #expect(buffer.overlays.isEmpty, "and nothing is presented")
    }

    @Test("Clicking the label opens the items over the page; choosing one closes it")
    func popupOpensAndCloses() throws {
        let (tui, context) = harness()
        var chosen = "—"
        let view = Menu("Actions") {
            Button("Rename") { chosen = "Rename" }
            Button("Delete") { chosen = "Delete" }
        }

        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))

        let opened = renderArmed(view, tui: tui, context: context)
        let popup = try #require(opened.overlays.first).content
        let rows = lines(popup)
        #expect(rows.contains { $0.contains("Rename") }, "the items float over the page: \(rows)")
        #expect(rows.contains { $0.contains("Delete") })
        #expect(
            opened.lines[0].stripped.contains(DropdownMenu.openCaret),
            "the label says it is open: \(opened.lines[0].stripped)")

        // Choosing an item runs its action and dismisses the menu.
        let itemY = try #require(rows.firstIndex { $0.contains("Delete") })
        let overlay = try #require(opened.overlays.first)
        let y = overlay.offsetY + itemY
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: y))
        #expect(chosen == "Delete")

        let closed = renderArmed(view, tui: tui, context: context)
        #expect(closed.overlays.isEmpty, "the menu closed behind the choice")
    }

    @Test("Escape closes an open pop-up menu")
    func escapeCloses() {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("Rename") {}
        }

        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        let opened = renderArmed(view, tui: tui, context: context)
        #expect(!opened.overlays.isEmpty, "sanity: it opened")

        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .escape)))
        let closed = renderArmed(view, tui: tui, context: context)
        #expect(closed.overlays.isEmpty)
    }

    @Test("Measuring a pop-up menu opens nothing and presents no section")
    func measuringOpensNothing() {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("Rename") {}
        }

        tui.keyEventDispatcher.clearHandlers()
        // `measureChild` sets `isMeasuring` itself.
        let size = measureChild(
            view, proposal: ProposedSize(width: 40, height: 24), context: context)
        #expect(size.height == 1, "the footprint is the collapsed label")
        #expect(tui.keyEventDispatcher.handlerCount == 0, "a measure registers nothing")
    }

    // MARK: - Focus emphasis

    /// The highlight must resolve through the shared focus-emphasis clock, not
    /// read `pulsePhase` itself. Two symptoms of getting this wrong, both of
    /// which the owner saw: the row breathes on a 2.0 s cycle while every other
    /// focused control on screen is on 0.8 s, and `.selectionIndicatorStyle`
    /// does not reach it.
    @Test("The highlighted row honours .selectionIndicatorStyle(.none)")
    func highlightHonoursTheIndicatorStyle() {
        let view = Menu("Menu") {
            Button("First") {}
            Button("Second") {}
        }
        .menuStyle(.inline)
        .selectionIndicatorStyle(.none)

        func frame(pulsePhase: Double) -> [String] {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            // A status bar of this frame's own: the environment no longer
            // hands out a shared instance, which is what let a parallel
            // neighbour's items be read back as this test's.
            environment.statusBar = StatusBarState()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.pulsePhase = pulsePhase
            let context = RenderContext(
                availableWidth: 40, availableHeight: 24, environment: environment,
                tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            context.environment.focusManager?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            return buffer.lines
        }

        #expect(
            frame(pulsePhase: 0) == frame(pulsePhase: 1),
            "with the animation off, the pulse clock must not reach the row at all")
    }

    // MARK: - Selection on open

    /// Opens `view`'s pop-up by clicking its label, as the given device.
    ///
    /// The run loop stamps the input source at its own event funnel (see
    /// `App.run`), which the harness has to mirror: it dispatches straight to
    /// the dispatchers, one level below where the stamp happens.
    private func openPopup(
        _ view: some View, as source: FocusManager.InputSource, tui: TUIContext,
        context: RenderContext
    ) {
        _ = renderArmed(view, tui: tui, context: context)
        context.environment.focusManager?.noteInputSource(source)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        _ = renderArmed(view, tui: tui, context: context)
    }

    /// The menu the navigation tests drive.
    ///
    /// `.selectionIndicatorStyle(.none)` because the highlight (and the open
    /// menu's border) otherwise breathes on a WALL-CLOCK timer: two frames taken
    /// at different moments then differ in every styled cell, and reading the
    /// highlight out of the drawn frame would be reading the clock. With the
    /// animation off the emphasis resolves to one steady colour, and the only
    /// thing that can differ between two frames is which row is highlighted.
    private var threeItemMenu: some View {
        Menu("Actions") {
            Button("Rename") {}
            Button("Duplicate") {}
            Button("Delete") {}
        }
        .selectionIndicatorStyle(.none)
    }

    /// The open pop-up's own buffer.
    private func popup(_ view: some View, tui: TUIContext, context: RenderContext) throws
        -> FrameBuffer
    {
        try #require(renderArmed(view, tui: tui, context: context).overlays.first).content
    }

    /// The same menu with nothing highlighted, to read the highlight against.
    /// Laid out in the same space as the frame it will be compared with — a
    /// menu that scrolls in one and not the other has nothing to compare.
    private func unhighlightedPopup(
        _ view: some View, height: Int = 24, overlayContentHeight: Int? = nil
    ) throws -> FrameBuffer {
        let (tui, context) = harness(height: height, overlayContentHeight: overlayContentHeight)
        openPopup(view, as: .pointer, tui: tui, context: context)
        return try popup(view, tui: tui, context: context)
    }

    /// The label of the highlighted row, or `nil` if none is.
    ///
    /// Read from the DRAWN frame — the row that differs from the same menu with
    /// nothing highlighted — rather than from whatever owns the highlight. That
    /// owner is precisely what moved when the pop-up engines merged (from
    /// `FocusManager.focusedID` to the column's own ordinal), and what the user
    /// sees did not move at all. A test that asserted the owner would have had
    /// to be rewritten; this one did not.
    private func highlightedRow(_ drawn: FrameBuffer, versus plain: FrameBuffer) -> String? {
        for (row, unhighlighted) in zip(drawn.lines, plain.lines) where row != unhighlighted {
            var label = row.stripped.filter { !"│╭╮╰╯".contains($0) }
            while label.first == " " { label.removeFirst() }
            while label.last == " " { label.removeLast() }
            return label
        }
        return nil
    }

    @Test("A pointer-opened pop-up highlights nothing; the first Down takes the top item")
    func pointerOpenedPopupStartsUnselected() throws {
        let (tui, context) = harness()
        let plain = try unhighlightedPopup(threeItemMenu)

        openPopup(threeItemMenu, as: .pointer, tui: tui, context: context)
        #expect(
            highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
                == nil,
            "nothing is chosen yet")

        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .down)))
        #expect(
            highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
                == "Rename")
    }

    @Test("The first Up in an unselected pop-up takes the LAST item")
    func pointerOpenedPopupUpTakesTheLastItem() throws {
        let (tui, context) = harness()
        let plain = try unhighlightedPopup(threeItemMenu)

        openPopup(threeItemMenu, as: .pointer, tui: tui, context: context)
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .up)))
        #expect(
            highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
                == "Delete")
    }

    /// The keyboard has no other way to point at a row, so a keyboard open
    /// starts on the first item — the counterpart to the pointer rule above.
    @Test("A keyboard-opened pop-up starts on the first item")
    func keyboardOpenedPopupStartsOnTheFirstItem() throws {
        let (tui, context) = harness()
        let plain = try unhighlightedPopup(threeItemMenu)

        openPopup(threeItemMenu, as: .keyboard, tui: tui, context: context)
        #expect(
            highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
                == "Rename")
    }

    /// A pop-up's rows are NOT page focus stops: the menu grabs the keyboard
    /// while it is up, so putting its rows in the ring only ever meant the ring
    /// had to be taught what a menu already knew. (An INLINE menu's rows still
    /// are — see `MenuColumnRenderTests`.)
    @Test("A pop-up's rows stay out of the focus ring")
    func popupRowsAreNotFocusStops() throws {
        let (tui, context) = harness()
        let focusManager = try #require(context.environment.focusManager)

        openPopup(threeItemMenu, as: .keyboard, tui: tui, context: context)
        #expect(
            focusManager.registeredFocusIDsInActiveSection().isEmpty,
            "the menu's section holds no focusable rows")
        #expect(focusManager.currentFocusedID == nil, "and nothing in it has the focus")
    }

    // MARK: - Jump navigation

    /// The gestures a `Picker` drop-down, a `List` and a `RadioButtonGroup` all
    /// answer, which a menu did not: its rows were Buttons in the focus ring, and
    /// the ring implements plain arrows only. Home/End/Page reached the focus
    /// manager's scroll fall-through, found no scroller in the menu's section,
    /// and died unhandled.
    @Test(
        "An open menu answers the jump keys",
        arguments: [
            (KeyEvent(key: .end), "Four"), (KeyEvent(key: .home), "One"),
            (KeyEvent(key: .pageDown), "Four"), (KeyEvent(key: .pageUp), "One"),
            (KeyEvent(key: .down, shift: true), "Four"), (KeyEvent(key: .up, shift: true), "One"),
        ])
    func jumpKeys(key: KeyEvent, expected: String) throws {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("One") {}
            Button("Two") {}
            Button("Three") {}
            Button("Four") {}
        }
        .selectionIndicatorStyle(.none)
        let plain = try unhighlightedPopup(view)

        openPopup(view, as: .keyboard, tui: tui, context: context)
        // Start in the middle so a jump in either direction is a real move.
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .down)))
        #expect(
            highlightedRow(try popup(view, tui: tui, context: context), versus: plain) == "Two",
            "sanity: the highlight starts in the middle")

        #expect(tui.keyEventDispatcher.dispatch(key), "the menu must consume it")
        #expect(highlightedRow(try popup(view, tui: tui, context: context), versus: plain) == expected)
    }

    /// A menu taller than the screen scrolls, and the highlighted row has to
    /// come with it. It used to for free: the row held the focus, and the reveal
    /// finds whatever holds the focus. A pop-up's rows no longer hold anything,
    /// so the column names its highlighted row as the reveal target instead —
    /// and if it stopped doing so, the arrows would walk the highlight straight
    /// off the bottom of a menu that never moved.
    @Test("A tall menu scrolls to keep the highlighted row on screen")
    func tallMenuFollowsTheHighlight() throws {
        let (tui, context) = harness(height: 12, overlayContentHeight: 10)
        let view = Menu("Actions") {
            ForEach(0..<30, id: \.self) { index in
                Button("Item \(index)") {}
            }
        }
        .selectionIndicatorStyle(.none)

        openPopup(view, as: .keyboard, tui: tui, context: context)
        for _ in 0..<11 { #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .down))) }

        // Asserted as "is it on screen", not "is it highlighted": once the menu
        // scrolls, its indicator rows move too, and which row carries the
        // highlight is what the tests above pin. What only this test can catch
        // is a highlight that walked past the bottom of a menu that never moved.
        let drawn = lines(try popup(view, tui: tui, context: context))
        #expect(
            drawn.contains { $0.contains("Item 11") },
            "the 12th row scrolled into view:\n\(drawn.joined(separator: "\n"))")
        #expect(
            !drawn.contains { $0.contains("Item 0 ") },
            "…and the first row scrolled out:\n\(drawn.joined(separator: "\n"))")
    }

    /// Left/Right act as Up/Down on the focus ring, which in a vertical menu is
    /// simply wrong — the Picker drop-down has always swallowed them.
    @Test("An open menu swallows Left and Right", arguments: [Key.left, .right])
    func horizontalArrowsAreInert(key: Key) throws {
        let (tui, context) = harness()
        let plain = try unhighlightedPopup(threeItemMenu)

        openPopup(threeItemMenu, as: .keyboard, tui: tui, context: context)
        let before = highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: key)))
        #expect(
            highlightedRow(try popup(threeItemMenu, tui: tui, context: context), versus: plain)
                == before)
    }

    /// Escape closes the MENU. Without the status-bar claim the page's own "⎋
    /// back" item won and the whole page was dismissed behind the open menu.
    @Test("An open menu claims the Escape label")
    func escapeLabelClaimed() {
        let (tui, context) = harness()
        // The status bar is shared per-app state, so start from a known point
        // rather than assuming no earlier test in this process claimed it.
        context.environment.statusBar?.escapeLabelOverride = nil
        openPopup(threeItemMenu, as: .keyboard, tui: tui, context: context)
        #expect(context.environment.statusBar?.escapeLabelOverride != nil)
    }

    // MARK: - Style plumbing

    @Test("menuStyle flows down through a container to the menus inside it")
    func styleFlowsThroughAContainer() {
        let (tui, context) = harness()
        let view = VStack {
            Menu("One") { Button("A") {} }
            Menu("Two") { Button("B") {} }
        }
        .menuStyle(.inline)

        let out = lines(renderArmed(view, tui: tui, context: context))
        #expect(out.contains { $0.contains("A") }, "both menus are expanded: \(out)")
        #expect(out.contains { $0.contains("B") })
    }
    // MARK: - onMenuOpen

    /// The hook exists so an app can clear whatever the LAST choice left on
    /// screen, which is the only way choosing the same item twice running reads
    /// as two choices. So the assertion that matters is the ORDER: the reset
    /// runs as the menu opens, not after the item's action.
    @Test("onMenuOpen fires on each opening, before the choice")
    func menuOpenHookFiresOnOpen() throws {
        let (tui, context) = harness()
        let log = EventLog()
        let view = Menu("Actions") {
            Button("Rename") { log.events.append("chose") }
        }
        .onMenuOpen { log.events.append("open") }

        _ = renderArmed(view, tui: tui, context: context)
        #expect(log.events.isEmpty, "rendering a closed menu is not an opening")

        func clickTrigger() {
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        }

        clickTrigger()
        #expect(log.events == ["open"], "opening reports once")
        let opened = renderArmed(view, tui: tui, context: context)
        #expect(log.events == ["open"], "and re-rendering the OPEN menu does not repeat it")

        let overlay = try #require(opened.overlays.first)
        let itemY = try #require(
            lines(overlay.content).firstIndex { $0.contains("Rename") })
        let y = overlay.offsetY + itemY
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: y))
        _ = renderArmed(view, tui: tui, context: context)
        #expect(log.events == ["open", "chose"], "closing is not an opening")

        clickTrigger()
        #expect(
            log.events == ["open", "chose", "open"],
            "and the next opening clears the way for the next choice")
    }

    /// A mutable box the menu's closures can write to — `@State` needs a render
    /// pass to bind, and these closures fire between renders.
    @MainActor private final class EventLog {
        var events: [String] = []
    }
}
