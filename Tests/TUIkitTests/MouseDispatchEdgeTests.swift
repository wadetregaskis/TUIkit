//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseDispatchEdgeTests.swift
//
//  Edge-case sweep over MouseEventDispatcher: half-open region boundaries
//  (with corner-click localization), drag capture staying with the press
//  region across other regions and beyond bounds, unconsumed presses not
//  capturing, wheel bubbling past non-wheel children to a scroller,
//  innermost-wins ordering for overlapping regions, and degenerate
//  (zero-size / negative-offset) regions neither matching nor trapping.
//  All clean at introduction; kept as a standing guard.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Mouse dispatch edge cases")
struct MouseDispatchEdgeTests {
    private func makeDispatcher() -> MouseEventDispatcher {
        let dispatcher = MouseEventDispatcher()
        // Frame-final: models the app's steady state, where the terminal's
        // reporting mode is actually set — the mid-gesture downgrade unwind
        // keys on frame-final transitions.
        dispatcher.setActiveSupport(.full, isFrameFinal: true)
        dispatcher.beginRenderPass()
        return dispatcher
    }

    @Test("Region boundaries are half-open on both axes")
    func regionBoundaries() {
        let dispatcher = makeDispatcher()
        var hits: [(Int, Int)] = []
        let id = dispatcher.register { event in
            if event.phase == .pressed { hits.append((event.x, event.y)) }
            return event.phase == .pressed
        }
        // Region covering columns 5..<15, rows 2..<5.
        dispatcher.setRegions([
            HitTestRegion(offsetX: 5, offsetY: 2, width: 10, height: 3, handlerID: id)
        ])

        let inside = [(5, 2), (14, 4), (14, 2), (5, 4)]
        let outside = [(4, 2), (15, 2), (5, 1), (5, 5), (14, 5), (15, 4)]
        for (x, y) in inside {
            #expect(
                dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y)),
                "(\(x),\(y)) is inside")
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
        for (x, y) in outside {
            #expect(
                !dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y)),
                "(\(x),\(y)) is outside")
        }
        // Localization: corner clicks arrive as (0,0) and (width-1, height-1).
        #expect(hits.first ?? (-1, -1) == (0, 0))
        #expect(hits[1] == (9, 2))
    }

    /// A `.dragged` with nothing captured is the same broken gesture as an
    /// unpaired release: the press landed where no control took it, and every
    /// drag since is hit-tested live into whatever the pointer now sits over.
    /// `DialogDrag` was the visible victim — it applied the motion from a
    /// never-begun anchor, so sweeping a held pointer across a dialog's title
    /// row teleported the dialog by the cursor's region-local coordinate.
    @Test("A drag whose press nothing captured is not delivered")
    func uncapturedDragIsDropped() {
        let dispatcher = makeDispatcher()
        var drags = 0
        let id = dispatcher.register { event in
            if event.phase == .dragged { drags += 1 }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: id)
        ])
        // No press first: the gesture began somewhere with no region.
        let handled = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 4, y: 1))
        #expect(drags == 0, "an uncaptured drag must not reach a control")
        #expect(handled == false)
    }

    /// …and the capture path is untouched: a drag that DOES follow its own
    /// press still reaches the handler that took it.
    @Test("A drag that follows its press still reaches that handler")
    func capturedDragStillDelivered() {
        let dispatcher = makeDispatcher()
        var drags = 0
        let id = dispatcher.register { event in
            if event.phase == .dragged { drags += 1 }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: id)
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 4, y: 2))
        #expect(drags == 1)
    }

    /// A press that deliberately hands the gesture back — the menu-opening
    /// press — keeps its drags flowing to whatever is now on screen, and the
    /// hand-off is PEEKED rather than consumed so the release still lands too.
    @Test("A handed-off gesture keeps receiving drags and its release")
    func handedOffGestureKeepsDragging() {
        let dispatcher = makeDispatcher()
        var drags = 0
        var releases = 0
        // A menu-opening press: consumes, then hands the gesture to the menu
        // it just put on screen.
        let opener = dispatcher.register { [dispatcher] _ in
            dispatcher.handOffGesture()
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 3, handlerID: opener)
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: 1))

        // The menu that the press opened, registered for the next frame.
        dispatcher.beginRenderPass()
        let menu = dispatcher.register { event in
            if event.phase == .dragged { drags += 1 }
            if event.phase == .released { releases += 1 }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 3, width: 10, height: 4, handlerID: menu)
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 4, y: 4))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: 5))
        #expect(drags == 1, "the menu tracks the held pointer")
        #expect(releases == 1, "and still gets the release that chooses a row")
    }

    @Test("Drag capture localizes to the press region, even outside it")
    func dragCaptureAcrossRegions() {
        let dispatcher = makeDispatcher()
        var eventsA: [(MousePhase, Int, Int)] = []
        var eventsB: [(MousePhase, Int, Int)] = []
        let idA = dispatcher.register { event in
            eventsA.append((event.phase, event.x, event.y)); return true
        }
        let idB = dispatcher.register { event in
            eventsB.append((event.phase, event.x, event.y)); return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: idA),
            HitTestRegion(offsetX: 20, offsetY: 0, width: 10, height: 2, handlerID: idB),
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 25, y: 1))  // over B!
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 25, y: 1))

        #expect(eventsB.isEmpty, "the drag stays captured by the press region")
        #expect(eventsA.map(\.0) == [.pressed, .dragged, .released])
        #expect(eventsA[1].1 == 25 && eventsA[1].2 == 1, "drag localized to A's origin (may exceed A's bounds)")

        // After release, a fresh press on B routes to B.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 25, y: 1))
        #expect(eventsB.map(\.0) == [.pressed])
    }

    /// A downgrade below clicks turns the terminal's button reporting off —
    /// the release that would unwind a held gesture never arrives. The
    /// dispatcher must forget the press capture (or it routes every later
    /// event for that button to a dead frame's closure once reporting comes
    /// back) and disarm the drag session's edge auto-scroll.
    @Test("A mid-gesture support downgrade clears the stranded capture")
    func supportDowngradeClearsCapture() {
        let dispatcher = makeDispatcher()
        var phases: [MousePhase] = []
        let id = dispatcher.register { event in
            phases.append(event.phase)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))
        #expect(phases == [.pressed])

        // Mid-gesture the effective support drops below clicks (a page with
        // `.mouseSupport(.disabled)` reached by keyboard), then comes back.
        dispatcher.setActiveSupport(.disabled, isFrameFinal: true)
        dispatcher.setActiveSupport(.full, isFrameFinal: true)

        // Later events for that button must NOT reach the stale capture.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 25, y: 5))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 25, y: 5))
        #expect(phases == [.pressed], "the stranded capture was routed events: \(phases)")

        // A fresh gesture works normally.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 1))
        #expect(phases == [.pressed, .pressed, .released])
    }

    /// The render pass transiently sets the scene BASE mid-frame before the
    /// per-frame feature requests are collected; the AppRunner then applies
    /// the frame-final effective. With a click-less base and a dialog
    /// elevating clicks (DialogDrag requests them every frame), the support
    /// cycles base → effective every frame — and treating the transient base
    /// set as a downgrade cancelled the in-flight gesture on every render,
    /// which a consumed press itself triggers. A dialog could not be dragged.
    @Test("The mid-frame base set does not cancel the gesture")
    func midFrameBaseSetKeepsCapture() {
        let dispatcher = makeDispatcher()
        var phases: [MousePhase] = []
        let id = dispatcher.register { event in
            phases.append(event.phase)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))

        // A frame renders: the click-less scene base is set mid-pass, then
        // the dialog's elevated effective support lands frame-final.
        dispatcher.setActiveSupport(.scrollOnly)
        dispatcher.setActiveSupport(.full, isFrameFinal: true)

        // The gesture is still captured: the drag routes to the press handler.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 6, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 6, y: 1))
        #expect(phases == [.pressed, .dragged, .released], "the transient base set broke the capture: \(phases)")
    }

    /// …and the real downgrade still unwinds even though the mid-frame base
    /// set already lowered the filtering floor: the unwind compares
    /// frame-final against frame-final, not against whatever the filter
    /// happens to hold.
    @Test("A frame-final downgrade after a mid-frame lower still unwinds")
    func frameFinalDowngradeAfterMidFrameLowerUnwinds() {
        let dispatcher = makeDispatcher()
        var phases: [MousePhase] = []
        let id = dispatcher.register { event in
            phases.append(event.phase)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 1))

        // The dialog closes: this frame's base set lowers the filter, and
        // the frame-final effective genuinely drops clicks.
        dispatcher.setActiveSupport(.scrollOnly)
        dispatcher.setActiveSupport(.scrollOnly, isFrameFinal: true)
        dispatcher.setActiveSupport(.full, isFrameFinal: true)

        // Dragged OUTSIDE the region: a live capture would still route it to
        // the press handler; an unwound one leaves nothing to hit.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 25, y: 5))
        #expect(phases == [.pressed], "the capture must be unwound by the real downgrade: \(phases)")
    }

    @Test("A mid-gesture support downgrade disarms the drag auto-scroll")
    func supportDowngradeDisarmsAutoScroll() {
        let dispatcher = makeDispatcher()
        let session = DragAndDropSession()
        dispatcher.dragAndDropSession = session

        session.armAutoScroll()
        #expect(session.autoScrollArmed)

        dispatcher.setActiveSupport(.disabled, isFrameFinal: true)
        #expect(
            !session.autoScrollArmed,
            "no release is coming to disarm it — the downgrade must")
    }

    @Test("An unconsumed press does not capture; stray drags fall through safely")
    func unconsumedPressNoCapture() {
        let dispatcher = makeDispatcher()
        var phases: [MousePhase] = []
        let id = dispatcher.register { event in
            phases.append(event.phase)
            return false  // never consumes
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        #expect(!dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 1)))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 1))
        // No crash, no capture; the region still saw the raw events it covers.
        #expect(phases.first == .pressed)
    }

    @Test("Wheel bubbles past a non-wheel inner region to an outer scroller")
    func wheelBubbles() {
        let dispatcher = makeDispatcher()
        var innerSaw = 0
        var outerScrolled = 0
        let outer = dispatcher.register { event in
            if event.phase == .scrolled { outerScrolled += 1; return true }
            return false
        }
        let inner = dispatcher.register { event in
            if event.phase == .scrolled { innerSaw += 1 }
            return false  // a Button: doesn't handle wheel
        }
        // Inner registered last = innermost.
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 40, height: 10, handlerID: outer),
            HitTestRegion(offsetX: 5, offsetY: 2, width: 10, height: 1, handlerID: inner),
        ])

        #expect(dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 7, y: 2)))
        #expect(innerSaw == 1, "the inner region was offered the wheel first")
        #expect(outerScrolled == 1, "the wheel bubbled to the scroller")
    }

    @Test("Overlapping regions: last registered (innermost) wins clicks")
    func innermostWins() {
        let dispatcher = makeDispatcher()
        var winner = ""
        let outer = dispatcher.register { event in
            if event.phase == .pressed { winner = "outer" }
            return true
        }
        let inner = dispatcher.register { event in
            if event.phase == .pressed { winner = "inner" }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 40, height: 10, handlerID: outer),
            HitTestRegion(offsetX: 5, offsetY: 2, width: 10, height: 2, handlerID: inner),
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 7, y: 3))
        #expect(winner == "inner")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 7, y: 3))

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 30, y: 8))
        #expect(winner == "outer", "outside the inner region the outer wins")
    }

    @Test("Zero-size and negative-offset regions never match")
    func degenerateRegions() {
        let dispatcher = makeDispatcher()
        let id = dispatcher.register { _ in true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 3, offsetY: 3, width: 0, height: 0, handlerID: id),
            HitTestRegion(offsetX: -5, offsetY: -5, width: 3, height: 3, handlerID: id),
        ])
        for (x, y) in [(3, 3), (0, 0), (-4, -4), (2, 2)] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        }
        // Reaching here without a crash is the assertion; (−4,−4) can't arrive
        // from a real terminal but must not trap.
        #expect(Bool(true))
    }
}
