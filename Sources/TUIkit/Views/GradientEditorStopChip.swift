//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientEditorStopChip.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Live Drag Handle

/// Wires a stop chip as a LIVE reorder handle: dragging the chip moves its
/// stop through the strip immediately, following the cursor — no drop
/// target, no floating preview; the reflowing strip (and the live gradient
/// preview above it) IS the feedback. A plain click still selects, forwarded
/// to the button by ``_DragHandle``.
///
/// The cursor→slot mapping is pure geometry
/// (``GradientEditorPanel/dragSlot(forX:y:count:)``): the drag's events stay
/// localized to THIS chip's original region for the whole drag (the
/// dispatcher's press capture), so adding the chip's strip origin — fixed at
/// render time — yields strip-relative coordinates however much the strip
/// reorders underneath.
struct _StopChipDragHandle<Content: View>: View {
    let content: Content

    /// The chip's stop index at render time — the drag's coordinate anchor.
    let index: Int

    /// How many stops the strip holds (fixed for the duration of a drag).
    let stopCount: Int

    /// Grabbing a chip (first movement) selects its stop.
    let grab: () -> Void

    /// Moves the stop currently at `from` to `to` (and follows it with the
    /// selection).
    let moveStop: (_ from: Int, _ to: Int) -> Void

    var body: Never {
        fatalError("_StopChipDragHandle renders via Renderable")
    }
}

extension _StopChipDragHandle: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else { return buffer }

        let anchor = GradientEditorPanel.chipStripOrigin(of: index, count: stopCount)
        let dragged = _DraggedStopBox()
        let grab = self.grab
        let moveStop = self.moveStop
        let index = self.index
        let stopCount = self.stopCount
        // Localized event → strip-relative point → nearest slot; move the
        // dragged stop there the moment it differs from where it is now.
        func follow(_ event: MouseEvent) {
            guard let current = dragged.current else { return }
            let slot = GradientEditorPanel.dragSlot(
                forX: anchor.x + event.x, y: anchor.y + event.y, count: stopCount)
            if slot != current {
                moveStop(current, slot)
                dragged.current = slot
            }
        }
        _DragHandle.install(
            on: &buffer,
            context: context,
            dispatcher: dispatcher,
            onDragBegin: { event, _ in
                dragged.current = index
                grab()
                follow(event)
            },
            onDragMove: follow,
            onDragEnd: { _ in dragged.current = nil })
        return buffer
    }
}

/// Where the dragged stop currently sits, tracked across the drag's events
/// (which all arrive at the closure captured at press time).
private final class _DraggedStopBox {
    var current: Int?
}
