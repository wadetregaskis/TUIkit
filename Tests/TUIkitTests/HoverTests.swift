//  🖥️ TUIKit — Terminal UI Kit for Swift
//  HoverTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Dispatcher hover state machine

@MainActor
@Suite("Dispatcher hover transitions")
struct DispatcherHoverTransitionTests {

    @Test("Entering a region fires .entered on its handler")
    func enteringRegionFiresEntered() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var sawEnter = false
        let id = dispatcher.register { event in
            if event.phase == .entered { sawEnter = true }
            return event.phase == .entered
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 3))

        #expect(sawEnter)
    }

    @Test("Leaving a region fires .exited on its handler")
    func leavingRegionFiresExited() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var enters = 0
        var exits = 0
        let id = dispatcher.register { event in
            switch event.phase {
            case .entered: enters += 1; return true
            case .exited: exits += 1; return true
            default: return false
            }
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 3))
        // Move within the region — no new transition
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 5, y: 5))
        // Move outside the region — fires exit
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 50, y: 50))

        #expect(enters == 1)
        #expect(exits == 1)
    }

    @Test("Crossing between two regions fires exit + enter pair")
    func crossingFiresExitThenEnter() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var transcript: [(handlerLabel: String, phase: MousePhase)] = []
        let a = dispatcher.register { event in
            if event.phase == .entered || event.phase == .exited {
                transcript.append(("A", event.phase))
                return true
            }
            return false
        }
        let b = dispatcher.register { event in
            if event.phase == .entered || event.phase == .exited {
                transcript.append(("B", event.phase))
                return true
            }
            return false
        }
        // Two non-overlapping regions
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: a),
            HitTestRegion(offsetX: 20, offsetY: 0, width: 10, height: 10, handlerID: b),
        ])

        // Cursor enters A
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 3))
        // Cursor crosses to B (passes off A first via the off-screen path)
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 25, y: 5))

        #expect(transcript.count == 3, "expected enter-A, exit-A, enter-B; got \(transcript)")
        #expect(transcript[0].handlerLabel == "A" && transcript[0].phase == .entered)
        #expect(transcript[1].handlerLabel == "A" && transcript[1].phase == .exited)
        #expect(transcript[2].handlerLabel == "B" && transcript[2].phase == .entered)
    }

    @Test("Motion inside the already-hovered region does not re-fire")
    func motionInsideAlreadyHoveredDoesNotRefire() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var enters = 0
        let id = dispatcher.register { event in
            if event.phase == .entered { enters += 1 }
            return event.phase == .entered
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: id)
        ])

        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 3))
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 4, y: 3))
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 5, y: 3))

        #expect(enters == 1, "should fire exactly one .entered for the whole sequence")
    }

    @Test("Motion outside any region does not fire transitions")
    func motionOutsideAnyRegionDoesNothing() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var anyCall = false
        let id = dispatcher.register { _ in anyCall = true; return false }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: id)
        ])

        let consumed = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 50, y: 50))

        #expect(!consumed)
        #expect(!anyCall)
    }

    @Test("Dispatch returns true when a transition fires, false otherwise")
    func dispatchReturnValueReflectsTransition() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        let id = dispatcher.register { _ in true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: id)
        ])

        // Enter → transition → true (forces a re-render)
        #expect(dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 3, y: 3)))
        // Stay → no transition → false (no re-render needed)
        #expect(!dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 4, y: 4)))
        // Leave → transition → true
        #expect(dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 50, y: 50)))
    }
}
