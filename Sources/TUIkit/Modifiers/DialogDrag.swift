//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogDrag.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Dialog Drag

/// Makes a presented dialog draggable by its title bar and border.
///
/// Shared by the modal/sheet and alert presentation hosts. A dialog is centred
/// by the compositor; this adds a persisted `(x, y)` offset that the user can
/// change by dragging the dialog's title row or border. ``OverlayLayer/placed(maxWidth:maxHeight:)``
/// applies that offset as a post-centre delta and clamps it so the whole dialog
/// stays on screen.
///
/// The grab region is only the title row and the border frame — the interior is
/// left free so the dialog's own controls still receive their clicks.
@MainActor
enum DialogDrag {
    /// Wires the dialog `buffer`'s title/border cells as a drag handle and
    /// returns the current offset to feed into the centred ``OverlayLayer``.
    /// Returns `(0, 0)` while measuring or when no dispatcher/state is available.
    static func offset(
        for buffer: inout FrameBuffer,
        context: RenderContext,
        propertyIndex: Int
    ) -> (x: Int, y: Int) {
        guard !context.isMeasuring, let stateStorage = context.environment.stateStorage else {
            return (0, 0)
        }
        let box: StateBox<_DialogDragHandler> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex),
            default: _DialogDragHandler())
        let handler = box.value

        if let mouseDispatcher = context.environment.mouseEventDispatcher {
            // Clicks claim the press; drag reporting moves the dialog.
            mouseDispatcher.requestFeature(.clicks)
            mouseDispatcher.requestFeature(.drag)
            let handlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .pressed where event.button == .left:
                    handler.beginDrag(atX: event.x, y: event.y)
                    return true
                case .dragged:
                    handler.updateDrag(toX: event.x, y: event.y)
                    return true
                case .released where event.button == .left:
                    handler.endDrag()
                    return true
                default:
                    return false
                }
            }
            appendGrabRegions(to: &buffer, handlerID: handlerID)
        }

        return (handler.offsetX, handler.offsetY)
    }

    /// Resets a dialog's drag offset. Called on the dismissed render path so a
    /// re-presented dialog opens centred rather than where it was last dragged.
    static func reset(context: RenderContext, propertyIndex: Int) {
        guard !context.isMeasuring, let stateStorage = context.environment.stateStorage else { return }
        let box: StateBox<_DialogDragHandler> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex),
            default: _DialogDragHandler())
        box.value.reset()
    }

    /// Appends the grab handle: the title row plus the left/right/bottom border
    /// cells, all pointing at `handlerID`. These never overlap the interior
    /// controls, and — being registered after them — win the hit-test only on
    /// the border cells, so interior clicks still reach the controls.
    private static func appendGrabRegions(to buffer: inout FrameBuffer, handlerID: HitTestRegion.HandlerID) {
        let width = buffer.width
        let height = buffer.height
        guard width > 0, height > 0 else { return }
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: width, height: 1, handlerID: handlerID))  // title row
        guard height > 1 else { return }
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: height - 1, width: width, height: 1, handlerID: handlerID))  // bottom
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: 1, height: height, handlerID: handlerID))  // left
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: width - 1, offsetY: 0, width: 1, height: height, handlerID: handlerID))  // right
    }
}

/// Persisted drag state for a presented dialog: the current offset from centre,
/// plus the press anchor while a drag is in progress. Mirrors the shape of
/// ``_SplitDividerHandler``.
///
/// During a drag the dispatcher delivers coordinates localized to the press
/// region's origin, so the delta to apply is the difference between the current
/// localized coordinate and the one recorded at press time.
final class _DialogDragHandler {
    private(set) var offsetX = 0
    private(set) var offsetY = 0

    private var pressLocalX = 0
    private var pressLocalY = 0
    private var pressOffsetX = 0
    private var pressOffsetY = 0

    /// Records the press point (region-local) and the offset at that moment.
    func beginDrag(atX x: Int, y: Int) {
        pressLocalX = x
        pressLocalY = y
        pressOffsetX = offsetX
        pressOffsetY = offsetY
    }

    /// Applies the drag: the new offset is the press-time offset plus how far the
    /// cursor has moved since the press.
    func updateDrag(toX x: Int, y: Int) {
        offsetX = pressOffsetX + (x - pressLocalX)
        offsetY = pressOffsetY + (y - pressLocalY)
    }

    func endDrag() {}

    /// Recentres the dialog.
    func reset() {
        offsetX = 0
        offsetY = 0
    }
}
