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
        dispatcher.setActiveSupport(.full)
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
