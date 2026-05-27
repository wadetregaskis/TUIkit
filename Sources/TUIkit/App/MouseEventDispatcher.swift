//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEventDispatcher.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Mouse Event Dispatcher

/// Routes terminal mouse events to the view tree using hit-test
/// regions emitted by `.onMouseEvent` modifiers.
///
/// The dispatcher resets its state at the start of every render pass.
/// During render, modifiers register their handlers and the
/// ``RenderLoop`` collects the absolute-coordinate
/// ``HitTestRegion``s from the root buffer. When a mouse event arrives
/// the dispatcher looks up the topmost region containing the cursor's
/// position and forwards the event to its handler.
///
/// Drags are tracked too: the dispatcher remembers which handler
/// received the press for each button, and routes the subsequent
/// `.dragged` and `.released` events to that same handler regardless of
/// where the cursor ended up — exactly the way GUI toolkits treat a
/// drag once it has captured a control.
final class MouseEventDispatcher: @unchecked Sendable {
    /// Per-frame handlers keyed by ``HitTestRegion/HandlerID``.
    ///
    /// `RenderLoop.beginRenderPass()` clears the table at the start of
    /// every frame; modifiers register their handlers again as their
    /// content renders.
    private var handlers: [HitTestRegion.HandlerID: (MouseEvent) -> Bool] = [:]

    /// The id of the handler that most recently consumed a button-down
    /// event for each tracked button. Populated when a `.pressed`
    /// arrives, used to route subsequent `.dragged` / `.released`
    /// events for the same button to the original handler, and cleared
    /// on `.released`.
    private var pressedHandlers: [MouseButton: HitTestRegion.HandlerID] = [:]

    /// The list of hit-test regions in absolute screen coordinates for
    /// the current frame.
    ///
    /// Populated by ``RenderLoop`` from the root buffer's
    /// ``FrameBuffer/hitTestRegions`` after compositing. Cleared on
    /// `beginRenderPass`.
    private var regions: [HitTestRegion] = []

    /// Monotonic source of fresh ids per render pass. We don't need
    /// the ids to be globally unique — clearing on `beginRenderPass`
    /// guarantees no carry-over between frames.
    private var nextHandlerID: UInt64 = 0

    init() {}
}

// MARK: - Internal API

extension MouseEventDispatcher {
    /// Resets the dispatcher's per-frame state.
    ///
    /// Called by ``RenderLoop`` at the start of every render pass. The
    /// drag-capture map (`pressedHandlers`) is intentionally *not*
    /// cleared here — captures span multiple frames, ended only by the
    /// matching `.released`.
    func beginRenderPass() {
        handlers.removeAll(keepingCapacity: true)
        regions.removeAll(keepingCapacity: true)
        nextHandlerID = 0
    }

    /// Records the hit-test regions extracted from the root buffer
    /// after compositing.
    ///
    /// The regions arrive in registration order (outer-most first).
    /// The dispatcher reverses that during dispatch so the innermost
    /// matching handler wins — same intuition as a tap dispatched in a
    /// SwiftUI / AppKit view tree.
    func setRegions(_ regions: [HitTestRegion]) {
        self.regions = regions
    }

    /// Registers a new handler and returns the id `.onMouseEvent`
    /// should emit alongside its region.
    func register(_ handler: @escaping (MouseEvent) -> Bool) -> HitTestRegion.HandlerID {
        let id = HitTestRegion.HandlerID(nextHandlerID)
        nextHandlerID += 1
        handlers[id] = handler
        return id
    }

    /// Dispatches one mouse event to the appropriate handler.
    ///
    /// - Returns: `true` if a handler consumed the event.
    @discardableResult
    func dispatch(_ event: MouseEvent) -> Bool {
        // Drag capture: when a button is currently held, route every
        // subsequent event for that button to the handler that took
        // the press, regardless of where the cursor sits now.
        if event.phase == .dragged || event.phase == .released {
            if let capturedID = pressedHandlers[event.button],
                let handler = handlers[capturedID]
            {
                _ = handler(event)
                if event.phase == .released {
                    pressedHandlers[event.button] = nil
                }
                return true
            }
        }

        // Otherwise, find the innermost region containing the cursor.
        guard let handlerID = topRegion(at: event.x, y: event.y) else {
            return false
        }
        guard let handler = handlers[handlerID] else { return false }
        let consumed = handler(event)
        if consumed, event.phase == .pressed {
            pressedHandlers[event.button] = handlerID
        }
        return consumed
    }

    /// Returns the handler id of the topmost region containing the
    /// given point, or `nil` if no region matches.
    private func topRegion(at x: Int, y: Int) -> HitTestRegion.HandlerID? {
        // Last-registered region wins; modifier chains evaluate outside-in,
        // so the inner-most modifier registers last.
        for region in regions.reversed() where region.contains(x: x, y: y) {
            return region.handlerID
        }
        return nil
    }
}
