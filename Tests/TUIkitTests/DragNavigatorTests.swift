//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragNavigatorTests.swift
//
//  The navigators pressed while something is in hand. They must move the view
//  under the POINTER — which during a carry is usually not the focused one —
//  and they must decline whenever there is nothing being carried, or nothing
//  under the cursor the carry could land in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("mid-drag navigators")
struct DragNavigatorTests {
    /// A session wired to a dispatcher it owns (the session's is `weak`), with
    /// two side-by-side scrollables — the drag's source and somewhere else.
    private final class Harness {
        let dispatcher = MouseEventDispatcher()
        let session = DragAndDropSession()
        let source = ScrollViewHandler(focusID: "source")
        let other = ScrollViewHandler(focusID: "other")
        static let sourceID = HitTestRegion.HandlerID(1)
        static let otherID = HitTestRegion.HandlerID(2)

        init(otherAccepts: Bool = true) {
            session.dispatcher = dispatcher
            for handler in [source, other] {
                handler.viewportHeight = 10
                handler.contentHeight = 100
            }
            dispatcher.setRegions([
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: 20, height: 10, handlerID: Self.sourceID),
                HitTestRegion(
                    offsetX: 30, offsetY: 0, width: 20, height: 10, handlerID: Self.otherID),
            ])
            addZone(Self.sourceID, source, shiftStep: 5)
            addZone(Self.otherID, other, shiftStep: 7)
            // The source is the gesture's own scrollable; the other qualifies
            // only if a destination there accepts the payload.
            session.registerTarget(
                DragAndDropSession.Target(
                    handlerID: Self.sourceID, accepts: { _ in true },
                    perform: { _, _ in true }, setTargeted: { _ in }))
            if otherAccepts {
                session.registerTarget(
                    DragAndDropSession.Target(
                        handlerID: Self.otherID, accepts: { _ in true },
                        perform: { _, _ in true }, setTargeted: { _ in }))
            }
        }

        private func addZone(
            _ id: HitTestRegion.HandlerID, _ vertical: any ScrollableOffsetState, shiftStep: Int
        ) {
            session.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: id, vertical: vertical, horizontal: nil, delayNanos: 0,
                    shiftStep: shiftStep))
        }

        /// Picks a payload up in the source and moves the pointer to `(x, y)`.
        func dragTo(x: Int, y: Int) {
            session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 5, y: 5)
            session.begin(payload: "x", preview: FrameBuffer(text: "x"))
            session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: x, y: y)
        }

        @discardableResult
        func press(_ key: Key, shift: Bool = false) -> Bool {
            session.handleDragNavigator(KeyEvent(key: key, shift: shift))
        }
    }

    @Test("Down scrolls the view under the pointer, not the one the drag came from")
    func scrollsTheTargetedView() {
        let harness = Harness()
        harness.dragTo(x: 35, y: 5)
        #expect(harness.press(.down))
        #expect(harness.other.scrollOffset == 1)
        #expect(harness.source.scrollOffset == 0)
    }

    @Test("Back over the source, the source is what moves")
    func scrollsTheSourceWhenOverIt() {
        let harness = Harness()
        harness.dragTo(x: 5, y: 5)
        #expect(harness.press(.down))
        #expect(harness.source.scrollOffset == 1)
        #expect(harness.other.scrollOffset == 0)
    }

    @Test("Shift accelerates by the targeted view's OWN configured step")
    func shiftUsesTheTargetsStep() {
        let harness = Harness()
        harness.dragTo(x: 35, y: 5)
        harness.press(.down, shift: true)
        #expect(harness.other.scrollOffset == 7)
    }

    @Test("End goes to the bottom of the targeted view")
    func endJumpsToTheTargetsBottom() {
        let harness = Harness()
        harness.dragTo(x: 35, y: 5)
        harness.press(.end)
        #expect(harness.other.scrollOffset == harness.other.maxOffset)
        #expect(harness.source.scrollOffset == 0)
    }

    @Test("With nothing in hand the keys are not claimed")
    func declinesWithNoDrag() {
        let harness = Harness()
        harness.session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 35, y: 5)
        #expect(!harness.press(.down))
        #expect(harness.other.scrollOffset == 0)
    }

    @Test("A view this drag could not land in is not scrolled under it")
    func declinesOverARefusingView() {
        let harness = Harness(otherAccepts: false)
        harness.dragTo(x: 35, y: 5)
        #expect(!harness.press(.down))
        #expect(harness.other.scrollOffset == 0)
        #expect(harness.source.scrollOffset == 0)
    }

    @Test("Keys that are not navigators fall through")
    func declinesOtherKeys() {
        let harness = Harness()
        harness.dragTo(x: 35, y: 5)
        #expect(!harness.press(.escape))
        #expect(!harness.press(.tab))
    }
}
