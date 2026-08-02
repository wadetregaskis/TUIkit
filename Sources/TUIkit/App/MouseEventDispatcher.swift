//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEventDispatcher.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch
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
    /// The app's drag-and-drop session, when one is wired (see
    /// ``TUIContext``). The dispatcher stamps it with every press / drag /
    /// release event in ABSOLUTE coordinates before routing — a drag-captured
    /// handler only ever sees region-relative coordinates, but drop targeting
    /// needs the on-screen cursor position.
    weak var dragAndDropSession: DragAndDropSession?

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
        /// The handler that claimed the press — captured directly, NOT by id.
        /// `pressedHandlers` spans frames (a press and its release can straddle
        /// one or more renders), but handler ids do not: `beginRenderPass`
        /// clears the table and re-registers everything from a counter reset to
        /// 0, so the same id maps to a *different* handler after any re-render.
        /// A render between press and release is routine — a consumed press
        /// requests one — so looking the handler up by the captured id on
        /// release would route the release to the wrong handler (the classic
        /// symptom: the first menu click always activated item 0). Holding the
        /// closure keeps the release/drag bound to the exact handler that took
        /// the press, which is the whole point of drag capture.
        let handler: (MouseEvent) -> Bool
        let regionOffsetX: Int
        let regionOffsetY: Int
    }

    /// The handler that most recently consumed a button-down event for
    /// each tracked button. Populated when a `.pressed` arrives, used
    /// to route subsequent `.dragged` / `.released` events for the
    /// same button to the original handler, and cleared on
    /// `.released`.
    private var pressedHandlers: [MouseButton: PressCapture] = [:]

    /// Set by the handler currently taking a `.pressed` event to say it wants
    /// no drag capture — see ``handOffGesture()``. Read (and cleared) around
    /// each handler call, so it can only ever speak for that one press.
    private var gestureHandedOff = false

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

    /// The handler ID of the region the cursor was sitting on
    /// when the previous `.moved` event was processed, or `nil`
    /// if the cursor wasn't over any registered region. Used to
    /// synthesise `.entered` / `.exited` transitions when the
    /// cursor crosses region boundaries. Preserved across
    /// render passes — handler IDs are stable across renders
    /// for view trees whose shape doesn't change, which covers
    /// the common case.
    private var lastHoveredHandlerID: HitTestRegion.HandlerID?

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

    /// A recorded button press, used to synthesise ``MouseEvent/clickCount``
    /// for the matching release and to carry the press's modifier state onto
    /// it (some terminals drop the SGR modifier bits on the release report).
    private struct LastClick {
        var button: MouseButton
        var x: Int
        var y: Int
        var timeNanos: UInt64
        var count: Int
        var shift: Bool
        var ctrl: Bool
        var meta: Bool
        /// Whether the press is still awaiting its matching release. Only an
        /// in-flight press donates its count/modifiers to a release — a stray
        /// release arriving long after (terminal quirk, or a press filtered by
        /// a mid-click config change) must not inherit stale state and read as
        /// a phantom modifier-click.
        var inFlight = true
    }

    /// The most recent button press. A press within ``multiClickWindowNanos``
    /// of the previous one, on the same button and (near) the same cell,
    /// increments the count.
    private var lastClick: LastClick?

    /// The cell the button currently down was pressed on, or `nil` when no
    /// press is in flight. Only the ORIGIN is kept: what a held gesture needs
    /// to know is whether it has moved at all, not how far.
    private var pressOrigin: (x: Int, y: Int)?

    /// Whether the cursor has left the cell it was pressed on, for the gesture
    /// currently in flight. See ``endsHeldGesture(_:)``.
    private var pointerMovedSincePress = false

    /// Whether the press in flight opened a pop-up menu — see
    /// ``pressOpenedPopup()``. Unlike ``gestureHandedOff`` this stands for the
    /// whole gesture, not for one handler call, because the question it answers
    /// is asked by a *different* handler on the release.
    private var pressOpenedPopupMenu = false

    /// Buttons whose press was handed back to live hit-testing rather than
    /// captured — see ``handOffGesture()``.
    ///
    /// These are the only presses whose release legitimately arrives with no
    /// capture to route it, and the release has somewhere real to go: the menu
    /// the press opened. Everything else that reaches a release with no capture
    /// is a release whose press went somewhere this control never heard about.
    private var handedOffPresses: Set<MouseButton> = []

    /// The maximum gap between successive clicks for them to count as one
    /// multi-click sequence (400 ms — a common desktop double-click threshold).
    private static let multiClickWindowNanos: UInt64 = 400_000_000

    /// Monotonic time source (nanoseconds), injectable for tests. Defaults to
    /// the same clock the run loop uses.
    var nowNanos: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }

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
        case .entered, .exited:
            // Synthetic phases — generated internally by the
            // dispatcher, never coming from the terminal. They
            // ride alongside the underlying `.moved` event's
            // permission.
            return activeSupport.motion
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

    /// The handler registered under `id` this frame, if any.
    ///
    /// Lets a wrapping modifier forward events to its content's handlers —
    /// ``DraggableModifier`` resolves its content's regions to closures at
    /// render time (ids die at the next render pass; closures don't — the
    /// same reasoning as ``PressCapture``) so a click or hover on the
    /// draggable surface can reach the interactive children beneath it.
    func handler(for id: HitTestRegion.HandlerID) -> ((MouseEvent) -> Bool)? {
        handlers[id]
    }

    /// Called by a handler *while it is consuming a press* to give the rest of
    /// the gesture away: the `.dragged` / `.released` events that follow are
    /// hit-tested live, against whatever is on screen by then, instead of being
    /// routed back here by drag capture.
    ///
    /// This is how a pop-up button tracks like a Mac menu. The press opens the
    /// menu, and from that moment the gesture belongs to the MENU — dragging
    /// highlights the row under the pointer and releasing over one chooses it.
    /// Capture is exactly wrong for that: it would send every later event back
    /// to the button, which is no longer the control the user is pointing at.
    ///
    /// The ordinary press keeps its capture, and should: it is what lets you
    /// press a button, slide off it, and release to cancel.
    func handOffGesture() {
        gestureHandedOff = true
    }

    /// Called by a handler *while it is consuming a press* to say that press
    /// OPENED a pop-up menu, so the release ending the same click is already
    /// spoken for. See ``endsPopupOpeningClick(_:)``.
    func pressOpenedPopup() {
        pressOpenedPopupMenu = true
    }

    /// Whether `event` is a button-release that ends a press-and-**hold** rather
    /// than one that merely completes a click.
    ///
    /// The distinction an open menu lives on. A menu opened by a press owns the
    /// rest of that gesture — drag down the rows, release on one to run it — so
    /// letting the button up is the user's answer, and away from every row the
    /// answer is "never mind": the menu goes. But a menu opened by a plain CLICK
    /// is sticky, staying up to be picked from at leisure, and the release that
    /// ends *that* click also lands away from every row (on the trigger, or on
    /// the menu's own top border, which is where a context menu anchors itself).
    /// Closing on that one would make a quick click open and shut the menu in a
    /// single gesture.
    ///
    /// Nothing in the event stream separates the two except whether the pointer
    /// moved, which only the dispatcher sees whole: a terminal reports a held
    /// move as a `.dragged` at the new cell, and the handler that would ask has
    /// no memory across the frames a gesture spans. So the bookkeeping lives
    /// here, beside the drag capture and the click count.
    ///
    /// A hold that never moves therefore reads as a click. That is the right way
    /// round: there is no clock in the event stream either, and treating a
    /// motionless gesture as a click leaves the menu up, which is recoverable —
    /// treating it as a hold would shut the menu under a user who was still
    /// deciding.
    func endsHeldGesture(_ event: MouseEvent) -> Bool {
        event.phase == .released && !event.button.isWheel && pointerMovedSincePress
    }

    /// Whether `event` is the release that merely ends the CLICK which opened a
    /// pop-up menu — the other half of ``endsHeldGesture(_:)``.
    ///
    /// A menu may be placed over the control that opened it: a drop-down taller
    /// than the space below it covers its own pop-up button, exactly as it does
    /// on a Mac, so the release ending the opening click lands on a menu ROW.
    /// That release must not choose it. The press was spent on opening the menu;
    /// only a release that went somewhere first (``endsHeldGesture(_:)``) is the
    /// user answering the menu they were just shown.
    ///
    /// - Precondition: the opening handler said so, via ``pressOpenedPopup()``.
    ///   Without that this cannot be distinguished from an ordinary click on a
    ///   row of a menu that was already open, which of course *does* choose it.
    func endsPopupOpeningClick(_ event: MouseEvent) -> Bool {
        event.phase == .released && !event.button.isWheel
            && pressOpenedPopupMenu && !pointerMovedSincePress
    }

    /// Updates the press-and-hold bookkeeping ``endsHeldGesture(_:)`` reads.
    ///
    /// Called for every event the dispatcher accepts, before any routing, so the
    /// record covers the whole gesture however it is routed — captured, handed
    /// off, or consumed by nobody at all.
    private func trackHeldGesture(_ event: MouseEvent) {
        switch event.phase {
        case .pressed:
            pressOrigin = (event.x, event.y)
            pointerMovedSincePress = false
            // Cleared before the press is routed, so the handler about to
            // consume it can set it (see ``pressOpenedPopup()``).
            pressOpenedPopupMenu = false
            // A new press supersedes any record of the last one, whose release
            // evidently never arrived (a lost release, a mouse-mode change
            // mid-gesture). Otherwise that record would let one later unpaired
            // release through.
            handedOffPresses.remove(event.button)
        case .dragged:
            guard let origin = pressOrigin else { return }
            if origin.x != event.x || origin.y != event.y { pointerMovedSincePress = true }
        default:
            break
        }
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

        // Synthesise the click count before any routing so every handler —
        // including a drag-captured one — sees the double-click.
        let event = stampClickCount(event)

        // Likewise the press-and-hold record: it has to be up to date before
        // any handler runs, and stay readable *through* the release that ends
        // the gesture, so it is cleared only once that release is fully routed.
        trackHeldGesture(event)
        defer {
            if event.phase == .released {
                pressOrigin = nil
                pointerMovedSincePress = false
                pressOpenedPopupMenu = false
            }
        }

        // Give the drag-and-drop session the absolute cursor before any
        // localisation (drop targeting hit-tests screen coordinates).
        if event.phase == .pressed || event.phase == .dragged || event.phase == .released {
            dragAndDropSession?.lastAbsoluteEvent = event
        }

        // Bare cursor motion drives the hover state machine —
        // not the normal click routing. See dispatchMotion for
        // the rationale on why we route `.moved` separately.
        if event.phase == .moved {
            return dispatchMotion(event)
        }

        // Drag capture: when a button is currently held, route every
        // subsequent event for that button to the handler that took
        // the press, regardless of where the cursor sits now.
        if event.phase == .dragged || event.phase == .released,
            let settled = routeAgainstItsPress(event)
        {
            return settled
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
            gestureHandedOff = false
            let consumed = handler(localized)
            if consumed {
                // A press captures the rest of the gesture — unless the handler
                // handed it off (``handOffGesture()``), which a menu-opening
                // press does so the drag and release find the open menu. That
                // hand-off is recorded, because it is what entitles the release
                // to be hit-tested live with nothing captured.
                if event.phase == .pressed {
                    if gestureHandedOff {
                        handedOffPresses.insert(event.button)
                    } else {
                        pressedHandlers[event.button] = PressCapture(
                            handler: handler,
                            regionOffsetX: region.offsetX,
                            regionOffsetY: region.offsetY
                        )
                    }
                }
                return true
            }
            // Fall through for wheel events AND for the secondary (right)
            // button: a control that doesn't handle a right-click lets it
            // BUBBLE to an ancestor, exactly like the wheel bubbles past a
            // Button/TextField to the surrounding scroller. This is what lets a
            // `.contextMenu` on a container open when you right-click a child
            // that has no context action of its own. A left click / drag /
            // motion still stops at the first matching region.
            if !event.button.isWheel, event.button != .right {
                return false
            }
        }
        return false
    }

    /// Settles a drag or release against the press that began the gesture.
    ///
    /// - Returns: the dispatch result when the press itself decides the
    ///   event's fate — routed to a live capture, to the legacy-release
    ///   fallback, or dropped for having no press behind it at all — and `nil`
    ///   when the event should go on to ordinary live hit-testing.
    private func routeAgainstItsPress(_ event: MouseEvent) -> Bool? {
        // When a button is held, every subsequent event for it goes to the
        // handler that took the press, wherever the cursor sits now.
        if let capture = pressedHandlers[event.button] {
            let localized = localize(
                event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY)
            _ = capture.handler(localized)
            if event.phase == .released {
                pressedHandlers[event.button] = nil
            }
            return true
        }

        guard event.phase == .released, event.button == .left else { return nil }

        // X10 legacy releases don't identify the button — the parser defaults
        // them to `.left`. If the press arrived as an SGR right/middle report
        // but its release fell back to legacy (which Terminal.app does on some
        // events), the capture for the REAL button would never clear, routing
        // every later event for that button to a stale closure from an old
        // frame. When a left release has no left capture and exactly ONE other
        // capture is in flight, treat it as that press's release. (A stray left
        // release while another button is genuinely held is far rarer than the
        // legacy fallback.)
        if pressedHandlers.count == 1, let (capturedButton, capture) = pressedHandlers.first {
            let localized = localize(
                event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY)
            _ = capture.handler(localized)
            pressedHandlers[capturedButton] = nil
            return true
        }

        // Nothing captured: this is a release whose press the frame's controls
        // never saw — it landed on the page background, or on something that
        // declined it — and the pointer has since travelled over whatever is
        // about to be handed a "click" it was never pressed for. Every control
        // that consumes a left press captures it, so the one legitimate way
        // here is a press that deliberately handed the gesture back: a
        // menu-opening press, whose release belongs to the menu now on screen.
        //
        // Left only. A right press is meant to bubble undeclined (that is how a
        // container's `.contextMenu` catches a right-click on a child), so a
        // right release routinely and correctly arrives with nothing captured —
        // hence the `.left` guard above.
        return handedOffPresses.remove(.left) == nil ? false : nil
    }

    /// Returns every region containing the given point, ordered
    /// innermost-first (last-registered first). Used by
    /// ``dispatch`` to implement wheel-event fall-through.
    private func matchingRegions(at x: Int, y: Int) -> [HitTestRegion] {
        regions.reversed().filter { $0.contains(x: x, y: y) }
    }

    /// The handler ids of every region containing the given (absolute)
    /// point, innermost-first. Drop targeting matches these against the
    /// frame's registered drop targets.
    func handlerIDs(at x: Int, y: Int) -> [HitTestRegion.HandlerID] {
        matchingRegions(at: x, y: y).map(\.handlerID)
    }

    /// The absolute top-left offset of the region registered with `id`, or
    /// `nil` when no current region carries it. Lets a drop destination
    /// translate an absolute drop point into its local space.
    func regionOffset(for id: HitTestRegion.HandlerID) -> (x: Int, y: Int)? {
        guard let region = regions.first(where: { $0.handlerID == id }) else { return nil }
        return (region.offsetX, region.offsetY)
    }

    /// The full absolute rectangle of the region registered with `id`, or `nil`
    /// when no current region carries it. Unlike ``regionOffset(for:)`` this
    /// carries the size too — the drag auto-scroll driver compares the cursor
    /// against a scrollable's *edges*, which needs its width/height, not just
    /// its top-left.
    ///
    /// The **largest** region wins, because one handler may own several. A
    /// `List` stamps an extra one-row region over its cursor row with the
    /// container's own handler id (so an enclosing `ScrollView` can find the
    /// row to reveal), and it sits ahead of the container in the array — so
    /// taking the *first* match measured the list's edges as that single row.
    /// Everything below the cursor row then read as "dragged past the bottom",
    /// which armed auto-scroll from the middle of a list whose cursor was still
    /// at its top.
    func regionRect(for id: HitTestRegion.HandlerID) -> HitTestRegion? {
        regions.filter { $0.handlerID == id }.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Processes a bare cursor-motion event by synthesising
    /// `.entered` / `.exited` transitions on the affected
    /// handlers — the hover state machine.
    ///
    /// Why route `.moved` separately:
    ///
    /// - There is no useful "the cursor moved here" semantic
    ///   that a single hit-test-based dispatch could deliver.
    ///   What views actually care about is "the cursor is now
    ///   over me" / "the cursor left me", and that requires
    ///   tracking which region the cursor was over previously.
    /// - Synthesising transitions in one place keeps the rest
    ///   of the dispatcher dumb. Modifiers like ``OnHover``
    ///   only have to react to the synthetic `.entered` /
    ///   `.exited` phases; they never deal with raw motion.
    ///
    /// Returns `true` iff at least one transition fired
    /// (either an `.entered` on a new region or an `.exited`
    /// on the previous one), so the AppRunner re-renders the
    /// view tree to reflect the new hover state. Pure motion
    /// inside the already-hovered region returns `false` —
    /// re-rendering for every cursor twitch would peg the run
    /// loop.
    private func dispatchMotion(_ event: MouseEvent) -> Bool {
        let currentRegion = matchingRegions(at: event.x, y: event.y).first
        let currentID = currentRegion?.handlerID

        guard currentID != lastHoveredHandlerID else { return false }

        var fired = false

        // Fire .exited on the previously hovered handler if it
        // is still registered. (Between event and re-render,
        // the previous frame's handlers are still in `handlers`
        // — beginRenderPass for the next frame hasn't run yet.)
        // Coordinates are localised to the region, honouring the
        // dispatcher's contract for every phase — hover handlers
        // mostly ignore them, but DraggableModifier hit-tests the
        // transition point against its content's regions to route
        // hover through to interactive children.
        if let oldID = lastHoveredHandlerID, let oldHandler = handlers[oldID] {
            let offset = regionOffset(for: oldID) ?? (0, 0)
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: event.x - offset.x, y: event.y - offset.y,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = oldHandler(exit)
            fired = true
        }

        if let newID = currentID, let newHandler = handlers[newID], let region = currentRegion {
            let enter = MouseEvent(
                button: .none, phase: .entered,
                x: event.x - region.offsetX, y: event.y - region.offsetY,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = newHandler(enter)
            fired = true
        }

        lastHoveredHandlerID = currentID
        return fired
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
            meta: event.meta,
            clickCount: event.clickCount
        )
    }

    /// Stamps a button press/release with the synthesised ``MouseEvent/clickCount``
    /// and carries the press's modifier state onto its matching release.
    ///
    /// A `.pressed` within the multi-click window of the previous press, on the
    /// same button and within one cell of it, advances the count; anything else
    /// resets it to 1. The matching `.released` carries the same count so a
    /// handler acting on release (the tap convention) sees the double-click.
    /// Motion / drag / wheel events are left at count 1.
    ///
    /// The release also inherits the modifier bits the press was reported with
    /// (unioned with its own). A click gesture's modifiers are fixed at press
    /// time, but a terminal could report the SGR modifier bits only on the
    /// press (`M`) and drop them on the release (`m`) — a handler that acts on
    /// release (List/Table selection, tap gestures) would then see a bare
    /// click and, for example, replace a multi-selection instead of toggling
    /// one row into it. Both macOS terminals byte-captured so far report
    /// symmetrically (see `Documentation/Terminal-compatibility.md`), making
    /// this a no-op there; the union stays as free defence-in-depth for
    /// unmeasured terminals.
    private func stampClickCount(_ event: MouseEvent) -> MouseEvent {
        switch event.phase {
        case .pressed:
            let now = nowNanos()
            let count: Int
            if let last = lastClick,
                last.button == event.button,
                abs(last.x - event.x) <= 1,
                abs(last.y - event.y) <= 1,
                now &- last.timeNanos <= Self.multiClickWindowNanos
            {
                count = last.count + 1
            } else {
                count = 1
            }
            lastClick = LastClick(
                button: event.button, x: event.x, y: event.y, timeNanos: now,
                count: count, shift: event.shift, ctrl: event.ctrl, meta: event.meta)
            return event.withClickCount(count)
        case .released:
            // Carry the in-flight press's count AND modifiers (if this release
            // matches it), so a terminal that drops modifier bits on the
            // release report doesn't strip the gesture's Shift/Ctrl/Option.
            // Only ONE release inherits per press: after it, the press is no
            // longer in flight, so a stray duplicate release can't pick up
            // stale modifiers from a long-finished click.
            if let last = lastClick, last.button == event.button, last.inFlight {
                lastClick?.inFlight = false
                return event.withClick(
                    count: last.count,
                    shift: event.shift || last.shift,
                    ctrl: event.ctrl || last.ctrl,
                    meta: event.meta || last.meta)
            }
            return event
        default:
            return event
        }
    }
}
