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
/// A single mouse feature that view modifiers can ask for on a
/// per-frame basis (see ``MouseEventDispatcher/requestFeature(_:)``).
public enum MouseFeature: Sendable {
    case clicks
    case scrolling
    case drag
    case motion
}

final class MouseEventDispatcher: @unchecked Sendable {
    /// Per-frame handlers keyed by ``HitTestRegion/HandlerID``.
    ///
    /// `RenderLoop.beginRenderPass()` clears the table at the start of
    /// every frame; modifiers register their handlers again as their
    /// content renders.
    private var handlers: [HitTestRegion.HandlerID: (MouseEvent) -> Bool] = [:]

    /// Tracks the in-progress press for each button: the handler that
    /// claimed the press, plus the offset of the region it claimed it
    /// from. The offset lets us keep delivering coordinates relative
    /// to the original region even when the cursor wanders elsewhere
    /// during the drag.
    private struct PressCapture {
        let handlerID: HitTestRegion.HandlerID
        let regionOffsetX: Int
        let regionOffsetY: Int
    }

    /// The handler that most recently consumed a button-down event for
    /// each tracked button. Populated when a `.pressed` arrives, used
    /// to route subsequent `.dragged` / `.released` events for the
    /// same button to the original handler, and cleared on
    /// `.released`.
    private var pressedHandlers: [MouseButton: PressCapture] = [:]

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

    /// Per-frame feature requests posted by view modifiers that
    /// genuinely need a higher mouse-tracking level than the base
    /// configuration provides (e.g. an ``.onHover`` modifier asks
    /// for motion). Cleared every `beginRenderPass`; the AppRunner
    /// merges this with the base ``MouseSupport`` configuration to
    /// decide which terminal tracking mode to apply.
    private var requestedFeatures: MouseSupport = .disabled

    /// An optional view-level override of the entire ``MouseSupport``
    /// configuration. Set via the ``View/mouseSupport(_:)`` modifier
    /// during a render pass; replaces (rather than unions) the
    /// scene-level base config for that frame. Cleared every
    /// `beginRenderPass`. The latest setter wins — innermost
    /// `.mouseSupport(...)` in the view tree takes effect.
    private var configOverride: MouseSupport?

    /// The effective ``MouseSupport`` configuration in force for the
    /// dispatching of incoming events. Set by the AppRunner each
    /// frame before processing input. Determines which kinds of
    /// events the dispatcher will forward to handlers — for example
    /// if `clicks` is false, click events arriving from the
    /// terminal are silently dropped.
    private var activeSupport: MouseSupport = .standard

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
        requestedFeatures = .disabled
        configOverride = nil
    }

    /// Records that the rendering view tree wants `feature` reported
    /// for the current frame, on top of whatever the base scene-level
    /// ``MouseSupport`` configuration provides.
    ///
    /// Typical caller: an `.onHover` modifier asks for motion so it
    /// can highlight while the cursor is over its content. The
    /// modifier calls this every frame the view is rendered; the
    /// AppRunner takes the union with the base config when deciding
    /// which terminal tracking mode to apply.
    func requestFeature(_ feature: MouseFeature) {
        switch feature {
        case .clicks: requestedFeatures.clicks = true
        case .scrolling: requestedFeatures.scrolling = true
        case .drag: requestedFeatures.drag = true
        case .motion: requestedFeatures.motion = true
        }
    }

    /// Returns the effective ``MouseSupport`` for the current frame.
    ///
    /// Resolution order:
    /// 1. If a view-level override was posted this frame (via
    ///    ``setConfigOverride(_:)``), it replaces the scene base.
    /// 2. Otherwise, the scene base is used.
    /// 3. Either way, per-frame feature requests are unioned on top,
    ///    so a modifier that needs `motion` always gets it
    ///    regardless of which level set the base.
    func effectiveSupport(baseConfig: MouseSupport) -> MouseSupport {
        let base = configOverride ?? baseConfig
        return base.union(with: requestedFeatures)
    }

    /// Replaces the per-frame ``MouseSupport`` configuration with
    /// `support`. Called by the ``View/mouseSupport(_:)`` view
    /// modifier during render. Last setter wins; cleared at the
    /// start of every render pass.
    func setConfigOverride(_ support: MouseSupport) {
        configOverride = support
    }

    /// Updates the effective configuration used to filter incoming
    /// events. The AppRunner calls this each frame after computing
    /// the union of base config and per-frame feature requests.
    func setActiveSupport(_ support: MouseSupport) {
        activeSupport = support
    }

    /// Returns whether an event of the given phase should be
    /// forwarded to handlers, given the currently active
    /// ``MouseSupport`` configuration.
    private func eventIsAllowed(_ event: MouseEvent) -> Bool {
        switch event.phase {
        case .scrolled: return activeSupport.scrolling
        case .pressed, .released: return activeSupport.clicks
        case .dragged: return activeSupport.drag
        case .moved: return activeSupport.motion
        }
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
    /// Coordinates in the event passed to the handler are **localised
    /// to the hit region** — `(0, 0)` is the region's top-left corner,
    /// matching SwiftUI's tap-gesture convention. For drag-captured
    /// handlers the same translation is applied (using the original
    /// region's offset) so a drag that leaves the source view simply
    /// produces negative or out-of-bounds local coordinates rather
    /// than re-binding to a different region.
    ///
    /// - Returns: `true` if a handler consumed the event.
    @discardableResult
    func dispatch(_ event: MouseEvent) -> Bool {
        // Diagnostic (TUIKIT_DEBUG_FOCUS=1): log every press/release
        // with the click coords (in content-area space), the
        // registered regions, and which — if any — matched. Used to
        // diagnose "I clicked the field but no focus event fired"
        // bugs: tells us whether the click ever reached the
        // dispatcher, whether its category is allowed, and whether
        // any region's geometry covers it. The outer guard is the
        // hot-path branch — when debug is off this is a single
        // global-Bool load and one comparison.
        if isFocusDebugEnabled, event.phase == .pressed || event.phase == .released {
            let regionLines = regions.enumerated().map { index, region in
                let matches = region.contains(x: event.x, y: event.y)
                return "    [\(index)] handler=\(region.handlerID.raw) "
                    + "x=\(region.offsetX)..<\(region.offsetX + region.width) "
                    + "y=\(region.offsetY)..<\(region.offsetY + region.height)"
                    + (matches ? " ← MATCHES" : "")
            }
            debugFocusLog("""
                dispatch \(event.phase) \(event.button)
                  click at (x=\(event.x), y=\(event.y))
                  activeSupport: \(activeSupport)
                  eventIsAllowed: \(eventIsAllowed(event))
                  regions (\(regions.count)):
                \(regionLines.joined(separator: "\n"))
                """)
        }

        // Honour the active MouseSupport configuration: drop events
        // whose category isn't enabled. The terminal may still send
        // them (e.g. wheel events arrive even in click-only mode),
        // but the user asked us not to surface them.
        guard eventIsAllowed(event) else { return false }

        // Drag capture: when a button is currently held, route every
        // subsequent event for that button to the handler that took
        // the press, regardless of where the cursor sits now.
        if event.phase == .dragged || event.phase == .released {
            if let capture = pressedHandlers[event.button],
                let handler = handlers[capture.handlerID]
            {
                let localized = localize(event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY)
                _ = handler(localized)
                if event.phase == .released {
                    pressedHandlers[event.button] = nil
                }
                return true
            }
        }

        // Find the matching regions outside-in (innermost first
        // = last-registered first; the dispatcher's contract is
        // that views register in render order, so the inner-
        // most modifier's region is appended last). For click /
        // drag events we hand the event to the innermost match
        // and stop; for wheel events we
        // let the dispatch fall through to the next region when
        // a handler returns false. That's what makes a List or
        // ScrollView scroll even when the cursor lands on top of
        // a Button or TextField inside it — those children don't
        // handle wheel events, so the wheel bubbles past them to
        // the surrounding scroller.
        let matching = matchingRegions(at: event.x, y: event.y)
        guard !matching.isEmpty else { return false }

        for region in matching {
            guard let handler = handlers[region.handlerID] else { continue }
            let localized = localize(
                event, byOffsetX: region.offsetX, offsetY: region.offsetY)
            let consumed = handler(localized)
            if consumed {
                if event.phase == .pressed {
                    pressedHandlers[event.button] = PressCapture(
                        handlerID: region.handlerID,
                        regionOffsetX: region.offsetX,
                        regionOffsetY: region.offsetY
                    )
                }
                return true
            }
            // Fall through only for wheel events. Click / drag
            // / motion stop at the first matching region (and
            // return its handler's `consumed` result, which is
            // already `false` here).
            if !event.button.isWheel {
                return false
            }
        }
        return false
    }

    /// Returns every region containing the given point, ordered
    /// innermost-first (last-registered first). Used by
    /// ``dispatch`` to implement wheel-event fall-through.
    private func matchingRegions(at x: Int, y: Int) -> [HitTestRegion] {
        regions.reversed().filter { $0.contains(x: x, y: y) }
    }

    /// Translates the event's coordinates from absolute screen-space
    /// into the local coordinate space of a hit region.
    private func localize(_ event: MouseEvent, byOffsetX dx: Int, offsetY dy: Int) -> MouseEvent {
        MouseEvent(
            button: event.button,
            phase: event.phase,
            x: event.x - dx,
            y: event.y - dy,
            shift: event.shift,
            ctrl: event.ctrl,
            meta: event.meta
        )
    }
}
