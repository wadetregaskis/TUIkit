//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    private func harness(width: Int = 40, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
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
}
