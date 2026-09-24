//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragGestureModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Drag Gesture Modifier

/// A modifier that delivers a continuous stream of drag-gesture
/// updates while the user holds the left mouse button and drags
/// across the wrapped view.
///
/// The modifier maintains per-handler state (the gesture's starting
/// position) in a reference box so it survives across the per-frame
/// closure rebinding. The dispatcher's drag-capture machinery
/// guarantees that once the `.pressed` is claimed, the matching
/// `.dragged` and `.released` events come back to the same closure —
/// so the handler keeps tracking the cursor even if it leaves the
/// view's bounds mid-drag.
public struct DragGestureModifier<Content: View>: View {
    let content: Content
    let action: (DragGestureEvent) -> Void

    public var body: Never {
        fatalError("DragGestureModifier renders via Renderable")
    }
}

extension DragGestureModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)

        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        // A drag needs the terminal to report presses and drag motion, and
        // the app's `mouseSupport(_:)` is not this modifier's to assume: the
        // default base has both, but an app that narrowed it to clicks and
        // scrolling would have left every `.onDragGesture` in the tree — its
        // own and the framework's — receiving a press and then nothing at all.
        // Per-frame, unioned onto the base, exactly as `.onHover` asks for
        // motion and `DialogDrag` asks for these two.
        dispatcher.requestFeature(.clicks, in: context)
        dispatcher.requestFeature(.drag, in: context)

        // Reference cell so the start position is shared across the
        // press → drag → release call sequence the same handler will
        // receive.
        let start = DragStart()
        let action = self.action

        let id = dispatcher.register(in: context) { event in
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                start.x = event.x
                start.y = event.y
                action(DragGestureEvent(
                    phase: .began, x: event.x, y: event.y,
                    startX: event.x, startY: event.y))
                return true
            case .dragged:
                action(DragGestureEvent(
                    phase: .moved, x: event.x, y: event.y,
                    startX: start.x, startY: start.y))
                return true
            case .released:
                action(DragGestureEvent(
                    phase: .ended, x: event.x, y: event.y,
                    startX: start.x, startY: start.y))
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

extension DragGestureModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Reference-typed scratch box used to remember a drag's starting
/// position across the press/drag/release callbacks for the same
/// handler closure.
private final class DragStart {
    var x: Int = 0
    var y: Int = 0
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension DragGestureModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension DragGestureModifier: DrawsContentUnchanged {}
