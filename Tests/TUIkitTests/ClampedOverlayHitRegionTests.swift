//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ClampedOverlayHitRegionTests.swift
//
//  A too-tall overlay (modal, drop-down) is clamped to the content area at
//  placement time — but `clamped(toWidth:height:)` deliberately carries ALL
//  hit-test regions (in-flow clamping must never discard them; the root
//  compositor re-places them). At the OVERLAY seam that clip is final: a
//  region belonging to clipped-away rows must not stay clickable, or a click
//  below the dialog's visible bottom (e.g. on the status bar of a short
//  terminal, whose events arrive with y >= contentHeight) activates an item
//  the user cannot see.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Clamped overlays drop clipped-away hit regions")
struct ClampedOverlayHitRegionTests {

    /// The seam directly: a 20-row layer with a row-15 hit region, composited
    /// into an 8-row content area. The full-width content centres at x = 0, so
    /// region coordinates survive unshifted.
    @Test("A region below the overlay clip is inert after compositing")
    func clippedRegionIsInert() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var hits: [(Int, Int)] = []
        let id = dispatcher.register { event in
            hits.append((event.x, event.y))
            return true
        }

        // Full-width rows so the centred placement lands at x = 0.
        var content = FrameBuffer(lines: (0..<20).map { _ in String(repeating: "x", count: 40) })
        content.hitTestRegions = [
            // Visible: top row of the dialog.
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 1, handlerID: id),
            // Clipped away entirely: row 15 of a dialog clamped to 8 rows.
            HitTestRegion(offsetX: 0, offsetY: 15, width: 10, height: 1, handlerID: id),
            // Straddling the clip: rows 6-11 — only rows 6 and 7 survive.
            HitTestRegion(offsetX: 0, offsetY: 6, width: 10, height: 6, handlerID: id),
        ]
        var base = FrameBuffer(lines: ["base"])
        base.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 0, content: content, level: .modal, centered: true)
        ]

        let composited = base.compositingOverlays(
            maxWidth: 40, maxHeight: 8, palette: EnvironmentValues().palette)
        #expect(composited.height <= 8, "the overlay is clamped to the content area")

        // The crisp invariant: no published region reaches below the clip.
        for region in composited.hitTestRegions {
            #expect(
                region.offsetY + region.height <= 8,
                "region rows \(region.offsetY)..<\(region.offsetY + region.height) exceed the 8-row clip")
        }

        dispatcher.setRegions(composited.hitTestRegions)

        // A click below the visible bottom must NOT route to the dialog.
        let phantom = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 15))
        #expect(!phantom, "no phantom click on a clipped-away row: \(hits)")
        #expect(hits.isEmpty, "the handler never saw the phantom click: \(hits)")

        // The straddling region's clipped tail is inert too…
        let belowStraddle = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 1, y: 9))
        #expect(!belowStraddle, "the straddling region is trimmed at the clip: \(hits)")

        // …while its visible rows and the top region still work.
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 7)))
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 7)))
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0)))
        #expect(hits.count == 3, "visible regions still route: \(hits)")
    }

    /// App-shaped: a modal taller than the content area, containing a
    /// selectable List. Clicking inside the List's (former) region below the
    /// composited dialog's visible bottom must not change the selection.
    @Test("Clicking below a clamped modal's visible bottom selects nothing")
    func clickBelowClampedModalIsInert() {
        final class Box { var sel: String? }
        let box = Box()
        let items = (1...30).map { "item-\($0)" }
        let view = Text("base")
            .modal(isPresented: .constant(true)) {
                List(selection: Binding(get: { box.sel }, set: { box.sel = $0 })) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                    }
                }
                .frame(height: 30)
            }

        let contentH = 10
        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.terminalWidth = 60
        env.terminalHeight = contentH + 4
        env.overlayContentHeight = contentH
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 60, availableHeight: contentH,
            environment: env, tuiContext: tui
        ).isolatingRenderCache()

        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: 60, maxHeight: contentH, palette: env.palette)
        #expect(composited.height <= contentH)
        dispatcher.setRegions(composited.hitTestRegions)

        // Every published region stays within the content area…
        for region in composited.hitTestRegions {
            #expect(
                region.offsetY + region.height <= contentH,
                "region rows \(region.offsetY)..<\(region.offsetY + region.height) exceed the content area")
        }

        // …and a click below the visible bottom, horizontally inside the
        // dialog (derived from its real regions), selects nothing. This is
        // exactly where a short terminal's status-bar clicks arrive
        // (y >= contentHeight).
        let clickX = (composited.hitTestRegions.first?.offsetX ?? 0) + 1
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: clickX, y: contentH + 1))
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: clickX, y: contentH + 1))
        #expect(box.sel == nil, "no invisible row was selected, got \(box.sel ?? "nil")")
    }
}
