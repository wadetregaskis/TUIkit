//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuColumnRenderTests.swift
//
//  The fixed target for the menu-engine merge.
//
//  TUIkit has two pop-up implementations — the `Picker`/combo-box drop-down,
//  which owns an integer highlight, and `Menu`/`.contextMenu`, whose rows are
//  real focusable Buttons. Putting them on one implementation moves who owns the
//  highlight, which is exactly the kind of change that can redraw a menu without
//  anyone noticing. So: pin what a mixed menu DRAWS, and what it puts into the
//  focus ring, the shortcut registry and the hit-test regions, before any of it
//  moves. Every later commit in the merge is read against this file.
//
//  One menu exercises every feature the view-composed side has that the
//  procedural side does not: a @ViewBuilder label, a destructive role, a key
//  equivalent, a divider, a disabled row, and a CJK label (whose width is
//  counted in cells, not characters).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Menu column rendering")
struct MenuColumnRenderTests {

    // MARK: - The fixture

    /// The one menu. Deliberately mixed; deliberately shared by both styles, so
    /// the inline and pop-up goldens differ only in assembly.
    @ViewBuilder
    private var mixedItems: some View {
        Button("Rename") {}.keyboardShortcut("r", modifiers: [])
        Button {
        } label: {
            HStack(spacing: 1) {
                Text("★")
                Text("Favourite")
            }
        }
        Button("文件を開く") {}
        Divider()
        Button("Locked") {}.disabled(true)
        Button("Delete", role: .destructive) {}
    }

    private func harness(width: Int = 44, height: Int = 20) -> (TUIContext, RenderContext) {
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

    /// One full frame, with the mouse dispatcher armed from the composited
    /// result — what the run loop does before it hands a frame to the pointer.
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

    // MARK: - What it draws

    @Test("Inline menu: rendered frame")
    func inlineGolden() {
        let (tui, context) = harness()
        let view = Menu("Actions") { mixedItems }.menuStyle(.inline)
        _ = renderArmed(view, tui: tui, context: context)
        assertSnapshot("menu-column-inline", width: 44, height: 20, of: view)
    }

    @Test("Pop-up menu: rendered frame")
    func popUpGolden() throws {
        let (tui, context) = harness()
        let view = Menu("Actions") { mixedItems }

        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        let opened = renderArmed(view, tui: tui, context: context)

        let popup = try #require(opened.overlays.first).content
        assertSnapshot("menu-column-popup", of: popup)
    }

    // MARK: - Invariants the goldens cannot express

    /// Every row is the same width, so the highlight bar reads as a bar rather
    /// than as a tag around each label — and CJK is counted in CELLS.
    @Test("Rows share one width, in cells", arguments: [true, false])
    func uniformRowWidth(inline: Bool) throws {
        let (tui, context) = harness()
        let base = Menu("Actions") { mixedItems }
        let buffer: FrameBuffer
        if inline {
            buffer = renderArmed(base.menuStyle(.inline), tui: tui, context: context)
        } else {
            _ = renderArmed(base, tui: tui, context: context)
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: 0))
            buffer = try #require(renderArmed(base, tui: tui, context: context).overlays.first)
                .content
        }
        let widths = Set(buffer.lines.map(\.strippedLength))
        #expect(widths.count == 1, "uniform width, got \(widths)")
        #expect(
            buffer.lines.contains { $0.stripped.contains("文件を開く") },
            "the CJK row is present and did not overflow its row")
    }

    /// The key equivalent is drawn, right-aligned in its own column — a thing
    /// the procedural renderer has no concept of, so the merge must not lose it.
    @Test("A row's key equivalent is drawn in a trailing column")
    func keyEquivalentColumn() {
        let (tui, context) = harness()
        let view = Menu("Actions") { mixedItems }.menuStyle(.inline)
        let lines = renderArmed(view, tui: tui, context: context).lines.map(\.stripped)
        let renameRow = lines.first { $0.contains("Rename") }
        #expect(renameRow != nil, "got \(lines)")
        #expect(
            renameRow?.hasSuffix("r  ") == false && renameRow?.contains("r") == true,
            "the hint sits at the trailing edge, inside the border: \(renameRow ?? "—")")
    }

    /// An inline menu's rows are the page's focus stops — this is what makes Tab
    /// reach them, `.defaultFocus` resolve, and the reveal machinery find them.
    /// The merge must NOT take this away from the inline style.
    @Test("Inline rows are in the page's focus ring; the disabled one is not focusable")
    func inlineRowsAreFocusStops() throws {
        let (tui, context) = harness()
        let focusManager = try #require(context.environment.focusManager)
        let view = Menu("Actions") { mixedItems }.menuStyle(.inline)
        _ = renderArmed(view, tui: tui, context: context)

        let registered = focusManager.registeredFocusIDsInActiveSection()
        let focusable = focusManager.focusableIDsInActiveSection()
        #expect(registered.count == 5, "five Buttons register (the Divider is not one)")
        #expect(focusable.count == 4, "the .disabled row registers but declines focus")
    }

    /// A key equivalent on a menu row is a real accelerator: it fires with the
    /// menu closed, from anywhere on the page. Losing that would be silent.
    @Test("An inline row's key equivalent reaches the shortcut registry")
    func inlineShortcutIsRegistered() {
        let (tui, context) = harness()
        let view = Menu("Actions") { mixedItems }.menuStyle(.inline)
        _ = renderArmed(view, tui: tui, context: context)
        #expect(
            tui.keyboardShortcuts.trigger(for: KeyEvent(key: .character("r"))),
            "the 'r' accelerator fires from anywhere on the page, not just inside the menu")
    }
}
