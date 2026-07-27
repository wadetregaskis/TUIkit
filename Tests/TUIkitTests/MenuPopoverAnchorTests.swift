//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuPopoverAnchorTests.swift
//
//  Where a pop-up `Menu` goes when there is no room below it.
//
//  Both cases here are the ones a menu at the bottom of a scrolling page hits,
//  and both are decided by ONE number — the `anchorHeight` its overlay carries.
//  A `Picker`'s drop-down passes 1 and has passed 1 since the day its
//  disappearing-at-the-viewport-edge bug was fixed; a `Menu` passed 0, which is
//  the same bug over again plus a second one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Menu popover anchoring")
struct MenuPopoverAnchorTests {

    private func harness(width: Int = 40, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

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

    /// A page whose `Menu` trigger is the LAST row a short ScrollView can show.
    private func pageWithMenuAtTheBottom(viewportHeight: Int) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<(viewportHeight - 1), id: \.self) { index in
                    Text("Filler \(index)")
                }
                Menu("Actions") {
                    Button("Rename") {}
                    Button("Delete") {}
                }
            }
        }
        .frame(height: viewportHeight)
    }

    /// A drop-down attached to a control on the last visible row starts exactly
    /// at the viewport's bottom edge, so a cull that measures only the popup's
    /// own span throws it away before the root compositor — whose job the
    /// placement is — ever sees it. That is what `anchorHeight` is for, and a
    /// `Menu` passing 0 opted out of it: `topY = offsetY - 0` is the row BELOW
    /// the trigger, which is already past the edge.
    ///
    /// The `Picker` drop-down's version of this was fixed long ago; the Example
    /// app's own Menus page is inside a ScrollView, so this one is reachable.
    @Test("A menu on the last visible row of a ScrollView still appears")
    func menuAtTheViewportEdgeSurvivesTheCull() throws {
        let (tui, context) = harness(height: 24)
        let view = pageWithMenuAtTheBottom(viewportHeight: 8)

        _ = renderArmed(view, tui: tui, context: context)
        // Click the trigger, which the render above put on the viewport's last
        // row (rows 0...6 are filler, row 7 is the Menu).
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 7))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 7))
        let opened = renderArmed(view, tui: tui, context: context)

        #expect(
            !opened.overlays.isEmpty,
            """
            the open menu survived the ScrollView's overlay cull:
            \(opened.lines.map(\.stripped).joined(separator: "\n"))
            """)
        let popup = try #require(opened.overlays.first).content
        #expect(
            popup.lines.contains { $0.stripped.contains("Rename") },
            "…and it is the menu, with its rows in it")
    }

    /// With no room below, the compositor flips a popover to sit ABOVE its
    /// anchor — placing the popup's bottom flush with the anchor's TOP, which
    /// it can only find if it is told how tall the anchor is. Told nothing, it
    /// puts the bottom flush with `offsetY` instead, which is the row below the
    /// trigger: the menu lands ON the control that opened it.
    ///
    /// (`OverlayLayer.anchorHeight`'s own documentation claimed a 0 "disables
    /// flipping". `placed(…)` has never had such a gate — it computes
    /// `offsetY - anchorHeight - height` and takes it whenever that is >= 0.)
    @Test("A pop-up menu declares the trigger above it")
    func popUpDeclaresItsAnchor() throws {
        let (tui, context) = harness()
        let view = Menu("Actions") {
            Button("Rename") {}
            Button("Delete") {}
        }

        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        let opened = renderArmed(view, tui: tui, context: context)

        let overlay = try #require(opened.overlays.first)
        #expect(
            overlay.anchorHeight == overlay.offsetY,
            "the trigger occupies every row between the top and the menu")

        // …and that is enough for the flip to clear it.
        let flipped = OverlayLayer(
            offsetX: 0, offsetY: 21, content: FrameBuffer(lines: ["x", "x", "x", "x"]),
            level: .popover, anchorHeight: overlay.anchorHeight
        ).placed(maxWidth: 40, maxHeight: 24)
        #expect(flipped.y + 4 <= 20, "the flipped menu ends at or above the trigger's row")
    }

    /// A `.contextMenu` is the other case, and its 0 is right: it is anchored
    /// AT the cell that was clicked, with no control above it to clear. Pinned
    /// so the pop-up menu's fix does not get copied onto it by symmetry.
    @Test("A context menu anchors at the click cell, with nothing above it")
    func contextMenuHasNoAnchor() throws {
        let (tui, context) = harness()
        let view = Text("Right-click me").contextMenu {
            Button("Cut") {}
            Button("Copy") {}
        }

        _ = renderArmed(view, tui: tui, context: context)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        let opened = renderArmed(view, tui: tui, context: context)

        #expect(try #require(opened.overlays.first).anchorHeight == 0)
    }
}
