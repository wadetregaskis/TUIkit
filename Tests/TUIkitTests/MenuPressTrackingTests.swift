//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuPressTrackingTests.swift
//
//  Press-and-hold menu tracking, the gesture every Mac menu answers: the menu
//  opens on the PRESS, dragging with the button down moves the highlight to the
//  row under the pointer, and releasing over a row chooses it. A plain click
//  still works — the menu simply stays up until the next one.
//
//  All three pop-up surfaces are driven here rather than in each control's own
//  suite, because it is ONE behaviour: the press hands the rest of its gesture
//  back to live hit-testing (`MouseEventDispatcher.handOffGesture`) so the drag
//  and release find the menu instead of the control that opened it. Testing it
//  once per control is how the three drift apart.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Menu press-and-hold tracking")
struct MenuPressTrackingTests {

    // MARK: - Harness

    private func harness(width: Int = 40, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        // Drag reports are a mouse-support CATEGORY: without this the dispatcher
        // drops every `.dragged` event before any handler sees it, and the whole
        // gesture under test is invisible.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// Renders a full frame and arms the dispatcher with the COMPOSITED regions,
    /// as the run loop does — an open menu's rows live inside its overlay until
    /// the overlays are flattened.
    @discardableResult
    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext)
        -> FrameBuffer
    {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    /// A left press, with the input source stamped the way `App.run`'s event
    /// funnel stamps it — one level above these dispatchers, and load-bearing:
    /// a POINTER-opened menu highlights nothing, which is the state the drag
    /// then has to change.
    private func press(_ tui: TUIContext, _ context: RenderContext, x: Int, y: Int) {
        context.environment.focusManager?.noteInputSource(.pointer)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: x, y: y))
    }

    /// The same, with the SECONDARY button — what opens a `.contextMenu`, and
    /// what then carries its whole gesture.
    private func rightPress(_ tui: TUIContext, _ context: RenderContext, x: Int, y: Int) {
        context.environment.focusManager?.noteInputSource(.pointer)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .pressed, x: x, y: y))
    }

    private func drag(_ tui: TUIContext, x: Int, y: Int, button: MouseButton = .left) {
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: button, phase: .dragged, x: x, y: y))
    }

    private func release(_ tui: TUIContext, x: Int, y: Int, button: MouseButton = .left) {
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: button, phase: .released, x: x, y: y))
    }

    private func release(_ tui: TUIContext, _ context: RenderContext, x: Int, y: Int) {
        context.environment.focusManager?.noteInputSource(.pointer)
        release(tui, x: x, y: y)
    }

    /// A point on the open menu's row whose text contains `label`, in absolute
    /// screen coordinates — the menu may be indented (a `Picker`'s drop-down
    /// hangs under its control, past the label), so the column matters as much
    /// as the row.
    private func row(_ frame: FrameBuffer, _ label: String) throws -> (x: Int, y: Int) {
        let overlay = try #require(frame.overlays.first, "the menu is open")
        let line = try #require(
            overlay.content.lines.firstIndex { $0.stripped.contains(label) },
            "\(label) is in the menu: \(overlay.content.lines.map(\.stripped))")
        // Past the menu's left border and its one-cell inset.
        return (overlay.offsetX + 2, overlay.offsetY + line)
    }

    /// The label of the highlighted row, read out of the DRAWN frame by
    /// comparing it with the same menu highlighting nothing — engine-agnostic,
    /// exactly as `MenuTests` does it.
    private func highlightedRow(_ drawn: FrameBuffer, versus plain: FrameBuffer) throws -> String? {
        let drawnPopup = try #require(drawn.overlays.first).content
        let plainPopup = try #require(plain.overlays.first).content
        for (row, unhighlighted) in zip(drawnPopup.lines, plainPopup.lines) where row != unhighlighted
        {
            var label = row.stripped.filter { !"│╭╮╰╯".contains($0) }
            while label.first == " " { label.removeFirst() }
            while label.last == " " { label.removeLast() }
            return label
        }
        return nil
    }

    // MARK: - Pull-down `Menu`

    /// `.selectionIndicatorStyle(.none)` because the highlight otherwise
    /// breathes on a wall clock, and two frames taken at different moments
    /// would then differ in every styled cell.
    private func actionsMenu(_ chosen: @escaping (String) -> Void = { _ in }) -> some View {
        Menu("Actions") {
            Button("Rename") { chosen("Rename") }
            Button("Duplicate") { chosen("Duplicate") }
            Button("Delete") { chosen("Delete") }
        }
        .selectionIndicatorStyle(.none)
    }

    @Test("Pressing a pop-up menu's label opens it — before the button comes back up")
    func menuOpensOnThePress() {
        let (tui, context) = harness()
        let view = actionsMenu()

        renderArmed(view, tui: tui, context: context)
        press(tui, context, x: 2, y: 0)
        let opened = renderArmed(view, tui: tui, context: context)

        #expect(
            !opened.overlays.isEmpty,
            """
            the menu is up with the button still down — that is what makes \
            click-and-hold possible at all: \(opened.lines.map(\.stripped))
            """)
    }

    @Test("Dragging with the button held moves the highlight to the row under the pointer")
    func dragMovesTheHighlight() throws {
        let (tui, context) = harness()
        let view = actionsMenu()

        renderArmed(view, tui: tui, context: context)
        press(tui, context, x: 2, y: 0)
        // The baseline every comparison below is read against: a POINTER-opened
        // menu highlights nothing (`MenuTests` pins that rule), so any row that
        // differs from this frame is a row the drag lit up.
        let justOpened = renderArmed(view, tui: tui, context: context)

        let target = try row(justOpened, "Delete")
        drag(tui, x: target.x, y: target.y)
        let dragged = renderArmed(view, tui: tui, context: context)
        #expect(try highlightedRow(dragged, versus: justOpened) == "Delete")

        let backTarget = try row(dragged, "Rename")
        drag(tui, x: backTarget.x, y: backTarget.y)
        let back = renderArmed(view, tui: tui, context: context)
        #expect(
            try highlightedRow(back, versus: justOpened) == "Rename",
            "the highlight follows the pointer, it does not just latch once")
    }

    @Test("Releasing over a row chooses it and closes the menu")
    func releaseOverARowChooses() throws {
        let (tui, context) = harness()
        var chosen = "—"
        let view = actionsMenu { chosen = $0 }

        renderArmed(view, tui: tui, context: context)
        press(tui, context, x: 2, y: 0)
        let opened = renderArmed(view, tui: tui, context: context)
        let target = try row(opened, "Duplicate")
        drag(tui, x: target.x, y: target.y)
        renderArmed(view, tui: tui, context: context)
        release(tui, x: target.x, y: target.y)

        #expect(chosen == "Duplicate", "one press-drag-release picked an item")
        #expect(
            renderArmed(view, tui: tui, context: context).overlays.isEmpty,
            "and the menu closed behind the choice")
    }

    /// The other half of the Mac model: a quick click leaves the menu up, so it
    /// can also be used click-then-click. Releasing on the trigger must not
    /// choose anything and must not close it either.
    @Test("A click that goes down and up on the label leaves the menu open")
    func clickWithoutDraggingLeavesItOpen() {
        let (tui, context) = harness()
        var chosen = "—"
        let view = actionsMenu { chosen = $0 }

        renderArmed(view, tui: tui, context: context)
        press(tui, context, x: 2, y: 0)
        renderArmed(view, tui: tui, context: context)
        release(tui, context, x: 2, y: 0)
        let after = renderArmed(view, tui: tui, context: context)

        #expect(!after.overlays.isEmpty, "still open, waiting to be picked from")
        #expect(chosen == "—", "and nothing was chosen by letting go of the label")
    }

    // MARK: - `Picker` drop-down

    @Test("A picker's drop-down opens on the press and its release picks an option")
    func pickerPressDragRelease() throws {
        let (tui, context) = harness()
        var choice = 0
        let view = Picker(
            "Theme",
            selection: Binding(get: { choice }, set: { choice = $0 })
        ) {
            Text("Light").tag(0)
            Text("Dark").tag(1)
            Text("Midnight").tag(2)
        }
        .pickerStyle(.menu)
        .selectionIndicatorStyle(.none)

        // The collapsed control sits after the picker's label on the same line;
        // `▐` is its leading cap.
        let closed = renderArmed(view, tui: tui, context: context)
        let controlX = try #require(
            closed.lines[0].stripped.firstIndex(of: "▐").map {
                closed.lines[0].stripped.distance(from: closed.lines[0].stripped.startIndex, to: $0)
            })
        press(tui, context, x: controlX + 1, y: 0)
        let opened = renderArmed(view, tui: tui, context: context)
        #expect(!opened.overlays.isEmpty, "the drop-down is up while the button is still down")

        let target = try row(opened, "Midnight")
        drag(tui, x: target.x, y: target.y)
        renderArmed(view, tui: tui, context: context)
        release(tui, x: target.x, y: target.y)

        #expect(choice == 2, "the release chose the option it landed on")
        #expect(
            renderArmed(view, tui: tui, context: context).overlays.isEmpty,
            "and the drop-down closed")
    }

    // MARK: - `.contextMenu`

    /// The right button opens a context menu and then carries the same gesture:
    /// press, drag down the rows, release on one. Same model as a pull-down —
    /// the only difference is which button is holding it.
    @Test("A context menu opens on the right press and its release runs the item")
    func contextMenuPressDragRelease() throws {
        let (tui, context) = harness()
        var chosen = "—"
        let view = Text("Right-click me")
            .contextMenu {
                Button("Cut") { chosen = "Cut" }
                Button("Copy") { chosen = "Copy" }
                Button("Paste") { chosen = "Paste" }
            }
            .selectionIndicatorStyle(.none)

        renderArmed(view, tui: tui, context: context)
        rightPress(tui, context, x: 3, y: 0)
        let opened = renderArmed(view, tui: tui, context: context)
        #expect(!opened.overlays.isEmpty, "the menu is up with the button still down")

        let target = try row(opened, "Paste")
        drag(tui, x: target.x, y: target.y, button: .right)
        let dragged = renderArmed(view, tui: tui, context: context)
        #expect(
            try highlightedRow(dragged, versus: opened) == "Paste",
            "the right-drag tracks like any other")

        release(tui, x: target.x, y: target.y, button: .right)
        #expect(chosen == "Paste", "and the right-release runs the item it landed on")
        #expect(
            renderArmed(view, tui: tui, context: context).overlays.isEmpty,
            "the menu closed behind the choice")
    }

    /// The sticky half, for the right button too: a click that does not move
    /// leaves the menu up to be picked from. The release lands on the menu's own
    /// top border — a context menu is anchored AT the clicked cell — which must
    /// neither choose anything nor dismiss it.
    @Test("A right-click that does not move leaves the context menu open")
    func contextMenuClickWithoutDraggingLeavesItOpen() {
        let (tui, context) = harness()
        var chosen = "—"
        let view = Text("Right-click me")
            .contextMenu {
                Button("Cut") { chosen = "Cut" }
                Button("Copy") { chosen = "Copy" }
            }

        renderArmed(view, tui: tui, context: context)
        rightPress(tui, context, x: 3, y: 0)
        let held = renderArmed(view, tui: tui, context: context)
        #expect(!held.overlays.isEmpty, "open on the press, before the button comes up")

        release(tui, x: 3, y: 0, button: .right)
        let after = renderArmed(view, tui: tui, context: context)

        #expect(!after.overlays.isEmpty, "still open, waiting to be picked from")
        #expect(chosen == "—", "and nothing ran")
    }

    // MARK: - Combo box

    @Test("A combo box's ▾ opens on the press and its release picks a suggestion")
    func comboBoxPressDragRelease() throws {
        let (tui, context) = harness()
        var text = ""
        let view = TextField("Fruit", text: Binding(get: { text }, set: { text = $0 }))
            .textInputSuggestions {
                Text("Apricot")
                Text("Blackberry")
                Text("Cranberry")
            }
            .frame(width: 24)
            .selectionIndicatorStyle(.none)

        let closed = renderArmed(view, tui: tui, context: context)
        // The ▾ sits in the two cells before the field's trailing cap.
        let caretX = closed.width - 2
        press(tui, context, x: caretX, y: 0)
        let opened = renderArmed(view, tui: tui, context: context)
        #expect(!opened.overlays.isEmpty, "the suggestions are up with the button still down")

        let target = try row(opened, "Blackberry")
        drag(tui, x: target.x, y: target.y)
        renderArmed(view, tui: tui, context: context)
        release(tui, x: target.x, y: target.y)

        #expect(text == "Blackberry", "the release committed the suggestion it landed on")
    }
}
