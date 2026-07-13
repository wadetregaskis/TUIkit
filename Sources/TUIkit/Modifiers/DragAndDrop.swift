//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAndDrop.swift
//
//  `.draggable(_:)` / `.dropDestination(for:action:isTargeted:)` — modelled
//  on SwiftUI's current (Transferable-era) drag-and-drop API, with the
//  deliberate terminal deviations documented on each entry point: payloads
//  are unconstrained in-process values (CoreTransferable is Apple-only and a
//  terminal cannot reach the system pasteboard anyway), and the drop action
//  receives a ``DropInfo`` (cell coordinates + the modifiers held at
//  release) instead of a `CGPoint`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Draggable

/// The view wrapper created by ``View/draggable(_:)``.
///
/// Renders its content and claims left presses over it: a press followed by
/// any cursor movement begins a drag session (the payload is evaluated
/// then), the drag preview follows the cursor as a floating overlay, and
/// release either drops on a targeted ``View/dropDestination(for:action:isTargeted:)``
/// or cancels. A press released without movement is treated as a click and
/// falls through to nothing — like a dialog title bar, a draggable view's
/// surface is a drag handle, so interactive children are better placed
/// outside it.
public struct DraggableModifier<Content: View, Payload>: View {
    let content: Content
    let payload: () -> Payload
    let preview: AnyView?

    public var body: Never {
        fatalError("DraggableModifier renders via Renderable")
    }
}

extension DraggableModifier: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)

        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return buffer }

        // The floating preview: the explicit preview view when given, else
        // the content's own rendered buffer (regions/overlays stripped — the
        // preview is purely visual).
        var previewBuffer: FrameBuffer
        if let preview {
            previewBuffer = TUIkit.renderToBuffer(preview, context: context)
        } else {
            previewBuffer = buffer
        }
        previewBuffer.hitTestRegions = []
        previewBuffer.overlays = []

        let payload = self.payload
        let capturedPreview = previewBuffer
        let dragging = DragFlag()
        let id = dispatcher.register { event in
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                dragging.isDragging = false
                return true
            case .dragged:
                if !dragging.isDragging {
                    dragging.isDragging = true
                    session.begin(payload: payload(), preview: capturedPreview)
                } else {
                    session.dragMoved()
                }
                return true
            case .released:
                if dragging.isDragging {
                    session.performDrop()
                    dragging.isDragging = false
                }
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: id
            )
        )
        return buffer
    }
}

/// Per-handler scratch: whether the current press has turned into a drag.
private final class DragFlag {
    var isDragging = false
}

// MARK: - Drop Destination

/// The view wrapper created by ``View/dropDestination(for:action:isTargeted:)``.
///
/// Renders its content and registers its on-screen rectangle as a drop
/// target for payloads of `Payload`. The region's own mouse handler is
/// inert (clicks fall through to the content) — the rectangle exists so the
/// active drag session can hit-test it.
public struct DropDestinationModifier<Content: View, Payload>: View {
    let content: Content
    let action: ([Payload], DropInfo) -> Bool
    let isTargeted: (Bool) -> Void

    public var body: Never {
        fatalError("DropDestinationModifier renders via Renderable")
    }
}

extension DropDestinationModifier: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)

        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return buffer }

        // An inert region: it never consumes events itself (so clicks reach
        // the content), but its composited rectangle is the drop zone.
        // INSERTED AT THE FRONT, not appended: the dispatcher routes clicks
        // to the innermost (last-registered) matching region and stops even
        // when the handler declines, so an appended zone would eat every
        // press over its content — a `.draggable` chip INSIDE a drop zone
        // could never start its drag. Fronting the region keeps interactive
        // children clickable (the same fallback-region pattern List and
        // Picker containers use), while drop TARGETING is unaffected — it
        // matches hit ids against the registered targets and skips
        // non-targets, so the zone is still found at any depth.
        let id = dispatcher.register { _ in false }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: id
            ),
            at: 0
        )

        let action = self.action
        let isTargeted = self.isTargeted
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: id,
                accepts: { $0 is Payload },
                perform: { payload, event in
                    guard let typed = payload as? Payload else { return false }
                    // The drop location in the destination's local space:
                    // the event is absolute, the region offset is known here.
                    let (dx, dy) = dispatcher.regionOffset(for: id) ?? (0, 0)
                    return action(
                        [typed],
                        DropInfo(
                            x: event.x - dx, y: event.y - dy,
                            shift: event.shift, ctrl: event.ctrl, meta: event.meta))
                },
                setTargeted: isTargeted
            )
        )
        return buffer
    }
}

// MARK: - View Extensions

extension View {
    /// Makes this view draggable within the app, carrying `payload`.
    ///
    /// Press and move to begin the drag: the view's rendered appearance
    /// follows the cursor as a floating preview, and releasing over a
    /// matching ``View/dropDestination(for:action:isTargeted:)`` delivers
    /// the payload (evaluated lazily, at drag start).
    ///
    /// Deviations from SwiftUI, forced by the terminal: the payload needs no
    /// `Transferable` conformance (CoreTransferable is Apple-only, and there
    /// is no system pasteboard to marshal through — drags stay inside the
    /// app), and the whole view surface acts as the drag handle, so a press
    /// on it is claimed rather than passed to interactive children.
    ///
    /// - Parameter payload: The value delivered on drop, evaluated when the
    ///   drag begins.
    /// - Returns: A draggable view.
    public func draggable<Payload>(
        _ payload: @autoclosure @escaping () -> Payload
    ) -> some View {
        DraggableModifier(content: self, payload: payload, preview: nil)
    }

    /// Makes this view draggable, with a custom drag preview shown at the
    /// cursor instead of the view's own rendered appearance.
    ///
    /// - Parameters:
    ///   - payload: The value delivered on drop, evaluated at drag start.
    ///   - preview: The floating preview view.
    /// - Returns: A draggable view.
    public func draggable<Payload, Preview: View>(
        _ payload: @autoclosure @escaping () -> Payload,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        DraggableModifier(content: self, payload: payload, preview: AnyView(preview()))
    }

    /// Marks this view as a destination for drags carrying `Payload` values.
    ///
    /// While a matching drag hovers over the view, `isTargeted` receives
    /// `true` (and `false` when it leaves or ends) — use it to highlight the
    /// zone. On release, `action` receives the dropped values and a
    /// ``DropInfo`` (the drop cell in the view's local space plus the
    /// modifiers held at release — a deliberate deviation from SwiftUI's
    /// `CGPoint`, since a terminal deals in cells and CAN observe modifiers
    /// throughout a drag); return whether the drop was accepted.
    ///
    /// - Parameters:
    ///   - payloadType: The payload type this destination accepts.
    ///   - action: Performs the drop; returns `true` if the values were taken.
    ///   - isTargeted: Observes whether a compatible drag is over the view.
    /// - Returns: A view that can receive drops.
    public func dropDestination<Payload>(
        for payloadType: Payload.Type = Payload.self,
        action: @escaping ([Payload], DropInfo) -> Bool,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        DropDestinationModifier<Self, Payload>(
            content: self, action: action, isTargeted: isTargeted)
    }
}
