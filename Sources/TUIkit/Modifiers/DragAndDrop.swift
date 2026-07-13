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

// MARK: - Drag Preview Anchor

/// How the floating preview of a drag anchors to the cursor.
public enum DragPreviewAnchor: Sendable, Equatable {
    /// The cell that was pressed stays under the cursor — the preview sits
    /// exactly where it would conceptually land, like macOS. The default.
    case grabPoint

    /// The preview's top-left corner rides at a fixed offset from the
    /// cursor. `.offset(x: 1, y: 1)` trails below-right, keeping the
    /// pointed-at cell itself uncovered — clearer, but the image no longer
    /// shows the true drop position.
    case offset(x: Int, y: Int)
}

private struct DragPreviewAnchorKey: EnvironmentKey {
    static let defaultValue: DragPreviewAnchor = .grabPoint
}

extension EnvironmentValues {
    /// How drag previews started in this scope anchor to the cursor.
    var dragPreviewAnchor: DragPreviewAnchor {
        get { self[DragPreviewAnchorKey.self] }
        set { self[DragPreviewAnchorKey.self] = newValue }
    }
}

extension View {
    /// Sets how the floating preview of drags started in this view's
    /// subtree anchors to the cursor (default: ``DragPreviewAnchor/grabPoint``).
    public func dragPreviewAnchor(_ anchor: DragPreviewAnchor) -> some View {
        environment(\.dragPreviewAnchor, anchor)
    }
}

// MARK: - Draggable

/// The view wrapper created by ``View/draggable(_:)``.
///
/// Renders its content and claims left presses over it: a press followed by
/// any cursor movement begins a drag session (the payload is evaluated
/// then), the drag preview follows the cursor as a floating overlay, and
/// release either drops on a targeted ``View/dropDestination(for:action:isTargeted:)``
/// or cancels. A press released without movement is a CLICK, forwarded to
/// the interactive child under the cursor — so a `Button` (or any control)
/// wrapped in `.draggable` still clicks, matching SwiftUI. Hover
/// transitions forward the same way, so the child keeps its hover
/// affordance. Only genuine drags (press + movement) are consumed here.
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
        let anchor = context.environment.dragPreviewAnchor
        _DragHandle.install(
            on: &buffer,
            dispatcher: dispatcher,
            onDragBegin: { _, grab in
                session.begin(
                    payload: payload(), preview: capturedPreview,
                    grabX: grab.x, grabY: grab.y, anchor: anchor)
            },
            onDragMove: { _ in session.dragMoved() },
            onDragEnd: { _ in
                let dropped = session.performDrop()
                debugFocusLog("draggable drop performed=\(dropped)")
            })
        return buffer
    }
}

// MARK: - Drag Handle Core

/// The shared plumbing of a drag-handle surface: claims left presses over a
/// rendered buffer, reports genuine drags (press + movement) through
/// callbacks, and keeps the buffer's interactive children working — a press
/// released without movement forwards to the child under the cursor as an
/// ordinary click, and hover transitions ride through likewise.
///
/// Used by ``DraggableModifier`` (drag-and-drop payloads) and the gradient
/// editor's stop chips (live reordering while the drag moves).
enum _DragHandle {
    /// Registers the handle's handler and appends its whole-buffer region
    /// (innermost, so it claims presses ahead of the children it forwards
    /// to). Callback events are localized to the buffer's origin; a drag's
    /// events stay localized to the ORIGINAL press region even when content
    /// re-renders mid-drag (the dispatcher's press capture).
    static func install(
        on buffer: inout FrameBuffer,
        dispatcher: MouseEventDispatcher,
        onDragBegin: @escaping (MouseEvent, _ grab: (x: Int, y: Int)) -> Void,
        onDragMove: @escaping (MouseEvent) -> Void,
        onDragEnd: @escaping (MouseEvent) -> Void
    ) {
        // The content's interactive regions, captured WITH their handler
        // closures. Clicks and hover forward to them below — and that must
        // go through closures, never ids: handler ids reset every render
        // pass while a press or hover routinely spans one (a consumed press
        // requests a re-render), so an id resolved at delivery time would
        // hit the wrong handler. Same reasoning as the dispatcher's own
        // press capture.
        let children: [(region: HitTestRegion, handler: (MouseEvent) -> Bool)] =
            buffer.hitTestRegions.compactMap { region in
                dispatcher.handler(for: region.handlerID).map { (region, $0) }
            }
        // Innermost child at a point (in the buffer's space, which is also
        // the space of the events this handler receives — its region sits at
        // the buffer's origin). Last-registered = innermost, as dispatched.
        func innermostChild(atX x: Int, y: Int) -> (region: HitTestRegion, handler: (MouseEvent) -> Bool)? {
            children.last { $0.region.contains(x: x, y: y) }
        }
        func forward(
            _ event: MouseEvent, phase: MousePhase,
            to child: (region: HitTestRegion, handler: (MouseEvent) -> Bool)
        ) {
            let localized = MouseEvent(
                button: event.button, phase: phase,
                x: event.x - child.region.offsetX, y: event.y - child.region.offsetY,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                clickCount: event.clickCount)
            _ = child.handler(localized)
        }

        let scratch = DragScratch()
        let id = dispatcher.register { event in
            // Hover transitions land here (the handle's region is the
            // innermost); ride them through to the child under the cursor
            // so it keeps its hover affordance.
            switch event.phase {
            case .entered:
                scratch.hoveredChild = innermostChild(atX: event.x, y: event.y)
                if let child = scratch.hoveredChild { forward(event, phase: .entered, to: child) }
                return true
            case .exited:
                if let child = scratch.hoveredChild { forward(event, phase: .exited, to: child) }
                scratch.hoveredChild = nil
                return true
            default:
                break
            }
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                scratch.isDragging = false
                // The grab point: where the press landed within this
                // surface. `.grabPoint`-anchored previews keep this cell
                // under the cursor for the whole drag.
                scratch.grab = (event.x, event.y)
                return true
            case .dragged:
                if !scratch.isDragging {
                    scratch.isDragging = true
                    onDragBegin(event, scratch.grab)
                } else {
                    onDragMove(event)
                }
                return true
            case .released:
                debugFocusLog(
                    "drag handle release: isDragging=\(scratch.isDragging) at (\(event.x), \(event.y))")
                if scratch.isDragging {
                    onDragEnd(event)
                    scratch.isDragging = false
                } else if let child = innermostChild(atX: event.x, y: event.y) {
                    // A press released without movement is a CLICK. The
                    // press itself was claimed (as a potential drag), so
                    // deliver the whole click — synthetic press, then the
                    // release — to the interactive child under the cursor:
                    // a Button inside a drag handle still clicks.
                    forward(event, phase: .pressed, to: child)
                    forward(event, phase: .released, to: child)
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
    }
}

/// Per-handler scratch: whether the current press has turned into a drag,
/// where it grabbed the surface, and which content child is hovered (to
/// close its hover out on exit).
private final class DragScratch {
    var isDragging = false
    var grab: (x: Int, y: Int) = (0, 0)
    var hoveredChild: (region: HitTestRegion, handler: (MouseEvent) -> Bool)?
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
                    // The drag is still active while its drop performs, so
                    // the preview frame is reportable — localized the same
                    // way (effects anchor to the image, not the cursor).
                    let frame = session.previewFrame() ?? (x: event.x, y: event.y, width: 0, height: 0)
                    return action(
                        [typed],
                        DropInfo(
                            x: event.x - dx, y: event.y - dy,
                            shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                            previewX: frame.x - dx, previewY: frame.y - dy,
                            previewWidth: frame.width, previewHeight: frame.height))
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
    /// The whole view surface acts as the drag handle, but interactive
    /// children keep working: a press released without movement is delivered
    /// to the child under the cursor as an ordinary click (and hover rides
    /// through likewise), so `Button { … }.draggable(value)` both clicks and
    /// drags — matching SwiftUI. Only genuine drags are consumed.
    ///
    /// Deviation from SwiftUI, forced by the terminal: the payload needs no
    /// `Transferable` conformance (CoreTransferable is Apple-only, and there
    /// is no system pasteboard to marshal through — drags stay inside the
    /// app).
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
